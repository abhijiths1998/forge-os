// The calendars: local ones (an .ics file each, ours to change) and
// subscriptions (an .ics address, fetched every hour, read-only), in
// ~/.local/share/forgeos/calendar with calendars.json listing them.
// Reminders are sent from here as desktop notifications.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';

import 'ics.dart';

class Calendar {
  Calendar({required this.id, required this.name, required this.colour, this.visible = true, this.url, this.synced, this.error});

  final String id;
  String name;
  Color colour;
  bool visible;

  /// A subscription's address (webcal:// or https://); null for local.
  String? url;
  DateTime? synced;
  String? error;

  bool get readOnly => url != null;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'colour': colour.toARGB32(),
        'visible': visible,
        'url': url,
        'synced': synced?.toIso8601String(),
      };

  static Calendar fromJson(Map<String, dynamic> j) => Calendar(
        id: j['id'] as String,
        name: j['name'] as String,
        colour: Color(j['colour'] as int),
        visible: j['visible'] as bool? ?? true,
        url: j['url'] as String?,
        synced: j['synced'] == null ? null : DateTime.tryParse(j['synced'] as String),
      );
}

const calendarColours = [
  Color(0xFF7C8CF8), Color(0xFF4FB6A0), Color(0xFFE0667E), Color(0xFFE8A13C),
  Color(0xFFB07BE0), Color(0xFF4FA3E0), Color(0xFF8FBF4F), Color(0xFFCF6FB0),
];

class Store extends ChangeNotifier {
  Store() {
    _load();
    _sync = Timer.periodic(const Duration(hours: 1), (_) => syncAll());
    syncAll();
    _reminders = Timer.periodic(const Duration(seconds: 20), (_) => _remind());
    _watch();
  }

  final List<Calendar> calendars = [];
  final Map<String, List<CalEvent>> _events = {};
  Timer? _sync;
  Timer? _reminders;
  DateTime _remindedUpTo = DateTime.now();
  final Set<String> _reminded = {};
  StreamSubscription<FileSystemEvent>? _watcher;
  DateTime _lastWrite = DateTime(2000);

  static String get dir {
    final home = Platform.environment['HOME'] ?? '';
    return '${Platform.environment['XDG_DATA_HOME'] ?? '$home/.local/share'}/forgeos/calendar';
  }

  File _file(String id) => File('$dir/$id.ics');
  File get _index => File('$dir/calendars.json');

  @override
  void dispose() {
    _sync?.cancel();
    _reminders?.cancel();
    _watcher?.cancel();
    super.dispose();
  }

  void _load() {
    Directory(dir).createSync(recursive: true);
    calendars.clear();
    try {
      final list = jsonDecode(_index.readAsStringSync()) as List<dynamic>;
      calendars.addAll(list.map((j) => Calendar.fromJson(j as Map<String, dynamic>)));
    } catch (_) {}
    if (calendars.isEmpty) {
      calendars.add(Calendar(id: 'personal', name: 'Personal', colour: calendarColours[0]));
      _saveIndex();
    }
    for (final c in calendars) {
      _readEvents(c);
    }
  }

  void _readEvents(Calendar c) {
    try {
      _events[c.id] = parseIcs(_file(c.id).readAsStringSync(), c.id);
    } catch (_) {
      _events[c.id] = [];
    }
  }

  // Another window (or a sync tool) changed the files: read them again.
  void _watch() {
    try {
      _watcher = Directory(dir).watch().listen((e) {
        if (DateTime.now().difference(_lastWrite) < const Duration(seconds: 2)) return;
        _load();
        notifyListeners();
      });
    } catch (_) {}
  }

