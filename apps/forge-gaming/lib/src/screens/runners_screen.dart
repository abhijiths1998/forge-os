// Proton and Wine: what is installed (from Steam, Lutris, the system or
// downloaded here), which one Windows games use by default, and GE-Proton
// releases to download.
import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

import '../models.dart';
import '../store.dart';
import '../widgets/glass.dart';
import '../window.dart';

String formatBytes(int bytes) {
  if (bytes <= 0) return '';
  const units = ['B', 'KB', 'MB', 'GB'];
  var v = bytes.toDouble();
  var u = 0;
  while (v >= 1024 && u < units.length - 1) {
    v /= 1024;
    u++;
  }
  return '${v.toStringAsFixed(v >= 100 || u == 0 ? 0 : 1)} ${units[u]}';
}

class RunnersScreen extends StatefulWidget {
  const RunnersScreen({super.key, required this.store, required this.palette});

  final GamingStore store;
  final ForgePalette palette;

  @override
  State<RunnersScreen> createState() => _RunnersScreenState();
}

class _RunnersScreenState extends State<RunnersScreen> {
  GamingStore get store => widget.store;
  ForgePalette get p => widget.palette;

  @override
  void initState() {
    super.initState();
    store.loadRunners();
    if (store.releases == null) store.loadReleases();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(fit: StackFit.expand, children: [
          Backdrop(palette: p, game: null),
          Column(children: [
            TitleStrip(palette: p),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: ListView(padding: const EdgeInsets.fromLTRB(24, 8, 24, 30), children: [
                    Row(children: [
                      GlassButton(
                        palette: p,
                        icon: Icons.arrow_back_rounded,
                        label: 'Library',
                        autofocus: true,
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                    ]),
                    const SizedBox(height: 18),
                    Text('Proton & Wine', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: p.text)),
                    const SizedBox(height: 4),
                    Text('What runs your Windows games. Steam and Heroic games use their own settings.',
                        style: TextStyle(color: p.dimText)),
                    const SizedBox(height: 18),
                    FocusTraversalGroup(child: _installed()),
                    const SizedBox(height: 18),
                    FocusTraversalGroup(child: _available()),
                  ]),
                ),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _installed() {
    return Glass(
      palette: p,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _heading('Installed'),
        if (store.runners.isEmpty)
          Text('None yet. Download GE-Proton below.', style: TextStyle(color: p.dimText)),
        for (final r in store.runners)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _RunnerRow(
              palette: p,
              runner: r,
              isDefault: r.id == store.defaultRunner,
              onDefault: () => store.setDefaultRunner(r),
              onRemove: r.source == 'forge' ? () => store.removeRunner(r) : null,
            ),
          ),
      ]),
    );
  }

  Widget _available() {
    final releases = store.releases;
    return Glass(
      palette: p,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: _heading('Get GE-Proton')),
          GlassButton(
            palette: p,
            icon: Icons.refresh_rounded,
            label: 'Check again',
            onPressed: () => store.loadReleases(),
          ),
        ]),
        Text('Proton with extra fixes for games outside Steam, from GloriousEggroll.',
            style: TextStyle(color: p.dimText, fontSize: 12.5)),
        const SizedBox(height: 12),
        if (releases == null)
          Padding(
            padding: const EdgeInsets.all(18),
            child: Center(child: CircularProgressIndicator(color: p.accent)),
          )
        else if (releases.isEmpty)
          Text('Couldn\'t reach GitHub.', style: TextStyle(color: p.dimText))
        else
          for (final r in releases)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _ReleaseRow(
                palette: p,
                release: r,
                download: store.downloads[r.name],
                onInstall: () => store.installRunner(r.name),
              ),
            ),
      ]),
    );
  }

  Widget _heading(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(t.toUpperCase(),
            style: TextStyle(fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w800, color: p.dimText)),
      );
}

class _RunnerRow extends StatelessWidget {
  const _RunnerRow({
    required this.palette,
    required this.runner,
    required this.isDefault,
    required this.onDefault,
    this.onRemove,
  });

  final ForgePalette palette;
  final Runner runner;
  final bool isDefault;
  final VoidCallback onDefault;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final from = switch (runner.source) {
      'steam' => 'from Steam',
      'lutris' => 'from Lutris',
      'system' => 'system',
      'forge' => 'downloaded here',
      _ => runner.source,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: p.dark ? 0.05 : 0.25),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        Icon(runner.kind == 'proton' ? Icons.bolt_rounded : Icons.wine_bar_rounded, color: p.accent),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(runner.name, style: TextStyle(fontWeight: FontWeight.w700, color: p.text)),
            Text('${runner.kind == 'proton' ? 'Proton' : 'Wine'} · $from',
                style: TextStyle(fontSize: 12, color: p.dimText)),
          ]),
        ),
        if (isDefault)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text('DEFAULT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: p.positive)),
          )
        else
          GlassButton(palette: p, label: 'Make default', onPressed: onDefault),
        if (onRemove != null) ...[
          const SizedBox(width: 8),
          GlassButton(palette: p, icon: Icons.delete_outline_rounded, label: 'Remove', danger: true, onPressed: onRemove),
        ],
      ]),
    );
  }
}

class _ReleaseRow extends StatelessWidget {
  const _ReleaseRow({required this.palette, required this.release, required this.onInstall, this.download});

  final ForgePalette palette;
  final RunnerRelease release;
  final Download? download;
  final VoidCallback onInstall;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final d = download;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: p.dark ? 0.05 : 0.25),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(release.name, style: TextStyle(fontWeight: FontWeight.w700, color: p.text)),
              Text(
                d != null
                    ? (d.total > 0
                        ? 'Downloading ${formatBytes(d.received)} of ${formatBytes(d.total)}'
                        : 'Starting download…')
                    : formatBytes(release.size),
                style: TextStyle(fontSize: 12, color: p.dimText),
              ),
            ]),
          ),
          if (release.installed)
            Text('INSTALLED', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: p.positive))
          else if (d == null)
            GlassButton(palette: p, icon: Icons.download_rounded, label: 'Download', filled: true, onPressed: onInstall),
        ]),
        if (d != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: d.fraction,
                minHeight: 6,
                color: p.accent,
                backgroundColor: Colors.white.withValues(alpha: 0.12),
              ),
            ),
          ),
      ]),
    );
  }
}
