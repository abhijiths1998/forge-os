// iCalendar (RFC 5545), the parts a personal calendar needs: events with
// times or whole days, repeats (RRULE: daily, weekly on given days,
// monthly, yearly, every N, until or count, with EXDATE exceptions) and a
// reminder (VALARM). Calendars are kept as .ics so any other app can read
// them, and subscriptions (Google's "secret address", holidays...) are .ics
// too.
//
// Times with a TZID are read as local time: right when the calendar is in
// this machine's zone, which is the usual case for one's own calendars.
import 'dart:math';

enum Freq { daily, weekly, monthly, yearly }

class Recurrence {
  const Recurrence(this.freq, {this.interval = 1, this.count, this.until, this.byDay = const []});

  final Freq freq;
  final int interval;
  final int? count;
  final DateTime? until;

  /// Weekdays (DateTime.monday..sunday) for weekly repeats.
  final List<int> byDay;

  static const _days = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];

  static Recurrence? parse(String v) {
    final parts = {
      for (final p in v.split(';'))
        if (p.contains('=')) p.substring(0, p.indexOf('=')).toUpperCase(): p.substring(p.indexOf('=') + 1),
    };
    final freq = switch (parts['FREQ']) {
      'DAILY' => Freq.daily,
      'WEEKLY' => Freq.weekly,
      'MONTHLY' => Freq.monthly,
      'YEARLY' => Freq.yearly,
      _ => null,
    };
    if (freq == null) return null;
    final byDay = <int>[];
    for (final d in (parts['BYDAY'] ?? '').split(',')) {
      // "MO", or "1MO"/"-1FR" (nth weekday of the month: kept as the day).
      final m = RegExp(r'([+-]?\d+)?([A-Z]{2})').firstMatch(d.trim());
      if (m != null) {
        final i = _days.indexOf(m.group(2)!);
        if (i >= 0) byDay.add(i + 1);
      }
    }
    return Recurrence(
      freq,
      interval: int.tryParse(parts['INTERVAL'] ?? '') ?? 1,
      count: int.tryParse(parts['COUNT'] ?? ''),
      until: parts['UNTIL'] == null ? null : parseIcsTime(parts['UNTIL']!).$1,
      byDay: freq == Freq.weekly ? byDay : const [],
    );
  }

  String format() {
    final out = ['FREQ=${freq.name.toUpperCase()}'];
    if (interval > 1) out.add('INTERVAL=$interval');
    if (count != null) out.add('COUNT=$count');
    if (until != null) out.add('UNTIL=${formatUtc(until!)}');
    if (byDay.isNotEmpty) out.add('BYDAY=${byDay.map((d) => _days[d - 1]).join(',')}');
    return out.join(';');
  }

  String describe(DateTime start) {
    final every = interval == 1 ? '' : ' $interval';
    final base = switch (freq) {
      Freq.daily => interval == 1 ? 'Every day' : 'Every$every days',
      Freq.weekly => interval == 1 ? 'Every week' : 'Every$every weeks',
      Freq.monthly => interval == 1 ? 'Every month' : 'Every$every months',
      Freq.yearly => interval == 1 ? 'Every year' : 'Every$every years',
    };
    return base;
  }
}

class CalEvent {
  CalEvent({
    required this.uid,
    required this.calendar,
    required this.title,
    required this.start,
    required this.end,
    this.allDay = false,
    this.location = '',
    this.notes = '',
    this.repeat,
    Set<DateTime>? exdates,
    this.alarm,
    this.extra = const [],
  }) : exdates = exdates ?? {};

  String uid;
  String calendar;
  String title;
  DateTime start;

  /// Exclusive; for all-day events, midnight after the last day.
  DateTime end;
  bool allDay;
  String location;
  String notes;
  Recurrence? repeat;
  Set<DateTime> exdates;

  /// Minutes before the start to remind; null for none.
  int? alarm;

  /// Lines we don't edit (ORGANIZER, ATTENDEE...), written back as read.
  List<String> extra;

  Duration get length => end.difference(start);

  CalEvent copy() => CalEvent(
        uid: uid,
        calendar: calendar,
        title: title,
        start: start,
        end: end,
        allDay: allDay,
        location: location,
        notes: notes,
        repeat: repeat,
        exdates: {...exdates},
        alarm: alarm,
        extra: extra,
      );

