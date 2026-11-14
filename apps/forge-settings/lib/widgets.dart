// Shared widgets for Forge Settings pages: page shells, lists, toggles and
// the per-page error banner. Built on forge_ui's GlassCard, PillButton and
// ForgeSlider.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

/// A page with a title, a one-line sub-headline, a scrollable body and an
/// error banner at the top. The body gets a max width so pages don't stretch
/// across a wide screen.
class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.title,
    required this.sub,
    required this.body,
    this.error,
  });

  final String title;
  final String sub;
  final Widget body;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final p = ForgePalette.current();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: p.text),
              ),
              Text(
                sub,
                style: TextStyle(fontSize: 13, color: p.dimText),
              ),
            ],
          ),
        ),
        if (error != null) ConfigError(text: error!),
        Expanded(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: body,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A control row: a label, a description, and a control on the right.
class SettingRow extends StatelessWidget {
  const SettingRow({
    super.key,
    required this.label,
    this.desc,
    required this.control,
  });

  final String label;
  final String? desc;
  final Widget control;

  @override
  Widget build(BuildContext context) {
    final p = ForgePalette.current();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.text),
                ),
              ),
            ],
          ),
          if (desc != null && desc!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 8),
              child: Text(
                desc!,
                style: TextStyle(fontSize: 12, color: p.dimText),
              ),
            ),
          control,
        ],
      ),
    );
  }
}

/// A labelled toggle bound to a bool.
class SettingToggle extends StatelessWidget {
  const SettingToggle({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = ForgePalette.current();
    return SizedBox(
      width: 52,
      height: 28,
      child: Switch(
        value: value,
        onChanged: onChanged,
        activeColor: p.accent,
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? p.accent : p.hover),
      ),
    );
  }
}

/// A button that applies a change and shows a result message.
class ApplyButton extends StatelessWidget {
  const ApplyButton({
    super.key,
    required this.label,
    required this.onTap,
    this.busy = false,
    this.icon,
  });

  final String label;
  final VoidCallback onTap;
  final bool busy;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = ForgePalette.current();
    return PillButton(
      palette: p,
      label: label,
      icon: icon,
      filled: true,
      onTap: busy ? null : onTap,
    );
  }
}

/// A list tile with a leading icon, a title, a subtitle and a trailing value.
class SettingTile extends StatelessWidget {
  const SettingTile({
    super.key,
    required this.icon,
    required this.title,
    this.sub,
    required this.value,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? sub;
  final Widget value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = ForgePalette.current();
    return GlassCard(
      palette: p,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, size: 20, color: p.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.text),
                ),
                if (sub != null && sub!.isNotEmpty)
                  Text(
                    sub!,
                    style: TextStyle(fontSize: 12, color: p.dimText),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          value,
        ],
      ),
    );
  }
}

/// A section header.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, required this.palette});

  final String text;
  final ForgePalette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w700,
          color: palette.dimText,
        ),
      ),
    );
  }
}

/// A filled button that opens an external editor (nm-connection-editor, etc.).
class OpenEditorButton extends StatelessWidget {
  const OpenEditorButton({
    super.key,
    required this.label,
    required this.command,
  });

  final String label;
  final List<String> command;

  @override
  Widget build(BuildContext context) {
    final p = ForgePalette.current();
    return PillButton(
      palette: p,
      label: label,
      filled: false,
      onTap: () async {
        try {
          await Process.run(command[0], command.sublist(1));
        } catch (_) {}
      },
    );
  }
}

/// The readable config-error banner, shared so every page uses the same look.
class ConfigError extends StatelessWidget {
  const ConfigError({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final p = ForgePalette.current();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: p.negative.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.negative.withValues(alpha: 0.6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, size: 16, color: p.negative),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12.5, color: p.text),
            ),
          ),
        ],
      ),
    );
  }
}
