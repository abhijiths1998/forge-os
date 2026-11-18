// Desktop mode: a sidebar of shelves, a hero panel for the game in focus and
// a grid of covers, all over a blurred backdrop of that game. Every part is
// reachable with the pad: d-pad moves, A opens, LB/RB change shelf,
// Y searches, X favourites, View switches to couch mode.
import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

import '../models.dart';
import '../pad.dart';
import '../store.dart';
import '../widgets/cover_tile.dart';
import '../widgets/glass.dart';
import '../widgets/osk.dart';
import '../window.dart';
import 'editor_screen.dart';
import 'game_screen.dart';
import 'runners_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.store, required this.palette, required this.onCouch});

  final GamingStore store;
  final ForgePalette palette;
  final VoidCallback onCouch;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

const _shelves = [
  (LibraryFilter.all, Icons.apps_rounded),
  (LibraryFilter.recent, Icons.history_rounded),
  (LibraryFilter.favorites, Icons.star_rounded),
  (LibraryFilter.steam, Icons.cloud_rounded),
  (LibraryFilter.heroic, Icons.shield_rounded),
  (LibraryFilter.lutris, Icons.wine_bar_rounded),
  (LibraryFilter.local, Icons.folder_special_rounded),
  (LibraryFilter.hidden, Icons.visibility_off_rounded),
];

class _LibraryScreenState extends State<LibraryScreen> {
  LibraryFilter _filter = LibraryFilter.all;
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _gridFocus = FocusScopeNode(debugLabel: 'grid');
  String? _focusedId;

