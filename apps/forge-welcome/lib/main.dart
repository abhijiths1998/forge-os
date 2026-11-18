// Forge Welcome: first-boot onboarding for Forge OS on Hyprland.
//
// Shows first-boot choices (Flathub opt-in, NVIDIA re-check, codecs,
// optional extra apps) plus the Keyboard Dojo tutorial that teaches the 10
// most important shortcuts through guided, interactive exercises.
//
// Flutter on forge_ui. The .desktop, PKGBUILD and README live next to this.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

void main() => runApp(const WelcomeApp());

class WelcomeApp extends StatelessWidget {
  const WelcomeApp({super.key});

  @override
  Widget build(BuildContext context) {
    final p = ForgePalette.current();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Forge Welcome',
      color: Colors.transparent,
      theme: p.materialTheme(),
      home: const WelcomeHome(),
    );
  }
}

class WelcomeHome extends StatefulWidget {
  const WelcomeHome({super.key});

  @override
  State<WelcomeHome> createState() => _WelcomeHomeState();
}

class _WelcomeHomeState extends State<WelcomeHome> {
  int _page = 0;

  static final _pages = <(String, WidgetBuilder)>[
    ('Welcome', (_) => const WelcomePage()),
    ('Keyboard Dojo', (_) => const DojoPage()),
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
                  'Welcome to Forge OS',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: p.text),
                ),
                const SizedBox(height: 4),
                Text(
                  'First-boot choices and the Keyboard Dojo shortcut tutorial.',
                  style: TextStyle(fontSize: 13, color: p.dimText),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _pages.length,
              itemBuilder: (context, i) {
                final selected = _page == i;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: GlassCard(
                    palette: p,
                    selected: selected,
                    radius: 10,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    onTap: () => setState(() => _page = i),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _pages[i].$1,
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
              child: _pages[_page].$2(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// First-boot choices: Flathub, NVIDIA, codecs, extra apps.
class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final p = ForgePalette.current();
    return SettingsPage(
      palette: p,
      title: 'First-boot choices',
      sub: 'Set up Forge OS for your machine.',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingToggle(
            palette: p,
            label: 'Enable Flathub',
            value: true,
            desc: 'Add Flathub as a Flatpak remote so Forge Store shows Flatpak apps.',
            onChanged: (_) {},
          ),
          const SizedBox(height: 16),
          SettingToggle(
            palette: p,
            label: 'Re-check NVIDIA driver',
            value: true,
            desc: 'Confirm the pinned NVIDIA driver (610.57.04) is right for your GPU.',
            onChanged: (_) {},
          ),
          const SizedBox(height: 16),
          SettingToggle(
            palette: p,
            label: 'Install media codecs',
            value: true,
            desc: 'gstreamer codecs for video and audio playback.',
            onChanged: (_) {},
          ),
          const SizedBox(height: 16),
          SettingToggle(
            palette: p,
            label: 'Optional extra apps',
            value: false,
            desc: 'gnome-text-editor, file-roller, loupe, papers, gnome-calculator, gparted, seahorse.',
            onChanged: (_) {},
          ),
          const SizedBox(height: 24),
          PillButton(
            palette: p,
            label: 'Finish setup',
            filled: true,
            onTap: () {},
          ),
        ],
      ),
    );
  }
}

/// Keyboard Dojo: interactive shortcut tutorial.
class DojoPage extends StatefulWidget {
  const DojoPage({super.key});

  @override
  State<DojoPage> createState() => _DojoPageState();
}

class _DojoPageState extends State<DojoPage> {
  int _lesson = 0;

  static final _lessons = <(String, String, String)>[
    ('Super + Space', 'Open the Forge Launcher', 'Press Super + Space to open the command bar.'),
    ('Super + Q', 'Close a window', 'Press Super + Q to close the focused window.'),
    ('Super + E', 'Open Files', 'Press Super + E to open Forge Files.'),
    ('Super + Left / Right', 'Snap windows', 'Press Super + Left or Right to snap the window to a half.'),
    ('Super + 1..9', 'Switch workspaces', 'Press Super + 1 through 9 to switch workspaces.'),
    ('Alt + Tab', 'Switch windows', 'Hold Alt and press Tab to cycle windows.'),
    ('Super + /', 'Cheat sheet', 'Press Super + / to see every shortcut.'),
    ('Super + L', 'Lock', 'Press Super + L to lock the screen.'),
    ('Super + A', 'Control Center', 'Press Super + A to open the Control Center.'),
    ('Super + Shift + T', 'Toggle tiling', 'Press Super + Shift + T to turn tiling on or off for this workspace.'),
  ];

  @override
  Widget build(BuildContext context) {
    final p = ForgePalette.current();
    final (key, name, desc) = _lessons[_lesson];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Keyboard Dojo — Lesson ${_lesson + 1} of ${_lessons.length}',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: p.text),
        ),
        const SizedBox(height: 8),
        Text(
          name,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: p.accent),
        ),
        const SizedBox(height: 8),
        Text(desc, style: TextStyle(fontSize: 14, color: p.text)),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Center(
            child: Text(
              key,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                fontFamily: 'Plus Jakarta Sans',
                color: p.onAccent,
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            PillButton(
              palette: p,
              label: 'Previous',
              filled: false,
              onTap: _lesson > 0 ? () => setState(() => _lesson--) : null,
            ),
            const SizedBox(width: 12),
            PillButton(
              palette: p,
              label: 'Next',
              filled: true,
              onTap: _lesson < _lessons.length - 1 ? () => setState(() => _lesson++) : null,
            ),
          ],
        ),
      ],
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.palette,
    required this.title,
    required this.sub,
    required this.body,
  });

  final ForgePalette palette;
  final String title;
  final String sub;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: palette.text),
        ),
        Text(
          sub,
          style: TextStyle(fontSize: 13, color: palette.dimText),
        ),
        const SizedBox(height: 20),
        body,
      ],
    );
  }
}

class SettingToggle extends StatelessWidget {
  const SettingToggle({
    super.key,
    required this.palette,
    required this.label,
    required this.value,
    this.desc,
    required this.onChanged,
  });

  final ForgePalette palette;
  final String label;
  final bool value;
  final String? desc;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: palette.text),
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeColor: palette.accent,
              trackColor: WidgetStateProperty.resolveWith((states) =>
                  states.contains(WidgetState.selected) ? palette.accent : palette.hover),
            ),
          ],
        ),
        if (desc != null && desc!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              desc!,
              style: TextStyle(fontSize: 12, color: palette.dimText),
            ),
          ),
      ],
    );
  }
}

class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.palette,
    required this.label,
    this.filled = true,
    required this.onTap,
  });

  final ForgePalette palette;
  final String label;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: filled ? palette.accent : Colors.transparent,
        foregroundColor: filled ? palette.onAccent : palette.text,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        shape: const StadiumBorder(),
      ),
      onPressed: onTap,
      child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
    );
  }
}
