/// ICMP echo through the Windows ICMP API (`iphlpapi!IcmpSendEcho2` /
/// `Icmp6SendEcho2`), asynchronously and without spawning a process.
///
/// This replaces running `ping.exe -n 1` per tick, which cost a process launch
/// per host per interval (the Windows twin of the fork-per-tick the macOS build
/// moved away from), and whose output is translated into the Windows display
/// language — so the app's log would turn Thai on a Thai system. Here every
/// verdict is a numeric `IP_STATUS`, and the text is written by the app.
///
/// Each request gets its own event; one 10 ms poller checks the events of all
/// requests in flight, so the UI isolate never blocks. The round-trip time
/// comes from the kernel, so the polling cadence does not affect it.
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'icmp_types.dart';

// --- iphlpapi -------------------------------------------------------------

typedef _IcmpCreateFileC = IntPtr Function();
typedef _IcmpCreateFileD = int Function();

typedef _IcmpSendEcho2C =
    Uint32 Function(
      IntPtr handle,
      IntPtr event,
      Pointer<Void> apcRoutine,
      Pointer<Void> apcContext,
      Uint32 destination,
      Pointer<Uint8> requestData,
      Uint16 requestSize,
      Pointer<Void> requestOptions,
      Pointer<Uint8> replyBuffer,
      Uint32 replySize,
      Uint32 timeout,
    );
typedef _IcmpSendEcho2D =
    int Function(
      int,
      int,
      Pointer<Void>,
      Pointer<Void>,
      int,
      Pointer<Uint8>,
      int,
      Pointer<Void>,
      Pointer<Uint8>,
      int,
      int,
    );

typedef _Icmp6SendEcho2C =
    Uint32 Function(
      IntPtr handle,
      IntPtr event,
      Pointer<Void> apcRoutine,
      Pointer<Void> apcContext,
      Pointer<Uint8> sourceAddress,
      Pointer<Uint8> destinationAddress,
      Pointer<Uint8> requestData,
      Uint16 requestSize,
      Pointer<Void> requestOptions,
      Pointer<Uint8> replyBuffer,
      Uint32 replySize,
      Uint32 timeout,
    );
typedef _Icmp6SendEcho2D =
    int Function(
      int,
      int,
      Pointer<Void>,
      Pointer<Void>,
      Pointer<Uint8>,
      Pointer<Uint8>,
      Pointer<Uint8>,
      int,
      Pointer<Void>,
      Pointer<Uint8>,
      int,
      int,
    );

typedef _ParseRepliesC = Uint32 Function(Pointer<Uint8>, Uint32);
typedef _ParseRepliesD = int Function(Pointer<Uint8>, int);

// --- kernel32 -------------------------------------------------------------

typedef _CreateEventWC =
    IntPtr Function(Pointer<Void>, Int32, Int32, Pointer<Utf16>);
typedef _CreateEventWD = int Function(Pointer<Void>, int, int, Pointer<Utf16>);

typedef _WaitForSingleObjectC = Uint32 Function(IntPtr, Uint32);
typedef _WaitForSingleObjectD = int Function(int, int);

typedef _CloseHandleC = Int32 Function(IntPtr);
typedef _CloseHandleD = int Function(int);

typedef _GetLastErrorC = Uint32 Function();
typedef _GetLastErrorD = int Function();

const int _waitObject0 = 0;
const int _invalidHandle = -1;
const int _afInet6 = 23;

// Reply layouts (x64). ICMP_ECHO_REPLY: Address@0, Status@4,
// RoundTripTime@8, ..., Options.Ttl@24. ICMPV6_ECHO_REPLY: a packed
// IPV6_ADDRESS_EX (port@0, flowinfo@2, addr[16]@6, scope@22) then
// Status@28 and RoundTripTime@32.
const int _v4Status = 4;
const int _v4Rtt = 8;
const int _v4Ttl = 24;
const int _v6Addr = 6;
const int _v6Status = 28;
const int _v6Rtt = 32;

/// ICMP_ECHO_REPLY + data + 8 + IO_STATUS_BLOCK, with plenty to spare.
const int _replySize = 512;

