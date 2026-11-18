// Forge Calendar: Forge OS's calendar. Month, week, day and agenda views
// in the Forge Glass look; local calendars kept as .ics files, .ics
// subscriptions (Google's secret address, holidays...), repeats, and
// reminders as desktop notifications. It stays running when its window is
// closed (and starts hidden at login with --background) so reminders come
// on time; opening it again shows the window.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forge_ui/forge_ui.dart';

import 'dates.dart';
import 'editor.dart';
import 'ics.dart';
import 'store.dart';
import 'views.dart';

void main() => runApp(const CalendarApp());

enum View { day, week, month, agenda }

class CalendarApp extends StatefulWidget {
  const CalendarApp({super.key});

  @override
  State<CalendarApp> createState() => _CalendarAppState();
}

class _CalendarAppState extends State<CalendarApp> {
  static const _window = MethodChannel('forge/window');
  final Store store = Store();

  /// A reminder shown in the window (notifications weren't available).
  Occurrence? _reminder;
  ForgePalette _p = ForgePalette.current();
  View _view = _savedView();
  DateTime _selected = today();
  DateTime _miniMonth = DateTime(today().year, today().month);
  final _navigator = GlobalKey<NavigatorState>();
  final _focus = FocusNode();
  final _searchText = TextEditingController();
  final _searchFocus = FocusNode();
  List<Occurrence>? _results;
  Timer? _themePoll;
  Timer? _midnight;

  BuildContext get _ctx => _navigator.currentContext!;

  // The last view picked, in ~/.config/forge/calendar.json.
  static File get _settings =>
      File('${Platform.environment['XDG_CONFIG_HOME'] ?? '${Platform.environment['HOME']}/.config'}/forge/calendar.json');

  static View _savedView() {
    try {
      final j = jsonDecode(_settings.readAsStringSync()) as Map<String, dynamic>;
      return View.values.asNameMap()[j['view']] ?? View.month;
    } catch (_) {
      return View.month;
    }
  }

