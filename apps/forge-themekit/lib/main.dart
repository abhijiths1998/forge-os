// Forge Theming Kit: pick a theme or shape your own: colour (light/dark,
// accent, glass tint), the liquid glass itself (blur, vibrancy, lens,
// bevel, inner bending, colour split, grain), surface opacities and corner
// radius. Glass and shape apply live as sliders move; colours on release.
//
//   forge-themekit                  the kit
//   forge-themekit --apply <theme>  apply a built-in or saved theme (by id)
//                                   or a theme .json file, and exit
//   forge-themekit --list           the themes, one "id<TAB>name" per line
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

import 'apply.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (args.contains('--list')) {
    for (final t in [...builtInThemes, ...ForgeTheme.saved()]) {
      stdout.writeln('${t.id}\t${t.name}');
    }
    exit(0);
  }
  final i = args.indexOf('--apply');
  if (i >= 0) {
    final want = i + 1 < args.length ? args[i + 1] : '';
    final theme = _find(want);
    if (theme == null) {
      stderr.writeln('forge-themekit: no theme "$want" '
          '(${[...builtInThemes, ...ForgeTheme.saved()].map((t) => t.id).join(', ')})');
      exit(1);
    }
    await Applier().all(theme);
    stdout.writeln('applied ${theme.name}');
    exit(0);
  }
  runApp(const ThemeKitApp());
}

ForgeTheme? _find(String want) {
  for (final t in [...builtInThemes, ...ForgeTheme.saved()]) {
    if (t.id == want || t.name.toLowerCase() == want.toLowerCase()) return t;
  }
  final f = File(want);
  if (want.endsWith('.json') && f.existsSync()) {
    try {
      return ForgeTheme.fromJson(jsonDecode(f.readAsStringSync()) as Map<String, dynamic>);
    } catch (_) {}
  }
  return null;
}

class ThemeKitApp extends StatefulWidget {
  const ThemeKitApp({super.key});

  @override
  State<ThemeKitApp> createState() => _ThemeKitAppState();
}

class _ThemeKitAppState extends State<ThemeKitApp> {
  final _applier = Applier();
  late ForgeTheme _theme = ForgeTheme.current() ?? ForgePalette.current().theme;
  List<ForgeTheme> _saved = ForgeTheme.saved();
  Timer? _glassTimer;
  bool _busy = false;
  bool _pendingColours = false;

  ForgePalette get _p => ForgePalette.of(_theme);

  /// The preset the current settings came from (null once edited).
  String? get _selectedId {
    for (final t in [...builtInThemes, ..._saved]) {
      if (t.id == _theme.id && _same(t, _theme)) return t.id;
    }
    return null;
  }

  static bool _same(ForgeTheme a, ForgeTheme b) {
    final ja = a.toJson()..remove('name');
    final jb = b.toJson()..remove('name');
    return ja.toString() == jb.toString();
  }

  // --- Applying -------------------------------------------------------------

  void _edit(ForgeTheme t, {bool glass = false, bool colours = false}) {
    setState(() => _theme = t.id == 'custom' ? t : t.copyWith(id: 'custom', name: 'Custom'));
    if (glass) {
      _glassTimer?.cancel();
      _glassTimer = Timer(const Duration(milliseconds: 140), () => _applier.glass(_theme));
    }
    if (colours) _applyColours();
  }

