// Forge Shot: Forge OS's screenshot tool. The runner has already taken the
// screenshot (linux/runner) and says what to do with it:
//
//   region <png>     pick a part of it on the overlay (overlay.dart), then
//                    save, copy, annotate or read its text
//   thumbnail <png>  saved and copied already (full screen, a window)
//   edit <png>       the editor (editor.dart)
//
// After a capture, the thumbnail (thumbnail.dart) offers the rest; annotating
// starts a new run, as an ordinary window, and this one ends.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

import 'editor.dart';
import 'native.dart';
import 'overlay.dart';
import 'store.dart';
import 'thumbnail.dart';

void main(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(ShotApp(mode: args.isNotEmpty ? args[0] : 'region', path: args.length > 1 ? args[1] : ''));
}

class ShotApp extends StatefulWidget {
  const ShotApp({super.key, required this.mode, required this.path});

  final String mode;
  final String path;

  @override
  State<ShotApp> createState() => _ShotAppState();
}

enum _Stage { loading, region, thumbnail, edit }

class _ShotAppState extends State<ShotApp> {
  final _palette = ForgePalette.current();
  _Stage _stage = _Stage.loading;
  ui.Image? _capture; // the screenshot as taken
  ui.Image? _shot; // what was kept of it
  File? _saved;
  String _status = '';

  bool get _ownCapture => widget.mode != 'edit';

  @override
  void initState() {
    super.initState();
    Store.load(widget.path).then((image) {
      _capture = image;
      if (widget.mode == 'edit') {
        setState(() => _stage = _Stage.edit);
      } else if (widget.mode == 'thumbnail') {
        _deliver(image, ShotAction.saveAndCopy);
      } else {
        setState(() => _stage = _Stage.region);
      }
    }, onError: (_) {
      _quit();
    });
  }

  String get _runDir => '${Platform.environment['XDG_RUNTIME_DIR'] ?? Directory.systemTemp.path}/forge-shot';

  Future<String> _temp(Uint8List bytes, String name) async {
    final f = File('$_runDir/$name');
    await f.parent.create(recursive: true);
    await f.writeAsBytes(bytes, flush: true);
    return f.path;
  }

  Future<void> _deliver(ui.Image image, ShotAction action) async {
    final bytes = await Store.png(image);
    var status = '';
    switch (action) {
      case ShotAction.saveAndCopy:
        _saved = await Store.save(bytes);
        status = await Native.copyImage(_saved!.path) ? 'Saved and copied' : 'Saved';
      case ShotAction.save:
        _saved = await Store.save(bytes);
        status = 'Saved';
      case ShotAction.copy:
        status = await Native.copyImage(await _temp(bytes, 'copied.png')) ? 'Copied' : 'Couldn\'t copy';
      case ShotAction.text:
        try {
          final text = await Store.text(await _temp(bytes, 'text.png'));
          status = text.isEmpty ? 'No text found' : (await Native.copyText(text) ? 'Text copied' : 'Couldn\'t copy');
        } catch (e) {
          status = '$e';
        }
      case ShotAction.edit:
        return _openEditor(await _temp(bytes, 'annotate-${DateTime.now().millisecondsSinceEpoch}.png'));
    }
    setState(() {
      _shot = image;
      _status = status;
      _stage = _Stage.thumbnail;
    });
    await Native.present('thumbnail');
  }

  Future<void> _openEditor(String path) async {
    await Process.start(Platform.resolvedExecutable, ['edit', path], mode: ProcessStartMode.detached);
    await _quit();
  }

  Future<void> _quit() async {
    // The capture lives in the runtime directory (in memory): drop it.
    if (_ownCapture && widget.path.startsWith(_runDir)) {
      try {
        File(widget.path).deleteSync();
      } catch (_) {}
    }
    await Native.quit();
  }

  Future<void> _region(Rect region, ShotAction action) async {
    final image = await Store.crop(_capture!, region);
    await _deliver(image, action);
  }

  Future<void> _showInFolder() async {
    final f = _saved;
    if (f == null) return;
    try {
      await Process.start('dolphin', ['--select', f.path], mode: ProcessStartMode.detached);
    } on ProcessException {
      await Process.start('xdg-open', [f.parent.path], mode: ProcessStartMode.detached);
    }
    await _quit();
  }

  Future<void> _delete() async {
    try {
      await _saved?.delete();
    } catch (_) {}
    setState(() {
      _status = 'Deleted';
      _saved = null;
    });
    await Future.delayed(const Duration(milliseconds: 900));
    await _quit();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Forge Shot',
      debugShowCheckedModeBanner: false,
      color: Colors.transparent,
      theme: _palette.materialTheme(),
      home: Scaffold(backgroundColor: Colors.transparent, body: _body()),
    );
  }

  Widget _body() {
    switch (_stage) {
      case _Stage.loading:
        return const SizedBox.shrink();
      case _Stage.region:
        return RegionOverlay(image: _capture!, palette: _palette, onDone: _region, onCancel: _quit);
      case _Stage.thumbnail:
        return Thumbnail(
          image: _shot!,
          status: _status,
          palette: _palette,
          saved: _saved != null,
          onEdit: () async => _openEditor(_saved?.path ?? await _temp(await Store.png(_shot!), 'annotate.png')),
          onCopy: () async {
            final path = _saved?.path ?? await _temp(await Store.png(_shot!), 'copied.png');
            final ok = await Native.copyImage(path);
            setState(() => _status = ok ? 'Copied' : 'Couldn\'t copy');
          },
          onFolder: _showInFolder,
          onDelete: _delete,
          onClose: _quit,
        );
      case _Stage.edit:
        return Editor(image: _capture!, path: widget.path, palette: _palette);
    }
  }
}
