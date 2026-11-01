// KWin, the compositor under the Forge desktop. KWin scripts can call out
// over D-Bus but can't be called, so it goes both ways like this:
//
//  * The bridge, a KWin script loaded once (by whichever shell part comes
//    first), calls Windows(json) on every shell part
//    (org.forgeos.Shell.p<pid> on the session bus) whenever windows or
//    virtual desktops change, and Run(command) on one of them for Forge's
//    shortcuts (KWin itself has no "run a command" action). The brightness
//    keys are powerdevil's.
//  * The shell changes things by loading a one-line script, running it
//    and unloading it again (activate a window, switch desktop).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dbus/dbus.dart';

import 'native.dart';
import 'wm.dart';

const _bridgeName = 'forge-shell-bridge';

/// What the bridge and the one-off scripts share: `push()` sends the state
/// to every shell part.
const _pushJs = r'''
function forgeState() {
  const desktops = workspace.desktops;
  const order = workspace.stackingOrder;
  const windows = [];
  for (let i = order.length - 1; i >= 0; i--) {
    const w = order[i];
    if (!w.normalWindow || w.skipTaskbar) continue;
    windows.push({
      id: w.internalId.toString(),
      app: w.desktopFileName || w.resourceClass || "",
      title: w.caption || "",
      minimized: w.minimized,
      focused: w === workspace.activeWindow,
      desktops: w.onAllDesktops ? [] :
        w.desktops.map(d => desktops.indexOf(d) + 1),
    });
  }
  return JSON.stringify({
    windows: windows,
    desktop: desktops.indexOf(workspace.currentDesktop) + 1,
    desktops: desktops.length,
  });
}
function forgeShells(then) {
  callDBus("org.freedesktop.DBus", "/org/freedesktop/DBus",
    "org.freedesktop.DBus", "ListNames", function (names) {
      then(names.filter(n => n.startsWith("org.forgeos.Shell.")).sort());
    });
}
function push() {
  const state = forgeState();
  forgeShells(shells => shells.forEach(s =>
    callDBus(s, "/org/forgeos/Shell", "org.forgeos.Shell", "Windows", state)));
}
''';

const _bridgeJs =
    '''
$_pushJs
function run(command) {
  forgeShells(shells => {
    if (shells.length)
      callDBus(shells[0], "/org/forgeos/Shell", "org.forgeos.Shell", "Run", command);
  });
}
function watch(w) {
  w.captionChanged.connect(push);
  w.minimizedChanged.connect(push);
  w.desktopsChanged.connect(push);
}
workspace.windowList().forEach(watch);
workspace.windowAdded.connect(w => { watch(w); push(); });
workspace.windowRemoved.connect(push);
workspace.windowActivated.connect(push);
workspace.currentDesktopChanged.connect(push);
workspace.desktopsChanged.connect(push);

registerShortcut("Forge Launcher", "Forge: Launcher", "Meta+Space",
  () => run("forge-launcher"));
registerShortcut("Forge Control", "Forge: Control Center", "Meta+A",
  () => run("forge-control"));
registerShortcut("Forge Terminal", "Forge: Terminal", "Meta+Return",
  () => run("konsole"));
registerShortcut("Forge Files", "Forge: Files", "Meta+E",
  () => run("dolphin"));
registerShortcut("Forge Close", "Forge: Close window", "Meta+Q",
  () => { if (workspace.activeWindow) workspace.activeWindow.closeWindow(); });
registerShortcut("Forge Lock", "Forge: Lock screen", "Meta+L",
  () => run("loginctl lock-session"));
registerShortcut("Forge Screenshot", "Forge: Screenshot", "Print",
  () => run("forge-shot"));
registerShortcut("Forge Volume Up", "Forge: Volume up", "Volume Up",
  () => run("wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+"));
registerShortcut("Forge Volume Down", "Forge: Volume down", "Volume Down",
  () => run("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"));
registerShortcut("Forge Mute", "Forge: Mute", "Volume Mute",
  () => run("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"));
registerShortcut("Forge Mic Mute", "Forge: Mute microphone", "Microphone Mute",
  () => run("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"));
registerShortcut("Forge Play", "Forge: Play/pause", "Media Play",
  () => run("playerctl play-pause"));
registerShortcut("Forge Next", "Forge: Next track", "Media Next",
  () => run("playerctl next"));
registerShortcut("Forge Previous", "Forge: Previous track", "Media Previous",
  () => run("playerctl previous"));

push();
''';

class _ShellObject extends DBusObject {
  _ShellObject(this._kwin) : super(DBusObjectPath('/org/forgeos/Shell'));