class _Api {
  _Api() {
    final iphlpapi = DynamicLibrary.open('iphlpapi.dll');
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    icmpCreateFile = iphlpapi
        .lookupFunction<_IcmpCreateFileC, _IcmpCreateFileD>('IcmpCreateFile');
    icmp6CreateFile = iphlpapi
        .lookupFunction<_IcmpCreateFileC, _IcmpCreateFileD>('Icmp6CreateFile');
    // Leaf calls: nothing runs on this thread between them and the
    // GetLastError that follows, so the error code survives.
    icmpSendEcho2 = iphlpapi.lookupFunction<_IcmpSendEcho2C, _IcmpSendEcho2D>(
      'IcmpSendEcho2',
      isLeaf: true,
    );
    icmp6SendEcho2 = iphlpapi
        .lookupFunction<_Icmp6SendEcho2C, _Icmp6SendEcho2D>(
          'Icmp6SendEcho2',
          isLeaf: true,
        );
    icmpParseReplies = iphlpapi.lookupFunction<_ParseRepliesC, _ParseRepliesD>(
      'IcmpParseReplies',
      isLeaf: true,
    );
    icmp6ParseReplies = iphlpapi.lookupFunction<_ParseRepliesC, _ParseRepliesD>(
      'Icmp6ParseReplies',
      isLeaf: true,
    );
    createEvent = kernel32.lookupFunction<_CreateEventWC, _CreateEventWD>(
      'CreateEventW',
    );
    waitForSingleObject = kernel32
        .lookupFunction<_WaitForSingleObjectC, _WaitForSingleObjectD>(
          'WaitForSingleObject',
          isLeaf: true,
        );
    closeHandle = kernel32.lookupFunction<_CloseHandleC, _CloseHandleD>(
      'CloseHandle',
    );
    getLastError = kernel32.lookupFunction<_GetLastErrorC, _GetLastErrorD>(
      'GetLastError',
      isLeaf: true,
    );
  }

  late final _IcmpCreateFileD icmpCreateFile;
  late final _IcmpCreateFileD icmp6CreateFile;
  late final _IcmpSendEcho2D icmpSendEcho2;
  late final _Icmp6SendEcho2D icmp6SendEcho2;
  late final _ParseRepliesD icmpParseReplies;
  late final _ParseRepliesD icmp6ParseReplies;
  late final _CreateEventWD createEvent;
  late final _WaitForSingleObjectD waitForSingleObject;
  late final _CloseHandleD closeHandle;
  late final _GetLastErrorD getLastError;

  /// One handle per family for the life of the process; overlapped requests
  /// on a shared handle are independent of each other.
  late final int v4Handle = icmpCreateFile();
  late final int v6Handle = icmp6CreateFile();
}

final _Api _api = _Api();

class _Request {
  _Request({
    required this.isV6,
    required this.event,
    required this.reply,
    required this.allocations,
    required this.deadlineMs,
  });

  final bool isV6;
  final int event;
  final Pointer<Uint8> reply;
  final List<Pointer<NativeType>> allocations;
  final int deadlineMs;
  final Completer<IcmpOutcome> completer = Completer<IcmpOutcome>();

  void release() {
    _api.closeHandle(event);
    for (final p in allocations) {
      calloc.free(p);
    }
  }
}

final Stopwatch _clock = Stopwatch()..start();
final List<_Request> _inFlight = <_Request>[];
Timer? _poller;

/// Grace past the request's own timeout before the poller reports it lost.
/// The driver always completes a request by its timeout, so this only guards
/// against an event that never fires.
const int _graceMs = 5000;

/// After this much longer, a request whose event never fired is dropped and
/// its buffers freed: nothing can still be writing to them by then.
const int _abandonMs = 60000;

bool _isIpStatus(int code) => code >= 11000 && code < 11100;