  /// Occurrences that overlap [from, to).
  Iterable<Occurrence> between(DateTime from, DateTime to) sync* {
    final r = repeat;
    if (r == null) {
      if (start.isBefore(to) && end.isAfter(from)) yield Occurrence(this, start, end);
      return;
    }
    final len = length;
    var n = 0;
    bool ok(DateTime s) => !exdates.any((x) => _sameStart(x, s));
    bool done(DateTime s) => (r.until != null && s.isAfter(r.until!)) || (r.count != null && n >= r.count!) || !s.isBefore(to);

    if (r.freq == Freq.weekly && r.byDay.isNotEmpty) {
      // Week by week from the start's week, each listed day in it.
      final weekStart = DateTime(start.year, start.month, start.day - (start.weekday - 1));
      for (var w = 0; w < 5000; w += r.interval) {
        for (final d in [...r.byDay]..sort()) {
          final day = DateTime(weekStart.year, weekStart.month, weekStart.day + w * 7 + d - 1);
          final s = DateTime(day.year, day.month, day.day, start.hour, start.minute, start.second);
          if (s.isBefore(start)) continue;
          if (done(s)) return;
          n++;
          if (s.add(len).isAfter(from) && ok(s)) yield Occurrence(this, s, _addLen(s, len));
        }
      }
      return;
    }
    for (var i = 0; i < 20000; i++) {
      final s = _nth(i * r.interval, r.freq);
      if (s == null) continue; // the 31st in a short month
      if (done(s)) return;
      n++;
      if (s.add(len).isAfter(from) && ok(s)) yield Occurrence(this, s, _addLen(s, len));
    }
  }

  DateTime _addLen(DateTime s, Duration len) {
    // Whole days stay whole days across daylight saving changes.
    if (allDay) return DateTime(s.year, s.month, s.day + len.inDays.clamp(1, 1 << 20));
    return s.add(len);
  }

  DateTime? _nth(int k, Freq f) {
    final s = start;
    switch (f) {
      case Freq.daily:
        return DateTime(s.year, s.month, s.day + k, s.hour, s.minute, s.second);
      case Freq.weekly:
        return DateTime(s.year, s.month, s.day + 7 * k, s.hour, s.minute, s.second);
      case Freq.monthly:
        final d = DateTime(s.year, s.month + k, s.day, s.hour, s.minute, s.second);
        return d.day == s.day ? d : null;
      case Freq.yearly:
        final d = DateTime(s.year + k, s.month, s.day, s.hour, s.minute, s.second);
        return d.day == s.day ? d : null;
    }
  }

  static bool _sameStart(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day && a.hour == b.hour && a.minute == b.minute;
}

class Occurrence {
  Occurrence(this.event, this.start, this.end);
  final CalEvent event;
  final DateTime start;
  final DateTime end;
  bool get allDay => event.allDay;
}

// ------------------------------------------------------------------ times

/// "20261031" (a date), "20261031T120000Z" (UTC) or "20261031T120000"
/// (local). Returns the local time and whether it was a date.
(DateTime, bool) parseIcsTime(String v) {
  v = v.trim();
  final date = RegExp(r'^(\d{4})(\d{2})(\d{2})$').firstMatch(v);
  if (date != null) {
    return (DateTime(int.parse(date[1]!), int.parse(date[2]!), int.parse(date[3]!)), true);
  }
  final m = RegExp(r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})(Z?)$').firstMatch(v);
  if (m == null) throw FormatException('bad time $v');
  final parts = [for (var i = 1; i <= 6; i++) int.parse(m[i]!)];
  if (m[7] == 'Z') {
    return (DateTime.utc(parts[0], parts[1], parts[2], parts[3], parts[4], parts[5]).toLocal(), false);
  }
  return (DateTime(parts[0], parts[1], parts[2], parts[3], parts[4], parts[5]), false);
}

String _two(int n) => n.toString().padLeft(2, '0');
String formatDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}${_two(d.month)}${_two(d.day)}';
String formatUtc(DateTime t) {
  final u = t.toUtc();
  return '${formatDate(u)}T${_two(u.hour)}${_two(u.minute)}${_two(u.second)}Z';
}

/// "-PT15M", "-P1D", "PT0S"... as minutes before the start.
int? parseTrigger(String v) {
  final m = RegExp(r'^([+-]?)P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$').firstMatch(v.trim());
  if (m == null) return null;
  final minutes = (int.tryParse(m[2] ?? '') ?? 0) * 7 * 1440 +
      (int.tryParse(m[3] ?? '') ?? 0) * 1440 +
      (int.tryParse(m[4] ?? '') ?? 0) * 60 +
      (int.tryParse(m[5] ?? '') ?? 0);
  return m[1] == '-' ? minutes : -minutes;
}

