// Forge Control's button in the top bar: the two-switch icon; a click
// toggles the panel (forge-control, which is already running hidden, so it
// opens at once).
import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as P5Support
import org.kde.plasma.plasmoid

PlasmoidItem {
    id: root

    // A button, not a popup: the panel is its own window.
    preferredRepresentation: fullRepresentation
    toolTipMainText: i18n("Control Center")
    toolTipSubText: i18n("Wi-Fi, Bluetooth, sound, brightness and power")

    fullRepresentation: MouseArea {
        // Square, as tall as the bar, like the tray's icons.
        readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
        Layout.minimumWidth: vertical ? Kirigami.Units.iconSizes.small : height
        Layout.maximumWidth: Layout.minimumWidth
        Layout.minimumHeight: vertical ? width : Kirigami.Units.iconSizes.small
        Layout.maximumHeight: Layout.minimumHeight
        hoverEnabled: true
        onClicked: runner.connectSource("forge-control")

        Kirigami.Icon {
            anchors.fill: parent
            source: Qt.resolvedUrl("../icons/forge-control.svg")
            isMask: true
            active: parent.containsMouse
        }
    }

    P5Support.DataSource {
        id: runner
        engine: "executable"
        onNewData: source => disconnectSource(source)
    }
}
