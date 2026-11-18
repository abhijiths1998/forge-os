// The app shell: desktop or couch mode, the pad dispatcher, the Guide button
// and toasts.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forge_ui/forge_ui.dart';

import 'pad.dart';
import 'screens/couch_screen.dart';
import 'screens/library_screen.dart';
import 'store.dart';
import 'widgets/glass.dart';
import 'window.dart';

class ForgeGamingApp extends StatefulWidget {
  const ForgeGamingApp({
    super.key,
    required this.store,
    required this.palette,
    this.couch = false,
    this.pad,
  });

  final GamingStore store;
  final ForgePalette palette;
  final bool couch;

  /// Pad presses; by default from the store's daemon.
  final Stream<PadPress>? pad;

  @override
  State<ForgeGamingApp> createState() => _ForgeGamingAppState();
}

class _ForgeGamingAppState extends State<ForgeGamingApp> with WidgetsBindingObserver {
  final _navigator = GlobalKey<NavigatorState>();
  late bool _couch = widget.couch;
  bool _windowActive = true;

  /// Brought up over a running game with Guide: the pad drives the UI
  /// (to stop the game, say) until Guide again goes back to the game.
  bool _overGame = false;
  late final PadDispatcher _pad;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pad = PadDispatcher(
      presses: widget.pad ?? padPresses(widget.store.daemon.events),
      navigatorKey: _navigator,
      isActive: () => _windowActive && (!widget.store.anyRunning || _overGame),
      onGuide: _onGuide,
    );
    if (_couch) windowCall('setFullscreen', true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pad.dispose();
    super.dispose();
  }

  // While another window (a game) has focus, the pad belongs to it.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _windowActive = state == AppLifecycleState.resumed;
    if (!_windowActive) _overGame = false;
  }

  void _onGuide() {
    final running = widget.store.anyRunning;
    if (_windowActive && running && _overGame) {
      // Guide again: back to the game.
      _overGame = false;
      returnToGame();
      return;
    }
    if (!_windowActive || running) {
      // Over a game: come forward, in couch mode, and let the pad drive it.
      _windowActive = true;
      _overGame = running;
      bringToFront();
      if (!_couch) _setCouch(true);
    } else {
      _setCouch(!_couch);
    }
  }

  void _setCouch(bool on) {
    if (on == _couch) return;
    _navigator.currentState?.popUntil((r) => r.isFirst);
    setState(() => _couch = on);
    windowCall('setFullscreen', on);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Forge Gaming',
      color: Colors.transparent,
      theme: p.materialTheme(),
      navigatorKey: _navigator,
      builder: (context, child) => CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () => _navigator.currentState?.maybePop(),
          const SingleActivator(LogicalKeyboardKey.f11): () => _setCouch(!_couch),
        },
        child: Stack(children: [
          child ?? const SizedBox.shrink(),
          _Toasts(palette: p, toasts: widget.store.toasts),
        ]),
      ),
      home: _couch
          ? CouchScreen(
              key: const ValueKey('couch'),
              store: widget.store,
              palette: p,
              onExit: () => _setCouch(false),
            )
          : LibraryScreen(
              key: const ValueKey('desktop'),
              store: widget.store,
              palette: p,
              onCouch: () => _setCouch(true),
            ),
    );
  }
}

/// Glass toasts in the bottom-right corner, each for a few seconds.
class _Toasts extends StatefulWidget {
  const _Toasts({required this.palette, required this.toasts});
  final ForgePalette palette;
  final Stream<String> toasts;

  @override
  State<_Toasts> createState() => _ToastsState();
}

class _ToastsState extends State<_Toasts> {
  final _shown = <(int, String)>[];
  var _n = 0;
  late final StreamSubscription<String> _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.toasts.listen((t) {
      final id = _n++;
      setState(() => _shown.add((id, t)));
      Timer(const Duration(seconds: 5), () {
        if (mounted) setState(() => _shown.removeWhere((e) => e.$1 == id));
      });
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 24,
      bottom: 24,
      child: IgnorePointer(
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (final (id, text) in _shown)
            Padding(
              key: ValueKey(id),
              padding: const EdgeInsets.only(top: 10),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Glass(
                  palette: widget.palette,
                  strength: 1.8,
                  radius: 16,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  child: Text(text,
                      style: TextStyle(color: widget.palette.text, fontSize: 13.5, fontWeight: FontWeight.w600)),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}
