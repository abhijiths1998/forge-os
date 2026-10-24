// forged from QML: the desktop's state (live, through forged's Changed
// signal) and its switches. D-Bus starts forged on the first call.
//
// Calls go without a signature: with one, Plasma's D-Bus module sends no
// arguments at all. Replies come wrapped (String() unwraps them).
import QtQuick

import org.kde.plasma.workspace.dbus as DBus

Item {
    id: forged

    property var state: ({})

    function part(name) {
        return state[name] || {};
    }

    function _call(member, args, done) {
        DBus.SessionBus.asyncCall({
            service: "org.forgeos.Forged",
            path: "/org/forgeos/Forged",
            iface: "org.forgeos.Forged",
            member: member,
            arguments: args,
        }, reply => done && done(String(reply.value), ""),
           failed => done && done("", (failed.error && failed.error.message) || "forged isn't answering"));
    }

    function refresh() {
        _call("State", [], (value, error) => { if (!error) forged.state = JSON.parse(value); });
    }

    /// Changes one thing (forged set); done(error or "").
    function set(key, value, done) {
        _call("Set", [key, String(value)], (value, error) => done && done(error || value));
    }

    /// A slow action (forged do), answered once it's finished; done(error or "").
    function act(action, arg, extra, done) {
        _call("Do", [action, arg || "", extra || ""], (value, error) => done && done(error || value));
    }

    DBus.SignalWatcher {
        busType: DBus.BusType.Session
        service: "org.forgeos.Forged"
        path: "/org/forgeos/Forged"
        iface: "org.forgeos.Forged"

        // Called by name for forged's Changed signal.
        function dbusChanged(state) {
            forged.state = JSON.parse(state);
        }
    }

    Component.onCompleted: refresh()
}
