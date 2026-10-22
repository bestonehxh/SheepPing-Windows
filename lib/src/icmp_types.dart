/// Shared between the ICMP engine (`icmp.dart`) and its web stub.
library;

/// Raw outcome of one echo request.
class IcmpOutcome {
  const IcmpOutcome({required this.status, this.from, this.rttMs, this.ttl});

  /// `IP_STATUS`: 0 is a reply, everything else is the failure reason.
  final int status;

  /// The address that answered (the target, or a router reporting an error).
  final String? from;
  final int? rttMs;

  /// IPv4 only: IPv6 echo replies carry no hop limit through this API.
  final int? ttl;
}

const int ipSuccess = 0;
const int ipReqTimedOut = 11010;
const int ipGeneralFailure = 11050;

/// Payload size, matching ping.exe's default.
const int echoDataSize = 32;
