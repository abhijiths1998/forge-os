// The battery, macOS-style, the percentage inside it; a click shows its
// details. Hidden on machines without one.
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import qs.services
import qs.widgets

HoverButton {
    id: button
    readonly property var dev: UPower.displayDevice
    readonly property int percent: Math.round(dev ? dev.percentage * (dev.percentage <= 1 ? 100 : 1) : 0)
    readonly property bool charging: dev && (dev.state === UPowerDeviceState.Charging || dev.state === UPowerDeviceState.FullyCharged)
    readonly property bool plugged: !UPower.onBattery
    readonly property bool low: percent <= 20 && !plugged

    visible: dev && dev.isLaptopBattery
    Layout.preferredWidth: icon.implicitWidth + 16
    Layout.fillHeight: true
    Layout.margins: 3
    radius: height / 2
    onClicked: popup.visible = !popup.visible

    BatteryIcon {
        id: icon
        anchors.centerIn: parent
        percent: button.percent
        charging: button.charging
        bodyHeight: 13
        ink: Theme.text
        fillColor: button.low ? Theme.danger : (button.plugged ? Theme.good : Theme.text)
    }

    BarPopup {
        id: popup
        button: button
        contentWidth: 280
        Row {
            spacing: 12
            BatteryIcon {
                anchors.verticalCenter: parent.verticalCenter
                percent: button.percent
                charging: button.charging
                bodyHeight: 22
                ink: Theme.text
                fillColor: button.low ? Theme.danger : (button.plugged ? Theme.good : Theme.text)
            }
            Column {
                Label { text: button.percent + "%"; size: 22; font.weight: Font.Bold }
                Label {
                    dim: true
                    text: {
                        const d = button.dev;
                        if (!d) return "";
                        if (d.state === UPowerDeviceState.FullyCharged) return "Fully charged";
                        if (d.state === UPowerDeviceState.Charging)
                            return d.timeToFull > 0 ? "Charging, full in " + fmt(d.timeToFull) : "Charging";
                        if (button.plugged) return "Plugged in, not charging";
                        return d.timeToEmpty > 0 ? fmt(d.timeToEmpty) + " left" : "On battery";
                    }
                    function fmt(s) { const m = Math.round(s / 60); return Math.floor(m / 60) + " h " + (m % 60) + " min"; }
                }
            }
        }
        Label {
            visible: text !== ""
            dim: true
            size: 12
            width: parent.width
            text: {
                const parts = [];
                const bat = UPower.devices.values.find(d => d.isLaptopBattery);
                if (bat && bat.healthSupported) parts.push("Health " + Math.round(bat.healthPercentage) + "%");
                if (bat && bat.model) parts.push(bat.model);
                return parts.join("  ·  ");
            }
        }
        Label {
            dim: true
            size: 12
            text: "Power: " + (Forged.power.profile || "balanced") + "  ·  Cooling: " + (Forged.thermal.profile || "—")
        }
    }
}
