// The window manager under the shell, whichever it is: KWin (the Forge
// session's compositor) or Forge Compositor (its JSON IPC,
// $FORGE_COMPOSITOR_SOCKET, when forge-session is asked for it). The bar
// and dock only see this.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'kwin.dart';

class Window {
  const Window({
    required this.id,
    required this.appClass,
    required this.title,
    this.minimized = false,
    this.mapped = true,
    required this.focusHistory,
  });

  final String id;

  /// The app id (Wayland) or class (X11).
  final String appClass;
  final String title;
  final bool minimized;
  final bool mapped;

  /// 0 is the focused window, 1 the one before...
  final int focusHistory;
}

abstract class Wm {
  /// The running window manager: Forge Compositor if this runs under it,
  /// KWin otherwise.
  static Wm connect() {
    final forge = Platform.environment['FORGE_COMPOSITOR_SOCKET'];
    if (forge != null && forge.isNotEmpty) return ForgeWm(forge);
    return KWinWm();
  }

  bool get hasWorkspaces;

  /// Fires whenever windows or workspaces change.
  Stream<void> changes();

  Future<List<Window>> windows();

  /// Raises and focuses a window, bringing it back if it was minimised.
  Future<void> activate(Window window);

  /// Asks a window to close (it may ask about unsaved work first).
  Future<void> close(Window window);

  Future<int> activeWorkspace() async => 1;
  Future<Set<int>> occupiedWorkspaces() async => {};
  Future<void> switchWorkspace(int n) async {}
}

/// Forge Compositor: one JSON request per line, one reply per line.
class ForgeWm extends Wm {
  ForgeWm(this._path);

  final String _path;

  @override
  bool get hasWorkspaces => false;

  Future<Map<String, dynamic>> request(Map<String, Object> req) async {
    final socket = await Socket.connect(
      InternetAddress(_path, type: InternetAddressType.unix),
      0,
    );
    socket.write('${jsonEncode(req)}\n');
    await socket.flush();
    final line = await utf8.decoder
        .bind(socket)
        .transform(const LineSplitter())
        .first;
    socket.destroy();
    return jsonDecode(line) as Map<String, dynamic>;
  }

  static List<Window> _windows(Object? list) {
    // The compositor lists windows front to back, minimised ones last, so
    // the order is the focus history.
    final out = <Window>[];
    for (final w in (list as List? ?? const [])) {
      final m = w as Map<String, dynamic>;
      final focused = m['focused'] == true;
      out.add(
        Window(
          id: '${m['id']}',
          appClass: m['app_id'] as String? ?? '',
          title: m['title'] as String? ?? '',
          minimized: m['minimized'] == true,
          focusHistory: focused ? 0 : out.length + 1,
        ),
      );
    }
    return out;
  }

  @override
  Stream<void> changes() async* {
    while (true) {
      try {
        final socket = await Socket.connect(
          InternetAddress(_path, type: InternetAddressType.unix),
          0,
        );
        socket.write('${jsonEncode({'subscribe': true})}\n');
        await socket.flush();
        await for (final _
            in utf8.decoder.bind(socket).transform(const LineSplitter())) {
          yield null;
        }
      } catch (_) {}
      await Future.delayed(const Duration(seconds: 1));
    }
  }

  @override
  Future<List<Window>> windows() async =>
      _windows((await request({'get': 'windows'}))['windows']);

  @override
  Future<void> activate(Window window) =>
      request({'activate': int.parse(window.id)});

  @override
  Future<void> close(Window window) =>
      request({'close': int.parse(window.id)});
}
