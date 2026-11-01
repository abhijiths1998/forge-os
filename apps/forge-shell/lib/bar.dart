// The top bar: a slim glass strip floating over the top edge.
//   left    the Forge emblem (opens the start menu), the workspaces, and
//           the focused app's name
//   centre  the date and time (opens the calendar)
//   right   Wi-Fi, Bluetooth, sound and the battery, from forged; a click
//           anywhere there opens Forge Control
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

import 'forged.dart';
import 'wm.dart';
import 'native.dart';
import 'popups/client.dart';

const _workspaceCount = 5;

class Bar extends StatefulWidget {
  const Bar({super.key, required this.palette});

  final ForgePalette palette;

  @override
  State<Bar> createState() => _BarState();
}

class _BarState extends State<Bar> {
  final _wm = Wm.connect();
  final _forged = Forged();
  final _popups = Popups();
  DesktopState _state = {};
  int _workspace = 1;
  Set<int> _occupied = {};
  String _title = '';
  DateTime _now = DateTime.now();
  Timer? _clock;
  final _subs = <StreamSubscription<Object?>>[];

  @override
  void initState() {
    super.initState();
    _tickClock();
    _subs.add(_forged.changes.listen((s) => setState(() => _state = s)));
    _forged.state().then((s) => setState(() => _state = s), onError: (_) {});
    _refreshWindows();
    _subs.add(_wm.changes().listen((_) => _refreshWindows()));
  }

  /// Ticks on the minute, so the clock turns over when the system's does.
  void _tickClock() {
    setState(() => _now = DateTime.now());
    _clock = Timer(Duration(seconds: 60 - _now.second), _tickClock);
  }

  Future<void> _refreshWindows() async {
    final wm = _wm;
    try {
      final (ws, occupied, windows) = await (
        wm.activeWorkspace(),
        wm.occupiedWorkspaces(),
        wm.windows(),
      ).wait;
      if (!mounted) return;
      final focused = windows.where((w) => w.focusHistory == 0 && !w.minimized);
      setState(() {
        _workspace = ws;
        _occupied = occupied;
        _title = focused.isEmpty ? '' : _appName(focused.first.appClass);
      });
    } catch (_) {}
  }

  /// What to call the focused app: its class made readable
  /// ("org.kde.dolphin" → "Dolphin").
  String _appName(String appClass) {
    final c = appClass.split('.').last;
    if (c.isEmpty) return '';
    return c[0].toUpperCase() + c.substring(1);
  }

  @override
  void dispose() {
    _clock?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  Map<String, dynamic> _part(String name) =>
      (_state[name] as Map<String, dynamic>?) ?? const {};

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final text = TextStyle(
      color: p.text,
      fontSize: 13,
      fontWeight: FontWeight.w600,
      height: 1,
    );
    return Container(
      decoration: BoxDecoration(
        color: p.window,
        borderRadius: BorderRadius.circular(
          p.cornerRadius.clamp(6, 17).toDouble(),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Row(
            children: [
              _BarButton(
                palette: p,
                onTap: _popups.startMenu,
                child: Image.asset('assets/emblem.png', width: 18, height: 18),
              ),
              if (_wm.hasWorkspaces) ...[
                const SizedBox(width: 4),
                _Workspaces(
                  palette: p,
                  active: _workspace,
                  occupied: _occupied,
                  onSelect: (n) => _wm.switchWorkspace(n),
                ),
              ],
              const SizedBox(width: 10),
              // All the room left, but a long title stops short of the clock.
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: Text(
                      _title,
                      style: text.copyWith(fontWeight: FontWeight.w700),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
              _BarButton(
                palette: p,
                onTap: () => Native.run('forge-control'),
                child: _Status(palette: p, part: _part),
              ),
            ],
          ),
          // The clock sits in the true centre, whatever is either side.
          _BarButton(
            palette: p,
            onTap: _popups.calendar,
            child: Text(_clockText(_now), style: text),
          ),
        ],
      ),
    );
  }
}

const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _clockText(DateTime t) =>
    '${_days[t.weekday - 1]} ${t.day} ${_months[t.month - 1]}   '
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// A rounded hover area around something in the bar.
class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.palette,
    required this.onTap,
    required this.child,
  });

  final ForgePalette palette;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        hoverColor: palette.hover,
        splashColor: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          child: child,
        ),
      ),
    );
  }
}

/// One dot per workspace: the active one a wide accent pill, ones with
/// windows solid, empty ones faint.
class _Workspaces extends StatelessWidget {
  const _Workspaces({
    required this.palette,
    required this.active,
    required this.occupied,
    required this.onSelect,
  });

