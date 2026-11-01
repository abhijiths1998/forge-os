// A Forge dialog: an icon, a title, a few lines, maybe a text or password
// field, and buttons. Asked for as JSON (by forge-dialog, or the shell):
//
//   {"title": "Delete 3 files?", "text": "They can't be brought back.",
//    "icon": "warning",
//    "buttons": [{"id": "cancel", "label": "Cancel"},
//                {"id": "delete", "label": "Delete", "danger": true}],
//    "input": {"placeholder": "Name", "value": "", "password": false},
//    "countdown": 30, "countdownButton": "delete"}
//
// Answers {"button": id, "text": what was typed}; button is "" when closed
// with Esc. Enter takes the primary (else the last) button.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forge_ui/forge_ui.dart';

import 'style.dart';

class DialogButtonSpec {
  DialogButtonSpec.fromJson(Map<String, dynamic> m)
    : id = m['id'] as String? ?? '',
      label = m['label'] as String? ?? '',
      primary = m['primary'] == true,
      danger = m['danger'] == true;

  const DialogButtonSpec(
    this.id,
    this.label, {
    this.primary = false,
    this.danger = false,
  });

  final String id;
  final String label;
  final bool primary;
  final bool danger;
}

class DialogSpec {
  DialogSpec.fromJson(Map<String, dynamic> m)
    : title = m['title'] as String? ?? '',
      text = m['text'] as String? ?? '',
      icon = m['icon'] as String?,
      buttons = [
        for (final b in m['buttons'] as List? ?? const [])
          DialogButtonSpec.fromJson(b as Map<String, dynamic>),
      ],
      input = m['input'] is Map ? m['input'] as Map<String, dynamic> : null,
      countdown = m['countdown'] as int? ?? 0,
      countdownButton = m['countdownButton'] as String?,
      countdownText = m['countdownText'] as String?;

  DialogSpec({
    required this.title,
    this.text = '',
    this.icon,
    required this.buttons,
    this.input,
    this.countdown = 0,
    this.countdownButton,
    this.countdownText,
  });

  final String title;
  final String text;
  final String? icon;
  final List<DialogButtonSpec> buttons;
  final Map<String, dynamic>? input;

  /// Seconds until [countdownButton] is pressed by itself (0: never).
  final int countdown;
  final String? countdownButton;

  /// "Shutting down in {s} seconds."
  final String? countdownText;

  List<DialogButtonSpec> get shownButtons =>
      buttons.isEmpty ? [const DialogButtonSpec('ok', 'OK', primary: true)] : buttons;
}

class DialogCard extends StatefulWidget {
  const DialogCard({
    super.key,
    required this.palette,
    required this.spec,
    required this.onDone,
  });

  final ForgePalette palette;
  final DialogSpec spec;

  /// (button id, typed text); '' for the button when cancelled.
  final void Function(String button, String text) onDone;

  @override
  State<DialogCard> createState() => _DialogCardState();
}

class _DialogCardState extends State<DialogCard> {
  late final _text = TextEditingController(
    text: widget.spec.input?['value'] as String? ?? '',
  );
  Timer? _timer;
  late int _left = widget.spec.countdown;

  @override
  void initState() {
    super.initState();
    if (_left > 0 && widget.spec.countdownButton != null) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() => _left--);
        if (_left <= 0) _press(widget.spec.countdownButton!);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _press(String id) {
    _timer?.cancel();
    widget.onDone(id, _text.text);
  }

  DialogButtonSpec get _default {
    final b = widget.spec.shownButtons;
    return b.firstWhere((x) => x.primary, orElse: () => b.last);
  }

