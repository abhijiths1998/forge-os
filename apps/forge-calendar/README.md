# Forge Calendar

Forge OS's calendar, in Flutter on `forge_ui` (Forge Glass, the accent,
follows theme changes).

- Month, week, day and agenda views (D/W/M/A; ←/→ to page, T for today,
  N for a new event, / or Ctrl+F to search). Weeks start on the locale's
  first day. Double-click a day or a time slot to add an event there.
- Events: all-day or timed, spanning days, repeating (daily, weekdays,
  weekly, monthly, yearly; RRULE's interval, count and until are kept),
  a reminder, a place and notes. Changing or deleting one occurrence of a
  repeating event asks whether it's just that one (an exception, as
  RECURRENCE-ID/EXDATE) or all of them.
- Calendars: local ones, one `.ics` file each in
  `~/.local/share/forgeos/calendar` (any app can read them; changes made
  there are picked up), subscriptions to an `.ics` address (Google
  Calendar's "Secret address in iCal format", holidays...) fetched every
  hour and read-only, and importing an `.ics` file. Right-click a calendar
  to rename, recolour or remove it.
- Reminders arrive as desktop notifications. The app keeps running when
  its window is closed, and starts hidden at login
  (`forge-calendar --background`, `/etc/xdg/autostart`), so they come on
  time; opening it again shows the window.

`lib/ics.dart` is the iCalendar reader/writer and repeat expansion, tested
in `test/ics_test.dart` (`flutter test`). Times given with a TZID are read
as local time, right for calendars in this machine's time zone.

Build: `flutter build linux --release --no-tree-shake-icons`; try it with
`utils/dev-install-app.sh forge-calendar`.
