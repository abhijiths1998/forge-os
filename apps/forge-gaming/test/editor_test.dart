import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:forge_gaming/src/screens/editor_screen.dart';
import 'package:forge_gaming/src/screens/file_browser.dart';
import 'package:forge_gaming/src/screens/runners_screen.dart';
import 'package:forge_gaming/src/widgets/glass.dart';

void main() {
  test('parseEnv / formatEnv', () {
    expect(parseEnv('A=1\n\n B = two words \nnoequals\n=x\nC=a=b'), {'A': '1', 'B': 'two words', 'C': 'a=b'});
    expect(formatEnv({'A': '1', 'B': '2'}), 'A=1\nB=2');
  });

  test('titleFromExe', () {
    expect(titleFromExe('/g/Hollow Knight/hollow_knight.x86_64'), 'Hollow Knight');
    expect(titleFromExe('/games/Celeste/Game.exe'), 'Celeste');
    expect(titleFromExe('/x/super-meat-boy.sh'), 'Super Meat Boy');
    expect(titleFromExe(''), '');
  });

  test('browseEntries: folders first, no hidden, filter applies to files', () {
    final d = Directory.systemTemp.createTempSync('fg-browse');
    addTearDown(() => d.deleteSync(recursive: true));
    for (final f in ['b.exe', 'A.txt', '.hidden', 'c.EXE']) {
      File('${d.path}/$f').writeAsStringSync('');
    }
    Directory('${d.path}/zdir').createSync();
    Directory('${d.path}/.git').createSync();
    final names = browseEntries(d).map((e) => e.path.split('/').last).toList();
    expect(names, ['zdir', 'A.txt', 'b.exe', 'c.EXE']);
    final exes = browseEntries(d, fileFilter: (p) => p.toLowerCase().endsWith('.exe'))
        .map((e) => e.path.split('/').last)
        .toList();
    expect(exes, ['zdir', 'b.exe', 'c.EXE']);
    expect(browseEntries(Directory('${d.path}/missing')), isEmpty);
  });

  test('formatBytes', () {
    expect(formatBytes(0), '');
    expect(formatBytes(512), '512 B');
    expect(formatBytes(1536), '1.5 KB');
    expect(formatBytes(512 * 1024 * 1024), '512 MB');
  });

  test('initials and stable title colours', () {
    expect(initials('Witcher 3'), 'W3');
    expect(initials('celeste'), 'CE');
    expect(initials(''), '?');
    expect(titleColours('GTA 5'), titleColours('GTA 5'));
  });
}
