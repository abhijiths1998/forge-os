// Forge Arcade: the launcher for the forge-games collection. The games and
// their covers come from /usr/share/forge-games/games.json (see
// packages/forge-games); this is only the window.
import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

import 'arcade.dart';
import 'gamepad.dart';
import 'games.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final games = await loadGames();
  runApp(ArcadeApp(games: games));
}

class ArcadeApp extends StatelessWidget {
  const ArcadeApp({super.key, required this.games});

  final List<Game> games;

  @override
  Widget build(BuildContext context) {
    final p = ForgePalette.current();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Forge Arcade',
      color: Colors.transparent,
      theme: p.materialTheme(),
      home: ArcadeHome(games: games, palette: p, pad: padActions()),
    );
  }
}
