// forge-thermal, which does the work: `status` and `list` run as the user,
// changing the profile goes through pkexec (polkit action
// org.forgeos.thermal: no password for the user at the machine).
import 'dart:io';

const helper = String.fromEnvironment('FORGE_THERMAL', defaultValue: '/usr/local/bin/forge-thermal');

/// The firmware limits a profile can set, in the order the app shows them.
const firmwareKeys = ['CPU_TEMP_LIMIT', 'GPU_TEMP_LIMIT', 'CPU_SUSTAINED_W', 'CPU_BOOST_W'];

/// One firmware limit as the firmware reports it.
class Limit {
  const Limit(this.current, this.min, this.max, this.fallback);

  final int current;
  final int min;
  final int max;

  /// The firmware's own default.
  final int fallback;

  static Limit? parse(String? line) {
    final v = line?.split(' ').map(int.tryParse).toList();
    if (v == null || v.length != 4 || v.contains(null)) return null;
    return Limit(v[0]!, v[1]!, v[2]!, v[3]!);
  }
}

class Status {
  Status(this.raw);

  final Map<String, String> raw;

  double? _num(String key) => double.tryParse(raw[key] ?? '');

  String get profile => raw['profile'] ?? 'balanced';
  double? get cpuTemp => _num('cpu_temp_c');
  double? get gpuTemp => _num('gpu_temp_c');
  double? get cpuClockGhz => _num('cpu_clock_khz') == null ? null : _num('cpu_clock_khz')! / 1e6;
  double? get cpuCapGhz => _num('cpu_cap_khz') == null ? null : _num('cpu_cap_khz')! / 1e6;
  double? get cpuMaxGhz => _num('cpu_max_khz') == null ? null : _num('cpu_max_khz')! / 1e6;
  double? get gpuClockMhz => _num('gpu_clock_mhz');
  double? get gpuMaxMhz => _num('gpu_max_mhz');
  double? get gpuWatts => _num('gpu_power_w');
  int? get fanRpm => int.tryParse(raw['fan_rpm'] ?? '');
  String? get gpuName => raw['gpu_name'];
  String? get platformProfile => raw['platform_profile'];

  /// A firmware limit by profile key (CPU_TEMP_LIMIT), if the firmware has it.
  Limit? limit(String key) => Limit.parse(raw['fw_${key.toLowerCase()}']);

  bool get hasFirmware => firmwareKeys.any((k) => limit(k) != null);
}

class Profile {
  const Profile(this.id, this.cpu, this.gpu, this.name, this.description, this.extras);

  final String id;
  final int cpu;
  final int gpu;
  final String name;
  final String description;

  /// PLATFORM_PROFILE and firmware limits, by key.
  final Map<String, String> extras;

  bool get needsFirmware => firmwareKeys.any(extras.containsKey);

  int? fw(String key) => int.tryParse(extras[key] ?? '');
}

class Thermal {
  Future<Status> status() async {
    final r = await Process.run(helper, ['status']);
    return Status({
      for (final line in (r.stdout as String).split('\n'))
        if (line.contains('=')) line.substring(0, line.indexOf('=')): line.substring(line.indexOf('=') + 1),
    });
  }

  Future<List<Profile>> list() async {
    final r = await Process.run(helper, ['list']);
    return [
      for (final line in (r.stdout as String).split('\n'))
        if (line.split('\t').length >= 5) _profile(line.split('\t')),
    ];
  }

  Profile _profile(List<String> f) =>
      Profile(f[0], int.tryParse(f[1]) ?? 100, int.tryParse(f[2]) ?? 100, f[3].isEmpty ? f[0] : f[3], f[4], {
        if (f.length > 5)
          for (final kv in f[5].split(' '))
            if (kv.contains('=')) kv.split('=')[0]: kv.split('=')[1],
      });

  /// Apply a profile; an error, or "" once it's applied.
  Future<String> apply(String id) => _root(['apply', id]);

  Future<String> custom(int cpu, int gpu, Map<String, int> limits) =>
      _root(['custom', '$cpu', '$gpu', for (final e in limits.entries) '${e.key}=${e.value}']);

  Future<String> _root(List<String> args) async {
    try {
      final r = await Process.run('pkexec', [helper, ...args]);
      if (r.exitCode == 0) return '';
      // 126/127: the polkit dialog was dismissed, or no agent.
      if (r.exitCode == 126 || r.exitCode == 127) return 'Not allowed: the change needs permission';
      final err = (r.stderr as String).trim();
      return err.isEmpty ? 'forge-thermal failed (${r.exitCode})' : err.replaceFirst('forge-thermal: ', '');
    } on ProcessException catch (e) {
      return e.message;
    }
  }
}