  void _setView(View v) {
    setState(() {
      _view = v;
      _results = null;
      _searchText.clear();
    });
    try {
      _settings.parent.createSync(recursive: true);
      _settings.writeAsStringSync(jsonEncode({'view': v.name}));
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    store.addListener(_changed);
    store.onUndelivered = (o) {
      setState(() => _reminder = o);
      _window.invokeMethod('present').catchError((_) => null);
    };
    _themePoll = Timer.periodic(const Duration(seconds: 3), (_) {
      final p = ForgePalette.current();
      if (p.theme.toJson().toString() != _p.theme.toJson().toString()) setState(() => _p = p);
    });
    // Today moves at midnight.
    _midnight = Timer.periodic(const Duration(minutes: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _themePoll?.cancel();
    _midnight?.cancel();
    store.removeListener(_changed);
    store.dispose();
    super.dispose();
  }

  void _changed() {
    if (_results != null) _results = store.search(_searchText.text);
    setState(() {});
  }

  // ------------------------------------------------------------ navigation

  void _step(int dir) {
    setState(() {
      _selected = switch (_view) {
        View.day => addDays(_selected, dir),
        View.week => addDays(_selected, 7 * dir),
        View.month => DateTime(_selected.year, _selected.month + dir, 1),
        View.agenda => addDays(_selected, 30 * dir),
      };
      _miniMonth = DateTime(_selected.year, _selected.month);
    });
  }

  void _today() => setState(() {
        _selected = today();
        _miniMonth = DateTime(_selected.year, _selected.month);
      });

  void _pick(DateTime d) => setState(() {
        _selected = d;
        _miniMonth = DateTime(d.year, d.month);
      });

  String get _heading {
    final s = _selected;
    switch (_view) {
      case View.day:
        return longDate(s);
      case View.week:
        final a = weekStart(s), b = addDays(a, 6);
        if (a.month == b.month) return '${monthNames[a.month - 1]} ${a.year}';
        if (a.year == b.year) return '${shortMonth(a.month)} – ${shortMonth(b.month)} ${a.year}';
        return '${shortMonth(a.month)} ${a.year} – ${shortMonth(b.month)} ${b.year}';
      case View.month:
        return '${monthNames[s.month - 1]} ${s.year}';
      case View.agenda:
        return 'From ${relativeDay(s).toLowerCase() == 'today' ? 'today' : shortDate(s)}';
    }
  }

  // ------------------------------------------------------------ events

  Future<void> _open(Occurrence o) async {
    await editEvent(_ctx, _p, store, o: o);
    _focus.requestFocus();
  }

  Future<void> _new(DateTime start, {bool allDay = false}) async {
    if (store.writable.isEmpty) return;
    await editEvent(_ctx, _p, store, start: start, allDay: allDay);
    _focus.requestFocus();
  }

  DateTime _newStart() {
    final now = DateTime.now();
    if (sameDay(_selected, now)) {
      final m = now.minute < 30 ? 30 : 60;
      return DateTime(now.year, now.month, now.day, now.hour).add(Duration(minutes: m));
    }
    return DateTime(_selected.year, _selected.month, _selected.day, 9);
  }

  // ------------------------------------------------------------ calendars

  Future<void> _addCalendar() async {
    final p = _p;
    final choice = await showMenu<String>(
      context: _ctx,
      color: p.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      position: const RelativeRect.fromLTRB(24, 420, 24, 0),
      items: [
        _menuItem(p, 'local', Icons.add_rounded, 'New calendar'),
        _menuItem(p, 'subscribe', Icons.cloud_sync_rounded, 'Subscribe to an address (.ics)'),
        _menuItem(p, 'import', Icons.file_open_rounded, 'Import an .ics file'),
      ],
    );
    if (!mounted || choice == null) return;
    if (choice == 'local') {
      await _ask('New calendar', 'Name', '', (name, _) async {
        if (name.trim().isEmpty) return 'Give it a name';
        store.addLocal(name.trim());
        return null;
      });
    } else if (choice == 'subscribe') {
      await _ask('Subscribe to a calendar', 'Name', 'https://…/basic.ics', (name, url) async {
        if (url == null || !RegExp(r'^(https?|webcals?)://').hasMatch(url.trim())) return 'An https:// or webcal:// address';
        return store.subscribe(name.trim().isEmpty ? 'Subscribed' : name.trim(), url);
      }, second: true, hint: 'In Google Calendar: Settings → your calendar → "Secret address in iCal format".');
    } else if (choice == 'import') {
      await _ask('Import events', 'Path to an .ics file', '', (path, _) async {
        var p = path.trim();
        if (p.startsWith('~')) p = '${Platform.environment['HOME']}${p.substring(1)}';
        if (!File(p).existsSync()) return 'No file there';
        try {
          final n = store.importFile(p, store.defaultCalendar);
          _toast('Imported $n event${n == 1 ? '' : 's'} into ${store.defaultCalendar.name}');
          return null;
        } catch (_) {
          return 'That isn\'t a calendar file';
        }
      });
    }
  }

  PopupMenuItem<String> _menuItem(ForgePalette p, String value, IconData icon, String label) => PopupMenuItem(
        value: value,
        height: 38,
        child: Row(children: [
          Icon(icon, size: 18, color: p.text.withValues(alpha: 0.75)),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(color: p.text, fontSize: 13)),
        ]),
      );

  /// A small form: one or two fields; [submit] returns an error or null.
  Future<void> _ask(String title, String label, String secondHint, Future<String?> Function(String, String?) submit,
      {bool second = false, String? hint, String initial = ''}) {
    final p = _p;
    final a = TextEditingController(text: initial), b = TextEditingController();
    String? error;
    var busy = false;
    return showDialog(
      context: _ctx,
      barrierColor: Colors.black26,
      builder: (context) => StatefulBuilder(builder: (context, setState) {
        Future<void> go() async {
          setState(() => busy = true);
          final err = await submit(a.text, second ? b.text : null);
          if (err == null) {
            if (context.mounted) Navigator.pop(context);
          } else {
            setState(() {
              error = err;
              busy = false;
            });
          }
        }

        InputDecoration deco(String h) => InputDecoration(
              hintText: h,
              hintStyle: TextStyle(color: p.dimText),
              filled: true,
              fillColor: p.card,
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            );
        return Dialog(
          backgroundColor: p.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(color: p.text, fontSize: 16, fontWeight: FontWeight.w700)),
                if (hint != null) ...[
                  const SizedBox(height: 6),
                  Text(hint, style: TextStyle(color: p.dimText, fontSize: 12.5)),
                ],
                const SizedBox(height: 14),
                TextField(controller: a, autofocus: true, style: TextStyle(color: p.text), decoration: deco(label), onSubmitted: (_) => go()),
                if (second) ...[
                  const SizedBox(height: 8),
                  TextField(controller: b, style: TextStyle(color: p.text), decoration: deco(secondHint), onSubmitted: (_) => go()),
                ],
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: TextStyle(color: p.negative, fontSize: 12.5)),
                ],
                const SizedBox(height: 16),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  PillButton(palette: p, label: 'Cancel', onTap: () => Navigator.pop(context)),
                  const SizedBox(width: 8),
                  PillButton(palette: p, label: busy ? 'Working…' : 'OK', filled: true, onTap: busy ? null : go),
                ]),
              ]),
            ),
          ),
        );
      }),
    );
  }

  Future<void> _calendarMenu(Calendar c, Offset at) async {
    final p = _p;
    final r = await showMenu<String>(
      context: _ctx,
      color: p.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
      items: [
        _menuItem(p, 'rename', Icons.edit_rounded, 'Rename'),
        PopupMenuItem<String>(
          enabled: false,
          height: 40,
          child: Row(children: [
            for (final col in calendarColours)
              GestureDetector(
                onTap: () {
                  c.colour = col;
                  store.update(c);
                  Navigator.pop(_ctx);
                },
                child: Container(
                  width: 20,
                  height: 20,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: col,
                    shape: BoxShape.circle,
                    border: c.colour == col ? Border.all(color: p.text, width: 2) : null,
                  ),
                ),
              ),
          ]),
        ),
        if (c.readOnly) _menuItem(p, 'sync', Icons.sync_rounded, 'Refresh now'),
        _menuItem(p, 'remove', Icons.delete_outline_rounded, c.readOnly ? 'Unsubscribe' : 'Delete calendar'),
      ],
    );
    if (!mounted) return;
    switch (r) {
      case 'rename':
        await _ask('Rename calendar', 'Name', '', (name, _) async {
          if (name.trim().isEmpty) return 'Give it a name';
          c.name = name.trim();
          store.update(c);
          return null;
        }, initial: c.name);
      case 'sync':
        await store.syncAll();
        if (c.error != null) _toast(c.error!);
      case 'remove':
        final ok = await showDialog<bool>(
          context: _ctx,
          builder: (context) => AlertDialog(
            backgroundColor: p.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: Text(c.readOnly ? 'Unsubscribe from ${c.name}?' : 'Delete ${c.name}?',
                style: TextStyle(color: p.text, fontSize: 16, fontWeight: FontWeight.w700)),
            content: Text(c.readOnly ? 'Its events disappear from here.' : 'Its events are deleted for good.',
                style: TextStyle(color: p.dimText, fontSize: 13)),
            actions: [
              PillButton(palette: p, label: 'Cancel', onTap: () => Navigator.pop(context, false)),
              PillButton(palette: p, label: c.readOnly ? 'Unsubscribe' : 'Delete', filled: true, onTap: () => Navigator.pop(context, true)),
            ],
          ),
        );
        if (ok ?? false) store.remove(c);
    }
  }

  String? _toastText;
  Timer? _toastTimer;
  void _toast(String t) {
    setState(() => _toastText = t);
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(seconds: 4), () => setState(() => _toastText = null));
  }

  // ------------------------------------------------------------ keys

  static final _viewKeys = {
    LogicalKeyboardKey.keyD: View.day,
    LogicalKeyboardKey.keyW: View.week,
    LogicalKeyboardKey.keyM: View.month,
    LogicalKeyboardKey.keyA: View.agenda,
  };

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    // Typing in a text field (search, the path): its keys are its own.
    if (FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<EditableText>() != null) {
      return KeyEventResult.ignored;
    }
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final key = e.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.pageUp) {
      _step(-1);
    } else if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.pageDown) {
      _step(1);
    } else if (key == LogicalKeyboardKey.keyN) {
      _new(_newStart());
    } else if ((key == LogicalKeyboardKey.keyF && ctrl) || key == LogicalKeyboardKey.slash) {
      _searchFocus.requestFocus();
    } else if (ctrl) {
      return KeyEventResult.ignored;
    } else if (key == LogicalKeyboardKey.keyT) {
      _today();
    } else if (_viewKeys.containsKey(key)) {
      _setView(_viewKeys[key]!);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final p = _p;
    return MaterialApp(
      navigatorKey: _navigator,
      debugShowCheckedModeBanner: false,
      title: 'Forge Calendar',
      color: Colors.transparent,
      theme: p.materialTheme(),
      home: Scaffold(
        backgroundColor: p.window,
        body: Focus(
          focusNode: _focus,
          autofocus: true,
          onKeyEvent: _onKey,
          child: Stack(children: [
            Row(children: [
              _sidebar(p),
              Expanded(
                child: Column(children: [
                  _header(p),
                  Expanded(child: _body(p)),
                ]),
              ),
            ]),
            if (_reminder != null)
              Positioned(
                top: 14,
                left: 0,
                right: 0,
                child: Center(child: _reminderBanner(p, _reminder!)),
              ),
            if (_toastText != null)
              Positioned(
                bottom: 20,
                left: 0,
                right: 0,
                child: Center(
                  child: Material(
                    color: p.surface,
                    elevation: 6,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Text(_toastText!, style: TextStyle(color: p.text, fontSize: 13)),
                    ),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _sidebar(ForgePalette p) {
    final upcoming = store.between(DateTime.now(), addDays(today(), 2)).where((o) => o.end.isAfter(DateTime.now())).take(4).toList();
    return Container(
      width: 260,
      color: p.sidebar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
        children: [
          SizedBox(
            height: 40,
            child: Material(
              color: p.accent,
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => _new(_newStart()),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.add_rounded, color: p.onAccent, size: 20),
                  const SizedBox(width: 6),
                  Text('New event', style: TextStyle(color: p.onAccent, fontSize: 14, fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 18),
          MiniMonth(
            palette: p,
            store: store,
            month: _miniMonth,
            selected: _selected,
            onPick: _pick,
            onMonth: (m) => setState(() => _miniMonth = m),
          ),
          if (upcoming.isNotEmpty) ...[
            const SizedBox(height: 18),
            _label(p, 'Coming up'),
            for (final o in upcoming)
              InkWell(
                onTap: () => _open(o),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
                  child: Row(children: [
                    Container(
                      width: 3,
                      height: 30,
                      decoration: BoxDecoration(
                        color: store.calendar(o.event.calendar)?.colour ?? p.accent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(o.event.title,
                            overflow: TextOverflow.ellipsis, style: TextStyle(color: p.text, fontSize: 12.5, fontWeight: FontWeight.w600)),
                        Text(
                          '${relativeDay(o.start)}${o.allDay ? '' : ', ${hm(o.start)}'}',
                          style: TextStyle(color: p.dimText, fontSize: 11.5),
                        ),
                      ]),
                    ),
                  ]),
                ),
              ),
          ],
          const SizedBox(height: 18),
          Row(children: [
            Expanded(child: _label(p, 'Calendars')),
            InkResponse(
              onTap: _addCalendar,
              radius: 14,
              child: Tooltip(message: 'Add a calendar', child: Icon(Icons.add_rounded, size: 18, color: p.dimText)),
            ),
          ]),
          for (final c in store.calendars)
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                c.visible = !c.visible;
                store.update(c);
              },
              onSecondaryTapDown: (d) => _calendarMenu(c, d.globalPosition),
              onLongPress: () => _calendarMenu(c, const Offset(40, 500)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                child: Row(children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: c.visible ? c.colour : Colors.transparent,
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: c.colour, width: 2),
                    ),
                    child: c.visible ? const Icon(Icons.check_rounded, size: 11, color: Colors.white) : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(c.name, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.text, fontSize: 13))),
                  if (c.readOnly)
                    Tooltip(
                      message: c.error ?? (c.synced == null ? 'Not fetched yet' : 'Updated ${relativeDay(c.synced!).toLowerCase()}, ${hm(c.synced!)}'),
                      child: Icon(c.error != null ? Icons.cloud_off_rounded : Icons.cloud_done_outlined,
                          size: 15, color: c.error != null ? p.negative : p.dimText),
                    ),
                ]),
              ),
            ),
          const SizedBox(height: 6),
          Text('Right-click a calendar to rename, recolour or remove it.',
              style: TextStyle(color: p.dimText.withValues(alpha: 0.7), fontSize: 11)),
        ],
      ),
    );
  }

  Widget _reminderBanner(ForgePalette p, Occurrence o) => Material(
        // Solid: it sits over the header.
        color: p.surface.withAlpha(250),
        elevation: 10,
        shadowColor: Colors.black54,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 440,
          padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: store.calendar(o.event.calendar)?.colour ?? p.accent, width: 1.5),
          ),
          child: Row(children: [
            Icon(Icons.notifications_active_rounded, color: store.calendar(o.event.calendar)?.colour ?? p.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(o.event.title, style: TextStyle(color: p.text, fontSize: 15, fontWeight: FontWeight.w700)),
                Text(
                  [
                    o.allDay ? relativeDay(o.start) : '${relativeDay(o.start)}, ${hm(o.start)} – ${hm(o.end)}',
                    if (o.event.location.isNotEmpty) o.event.location,
                  ].join(' · '),
                  style: TextStyle(color: p.dimText, fontSize: 12.5),
                ),
              ]),
            ),
            PillButton(palette: p, label: 'Open', onTap: () {
              final x = o;
              setState(() => _reminder = null);
              _open(x);
            }),
            const SizedBox(width: 6),
            PillButton(palette: p, label: 'Dismiss', filled: true, onTap: () => setState(() => _reminder = null)),
          ]),
        ),
      );

  Widget _label(ForgePalette p, String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6, left: 4),
        child: Text(t.toUpperCase(), style: TextStyle(color: p.dimText, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
      );

  Widget _header(ForgePalette p) => Container(
        height: 62,
        padding: const EdgeInsets.fromLTRB(20, 8, 16, 8),
        child: Row(children: [
          PillButton(palette: p, label: 'Today', onTap: _today),
          const SizedBox(width: 10),
          _navBtn(p, Icons.chevron_left_rounded, () => _step(-1)),
          _navBtn(p, Icons.chevron_right_rounded, () => _step(1)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(_results != null ? 'Search' : _heading,
                overflow: TextOverflow.ellipsis, style: TextStyle(color: p.text, fontSize: 21, fontWeight: FontWeight.w800)),
          ),
          SizedBox(
            width: 200,
            height: 36,
            child: TextField(
              controller: _searchText,
              focusNode: _searchFocus,
              style: TextStyle(color: p.text, fontSize: 13.5),
              decoration: InputDecoration(
                hintText: 'Search events',
                hintStyle: TextStyle(color: p.dimText, fontSize: 13.5),
                prefixIcon: Icon(Icons.search_rounded, size: 18, color: p.dimText),
                filled: true,
                fillColor: p.card,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
              onChanged: (q) => setState(() => _results = q.trim().isEmpty ? null : store.search(q.trim())),
              onSubmitted: (_) => _focus.requestFocus(),
            ),
          ),
          const SizedBox(width: 12),
          Segmented<View>(
            palette: p,
            options: const {View.day: 'Day', View.week: 'Week', View.month: 'Month', View.agenda: 'Agenda'},
            value: _view,
            onChanged: _setView,
          ),
        ]),
      );

  Widget _navBtn(ForgePalette p, IconData icon, VoidCallback onTap) => InkResponse(
        onTap: onTap,
        radius: 18,
        child: Padding(padding: const EdgeInsets.all(5), child: Icon(icon, color: p.text, size: 22)),
      );

  Widget _body(ForgePalette p) {
    if (_results != null) {
      return AgendaView(store: store, palette: p, from: today(), onOpen: _open, results: _results);
    }
    return switch (_view) {
      View.month => MonthView(
          store: store,
          palette: p,
          month: DateTime(_selected.year, _selected.month),
          selected: _selected,
          onSelect: _pick,
          onOpen: _open,
          onNew: _new,
          onShowDay: (d) => setState(() {
            _selected = d;
            _view = View.day;
          }),
        ),
      View.week => TimelineView(
          key: ValueKey('w${weekStart(_selected)}'),
          store: store,
          palette: p,
          first: weekStart(_selected),
          days: 7,
          onOpen: _open,
          onNew: _new,
          onSelect: (d) => setState(() {
            _selected = d;
            _view = View.day;
          }),
        ),
      View.day => TimelineView(
          key: ValueKey('d$_selected'),
          store: store,
          palette: p,
          first: _selected,
          days: 1,
          onOpen: _open,
          onNew: _new,
          onSelect: _pick,
        ),
      View.agenda => AgendaView(store: store, palette: p, from: _selected, onOpen: _open),
    };
  }
}
