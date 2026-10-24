// The pieces of the Control Center panel, in Forge UI's look: cards on the
// glass, the accent for whatever is on.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

const _radius = 14.0;

BoxDecoration _card(ForgePalette p) => BoxDecoration(
    color: p.card, borderRadius: BorderRadius.circular(_radius));

/// An icon in a circle: accent when on.
class _Bubble extends StatelessWidget {
  const _Bubble(
      {required this.palette,
      required this.icon,
      required this.on,
      this.size = 34});

  final ForgePalette palette;
  final IconData icon;
  final bool on;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: on ? p.accent : p.hover,
      ),
      child: Icon(icon, size: size * 0.53, color: on ? p.onAccent : p.text),
    );
  }
}

/// Wi-Fi, Bluetooth: an on/off switch with what it's connected to.
class WideToggle extends StatelessWidget {
  const WideToggle({
    super.key,
    required this.palette,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.on,
    this.onTap,
  });

  final ForgePalette palette;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool on;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Opacity(
      opacity: onTap == null ? 0.55 : 1,
      child: Material(
        color: p.card,
        borderRadius: BorderRadius.circular(_radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(_radius),
          hoverColor: p.hover,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(children: [
              _Bubble(palette: p, icon: icon, on: on),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            color: p.text,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700)),
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.dimText, fontSize: 12)),
                  ],
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Quiet, Dark, Tiling: a round switch with a label under it.
class RoundToggle extends StatelessWidget {
  const RoundToggle({
    super.key,
    required this.palette,
    required this.icon,
    required this.label,
    required this.on,
    this.onTap,
  });

