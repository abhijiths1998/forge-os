// Forge-styled dialogs: ask for a name, confirm, properties, open with.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

import 'fs.dart';
import 'icons.dart';

Widget _frame(ForgePalette p, {required Widget child, double width = 380}) => Dialog(
      backgroundColor: p.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: width), child: child),
      ),
    );

Widget _title(ForgePalette p, String t) =>
    Text(t, style: TextStyle(color: p.text, fontSize: 16, fontWeight: FontWeight.w700));

/// Ask for a name. [validate] returns an error to show, or null to close.
Future<void> askName(
  BuildContext context,
  ForgePalette p, {
  required String title,
  required String action,
  String initial = '',
  bool selectStem = true,
  required Future<String?> Function(String) validate,
}) {
  final text = TextEditingController(text: initial);
  final dot = initial.lastIndexOf('.');
  text.selection = TextSelection(baseOffset: 0, extentOffset: selectStem && dot > 0 ? dot : initial.length);
  String? error;
  return showDialog(
    context: context,
    barrierColor: Colors.black26,
    builder: (context) => StatefulBuilder(builder: (context, setState) {
      Future<void> submit() async {
        final err = await validate(text.text.trim());
        if (err == null) {
          if (context.mounted) Navigator.pop(context);
        } else {
          setState(() => error = err);
        }
      }

      return _frame(
        p,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          _title(p, title),
          const SizedBox(height: 14),
          TextField(
            controller: text,
            autofocus: true,
            style: TextStyle(color: p.text, fontSize: 14),
            decoration: InputDecoration(
              filled: true,
              fillColor: p.card,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              errorText: error,
            ),
            onSubmitted: (_) => submit(),
          ),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            PillButton(palette: p, label: 'Cancel', onTap: () => Navigator.pop(context)),
            const SizedBox(width: 8),
            PillButton(palette: p, label: action, filled: true, onTap: submit),
          ]),
        ]),
      );
    }),
  );
}

Future<bool> confirm(BuildContext context, ForgePalette p, String title, String body, String action) async {
  final r = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black26,
    builder: (context) => _frame(
      p,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        _title(p, title),
        const SizedBox(height: 8),
        Text(body, style: TextStyle(color: p.dimText, fontSize: 13)),
        const SizedBox(height: 18),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          PillButton(palette: p, label: 'Cancel', onTap: () => Navigator.pop(context, false)),
          const SizedBox(width: 8),
          PillButton(palette: p, label: action, filled: true, onTap: () => Navigator.pop(context, true)),
        ]),
      ]),
    ),
  );
  return r ?? false;
}

Future<void> showProperties(BuildContext context, ForgePalette p, List<Entry> entries) {
  return showDialog(
    context: context,
    barrierColor: Colors.black26,
    builder: (context) => _frame(p, width: 420, child: _Properties(p: p, entries: entries)),
  );
}

class _Properties extends StatefulWidget {
  const _Properties({required this.p, required this.entries});
  final ForgePalette p;
  final List<Entry> entries;

  @override
  State<_Properties> createState() => _PropertiesState();
}

class _PropertiesState extends State<_Properties> {
  int? _size;
  String? _mime;
  String? _opener;

  @override
  void initState() {
    super.initState();
    _measure();
  }

  Future<void> _measure() async {
    var total = 0;
    for (final e in widget.entries) {
      total += e.isDir ? (await folderSize(e.path) ?? 0) : e.size;
    }
    if (widget.entries.length == 1 && !widget.entries.first.isDir) {
      _mime = await mimeOf(widget.entries.first.path);
      final id = await defaultApp(_mime!);
      if (id != null) {
        final apps = await appsFor(_mime!);
        _opener = apps.where((a) => a.id == id).map((a) => a.name).firstOrNull ?? id.replaceAll('.desktop', '');
      }
    }
    if (mounted) setState(() => _size = total);
  }

