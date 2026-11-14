// The Arcade window: a grid of covers on the left, the chosen game on the
// right. Arrows move, Enter plays, Esc quits; a gamepad does the same.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forge_ui/forge_ui.dart';

import 'gamepad.dart';
import 'games.dart';
import 'scores.dart';
import 'title_strip.dart';

/// Where the selection goes for an arrow key in a grid of [columns].
/// Down from a short last row lands on its last card rather than nowhere.
int moveSelection(int index, int count, int columns, LogicalKeyboardKey key) {
  if (count == 0) return 0;
  final cols = columns < 1 ? 1 : columns;
  final next = switch (key) {
    LogicalKeyboardKey.arrowLeft => index - 1,
    LogicalKeyboardKey.arrowRight => index + 1,
    LogicalKeyboardKey.arrowUp => index - cols,
    LogicalKeyboardKey.arrowDown => index + cols,
    _ => index,
  };
  if (key == LogicalKeyboardKey.arrowDown && next >= count) {
    return index ~/ cols < (count - 1) ~/ cols ? count - 1 : index;
  }
  if (next < 0 || next >= count) return index;
  return next;
}

class ArcadeHome extends StatefulWidget {
  const ArcadeHome({
    super.key,
    required this.games,
    required this.palette,
    this.launch = launchGame,
    this.onQuit,
    this.loadScoresFor = loadScores,
    this.pad,
  });

  final List<Game> games;
  final ForgePalette palette;
  final Future<void> Function(Game) launch;
  final VoidCallback? onQuit;
  final Future<List<ScoreEntry>> Function(Game) loadScoresFor;

  /// Gamepad actions, if there is a pad.
  final Stream<PadAction>? pad;

  @override
  State<ArcadeHome> createState() => _ArcadeHomeState();
}

class _ArcadeHomeState extends State<ArcadeHome> with WidgetsBindingObserver {
  static const _cardWidth = 230.0;

  int _selected = 0;
  int _columns = 3;
  bool _active = true;
  String? _launching;
  String? _error;
  late Future<List<ScoreEntry>> _scores;
  StreamSubscription<PadAction>? _padSub;
  final _cardKeys = <int, GlobalKey>{};