Duration? _parseDuration(String v) {
  final m = parseTrigger(v.startsWith('-') ? v : '-$v');
  return m == null ? null : Duration(minutes: m);
}

// ------------------------------------------------------------------ text

String _unescape(String v) => v.replaceAllMapped(RegExp(r'\\([\\;,nN])'), (m) => switch (m[1]) {
      'n' || 'N' => '\n',
      _ => m[1]!,
    });

String _escape(String v) =>
    v.replaceAll('\\', '\\\\').replaceAll(';', '\\;').replaceAll(',', '\\,').replaceAll('\n', '\\n');

/// Long lines folded at 75 bytes, as the format wants.
String _fold(String line) {
  if (line.length <= 74) return line;
  final out = StringBuffer();
  var i = 0;
  var first = true;
  while (i < line.length) {
    final take = min(first ? 74 : 73, line.length - i);
    if (!first) out.write('\r\n ');
    out.write(line.substring(i, i + take));
    i += take;
    first = false;
  }
  return out.toString();
}

class _Prop {
  _Prop(this.name, this.params, this.value);
  final String name;
  final Map<String, String> params;
  final String value;
}

_Prop? _parseLine(String line) {
  // NAME;PARAM=x;PARAM="y:z":VALUE
  var inQuote = false;
  var colon = -1;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (ch == '"') inQuote = !inQuote;
    if (ch == ':' && !inQuote) {
      colon = i;
      break;
    }
  }
  if (colon < 0) return null;
  final head = line.substring(0, colon).split(';');
  final params = <String, String>{};
  for (final p in head.skip(1)) {
    final eq = p.indexOf('=');
    if (eq > 0) params[p.substring(0, eq).toUpperCase()] = p.substring(eq + 1).replaceAll('"', '');
  }
  return _Prop(head.first.toUpperCase(), params, line.substring(colon + 1));
}

/// The events in an .ics file's text.
List<CalEvent> parseIcs(String text, String calendar) {
  final lines = <String>[];
  for (final raw in text.replaceAll('\r\n', '\n').split('\n')) {
    if ((raw.startsWith(' ') || raw.startsWith('\t')) && lines.isNotEmpty) {
      lines[lines.length - 1] += raw.substring(1);
    } else if (raw.isNotEmpty) {
      lines.add(raw);
    }
  }
  final events = <CalEvent>[];
  // Edited single occurrences of a repeating event (RECURRENCE-ID) become
  // events of their own, and their original slot an exception.
  final overrides = <(String, DateTime)>[];
  Map<String, _Prop>? ev;
  List<String>? extra;
  List<_Prop>? exdates;
  var inAlarm = false;
  int? alarm;
  for (final line in lines) {
    final p = _parseLine(line);
    if (p == null) continue;
    if (p.name == 'BEGIN' && p.value == 'VEVENT') {
      ev = {};
      extra = [];
      exdates = [];
      alarm = null;
    } else if (p.name == 'BEGIN' && p.value == 'VALARM') {
      inAlarm = true;
    } else if (p.name == 'END' && p.value == 'VALARM') {
      inAlarm = false;
    } else if (p.name == 'END' && p.value == 'VEVENT' && ev != null) {
      final e = _build(ev, extra!, exdates!, alarm, calendar);
      if (e != null) {
        events.add(e);
        final rid = ev['RECURRENCE-ID'];
        if (rid != null) {
          try {
            overrides.add((e.uid, parseIcsTime(rid.value).$1));
            e.uid = '${e.uid}#${formatUtc(parseIcsTime(rid.value).$1)}';
          } catch (_) {}
        }
      }
      ev = null;
    } else if (ev != null && inAlarm) {
      if (p.name == 'TRIGGER' && p.params['VALUE'] != 'DATE-TIME') alarm ??= parseTrigger(p.value);
    } else if (ev != null) {
      if (p.name == 'EXDATE') {
        exdates!.add(p);
      } else if (const {'UID', 'SUMMARY', 'DTSTART', 'DTEND', 'DURATION', 'LOCATION', 'DESCRIPTION', 'RRULE', 'RECURRENCE-ID'}
          .contains(p.name)) {
        ev[p.name] = p;
      } else if (!const {'DTSTAMP', 'CREATED', 'LAST-MODIFIED', 'SEQUENCE'}.contains(p.name)) {
        extra!.add(line);
      }
    }
  }
  for (final (uid, at) in overrides) {
    for (final e in events.where((e) => e.uid == uid)) {
      e.exdates.add(at);
    }
  }
  return events;
}

