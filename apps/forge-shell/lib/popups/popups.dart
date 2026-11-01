// forge-shell popups: everything the Forge desktop pops up, drawn on one
// screen-sized overlay that's mapped only while something is open:
//
//   the start menu      the bar's emblem, a tap on Super
//   the calendar        the bar's clock
//   menus               right-clicking the dock or the desktop
//   dialogs             forge-dialog, the power choices and their questions
//   the wallpaper picker
//   polkit's prompt     when an app needs an administrator (the runner is
//                       the polkit agent; see linux/runner/polkit_agent.cc)
//
// Asked for over D-Bus, org.forgeos.Popups at /org/forgeos/Popups:
//   StartMenu(), Calendar(), Wallpapers(), Power(s what)   open and return
//   Menu(s json) → s id, Dialog(s json) → s json           wait for the answer
// (popups/client.dart, and the forge-dialog script).
//
// One thing at a time: a menu, the start menu or the calendar gives way to
// whatever opens next; dialogs (and polkit's prompt) wait their turn and
// can't be clicked away.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forge_ui/forge_ui.dart';

import '../native.dart';
import 'calendar.dart';
import 'client.dart' show popupsName, popupsPath;
import 'dialog.dart';
import 'menu.dart';
import 'polkit.dart';
import 'style.dart';
import 'start_menu.dart';
import 'wallpapers.dart';

/// Where the top bar ends (forge-shell bar: 8 px margin, 34 px tall), so
/// what drops from it starts just below.
const _belowBar = 8.0 + 34 + 6;
const _edge = 8.0;

sealed class _Entry {
  final _done = Completer<String>();
  Future<String> get result => _done.future;

  /// Waits its turn, dims the screen, isn't closed by clicking outside.
  bool get modal => false;

  void complete(String r) {
    if (!_done.isCompleted) _done.complete(r);
  }
}

class _StartEntry extends _Entry {}

class _CalendarEntry extends _Entry {}

class _WallpaperEntry extends _Entry {
  @override
  bool get modal => true;
}

class _PowerEntry extends _Entry {
  @override
  bool get modal => true;
}

class _MenuEntry extends _Entry {
  _MenuEntry(this.spec, this.at, {this.above = false});

  final MenuSpec spec;
  final Offset at;
  final bool above;
}

class _DialogEntry extends _Entry {
  _DialogEntry(this.spec);

  final DialogSpec spec;

  /// What was typed in its field, if it has one.
  String typed = '';

  @override
  bool get modal => true;
}

class _AuthEntry extends _Entry {
  _AuthEntry(this.request);

  final AuthRequest request;
  final state = AuthState();

  @override
  bool get modal => true;
}

class PopupsHost extends StatefulWidget {
  const PopupsHost({super.key, required this.palette});

  final ForgePalette palette;

  @override
  State<PopupsHost> createState() => _PopupsHostState();
}

class _PopupsHostState extends State<PopupsHost> {
  final _bus = DBusClient.session();
  _Entry? _current;
  final _queue = <_Entry>[];

  /// A menu over the current popup (an app's menu in the start menu).
  _MenuEntry? _sub;
  bool _mapped = false;
  List<App> _apps = [];

