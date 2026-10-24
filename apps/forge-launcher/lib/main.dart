// Forge Launcher: the Meta+Space command bar. A Forge Glass card with a
// search field and results; see sources.dart for what it finds.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'native.dart';
import 'palette.dart';
import 'sources.dart';

const _searchHeight = 64.0;
const _rowHeight = 52.0;
const _maxRows = 8;
const _radius = 14.0; // KWin's window corner radius (kwinrc [Round-Corners])

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LauncherApp());
}

class LauncherApp extends StatefulWidget {
  const LauncherApp({super.key});

  @override
  State<LauncherApp> createState() => _LauncherAppState();
}

class _LauncherAppState extends State<LauncherApp> {
  final _usage = Usage();
  late final _sources = Sources(_usage);
  final _query = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();

  Palette _palette = Palette.current();
  List<Result> _results = [];
  int _selected = 0;
  int _searchId = 0;
  Timer? _fileTimer;
  String _pending = '';

  @override
  void initState() {
    super.initState();
    Native.onEvent((event) {
      if (event == 'shown') _onShown();
    });
    // FORGE_LAUNCHER_QUERY pre-fills the search on start, for testing.
    _pending = Platform.environment['FORGE_LAUNCHER_QUERY'] ?? '';
    _sources.reloadApps().then((_) => _update(_pending));
  }

  Future<void> _onShown() async {
    setState(() => _palette = Palette.current());
    _query.text = _pending;
    _pending = '';
    await _sources.reloadApps();
    _update(_query.text);
    _focus.requestFocus();
  }

  void _update(String text) {
    final id = ++_searchId;
    _fileTimer?.cancel();
    setState(() {
      _results = _sources.search(text);
      _selected = 0;
    });
    _resize();
    // Files are slower (a Baloo query): add them once typing pauses, just
    // above the web search row.
    _fileTimer = Timer(const Duration(milliseconds: 180), () async {
      final files = await _sources.files(text);
      if (files.isEmpty || id != _searchId) return;
      setState(() {
        final web = _results.isNotEmpty && _results.last.kind == Kind.web
            ? _results.removeLast()
            : null;
        _results.addAll(files);
        if (web != null) _results.add(web);
      });
      _resize();
    });
  }

  void _resize() {
    final rows = _results.length.clamp(0, _maxRows);
    final height =
        _searchHeight + (rows == 0 ? 0 : 1 + 16 + rows * _rowHeight);
    Native.setHeight(height.round());
  }

  Future<void> _activate(int index) async {
    if (index < 0 || index >= _results.length) return;
    final r = _results[index];
    _usage.record(r.key);
    await Native.hide();
    try {
      await r.run();
    } catch (_) {
      // nothing useful to show from a hidden launcher
    }
  }

  void _move(int delta) {
    if (_results.isEmpty) return;
    setState(() {
      _selected = (_selected + delta) % _results.length;
    });
    // Keep the selection in view.
    final top = _selected * _rowHeight;
    final view = _scroll.hasClients ? _scroll.position : null;
    if (view == null) return;
    if (top < view.pixels) {
      _scroll.jumpTo(top);
    } else if (top + _rowHeight > view.pixels + view.viewportDimension) {
      _scroll.jumpTo(top + _rowHeight - view.viewportDimension);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      if (_query.text.isNotEmpty) {
        _query.clear();
        _update('');
      } else {
        Native.hide();
      }
    } else if (key == LogicalKeyboardKey.arrowDown ||
        (key == LogicalKeyboardKey.tab &&
            !HardwareKeyboard.instance.isShiftPressed)) {
      _move(1);
    } else if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.tab) {
      _move(-1);
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _activate(_selected);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final p = _palette;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      color: Colors.transparent,
      theme: ThemeData(
        fontFamily: fontFamily,
        brightness: p.dark ? Brightness.dark : Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: p.accent,
          brightness: p.dark ? Brightness.dark : Brightness.light,
        ),
        textSelectionTheme: TextSelectionThemeData(
          cursorColor: p.accent,
          selectionColor: p.accent.withValues(alpha: 0.35),
        ),
      ),
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: Container(
          decoration: BoxDecoration(
            color: p.surface,
            // No outline: the glass runs to the edge, like every window.
            borderRadius: BorderRadius.circular(_radius),
          ),
          child: Column(
            children: [
              _searchField(p),
              if (_results.isNotEmpty) ...[
                Divider(height: 1, thickness: 1, color: p.rim),
                Expanded(child: _list(p)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _searchField(Palette p) {
    return SizedBox(
      height: _searchHeight - 2,
      child: Row(
        children: [
          const SizedBox(width: 20),
          Icon(Icons.search_rounded, color: p.dimText, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Focus(
              onKeyEvent: _onKey,
              child: TextField(
                controller: _query,
                focusNode: _focus,
                autofocus: true,
                onChanged: _update,
                style: TextStyle(
                    fontSize: 20, color: p.text, fontWeight: FontWeight.w400),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Search apps, files, settings…',
                  hintStyle: TextStyle(color: p.dimText),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 20),
            child: Text('>  run    ?  web',
                style: TextStyle(fontSize: 12, color: p.dimText)),
          ),
        ],
      ),
    );
  }

  Widget _list(Palette p) {
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.all(8),
      itemExtent: _rowHeight,
      itemCount: _results.length,
      itemBuilder: (context, i) => _ResultRow(
        result: _results[i],
        selected: i == _selected,
        palette: p,
        onHover: () => setState(() => _selected = i),
        onTap: () => _activate(i),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.result,
    required this.selected,
    required this.palette,
    required this.onHover,
    required this.onTap,
  });

  final Result result;
  final bool selected;
  final Palette palette;
  final VoidCallback onHover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final fg = selected ? p.onAccent : p.text;
    final dim = selected ? p.onAccent.withValues(alpha: 0.8) : p.dimText;
    return MouseRegion(
      onHover: (_) => selected ? null : onHover(),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          decoration: BoxDecoration(
            color: selected ? p.accent.withValues(alpha: 0.88) : null,
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              _Icon(appId: result.appId, name: result.iconName),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(result.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: fg)),
                    if (result.subtitle.isNotEmpty)
                      Text(result.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: dim)),
                  ],
                ),
              ),
              Text(kindLabels[result.kind]!,
                  style: TextStyle(fontSize: 12, color: dim)),
            ],
          ),
        ),
      ),
    );
  }
}

/// An icon from the desktop's icon theme, via the GTK runner.
class _Icon extends StatelessWidget {
  const _Icon({this.appId, this.name});

  final String? appId;
  final String? name;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 32,
      child: FutureBuilder<Uint8List?>(
        future: Native.icon(app: appId, name: name, size: 32),
        builder: (context, snap) => snap.data == null
            ? const SizedBox()
            : Image.memory(snap.data!,
                width: 32, height: 32, filterQuality: FilterQuality.medium),
      ),
    );
  }
}
