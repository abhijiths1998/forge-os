// Forge Battery: the top bar's battery, macOS-style (BatteryIcon.qml), with
// the percentage inside it, beside it or hidden. Green while plugged in, red
// at 20% and below, a bolt while charging. A click opens a popup
// (BatteryPopup.qml) with the details and the choice of style. Takes no
// space on machines without a battery.
//
// Data: Plasma's powermanagement engine (PowerDevil): "Battery" (Has
// Battery, Percent, State, Smoothed Remaining msec), "AC Adapter" (Plugged
// in) and "Battery0" (Capacity, i.e. health; Vendor; Product).
import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as P5Support
import org.kde.plasma.plasmoid

PlasmoidItem {
    id: root

    readonly property var battery: pm.data["Battery"] || {}
    readonly property var cell: pm.data["Battery0"] || {}
    readonly property bool present: battery["Has Battery"] === true
    readonly property int percent: battery["Percent"] || 0
    readonly property string batteryState: battery["State"] || ""
    readonly property bool charging: batteryState === "Charging"
    readonly property bool pluggedIn: (pm.data["AC Adapter"] || {})["Plugged in"] === true
    readonly property bool low: percent <= 20 && !pluggedIn
    readonly property int minutesLeft: Math.round((battery["Smoothed Remaining msec"] || 0) / 60000)
    readonly property string mode: Plasmoid.configuration.percentage || "inside"

    readonly property string status: {
        if (batteryState === "FullyCharged") return i18n("Fully charged");
        if (charging) return i18n("Charging");
        if (pluggedIn) return i18n("Plugged in, not charging");
        if (minutesLeft > 0)
            return i18n("%1 h %2 min left", Math.floor(minutesLeft / 60), minutesLeft % 60);
        return i18n("On battery");
    }
    readonly property string details: {
        const parts = [];
        if (cell["Capacity"]) parts.push(i18n("Health %1%", cell["Capacity"]));
        const model = [cell["Vendor"], cell["Product"]].filter(s => s).join(" ");
        if (model) parts.push(model);
        return parts.join("  ·  ");
    }

    // A button, not Plasma's own popup: the popup below is ours.
    preferredRepresentation: fullRepresentation
    toolTipMainText: i18n("Battery %1%", percent)
    toolTipSubText: status

    P5Support.DataSource {
        id: pm
        engine: "powermanagement"
        connectedSources: ["Battery", "AC Adapter", "Battery0"]
    }

    P5Support.DataSource {
        id: runner
        engine: "executable"
        onNewData: source => disconnectSource(source)
    }

    fullRepresentation: MouseArea {
        id: button

        readonly property color ink: Kirigami.Theme.textColor
        readonly property color fillColor: root.low ? Kirigami.Theme.negativeTextColor
            : root.pluggedIn ? Kirigami.Theme.positiveTextColor : ink
        // The battery: about 55% of the bar's height.
        readonly property real bodyHeight: Math.round(Math.max(11, height * 0.56))

        visible: root.present
        Layout.minimumWidth: root.present ? row.implicitWidth + Kirigami.Units.smallSpacing * 2 : 0
        Layout.maximumWidth: Layout.minimumWidth
        Layout.fillHeight: true
        hoverEnabled: true
        onClicked: popup.visible = !popup.visible

        Row {
            id: row
            anchors.centerIn: parent
            spacing: Math.round(button.bodyHeight * 0.3)

            Text {
                visible: root.mode === "beside"
                anchors.verticalCenter: parent.verticalCenter
                text: root.percent + "%"
                color: button.ink
                font.pixelSize: Math.round(button.bodyHeight * 0.95)
                font.weight: Font.DemiBold
                font.features: { "tnum": 1 }
            }
            BatteryIcon {
                anchors.verticalCenter: parent.verticalCenter
                percent: root.percent
                charging: root.charging
                digits: root.mode === "inside"
                ink: button.ink
                fillColor: button.fillColor
                bodyHeight: button.bodyHeight
                opacity: button.containsMouse || popup.visible ? 1 : 0.92
            }
        }

        PlasmaCore.Dialog {
            id: popup
            visualParent: button
            location: Plasmoid.location
            type: PlasmaCore.Dialog.AppletPopup
            hideOnWindowDeactivate: true

            mainItem: BatteryPopup {
                percent: root.percent
                charging: root.charging
                status: root.status
                details: root.details
                mode: root.mode
                fillColor: button.fillColor
                onModeChosen: chosen => Plasmoid.configuration.percentage = chosen
                onSettingsRequested: {
                    popup.visible = false;
                    runner.connectSource("systemsettings kcm_powerdevilprofilesconfig");
                }

                Keys.onEscapePressed: popup.visible = false
            }
        }
    }
}
