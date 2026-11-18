// Drives the whole app with pad presses, as forge-gamed would send them.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_gaming/src/app.dart';
import 'package:forge_gaming/src/pad.dart';
import 'package:forge_gaming/src/screens/couch_screen.dart';
import 'package:forge_gaming/src/screens/game_screen.dart';
import 'package:forge_gaming/src/screens/library_screen.dart';
import 'package:forge_gaming/src/store.dart';
import 'package:forge_gaming/src/widgets/cover_tile.dart';
import 'package:forge_ui/forge_ui.dart';

import 'fake_daemon.dart';

void main() {
  late FakeDaemon daemon;
  late GamingStore store;
  late StreamController<PadPress> pad;

  Future<void> start(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    daemon = FakeDaemon({
      'library.list': (_) => {
            'games': [
              gameJson('local:a', 'Alpha'),
              gameJson('local:b', 'Bravo'),
              gameJson('local:c', 'Charlie'),
            ]
          },
      'game.update': (p) => {'game': gameJson(p!['id'] as String, 'Alpha', favorite: p['favorite'] == true)},
      'system.info': (_) => {
            'thermal': {'available': true, 'profiles': ['balanced', 'custom', 'performance'], 'current': 'balanced'},
            'quiet': {'available': true},
          },
    });
    store = GamingStore(daemon);
    await store.init();
    pad = StreamController<PadPress>();
    await tester.pumpWidget(ForgeGamingApp(store: store, palette: ForgePalette.of(forgeGlass), pad: pad.stream));
    await tester.pumpAndSettle();
  }

  Future<void> press(WidgetTester tester, PadButton b) async {
    pad.add(PadPress(b));
    await tester.pump();
    await tester.pumpAndSettle();
  }

  String? focusedTitle() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    return ctx?.findAncestorWidgetOfExactType<CoverTile>()?.game.title;
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  }

  testWidgets('d-pad moves focus, A opens, X favourites, B goes back', (tester) async {
    await start(tester);
    expect(find.byType(LibraryScreen), findsOneWidget);
    expect(focusedTitle(), 'Alpha', reason: 'the first cover has focus');

    await press(tester, PadButton.right);
    expect(focusedTitle(), 'Bravo');
    await press(tester, PadButton.left);
    expect(focusedTitle(), 'Alpha');

    await press(tester, PadButton.x);
    expect(daemon.calls.last.$1, 'game.update');
    expect(daemon.calls.last.$2, {'id': 'local:a', 'favorite': true});

    await press(tester, PadButton.a);
    expect(find.byType(GameScreen), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);

    // A on the focused Play button launches.
    await press(tester, PadButton.a);
    expect(daemon.calls.any((c) => c.$1 == 'game.launch' && c.$2!['id'] == 'local:a'), isTrue);

    await press(tester, PadButton.b);
    expect(find.byType(GameScreen), findsNothing);
    await finish(tester);
  });

  testWidgets('the pad is ignored while a game runs, except Guide', (tester) async {
    await start(tester);
    daemon.emit('game.started', {'id': 'local:b', 'tracked': true});
    await tester.pump();
    await press(tester, PadButton.right);
    expect(focusedTitle(), 'Alpha', reason: 'focus did not move behind the game');

    await press(tester, PadButton.guide);
    expect(find.byType(CouchScreen), findsOneWidget, reason: 'Guide brings Forge Gaming up in couch mode');

    // Summoned over the game, the pad drives the UI (to reach Stop)...
    // Couch mode opens on the "Playing now" shelf (just Bravo); down is All games.
    expect(focusedTitle(), 'Bravo');
    await press(tester, PadButton.down);
    expect(focusedTitle(), isNot('Bravo'));

    // ...until Guide again hands the screen back to the game.
    await press(tester, PadButton.guide);
    final after = focusedTitle();
    await press(tester, PadButton.up);
    expect(focusedTitle(), after, reason: 'ignored again once back in the game');
    await finish(tester);
  });

  testWidgets('couch mode: shelves, open with A, B leaves', (tester) async {
    await start(tester);
    await press(tester, PadButton.back);
    expect(find.byType(CouchScreen), findsOneWidget);
    expect(find.text('All games'), findsOneWidget);
    expect(focusedTitle(), 'Alpha');
    await press(tester, PadButton.right);
    expect(focusedTitle(), 'Bravo');
    expect(find.text('Bravo'), findsWidgets, reason: 'the hero shows the focused game');

    await press(tester, PadButton.a);
    expect(find.byType(GameScreen), findsOneWidget);
    await press(tester, PadButton.b);
    expect(find.byType(CouchScreen), findsOneWidget);

    await press(tester, PadButton.b);
    expect(find.byType(LibraryScreen), findsOneWidget, reason: 'B at the couch root returns to desktop');
    await finish(tester);
  });

  testWidgets('game profile: pick a cooling profile with the pad', (tester) async {
    await start(tester);
    await press(tester, PadButton.a);
    expect(find.text('GAME PROFILE'), findsOneWidget);
    expect(find.text('Performance'), findsOneWidget);
    expect(find.text('Custom'), findsNothing, reason: 'custom only shows when already chosen');
    expect(find.text('Do not disturb'), findsOneWidget);
    await tester.tap(find.text('Performance'));
    await tester.pumpAndSettle();
    final call = daemon.calls.lastWhere((c) => c.$1 == 'game.update');
    expect(call.$2, {
      'id': 'local:a',
      'profile': {'thermal': 'performance', 'quiet': false}
    });
    await finish(tester);
  });
}