  @override
  void initState() {
    super.initState();
    _loadApps();
    HardwareKeyboard.instance.addHandler(_escape);
    Native.onCall(_fromRunner);
    _serve();
    _polkit();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_escape);
    _bus.close();
    super.dispose();
  }

  Future<void> _loadApps() async {
    try {
      final apps = await Native.apps();
      if (mounted) setState(() => _apps = apps);
    } catch (_) {}
  }

  Future<void> _serve() async {
    try {
      final reply = await _bus.requestName(
        popupsName,
        flags: {DBusRequestNameFlag.doNotQueue},
      );
      if (reply != DBusRequestNameReply.primaryOwner &&
          reply != DBusRequestNameReply.alreadyOwner) {
        stderr.writeln('forge-shell popups: $popupsName is taken ($reply)');
      }
      await _bus.registerObject(_PopupsObject(this));
    } catch (e) {
      stderr.writeln('forge-shell popups: D-Bus: $e');
    }
  }

  /// Be polkit's agent for this session, or leave it to KDE's.
  Future<void> _polkit() async {
    final env = Platform.environment;
    if (env['FORGE_NO_POLKIT'] == '1') return;
    try {
      await Native.call<void>('polkitRegister');
    } on PlatformException catch (e) {
      stderr.writeln('forge-shell popups: no polkit agent: ${e.message}');
      // In a real Forge session someone must answer polkit, or nothing
      // that needs a password works.
      if (env['XDG_CURRENT_DESKTOP'] == 'Forge' &&
          (env['FORGE_POLKIT_PROCESS'] ?? '').isEmpty) {
        Native.run('/usr/lib/polkit-kde-authentication-agent-1');
      }
    }
  }

  // --- Opening and closing ----------------------------------------------------

  Future<String> _open(_Entry e) {
    final cur = _current;
    if (cur == null) {
      _current = e;
    } else if (!cur.modal) {
      _closeSub();
      cur.complete('');
      _current = e;
    } else if (e.modal) {
      _queue.add(e);
    } else {
      e.complete(''); // a menu can't open over a question
      return e.result;
    }
    _update();
    return e.result;
  }

  void _close(_Entry e, [String result = '']) {
    e.complete(result);
    if (identical(_current, e)) {
      _closeSub();
      _current = _queue.isEmpty ? null : _queue.removeAt(0);
      if (_current is _StartEntry) _loadApps();
    } else {
      _queue.remove(e);
    }
    if (e is _StartEntry) _loadApps(); // anything installed meanwhile
    _update();
  }

  void _closeSub() {
    _sub?.complete('');
    _sub = null;
  }

  /// Redraws, mapping the overlay when something's open and unmapping it
  /// once the empty frame is drawn.
  void _update() {
    if (!mounted) return;
    setState(() {});
    if (_current != null && !_mapped) {
      _mapped = true;
      Native.call<void>('show');
    } else if (_current == null && _mapped) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_current == null && _mapped) {
          _mapped = false;
          Native.call<void>('hide');
        }
      });
    }
  }

  bool _escape(KeyEvent e) {
    if (e is! KeyDownEvent || e.logicalKey != LogicalKeyboardKey.escape) {
      return false;
    }
    if (_sub != null) {
      _closeSub();
      _update();
      return true;
    }
    final cur = _current;
    if (cur == null) return false;
    if (cur is _AuthEntry) {
      _cancelAuth(cur);
    } else {
      _close(cur);
    }
    return true;
  }

  // --- What can be asked for ---------------------------------------------------

  void toggleStart() {
    final cur = _current;
    if (cur is _StartEntry) {
      _close(cur);
    } else {
      _open(_StartEntry());
    }
  }

  void toggleCalendar() {
    final cur = _current;
    if (cur is _CalendarEntry) {
      _close(cur);
    } else {
      _open(_CalendarEntry());
    }
  }

  void wallpapers() => _open(_WallpaperEntry());

  Future<String> menu(Map<String, dynamic> m) => _open(
    _MenuEntry(
      MenuSpec.fromJson(m),
      Offset((m['x'] as num? ?? 0).toDouble(), (m['y'] as num? ?? 0).toDouble()),
      above: m['above'] == true,
    ),
  );

  Future<String> dialog(Map<String, dynamic> m) async {
    final e = _DialogEntry(DialogSpec.fromJson(m));
    final button = await _open(e);
    return jsonEncode({'button': button, 'text': e.typed});
  }

  /// '' shows the choices; an action id asks about it (if it needs asking)
  /// and does it.
  Future<void> power(String what) async {
    if (what.isEmpty) {
      what = await _open(_PowerEntry());
      if (what.isEmpty) return;
    }
    final action = PowerAction.byId(what);
    if (action == null) return;
    if (action.confirm != null) {
      final answer = await _open(_DialogEntry(action.confirmDialog()));
      if (answer != action.id) return;
    }
    _doPower(action.id);
  }

  void _doPower(String id) {
    final session = Platform.environment['XDG_SESSION_ID'] ?? '';
    final command = switch (id) {
      'lock' => 'loginctl lock-session',
      'sleep' => 'systemctl suspend',
      'logout' => 'loginctl terminate-session $session',
      'restart' => 'systemctl reboot',
      'shutdown' => 'systemctl poweroff',
      _ => 'true',
    };
    // Tests: say what would happen instead (a nested session shares the
    // real one's login session, so "log out" would end that).
    if (Platform.environment['FORGE_DRY_POWER'] == '1') {
      stderr.writeln('forge-shell popups: would run: $command');
      return;
    }
    Native.run(command);
  }

  // --- polkit, through the runner --------------------------------------------

  _AuthEntry? _auth(Object? args) {
    final id = (args as Map?)?['id'];
    for (final e in [_current, ..._queue]) {
      if (e is _AuthEntry && e.request.id == id) return e;
    }
    return null;
  }

  Future<Object?> _fromRunner(MethodCall call) async {
    final args = call.arguments;
    switch (call.method) {
      case 'authBegin':
        _open(_AuthEntry(AuthRequest.fromJson(args as Map)));
      case 'authInfo':
        final m = args as Map;
        _auth(m)?.state.message(m['text'] as String? ?? '', m['error'] == true);
      case 'authDone':
        final e = _auth(args);
        if (e == null) break;
        if ((args as Map)['ok'] == true) {
          _close(e);
        } else {
          e.state.failed("That password didn't work. Try again.");
        }
      case 'authClose':
        final e = _auth(args);
        if (e != null) _close(e);
    }
    return null;
  }

  void _cancelAuth(_AuthEntry e) {
    Native.call<void>('authCancel', {'id': e.request.id});
    _close(e);
  }

  // --- Drawing -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final cur = _current;
    final sub = _sub;
    return LayoutBuilder(
      builder: (context, box) {
        final screen = box.biggest;
        return Stack(
          children: [
            // Outside the popup: a click closes a menu; a question stays.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (_) => _outside(),
                onSecondaryTapDown: (_) => _outside(),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  color: cur != null && cur.modal
                      ? Colors.black.withValues(alpha: p.dark ? 0.35 : 0.22)
                      : Colors.transparent,
                ),
              ),
            ),
            if (cur != null)
              KeyedSubtree(
                key: ObjectKey(cur),
                child: _place(cur, screen, _content(cur)),
              ),
            if (sub != null) ...[
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (_) => setState(_closeSub),
                  onSecondaryTapDown: (_) => setState(_closeSub),
                ),
              ),
              KeyedSubtree(
                key: ObjectKey(sub),
                child: _place(sub, screen, _menuCard(sub)),
              ),
            ],
          ],
        );
      },
    );
  }

  void _outside() {
    if (_sub != null) {
      setState(_closeSub);
      return;
    }
    final cur = _current;
    if (cur != null && !cur.modal) _close(cur);
  }

  Widget _menuCard(_MenuEntry e) => MenuCard(
    palette: widget.palette,
    spec: e.spec,
    onPick: (id) {
      if (identical(e, _sub)) {
        e.complete(id);
        setState(() => _sub = null);
      } else {
        _close(e, id);
      }
    },
  );

  Widget _content(_Entry e) {
    final p = widget.palette;
    return switch (e) {
      _StartEntry() => StartMenu(
        palette: p,
        apps: _apps,
        onLaunch: (app) {
          _close(e);
          Native.launch(app.id);
        },
        onPower: (id) {
          _close(e);
          power(id);
        },
        onMenu: (at, spec) {
          _closeSub();
          final m = _MenuEntry(spec, at);
          setState(() => _sub = m);
          return m.result;
        },
      ),
      _CalendarEntry() => CalendarCard(palette: p),
      _WallpaperEntry() => WallpaperPicker(palette: p, onClose: () => _close(e)),
      _PowerEntry() => PowerCard(palette: p, onPick: (id) => _close(e, id)),
      _MenuEntry() => _menuCard(e),
      _DialogEntry() => DialogCard(
        palette: p,
        spec: e.spec,
        onDone: (button, text) {
          e.typed = text;
          _close(e, button);
        },
      ),
      _AuthEntry() => AuthCard(
        palette: p,
        request: e.request,
        state: e.state,
        onRespond: (user, password) => Native.call<void>('authRespond', {
          'id': e.request.id,
          'user': user,
          'password': password,
        }),
        onCancel: () => _cancelAuth(e),
      ),
    };
  }

  /// Where each kind goes on the screen.
  Widget _place(_Entry e, Size screen, Widget child) {
    switch (e) {
      case _StartEntry():
        return Positioned(
          left: _edge,
          top: _belowBar,
          child: PopIn(origin: Alignment.topLeft, child: child),
        );
      case _CalendarEntry():
        return Positioned(
          left: (screen.width - calendarWidth) / 2,
          top: _belowBar,
          child: PopIn(child: child),
        );
      case _MenuEntry(:final at, :final above):
        return Positioned.fill(
          child: CustomSingleChildLayout(
            delegate: _MenuLayout(at, above),
            child: PopIn(
              origin: above ? Alignment.bottomLeft : Alignment.topLeft,
              child: child,
            ),
          ),
        );
      default:
        return Center(
          child: PopIn(origin: Alignment.center, child: child),
        );
    }
  }
}

