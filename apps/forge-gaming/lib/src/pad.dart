// Controller input. forge-gamed reads the pads (SDL3, Xbox layout) and sends
// pad.button events; this turns them into Flutter focus moves and intents,
// so every focusable widget works with a pad without knowing about it:
//
//   d-pad / left stick  move focus (directional traversal)
//   A                   activate the focused widget (ActivateIntent)
//   B                   go back (pop the route)
//   anything else       whatever the nearest [PadShortcuts] around the focus binds
//
// While the window is not focused or a game is running, presses are ignored
// (the pad belongs to the game); the Guide button always gets through.
import 'dart:async';

import 'package:flutter/material.dart';

import 'daemon.dart';

enum PadButton { a, b, x, y, lb, rb, lt, rt, back, start, guide, ls, rs, up, down, left, right }

class PadPress {
  const PadPress(this.button, {this.pad = 0, this.repeat = false});
  final PadButton button;
  final int pad;
  final bool repeat;
}

/// Presses (not releases) from forge-gamed's pad.button events.
Stream<PadPress> padPresses(Stream<DaemonEvent> events) => events
    .where((e) => e.name == 'pad.button' && e.data['pressed'] == true)
    .map((e) {
      final b = PadButton.values.where((v) => v.name == e.data['button']);
      if (b.isEmpty) return null;
      final pad = e.data['pad'];
      return PadPress(b.first, pad: pad is int ? pad : 0, repeat: e.data['repeat'] == true);
    })
    .where((p) => p != null)
    .cast<PadPress>();

/// Binds pad buttons for the subtree, like [Shortcuts] does for keys.
/// The binding nearest the focused widget wins; return false from a handler
/// to let an outer binding (or the default) have the press.
class PadShortcuts extends StatefulWidget {
  const PadShortcuts({super.key, required this.bindings, required this.child});

  final Map<PadButton, bool Function()> bindings;
  final Widget child;

  @override
  State<PadShortcuts> createState() => _PadShortcutsState();
}

class _PadShortcutsState extends State<PadShortcuts> {
  @override
  Widget build(BuildContext context) => widget.child;
}

/// Simple bindings that always claim the press.
Map<PadButton, bool Function()> padBindings(Map<PadButton, VoidCallback> m) =>
    m.map((k, f) => MapEntry(k, () {
          f();
          return true;
        }));

class PadDispatcher {
  PadDispatcher({
    required Stream<PadPress> presses,
    required this.navigatorKey,
    required this.isActive,
    this.onGuide,
    this.onUnhandled,
  }) {
    _sub = presses.listen(handle);
  }

  final GlobalKey<NavigatorState> navigatorKey;

  /// False while a game owns the pad or the window is in the background.
  final bool Function() isActive;
  final VoidCallback? onGuide;

  /// Called for a press nobody took (B at the root, say).
  final void Function(PadButton)? onUnhandled;

  late final StreamSubscription<PadPress> _sub;

  void dispose() => _sub.cancel();

  void handle(PadPress p) {
    if (p.button == PadButton.guide) {
      if (!p.repeat) onGuide?.call();
      return;
    }
    if (!isActive()) return;

    final focus = FocusManager.instance.primaryFocus;
    // Bindings from the focused widget outwards.
    if (!p.repeat || _repeats(p.button)) {
      BuildContext? ctx = focus?.context ?? navigatorKey.currentContext;
      while (ctx != null) {
        final state = ctx.findAncestorStateOfType<_PadShortcutsState>();
        if (state == null) break;
        final f = state.widget.bindings[p.button];
        if (f != null && f()) return;
        ctx = state.context;
      }
    }

    switch (p.button) {
      case PadButton.up:
        _move(focus, TraversalDirection.up);
      case PadButton.down:
        _move(focus, TraversalDirection.down);
      case PadButton.left:
        _move(focus, TraversalDirection.left);
      case PadButton.right:
        _move(focus, TraversalDirection.right);
      case PadButton.a when !p.repeat:
        final ctx = focus?.context;
        if (ctx == null || Actions.maybeInvoke(ctx, const ActivateIntent()) == null) {
          onUnhandled?.call(p.button);
        }
      case PadButton.b when !p.repeat:
        final nav = navigatorKey.currentState;
        if (nav == null) return;
        nav.maybePop().then((popped) {
          if (!popped) onUnhandled?.call(PadButton.b);
        });
      default:
        if (!p.repeat) onUnhandled?.call(p.button);
    }
  }

  static bool _repeats(PadButton b) =>
      b == PadButton.up || b == PadButton.down || b == PadButton.left || b == PadButton.right;

  void _move(FocusNode? focus, TraversalDirection dir) {
    // Nothing focused yet (or only a scope): start at the first widget.
    if (focus == null || focus is FocusScopeNode || focus.context == null) {
      final scope = focus is FocusScopeNode
          ? focus
          : FocusScope.of(navigatorKey.currentContext ?? focus!.context!);
      scope.nextFocus();
      return;
    }
    focus.focusInDirection(dir);
  }
}

/// A hint for the bottom bar: a button glyph and what it does.
class PadHint {
  const PadHint(this.button, this.label, {this.also});
  final PadButton button;
  final String label;

  /// A second button shown with the first ("LB RB  Shelf").
  final PadButton? also;
}
