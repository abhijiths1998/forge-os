// Forge Thermal: watch the CPU and GPU temperatures and pick how hard the
// machine may run. Profiles cap clocks everywhere; where the firmware takes
// limits itself (Lenovo LOQ/Legion), they also set the temperature and
// wattage it holds the chips at. forge-thermal does the work (backend.dart);
// this is only the window.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

import 'backend.dart';
import 'charts.dart';

void main() => runApp(const ThermalApp());

class ThermalApp extends StatefulWidget {
  const ThermalApp({super.key});

  @override
  State<ThermalApp> createState() => _ThermalAppState();
}

class _ThermalAppState extends State<ThermalApp> {
  static const _refresh = Duration(seconds: 2);
  static const _window = Duration(minutes: 2);

  // The order the profiles read in, coolest first; others after.
  static const _order = ['silent', 'cool', 'balanced', 'gaming', 'performance', 'custom'];

  final _thermal = Thermal();
  final _samples = <Sample>[];
  ForgePalette _p = ForgePalette.current();
  Status? _status;
  List<Profile> _profiles = [];
  Timer? _timer;
  String? _busy; // the profile being applied
  String _message = '';
  bool _messageIsError = false;

  // The Custom editor's values, seeded from the custom profile.
  double _cpu = 90, _gpu = 100;
  final _limits = <String, double>{};

