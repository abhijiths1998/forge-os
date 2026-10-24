// A top-bar icon that opens a popup under it, in Plasma's applet-popup
// style (the same frosted panel as the tray's popups). Wi-Fi, Bluetooth and
// Sound use it; the popup's content is `popup`.
import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore

MouseArea {
    id: button

    property alias iconSource: icon.source
    /// The popup's content.
    property Item popup
    /// The applet's location (Plasmoid.location), so the popup opens away from the bar.
    property int location: PlasmaCore.Types.TopEdge
    property bool vertical: false
    readonly property alias expanded: dialog.visible

    function close() { dialog.visible = false; }

    // Square, as tall as the bar, like the tray's icons were.
    Layout.minimumWidth: vertical ? Kirigami.Units.iconSizes.small : height
    Layout.maximumWidth: Layout.minimumWidth
    Layout.minimumHeight: vertical ? width : Kirigami.Units.iconSizes.small
    Layout.maximumHeight: Layout.minimumHeight
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
    onClicked: mouse => {
        if (mouse.button === Qt.LeftButton) dialog.visible = !dialog.visible;
    }

    Kirigami.Icon {
        id: icon
        anchors.centerIn: parent
        width: Kirigami.Units.iconSizes.small
        height: width
        active: button.containsMouse || dialog.visible
    }

    PlasmaCore.Dialog {
        id: dialog
        visualParent: button
        location: button.location
        type: PlasmaCore.Dialog.AppletPopup
        hideOnWindowDeactivate: true
        mainItem: button.popup
    }
}