  KeyEventResult _key(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.enter ||
        e.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _press(_default.id);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final s = widget.spec;
    final input = s.input;
    final iconData = popupIcons[s.icon];
    final iconColour = switch (s.icon) {
      'warning' => const Color(0xFFF2A33A),
      'error' => p.negative,
      _ => p.accent,
    };
    final countdown = _timer != null && s.countdownText != null
        ? s.countdownText!.replaceAll('{s}', '$_left')
        : null;

    return Focus(
      autofocus: input == null,
      onKeyEvent: _key,
      child: PopupCard(
        palette: p,
        width: 420,
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (iconData != null) ...[
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: iconColour.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(iconData, color: iconColour, size: 22),
                  ),
                  const SizedBox(width: 14),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 2),
                      Text(
                        s.title,
                        style: TextStyle(
                          color: p.text,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (s.text.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          s.text,
                          style: TextStyle(
                            color: p.text.withValues(alpha: 0.75),
                            fontSize: 13.5,
                            height: 1.4,
                          ),
                        ),
                      ],
                      if (countdown != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          countdown,
                          style: TextStyle(
                            color: p.dimText,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (input != null) ...[
              const SizedBox(height: 18),
              ForgeField(
                palette: p,
                controller: _text,
                autofocus: true,
                password: input['password'] == true,
                hint: input['placeholder'] as String?,
                onSubmitted: (_) => _press(_default.id),
              ),
            ],
            const SizedBox(height: 22),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                for (final (i, b) in s.shownButtons.indexed) ...[
                  if (i > 0) const SizedBox(width: 8),
                  DialogButton(
                    palette: p,
                    label: b.label,
                    primary: b.primary,
                    danger: b.danger,
                    onTap: () => _press(b.id),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// What the power choices do, and how each one is asked about.
class PowerAction {
  const PowerAction(
    this.id,
    this.label,
    this.icon, {
    this.confirm,
    this.countdownText,
  });

  final String id;
  final String label;
  final String icon;

  /// The question, for the ones that end the session.
  final String? confirm;
  final String? countdownText;

  static const all = [
    PowerAction('lock', 'Lock', 'lock'),
    PowerAction('sleep', 'Sleep', 'sleep'),
    PowerAction(
      'logout',
      'Log out',
      'logout',
      confirm: 'Log out?',
      countdownText: 'Logging out in {s} seconds.',
    ),
    PowerAction(
      'restart',
      'Restart',
      'restart',
      confirm: 'Restart now?',
      countdownText: 'Restarting in {s} seconds.',
    ),
    PowerAction(
      'shutdown',
      'Shut down',
      'power',
      confirm: 'Shut down now?',
      countdownText: 'Shutting down in {s} seconds.',
    ),
  ];

  static PowerAction? byId(String id) =>
      all.where((a) => a.id == id).firstOrNull;

  DialogSpec confirmDialog() => DialogSpec(
    title: confirm ?? label,
    text: 'Apps that are still open will be closed, and unsaved work in '
        'them may be lost.',
    icon: icon,
    buttons: [
      const DialogButtonSpec('cancel', 'Cancel'),
      DialogButtonSpec(id, label, primary: true),
    ],
    countdown: 30,
    countdownButton: id,
    countdownText: countdownText,
  );
}

/// The power choices as a row of big round buttons (from the power key,
/// the desktop menu or `forge-dialog power`).
class PowerCard extends StatelessWidget {
  const PowerCard({super.key, required this.palette, required this.onPick});

  final ForgePalette palette;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return PopupCard(
      palette: p,
      padding: const EdgeInsets.fromLTRB(26, 22, 26, 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Power',
            style: TextStyle(
              color: p.text,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final a in PowerAction.all)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: _BigButton(
                    palette: p,
                    icon: popupIcons[a.icon]!,
                    label: a.label,
                    danger: a.id == 'shutdown',
                    onTap: () => onPick(a.id),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          DialogButton(palette: p, label: 'Cancel', onTap: () => onPick('')),
        ],
      ),
    );
  }
}

class _BigButton extends StatefulWidget {
  const _BigButton({
    required this.palette,
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final ForgePalette palette;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  State<_BigButton> createState() => _BigButtonState();
}

class _BigButtonState extends State<_BigButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final tint = widget.danger ? p.negative : p.accent;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _hover ? tint : p.hover,
              ),
              child: Icon(
                widget.icon,
                size: 26,
                color: _hover ? Colors.white : p.text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.label,
              style: TextStyle(
                color: p.text,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