  Future<void> _applyColours() async {
    if (_busy) {
      _pendingColours = true;
      return;
    }
    setState(() => _busy = true);
    try {
      await _applier.colours(_theme);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (_pendingColours) {
      _pendingColours = false;
      _applyColours();
    }
  }

  Future<void> _pick(ForgeTheme t) async {
    setState(() {
      _theme = t;
      _busy = true;
    });
    try {
      await _applier.all(t);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveAs() async {
    final name = await showDialog<String>(
      context: _navigator.currentContext!,
      builder: (context) => _NameDialog(palette: _p, initial: _theme.id == 'custom' ? '' : _theme.name),
    );
    if (name == null || name.trim().isEmpty) return;
    final id = name.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    final t = _theme.copyWith(id: 'user-$id', name: name.trim());
    t.writeTo(File('${ForgeTheme.savedDir.path}/${t.id}.json'));
    t.writeTo(ForgeTheme.currentFile);
    setState(() {
      _theme = t;
      _saved = ForgeTheme.saved();
    });
  }

  void _delete(ForgeTheme t) {
    final f = File('${ForgeTheme.savedDir.path}/${t.id}.json');
    if (f.existsSync()) f.deleteSync();
    setState(() => _saved = ForgeTheme.saved());
  }

  final _navigator = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    final p = _p;
    return MaterialApp(
      navigatorKey: _navigator,
      debugShowCheckedModeBanner: false,
      title: 'Forge Theming Kit',
      color: Colors.transparent,
      theme: p.materialTheme(),
      home: Scaffold(
        backgroundColor: p.window,
        body: Row(children: [
          _Gallery(
            palette: p,
            selectedId: _selectedId,
            saved: _saved,
            onPick: _pick,
            onDelete: _delete,
          ),
          Expanded(child: _controls(p)),
        ]),
      ),
    );
  }

  Widget _controls(ForgePalette p) {
    final t = _theme;
    String pct(double v) => '${v.round()}%';
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(28, 22, 28, 12),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.name,
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: p.text)),
              Text(_busy ? 'Applying…' : 'Applied to the desktop as you change it',
                  style: TextStyle(fontSize: 13, color: p.dimText)),
            ]),
          ),
          PillButton(
              palette: p,
              label: 'Save as theme',
              icon: Icons.bookmark_add_rounded,
              filled: true,
              onTap: _saveAs),
        ]),
      ),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 28),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _Preview(theme: t),
            ),
            _section(p, 'Colour'),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
              child: Row(children: [
                Text('Mode', style: TextStyle(color: p.text, fontSize: 13.5, fontWeight: FontWeight.w600)),
                const Spacer(),
                Segmented<bool>(
                  palette: p,
                  options: const {true: 'Dark', false: 'Light'},
                  value: t.dark,
                  onChanged: (v) => _edit(t.copyWith(dark: v), colours: true),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
              child: Wrap(spacing: 10, runSpacing: 10, children: [
                for (final c in _accents)
                  _Swatch(
                    colour: c,
                    selected: c.toARGB32() == t.accent.toARGB32(),
                    onTap: () => _edit(t.copyWith(accent: c), colours: true),
                  ),
              ]),
            ),
            ForgeSlider(
              palette: p,
              label: 'Accent',
              value: HSLColor.fromColor(t.accent).hue,
              min: 0,
              max: 359,
              track: hueGradient,
              format: (v) => hex(t.accent),
              onChanged: (v) => _edit(t.copyWith(
                  accent: HSLColor.fromColor(t.accent).withHue(v).toColor())),
              onChangeEnd: (_) => _applyColours(),
            ),
            ForgeSlider(
              palette: p,
              label: 'Glass tint',
              value: t.tintHue,
              min: 0,
              max: 359,
              track: hueGradient,
              format: (v) => '${v.round()}°',
              hint: 'The colour the glass leans towards',
              onChanged: (v) => _edit(t.copyWith(tintHue: v)),
              onChangeEnd: (_) => _applyColours(),
            ),
            ForgeSlider(
              palette: p,
              label: 'Tint strength',
              value: t.tintStrength,
              min: 0,
              max: 2,
              format: (v) => v == 0 ? 'Neutral' : '${(v * 100).round()}%',
              hint: '0 is neutral grey glass, 100% is Forge Glass',
              onChanged: (v) => _edit(t.copyWith(tintStrength: v)),
              onChangeEnd: (_) => _applyColours(),
            ),
            _section(p, 'Liquid glass'),
            ForgeSlider(
              palette: p, label: 'Blur', value: t.blur.toDouble(), min: 1, max: 15, divisions: 14,
              hint: 'How frosted: low is clear glass, high is frosted',
              onChanged: (v) => _edit(t.copyWith(blur: v.round()), glass: true),
            ),
            ForgeSlider(
              palette: p, label: 'Vibrancy', value: t.saturation, min: 0.5, max: 2.5,
              format: (v) => '${(v * 100).round()}%',
              hint: 'How rich the colours behind the glass look',
              onChanged: (v) => _edit(t.copyWith(saturation: v), glass: true),
            ),
            ForgeSlider(
              palette: p, label: 'Lens width', value: t.lensWidth, min: 0, max: 4,
              format: (v) => v == 0 ? 'Off' : '${(v * 10).round()} px',
              hint: 'How far in from the edge the glass bends the background',
              onChanged: (v) => _edit(t.copyWith(lensWidth: v), glass: true),
            ),
            ForgeSlider(
              palette: p, label: 'Lens strength', value: t.lensStrength.toDouble(), min: 0, max: 20,
              divisions: 20,
              hint: 'How much it bends',
              onChanged: (v) => _edit(t.copyWith(lensStrength: v.round()), glass: true),
            ),
            ForgeSlider(
              palette: p, label: 'Edge bevel', value: t.bevel.toDouble(), min: 5, max: 15,
              divisions: 10,
              hint: 'How rounded the glass edge is; high can look shaded',
              onChanged: (v) => _edit(t.copyWith(bevel: v.round()), glass: true),
            ),
            ForgeSlider(
              palette: p, label: 'Inner bending', value: t.innerBend.toDouble(), min: 0, max: 100,
              divisions: 100, format: (v) => v == 0 ? 'Off' : '${v.round()}%',
              hint: 'Bends the background across the pane too, not only at the edge',
              onChanged: (v) => _edit(t.copyWith(innerBend: v.round()), glass: true),
            ),
            ForgeSlider(
              palette: p, label: 'Colour split', value: t.colourSplit.toDouble(), min: 0, max: 20,
              divisions: 20, format: (v) => v == 0 ? 'Off' : v.round().toString(),
              hint: 'Prism-like red/blue fringes in the lens; off keeps edges clean',
              onChanged: (v) => _edit(t.copyWith(colourSplit: v.round()), glass: true),
            ),
            ForgeSlider(
              palette: p, label: 'Grain', value: t.grain.toDouble(), min: 0, max: 14,
              divisions: 14, format: (v) => v == 0 ? 'Off' : v.round().toString(),
              hint: 'A fine noise texture over the frost',
              onChanged: (v) => _edit(t.copyWith(grain: v.round()), glass: true),
            ),
            _section(p, 'Surfaces'),
            ForgeSlider(
              palette: p, label: 'Windows', value: t.windowOpacity.toDouble(), min: 15, max: 100,
              divisions: 85, format: pct,
              hint: 'How solid window backgrounds are; lower shows more glass',
              onChanged: (v) => _edit(t.copyWith(windowOpacity: v.round())),
              onChangeEnd: (_) => _applyColours(),
            ),
            ForgeSlider(
              palette: p, label: 'Menus and toolbars', value: t.menuOpacity.toDouble(), min: 15,
              max: 100, divisions: 85, format: pct,
              hint: 'Apps opened after the change pick it up',
              onChanged: (v) => _edit(t.copyWith(menuOpacity: v.round())),
              onChangeEnd: (_) => _applyColours(),
            ),
            ForgeSlider(
              palette: p, label: 'Terminal', value: t.terminalOpacity.toDouble(), min: 15,
              max: 100, divisions: 85, format: pct,
              onChanged: (v) => _edit(t.copyWith(terminalOpacity: v.round())),
              onChangeEnd: (_) => _applyColours(),
            ),
            _section(p, 'Shape'),
            ForgeSlider(
              palette: p, label: 'Corner radius', value: t.cornerRadius.toDouble(), min: 0, max: 24,
              divisions: 24, format: (v) => '${v.round()} px',
              hint: 'Windows and menus (the dock keeps its own)',
              onChanged: (v) => _edit(t.copyWith(cornerRadius: v.round()), glass: true),
            ),
          ],
        ),
      ),
    ]);
  }

  Widget _section(ForgePalette p, String text) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: SectionLabel(text, palette: p),
      );
}

