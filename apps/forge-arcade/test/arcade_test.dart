import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:forge_arcade/arcade.dart';
import 'package:forge_arcade/gamepad.dart';
import 'package:forge_arcade/games.dart';
import 'package:forge_arcade/scores.dart';
import 'package:forge_ui/forge_ui.dart';

List<Game> _games(int n) => [
      for (var i = 0; i < n; i++)
        Game(
          id: 'g$i',
          name: 'Game $i',
          description: 'About game $i.',
          controls: const [('Space', 'Jump')],
          needsGpu: i == 0,
          exec: '/usr/bin/g$i',
          cover: '/nonexistent/g$i.png',
          highScoreFile: i == 1 ? '/nonexistent/best' : null,
        ),
    ];

void main() {
  test('moveSelection stays on the grid', () {
    int m(int i, LogicalKeyboardKey k) => moveSelection(i, 10, 3, k);
    expect(m(0, LogicalKeyboardKey.arrowLeft), 0);
    expect(m(0, LogicalKeyboardKey.arrowRight), 1);
    expect(m(1, LogicalKeyboardKey.arrowDown), 4);
    expect(m(4, LogicalKeyboardKey.arrowUp), 1);
    expect(m(1, LogicalKeyboardKey.arrowUp), 1);
    // Ten cards in three columns: the last row has one card.
    expect(m(7, LogicalKeyboardKey.arrowDown), 9);
    expect(m(9, LogicalKeyboardKey.arrowDown), 9);
    expect(m(9, LogicalKeyboardKey.arrowRight), 9);
  });

  Future<(List<String>, List<bool>, StreamController<PadAction>)> pump(
      WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final launched = <String>[];
    final quits = <bool>[];
    final pad = StreamController<PadAction>();
    addTearDown(pad.close);
    final p = ForgePalette.of(forgeGlass);
    await tester.pumpWidget(MaterialApp(
      theme: p.materialTheme(),
      home: ArcadeHome(
        games: _games(10),
        palette: p,
        launch: (g) async => launched.add(g.id),
        onQuit: () => quits.add(true),
        loadScoresFor: (g) async => const [ScoreEntry(42)],
        pad: pad.stream,
      ),
    ));
    await tester.pump();
    return (launched, quits, pad);
  }

  testWidgets('arrows move the selection and the details follow', (tester) async {
    await pump(tester);
    expect(find.text('About game 0.'), findsOneWidget);
    expect(find.text('Needs a GPU'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(find.text('About game 1.'), findsOneWidget);
    expect(find.text('Needs a GPU'), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('42'), findsOneWidget); // game 1 keeps scores

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    // 1200 px wide: the grid has 3 columns, so down from 1 is 1 + columns.
    expect(find.textContaining('About game '), findsOneWidget);
    expect(find.text('About game 1.'), findsNothing);
    await tester.pumpAndSettle();
  });

  testWidgets('Enter plays the selected game, Esc quits', (tester) async {
    final (launched, quits, _) = await pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(launched, ['g1']);
    await tester.pump(const Duration(seconds: 4)); // the "Starting..." delay
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(quits, [true]);
    await tester.pumpAndSettle();
  });

  testWidgets('the Play button launches too', (tester) async {
    final (launched, _, _) = await pump(tester);
    await tester.tap(find.text('Play'));
    await tester.pump();
    expect(launched, ['g0']);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('a gamepad moves, plays and quits', (tester) async {
    final (launched, quits, pad) = await pump(tester);
    pad.add(PadAction.right);
    await tester.idle(); // let the stream deliver
    await tester.pump();
    expect(find.text('About game 1.'), findsOneWidget);
    pad.add(PadAction.select);
    await tester.idle(); // let the stream deliver
    await tester.pump();
    expect(launched, ['g1']);
    await tester.pump(const Duration(seconds: 4));
    pad.add(PadAction.back);
    await tester.idle(); // let the stream deliver
    await tester.pump();
    expect(quits, [true]);
  });

  testWidgets('no games shows a message, not a crash', (tester) async {
    final p = ForgePalette.of(forgeGlass);
    await tester.pumpWidget(MaterialApp(
      theme: p.materialTheme(),
      home: ArcadeHome(games: const [], palette: p, onQuit: () {}),
    ));
    expect(find.textContaining('No games installed'), findsOneWidget);
  });
}