/// A menu at a point, kept on the screen: flipped left or up if it would
/// run off the right or bottom edge.
class _MenuLayout extends SingleChildLayoutDelegate {
  _MenuLayout(this.at, this.above);

  final Offset at;
  final bool above;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints c) =>
      BoxConstraints.loose(c.biggest).deflate(const EdgeInsets.all(_edge));

  @override
  Offset getPositionForChild(Size screen, Size menu) {
    var x = at.dx;
    if (x + menu.width > screen.width - _edge) x = at.dx - menu.width;
    var y = above ? at.dy - menu.height : at.dy;
    if (!above && y + menu.height > screen.height - _edge) {
      y = at.dy - menu.height;
    }
    return Offset(
      x.clamp(_edge, (screen.width - menu.width - _edge).clamp(_edge, 1e9)),
      y.clamp(_edge, (screen.height - menu.height - _edge).clamp(_edge, 1e9)),
    );
  }

  @override
  bool shouldRelayout(_MenuLayout old) => old.at != at || old.above != above;
}

class _PopupsObject extends DBusObject {
  _PopupsObject(this._host) : super(DBusObjectPath(popupsPath));

  final _PopupsHostState _host;

  static DBusMethodResponse _ok([String? s]) =>
      DBusMethodSuccessResponse([if (s != null) DBusString(s)]);

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    if (call.interface != null && call.interface != popupsName) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    String arg() =>
        call.values.isNotEmpty && call.values.first is DBusString
        ? call.values.first.asString()
        : '';
    Map<String, dynamic> json() {
      try {
        return jsonDecode(arg()) as Map<String, dynamic>;
      } catch (_) {
        return {};
      }
    }

