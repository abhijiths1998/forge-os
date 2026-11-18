// The event editor: a Forge sheet with the title, when, repeat, reminder,
// calendar, place and notes. Also asks, for repeating events, whether a
// change is for one day or all of them.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forge_ui/forge_ui.dart';

import 'dates.dart';
import 'ics.dart';
import 'store.dart';

enum Scope { one, all }

Future<Scope?> askScope(BuildContext context, ForgePalette p, String verb) => showDialog<Scope>(
      context: context,
      barrierColor: Colors.black26,
      builder: (context) => Dialog(
        backgroundColor: p.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$verb a repeating event', style: TextStyle(color: p.text, fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text('Just this one, or every time it repeats?', style: TextStyle(color: p.dimText, fontSize: 13)),
              const SizedBox(height: 18),
              Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: [
                PillButton(palette: p, label: 'Cancel', onTap: () => Navigator.pop(context)),
                PillButton(palette: p, label: 'This one', onTap: () => Navigator.pop(context, Scope.one)),
                PillButton(palette: p, label: 'All of them', filled: true, onTap: () => Navigator.pop(context, Scope.all)),
              ]),
            ]),
          ),
        ),
      ),
    );

/// Edit [o] (an existing occurrence) or create a new event starting at
/// [start]. Returns when it's saved, deleted or dismissed.
Future<void> editEvent(
  BuildContext context,
  ForgePalette p,
  Store store, {
  Occurrence? o,
  DateTime? start,
  bool allDay = false,
}) async {
  CalEvent event;
  String? fromCalendar;
  final existing = o != null;
  if (o != null) {
    event = o.event.copy();
    fromCalendar = o.event.calendar;
  } else {
    final s = start ?? _nextHalfHour();
    event = CalEvent(
      uid: Store.newUid(),
      calendar: store.defaultCalendar.id,
      title: '',
      start: allDay ? day(s) : s,
      end: allDay ? addDays(day(s), 1) : s.add(const Duration(hours: 1)),
      allDay: allDay,
      alarm: allDay ? null : 10,
    );
  }
  final readOnly = store.calendar(event.calendar)?.readOnly ?? false;
  await showDialog(
    context: context,
    barrierColor: Colors.black26,
    builder: (context) => _Editor(
      p: p,
      store: store,
      event: event,
      occurrence: o,
      existing: existing,
      readOnly: readOnly,
      fromCalendar: fromCalendar,
    ),
  );
}

DateTime _nextHalfHour() {
  final n = DateTime.now();
  final m = n.minute < 30 ? 30 : 60;
  return DateTime(n.year, n.month, n.day, n.hour).add(Duration(minutes: m));
}

class _Editor extends StatefulWidget {
  const _Editor({
    required this.p,
    required this.store,
    required this.event,
    required this.occurrence,
    required this.existing,
    required this.readOnly,
    required this.fromCalendar,
  });

  final ForgePalette p;
  final Store store;
  final CalEvent event;
  final Occurrence? occurrence;
  final bool existing;
  final bool readOnly;
  final String? fromCalendar;

  @override
  State<_Editor> createState() => _EditorState();
}

enum _Repeat { none, daily, weekdays, weekly, monthly, yearly }

class _EditorState extends State<_Editor> {
  late final CalEvent e = widget.event;
  late final _title = TextEditingController(text: e.title);
  late final _where = TextEditingController(text: e.location);
  late final _notes = TextEditingController(text: e.notes);
  // Editing one occurrence: show its own day, not the series' first.
  late DateTime _start = widget.occurrence?.start ?? e.start;
  late DateTime _end = widget.occurrence?.end ?? e.end;
  late _Repeat _repeat = _repeatOf(e.repeat);
  String? _error;

  static const _alarms = <int?, String>{
    null: 'No reminder',
    0: 'When it starts',
    5: '5 minutes before',
    10: '10 minutes before',
    15: '15 minutes before',
    30: '30 minutes before',
    60: '1 hour before',
    1440: '1 day before',
  };

