// Dates, as the calendar needs them: days without times, weeks starting
// on the locale's first day, and names.
import 'dart:io';

const monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];
const dayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

DateTime day(DateTime t) => DateTime(t.year, t.month, t.day);
DateTime addDays(DateTime t, int n) => DateTime(t.year, t.month, t.day + n, t.hour, t.minute);
bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
DateTime today() => day(DateTime.now());

/// The weekday weeks start on (DateTime.monday..sunday), from the locale
/// (`locale first_weekday week-1stday`): Sunday for en_US and en_IN,
/// Monday for most of Europe.
final int firstWeekday = () {
  try {
    final r = Process.runSync('locale', ['first_weekday', 'week-1stday']);
    final lines = (r.stdout as String).trim().split('\n');
    final first = int.parse(lines[0].trim());
    final base = lines[1].trim(); // a date that is the week's day 1
    final d = DateTime(int.parse(base.substring(0, 4)), int.parse(base.substring(4, 6)), int.parse(base.substring(6, 8)));
    return ((d.weekday - 1 + first - 1) % 7) + 1;
  } catch (_) {
    return DateTime.monday;
  }
}();

DateTime weekStart(DateTime t) {
  final d = day(t);
  return addDays(d, -((d.weekday - firstWeekday + 7) % 7));
}

/// The 6 weeks shown for [month]'s grid.
DateTime monthGridStart(DateTime month) => weekStart(DateTime(month.year, month.month, 1));

String shortDay(int weekday) => dayNames[weekday - 1].substring(0, 3);
String shortMonth(int month) => monthNames[month - 1].substring(0, 3);

String two(int n) => n.toString().padLeft(2, '0');
String hm(DateTime t) => '${two(t.hour)}:${two(t.minute)}';

/// "Saturday 31 October 2026"
String longDate(DateTime t) => '${dayNames[t.weekday - 1]} ${t.day} ${monthNames[t.month - 1]} ${t.year}';

/// "Sat 31 Oct"
String shortDate(DateTime t) => '${shortDay(t.weekday)} ${t.day} ${shortMonth(t.month)}';

String relativeDay(DateTime t) {
  final d = day(t);
  final now = today();
  if (d == now) return 'Today';
  if (d == addDays(now, 1)) return 'Tomorrow';
  if (d == addDays(now, -1)) return 'Yesterday';
  return d.year == now.year ? shortDate(d) : '${shortDate(d)} ${d.year}';
}
