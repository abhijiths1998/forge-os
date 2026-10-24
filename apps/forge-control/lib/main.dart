// Forge Control: the Control Center. A glass panel under the top bar with
// the switches people reach for most: Wi-Fi, Bluetooth, quiet, dark mode,
// tiling, brightness, volume, power and cooling profiles, and what's
// playing. The state and the switches are forged's (forged.dart); this is
// only the panel.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forge_ui/forge_ui.dart';

import 'forged.dart';
import 'tiles.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ControlApp());
}

class Native {
  static const _channel = MethodChannel('forge/control');

  /// Called with "shown" / "hidden" as the runner toggles the window.
  static void onEvent(void Function(String event) handler) {
    _channel.setMethodCallHandler((call) async => handler(call.method));
  }

  static Future<void> hide() => _channel.invokeMethod('hide');

  static Future<void> setHeight(int height) =>
      _channel.invokeMethod('setHeight', {'height': height});
}

class ControlApp extends StatefulWidget {
  const ControlApp({super.key});

  @override
  State<ControlApp> createState() => _ControlAppState();
}

class _ControlAppState extends State<ControlApp> {
  final _forged = Forged();
  final _content = GlobalKey();
  ForgePalette _palette = ForgePalette.current();
  DesktopState _state = {};
  String _error = '';
  StreamSubscription<DesktopState>? _changes;
  Timer? _errorTimer;

  // A slider being dragged keeps its own value; forged's would make it jump.
  final _dragging = <String, double>{};
  final _sendTimers = <String, Timer>{};

  @override
  void initState() {
    super.initState();
    Native.onEvent((event) {
      if (event == 'shown') _onShown();
    });
    _connect();
  }

  Future<void> _connect() async {
    _changes = _forged.changes.listen((s) => setState(() => _state = s));
    try {
      final s = await _forged.state();
      setState(() => _state = s);
    } catch (_) {
      setState(() => _error = 'forged isn\'t running');
    }
  }