  _Repeat _repeatOf(Recurrence? r) {
    if (r == null) return _Repeat.none;
    return switch (r.freq) {
      Freq.daily => _Repeat.daily,
      Freq.weekly => r.byDay.length == 5 && !r.byDay.contains(6) && !r.byDay.contains(7) ? _Repeat.weekdays : _Repeat.weekly,
      Freq.monthly => _Repeat.monthly,
      Freq.yearly => _Repeat.yearly,
    };
  }

  Recurrence? _recurrence() {
    final keep = e.repeat; // keep an UNTIL/COUNT/INTERVAL we didn't touch
    Recurrence make(Freq f, {List<int> byDay = const []}) => (keep != null && keep.freq == f && byDay.isEmpty == keep.byDay.isEmpty)
        ? Recurrence(f, interval: keep.interval, count: keep.count, until: keep.until, byDay: byDay.isEmpty ? keep.byDay : byDay)
        : Recurrence(f, byDay: byDay);
    return switch (_repeat) {
      _Repeat.none => null,
      _Repeat.daily => make(Freq.daily),
      _Repeat.weekdays => make(Freq.weekly, byDay: const [1, 2, 3, 4, 5]),
      _Repeat.weekly => make(Freq.weekly),
      _Repeat.monthly => make(Freq.monthly),
      _Repeat.yearly => make(Freq.yearly),
    };
  }

  @override
  void dispose() {
    _title.dispose();
    _where.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool isStart) async {
    final cur = isStart ? _start : (e.allDay ? addDays(_end, -1) : _end);
    final d = await showDatePicker(
      context: context,
      initialDate: cur,
      firstDate: DateTime(1970),
      lastDate: DateTime(2200),
      builder: (context, child) => _themed(child!),
    );
    if (d == null) return;
    setState(() {
      if (isStart) {
        final len = _end.difference(_start);
        _start = DateTime(d.year, d.month, d.day, _start.hour, _start.minute);
        _end = _start.add(len);
      } else {
        _end = e.allDay ? addDays(d, 1) : DateTime(d.year, d.month, d.day, _end.hour, _end.minute);
      }
    });
  }