  final KWinWm _kwin;

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    if (call.interface != 'org.forgeos.Shell' ||
        call.signature != DBusSignature('s')) {
      return DBusMethodErrorResponse.unknownMethod();
    }
    final arg = call.values.first.asString();
    switch (call.name) {
      case 'Windows':
        _kwin._update(arg);
      case 'Run':
        Native.run(arg);
      default:
        return DBusMethodErrorResponse.unknownMethod();
    }
    return DBusMethodSuccessResponse();
  }
}

class KWinWm extends Wm {
  KWinWm() {
    _ready = _start();
    _ready.catchError((Object e) => stderr.writeln('forge-shell: KWin: $e'));
  }

  final _client = DBusClient.session();
  final _changes = StreamController<void>.broadcast();
  late final Future<void> _ready;
  Map<String, dynamic>? _state;
  Completer<void>? _firstState = Completer();
  int _scripts = 0;

  late final _scripting = DBusRemoteObject(
    _client,
    name: 'org.kde.KWin',
    path: DBusObjectPath('/Scripting'),
  );

  Future<void> _start() async {
    await _client.requestName('org.forgeos.Shell.p$pid');
    await _client.registerObject(_ShellObject(this));
    final loaded = await _scripting.callMethod(
      'org.kde.kwin.Scripting',
      'isScriptLoaded',
      [const DBusString(_bridgeName)],
      replySignature: DBusSignature('b'),
    );
    if (loaded.values.first.asBoolean()) {
      // Up already, for another part: ask for the state now.
      await _runScript('$_pushJs\npush();');
    } else {
      await _runScript(_bridgeJs, name: _bridgeName, keep: true);
    }
  }

  void _update(String json) {
    try {
      _state = jsonDecode(json) as Map<String, dynamic>;
    } on FormatException catch (_) {
      return;
    }
    _firstState?.complete();
    _firstState = null;
    _changes.add(null);
  }

  /// Loads [js] into KWin and runs it; unloads it after unless [keep].
  Future<void> _runScript(String js, {String? name, bool keep = false}) async {
    final plugin = name ?? 'forge-shell-$pid-${_scripts++}';
    final dir = Platform.environment['XDG_RUNTIME_DIR'] ?? '/tmp';
    final file = File('$dir/$plugin.js');
    await file.writeAsString(js);
    try {
      final reply = await _scripting.callMethod(
        'org.kde.kwin.Scripting',
        'loadScript',
        [DBusString(file.path), DBusString(plugin)],
        replySignature: DBusSignature('i'),
      );
      final id = reply.values.first.asInt32();
      if (id < 0) return; // loaded already
      await DBusRemoteObject(
        _client,
        name: 'org.kde.KWin',
        path: DBusObjectPath('/Scripting/Script$id'),
      ).callMethod(
        'org.kde.kwin.Script',
        'run',
        [],
        replySignature: DBusSignature(''),
      );
      if (!keep) {
        await _scripting.callMethod('org.kde.kwin.Scripting', 'unloadScript', [
          DBusString(plugin),
        ], replySignature: DBusSignature('b'));
      }
    } finally {
      // KWin has read it by now (run is synchronous).
      if (!keep) await file.delete().catchError((_) => file);
    }
  }

  Future<Map<String, dynamic>> _current() async {
    await _ready;
    final first = _firstState;
    if (first != null) {
      await first.future.timeout(const Duration(seconds: 2), onTimeout: () {});
    }
    return _state ?? const {};
  }

  @override
  bool get hasWorkspaces => true;

  @override
  Stream<void> changes() => _changes.stream;

  @override
  Future<List<Window>> windows() async {
    final list = (await _current())['windows'] as List? ?? const [];
    // Listed top of the stack first, so the order is the focus history.
    return [
      for (final (i, w) in list.indexed)
        Window(
          id: (w as Map)['id'] as String,
          appClass: w['app'] as String? ?? '',
          title: w['title'] as String? ?? '',
          minimized: w['minimized'] == true,
          focusHistory: w['focused'] == true ? 0 : i + 1,
        ),
    ];
  }

  @override
  Future<void> activate(Window window) => _runScript('''
for (const w of workspace.windowList()) {
  if (w.internalId.toString() === ${jsonEncode(window.id)}) {
    w.minimized = false;
    workspace.activeWindow = w;
  }
}''');

  @override
  Future<void> close(Window window) => _runScript('''
for (const w of workspace.windowList()) {
  if (w.internalId.toString() === ${jsonEncode(window.id)}) w.closeWindow();
}''');

  @override
  Future<int> activeWorkspace() async =>
      (await _current())['desktop'] as int? ?? 1;

  @override
  Future<Set<int>> occupiedWorkspaces() async => {
    for (final w in (await _current())['windows'] as List? ?? const [])
      for (final d in (w as Map)['desktops'] as List? ?? const []) d as int,
  };

  @override
  Future<void> switchWorkspace(int n) => _runScript('''
const d = workspace.desktops[${n - 1}];
if (d) workspace.currentDesktop = d;''');
}
