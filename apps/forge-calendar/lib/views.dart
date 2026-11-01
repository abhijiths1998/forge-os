// The calendar's views: a month grid, a week or day timeline, and an agenda
// list. Clicking an event opens it; double-clicking empty space (or a slot
// in the timeline) makes a new one there.
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

import 'dates.dart';
import 'ics.dart';
import 'store.dart';

typedef OpenEvent = void Function(Occurrence o);
typedef NewEvent = void Function(DateTime start, {bool allDay});

Color _eventColour(Store s, Occurrence o, ForgePalette p) => s.calendar(o.event.calendar)?.colour ?? p.accent;

// ---------------------------------------------------------------- month

class MonthView extends StatelessWidget {
  const MonthView({
    super.key,
    required this.store,
    required this.palette,
    required this.month,
    required this.selected,
    required this.onSelect,
    required this.onOpen,
    required this.onNew,
    required this.onShowDay,
  });

  final Store store;
  final ForgePalette palette;
  final DateTime month;
  final DateTime selected;
  final ValueChanged<DateTime> onSelect;
  final OpenEvent onOpen;
  final NewEvent onNew;
  final ValueChanged<DateTime> onShowDay;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final start = monthGridStart(month);
    final end = addDays(start, 42);
    final occ = store.between(start, end);
    final byDay = <DateTime, List<Occurrence>>{};
    for (final o in occ) {
      // Multi-day events show on each of their days.
      var d = day(o.start);
      final last = o.allDay ? addDays(day(o.end), -1) : day(o.end.subtract(const Duration(seconds: 1)));
      while (!d.isAfter(last) && d.isBefore(end)) {
        if (!d.isBefore(start)) byDay.putIfAbsent(d, () => []).add(o);
        d = addDays(d, 1);
      }
    }
    final now = today();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 16, 12),
      child: Column(children: [
        Row(children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(shortDay(addDays(start, i).weekday).toUpperCase(),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: p.dimText, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
              ),
            ),
        ]),
        Expanded(
          child: LayoutBuilder(builder: (context, box) {
            final cellH = box.maxHeight / 6;
            final fit = max(0, ((cellH - 34) / 21).floor());
            return Column(children: [
              for (var w = 0; w < 6; w++)
                Expanded(
                  child: Row(children: [
                    for (var i = 0; i < 7; i++)
                      Expanded(
                        child: _DayCell(
                          store: store,
                          palette: p,
                          date: addDays(start, w * 7 + i),
                          inMonth: addDays(start, w * 7 + i).month == month.month,
                          isToday: addDays(start, w * 7 + i) == now,
                          selected: addDays(start, w * 7 + i) == selected,
                          events: byDay[addDays(start, w * 7 + i)] ?? const [],
                          fit: fit,
                          onSelect: onSelect,
                          onOpen: onOpen,
                          onNew: onNew,
                          onShowDay: onShowDay,
                        ),
                      ),
                  ]),
                ),
            ]);
          }),
        ),
      ]),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.store,
    required this.palette,
    required this.date,
    required this.inMonth,
    required this.isToday,
    required this.selected,
    required this.events,
    required this.fit,
    required this.onSelect,
    required this.onOpen,
    required this.onNew,
    required this.onShowDay,
  });

  final Store store;
  final ForgePalette palette;
  final DateTime date;
  final bool inMonth, isToday, selected;
  final List<Occurrence> events;
  final int fit;
  final ValueChanged<DateTime> onSelect;
  final OpenEvent onOpen;
  final NewEvent onNew;
  final ValueChanged<DateTime> onShowDay;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final shown = events.length > fit ? max(0, fit - 1) : events.length;
    return GestureDetector(
      onTap: () => onSelect(date),
      onDoubleTap: () => onNew(DateTime(date.year, date.month, date.day, 9), allDay: false),
      child: Container(
        margin: const EdgeInsets.all(2),
        padding: const EdgeInsets.fromLTRB(6, 5, 6, 4),
        decoration: BoxDecoration(
          color: selected ? p.accent.withValues(alpha: 0.12) : (inMonth ? p.card : Colors.transparent),
          borderRadius: BorderRadius.circular(10),
          border: selected ? Border.all(color: p.accent.withValues(alpha: 0.5), width: 1.2) : null,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: isToday ? BoxDecoration(color: p.accent, shape: BoxShape.circle) : null,
              child: Text(
                date.day == 1 && !isToday ? '${date.day}' : '${date.day}',
                style: TextStyle(
                  color: isToday ? p.onAccent : p.text.withValues(alpha: inMonth ? 0.95 : 0.35),
                  fontSize: 12.5,
                  fontWeight: isToday ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ),
            if (date.day == 1)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(shortMonth(date.month), style: TextStyle(color: p.dimText, fontSize: 11.5, fontWeight: FontWeight.w600)),
              ),
          ]),
          const SizedBox(height: 3),
          for (final o in events.take(shown)) _chip(o),
          if (events.length > shown)
            InkWell(
              onTap: () => onShowDay(date),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text('+${events.length - shown} more',
                    style: TextStyle(color: p.dimText, fontSize: 11.5, fontWeight: FontWeight.w600)),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _chip(Occurrence o) {
    final p = palette;
    final colour = _eventColour(store, o, p);
    final past = o.end.isBefore(DateTime.now());
    final allDayish = o.allDay || !sameDay(o.start, o.end.subtract(const Duration(seconds: 1)));
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: InkWell(
        onTap: () => onOpen(o),
        borderRadius: BorderRadius.circular(6),
        child: Opacity(
          opacity: past ? 0.55 : 1,
          child: Container(
            height: 19,
            padding: const EdgeInsets.symmetric(horizontal: 5),
            decoration: allDayish
                ? BoxDecoration(color: colour.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(6))
                : null,
            child: Row(children: [
              if (!allDayish) ...[
                Container(width: 7, height: 7, decoration: BoxDecoration(color: colour, shape: BoxShape.circle)),
                const SizedBox(width: 5),
                Text(hm(o.start), style: TextStyle(color: p.dimText, fontSize: 11, fontFeatures: const [FontFeature.tabularFigures()])),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(o.event.title,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: TextStyle(
                      color: allDayish ? Colors.white : p.text,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    )),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- week / day

class TimelineView extends StatefulWidget {
  const TimelineView({
    super.key,
    required this.store,
    required this.palette,
    required this.first,
    required this.days,
    required this.onOpen,
    required this.onNew,
    required this.onSelect,
  });

  final Store store;
  final ForgePalette palette;
  final DateTime first;
  final int days;
  final OpenEvent onOpen;
  final NewEvent onNew;
  final ValueChanged<DateTime> onSelect;

  @override
  State<TimelineView> createState() => _TimelineViewState();
}

class _TimelineViewState extends State<TimelineView> {
  static const hourH = 52.0;
  static const gutter = 56.0;
  late final _scroll = ScrollController(initialScrollOffset: _initialOffset());
  Timer? _tick;

  double _initialOffset() {
    // Start around now (or 8:00 if it's a different week), with context above.
    final now = DateTime.now();
    final inRange = !now.isBefore(widget.first) && now.isBefore(addDays(widget.first, widget.days));
    final h = inRange ? max(0, now.hour - 2) : 7;
    return h * hourH;
  }

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(minutes: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final first = widget.first;
    final last = addDays(first, widget.days);
    final occ = widget.store.between(first, last);
    final allDay = occ.where((o) => o.allDay || o.end.difference(o.start) >= const Duration(hours: 24)).toList();
    final timed = occ.where((o) => !allDay.contains(o)).toList();
    final now = DateTime.now();

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 16, 12),
      child: Column(children: [
        // Day headers.
        Row(children: [
          const SizedBox(width: gutter),
          for (var i = 0; i < widget.days; i++)
            Expanded(
              child: InkWell(
                onTap: () => widget.onSelect(addDays(first, i)),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(children: [
                    Text(shortDay(addDays(first, i).weekday).toUpperCase(),
                        style: TextStyle(color: p.dimText, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
                    const SizedBox(height: 2),
                    Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: addDays(first, i) == today() ? BoxDecoration(color: p.accent, shape: BoxShape.circle) : null,
                      child: Text('${addDays(first, i).day}',
                          style: TextStyle(
                            color: addDays(first, i) == today() ? p.onAccent : p.text,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          )),
                    ),
                  ]),
                ),
              ),
            ),
        ]),
        // All-day row.
        if (allDay.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: gutter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 4, right: 8),
                  child: Text('all day', textAlign: TextAlign.right, style: TextStyle(color: p.dimText, fontSize: 11)),
                ),
              ),
              for (var i = 0; i < widget.days; i++)
                Expanded(
                  child: Column(children: [
                    for (final o in allDay.where((o) {
                      final d = addDays(first, i);
                      return !o.start.isAfter(d.add(const Duration(hours: 23))) && o.end.isAfter(d);
                    }))
                      _block(o, compact: true),
                  ]),
                ),
            ]),
          ),
        Container(height: 1, color: p.rim),
        Expanded(
          child: SingleChildScrollView(
            controller: _scroll,
            child: SizedBox(
              height: hourH * 24,
              child: LayoutBuilder(builder: (context, box) {
                final colW = (box.maxWidth - gutter) / widget.days;
                return Stack(children: [
                  // Hour lines and labels.
                  for (var h = 0; h < 24; h++) ...[
                    Positioned(
                      top: h * hourH,
                      left: gutter,
                      right: 0,
                      child: Container(height: 1, color: p.rim),
                    ),
                    if (h > 0)
                      Positioned(
                        top: h * hourH - 7,
                        left: 0,
                        width: gutter - 10,
                        child: Text('${two(h)}:00', textAlign: TextAlign.right, style: TextStyle(color: p.dimText, fontSize: 11)),
                      ),
                  ],
                  // Empty slots: double-click makes an event at that half hour.
                  for (var i = 0; i < widget.days; i++)
                    Positioned(
                      left: gutter + i * colW,
                      top: 0,
                      width: colW,
                      height: hourH * 24,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onDoubleTapDown: (d) => _newAt(i, d.localPosition.dy),
                        onDoubleTap: () {},
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border(left: BorderSide(color: p.rim)),
                            color: addDays(first, i) == today() ? p.accent.withValues(alpha: 0.04) : null,
                          ),
                        ),
                      ),
                    ),
                  // Events.
                  for (var i = 0; i < widget.days; i++) ..._dayEvents(timed, addDays(first, i), gutter + i * colW, colW),
                  // Now.
                  if (!now.isBefore(first) && now.isBefore(last))
                    Positioned(
                      top: (now.hour + now.minute / 60) * hourH - 1,
                      left: gutter + day(now).difference(first).inDays * colW - 4,
                      width: colW + 4,
                      child: Row(children: [
                        Container(width: 9, height: 9, decoration: BoxDecoration(color: p.negative, shape: BoxShape.circle)),
                        Expanded(child: Container(height: 2, color: p.negative)),
                      ]),
                    ),
                ]);
              }),
            ),
          ),
        ),
      ]),
    );
  }

  double? _pendingY;
  void _newAt(int dayIndex, double y) {
    _pendingY = y;
    final minutes = ((_pendingY! / hourH) * 60 / 30).floor() * 30;
    final d = addDays(widget.first, dayIndex);
    widget.onNew(DateTime(d.year, d.month, d.day).add(Duration(minutes: minutes)));
  }

  /// Timed events on [d], side by side where they overlap.
  List<Widget> _dayEvents(List<Occurrence> all, DateTime d, double left, double width) {
    final next = addDays(d, 1);
    final list = all.where((o) => o.start.isBefore(next) && o.end.isAfter(d)).toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    // Greedy columns within clusters of overlapping events.
    final out = <Widget>[];
    var cluster = <(Occurrence, int)>[];
    DateTime? clusterEnd;
    void flush() {
      final cols = cluster.isEmpty ? 1 : cluster.map((c) => c.$2).reduce(max) + 1;
      for (final (o, col) in cluster) {
        final s = o.start.isBefore(d) ? d : o.start;
        final e = o.end.isAfter(next) ? next : o.end;
        final top = s.difference(d).inMinutes / 60 * hourH;
        final h = max(20.0, e.difference(s).inMinutes / 60 * hourH);
        final w = (width - 6) / cols;
        out.add(Positioned(
          top: top + 1,
          left: left + 3 + col * w,
          width: w - 2,
          height: h - 2,
          child: _block(o),
        ));
      }
      cluster = [];
      clusterEnd = null;
    }

    for (final o in list) {
      if (clusterEnd != null && !o.start.isBefore(clusterEnd!)) flush();
      final used = cluster.where((c) => c.$1.end.isAfter(o.start)).map((c) => c.$2).toSet();
      var col = 0;
      while (used.contains(col)) {
        col++;
      }
      cluster.add((o, col));
      clusterEnd = clusterEnd == null || o.end.isAfter(clusterEnd!) ? o.end : clusterEnd;
    }
    flush();
    return out;
  }

  Widget _block(Occurrence o, {bool compact = false}) {
    final p = widget.palette;
    final colour = _eventColour(widget.store, o, p);
    final past = o.end.isBefore(DateTime.now());
    return Padding(
      padding: compact ? const EdgeInsets.fromLTRB(2, 0, 2, 2) : EdgeInsets.zero,
      child: Material(
        color: Color.alphaBlend(colour.withValues(alpha: past ? 0.35 : 0.8), p.surface),
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => widget.onOpen(o),
          child: Container(
            decoration: BoxDecoration(border: Border(left: BorderSide(color: colour, width: 3))),
            padding: EdgeInsets.fromLTRB(6, compact ? 2 : 4, 4, 2),
            alignment: Alignment.topLeft,
            child: LayoutBuilder(builder: (context, box) {
              final roomy = box.maxHeight > 34;
              return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(o.event.title,
                    maxLines: roomy ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                if (!compact && roomy)
                  Text(
                    '${hm(o.start)} – ${hm(o.end)}${o.event.location.isNotEmpty ? ' · ${o.event.location}' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 11),
                  ),
              ]);
            }),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- agenda

class AgendaView extends StatelessWidget {
  const AgendaView({
    super.key,
    required this.store,
    required this.palette,
    required this.from,
    required this.onOpen,
    this.results,
  });

  final Store store;
  final ForgePalette palette;
  final DateTime from;
  final OpenEvent onOpen;

  /// Search results instead of what's coming up.
  final List<Occurrence>? results;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final list = results ?? store.between(from, addDays(from, 90));
    if (list.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(results == null ? Icons.event_available_rounded : Icons.search_off_rounded, size: 56, color: p.dimText.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          Text(results == null ? 'Nothing in the next three months' : 'No events match',
              style: TextStyle(color: p.dimText, fontSize: 14)),
        ]),
      );
    }
    final groups = <DateTime, List<Occurrence>>{};
    for (final o in list) {
      final d = o.start.isBefore(from) && results == null ? from : day(o.start);
      groups.putIfAbsent(d, () => []).add(o);
    }
    final days = groups.keys.toList()..sort();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 4, 24, 24),
      itemCount: days.length,
      itemBuilder: (context, i) {
        final d = days[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 110,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(relativeDay(d),
                    style: TextStyle(color: d == today() ? p.accent : p.text, fontSize: 15, fontWeight: FontWeight.w700)),
                Text(d == today() || relativeDay(d).length > 9 ? shortDate(d) : dayNames[d.weekday - 1],
                    style: TextStyle(color: p.dimText, fontSize: 12)),
              ]),
            ),
            Expanded(
              child: Column(children: [
                for (final o in groups[d]!)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: GlassCard(
                      palette: p,
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                      onTap: () => onOpen(o),
                      child: Row(children: [
                        Container(
                          width: 4,
                          height: 36,
                          decoration: BoxDecoration(color: _eventColour(store, o, p), borderRadius: BorderRadius.circular(2)),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 96,
                          child: Text(o.allDay ? 'All day' : '${hm(o.start)} – ${hm(o.end)}',
                              style: TextStyle(color: p.dimText, fontSize: 12.5, fontFeatures: const [FontFeature.tabularFigures()])),
                        ),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(o.event.title, style: TextStyle(color: p.text, fontSize: 14, fontWeight: FontWeight.w600)),
                            if (o.event.location.isNotEmpty)
                              Text(o.event.location, style: TextStyle(color: p.dimText, fontSize: 12)),
                          ]),
                        ),
                        if (o.event.repeat != null) Icon(Icons.repeat_rounded, size: 15, color: p.dimText),
                        if (o.event.alarm != null) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.notifications_none_rounded, size: 15, color: p.dimText),
                        ],
                      ]),
                    ),
                  ),
              ]),
            ),
          ]),
        );
      },
    );
  }
}