  Future<void> _pickTime(bool isStart) async {
    final cur = isStart ? _start : _end;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(cur),
      builder: (context, child) => _themed(MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      )),
    );
    if (t == null) return;
    setState(() {
      if (isStart) {
        final len = _end.difference(_start);
        _start = DateTime(_start.year, _start.month, _start.day, t.hour, t.minute);
        _end = _start.add(len);
      } else {
        _end = DateTime(_end.year, _end.month, _end.day, t.hour, t.minute);
        if (!_end.isAfter(_start)) _end = _end.add(const Duration(days: 1));
      }
    });
  }

  Widget _themed(Widget child) {
    final p = widget.p;
    return Theme(
      data: p.materialTheme().copyWith(
        dialogTheme: DialogThemeData(backgroundColor: p.surface),
        colorScheme: p.materialTheme().colorScheme.copyWith(surface: p.surface, onSurface: p.text),
      ),
      child: child,
    );
  }

  void _setAllDay(bool on) {
    setState(() {
      e.allDay = on;
      if (on) {
        _start = day(_start);
        _end = addDays(day(_end.subtract(const Duration(seconds: 1))), 1);
        if (!_end.isAfter(_start)) _end = addDays(_start, 1);
      } else {
        _start = DateTime(_start.year, _start.month, _start.day, 9);
        _end = _start.add(const Duration(hours: 1));
      }
    });
  }

  Future<void> _save() async {
    if (!_end.isAfter(_start)) {
      setState(() => _error = 'It has to end after it starts');
      return;
    }
    final store = widget.store;
    final o = widget.occurrence;
    var target = e;
    final wasRepeating = o != null && o.event.repeat != null;
    if (wasRepeating) {
      final scope = await askScope(context, widget.p, 'Change');
      if (scope == null) return;
      if (scope == Scope.one) {
        target = store.detach(o);
        store.save(o.event); // its exception
      }
    }
    target
      ..title = _title.text.trim().isEmpty ? '(No title)' : _title.text.trim()
      ..location = _where.text.trim()
      ..notes = _notes.text.trim()
      ..allDay = e.allDay
      ..alarm = e.alarm
      ..calendar = e.calendar;
    if (target == e) {
      // A whole series moves by how much this occurrence moved.
      final shift = o == null ? Duration.zero : _start.difference(o.start);
      final len = _end.difference(_start);
      target.start = o == null ? _start : o.event.start.add(shift);
      target.end = target.start.add(len);
      if (e.allDay) target.end = addDays(day(target.start), len.inDays.clamp(1, 1 << 20));
      target.repeat = _recurrence();
    } else {
      target
        ..start = _start
        ..end = _end;
    }
    store.save(target, fromCalendar: target == e ? widget.fromCalendar : null);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final o = widget.occurrence!;
    if (o.event.repeat != null) {
      final scope = await askScope(context, widget.p, 'Delete');
      if (scope == null) return;
      if (scope == Scope.one) {
        widget.store.skipOccurrence(o);
      } else {
        widget.store.delete(o.event);
      }
    } else {
      widget.store.delete(o.event);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final ro = widget.readOnly;
    final cal = widget.store.calendar(e.calendar);
    final fieldStyle = TextStyle(color: p.text, fontSize: 14);
    InputDecoration deco(String hint, IconData icon) => InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: p.dimText),
          prefixIcon: Icon(icon, size: 18, color: p.dimText),
          filled: true,
          fillColor: p.card,
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        );
    Widget chip(String text, VoidCallback? onTap) => InkWell(
          onTap: ro ? null : onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(10)),
            child: Text(text, style: TextStyle(color: p.text, fontSize: 13.5, fontWeight: FontWeight.w500)),
          ),
        );
    final endDay = e.allDay ? addDays(_end, -1) : _end;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, control: true): _save,
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
      },
      child: Dialog(
        backgroundColor: p.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 12, height: 12, decoration: BoxDecoration(color: cal?.colour ?? p.accent, shape: BoxShape.circle)),
                const SizedBox(width: 10),
                Text(widget.existing ? (ro ? 'Event' : 'Edit event') : 'New event',
                    style: TextStyle(color: p.dimText, fontSize: 13, fontWeight: FontWeight.w600)),
                const Spacer(),
                if (ro) Text('Read-only calendar', style: TextStyle(color: p.dimText, fontSize: 12)),
              ]),
              const SizedBox(height: 10),
              TextField(
                controller: _title,
                autofocus: !widget.existing,
                readOnly: ro,
                style: TextStyle(color: p.text, fontSize: 20, fontWeight: FontWeight.w700),
                decoration: InputDecoration(
                  hintText: 'Title',
                  hintStyle: TextStyle(color: p.dimText),
                  border: InputBorder.none,
                ),
                onSubmitted: (_) => ro ? null : _save(),
              ),
              const SizedBox(height: 6),
              Row(children: [
                Icon(Icons.schedule_rounded, size: 18, color: p.dimText),
                const SizedBox(width: 10),
                Text('All day', style: TextStyle(color: p.text, fontSize: 13.5)),
                const Spacer(),
                Switch(value: e.allDay, activeTrackColor: p.accent, onChanged: ro ? null : _setAllDay),
              ]),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                chip(shortDate(_start) + (_start.year != DateTime.now().year ? ' ${_start.year}' : ''), () => _pickDate(true)),
                if (!e.allDay) chip(hm(_start), () => _pickTime(true)),
                Text('→', style: TextStyle(color: p.dimText)),
                if (e.allDay || !sameDay(_start, _end))
                  chip(shortDate(endDay) + (endDay.year != DateTime.now().year ? ' ${endDay.year}' : ''), () => _pickDate(false)),
                if (!e.allDay) chip(hm(_end), () => _pickTime(false)),
              ]),
              if (_error != null) ...[
                const SizedBox(height: 6),
                Text(_error!, style: TextStyle(color: p.negative, fontSize: 12.5)),
              ],
              const SizedBox(height: 14),
              _dropdown<_Repeat>(
                p,
                Icons.repeat_rounded,
                _repeat,
                {
                  _Repeat.none: 'Doesn\'t repeat',
                  _Repeat.daily: 'Every day',
                  _Repeat.weekdays: 'Every weekday (Mon–Fri)',
                  _Repeat.weekly: 'Every week on ${dayNames[_start.weekday - 1]}',
                  _Repeat.monthly: 'Every month on the ${_start.day}${_ordinal(_start.day)}',
                  _Repeat.yearly: 'Every year on ${_start.day} ${monthNames[_start.month - 1]}',
                },
                ro || (widget.occurrence?.event.uid.contains('#') ?? false) ? null : (v) => setState(() => _repeat = v),
              ),
              const SizedBox(height: 8),
              _dropdown<int?>(p, Icons.notifications_none_rounded, _alarms.containsKey(e.alarm) ? e.alarm : null, _alarms,
                  ro ? null : (v) => setState(() => e.alarm = v)),
              const SizedBox(height: 8),
              _dropdown<String>(
                p,
                Icons.calendar_today_rounded,
                e.calendar,
                {for (final c in ro ? [cal!] : widget.store.writable) c.id: c.name},
                ro ? null : (v) => setState(() => e.calendar = v),
                colours: {for (final c in widget.store.calendars) c.id: c.colour},
              ),
              const SizedBox(height: 8),
              TextField(controller: _where, readOnly: ro, style: fieldStyle, decoration: deco('Place', Icons.place_outlined)),
              const SizedBox(height: 8),
              TextField(
                controller: _notes,
                readOnly: ro,
                style: fieldStyle,
                minLines: 2,
                maxLines: 6,
                decoration: deco('Notes', Icons.notes_rounded),
              ),
              const SizedBox(height: 16),
              Row(children: [
                if (widget.existing && !ro)
                  TextButton.icon(
                    onPressed: _delete,
                    icon: Icon(Icons.delete_outline_rounded, color: p.negative, size: 18),
                    label: Text('Delete', style: TextStyle(color: p.negative)),
                  ),
                const Spacer(),
                PillButton(palette: p, label: ro ? 'Close' : 'Cancel', onTap: () => Navigator.pop(context)),
                if (!ro) ...[
                  const SizedBox(width: 8),
                  PillButton(palette: p, label: 'Save', filled: true, onTap: _save),
                ],
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  static String _ordinal(int n) {
    if (n >= 11 && n <= 13) return 'th';
    return switch (n % 10) { 1 => 'st', 2 => 'nd', 3 => 'rd', _ => 'th' };
  }

  Widget _dropdown<T>(ForgePalette p, IconData icon, T value, Map<T, String> options, ValueChanged<T>? onChanged,
      {Map<T, Color>? colours}) {
    return Container(
      padding: const EdgeInsets.only(left: 12, right: 8),
      decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        Icon(icon, size: 18, color: p.dimText),
        const SizedBox(width: 10),
        Expanded(
          child: DropdownButton<T>(
            value: options.containsKey(value) ? value : options.keys.first,
            isExpanded: true,
            underline: const SizedBox(),
            dropdownColor: p.surface,
            borderRadius: BorderRadius.circular(12),
            style: TextStyle(color: p.text, fontSize: 13.5),
            iconEnabledColor: p.dimText,
            items: [
              for (final o in options.entries)
                DropdownMenuItem(
                  value: o.key,
                  child: Row(children: [
                    if (colours?[o.key] != null) ...[
                      Container(width: 10, height: 10, decoration: BoxDecoration(color: colours![o.key], shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                    ],
                    Flexible(child: Text(o.value, overflow: TextOverflow.ellipsis)),
                  ]),
                ),
            ],
            onChanged: onChanged == null ? null : (v) => onChanged(v as T),
          ),
        ),
      ]),
    );
  }
}