const _accents = [
  Color(0xFF7F8EF5), Color(0xFF5CC8FF), Color(0xFF4FE3C1), Color(0xFF22A884),
  Color(0xFFA3D65C), Color(0xFFFFC145), Color(0xFFFF8A4C), Color(0xFFFF5C6C),
  Color(0xFFFF7AA8), Color(0xFFB57BFF),
];

class _Swatch extends StatelessWidget {
  const _Swatch({required this.colour, required this.selected, required this.onTap});

  final Color colour;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: colour,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: selected ? 3 : 0),
          boxShadow: [BoxShadow(color: colour.withValues(alpha: 0.5), blurRadius: selected ? 10 : 0)],
        ),
      ),
    );
  }
}

/// A small mock of the theme: wallpaper-like backdrop, a window with a
/// sidebar, text and an accent button, in the theme's own colours.
class _Preview extends StatelessWidget {
  const _Preview({required this.theme});

  final ForgeTheme theme;

  @override
  Widget build(BuildContext context) {
    final p = ForgePalette.of(theme);
    final c = ThemeColours(theme);
    final r = theme.cornerRadius.toDouble();
    final backdrop = theme.dark
        ? [c.tint(const Color(0xFF2B2F6E)), c.tint(const Color(0xFF6B3A6E)), const Color(0xFFB0685A)]
        : [c.tint(const Color(0xFFB8C2F2)), c.tint(const Color(0xFFE6C3E8)), const Color(0xFFF2CFB8)];
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 190,
        decoration: BoxDecoration(gradient: LinearGradient(colors: backdrop)),
        padding: const EdgeInsets.fromLTRB(40, 26, 40, 26),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(r),
          child: Container(
            color: c.tint(c.base.window.$1).withAlpha(c.windowAlpha + 40),
            child: Row(children: [
              Container(
                width: 120,
                color: p.sidebar,
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final (i, label) in ['Home', 'Music', 'Photos'].indexed)
                    Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: i == 0 ? p.accent.withValues(alpha: 0.88) : Colors.transparent,
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(label,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: i == 0 ? p.onAccent : p.text)),
                    ),
                ]),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(theme.name,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text)),
                    const SizedBox(height: 4),
                    Text('Liquid glass, your colours.',
                        style: TextStyle(fontSize: 12, color: p.dimText)),
                    const Spacer(),
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(16)),
                        child: Text('Open',
                            style: TextStyle(color: p.onAccent, fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(width: 8),
                      Text('Link', style: TextStyle(color: c.link, fontSize: 12)),
                    ]),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The themes: built-in ones and the user's own.