  void _saveIndex() {
    _lastWrite = DateTime.now();
    _index.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(calendars.map((c) => c.toJson()).toList()));
  }

  void _saveEvents(Calendar c) {
    _lastWrite = DateTime.now();
    final tmp = File('${_file(c.id).path}.tmp');
    tmp.writeAsStringSync(writeIcs(_events[c.id] ?? [], name: c.name));
    tmp.renameSync(_file(c.id).path);
  }

  Calendar? calendar(String id) => calendars.where((c) => c.id == id).firstOrNull;

  Calendar get defaultCalendar => calendars.firstWhere((c) => !c.readOnly, orElse: () => calendars.first);

  List<Calendar> get writable => calendars.where((c) => !c.readOnly).toList();

  /// Every visible occurrence overlapping [from, to), in start order.
  List<Occurrence> between(DateTime from, DateTime to, {bool all = false}) {
    final out = <Occurrence>[];
    for (final c in calendars) {
      if (!c.visible && !all) continue;
      for (final e in _events[c.id] ?? const <CalEvent>[]) {
        out.addAll(e.between(from, to));
      }
    }
    out.sort((a, b) {
      if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
      final c = a.start.compareTo(b.start);
      return c != 0 ? c : b.end.compareTo(a.end);
    });
    return out;
  }

  List<Occurrence> search(String q) {
    final s = q.toLowerCase();
    final now = DateTime.now();
    final all = between(DateTime(now.year - 2), DateTime(now.year + 3));
    return all
        .where((o) =>
            o.event.title.toLowerCase().contains(s) ||
            o.event.location.toLowerCase().contains(s) ||
            o.event.notes.toLowerCase().contains(s))
        .toList();
  }

  // ------------------------------------------------------------ events

  static String newUid() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${Random().nextInt(1 << 32).toRadixString(36)}@forge-os';

  void save(CalEvent e, {String? fromCalendar}) {
    final from = fromCalendar ?? e.calendar;
    if (from != e.calendar) {
      _events[from]?.removeWhere((x) => x.uid == e.uid);
      final old = calendar(from);
      if (old != null) _saveEvents(old);
    }
    final list = _events.putIfAbsent(e.calendar, () => []);
    final i = list.indexWhere((x) => x.uid == e.uid);
    i >= 0 ? list[i] = e : list.add(e);
    _saveEvents(calendar(e.calendar)!);
    notifyListeners();
  }

  void delete(CalEvent e) {
    _events[e.calendar]?.removeWhere((x) => x.uid == e.uid || x.uid.startsWith('${e.uid}#'));
    _saveEvents(calendar(e.calendar)!);
    notifyListeners();
  }

  /// Leave out one occurrence of a repeating event.
  void skipOccurrence(Occurrence o) {
    o.event.exdates.add(o.start);
    save(o.event);
  }

  /// Change one occurrence only: it becomes its own event (RECURRENCE-ID).
  CalEvent detach(Occurrence o) {
    final copy = o.event.copy()
      ..uid = '${o.event.uid.split('#').first}#${formatUtc(o.start)}'
      ..repeat = null
      ..exdates = {}
      ..start = o.start
      ..end = o.end;
    o.event.exdates.add(o.start);
    return copy;
  }

  // ------------------------------------------------------------ calendars

  Calendar addLocal(String name) {
    final c = Calendar(id: _freeId(name), name: name, colour: calendarColours[calendars.length % calendarColours.length]);
    calendars.add(c);
    _events[c.id] = [];
    _saveIndex();
    _saveEvents(c);
    notifyListeners();
    return c;
  }

  Future<String?> subscribe(String name, String url) async {
    final c = Calendar(
      id: _freeId(name),
      name: name,
      colour: calendarColours[calendars.length % calendarColours.length],
      url: url.trim(),
    );
    final err = await _fetch(c);
    if (err != null) return err;
    calendars.add(c);
    _saveIndex();
    notifyListeners();
    return null;
  }

  /// Bring an .ics file's events into a local calendar.
  int importFile(String path, Calendar into) {
    final events = parseIcs(File(path).readAsStringSync(), into.id);
    final list = _events.putIfAbsent(into.id, () => []);
    for (final e in events) {
      list.removeWhere((x) => x.uid == e.uid);
      list.add(e);
    }
    _saveEvents(into);
    notifyListeners();
    return events.length;
  }

  void update(Calendar c) {
    _saveIndex();
    notifyListeners();
  }

  void remove(Calendar c) {
    calendars.remove(c);
    _events.remove(c.id);
    try {
      _file(c.id).deleteSync();
    } catch (_) {}
    if (calendars.isEmpty) {
      _load();
    } else {
      _saveIndex();
    }
    notifyListeners();
  }

  String _freeId(String name) {
    var base = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
    if (base.isEmpty) base = 'calendar';
    var id = base;
    for (var i = 2; calendars.any((c) => c.id == id); i++) {
      id = '$base-$i';
    }
    return id;
  }

  Future<void> syncAll() async {
    for (final c in calendars.where((c) => c.readOnly)) {
      await _fetch(c);
    }
    notifyListeners();
  }

  Future<String?> _fetch(Calendar c) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final uri = Uri.parse(c.url!.replaceFirst(RegExp(r'^webcals?://'), 'https://'));
      final req = await client.getUrl(uri);
      req.headers.set('User-Agent', 'Forge Calendar/1.0');
      final res = await req.close().timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) {
        c.error = 'The address answered ${res.statusCode}';
        return c.error;
      }
      final text = await res.transform(utf8.decoder).join();
      if (!text.contains('BEGIN:VCALENDAR')) {
        c.error = 'That address isn\'t a calendar (.ics)';
        return c.error;
      }
      _lastWrite = DateTime.now();
      _file(c.id).writeAsStringSync(text);
      _events[c.id] = parseIcs(text, c.id);
      c.synced = DateTime.now();
      c.error = null;
      _saveIndex();
      return null;
    } catch (e) {
      c.error = 'Couldn\'t reach it: ${e is SocketException ? 'offline?' : e.toString().split('\n').first}';
      return c.error;
    } finally {
      client.close();
    }
  }

  // ------------------------------------------------------------ reminders

  void _remind() {
    final now = DateTime.now();
    // Anything due since the last look (the machine may have slept).
    final from = _remindedUpTo.subtract(const Duration(seconds: 1));
    _remindedUpTo = now;
    final soon = between(from.subtract(const Duration(days: 8)), now.add(const Duration(days: 8)), all: true);
    for (final o in soon) {
      final a = o.event.alarm;
      if (a == null) continue;
      final at = o.start.subtract(Duration(minutes: a));
      if (at.isAfter(from) && !at.isAfter(now)) {
        final key = '${o.event.uid}@${o.start.millisecondsSinceEpoch}';
        if (_reminded.add(key)) _notify(o);
      }
    }
  }

  /// A reminder that couldn't be shown as a notification (no notification
  /// server, as in a Forge session before Forge has its own): the window
  /// shows it instead.
  void Function(Occurrence o)? onUndelivered;

  Future<void> _notify(Occurrence o) async {
    final e = o.event;
    final when = e.allDay ? 'All day' : '${_hm(o.start)} – ${_hm(o.end)}';
    final body = [when, if (e.location.isNotEmpty) e.location].join(' · ');
    final r = await Process.run('gdbus', [
      'call', '--session', '--timeout', '5',
      '--dest', 'org.freedesktop.Notifications',
      '--object-path', '/org/freedesktop/Notifications',
      '--method', 'org.freedesktop.Notifications.Notify',
      'Forge Calendar', '0', 'x-office-calendar', e.title, body, '[]',
      "{'desktop-entry': <'org.forgeos.calendar'>, 'urgency': <byte 1>}", '0',
    ]).catchError((_) => ProcessResult(0, 1, '', ''));
    if (r.exitCode != 0) onUndelivered?.call(o);
  }

  static String _hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
