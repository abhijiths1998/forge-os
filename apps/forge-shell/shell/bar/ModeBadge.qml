// Shows the mode Hyprland is in (resize, move) while it's in one.
import QtQuick
import QtQuick.Layouts
import qs.services
import qs.widgets

Rectangle {
    visible: Shell.submap !== ""
    Layout.preferredHeight: 24
    Layout.preferredWidth: label.implicitWidth + 20
    radius: 12
    color: Theme.accent
    Label {
        id: label
        anchors.centerIn: parent
        text: Shell.submap.charAt(0).toUpperCase() + Shell.submap.slice(1) + " mode · Esc"
        color: Theme.onAccent
        font.weight: Font.DemiBold
        size: 12
    }
}
