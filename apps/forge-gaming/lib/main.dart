// Forge Gaming: the Forge OS game library and launcher. This is the UI;
// forge-gamed (apps/forge-gamed, C++) scans libraries, launches games and
// reads the controllers. See docs/FORGE-GAMING.md.
//
//   forge-gaming           desktop mode
//   forge-gaming --couch   full-screen couch mode (what the Guide button opens)
import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

import 'src/app.dart';
import 'src/daemon.dart';
import 'src/store.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final daemon = DaemonClient();
  final store = GamingStore(daemon);
  runApp(ForgeGamingApp(
    store: store,
    palette: ForgePalette.current(),
    couch: args.contains('--couch'),
  ));
  try {
    // The store registers and loads when the connection comes up.
    await daemon.connect();
  } on DaemonError catch (e) {
    // The library shows "Can't reach the game service" with a retry.
    store.markOffline(e.message);
  }
}