/// Sends one echo request to [target] and completes with its outcome.
///
/// [scopeId] is the IPv6 zone index ("fe80::1%12"); ignored for IPv4.
Future<IcmpOutcome> icmpEcho(
  InternetAddress target, {
  required Duration timeout,
  int scopeId = 0,
}) {
  final bool isV6 = target.type == InternetAddressType.IPv6;
  final int handle = isV6 ? _api.v6Handle : _api.v4Handle;
  if (handle == 0 || handle == _invalidHandle) {
    return Future<IcmpOutcome>.value(
      const IcmpOutcome(status: ipGeneralFailure),
    );
  }

  final int event = _api.createEvent(nullptr, 1, 0, nullptr);
  if (event == 0) {
    return Future<IcmpOutcome>.value(
      const IcmpOutcome(status: ipGeneralFailure),
    );
  }

  final data = calloc<Uint8>(echoDataSize);
  // ping.exe's payload: "abcdefghijklmnopqrstuvwabcdefghi".
  for (var i = 0; i < echoDataSize; i++) {
    data[i] = 0x61 + (i % 23);
  }
  final reply = calloc<Uint8>(_replySize);
  final allocations = <Pointer<NativeType>>[data, reply];
  final int timeoutMs = timeout.inMilliseconds.clamp(1, 600000);
  final Uint8List raw = target.rawAddress;

  int result;
  if (isV6) {
    // Two sockaddr_in6: the unspecified source, then the destination.
    final src = calloc<Uint8>(28);
    final dst = calloc<Uint8>(28);
    allocations.addAll(<Pointer<NativeType>>[src, dst]);
    src.cast<Uint16>()[0] = _afInet6;
    dst.cast<Uint16>()[0] = _afInet6;
    for (var i = 0; i < 16; i++) {
      dst[8 + i] = raw[i];
    }
    (dst + 24).cast<Uint32>().value = scopeId;
    result = _api.icmp6SendEcho2(
      handle,
      event,
      nullptr,
      nullptr,
      src,
      dst,
      data,
      echoDataSize,
      nullptr,
      reply,
      _replySize,
      timeoutMs,
    );
  } else {
    // IPAddr is in network byte order: the address bytes as they read.
    final int destination =
        raw[0] | (raw[1] << 8) | (raw[2] << 16) | (raw[3] << 24);
    result = _api.icmpSendEcho2(
      handle,
      event,
      nullptr,
      nullptr,
      destination,
      data,
      echoDataSize,
      nullptr,
      reply,
      _replySize,
      timeoutMs,
    );
  }
  final int error = result == 0 ? _api.getLastError() : 0;

  final request = _Request(
    isV6: isV6,
    event: event,
    reply: reply,
    allocations: allocations,
    deadlineMs: _clock.elapsedMilliseconds + timeoutMs + _graceMs,
  );

  // GetLastError is not dependable here: the Dart VM may overwrite it between
  // two FFI calls, and under load it read 0 for requests that were in fact
  // pending. So only a real IP_STATUS code counts as an up-front refusal (bad
  // destination, no route); anything else waits on the event, which the
  // driver signals for every request it accepted.
  if (result == 0 && _isIpStatus(error)) {
    request.release();
    return Future<IcmpOutcome>.value(IcmpOutcome(status: error));
  }

  if (result != 0) {
    // Already answered (the API returns the reply count when it completes
    // synchronously), so there is nothing to wait for.
    final outcome = _parse(request);
    request.release();
    return Future<IcmpOutcome>.value(outcome);
  }

  _inFlight.add(request);
  _poller ??= Timer.periodic(const Duration(milliseconds: 10), (_) => _poll());
  return request.completer.future;
}

void _poll() {
  final int now = _clock.elapsedMilliseconds;
  _inFlight.removeWhere((request) {
    if (_api.waitForSingleObject(request.event, 0) == _waitObject0) {
      if (!request.completer.isCompleted) {
        request.completer.complete(_parse(request));
      }
      request.release();
      return true;
    }
    if (now > request.deadlineMs && !request.completer.isCompleted) {
      // Report the loss, but keep the buffers until the event fires: the
      // driver may still write into them.
      request.completer.complete(const IcmpOutcome(status: ipReqTimedOut));
    }
    if (now > request.deadlineMs + _abandonMs) {
      request.release();
      return true;
    }
    return false;
  });
  if (_inFlight.isEmpty) {
    _poller?.cancel();
    _poller = null;
  }
}

IcmpOutcome _parse(_Request request) {
  final reply = request.reply;
  final int count = request.isV6
      ? _api.icmp6ParseReplies(reply, _replySize)
      : _api.icmpParseReplies(reply, _replySize);
  final int lastError = count == 0 ? _api.getLastError() : 0;
  final ByteData view = ByteData.sublistView(reply.asTypedList(_replySize));

  final int structStatus = view.getUint32(
    request.isV6 ? _v6Status : _v4Status,
    Endian.little,
  );
  int status = structStatus;
  if (count == 0) {
    // No reply: the reason is in GetLastError, or else in the struct.
    status = _isIpStatus(lastError) ? lastError : status;
    if (status == ipSuccess) status = ipReqTimedOut;
  }

  String? from;
  if (request.isV6) {
    final bytes = Uint8List.fromList(
      reply.asTypedList(_replySize).sublist(_v6Addr, _v6Addr + 16),
    );
    if (bytes.any((b) => b != 0)) {
      from = InternetAddress.fromRawAddress(bytes).address;
    }
  } else {
    final bytes = Uint8List.fromList(reply.asTypedList(4));
    if (bytes.any((b) => b != 0)) {
      from = InternetAddress.fromRawAddress(bytes).address;
    }
  }

  if (status != ipSuccess) return IcmpOutcome(status: status, from: from);
  return IcmpOutcome(
    status: ipSuccess,
    from: from,
    rttMs: view.getUint32(request.isV6 ? _v6Rtt : _v4Rtt, Endian.little),
    ttl: request.isV6 ? null : view.getUint8(_v4Ttl),
  );
}