  void _onShown() {
    setState(() => _palette = ForgePalette.current());
    _forged.state().then((s) => setState(() => _state = s), onError: (_) {});
  }

  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }

  Map<String, dynamic> part(String name) =>
      (_state[name] as Map<String, dynamic>?) ?? const {};

  bool available(String name) => part(name)['available'] == true;

  Future<void> _set(String key, String value) async {
    final err = await _forged.set(key, value).catchError((_) => 'no forged');
    if (err.isEmpty || !mounted) return;
    _errorTimer?.cancel();
    setState(() => _error = err);
    _errorTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _error = '');
    });
  }

  void _toggle(String key) =>
      _set(key, part(key)['enabled'] == true ? 'off' : 'on');

  /// A slider moved: send at most every 60 ms while dragging, and the end
  /// value always.
  void _slide(String key, double value, {bool end = false}) {
    setState(() => end ? _dragging.remove(key) : _dragging[key] = value);
    _sendTimers[key]?.cancel();
    if (end) {
      _set(key, value.round().toString());
    } else {
      _sendTimers[key] = Timer(const Duration(milliseconds: 60),
          () => _set(key, value.round().toString()));
    }
  }

  /// A device name if it's short enough to read at a glance ("Headphones"),
  /// not a sound card's full hardware name.
  String? _short(String? name) =>
      name != null && name.length <= 26 ? name : null;

  double _level(String key) =>
      _dragging[key] ?? (part(key)['level'] as num? ?? 0).toDouble();

  /// The window is only as tall as the panel.
  void _fitHeight() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final box = _content.currentContext?.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize) Native.setHeight(box.size.height.ceil());
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = _palette;
    _fitHeight();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      color: Colors.transparent,
      theme: p.materialTheme(),
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): Native.hide,
          },
          child: Focus(
            autofocus: true,
            // Laid out at its full height whatever the window's height is,
            // so _fitHeight measures what the window should be.
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: Container(
                key: _content,
                decoration: BoxDecoration(
                  color: p.surface,
                  borderRadius:
                      BorderRadius.circular(p.cornerRadius.toDouble()),
                ),
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _panel(p),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _panel(ForgePalette p) {
    final wifi = part('wifi'), bt = part('bluetooth');
    final connected = (bt['connected'] as List?)?.cast<String>() ?? const [];
    final media = part('media');
    const gap = SizedBox(height: 10);
    return [
      Row(children: [
        Expanded(
          child: WideToggle(
            palette: p,
            icon: wifi['enabled'] == true
                ? Icons.wifi_rounded
                : Icons.wifi_off_rounded,
            title: 'Wi-Fi',
            subtitle: !available('wifi')
                ? (wifi['wired'] == true ? 'Wired' : 'Unavailable')
                : wifi['enabled'] != true
                    ? 'Off'
                    : (wifi['ssid'] as String?) ?? 'Not connected',
            on: wifi['enabled'] == true,
            onTap: available('wifi') ? () => _toggle('wifi') : null,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: WideToggle(
            palette: p,
            icon: bt['enabled'] == true
                ? Icons.bluetooth_rounded
                : Icons.bluetooth_disabled_rounded,
            title: 'Bluetooth',
            subtitle: !available('bluetooth')
                ? 'Unavailable'
                : bt['enabled'] != true
                    ? 'Off'
                    : connected.isEmpty
                        ? 'On'
                        : connected.join(', '),
            on: bt['enabled'] == true,
            onTap: available('bluetooth') ? () => _toggle('bluetooth') : null,
          ),
        ),
      ]),
      gap,
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        RoundToggle(
          palette: p,
          icon: Icons.do_not_disturb_on_rounded,
          label: 'Quiet',
          on: part('dnd')['enabled'] == true,
          onTap: available('dnd') ? () => _toggle('dnd') : null,
        ),
        RoundToggle(
          palette: p,
          icon: Icons.dark_mode_rounded,
          label: 'Dark',
          on: part('dark')['enabled'] == true,
          onTap: () => _toggle('dark'),
        ),
        RoundToggle(
          palette: p,
          icon: Icons.grid_view_rounded,
          label: 'Tiling',
          on: part('tiling')['enabled'] == true,
          onTap: () => _toggle('tiling'),
        ),
      ]),
      if (available('brightness')) ...[
        gap,
        LevelCard(
          palette: p,
          title: 'Display',
          icon: Icons.light_mode_rounded,
          value: _level('brightness'),
          max: 100,
          onChanged: (v) => _slide('brightness', v),
          onChangeEnd: (v) => _slide('brightness', v, end: true),
        ),
      ],
      if (available('volume')) ...[
        gap,
        LevelCard(
          palette: p,
          title: 'Sound',
          subtitle: _short(part('volume')['device'] as String?),
          icon: part('volume')['muted'] == true
              ? Icons.volume_off_rounded
              : Icons.volume_up_rounded,
          value: _level('volume'),
          max: 100,
          onIconTap: () => _set(
              'volume', part('volume')['muted'] == true ? 'unmute' : 'mute'),
          onChanged: (v) => _slide('volume', v),
          onChangeEnd: (v) => _slide('volume', v, end: true),
        ),
      ],
      if (available('power') || available('thermal')) ...[
        gap,
        ProfilesCard(
          palette: p,
          power: available('power') ? part('power') : null,
          thermal: available('thermal') ? part('thermal') : null,
          onPower: (v) => _set('power', v),
          onThermal: (v) => _set('thermal', v),
        ),
      ],
      if (media['available'] == true) ...[
        gap,
        MediaCard(
          palette: p,
          media: media,
          onAction: (a) => _forged.media(a),
        ),
      ],
      gap,
      Footer(
        palette: p,
        battery: available('battery') ? part('battery') : null,
        message: _error,
      ),
    ];
  }
}