  Game? get _game => widget.games.isEmpty ? null : widget.games[_selected];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scores = _loadScores();
    _padSub = widget.pad?.listen(_onPad);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _padSub?.cancel();
    super.dispose();
  }

  // While a game has focus the pad belongs to it, not to the Arcade.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
  }

  Future<List<ScoreEntry>> _loadScores() {
    final g = _game;
    return g == null ? Future.value(const []) : widget.loadScoresFor(g);
  }

  void _select(int i) {
    if (i == _selected) return;
    setState(() {
      _selected = i;
      _error = null;
      _scores = _loadScores();
    });
    final ctx = _cardKeys[i]?.currentContext;
    if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 150));
  }

  void _quit() => (widget.onQuit ?? () => exit(0))();

  Future<void> _play() async {
    final g = _game;
    if (g == null || _launching != null) return;
    setState(() {
      _launching = g.id;
      _error = null;
    });
    try {
      await widget.launch(g);
      // The game opens its own window; leave the message up while it does.
      await Future<void>.delayed(const Duration(seconds: 3));
    } on Exception catch (e) {
      if (mounted) setState(() => _error = 'Couldn\'t start ${g.name}: $e');
    }
    if (mounted) setState(() => _launching = null);
  }

  void _onPad(PadAction a) {
    if (!_active) return;
    switch (a) {
      case PadAction.select:
        _play();
      case PadAction.back:
        _quit();
      case PadAction.left:
        _select(moveSelection(_selected, widget.games.length, _columns, LogicalKeyboardKey.arrowLeft));
      case PadAction.right:
        _select(moveSelection(_selected, widget.games.length, _columns, LogicalKeyboardKey.arrowRight));
      case PadAction.up:
        _select(moveSelection(_selected, widget.games.length, _columns, LogicalKeyboardKey.arrowUp));
      case PadAction.down:
        _select(moveSelection(_selected, widget.games.length, _columns, LogicalKeyboardKey.arrowDown));
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final k = event.logicalKey;
    if (k == LogicalKeyboardKey.escape) {
      _quit();
    } else if (k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.numpadEnter ||
        k == LogicalKeyboardKey.space) {
      _play();
    } else if (const [
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowDown,
    ].contains(k)) {
      _select(moveSelection(_selected, widget.games.length, _columns, k));
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: p.window,
        body: Column(
          children: [
            TitleStrip(palette: p, onClose: widget.onQuit),
            Expanded(
              child: widget.games.isEmpty
                  ? _empty(p)
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _grid(p)),
                          const SizedBox(width: 20),
                          SizedBox(width: 360, child: _details(p, _game!)),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty(ForgePalette p) => Center(
        child: Text('No games installed. Is forge-games installed?',
            style: TextStyle(color: p.dimText, fontSize: 15)),
      );

  Widget _grid(ForgePalette p) {
    return LayoutBuilder(builder: (context, box) {
      _columns = (box.maxWidth / _cardWidth).floor().clamp(1, 6);
      return GridView.builder(
        padding: const EdgeInsets.only(right: 4),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: _columns,
          mainAxisSpacing: 14,
          crossAxisSpacing: 14,
          childAspectRatio: 1.42,
        ),
        itemCount: widget.games.length,
        itemBuilder: (context, i) => _card(p, i),
      );
    });
  }

  Widget _card(ForgePalette p, int i) {
    final g = widget.games[i];
    return GlassCard(
      key: _cardKeys.putIfAbsent(i, GlobalKey.new),
      palette: p,
      selected: i == _selected,
      padding: const EdgeInsets.all(8),
      onTap: () => _select(i),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: Cover(game: g, palette: p, radius: 8)),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 2),
            child: Text(g.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: p.text)),
          ),
        ],
      ),
    );
  }

  Widget _details(ForgePalette p, Game g) {
    return GlassCard(
      palette: p,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                AspectRatio(aspectRatio: 1.6, child: Cover(game: g, palette: p, radius: 10)),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(
                    child: Text(g.name,
                        style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: p.text)),
                  ),
                  if (g.needsGpu) GpuBadge(palette: p),
                ]),
                const SizedBox(height: 8),
                Text(g.description,
                    style: TextStyle(fontSize: 13, height: 1.4, color: p.text.withValues(alpha: 0.8))),
                SectionLabel('Controls', palette: p),
                ControlsTable(controls: g.controls, palette: p),
                if (g.highScoreFile != null) ...[
                  SectionLabel(g.lowerIsBetter ? 'Best round' : 'High scores', palette: p),
                  _scoresView(p, g),
                ],
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!, style: TextStyle(fontSize: 12, color: p.negative)),
            ),
          PlayButton(
            palette: p,
            label: _launching == g.id ? 'Starting...' : 'Play',
            onTap: _launching == null ? _play : null,
          ),
        ],
      ),
    );
  }

  Widget _scoresView(ForgePalette p, Game g) {
    return FutureBuilder<List<ScoreEntry>>(
      future: _scores,
      builder: (context, snap) {
        final list = snap.data ?? const [];
        if (list.isEmpty) {
          return Text(snap.connectionState == ConnectionState.done ? 'Nothing yet.' : '',
              style: TextStyle(fontSize: 12.5, color: p.dimText));
        }
        final shown = list.take(5).toList();
        return Column(
          children: [
            for (var i = 0; i < shown.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  SizedBox(
                    width: 22,
                    child: Text('${i + 1}.', style: TextStyle(fontSize: 12.5, color: p.dimText)),
                  ),
                  Expanded(
                    child: Text(shown[i].name ?? (g.lowerIsBetter ? 'Strokes' : 'Best'),
                        style: TextStyle(fontSize: 12.5, color: p.text)),
                  ),
                  Text('${shown[i].score}',
                      style: TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w700, color: p.text)),
                ]),
              ),
          ],
        );
      },
    );
  }
}

/// A game's cover, or a plain panel with its name while the file is missing.
class Cover extends StatelessWidget {
  const Cover({super.key, required this.game, required this.palette, this.radius = 8});

  final Game game;
  final ForgePalette palette;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.file(
        File(game.cover),
        fit: BoxFit.cover,
        width: double.infinity,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, _, _) => ColoredBox(
          color: palette.hover,
          child: Center(
            child: Text(game.name,
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.dimText, fontWeight: FontWeight.w700)),
          ),
        ),
      ),
    );
  }
}

class GpuBadge extends StatelessWidget {
  const GpuBadge({super.key, required this.palette});
  final ForgePalette palette;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Needs a GPU with OpenGL 3.3',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: palette.accent.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text('Needs a GPU',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: palette.text)),
      ),
    );
  }
}

class ControlsTable extends StatelessWidget {
  const ControlsTable({super.key, required this.controls, required this.palette});

  final List<(String, String)> controls;
  final ForgePalette palette;

  @override
  Widget build(BuildContext context) {
    return Table(
      columnWidths: const {0: FlexColumnWidth(5), 1: FlexColumnWidth(6)},
      defaultVerticalAlignment: TableCellVerticalAlignment.top,
      children: [
        for (final (keys, action) in controls)
          TableRow(children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 6, right: 10),
              child: Text(keys,
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700, color: palette.text)),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(action, style: TextStyle(fontSize: 12, color: palette.text.withValues(alpha: 0.8))),
            ),
          ]),
      ],
    );
  }
}

class PlayButton extends StatelessWidget {
  const PlayButton({super.key, required this.palette, required this.label, this.onTap});

  final ForgePalette palette;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.6 : 1,
      child: Material(
        color: palette.accent,
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: onTap,
          child: SizedBox(
            height: 56,
            child: Center(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: palette.onAccent)),
            ),
          ),
        ),
      ),
    );
  }
}