  final ForgePalette palette;
  final int active;
  final Set<int> occupied;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final count = [
      _workspaceCount,
      active,
      ...occupied,
    ].reduce((a, b) => a > b ? a : b);
    return Row(
      children: [
        for (var n = 1; n <= count; n++)
          GestureDetector(
            onTap: () => onSelect(n),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                width: n == active ? 20 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: n == active
                      ? palette.accent
                      : palette.text.withValues(
                          alpha: occupied.contains(n) ? 0.55 : 0.2,
                        ),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Wi-Fi, Bluetooth, sound and battery, as forged sees them.
class _Status extends StatelessWidget {
  const _Status({required this.palette, required this.part});

  final ForgePalette palette;
  final Map<String, dynamic> Function(String) part;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final wifi = part('wifi');
    final bt = part('bluetooth');
    final volume = part('volume');
    final battery = part('battery');

    IconData wifiIcon() {
      if (wifi['wired'] == true) return Icons.settings_ethernet_rounded;
      if (wifi['enabled'] != true) return Icons.wifi_off_rounded;
      if (wifi['ssid'] == null) return Icons.wifi_find_rounded;
      final s = wifi['signal'] as int? ?? 100;
      return s > 66
          ? Icons.wifi_rounded
          : s > 33
          ? Icons.wifi_2_bar_rounded
          : Icons.wifi_1_bar_rounded;
    }

    IconData volumeIcon() {
      final level = volume['level'] as int? ?? 0;
      if (volume['muted'] == true || level == 0) {
        return Icons.volume_off_rounded;
      }
      return level < 50 ? Icons.volume_down_rounded : Icons.volume_up_rounded;
    }

    Widget icon(IconData data) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: Icon(data, size: 16, color: p.text),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (bt['available'] == true && bt['enabled'] == true)
          icon(
            (bt['connected'] as List?)?.isNotEmpty == true
                ? Icons.bluetooth_connected_rounded
                : Icons.bluetooth_rounded,
          ),
        if (wifi['available'] == true) icon(wifiIcon()),
        if (volume['available'] == true) icon(volumeIcon()),
        if (battery['available'] == true) ...[
          const SizedBox(width: 5),
          BatteryIcon(
            palette: p,
            percent: battery['percent'] as int? ?? 0,
            charging: battery['charging'] == true,
          ),
        ],
      ],
    );
  }
}

/// The battery as on the Plasma bar: an outline filled to the charge, the
/// percentage inside it, green while plugged in and red at 20% or less.
class BatteryIcon extends StatelessWidget {
  const BatteryIcon({
    super.key,
    required this.palette,
    required this.percent,
    required this.charging,
  });

  final ForgePalette palette;
  final int percent;
  final bool charging;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final fill = charging
        ? p.positive
        : percent <= 20
        ? p.negative
        : p.text;
    // Digits readable on the fill: dark ink on a light fill and the reverse.
    final onFill = fill.computeLuminance() > 0.45 ? Colors.black : Colors.white;
    final digits = TextStyle(
      fontSize: 9.5,
      fontWeight: FontWeight.w800,
      height: 1,
      letterSpacing: -0.2,
    );
    const w = 28.0, h = 14.0;
    final level = (percent.clamp(0, 100)) / 100;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: w,
          height: h,
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: p.text.withValues(alpha: 0.45),
                    width: 1.2,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(2),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: level,
                  child: Container(
                    decoration: BoxDecoration(
                      color: fill,
                      borderRadius: BorderRadius.circular(2.5),
                    ),
                  ),
                ),
              ),
              // The number twice: in ink over the empty part, and in the fill's
              // own contrast colour clipped to the fill.
              Center(
                child: Text('$percent', style: digits.copyWith(color: p.text)),
              ),
              ClipRect(
                clipper: _LeftPart(2 + (w - 4) * level),
                child: Center(
                  child: Text(
                    '$percent',
                    style: digits.copyWith(color: onFill),
                  ),
                ),
              ),
            ],
          ),
        ),
        Container(
          width: 2,
          height: 5,
          margin: const EdgeInsets.only(left: 1),
          decoration: BoxDecoration(
            color: p.text.withValues(alpha: 0.45),
            borderRadius: const BorderRadius.horizontal(
              right: Radius.circular(1.5),
            ),
          ),
        ),
        if (charging)
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Icon(Icons.bolt_rounded, size: 13, color: p.text),
          ),
      ],
    );
  }
}

class _LeftPart extends CustomClipper<Rect> {
  _LeftPart(this.width);

  final double width;

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, width, size.height);

  @override
  bool shouldReclip(_LeftPart old) => old.width != width;
}
