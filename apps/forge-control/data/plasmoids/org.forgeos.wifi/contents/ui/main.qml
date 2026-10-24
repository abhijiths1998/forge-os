// Forge Wi-Fi: the top bar's Wi-Fi icon (signal strength, off, wired) and
// its popup (WifiPopup.qml): the switch, nearby networks, joining one. The
// state and the actions are forged's (org.forgeos.panel's Forged).
import QtQuick

import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as P5Support
import org.kde.plasma.plasmoid
import org.forgeos.panel

PlasmoidItem {
    id: root

    readonly property var wifi: forged.part("wifi")
    readonly property string icon: {
        if (wifi.wired && !wifi.ssid) return "network-wired-symbolic";
        if (!wifi.enabled) return "network-wireless-offline-symbolic";
        if (!wifi.ssid) return "network-wireless-disconnected-symbolic";
        const s = wifi.signal || 0;
        return "network-wireless-signal-" + (s >= 80 ? "excellent" : s >= 55 ? "good" : s >= 30 ? "ok" : s > 5 ? "weak" : "none") + "-symbolic";
    }

    preferredRepresentation: fullRepresentation
    toolTipMainText: i18n("Wi-Fi")
    toolTipSubText: !wifi.enabled ? i18n("Off") : wifi.ssid ? i18n("Connected to %1", wifi.ssid)
                  : wifi.wired ? i18n("Wired") : i18n("Not connected")

    Forged { id: forged }

    P5Support.DataSource {
        id: runner
        engine: "executable"
        onNewData: source => disconnectSource(source)
    }

    fullRepresentation: BarButton {
        id: button
        iconSource: root.icon
        location: Plasmoid.location
        vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
        popup: WifiPopup {
            forged: forged
            onSettingsRequested: {
                button.close();
                runner.connectSource("systemsettings kcm_networkmanagement");
            }
        }
    }
}
