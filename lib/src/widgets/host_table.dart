/// The host table: a fixed column grid shared by the header and every row,
/// ported from `HostTableHeader` / `HostTableRow` in `PingInfoView.swift`.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../theme.dart';
import '../view_model.dart';

/// Column geometry, copied verbatim from the `Col` enum in the Swift source.
class Col {
  static const double dot = 26;
  static const double host = 185;
  static const double ip = 138;
  static const double status = 76;
  static const double latency = 88;
  static const double success = 70;
  static const double failed = 62;
  static const double rate = 64;
  static const double hPad = 14;
  static const double rowH = 32;
  static const double headerH = 26;
}

class HostTable extends StatefulWidget {
  const HostTable({super.key, required this.hosts, required this.vm});

  final List<PingHost> hosts;
  final PingViewModel vm;

  @override
  State<HostTable> createState() => _HostTableState();
}

class _HostTableState extends State<HostTable> {
  @override
  Widget build(BuildContext context) {
    final Palette p = context.palette;

    return ColoredBox(
      color: p.content,
      child: Column(
        children: <Widget>[
          const _TableHeader(),
          Expanded(
            child: widget.hosts.isEmpty
                ? const _EmptyState()
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: widget.hosts.length,
                    itemExtent: Col.rowH,
                    itemBuilder: (BuildContext context, int index) {
                      final host = widget.hosts[index];
                      return _HostRow(
                        key: ValueKey<String>(host.id),
                        host: host,
                        isSelected: widget.vm.selectedIDs.contains(host.id),
                        isEven: index.isEven,
                        onTap: () => _select(host),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _select(PingHost host) {
    final keys = HardwareKeyboard.instance;
    if (keys.isShiftPressed) {
      widget.vm.selectRange(host);
    } else if (keys.isControlPressed) {
      widget.vm.toggleSelect(host);
    } else {
      widget.vm.selectSingle(host);
    }
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader();

  @override
  Widget build(BuildContext context) {
    final Palette p = context.palette;
    Widget h(String label, double width, Alignment align) => SizedBox(
      width: width,
      child: Align(
        alignment: align,
        child: Text(
          label.toUpperCase(),
          maxLines: 1,
          style: AppText.columnHeader.copyWith(color: p.secondary),
        ),
      ),
    );

    // `controlBackgroundColor`, like the rows: the macOS header is part of the
    // table surface, not a separate bar.
    return Container(
      height: Col.headerH,
      decoration: BoxDecoration(
        color: p.content,
        border: Border(bottom: BorderSide(color: p.separator, width: 1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: Col.hPad),
      child: Row(
        children: <Widget>[
          const SizedBox(width: Col.dot),
          h('Host', Col.host, Alignment.centerLeft),
          h('Resolved IP', Col.ip, Alignment.centerLeft),
          h('Status', Col.status, Alignment.centerLeft),
          h('Latency', Col.latency, Alignment.centerRight),
          h('Success', Col.success, Alignment.centerRight),
          h('Failed', Col.failed, Alignment.centerRight),
          h('Rate', Col.rate, Alignment.centerRight),
          const Spacer(),
        ],
      ),
    );
  }
}

class _HostRow extends StatefulWidget {
  const _HostRow({
    super.key,
    required this.host,
    required this.isSelected,
    required this.isEven,
    required this.onTap,
  });

  final PingHost host;
  final bool isSelected;
  final bool isEven;
  final VoidCallback onTap;

  @override
  State<_HostRow> createState() => _HostRowState();
}

/// Hover lives in the row itself: tracking it as an index on the table
/// rebuilt every row on each mouse move, and left a stale highlight on
/// whichever host slid into that index after a removal.
class _HostRowState extends State<_HostRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final Palette p = context.palette;
    final host = widget.host;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: host,
          builder: (BuildContext context, Widget? _) {
            // Alternating bands, as `alternatingContentBackgroundColors`.
            Color background = widget.isEven ? p.content : p.altRow;
            if (widget.isSelected) {
              background = Color.alphaBlend(p.selection, background);
            } else if (_hover) {
              background = Color.alphaBlend(p.hover, background);
            }

            return Container(
              height: Col.rowH,
              decoration: BoxDecoration(
                color: background,
                border: Border(
                  bottom: BorderSide(
                    // `Divider().opacity(0.4)`: 40% *of* the separator.
                    // withValues(alpha: 0.4) set it to 40% white outright,
                    // which drew a bright rule under every row.
                    color: p.separator.withValues(alpha: p.separator.a * 0.4),
                    width: 1,
                  ),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: Col.hPad),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: Col.dot,
                    child: Center(child: StatusDot(status: host.status)),
                  ),
                  SizedBox(
                    width: Col.host,
                    child: Text(
                      host.address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.mono.copyWith(color: p.text),
                    ),
                  ),
                  SizedBox(
                    width: Col.ip,
                    child: Text(
                      host.resolvedText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.monoSmall.copyWith(color: p.secondary),
                    ),
                  ),
                  SizedBox(
                    width: Col.status,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _StatusBadge(status: host.status),
                    ),
                  ),
                  SizedBox(
                    width: Col.latency,
                    child: Text(
                      host.latencyText,
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      style: AppText.monoSmall.copyWith(
                        color: host.latency == null
                            ? p.tertiary
                            : p.latencyColor(host.latency!),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: Col.success,
                    child: Text(
                      '${host.successCount}',
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      style: AppText.monoDigits.copyWith(color: p.green),
                    ),
                  ),
                  SizedBox(
                    width: Col.failed,
                    child: Text(
                      '${host.failCount}',
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      style: AppText.monoDigits.copyWith(
                        color: host.failCount > 0 ? p.red : p.secondary,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: Col.rate,
                    child: Text(
                      host.rateText,
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      style: AppText.monoDigits.copyWith(
                        color: host.successCount + host.failCount == 0
                            ? p.tertiary
                            : p.rateColor(host.successRate),
                      ),
                    ),
                  ),
                  const Spacer(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final PingStatus status;

  @override
  Widget build(BuildContext context) {
    final Palette p = context.palette;
    final Color color = p.statusColor(_statusColor(status));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.label,
        style: AppText.captionStrong.copyWith(color: color),
      ),
    );
  }
}

PingStatusColor _statusColor(PingStatus status) => switch (status) {
  PingStatus.idle => PingStatusColor.idle,
  PingStatus.running => PingStatusColor.running,
  PingStatus.success => PingStatusColor.success,
  PingStatus.failed => PingStatusColor.failed,
};

/// The 9 px status dot. While running it grows a soft pulsing ring, matching
/// the `repeatForever` animation on the Swift `StatusDot`.
class StatusDot extends StatefulWidget {
  const StatusDot({super.key, required this.status, this.size = 9});

  final PingStatus status;
  final double size;

  @override
  State<StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<StatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(StatusDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.status == PingStatus.running) {
      if (!_controller.isAnimating) _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Palette p = context.palette;
    final Color color = p.statusColor(_statusColor(widget.status));
    final double ring = widget.size * 1.8;

    return SizedBox(
      width: 18,
      height: 18,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          if (widget.status == PingStatus.running)
            AnimatedBuilder(
              animation: _controller,
              builder: (BuildContext context, Widget? _) {
                final double t = Curves.easeInOut.transform(_controller.value);
                final double d = ring * (0.5 + 0.5 * t);
                return Container(
                  width: d,
                  height: d,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.28),
                    shape: BoxShape.circle,
                  ),
                );
              },
            ),
          Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: widget.status == PingStatus.idle
                  ? null
                  : <BoxShadow>[
                      BoxShadow(
                        color: color.withValues(alpha: 0.5),
                        blurRadius: 3,
                      ),
                    ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final Palette p = context.palette;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // The macOS `SheepOutline` template image, tinted `.tertiary`.
            Image.asset(
              'assets/images/sheep_outline.png',
              width: 72,
              height: 64,
              fit: BoxFit.contain,
              color: p.tertiary,
              colorBlendMode: BlendMode.srcIn,
              filterQuality: FilterQuality.medium,
              excludeFromSemantics: true,
            ),
            const SizedBox(height: 14),
            Text('No Hosts', style: AppText.title2.copyWith(color: p.text)),
            const SizedBox(height: 6),
            Text(
              'Tap  +  in the toolbar to add an IP address or hostname.',
              textAlign: TextAlign.center,
              style: AppText.callout.copyWith(color: p.secondary),
            ),
          ],
        ),
      ),
    );
  }
}
