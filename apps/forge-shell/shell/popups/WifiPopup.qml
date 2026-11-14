// Wi-Fi: on/off, nearby networks (known first, then by strength); a click
// joins one, asking for the password when it needs one.
import QtQuick
import QtQuick.Controls
import qs.services
import qs.widgets

BarPopup {
    id: popup
    contentWidth: 330
    readonly property var w: Forged.wifi
    property string asking: ""      // SSID we need a password for
    property string error: ""

    onVisibleChanged: if (visible) { asking = ""; error = ""; Forged.run("wifi-rescan"); }

    Header {
        title: "Wi-Fi"
        on: popup.w.enabled === true
        onSwitched: Forged.set("wifi", popup.w.enabled ? "off" : "on")
    }
    Label {
        visible: popup.w.wired === true
        dim: true
        size: 12
        text: "Connected by cable"
    }
    Repeater {
        model: popup.w.enabled ? (popup.w.networks || []) : []
        ListRow {
            required property var modelData
            icon: Icons.wifi[Math.max(1, Math.min(4, Math.ceil(modelData.signal / 25)))]
            title: modelData.ssid
            detail: modelData.active ? "Connected" : (modelData.known ? "Saved" : (modelData.secure ? "Secured" : "Open"))
            current: modelData.active
            busy: popup.w.busy === modelData.ssid
            onClicked: {
                popup.error = "";
                if (modelData.active) { Forged.run("wifi-disconnect"); return; }
                Forged.run("wifi-connect", modelData.ssid, "", err => {
                    if (err === "needs-password") popup.asking = modelData.ssid;
                    else if (err) popup.error = err;
                });
            }
        }
    }
    Column {
        visible: popup.asking !== ""
        width: parent.width
        spacing: 6
        Label { text: "Password for " + popup.asking; size: 12; dim: true }
        TextField {
            id: password
            width: parent.width
            echoMode: TextInput.Password
            placeholderText: "Password"
            color: Theme.text
            font.family: Theme.font
            background: Rectangle { radius: 10; color: Theme.faint; border.color: Theme.accent; border.width: password.activeFocus ? 1 : 0 }
            onAccepted: {
                const ssid = popup.asking;
                popup.asking = "";
                Forged.run("wifi-connect", ssid, text, err => { if (err) popup.error = err; });
                text = "";
            }
        }
    }
    Label { visible: popup.error !== ""; text: popup.error; color: Theme.danger; size: 12; width: parent.width; wrapMode: Text.Wrap }
    ListRow {
        icon: Icons.settings
        title: "Network settings…"
        onClicked: { popup.visible = false; Quickshell.execDetached(["nm-connection-editor"]); }
    }
}