// ---------------------------------------------------------------- mini month

class MiniMonth extends StatelessWidget {
  const MiniMonth({super.key, required this.palette, required this.store, required this.month, required this.selected, required this.onPick, required this.onMonth});

  final ForgePalette palette;
  final Store store;
  final DateTime month;
  final DateTime selected;
  final ValueChanged<DateTime> onPick;
  final ValueChanged<DateTime> onMonth;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final start = monthGridStart(month);
    final busy = <DateTime>{for (final o in store.between(start, addDays(start, 42))) day(o.start)};
    return Column(children: [
      Row(children: [
        Expanded(
          child: Text('${monthNames[month.month - 1]} ${month.year}',
              style: TextStyle(color: p.text, fontSize: 13.5, fontWeight: FontWeight.w700)),
        ),
        _arrow(p, Icons.chevron_left_rounded, () => onMonth(DateTime(month.year, month.month - 1))),
        _arrow(p, Icons.chevron_right_rounded, () => onMonth(DateTime(month.year, month.month + 1))),
      ]),
      const SizedBox(height: 6),
      Row(children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Text(shortDay(addDays(start, i).weekday).substring(0, 1),
                textAlign: TextAlign.center, style: TextStyle(color: p.dimText, fontSize: 11, fontWeight: FontWeight.w700)),
          ),
      ]),
      const SizedBox(height: 4),
      for (var w = 0; w < 6; w++)
        Row(children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: () {
                final d = addDays(start, w * 7 + i);
                final isToday = d == today();
                final sel = d == selected;
                return InkWell(
                  onTap: () => onPick(d),
                  customBorder: const CircleBorder(),
                  child: Container(
                    height: 28,
                    margin: const EdgeInsets.all(1),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isToday ? p.accent : (sel ? p.accent.withValues(alpha: 0.25) : null),
                    ),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text('${d.day}',
                          style: TextStyle(
                            color: isToday ? p.onAccent : p.text.withValues(alpha: d.month == month.month ? 0.9 : 0.3),
                            fontSize: 11.5,
                            fontWeight: isToday || sel ? FontWeight.w700 : FontWeight.w500,
                          )),
                      if (busy.contains(d) && !isToday)
                        Container(width: 3, height: 3, decoration: BoxDecoration(color: p.accent, shape: BoxShape.circle)),
                    ]),
                  ),
                );
              }(),
            ),
        ]),
    ]);
  }

  Widget _arrow(ForgePalette p, IconData icon, VoidCallback onTap) => InkResponse(
        onTap: onTap,
        radius: 14,
        child: Padding(padding: const EdgeInsets.all(3), child: Icon(icon, size: 18, color: p.dimText)),
      );
}
