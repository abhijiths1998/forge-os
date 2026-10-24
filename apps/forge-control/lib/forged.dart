// forged over D-Bus (org.forgeos.Forged on the session bus): the desktop's
// state as JSON, a Changed signal carrying the whole state whenever any of
// it changes, and Set / Media to change things. D-Bus starts forged on the
// first call if it isn't running.
import 'dart:convert';

import 'package:dbus/dbus.dart';

typedef DesktopState = Map<String, dynamic>;

class Forged {
  Forged() : _client = DBusClient.session() {
    _object = DBusRemoteObject(_client,
        name: _name, path: DBusObjectPath('/org/forgeos/Forged'));
  }

  static const _name = 'org.forgeos.Forged';
  final DBusClient _client;
  late final DBusRemoteObject _object;

  Stream<DesktopState> get changes => DBusRemoteObjectSignalStream(
        object: _object,
        interface: _name,
        name: 'Changed',
        signature: DBusSignature('s'),
      ).map((s) => jsonDecode(s.values.first.asString()) as DesktopState);

  Future<DesktopState> state() async {
    final reply = await _object.callMethod(_name, 'State', [],
        replySignature: DBusSignature('s'));
    return jsonDecode(reply.values.first.asString()) as DesktopState;
  }

  /// Changes one thing (see `forged help`); an error to show, or "".
  Future<String> set(String key, String value) async {
    final reply = await _object.callMethod(
        _name, 'Set', [DBusString(key), DBusString(value)],
        replySignature: DBusSignature('s'));
    return reply.values.first.asString();
  }

  /// play-pause, next or previous, on the player forged picked.
  Future<void> media(String action) => _object.callMethod(
      _name, 'Media', [DBusString(action)],
      replySignature: DBusSignature('b'));
}