  @override
  void initState() {
    super.initState();
    _loadProfiles();
    _poll();
    _timer = Timer.periodic(_refresh, (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    final Status s;
    try {
      s = await _thermal.status();
    } catch (_) {
      if (mounted) setState(() => _say('forge-thermal isn\'t installed', error: true));
      return;
    }
    if (!mounted) return;
    final now = DateTime.now();
    setState(() {
      _status = s;
      _samples
        ..add(Sample(now, s.cpuTemp, s.gpuTemp))
        ..removeWhere((x) => now.difference(x.at) > _window);
      // The theme may have changed since the last look.
      _p = ForgePalette.current();
    });
  }

  Future<void> _loadProfiles() async {
    final list = await _thermal.list().catchError((_) => <Profile>[]);
    list.sort((a, b) {
      int rank(Profile p) => _order.contains(p.id) ? _order.indexOf(p.id) : _order.length;
      return rank(a).compareTo(rank(b));
    });
    if (!mounted) return;
    setState(() {
      _profiles = list;
      final custom = list.where((p) => p.id == 'custom').firstOrNull;
      if (custom != null) {
        _cpu = custom.cpu.toDouble();
        _gpu = custom.gpu.toDouble();
        for (final k in firmwareKeys) {
          final v = custom.fw(k);
          if (v != null) _limits[k] = v.toDouble();
        }
      }
    });
  }

  void _say(String text, {bool error = false}) {
    _message = text;
    _messageIsError = error;
  }

  Future<void> _run(String id, Future<String> Function() change) async {
    setState(() {
      _busy = id;
      _say('');
    });
    final err = await change();
    if (!mounted) return;
    setState(() {
      _busy = null;
      _say(err.isEmpty ? 'Applied, and kept after restarts' : err, error: err.isNotEmpty);
    });
    await _loadProfiles();
    await _poll();
  }

  void _apply(Profile p) => _run(p.id, () => _thermal.apply(p.id));

  void _applyCustom() {
    final s = _status;
    final limits = <String, int>{
      for (final k in firmwareKeys)
        if (s?.limit(k) != null) k: (_limits[k] ?? s!.limit(k)!.fallback.toDouble()).round(),
    };
    _run('custom', () => _thermal.custom(_cpu.round(), _gpu.round(), limits));
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Forge Thermal',
      color: Colors.transparent,
      theme: p.materialTheme(),
      home: Scaffold(
        backgroundColor: p.window,
        body: ListView(
          padding: const EdgeInsets.fromLTRB(28, 22, 28, 28),
          children: [
            _header(p),
            _lostLimits(p),
            const SizedBox(height: 18),
            _readings(p),
            const SizedBox(height: 12),
            _history(p),
            SectionLabel('Profiles', palette: p),
            _profileGrid(p),
            SectionLabel('Custom limits', palette: p),
            _customEditor(p),
          ],
        ),
      ),
    );
  }

  // --- Header -----------------------------------------------------------

  /// The firmware drops its limits when something else picks the platform
  /// profile (Forge Control's Power row, Fn+Q); say so, with a way back.
  Widget _lostLimits(ForgePalette p) {
    final s = _status;
    final active = _profiles.where((x) => x.id == s?.profile).firstOrNull;
    if (s == null || active == null || !active.needsFirmware || s.platformProfile == null) {
      return const SizedBox.shrink();
    }
    if (s.platformProfile == 'custom') return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: GlassCard(
        palette: p,
        padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
        child: Row(
          children: [
            Icon(Heat.warm.icon, size: 18, color: Heat.warm.colour),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${active.name}\'s limits are off: the power profile changed to ${s.platformProfile}, '
                'and the firmware forgets them then.',
                style: TextStyle(fontSize: 12.5, color: p.text),
              ),
            ),
            PillButton(
              palette: p,
              label: 'Put them back',
              filled: true,
              onTap: _busy != null ? null : () => _apply(active),
            ),
          ],
        ),
      ),
    );
  }

  double get _cpuLimit => _status?.limit('CPU_TEMP_LIMIT')?.current.toDouble() ?? 100;
  double get _gpuLimit => _status?.limit('GPU_TEMP_LIMIT')?.current.toDouble() ?? 87;

  Heat? get _overall {
    final s = _status;
    if (s == null) return null;
    final heats = [
      if (s.cpuTemp != null) heatOf(s.cpuTemp!, _cpuLimit),
      if (s.gpuTemp != null) heatOf(s.gpuTemp!, _gpuLimit),
    ];
    return heats.isEmpty ? null : heats.reduce((a, b) => a.index >= b.index ? a : b);
  }

  Widget _header(ForgePalette p) {
    final s = _status;
    final active = _profiles.where((x) => x.id == s?.profile).firstOrNull;
    final heat = _overall;
    final subtitle = [
      if (active != null) '${active.name} profile',
      if (s?.platformProfile != null) 'firmware: ${s!.platformProfile}',
    ].join(' · ');
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Forge Thermal',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: p.text),
              ),
              Text(
                subtitle.isEmpty ? 'Reading the sensors…' : subtitle,
                style: TextStyle(fontSize: 13, color: p.dimText),
              ),
            ],
          ),
        ),
        if (heat != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(color: p.hover, borderRadius: BorderRadius.circular(20)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(heat.icon, size: 16, color: heat.colour),
                const SizedBox(width: 6),
                Text(
                  const {Heat.cool: 'Running cool', Heat.warm: 'Running warm', Heat.hot: 'At its limit'}[heat]!,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.text),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // --- Live readings ------------------------------------------------------

  Widget _readings(ForgePalette p) {
    final s = _status;
    final cpuW = s?.limit('CPU_SUSTAINED_W');
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _chipCard(
              p,
              title: 'Processor',
              colour: cpuColour(p),
              gauge: TempGauge(palette: p, value: s?.cpuTemp, limit: _cpuLimit),
              facts: [
                if (s?.cpuClockGhz != null) ('Clock', '${s!.cpuClockGhz!.toStringAsFixed(2)} GHz'),
                if (s?.cpuCapGhz != null && s?.cpuMaxGhz != null)
                  (
                    'Speed cap',
                    s!.cpuCapGhz! >= s.cpuMaxGhz! - 0.01 ? 'None' : '${s.cpuCapGhz!.toStringAsFixed(2)} GHz',
                  ),
                if (cpuW != null) ('Power limit', '${cpuW.current} W'),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _chipCard(
              p,
              title: _shortGpu(s?.gpuName) ?? 'Graphics',
              colour: gpuColour(p),
              gauge: TempGauge(palette: p, value: s?.gpuTemp, limit: _gpuLimit),
              facts: [
                if (s?.gpuClockMhz != null) ('Clock', '${s!.gpuClockMhz!.round()} MHz'),
                if (s?.gpuWatts != null) ('Power', '${s!.gpuWatts!.toStringAsFixed(0)} W'),
                if (s?.gpuMaxMhz != null) ('Max clock', '${s!.gpuMaxMhz!.round()} MHz'),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 170,
            child: GlassCard(
              palette: p,
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Fans',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text),
                  ),
                  const Spacer(),
                  Icon(Icons.air_rounded, size: 30, color: p.dimText),
                  const SizedBox(height: 8),
                  Text(
                    s?.fanRpm == null ? '–' : '${s!.fanRpm}',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      color: p.text,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  Text('RPM', style: TextStyle(fontSize: 12, color: p.dimText)),
                  const Spacer(),
                  Text(
                    'The firmware runs the fans from the temperatures',
                    style: TextStyle(fontSize: 11, color: p.dimText),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// "NVIDIA GeForce RTX 3050 6GB Laptop GPU" -> "RTX 3050".
  String? _shortGpu(String? name) =>
      name == null ? null : RegExp(r'(RTX|GTX|RX|Arc)\s*\w+').firstMatch(name)?.group(0) ?? name;

  Widget _chipCard(
    ForgePalette p, {
    required String title,
    required Color colour,
    required Widget gauge,
    required List<(String, String)> facts,
  }) {
    return GlassCard(
      palette: p,
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          gauge,
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // The key that ties this card to its line in the chart.
                    Container(
                      width: 12,
                      height: 4,
                      decoration: BoxDecoration(color: colour, borderRadius: BorderRadius.circular(2)),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        title,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                for (final (k, v) in facts)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Text(k, style: TextStyle(fontSize: 12.5, color: p.dimText)),
                        const Spacer(),
                        Text(
                          v,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: p.text,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _history(ForgePalette p) {
    Widget key(String name, Color c) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 4,
          decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 6),
        Text(name, style: TextStyle(fontSize: 12, color: p.dimText)),
      ],
    );
    return GlassCard(
      palette: p,
      padding: const EdgeInsets.fromLTRB(18, 14, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Temperature, last ${_window.inMinutes} minutes',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.text),
              ),
              const Spacer(),
              key('CPU', cpuColour(p)),
              const SizedBox(width: 14),
              key('GPU', gpuColour(p)),
              const SizedBox(width: 6),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 170,
            child: HistoryChart(palette: p, samples: _samples, window: _window),
          ),
        ],
      ),
    );
  }

  // --- Profiles -------------------------------------------------------------

  List<Profile> get _shownProfiles {
    final fw = _status?.hasFirmware ?? false;
    return _profiles.where((x) => fw || !x.needsFirmware).toList();
  }

  Widget _profileGrid(ForgePalette p) {
    final current = _status?.profile;
    final shown = _shownProfiles;
    if (shown.isEmpty) {
      return Text('No profiles found in /etc/forge-thermal/profiles', style: TextStyle(color: p.dimText));
    }
    return LayoutBuilder(
      builder: (context, box) {
        const gap = 10.0;
        final cols = box.maxWidth > 820 ? 3 : 2;
        final width = (box.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final prof in shown) SizedBox(width: width, child: _profileCard(p, prof, prof.id == current)),
          ],
        );
      },
    );
  }

  String _limitsLine(Profile prof) {
    final bits = [
      if (prof.fw('CPU_TEMP_LIMIT') != null) 'CPU ${prof.fw('CPU_TEMP_LIMIT')} °C',
      if (prof.fw('CPU_SUSTAINED_W') != null) '${prof.fw('CPU_SUSTAINED_W')} W',
      if (prof.fw('GPU_TEMP_LIMIT') != null) 'GPU ${prof.fw('GPU_TEMP_LIMIT')} °C',
    ];
    if (bits.isNotEmpty) return bits.join(' · ');
    return 'CPU ${prof.cpu}% · GPU ${prof.gpu}%';
  }

  Widget _profileCard(ForgePalette p, Profile prof, bool selected) {
    final busy = _busy == prof.id;
    return GlassCard(
      palette: p,
      selected: selected,
      onTap: _busy != null || prof.id == 'custom' ? null : () => _apply(prof),
      child: SizedBox(
        height: 86,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_icon(prof.id), size: 18, color: selected ? p.accent : p.dimText),
                const SizedBox(width: 8),
                Text(
                  prof.name,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: p.text),
                ),
                const Spacer(),
                if (busy)
                  const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                else if (selected)
                  Icon(Icons.check_circle_rounded, size: 18, color: p.accent),
              ],
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Text(
                prof.id == 'custom' ? 'Set below' : prof.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: p.dimText),
              ),
            ),
            Text(
              _limitsLine(prof),
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: p.text.withValues(alpha: 0.8)),
            ),
          ],
        ),
      ),
    );
  }

  IconData _icon(String id) => switch (id) {
    'silent' => Icons.nightlight_round,
    'cool' => Icons.ac_unit_rounded,
    'balanced' => Icons.balance_rounded,
    'gaming' => Icons.sports_esports_rounded,
    'performance' => Icons.bolt_rounded,
    'custom' => Icons.tune_rounded,
    _ => Icons.thermostat_rounded,
  };

  // --- Custom ---------------------------------------------------------------

  Widget _customEditor(ForgePalette p) {
    final s = _status;
    String pct(double v) => v >= 100 ? 'No cap' : '${v.round()}%';
    Widget fwSlider(String key, String label, String unit, String hint) {
      final l = s?.limit(key);
      if (l == null) return const SizedBox.shrink();
      final v = (_limits[key] ?? l.fallback.toDouble()).clamp(l.min.toDouble(), l.max.toDouble());
      return ForgeSlider(
        palette: p,
        label: label,
        value: v,
        min: l.min.toDouble(),
        max: l.max.toDouble(),
        divisions: l.max - l.min,
        format: (x) => '${x.round()} $unit${x.round() == l.fallback ? ' (default)' : ''}',
        hint: hint,
        onChanged: (x) => setState(() => _limits[key] = x),
      );
    }

    return GlassCard(
      palette: p,
      padding: const EdgeInsets.fromLTRB(0, 18, 0, 16),
      // Whole degrees and watts: the steps are there, the dots aren't needed.
      child: SliderTheme(
        data: p.materialTheme().sliderTheme.copyWith(tickMarkShape: SliderTickMarkShape.noTickMark),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (s?.hasFirmware ?? false) ...[
              fwSlider(
                'CPU_TEMP_LIMIT',
                'CPU temperature limit',
                '°C',
                'The firmware slows the CPU to stay under this. Lower is cooler and quieter',
              ),
              fwSlider('GPU_TEMP_LIMIT', 'GPU temperature limit', '°C', 'The same for the graphics card'),
              fwSlider(
                'CPU_SUSTAINED_W',
                'CPU sustained power',
                'W',
                'What the CPU may draw for long stretches; the biggest lever on heat in games',
              ),
              fwSlider('CPU_BOOST_W', 'CPU boost power', 'W', 'Short bursts, for snappiness'),
            ],
            ForgeSlider(
              palette: p,
              label: 'CPU speed cap',
              value: _cpu,
              min: 30,
              max: 100,
              divisions: 70,
              format: pct,
              hint: 'A hard cap on clock speed, for any machine',
              onChanged: (x) => setState(() => _cpu = x),
            ),
            ForgeSlider(
              palette: p,
              label: 'GPU speed cap',
              value: _gpu,
              min: 30,
              max: 100,
              divisions: 70,
              format: pct,
              onChanged: (x) => setState(() => _gpu = x),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _message,
                      style: TextStyle(fontSize: 12.5, color: _messageIsError ? p.negative : p.dimText),
                    ),
                  ),
                  PillButton(
                    palette: p,
                    label: 'Defaults',
                    onTap: _busy != null
                        ? null
                        : () => setState(() {
                            _cpu = 100;
                            _gpu = 100;
                            _limits.clear();
                          }),
                  ),
                  const SizedBox(width: 8),
                  PillButton(
                    palette: p,
                    label: _busy == 'custom' ? 'Applying…' : 'Apply custom',
                    icon: Icons.check_rounded,
                    filled: true,
                    onTap: _busy != null ? null : _applyCustom,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