  GamingStore get store => widget.store;
  ForgePalette get p => widget.palette;

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    _gridFocus.dispose();
    super.dispose();
  }

  void _cycleShelf(int step) {
    final i = _shelves.indexWhere((s) => s.$1 == _filter);
    setState(() => _filter = _shelves[(i + step) % _shelves.length].$1);
  }

  Game? _focusedGame(List<Game> shown) {
    final id = _focusedId;
    if (id != null) {
      final g = store.game(id);
      if (g != null) return g;
    }
    return shown.isEmpty ? null : shown.first;
  }

  void _open(Game g) => Navigator.of(context).push(fadeRoute(GameScreen(store: store, palette: p, gameId: g.id)));

  void _toggleFavourite() {
    final g = _focusedId == null ? null : store.game(_focusedId!);
    if (g != null) store.setFavorite(g, !g.favorite);
  }

  Future<void> _addGame() async {
    await Navigator.of(context).push(fadeRoute(EditorScreen(store: store, palette: p)));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final shown = selectGames(store.games, _filter, _search.text);
        final focused = _focusedGame(shown);
        return PadShortcuts(
          bindings: padBindings({
            PadButton.lb: () => _cycleShelf(-1),
            PadButton.rb: () => _cycleShelf(1),
            PadButton.y: () => _searchFocus.requestFocus(),
            PadButton.x: _toggleFavourite,
            PadButton.back: widget.onCouch,
            PadButton.start: _addGame,
          }),
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Stack(fit: StackFit.expand, children: [
              Backdrop(palette: p, game: focused),
              Column(children: [
                TitleStrip(palette: p, trailing: [
                  ExcludeFocus(
                    child: TextButton.icon(
                      onPressed: widget.onCouch,
                      icon: Icon(Icons.tv_rounded, size: 17, color: p.text),
                      label: Text('Couch mode', style: TextStyle(color: p.text, fontSize: 12.5)),
                    ),
                  ),
                  const SizedBox(width: 6),
                ]),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      SizedBox(width: 236, child: FocusTraversalGroup(child: _sidebar())),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          FocusTraversalGroup(child: _toolbar()),
                          const SizedBox(height: 16),
                          if (focused != null) _hero(focused),
                          if (focused != null) const SizedBox(height: 16),
                          Expanded(child: FocusTraversalGroup(child: _grid(shown))),
                        ]),
                      ),
                    ]),
                  ),
                ),
                if (store.pads.isNotEmpty) _hints(),
              ]),
            ]),
          ),
        );
      },
    );
  }

  Widget _sidebar() {
    int count(LibraryFilter f) => selectGames(store.games, f, '').length;
    return Glass(
      palette: p,
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 10),
          child: Text('LIBRARY',
              style: TextStyle(fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w800, color: p.dimText)),
        ),
        for (final (f, icon) in _shelves)
          if (f != LibraryFilter.hidden || count(f) > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: _NavItem(
                palette: p,
                icon: icon,
                label: f.label,
                count: count(f),
                selected: _filter == f,
                onTap: () => setState(() => _filter = f),
              ),
            ),
        const Spacer(),
        _NavItem(
          palette: p,
          icon: Icons.add_circle_rounded,
          label: 'Add a game',
          onTap: _addGame,
        ),
        const SizedBox(height: 4),
        _NavItem(
          palette: p,
          icon: Icons.memory_rounded,
          label: 'Proton & Wine',
          onTap: () => Navigator.of(context).push(fadeRoute(RunnersScreen(store: store, palette: p))),
        ),
        const SizedBox(height: 12),
        _padStatus(),
      ]),
    );
  }

  Widget _padStatus() {
    final pads = store.pads.values.toList();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        Icon(Icons.gamepad_rounded, size: 20, color: pads.isEmpty ? p.dimText : p.positive),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            !store.connected
                ? 'Game service offline'
                : pads.isEmpty
                    ? 'No controller'
                    : pads.length == 1
                        ? pads.first.name
                        : '${pads.length} controllers',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: p.text.withValues(alpha: 0.85)),
          ),
        ),
      ]),
    );
  }

  Widget _toolbar() {
    return Row(children: [
      Expanded(
        child: GlassField(
          palette: p,
          controller: _search,
          focusNode: _searchFocus,
          hint: 'Search your games',
          icon: Icons.search_rounded,
          onChanged: (_) => setState(() {}),
          trailing: _search.text.isEmpty
              ? null
              : ExcludeFocus(
                  child: IconButton(
                    icon: Icon(Icons.close_rounded, size: 16, color: p.dimText),
                    onPressed: () => setState(_search.clear),
                  ),
                ),
        ),
      ),
      const SizedBox(width: 12),
      GlassButton(
        palette: p,
        icon: Icons.refresh_rounded,
        label: 'Rescan',
        onPressed: store.connected ? () => store.refresh() : null,
      ),
    ]);
  }

  Widget _hero(Game g) {
    return SizedBox(
      height: 168,
      child: Glass(
        palette: p,
        padding: EdgeInsets.zero,
        child: Stack(fit: StackFit.expand, children: [
          // The game's wide art bleeding in from the right.
          Positioned.fill(
            left: 260,
            child: ShaderMask(
              shaderCallback: (r) => const LinearGradient(
                colors: [Color(0x00000000), Color(0xAA000000)],
                stops: [0, 0.45],
              ).createShader(r),
              blendMode: BlendMode.dstIn,
              child: GameArt(source: g.backdrop, title: g.title, placeholderText: false),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(sourceIcon(g.source), size: 14, color: p.dimText),
                const SizedBox(width: 6),
                Text(g.source.label.toUpperCase(),
                    style: TextStyle(fontSize: 11, letterSpacing: 1, color: p.dimText, fontWeight: FontWeight.w700)),
                if (g.running) ...[
                  const SizedBox(width: 10),
                  Text('● PLAYING',
                      style: TextStyle(fontSize: 11, color: p.positive, fontWeight: FontWeight.w800)),
                ],
              ]),
              const SizedBox(height: 6),
              Text(g.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: p.text, height: 1.1)),
              const SizedBox(height: 6),
              Text('${formatPlaytime(g.playtimeMinutes)}  ·  Last played ${formatLastPlayed(g.lastPlayed).toLowerCase()}',
                  style: TextStyle(fontSize: 13, color: p.text.withValues(alpha: 0.75))),
              const Spacer(),
              ExcludeFocus(
                // The grid tile is the pad's way in; these are for the mouse.
                child: Row(children: [
                  GlassButton(
                    palette: p,
                    filled: true,
                    icon: g.running ? Icons.stop_rounded : Icons.play_arrow_rounded,
                    label: g.running ? 'Stop' : 'Play',
                    onPressed: () => g.running ? store.stop(g) : store.launch(g),
                  ),
                  const SizedBox(width: 10),
                  GlassButton(palette: p, icon: Icons.info_outline_rounded, label: 'Details', onPressed: () => _open(g)),
                ]),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _grid(List<Game> shown) {
    if (store.loading) {
      return Center(child: CircularProgressIndicator(color: p.accent));
    }
    if (!store.connected && store.games.isEmpty) {
      return _message(Icons.cloud_off_rounded, 'Can\'t reach the game service',
          store.error ?? 'forge-gamed is not running.', 'Try again', () => store.refresh());
    }
    if (shown.isEmpty) {
      return _filter == LibraryFilter.all && _search.text.isEmpty
          ? _message(Icons.sports_esports_rounded, 'No games yet',
              'Install games with Steam, Heroic or Lutris, or add your own.', 'Add a game', _addGame)
          : _message(Icons.search_off_rounded, 'Nothing here', 'No games match.', null, null);
    }
    return FocusScope(
      node: _gridFocus,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(6, 10, 6, 24),
        clipBehavior: Clip.none,
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 190,
          childAspectRatio: 2 / 3,
          mainAxisSpacing: 22,
          crossAxisSpacing: 20,
        ),
        itemCount: shown.length,
        itemBuilder: (context, i) {
          final g = shown[i];
          return CoverTile(
            key: ValueKey(g.id),
            palette: p,
            game: g,
            autofocus: i == 0,
            busy: store.handedOff.contains(g.id),
            onActivate: () => _open(g),
            onFocus: (f) {
              if (f && _focusedId != g.id) setState(() => _focusedId = g.id);
            },
          );
        },
      ),
    );
  }

  Widget _message(IconData icon, String title, String body, String? action, VoidCallback? onAction) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Glass(
          palette: p,
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 44, color: p.accent),
            const SizedBox(height: 12),
            Text(title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: p.text)),
            const SizedBox(height: 6),
            Text(body, textAlign: TextAlign.center, style: TextStyle(color: p.dimText)),
            if (action != null) ...[
              const SizedBox(height: 18),
              GlassButton(palette: p, filled: true, label: action, onPressed: onAction, autofocus: true),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _hints() {
    final type = store.pads.values.first.type;
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 0, 26, 14),
      child: Align(
        alignment: Alignment.centerRight,
        child: PadHintBar(palette: p, type: type, hints: const [
          PadHint(PadButton.a, 'Open'),
          PadHint(PadButton.x, 'Favourite'),
          PadHint(PadButton.y, 'Search'),
          PadHint(PadButton.lb, 'Shelf', also: PadButton.rb),
          PadHint(PadButton.start, 'Add game'),
          PadHint(PadButton.back, 'Couch mode'),
        ]),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.palette,
    required this.icon,
    required this.label,
    required this.onTap,
    this.count,
    this.selected = false,
  });

  final ForgePalette palette;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final int? count;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Focusable(
      onActivate: onTap,
      builder: (context, focused, hovered) => FocusGlow(
        palette: p,
        focused: focused,
        hovered: false,
        radius: 12,
        scale: 1.02,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            gradient: selected
                ? LinearGradient(colors: [p.accent.withValues(alpha: 0.75), p.accent.withValues(alpha: 0.35)])
                : null,
            color: selected ? null : Colors.white.withValues(alpha: focused || hovered ? 0.12 : 0),
          ),
          child: Row(children: [
            Icon(icon, size: 18, color: selected ? p.onAccent : p.text.withValues(alpha: 0.85)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? p.onAccent : p.text,
                  )),
            ),
            if (count != null)
              Text('$count', style: TextStyle(fontSize: 12, color: selected ? p.onAccent : p.dimText)),
          ]),
        ),
      ),
    );
  }
}

/// Pages fade and rise slightly into place rather than slide.
Route<T> fadeRoute<T>(Widget page) => PageRouteBuilder<T>(
      // Opaque once in place: every page draws its own backdrop.
      opaque: true,
      transitionDuration: const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, _, _) => page,
      transitionsBuilder: (context, anim, _, child) {
        final a = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: a,
          child: ScaleTransition(scale: Tween(begin: 0.98, end: 1.0).animate(a), child: child),
        );
      },
    );
