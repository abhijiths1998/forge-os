# Forge Thermal

CPU and GPU temperatures, live and over the last two minutes, the fan speed,
and the cooling profiles: Silent, Cool, Balanced, Cool gaming, Performance
and Custom. Flutter on `forge_ui`.

The work is `forge-thermal`'s (`profile/airootfs/usr/local/bin`): `status` and
`list` run as the user, applying a profile goes through `pkexec` (polkit
`org.forgeos.thermal`, no password at the machine). Profiles cap clocks on any
machine; on laptops whose firmware takes limits (Lenovo LOQ/Legion, through
`lenovo-wmi-other`) they also set the CPU/GPU temperature limits and the CPU's
sustained and boost watts, and the app shows sliders for those. Profiles that
need the firmware are hidden where it isn't there.

    flutter run -d linux --dart-define=FORGE_THERMAL=/path/to/forge-thermal

runs it against another copy of the tool (the default is
`/usr/local/bin/forge-thermal`). Applying only works with the installed one,
since polkit allows that path.
