// Forge Wallpapers: the wallpaper app for Forge OS on Hyprland.
//
// Shows a grid of the bundled Forge cast wallpapers, with tabs for online
// sources (Wallhaven, NASA APOD, Unsplash/Pexels) — the UI can list images
// but fetching keys and download logic are stubbed for now. Daily rotation
// and swww/awww integration are placeholders.
//
// Flutter on forge_ui. The .desktop, PKGBUILD and README live next to this.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

void main() => runApp(const WallpapersApp());

class WallpapersApp extends StatelessWidget {
  const WallpapersApp({super.key});

  @override
  Widget build(BuildContext context) {
    final p = ForgePalette.current();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Forge Wallpapers',
      color: Colors.transparent,
      theme: p.materialTheme(),
      home: const WallpapersHome(),
    );
  }
}

class WallpapersHome extends StatefulWidget {
  const WallpapersHome({super.key});

  @override
  State<WallpapersHome> createState() => _WallpapersHomeState();
}

class _WallpapersHomeState extends State<WallpapersHome> {
  int _tab = 0;

  static final _tabs = <(String, WidgetBuilder)>[
    ('Forge Cast', (_) => const CastGrid()),
    ('Wallhaven', (_) => const OnlineSource('Wallhaven')),
    ('NASA APOD', (_) => const OnlineSource('NASA APOD')),
    ('Unsplash', (_) => const OnlineSource('Unsplash')),
    ('Pexels', (_) => const OnlineSource('Pexels')),
  ];

  @override
  Widget build(BuildContext context) {
    final p = ForgePalette.current();
    return Material(
      color: p.window,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 22, 28, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Forge Wallpapers',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: p.text),
                ),
                const SizedBox(height: 4),
                Text(
                  'Bundled Forge cast wallpapers and online sources. '
                  'Set any wallpaper with one click.',
                  style: TextStyle(fontSize: 13, color: p.dimText),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _tabs.length,
              itemBuilder: (context, i) {
                final selected = _tab == i;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: GlassCard(
                    palette: p,
                    selected: selected,
                    radius: 10,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    onTap: () => setState(() => _tab = i),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _tabs[i].$1,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: selected ? p.onAccent : p.text,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: _tabs[_tab].$2(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// Grid of the bundled Forge cast wallpapers.
class CastGrid extends StatelessWidget {
  const CastGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final p = ForgePalette.current();
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        childAspectRatio: 1,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: castNames.length,
      itemBuilder: (context, i) {
        final name = castNames[i];
        return GlassCard(
          palette: p,
          radius: 14,
          onTap: () => _applyWallpaper(name),
          child: Column(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: p.card,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(
                      name.replaceAll('_', ' '),
                      style: TextStyle(fontSize: 12, color: p.text),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                name.replaceAll('_', ' '),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.text),
              ),
            ],
          ),
        );
      },
    );
  }

  void _applyWallpaper(String name) {
    // Placeholder: in M6 this calls swww/awww to set the wallpaper with an
    // animated transition. The swww/awww integration is not yet wired here.
    // Not verified on hardware.
  }
}

/// The 8 original Forge cast mascots.
const castNames = <String>[
  'shonen_fighter',
  'mecha_pilot',
  'wandering_ronin',
  'magical_girl',
  'cyberpunk_hacker',
  'yokai_guardian',
  'sky_pirate',
  'idol_singer',
];

/// Placeholder for an online wallpaper source.
class OnlineSource extends StatelessWidget {
  const OnlineSource(this.source, {super.key});

  final String source;

  @override
  Widget build(BuildContext context) {
    final p = ForgePalette.current();
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_outlined, size: 48, color: p.dimText),
          const SizedBox(height: 12),
          Text(
            '$source coming soon',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: p.text),
          ),
          const SizedBox(height: 4),
          Text(
            'Fetch keys and download logic are stubbed for M6.',
            style: TextStyle(fontSize: 13, color: p.dimText),
          ),
        ],
      ),
    );
  }
}
