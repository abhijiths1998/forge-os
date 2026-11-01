// Asking the popups part (forge-shell popups) for something, from the
// other shell parts: org.forgeos.Popups on the session bus. Each call that
// shows something waits until it's closed and returns what was picked.
// `forge-dialog` (a script) is the same thing for everyone else.
import 'dart:convert';

import 'package:dbus/dbus.dart';

const popupsName = 'org.forgeos.Popups';
const popupsPath = '/org/forgeos/Popups';

/// One line of a menu.
class MenuItem {
  const MenuItem(
    this.id,
    this.label, {
    this.icon,
    this.danger = false,
    this.enabled = true,
    this.checked,
    this.hint,
  }) : separator = false;

  const MenuItem.separator()
    : id = '',
      label = '',
      icon = null,
      danger = false,
      enabled = false,
      checked = null,
      hint = null,
      separator = true;

  final String id;
  final String label;

  /// A name from popups/icons.dart ("pin", "close", "terminal"...).
  final String? icon;
  final bool danger;
  final bool enabled;
  final bool? checked;

  /// Greyed text on the right: a shortcut, a count.
  final String? hint;
  final bool separator;

  Map<String, Object?> toJson() => separator
      ? {'separator': true}
      : {
          'id': id,
          'label': label,
          'icon': ?icon,
          'danger': danger,
          'enabled': enabled,
          'checked': ?checked,
          'hint': ?hint,
        };
}

class Popups {
  Popups() : _client = DBusClient.session();

  final DBusClient _client;
  late final _object = DBusRemoteObject(
    _client,
    name: popupsName,
    path: DBusObjectPath(popupsPath),
  );

  Future<String> _call(String method, [String? arg]) async {
    try {
      final reply = await _object.callMethod(
        popupsName,
        method,
        [if (arg != null) DBusString(arg)],
        replySignature: DBusSignature(
          method == 'Menu' || method == 'Dialog' ? 's' : '',
        ),
      );
      return reply.values.isEmpty ? '' : reply.values.first.asString();
    } catch (_) {
      return ''; // the popups part isn't running (yet)
    }
  }

  Future<void> startMenu() => _call('StartMenu');

  Future<void> calendar() => _call('Calendar');

  /// '' for the power choices, or 'shutdown', 'restart', 'logout' to ask.
  Future<void> power([String what = '']) => _call('Power', what);

  Future<void> wallpapers() => _call('Wallpapers');

  /// A menu at a point on the screen (logical pixels), opening downwards,
  /// or upwards from it with [above]. The picked item's id, or ''.
  Future<String> menu({
    required double x,
    required double y,
    required List<MenuItem> items,
    String? title,
    bool above = false,
  }) => _call(
    'Menu',
    jsonEncode({
      'x': x,
      'y': y,
      'above': above,
      'title': ?title,
      'items': [for (final i in items) i.toJson()],
    }),
  );
}
