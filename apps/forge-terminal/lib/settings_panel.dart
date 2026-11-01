// The settings sheet that slides over the right of the terminal: font,
// size, cursor, opacity, scrollback, shell. Saved as they change.
import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

import 'settings.dart';

class SettingsPanel extends StatefulWidget {
  const SettingsPanel({
    super.key,
    required this.palette,
    required this.settings,
    required this.onChanged,
    required this.onClose,
  });

  final ForgePalette palette;
  final TerminalSettings settings;
  final ValueChanged<TerminalSettings> onChanged;
  final VoidCallback onClose;

  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel> {
  List<String> _fonts = [];
  late final TextEditingController _shell = TextEditingController(text: widget.settings.shell ?? '');

  @override
  void initState() {
    super.initState();
    monospaceFonts().then((f) {
      if (mounted) setState(() => _fonts = f);
    });
  }

  @override
  void dispose() {
    _shell.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final s = widget.settings;
    final font = s.resolvedFont;
    final fonts = {..._fonts, font}.toList()..sort();
    final themeOpacity = p.theme.terminalOpacity;

    return Material(
      color: p.surface,
      elevation: 8,
      shadowColor: Colors.black45,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 320,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
          children: [
            Row(children: [
              Expanded(
                child: Text('Terminal', style: TextStyle(color: p.text, fontSize: 17, fontWeight: FontWeight.w700)),
              ),
              IconButton(
                icon: Icon(Icons.close_rounded, color: p.text, size: 20),
                onPressed: widget.onClose,
              ),
            ]),
            SectionLabel('Text', palette: p),
            const SizedBox(height: 6),
            _row(
              p,
              'Font',
              DropdownButton<String>(
                value: font,
                isExpanded: true,
                underline: const SizedBox(),
                dropdownColor: p.surface,
                borderRadius: BorderRadius.circular(12),
                style: TextStyle(color: p.text, fontSize: 13),
                items: [
                  for (final f in fonts)
                    DropdownMenuItem(
                      value: f,
                      child: Text(f == desktopFixedFont() ? '$f (desktop)' : f, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (f) => widget.onChanged(s.copyWith(fontFamily: () => f == desktopFixedFont() ? null : f)),
              ),
            ),
            ForgeSlider(
              palette: p,
              label: 'Size',
              value: s.fontSize,
              min: 7,
              max: 24,
              divisions: 34,
              format: (v) => '${v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1)} pt',
              onChanged: (v) => widget.onChanged(s.copyWith(fontSize: v)),
            ),
            const SizedBox(height: 10),
            Text('Cursor', style: TextStyle(color: p.text, fontSize: 13)),
            const SizedBox(height: 6),
            Segmented<CursorShape>(
              palette: p,
              options: const {CursorShape.bar: 'Bar', CursorShape.block: 'Block', CursorShape.underline: 'Line'},
              value: s.cursor,
              onChanged: (c) => widget.onChanged(s.copyWith(cursor: c)),
            ),
            const SizedBox(height: 18),
            SectionLabel('Look', palette: p),
            const SizedBox(height: 6),
            _switch(
              p,
              'Opacity from the theme',
              'The Theming Kit\'s terminal opacity ($themeOpacity%)',
              s.opacity == null,
              (on) => widget.onChanged(s.copyWith(opacity: () => on ? null : themeOpacity)),
            ),
            if (s.opacity != null)
              ForgeSlider(
                palette: p,
                label: 'Opacity',
                value: s.opacity!.toDouble(),
                min: 20,
                max: 100,
                divisions: 80,
                format: (v) => '${v.round()}%',
                onChanged: (v) => widget.onChanged(s.copyWith(opacity: () => v.round())),
              ),
            _switch(
              p,
              'Light when the desktop is light',
              'Otherwise always the dark glass, which most programs expect',
              s.lightFollowsDesktop,
              (on) => widget.onChanged(s.copyWith(lightFollowsDesktop: on)),
            ),
            const SizedBox(height: 18),
            SectionLabel('Behaviour', palette: p),
            const SizedBox(height: 6),
            ForgeSlider(
              palette: p,
              label: 'Scrollback',
              value: s.scrollback.toDouble(),
              min: 1000,
              max: 100000,
              divisions: 99,
              format: (v) => '${(v / 1000).round()}k lines',
              hint: 'For new tabs',
              onChanged: (v) => widget.onChanged(s.copyWith(scrollback: v.round())),
            ),
            _switch(
              p,
              'Ask before closing a busy tab',
              'When something besides the shell is running',
              s.confirmClose,
              (on) => widget.onChanged(s.copyWith(confirmClose: on)),
            ),
            const SizedBox(height: 8),
            Text('Shell', style: TextStyle(color: p.text, fontSize: 13)),
            TextField(
              controller: _shell,
              style: TextStyle(color: p.text, fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Your account\'s shell',
                hintStyle: TextStyle(color: p.dimText),
              ),
              onSubmitted: (v) => widget.onChanged(s.copyWith(shell: () => v.trim().isEmpty ? null : v.trim())),
            ),
            const SizedBox(height: 18),
            SectionLabel('Keys', palette: p),
            const SizedBox(height: 6),
            for (final (k, v) in const [
              ('Ctrl+Shift+T / W', 'New / close tab'),
              ('Ctrl+Tab, Alt+1…9', 'Switch tab'),
              ('Ctrl+Shift+C / V', 'Copy / paste'),
              ('Ctrl+Shift+F', 'Find'),
              ('Ctrl+= / − / 0', 'Zoom'),
              ('Ctrl+Shift+E', 'Open the folder in Files'),
              ('Ctrl+click', 'Open a link or path'),
            ])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Expanded(child: Text(v, style: TextStyle(color: p.dimText, fontSize: 12.5))),
                  Text(k, style: TextStyle(color: p.text, fontSize: 12.5, fontWeight: FontWeight.w600)),
                ]),
              ),
          ],
        ),
      ),
    );
  }

  Widget _row(ForgePalette p, String label, Widget child) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          SizedBox(width: 60, child: Text(label, style: TextStyle(color: p.text, fontSize: 13))),
          Expanded(child: child),
        ]),
      );

  Widget _switch(ForgePalette p, String title, String sub, bool value, ValueChanged<bool> onChanged) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(color: p.text, fontSize: 13)),
              Text(sub, style: TextStyle(color: p.dimText, fontSize: 11.5)),
            ]),
          ),
          Switch(value: value, activeTrackColor: p.accent, onChanged: onChanged),
        ]),
      );
}