    switch (call.name) {
      case 'StartMenu':
        _host.toggleStart();
        return _ok();
      case 'Calendar':
        _host.toggleCalendar();
        return _ok();
      case 'Wallpapers':
        _host.wallpapers();
        return _ok();
      case 'Power':
        unawaited(_host.power(arg()));
        return _ok();
      case 'Menu':
        return _ok(await _host.menu(json()));
      case 'Dialog':
        return _ok(await _host.dialog(json()));
    }
    return DBusMethodErrorResponse.unknownMethod();
  }

  @override
  List<DBusIntrospectInterface> introspect() => [
    DBusIntrospectInterface(
      popupsName,
      methods: [
        DBusIntrospectMethod('StartMenu'),
        DBusIntrospectMethod('Calendar'),
        DBusIntrospectMethod('Wallpapers'),
        DBusIntrospectMethod(
          'Power',
          args: [
            DBusIntrospectArgument(
              DBusSignature('s'),
              DBusArgumentDirection.in_,
              name: 'what',
            ),
          ],
        ),
        for (final m in ['Menu', 'Dialog'])
          DBusIntrospectMethod(
            m,
            args: [
              DBusIntrospectArgument(
                DBusSignature('s'),
                DBusArgumentDirection.in_,
                name: 'json',
              ),
              DBusIntrospectArgument(
                DBusSignature('s'),
                DBusArgumentDirection.out,
                name: 'answer',
              ),
            ],
          ),
      ],
    ),
  ];
}