CalEvent? _build(Map<String, _Prop> ev, List<String> extra, List<_Prop> exdates, int? alarm, String calendar) {
  final dtstart = ev['DTSTART'];
  if (dtstart == null) return null;
  try {
    final (start, isDate) = parseIcsTime(dtstart.value);
    final allDay = isDate || dtstart.params['VALUE'] == 'DATE';
    DateTime end;
    if (ev['DTEND'] != null) {
      end = parseIcsTime(ev['DTEND']!.value).$1;
    } else if (ev['DURATION'] != null) {
      end = start.add(_parseDuration(ev['DURATION']!.value) ?? Duration.zero);
    } else {
      end = allDay ? DateTime(start.year, start.month, start.day + 1) : start;
    }
    if (!end.isAfter(start)) end = allDay ? DateTime(start.year, start.month, start.day + 1) : start.add(const Duration(minutes: 30));
    final ex = <DateTime>{};
    for (final p in exdates) {
      for (final v in p.value.split(',')) {
        try {
          ex.add(parseIcsTime(v).$1);
        } catch (_) {}
      }
    }
    return CalEvent(
      uid: ev['UID']?.value ?? '${start.millisecondsSinceEpoch}-${Random().nextInt(1 << 30)}@forge',
      calendar: calendar,
      title: _unescape(ev['SUMMARY']?.value ?? '(No title)'),
      start: start,
      end: end,
      allDay: allDay,
      location: _unescape(ev['LOCATION']?.value ?? ''),
      notes: _unescape(ev['DESCRIPTION']?.value ?? ''),
      repeat: ev['RRULE'] == null ? null : Recurrence.parse(ev['RRULE']!.value),
      exdates: ex,
      alarm: alarm,
      extra: extra,
    );
  } catch (_) {
    return null;
  }
}

/// A calendar file for [events].
String writeIcs(List<CalEvent> events, {String name = 'Forge Calendar'}) {
  final out = <String>[
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//Forge OS//Forge Calendar//EN',
    'CALSCALE:GREGORIAN',
    'X-WR-CALNAME:${_escape(name)}',
  ];
  final stamp = formatUtc(DateTime.now());
  for (final e in events) {
    final hash = e.uid.indexOf('#');
    out
      ..add('BEGIN:VEVENT')
      ..add('UID:${hash < 0 ? e.uid : e.uid.substring(0, hash)}')
      ..add('DTSTAMP:$stamp');
    if (hash >= 0) out.add('RECURRENCE-ID:${e.uid.substring(hash + 1)}');
    if (e.allDay) {
      out
        ..add('DTSTART;VALUE=DATE:${formatDate(e.start)}')
        ..add('DTEND;VALUE=DATE:${formatDate(e.end)}');
    } else {
      out
        ..add('DTSTART:${formatUtc(e.start)}')
        ..add('DTEND:${formatUtc(e.end)}');
    }
    out.add('SUMMARY:${_escape(e.title)}');
    if (e.location.isNotEmpty) out.add('LOCATION:${_escape(e.location)}');
    if (e.notes.isNotEmpty) out.add('DESCRIPTION:${_escape(e.notes)}');
    if (e.repeat != null) out.add('RRULE:${e.repeat!.format()}');
    for (final x in e.exdates) {
      out.add(e.allDay ? 'EXDATE;VALUE=DATE:${formatDate(x)}' : 'EXDATE:${formatUtc(x)}');
    }
    out.addAll(e.extra);
    if (e.alarm != null) {
      out
        ..add('BEGIN:VALARM')
        ..add('ACTION:DISPLAY')
        ..add('DESCRIPTION:${_escape(e.title)}')
        ..add('TRIGGER:${e.alarm == 0 ? 'PT0S' : '-PT${e.alarm}M'}')
        ..add('END:VALARM');
    }
    out.add('END:VEVENT');
  }
  out.add('END:VCALENDAR');
  return '${out.map(_fold).join('\r\n')}\r\n';
}
