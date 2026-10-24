// Images in and out: loading the capture, cropping, PNG, where screenshots
// are saved (~/Pictures/Screenshots, or wherever the Pictures folder is), and
// the text in an image (tesseract).
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

class Store {
  static Future<ui.Image> load(String path) async {
    final codec = await ui.instantiateImageCodec(await File(path).readAsBytes());
    return (await codec.getNextFrame()).image;
  }

  static Future<Uint8List> png(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }

  /// A part of an image, at its own resolution.
  static Future<ui.Image> crop(ui.Image image, Rect rect) {
    final r = rect.intersect(Offset.zero & Size(image.width.toDouble(), image.height.toDouble()));
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawImageRect(image, r, Offset.zero & r.size, Paint());
    return recorder.endRecording().toImage(r.width.round(), r.height.round());
  }

  /// The Pictures folder's Screenshots folder, made if need be.
  static Future<Directory> folder() async {
    var pictures = '';
    try {
      final r = await Process.run('xdg-user-dir', ['PICTURES']);
      pictures = (r.stdout as String).trim();
    } catch (_) {}
    final home = Platform.environment['HOME'] ?? '';
    if (pictures.isEmpty || pictures == home) pictures = '$home/Pictures';
    return Directory('$pictures/Screenshots').create(recursive: true);
  }

  static String fileName([DateTime? at]) {
    final t = at ?? DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return 'Screenshot_${t.year}-${two(t.month)}-${two(t.day)}_'
        '${two(t.hour)}-${two(t.minute)}-${two(t.second)}.png';
  }

  /// Saves PNG bytes into the Screenshots folder, never over another file.
  static Future<File> save(Uint8List bytes) async {
    final dir = await folder();
    var file = File('${dir.path}/${fileName()}');
    for (var i = 2; file.existsSync(); i++) {
      file = File('${dir.path}/${fileName().replaceFirst('.png', '-$i.png')}');
    }
    return file.writeAsBytes(bytes, flush: true);
  }

  /// The text in an image (tesseract), in English and any other language
  /// whose data is installed. Throws a message to show when it can't.
  static Future<String> text(String path) async {
    ProcessResult langs;
    try {
      langs = await Process.run('tesseract', ['--list-langs']);
    } on ProcessException {
      throw 'Text recognition needs tesseract';
    }
    final have = (langs.stdout as String)
        .split('\n')
        .skip(1)
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && l != 'osd')
        .toList();
    if (have.isEmpty) throw 'Text recognition needs a language (tesseract-data-eng)';
    final use = have.contains('eng') ? ['eng', ...have.where((l) => l != 'eng').take(2)] : have.take(3).toList();
    final r = await Process.run('tesseract', [path, 'stdout', '-l', use.join('+')]);
    if (r.exitCode != 0) throw 'Couldn\'t read the text';
    return (r.stdout as String).trim();
  }
}
