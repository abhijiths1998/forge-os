// Couch mode: full screen, made for the sofa. The game in focus fills the
// screen behind its title; shelves of covers along the bottom (Continue
// playing, Favourites, All games). A opens, X favourites, Y searches with the
// on-screen keyboard, Start opens the menu, B leaves couch mode.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

import '../models.dart';
import '../pad.dart';
import '../store.dart';
import '../widgets/cover_tile.dart';
import '../widgets/glass.dart';
import '../widgets/osk.dart';
import '../window.dart';
import 'game_screen.dart';
import 'library_screen.dart' show fadeRoute;

class CouchScreen extends StatefulWidget {
  const CouchScreen({super.key, required this.store, required this.palette, required this.onExit});

  final GamingStore store;
  final ForgePalette palette;

  /// Back to desktop mode.
  final VoidCallback onExit;

  @override
  State<CouchScreen> createState() => _CouchScreenState();
}

class _CouchScreenState extends State<CouchScreen> {
  String? _focusedId;
  String _query = '';
  late Timer _clock;
  DateTime _now = DateTime.now();

  GamingStore get store => widget.store;
  ForgePalette get p => widget.palette;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 15), (_) => setState(() => _now = DateTime.now()));
  }

  @override
  void dispose() {
    _clock.cancel();
    super.dispose();
  }

  void _open(Game g) =>
      Navigator.of(context).push(fadeRoute(GameScreen(store: store, palette: p, gameId: g.id, couch: true)));

  Future<void> _search() async {
    final q = await showPadKeyboard(context, palette: p, initial: _query, title: 'Search your games');
    if (q != null) setState(() => _query = q.trim());
  }

  void _toggleFavourite() {
    final g = _focusedId == null ? null : store.game(_focusedId!);
    if (g != null) store.setFavorite(g, !g.favorite);
  }

  Future<void> _menu() async {
    final choice = await showDialog<String>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Glass(
            palette: p,
            strength: 1.6,
            child: FocusTraversalGroup(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Forge Gaming', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: p.text)),
                const SizedBox(height: 16),
                for (final (id, icon, label) in [
                  ('desktop', Icons.desktop_windows_rounded, 'Desktop mode'),
                  ('rescan', Icons.refresh_rounded, 'Rescan library'),
                  ('quit', Icons.power_settings_new_rounded, 'Close Forge Gaming'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: GlassButton(
                      palette: p,
                      large: true,
                      icon: icon,
                      label: label,
                      autofocus: id == 'desktop',
                      onPressed: () => Navigator.pop(context, id),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
    switch (choice) {
      case 'desktop':
        widget.onExit();
      case 'rescan':
        store.refresh();
      case 'quit':
        windowCall('close');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final visible = store.games.where((g) => !g.hidden).toList();
        final shelves = <(String, List<Game>)>[
          if (_query.isNotEmpty) ('Results for “$_query”', selectGames(store.games, LibraryFilter.all, _query)),
          if (_query.isEmpty) ('Playing now', selectGames(store.games, LibraryFilter.playing, '')),
          if (_query.isEmpty) ('Continue playing', recentGames(store.games)),
          if (_query.isEmpty) ('Favourites', selectGames(store.games, LibraryFilter.favorites, '')),
          if (_query.isEmpty) ('All games', selectGames(store.games, LibraryFilter.all, '')),
        ].where((s) => s.$2.isNotEmpty || s.$1.startsWith('Results')).toList();
        Game? focused = _focusedId == null ? null : store.game(_focusedId!);
        focused ??= shelves.isNotEmpty && shelves.first.$2.isNotEmpty ? shelves.first.$2.first : null;

        return PadShortcuts(
          bindings: {
            PadButton.y: () {
              _search();
              return true;
            },
            PadButton.x: () {
              _toggleFavourite();
              return true;
            },
            PadButton.start: () {
              _menu();
              return true;
            },
            PadButton.back: () {
              widget.onExit();
              return true;
            },
            PadButton.b: () {
              // Clear a search first, then leave couch mode.
              if (_query.isNotEmpty) {
                setState(() => _query = '');
              } else {
                widget.onExit();
              }
              return true;
            },
          },
          child: Scaffold(
            backgroundColor: Colors.black,
            body: Stack(fit: StackFit.expand, children: [
              _hero(focused),
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _topBar(),
                Expanded(flex: 5, child: _focusInfo(focused)),
                SizedBox(
                  height: 352,
                  child: visible.isEmpty
                      ? _empty()
                      : ListView(
                          padding: const EdgeInsets.only(bottom: 20),
                          children: [for (final s in shelves) _shelf(s.$1, s.$2)],
                        ),
                ),
                _hints(),
              ]),
            ]),
          ),
        );
      },
    );
  }

  Widget _hero(Game? g) {
    return Stack(fit: StackFit.expand, children: [
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 500),
        child: g == null
            ? ColoredBox(key: const ValueKey('none'), color: p.window)
            : SizedBox.expand(
                key: ValueKey(g.id),
                child: GameArt(source: g.backdrop, title: g.title, placeholderText: false),
              ),
      ),
      // Fade the art into the shelves and behind the title.
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x66000000), Color(0x22000000), Color(0xCC000000), Color(0xF2000000)],
            stops: [0, 0.3, 0.62, 1],
          ),
        ),
      ),
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [Color(0xAA000000), Color(0x00000000)],
            stops: [0, 0.6],
          ),
        ),
      ),
    ]);
  }

  Widget _topBar() {
    final pads = store.pads.values.toList();
    final time = '${_now.hour.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(64, 34, 64, 0),
      child: Row(children: [
        Icon(Icons.sports_esports_rounded, color: p.accent, size: 30),
        const SizedBox(width: 12),
        const Text('Forge Gaming',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.3)),
        const Spacer(),
        Glass(
          palette: p,
          radius: 30,
          blur: 20,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          child: Row(children: [
            Icon(Icons.gamepad_rounded, size: 20, color: pads.isEmpty ? Colors.white54 : p.positive),
            if (pads.length > 1) Text(' ${pads.length}', style: const TextStyle(color: Colors.white)),
            const SizedBox(width: 16),
            if (store.anyRunning) ...[
              Icon(Icons.play_circle_fill_rounded, size: 20, color: p.positive),
              const SizedBox(width: 16),
            ],
            Text(time, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
          ]),
        ),
      ]),
    );
  }

  Widget _focusInfo(Game? g) {
    if (g == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(68, 0, 68, 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: [
        Row(children: [
          Icon(sourceIcon(g.source), size: 18, color: Colors.white70),
          const SizedBox(width: 8),
          Text(g.source.label.toUpperCase(),
              style: const TextStyle(color: Colors.white70, letterSpacing: 1.4, fontWeight: FontWeight.w700)),
          if (g.running) ...[
            const SizedBox(width: 14),
            Text('● PLAYING NOW', style: TextStyle(color: p.positive, fontWeight: FontWeight.w800)),
          ],
        ]),
        const SizedBox(height: 8),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          // Old and new title fade over each other from the same left edge.
          layoutBuilder: (current, previous) =>
              Stack(alignment: Alignment.bottomLeft, children: [...previous, ?current]),
          child: Text(g.title,
              key: ValueKey(g.id),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 64,
                height: 1.02,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                shadows: [Shadow(blurRadius: 30, color: Colors.black54)],
              )),
        ),
        const SizedBox(height: 12),
        Text('${formatPlaytime(g.playtimeMinutes)}   ·   Last played ${formatLastPlayed(g.lastPlayed).toLowerCase()}',
            style: const TextStyle(fontSize: 18, color: Colors.white70)),
      ]),
    );
  }

  Widget _shelf(String title, List<Game> games) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(68, 8, 68, 4),
          child: Text(title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
        ),
        SizedBox(
          height: 290,
          child: games.isEmpty
              ? const Padding(
                  padding: EdgeInsets.only(left: 68, top: 20),
                  child: Text('No games match.', style: TextStyle(color: Colors.white60, fontSize: 18)),
                )
              : FocusTraversalGroup(
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    padding: const EdgeInsets.symmetric(horizontal: 64, vertical: 22),
                    itemCount: games.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 22),
                    itemBuilder: (context, i) {
                      final g = games[i];
                      return SizedBox(
                        width: 164,
                        child: CoverTile(
                          palette: p,
                          game: g,
                          showTitle: false,
                          autofocus: i == 0 && title == _firstShelfTitle,
                          busy: store.handedOff.contains(g.id),
                          onActivate: () => _open(g),
                          onFocus: (f) {
                            if (f && _focusedId != g.id) setState(() => _focusedId = g.id);
                          },
                        ),
                      );
                    },
                  ),
                ),
        ),
      ]),
    );
  }

  String get _firstShelfTitle {
    if (_query.isNotEmpty) return 'Results for “$_query”';
    if (store.anyRunning) return 'Playing now';
    if (recentGames(store.games).isNotEmpty) return 'Continue playing';
    if (selectGames(store.games, LibraryFilter.favorites, '').isNotEmpty) return 'Favourites';
    return 'All games';
  }

  Widget _empty() => Center(
        child: Text(
          store.connected ? 'No games yet. Add some in desktop mode (Start → Desktop mode).' : 'Game service offline.',
          style: const TextStyle(color: Colors.white70, fontSize: 20),
        ),
      );

  Widget _hints() {
    final type = store.pads.isEmpty ? PadType.xbox : store.pads.values.first.type;
    return Padding(
      padding: const EdgeInsets.fromLTRB(68, 0, 68, 30),
      child: Row(children: [
        const Spacer(),
        PadHintBar(palette: p, type: type, hints: [
          const PadHint(PadButton.a, 'Open'),
          const PadHint(PadButton.x, 'Favourite'),
          const PadHint(PadButton.y, 'Search'),
          const PadHint(PadButton.start, 'Menu'),
          PadHint(PadButton.b, _query.isNotEmpty ? 'Clear search' : 'Desktop'),
          if (store.anyRunning) const PadHint(PadButton.guide, 'Back to game'),
        ]),
      ]),
    );
  }
}