  final ForgePalette palette;
  final IconData icon;
  final String label;
  final bool on;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.55 : 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(_radius),
        hoverColor: palette.hover,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Column(children: [
            _Bubble(palette: palette, icon: icon, on: on, size: 46),
            const SizedBox(height: 6),
            Text(label,
                style: TextStyle(
                    color: palette.text,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}

/// Brightness, volume: a title and a slider; the icon can be a button
/// (mute).
class LevelCard extends StatelessWidget {
  const LevelCard({
    super.key,
    required this.palette,
    required this.title,
    required this.icon,
    required this.value,
    required this.max,
    required this.onChanged,
    required this.onChangeEnd,
    this.subtitle,
    this.onIconTap,
  });

  final ForgePalette palette;
  final String title;
  final String? subtitle;
  final IconData icon;
  final double value;
  final double max;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
  final VoidCallback? onIconTap;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Container(
      decoration: _card(p),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(title,
                style: TextStyle(
                    color: p.text, fontSize: 13, fontWeight: FontWeight.w700)),
            if (subtitle != null) ...[
              const SizedBox(width: 8),
              Expanded(
                child: Text(subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.dimText, fontSize: 11.5)),
              ),
            ] else
              const Spacer(),
            Text('${value.round()}%',
                style: TextStyle(color: p.dimText, fontSize: 12)),
          ]),
          Row(children: [
            InkWell(
              customBorder: const CircleBorder(),
              onTap: onIconTap,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(icon, size: 20, color: p.text),
              ),
            ),
            Expanded(
              child: Slider(
                value: value.clamp(0, max),
                max: max,
                onChanged: onChanged,
                onChangeEnd: onChangeEnd,
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

/// A row of choices, one picked (power and cooling profiles).
class _Choices extends StatelessWidget {
  const _Choices({
    required this.palette,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final ForgePalette palette;
  final Map<String, String> options;
  final String? value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
          color: p.hover, borderRadius: BorderRadius.circular(11)),
      child: Row(children: [
        for (final e in options.entries)
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(e.key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                padding: const EdgeInsets.symmetric(vertical: 7),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: e.key == value ? p.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(e.value,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: e.key == value ? p.onAccent : p.text)),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Power profile (power-profiles-daemon) and cooling (Forge Thermal).
class ProfilesCard extends StatelessWidget {
  const ProfilesCard({
    super.key,
    required this.palette,
    required this.power,
    required this.thermal,
    required this.onPower,
    required this.onThermal,
  });

  final ForgePalette palette;
  final Map<String, dynamic>? power;
  final Map<String, dynamic>? thermal;
  final ValueChanged<String> onPower;
  final ValueChanged<String> onThermal;

  static const _powerNames = {
    'power-saver': 'Saver',
    'balanced': 'Balanced',
    'performance': 'Performance',
  };
  static const _thermalOrder = [
    'silent', 'cool', 'balanced', 'performance', 'custom', //
  ];
  // Up to five fit in the row, so short names; "Max" is no clock limit.
  static const _thermalNames = {'performance': 'Max'};

  String _name(String id) => id[0].toUpperCase() + id.substring(1);

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final label = TextStyle(
        color: p.text, fontSize: 13, fontWeight: FontWeight.w700);
    final thermalProfiles = [
      ...(thermal?['profiles'] as List? ?? const [])
          .cast<String>()
          // Custom only shows while it's the one in use.
          .where((t) => t != 'custom' || t == thermal?['profile']),
    ]..sort((a, b) =>
        _thermalOrder.indexOf(a).compareTo(_thermalOrder.indexOf(b)));
    final temp = thermal?['cpu_temp'];
    return Container(
      decoration: _card(p),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (power != null) ...[
            Text('Power', style: label),
            const SizedBox(height: 6),
            _Choices(
              palette: p,
              options: {
                for (final id in (power!['profiles'] as List).cast<String>())
                  id: _powerNames[id] ?? _name(id),
              },
              value: power!['profile'] as String?,
              onChanged: onPower,
            ),
          ],
          if (power != null && thermal != null) const SizedBox(height: 10),
          if (thermal != null) ...[
            Row(children: [
              Text('Cooling', style: label),
              const Spacer(),
              if (temp != null)
                Text('CPU $temp°C',
                    style: TextStyle(color: p.dimText, fontSize: 12)),
            ]),
            const SizedBox(height: 6),
            _Choices(
              palette: p,
              options: {
                for (final id in thermalProfiles)
                  id: _thermalNames[id] ?? _name(id),
              },
              value: thermal!['profile'] as String?,
              onChanged: onThermal,
            ),
          ],
        ],
      ),
    );
  }
}

/// What's playing, with previous / play-pause / next.
class MediaCard extends StatelessWidget {
  const MediaCard({
    super.key,
    required this.palette,
    required this.media,
    required this.onAction,
  });

  final ForgePalette palette;
  final Map<String, dynamic> media;
  final ValueChanged<String> onAction;

  Widget _art(ForgePalette p) {
    final url = media['art'] as String?;
    final fallback = Container(
      color: p.hover,
      child: Icon(Icons.music_note_rounded, color: p.dimText),
    );
    Widget image = fallback;
    if (url != null && url.startsWith('file://')) {
      image = Image.file(File(Uri.parse(url).toFilePath()),
          fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback);
    } else if (url != null && url.startsWith('http')) {
      image = Image.network(url,
          fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(width: 48, height: 48, child: image),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final title = (media['title'] as String?) ?? '';
    final artist = (media['artist'] as String?) ?? '';
    final playing = media['playing'] == true;
    Widget button(IconData icon, String action, bool enabled) => IconButton(
          icon: Icon(icon, color: p.text),
          iconSize: 26,
          visualDensity: VisualDensity.compact,
          onPressed: enabled ? () => onAction(action) : null,
        );
    return Container(
      decoration: _card(p),
      padding: const EdgeInsets.all(10),
      child: Row(children: [
        _art(p),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title.isEmpty ? (media['player'] as String? ?? '') : title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: p.text,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700)),
              Text(artist.isEmpty ? (media['player'] as String? ?? '') : artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.dimText, fontSize: 12)),
            ],
          ),
        ),
        button(Icons.skip_previous_rounded, 'previous',
            media['can_previous'] == true),
        button(playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            'play-pause', true),
        button(Icons.skip_next_rounded, 'next', media['can_next'] == true),
      ]),
    );
  }
}

/// Battery on the left (or a message, briefly), Settings on the right.
class Footer extends StatelessWidget {
  const Footer({
    super.key,
    required this.palette,
    required this.battery,
    required this.message,
  });

  final ForgePalette palette;
  final Map<String, dynamic>? battery;
  final String message;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final dim = TextStyle(color: p.dimText, fontSize: 12);
    Widget left = const SizedBox.shrink();
    if (message.isNotEmpty) {
      left = Text(message,
          maxLines: 2, style: dim.copyWith(color: p.negative));
    } else if (battery != null) {
      final pct = battery!['percent'] as int? ?? 0;
      final charging = battery!['charging'] == true;
      final mins = battery!['minutes_left'] as int?;
      left = Row(children: [
        Icon(
            charging
                ? Icons.battery_charging_full_rounded
                : pct > 20
                    ? Icons.battery_std_rounded
                    : Icons.battery_alert_rounded,
            size: 18,
            color: pct > 20 || charging ? p.dimText : p.negative),
        const SizedBox(width: 4),
        Text(
            '$pct%${!charging && mins != null ? ' · ${mins ~/ 60}h ${mins % 60}m left' : ''}',
            style: dim),
      ]);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(children: [
        Expanded(child: left),
        TextButton.icon(
          onPressed: () => Process.start('systemsettings', [],
              mode: ProcessStartMode.detached),
          icon: Icon(Icons.settings_rounded, size: 16, color: p.text),
          label: Text('Settings',
              style: TextStyle(
                  color: p.text, fontSize: 12.5, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}
