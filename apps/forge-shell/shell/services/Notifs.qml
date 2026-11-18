pragma Singleton
// Forge's notification server. Every notification is kept for the
// notification centre (Super+N) until it's dismissed; pop-ups show for a
// few seconds, and not at all while do not disturb is on (forged holds that
// switch), except urgent ones.
import QtQuick
import Quickshell
import Quickshell.Services.Notifications

Singleton {
    id: root

    readonly property var history: server.trackedNotifications.values.slice().reverse()
    property var popups: []          // notifications showing as pop-ups now
    readonly property bool quiet: Forged.dnd.enabled === true

    function dismissAll() {
        for (const n of server.trackedNotifications.values.slice()) n.dismiss();
    }
    function hidePopup(n) { popups = popups.filter(p => p !== n); }

    NotificationServer {
        id: server
        keepOnReload: true
        actionsSupported: true
        actionIconsSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        imageSupported: true
        persistenceSupported: true

        onNotification: n => {
            n.tracked = true;
            if (!root.quiet || n.urgency === NotificationUrgency.Critical)
                root.popups = [n].concat(root.popups).slice(0, 4);
            n.closed.connect(() => root.hidePopup(n));
        }
    }
}
