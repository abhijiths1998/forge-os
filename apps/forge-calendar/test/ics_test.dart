import 'package:forge_calendar/ics.dart';
import 'package:test/test.dart';

void main() {
  test('round trip with repeat, alarm and folding', () {
    final e = CalEvent(
      uid: 'a@forge', calendar: 'p', title: 'Stand-up; daily, with a very long title that has to be folded across lines ok',
      start: DateTime(2026, 11, 2, 9, 30), end: DateTime(2026, 11, 2, 9, 45),
      repeat: const Recurrence(Freq.weekly, byDay: [1, 3, 5]), alarm: 10, notes: 'line1\nline2',
      exdates: {DateTime(2026, 11, 4, 9, 30)});
    final text = writeIcs([e]);
    expect(text.split('\r\n').every((l) => l.length <= 75), isTrue);
    final back = parseIcs(text, 'p').single;
    expect(back.title, e.title);
    expect(back.notes, 'line1\nline2');
    expect(back.start, e.start);
    expect(back.alarm, 10);
    final occ = back.between(DateTime(2026, 11, 1), DateTime(2026, 11, 15)).map((o) => o.start.day).toList();
    expect(occ, [2, 6, 9, 11, 13]); // Mon Wed Fri, minus Wed 4th
  });
  test('all-day and monthly 31st skips short months', () {
    final e = CalEvent(uid: 'b', calendar: 'p', title: 'Rent', start: DateTime(2026, 1, 31), end: DateTime(2026, 2, 1),
        allDay: true, repeat: const Recurrence(Freq.monthly, count: 4));
    final back = parseIcs(writeIcs([e]), 'p').single;
    expect(back.allDay, isTrue);
    final occ = back.between(DateTime(2026, 1, 1), DateTime(2027, 1, 1)).map((o) => '${o.start.month}/${o.start.day}').toList();
    expect(occ, ['1/31', '3/31', '5/31', '7/31']);
  });
  test('google-style UTC, TZID, override and DURATION', () {
    const ics = 'BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:g1\r\nDTSTART:20261105T100000Z\r\nDURATION:PT1H\r\n'
        'RRULE:FREQ=DAILY;COUNT=3\r\nSUMMARY:Sync\r\nBEGIN:VALARM\r\nTRIGGER:-P1D\r\nEND:VALARM\r\nEND:VEVENT\r\n'
        'BEGIN:VEVENT\r\nUID:g1\r\nRECURRENCE-ID:20261106T100000Z\r\nDTSTART;TZID=Asia/Kolkata:20261106T180000\r\n'
        'DTEND;TZID=Asia/Kolkata:20261106T190000\r\nSUMMARY:Sync (moved)\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n';
    final evs = parseIcs(ics, 'g');
    expect(evs.length, 2);
    expect(evs.first.alarm, 1440);
    final occ = evs.expand((e) => e.between(DateTime(2026, 11, 1), DateTime(2026, 11, 30))).toList();
    expect(occ.length, 3);
    expect(occ.where((o) => o.event.title == 'Sync (moved)').single.start, DateTime(2026, 11, 6, 18));
  });
}
