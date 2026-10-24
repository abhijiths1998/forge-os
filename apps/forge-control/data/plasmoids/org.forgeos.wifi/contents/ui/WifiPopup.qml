// Forge Wi-Fi's popup: the switch and the network in use, then the networks
// around, strongest and saved first. A click joins a saved or open network;
// a locked one asks for its password in place. The network in use can be
// left from its row.
import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.forgeos.panel

ColumnLayout {
    id: popup

    required property Forged forged
    signal settingsRequested()

    readonly property var wifi: forged.part("wifi")
    readonly property var networks: wifi.networks || []
    /// The network whose password field is open.
    property string asking: ""
    property string error: ""
    property bool scanning: false

    function signalIcon(s) {
        return "network-wireless-signal-" + (s >= 80 ? "excellent" : s >= 55 ? "good" : s >= 30 ? "ok" : s > 5 ? "weak" : "none") + "-symbolic";
    }

    function join(network, password) {
        popup.error = "";
        forged.act("wifi-connect", network.ssid, password || "", error => {
            if (error === "needs-password") {
                popup.asking = network.ssid;
            } else if (error) {
                popup.asking = network.secure ? network.ssid : "";
                popup.error = error;
            } else {
                popup.asking = "";
            }
        });
    }

    width: Kirigami.Units.gridUnit * 18
    spacing: Kirigami.Units.smallSpacing

    PopupHeader {
        iconSource: "network-wireless-signal-excellent-symbolic"
        title: i18n("Wi-Fi")
        subtitle: !popup.wifi.enabled ? i18n("Off")
                : popup.wifi.ssid ? i18n("Connected to %1", popup.wifi.ssid)
                : popup.wifi.busy ? i18n("Joining %1…", popup.wifi.busy)
                : i18n("Not connected")
        on: popup.wifi.enabled === true
        showSwitch: popup.wifi.available === true
        onToggled: checked => popup.forged.set("wifi", checked ? "on" : "off")
    }

    SectionLabel {
        visible: popup.wifi.enabled === true
        text: i18n("Networks")

        Kirigami.Icon {
            width: 16
            height: 16
            source: "view-refresh-symbolic"
            color: Kirigami.Theme.textColor
            isMask: true
            opacity: refreshHover.hovered ? 1 : 0.6
            RotationAnimation on rotation {
                running: popup.scanning
                from: 0; to: 360; duration: 900; loops: Animation.Infinite
                onRunningChanged: if (!running) parent.rotation = 0
            }
            HoverHandler { id: refreshHover; cursorShape: Qt.PointingHandCursor }
            TapHandler {
                onTapped: {
                    popup.scanning = true;
                    popup.forged.act("wifi-rescan", "", "", () => scanDone.restart());
                }
            }
            // Results trickle in for a few seconds after the scan starts.
            Timer { id: scanDone; interval: 3000; onTriggered: popup.scanning = false }
        }
    }

    PlasmaComponents.ScrollView {
        id: scroll
        visible: popup.wifi.enabled === true && popup.networks.length > 0
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(list.implicitHeight, Kirigami.Units.gridUnit * 16)

        ColumnLayout {
            id: list
            width: scroll.availableWidth
            spacing: 2

            Repeater {
                model: popup.networks

                delegate: ListRow {
                    id: networkRow
                    required property var modelData
                    readonly property bool joining: popup.wifi.busy === modelData.ssid

                    iconSource: popup.signalIcon(modelData.signal)
                    title: modelData.ssid
                    subtitle: modelData.active ? i18n("Connected")
                            : joining ? i18n("Joining…")
                            : modelData.known ? i18n("Saved")
                            : modelData.secure ? "" : i18n("Open network")
                    trailingIcon: modelData.secure ? "object-locked-symbolic" : ""
                    current: modelData.active
                    busy: joining
                    onClicked: {
                        if (modelData.active || joining) return;
                        if (modelData.secure && !modelData.known) {
                            popup.error = "";
                            popup.asking = popup.asking === modelData.ssid ? "" : modelData.ssid;
                        } else {
                            popup.join(modelData);
                        }
                    }

                    // The network in use: leave it.
                    Text {
                        visible: networkRow.modelData.active
                        Layout.alignment: Qt.AlignRight
                        text: i18n("Disconnect")
                        color: leaveHover.hovered ? Kirigami.Theme.textColor : Kirigami.Theme.highlightColor
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        HoverHandler { id: leaveHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: popup.forged.act("wifi-disconnect", "", "") }
                    }

                    // A locked network: its password, in place.
                    RowLayout {
                        visible: popup.asking === networkRow.modelData.ssid
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        PlasmaComponents.TextField {
                            id: password
                            Layout.fillWidth: true
                            echoMode: TextInput.Password
                            placeholderText: i18n("Password")
                            enabled: !networkRow.joining
                            onVisibleChanged: if (visible) { text = ""; forceActiveFocus(); }
                            onAccepted: if (text) popup.join(networkRow.modelData, text)
                            Keys.onEscapePressed: popup.asking = ""
                        }
                        PlasmaComponents.Button {
                            text: i18n("Join")
                            enabled: password.text.length > 0 && !networkRow.joining
                            onClicked: popup.join(networkRow.modelData, password.text)
                        }
                    }
                    Text {
                        visible: popup.asking === networkRow.modelData.ssid && popup.error.length > 0
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: popup.error
                        color: Kirigami.Theme.negativeTextColor
                        font.pixelSize: 11
                    }
                }
            }
        }
    }

    Text {
        visible: popup.wifi.enabled !== true || popup.networks.length === 0
        Layout.fillWidth: true
        Layout.margins: Kirigami.Units.largeSpacing
        horizontalAlignment: Text.AlignHCenter
        text: popup.wifi.available === false ? i18n("No Wi-Fi hardware is switched on.")
            : popup.wifi.enabled !== true ? i18n("Wi-Fi is off.")
            : i18n("Looking for networks…")
        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.6)
        font.pixelSize: 12
    }

    FooterLink {
        text: i18n("Network settings…")
        onClicked: popup.settingsRequested()
    }
}
