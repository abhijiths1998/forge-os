// One game: big art, play time, Play/Stop up front (focused, so A plays),
// then favourite, hide, edit and the last run's log. Used by both modes;
// couch mode only makes it bigger.
import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

import '../models.dart';
import '../pad.dart';
import '../store.dart';
import '../widgets/cover_tile.dart';
import '../widgets/glass.dart';
import '../window.dart';
import 'editor_screen.dart';
import 'library_screen.dart' show fadeRoute;

class GameScreen extends StatelessWidget {
  const GameScreen({
    super.key,
    required this.store,
    required this.palette,
    required this.gameId,
    this.couch = false,
  });

  final GamingStore store;
  final ForgePalette palette;
  final String gameId;
  final bool couch;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final g = store.game(gameId);
        if (g == null) {
          // Removed while open.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) Navigator.of(context).maybePop();
          });
          return const SizedBox.shrink();
        }
        final busy = store.handedOff.contains(g.id);
        return PadShortcuts(
          bindings: padBindings({
            PadButton.x: () => store.setFavorite(g, !g.favorite),
            PadButton.y: () => _showLog(context, g),
          }),
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Stack(fit: StackFit.expand, children: [
              Backdrop(palette: p, game: g, opacity: 0.75),
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (!couch) TitleStrip(palette: p),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(couch ? 80 : 40, couch ? 70 : 16, couch ? 80 : 40, 30),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SizedBox(
                        width: couch ? 300 : 230,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: AspectRatio(
                            aspectRatio: 2 / 3,
                            child: GameArt(source: g.cover, title: g.title),
                          ),
                        ),
                      ),
                      SizedBox(width: couch ? 48 : 32),
                      Expanded(child: _details(context, g, busy)),
                    ]),
                  ),
                ),
                if (store.pads.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.fromLTRB(40, 0, couch ? 80 : 40, couch ? 36 : 18),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: PadHintBar(palette: p, type: store.pads.values.first.type, hints: [
                        PadHint(PadButton.a, 'Select'),
                        PadHint(PadButton.x, g.favorite ? 'Unfavourite' : 'Favourite'),
                        const PadHint(PadButton.y, 'Log'),
                        const PadHint(PadButton.b, 'Back'),
                      ]),
                    ),
                  ),
              ]),
            ]),
          ),
        );
      },
    );
  }

  Widget _details(BuildContext context, Game g, bool busy) {
    final p = palette;
    final big = couch ? 1.25 : 1.0;
    return FocusTraversalGroup(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (!couch)
          Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: GlassButton(
              palette: p,
              icon: Icons.arrow_back_rounded,
              label: 'Library',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
        Row(children: [
          Icon(sourceIcon(g.source), size: 16 * big, color: p.dimText),
          const SizedBox(width: 8),
          Text(g.source.label.toUpperCase(),
              style: TextStyle(fontSize: 12 * big, letterSpacing: 1.2, color: p.dimText, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 8),
        Text(g.title,
            style: TextStyle(fontSize: 42 * big, fontWeight: FontWeight.w900, color: p.text, height: 1.05)),
        const SizedBox(height: 22),
        Wrap(spacing: 14, runSpacing: 14, children: [
          _stat(Icons.timer_outlined, 'Played', formatPlaytime(g.playtimeMinutes)),
          _stat(Icons.event_rounded, 'Last played', formatLastPlayed(g.lastPlayed)),
          if (g.settings != null)
            _stat(g.settings!.kind == GameKind.windows ? Icons.window_rounded : Icons.terminal_rounded, 'Runs with',
                _runsWith(g.settings!)),
        ]),
        const SizedBox(height: 30),
        Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
          GlassButton(
            palette: p,
            large: true,
            filled: true,
            autofocus: true,
            danger: g.running,
            icon: g.running ? Icons.stop_rounded : Icons.play_arrow_rounded,
            label: g.running ? 'Stop' : (busy ? 'Starting…' : 'Play'),
            onPressed: busy
                ? null
                : () {
                    if (g.running) {
                      store.stop(g);
                    } else {
                      store.rumble(strength: 0.5, ms: 140);
                      store.launch(g);
                    }
                  },
          ),
          GlassButton(
            palette: p,
            large: couch,
            icon: g.favorite ? Icons.star_rounded : Icons.star_outline_rounded,
            label: g.favorite ? 'Favourite' : 'Add to favourites',
            onPressed: () => store.setFavorite(g, !g.favorite),
          ),
          GlassButton(
            palette: p,
            large: couch,
            icon: g.hidden ? Icons.visibility_rounded : Icons.visibility_off_rounded,
            label: g.hidden ? 'Show in library' : 'Hide',
            onPressed: () => store.setHidden(g, !g.hidden),
          ),
          if (g.isLocal)
            GlassButton(
              palette: p,
              large: couch,
              icon: Icons.tune_rounded,
              label: 'Settings',
              onPressed: () => Navigator.of(context)
                  .push(fadeRoute(EditorScreen(store: store, palette: p, game: g))),
            ),
          GlassButton(
            palette: p,
            large: couch,
            icon: Icons.receipt_long_rounded,
            label: 'Log',
            onPressed: () => _showLog(context, g),
          ),
        ]),
        if (!g.isLocal)
          Padding(
            padding: const EdgeInsets.only(top: 22),
            child: Text(
              switch (g.source) {
                GameSource.steam => 'Starts through Steam. Set Proton and launch options in Steam.',
                GameSource.heroic => 'Starts through Heroic. Set Wine and launch options in Heroic.',
                GameSource.lutris => 'Starts through Lutris with its own settings.',
                GameSource.local => '',
              },
              style: TextStyle(color: p.dimText, fontSize: 13 * big),
            ),
          ),
      ]),
    );
  }

  String _runsWith(GameSettings s) {
    if (s.kind == GameKind.native) return 'Linux';
    final id = s.runner ?? store.defaultRunner;
    for (final r in store.runners) {
      if (r.id == id) return r.name;
    }
    return s.runner == null ? 'Default Proton' : 'Missing runner';
  }

  Widget _stat(IconData icon, String label, String value) {
    final p = palette;
    return Glass(
      palette: p,
      radius: 16,
      blur: 18,
      padding: EdgeInsets.symmetric(horizontal: couch ? 22 : 18, vertical: couch ? 16 : 12),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: couch ? 24 : 20, color: p.accent),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 11, color: p.dimText, fontWeight: FontWeight.w600)),
          Text(value, style: TextStyle(fontSize: couch ? 18 : 15, color: p.text, fontWeight: FontWeight.w700)),
        ]),
      ]),
    );
  }

  Future<void> _showLog(BuildContext context, Game g) async {
    final text = await store.log(g);
    if (!context.mounted) return;
    final scroll = ScrollController();
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (context) => PadShortcuts(
        // The stick scrolls the log rather than hunting for focus.
        bindings: padBindings({
          PadButton.down: () => scroll.animateTo((scroll.offset + 220).clamp(0, scroll.position.maxScrollExtent),
              duration: const Duration(milliseconds: 120), curve: Curves.easeOut),
          PadButton.up: () => scroll.animateTo((scroll.offset - 220).clamp(0, scroll.position.maxScrollExtent),
              duration: const Duration(milliseconds: 120), curve: Curves.easeOut),
        }),
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(48),
          child: Glass(
            palette: palette,
            strength: 1.6,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('${g.title} — last run',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: palette.text)),
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SingleChildScrollView(
                    controller: scroll,
                    reverse: false,
                    child: SelectableText(
                      text.isEmpty ? 'No output yet. Play the game once.' : text,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.white70),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: GlassButton(
                  palette: palette,
                  filled: true,
                  autofocus: true,
                  label: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
    scroll.dispose();
  }
}
