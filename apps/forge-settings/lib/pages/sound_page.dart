// Sound page: volume and the default output, read and set through wpctl
// (PipeWire). There’s no server to restart: changes apply at once.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

import '../main.dart';

class SoundPage extends StatefulWidget {
  const SoundPage({super.key});

  @override
  State<SoundPage> createState() => _SoundPageState();
}

class _SoundPageState extends State<SoundPage> {
  int _volume = 50;
  bool _muted = false;
  String _defaultSink = '';
  List<String> _sinks = <String>[];
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _volume();
    await _sinks();
  }

  /// Parse "Volume: 0.50" (wpctl prints 0.0–1.0) and the mute flag.
  Future<void> _volume() async {
    try {
      final r = await Process.run('wpctl', ['get-volume', '@DEFAULT_AUDIO_SINK@']);
      final out = (r.stdout as String).trim();
      final muted = out.contains('[MUTED]');
      final m = RegExp(r'Volume:\s*([\d.]+)').firstMatch(out);
      final vol = m != null ? (double.tryParse(m.group(1)!) ?? 0.5) : 0.5;
      if (!mounted) return;
      setState(() {
        _volume = (vol * 100).round();
        _muted = muted;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Couldn’t read the volume (wpctl get-volume).');
    }
  }

  /// List sinks from wpctl status, taking the names after "├─" / "└─".
  Future<void> _sinks() async {
    try {
      final r = await Process.run('wpctl', ['status']);
      final out = (r.stdout as String);
      final sinks = <String>[];
      var inAudio = false;
      for (final line in out.split('\n')) {
        if (line.contains('Audio')) {
          inAudio = true;
          continue;
        }
        if (inAudio) {
          final m = RegExp(r'[├└]─\s*([^\[]+?)\s*\[vol').firstMatch(line);
          if (m != null) sinks.add(m.group(1)!.trim());
        }
      }
      if (!mounted) return;
      setState(() => _sinks = sinks);
    } catch (_) {}
  }

  Future<void> _setVolume(int pct) async {
    final vol = (pct / 100).clamp(0.0, 1.0);
    try {
      await Process.run('wpctl', ['set-volume', '@DEFAULT_AUDIO_SINK@', vol.toStringAsFixed(2)]);
      if (!mounted) return;
      setState(() {
        _volume = pct;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = "Couldn't set the volume: $e");
    }
  }

  Future<void> _toggleMute() async {
    try {
      await Process.run('wpctl', ['set-mute', '@DEFAULT_AUDIO_SINK@', 'toggle']);
      if (!mounted) return;
      setState(() {
        _muted = !_muted;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = "Couldn't toggle mute: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = ForgePalette.current();
    return SettingsPage(
      title: 'Sound',
      sub: 'Volume and output through PipeWire (wpctl).',
      error: _error,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel('Output', palette: p),
          SettingRow(
            label: 'Default output',
            desc: 'The sink PipeWire sends sound to.',
            control: SizedBox(
              width: 260,
              child: DropdownButtonFormField<String>(
                value: _defaultSink.isEmpty ? null : _defaultSink,
                items: _sinks
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _defaultSink = v);
                    _busy = true;
                    Process.run('wpctl', ['set-default', v]).then((_) {
                      setState(() => _busy = false);
                    });
                  }
                },
              ),
            ),
          ),
          SettingRow(
            label: 'Volume',
            desc: 'The default sink’s volume, set at once.',
            control: SizedBox(
              width: 260,
              child: ForgeSlider(
                palette: p,
                label: '',
                value: _volume.toDouble(),
                min: 0,
                max: 150,
                divisions: 150,
                format: (v) => '${v.round()}%${_muted ? ' (muted)' : ''}',
                onChanged: (v) => setState(() => _volume = v.round()),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              PillButton(
                palette: p,
                label: _muted ? 'Unmute' : 'Mute',
                onTap: _toggleMute,
              ),
              const SizedBox(width: 8),
              ApplyButton(
                label: 'Apply volume',
                onTap: () {
                  setState(() => _busy = true);
                  _setVolume(_volume);
                  setState(() => _busy = false);
                },
                busy: _busy,
              ),
              const SizedBox(width: 8),
              Text(
                _muted ? 'Muted' : '',
                style: TextStyle(fontSize: 12.5, color: p.negative),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SectionLabel('Advanced', palette: p),
          Text(
            '• Volume changes apply at once — there’s nothing to reload.\n'
            '• For VPN and advanced network settings, open nm-connection-editor.\n'
            '• Per-app volume and input devices: pavucontrol.',
            style: TextStyle(fontSize: 12.5, color: p.dimText),
          ),
        ],
      ),
    );
  }
}
