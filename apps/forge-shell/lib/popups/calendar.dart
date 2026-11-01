// The calendar, from the clock in the top bar: the time and date large,
// and a month you can page through (weeks start on Monday). Today is the
// accent dot; clicking the month's name comes back to this month.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

import '../native.dart';
import 'style.dart';

const calendarWidth = 330.0;

const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

class CalendarCard extends StatefulWidget {
  const CalendarCard({super.key, required this.palette});

  final ForgePalette palette;

  @override
  State<CalendarCard> createState() => _CalendarCardState();
}

class _CalendarCardState extends State<CalendarCard> {
  DateTime _now = DateTime.now();
  late DateTime _month = DateTime(_now.year, _now.month);
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _page(int by) =>
      setState(() => _month = DateTime(_month.year, _month.month + by));

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    String two(int n) => n.toString().padLeft(2, '0');
    final first = _month;
    final lead = first.weekday - 1; // blanks before the 1st
    final days = DateTime(first.year, first.month + 1, 0).day;
    final cells = ((lead + days) / 7).ceil() * 7;
    final thisMonth = _month.year == _now.year && _month.month == _now.month;

    return PopupCard(
      palette: p,
      width: calendarWidth,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${two(_now.hour)}:${two(_now.minute)}',
            style: TextStyle(
              color: p.text,
              fontSize: 40,
              fontWeight: FontWeight.w300,
              height: 1.05,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${_weekdays[_now.weekday - 1]}, ${_now.day} '
            '${_months[_now.month - 1]} ${_now.year}',
            style: TextStyle(
              color: p.accent,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => setState(
                  () => _month = DateTime(_now.year, _now.month),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  child: Text(
                    '${_months[_month.month - 1]} ${_month.year}',
                    style: TextStyle(
                      color: p.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const Spacer(),
              _Arrow(
                palette: p,
                icon: Icons.chevron_left_rounded,
                onTap: () => _page(-1),
              ),
              _Arrow(
                palette: p,
                icon: Icons.chevron_right_rounded,
                onTap: () => _page(1),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final d in _weekdays)
                Expanded(
                  child: Center(
                    child: Text(
                      d.substring(0, 2),
                      style: TextStyle(
                        color: p.dimText,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          for (var row = 0; row < cells ~/ 7; row++)
            Row(
              children: [
                for (var col = 0; col < 7; col++)
                  Expanded(
                    child: _Day(
                      palette: p,
                      day: row * 7 + col - lead + 1,
                      days: days,
                      today: thisMonth && row * 7 + col - lead + 1 == _now.day,
                      weekend: col >= 5,
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 10),
          // Events live in Forge Calendar.
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => Native.run('forge-calendar'),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.event_rounded, size: 18, color: p.accent),
                  const SizedBox(width: 10),
                  Text(
                    'Open Calendar',
                    style: TextStyle(color: p.text, fontSize: 13.5, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow({required this.palette, required this.icon, required this.onTap});

  final ForgePalette palette;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onTap,
    icon: Icon(icon, size: 20),
    color: palette.text,
    hoverColor: palette.hover,
    visualDensity: VisualDensity.compact,
  );
}

class _Day extends StatelessWidget {
  const _Day({
    required this.palette,
    required this.day,
    required this.days,
    required this.today,
    required this.weekend,
  });

  final ForgePalette palette;
  final int day;
  final int days;
  final bool today;
  final bool weekend;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final inMonth = day >= 1 && day <= days;
    return SizedBox(
      height: 36,
      child: Center(
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: today
              ? BoxDecoration(color: p.accent, shape: BoxShape.circle)
              : null,
          child: inMonth
              ? Text(
                  '$day',
                  style: TextStyle(
                    color: today
                        ? Colors.white
                        : weekend
                        ? p.dimText
                        : p.text,
                    fontSize: 13,
                    fontWeight: today ? FontWeight.w700 : FontWeight.w500,
                  ),
                )
              : null,
        ),
      ),
    );
  }
}