  String _perms(int mode) {
    const s = 'rwxrwxrwx';
    return [for (var i = 0; i < 9; i++) (mode & (1 << (8 - i))) != 0 ? s[i] : '-'].join();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final list = widget.entries;
    final one = list.length == 1 ? list.first : null;
    Widget row(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 110, child: Text(k, style: TextStyle(color: p.dimText, fontSize: 13))),
            Expanded(child: SelectableText(v, style: TextStyle(color: p.text, fontSize: 13))),
          ]),
        );
    final folders = list.where((e) => e.isDir).length;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        if (one != null) FileIcon(entry: one, size: 48, accent: p.accent),
        const SizedBox(width: 14),
        Expanded(child: _title(p, one?.name ?? '${list.length} items')),
      ]),
      const SizedBox(height: 16),
      if (one != null) row('Kind', _mime == null ? kindName(one) : '${kindName(one)} ($_mime)'),
      if (one == null) row('Contains', '$folders folder${folders == 1 ? '' : 's'}, ${list.length - folders} file${list.length - folders == 1 ? '' : 's'}'),
      row('Size', _size == null ? 'Measuring…' : '${sizeText(_size!)}  (${_size!} bytes)'),
      row('Where', pretty(one?.trashOrigin != null ? dirname(one!.trashOrigin!) : dirname(list.first.path))),
      if (one != null) row('Modified', dateText(one.modified)),
      if (one != null) row('Permissions', '${_perms(one.mode)}${one.executable ? '  (can run as a program)' : ''}'),
      if (one?.isLink ?? false) row('Points to', _linkTarget(one!.path)),
      if (_opener != null) row('Opens with', _opener!),
      const SizedBox(height: 14),
      Align(
        alignment: Alignment.centerRight,
        child: PillButton(palette: p, label: 'Close', filled: true, onTap: () => Navigator.pop(context)),
      ),
    ]);
  }

  String _linkTarget(String path) {
    try {
      return Link(path).targetSync();
    } catch (_) {
      return '?';
    }
  }
}

/// Pick an app to open [entries] with; optionally make it the default.
Future<void> openWithDialog(BuildContext context, ForgePalette p, List<Entry> entries) async {
  final mime = await mimeOf(entries.first.path);
  final apps = await appsFor(mime);
  final def = await defaultApp(mime);
  if (!context.mounted) return;
  var always = false;
  await showDialog(
    context: context,
    barrierColor: Colors.black26,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => _frame(
        p,
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          _title(p, 'Open ${entries.length == 1 ? entries.first.name : '${entries.length} files'} with'),
          const SizedBox(height: 4),
          Text(mime, style: TextStyle(color: p.dimText, fontSize: 12)),
          const SizedBox(height: 12),
          if (apps.isEmpty)
            Text('No installed app says it opens this kind of file.', style: TextStyle(color: p.dimText, fontSize: 13)),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: ListView(shrinkWrap: true, children: [
              for (final a in apps)
                ListTile(
                  dense: true,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  hoverColor: p.hover,
                  leading: Icon(Icons.apps_rounded, color: p.accent),
                  title: Text(a.name, style: TextStyle(color: p.text, fontSize: 13.5, fontWeight: FontWeight.w600)),
                  subtitle: a.id == def ? Text('Default', style: TextStyle(color: p.dimText, fontSize: 11.5)) : null,
                  onTap: () {
                    if (always) setDefaultApp(mime, a.id);
                    openWith(a, entries.map((e) => e.path).toList());
                    Navigator.pop(context);
                  },
                ),
            ]),
          ),
          const SizedBox(height: 6),
          Row(children: [
            Checkbox(value: always, activeColor: p.accent, onChanged: (v) => setState(() => always = v ?? false)),
            Text('Always open this kind of file with it', style: TextStyle(color: p.text, fontSize: 13)),
          ]),
          Align(
            alignment: Alignment.centerRight,
            child: PillButton(palette: p, label: 'Cancel', onTap: () => Navigator.pop(context)),
          ),
        ]),
      ),
    ),
  );
}