class _Gallery extends StatelessWidget {
  const _Gallery({
    required this.palette,
    required this.selectedId,
    required this.saved,
    required this.onPick,
    required this.onDelete,
  });

  final ForgePalette palette;
  final String? selectedId;
  final List<ForgeTheme> saved;
  final void Function(ForgeTheme) onPick;
  final void Function(ForgeTheme) onDelete;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    Widget grid(List<ForgeTheme> themes, {bool deletable = false}) => GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.05,
          children: [
            for (final t in themes)
              _ThemeTile(
                theme: t,
                palette: p,
                selected: t.id == selectedId,
                onTap: () => onPick(t),
                onDelete: deletable ? () => onDelete(t) : null,
              ),
          ],
        );
    return Container(
      width: 300,
      color: p.sidebar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
        children: [
          Row(children: [
            Icon(Icons.palette_rounded, color: p.accent, size: 24),
            const SizedBox(width: 10),
            Text('Theming Kit',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: p.text)),
          ]),
          SectionLabel('Themes', palette: p),
          grid(builtInThemes),
          if (saved.isNotEmpty) ...[
            SectionLabel('Your themes', palette: p),
            grid(saved, deletable: true),
          ],
        ],
      ),
    );
  }
}

class _ThemeTile extends StatelessWidget {
  const _ThemeTile({
    required this.theme,
    required this.palette,
    required this.selected,
    required this.onTap,
    this.onDelete,
  });

  final ForgeTheme theme;
  final ForgePalette palette;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final c = ThemeColours(theme);
    final glass = c.tint(c.base.window.$1);
    return GlassCard(
      palette: palette,
      selected: selected,
      padding: const EdgeInsets.all(8),
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [glass, c.tint(c.base.complementary.$1), theme.accent.withValues(alpha: 0.7)],
                stops: const [0, 0.6, 1],
              ),
            ),
            child: Stack(children: [
              Positioned(
                left: 10,
                bottom: 10,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(color: theme.accent, shape: BoxShape.circle),
                ),
              ),
              if (onDelete != null)
                Positioned(
                  right: 2,
                  top: 2,
                  child: IconButton(
                    iconSize: 16,
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Delete theme',
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    onPressed: onDelete,
                  ),
                ),
            ]),
          ),
        ),
        const SizedBox(height: 6),
        Text(theme.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: palette.text)),
      ]),
    );
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.palette, required this.initial});

  final ForgePalette palette;
  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _name = TextEditingController(text: widget.initial);

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    return AlertDialog(
      backgroundColor: p.dark ? const Color(0xFF1E2139) : const Color(0xFFF7F6FC),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text('Save theme', style: TextStyle(color: p.text, fontWeight: FontWeight.w700)),
      content: TextField(
        controller: _name,
        autofocus: true,
        style: TextStyle(color: p.text),
        decoration: InputDecoration(hintText: 'Name', hintStyle: TextStyle(color: p.dimText)),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        PillButton(palette: p, label: 'Cancel', onTap: () => Navigator.pop(context)),
        PillButton(palette: p, label: 'Save', filled: true, onTap: () => Navigator.pop(context, _name.text)),
      ],
    );
  }
}
