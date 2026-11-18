// A Control Center tile: icon, name, state; click to switch it, the arrow
// (when there's more) to open its details.
import QtQuick
import QtQuick.Layouts
import qs.services

Rectangle {
    id: tile
    property string icon
    property string title
    property string detail
    property bool on: false
    property bool available: true
    property bool more: false
    signal toggled()
    signal expanded()

    implicitHeight: 58
    radius: Theme.radius - 2
    color: on ? Theme.accent : (mouse.containsMouse ? Theme.hover : Theme.faint)
    opacity: available ? 1 : 0.45
    Behavior on color { ColorAnimation { duration: 140 } }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: tile.available
        cursorShape: Qt.PointingHandCursor
        onClicked: tile.toggled()
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: tile.more ? 4 : 12
        spacing: 10
        Icon {
            text: tile.icon
            size: 19
            color: tile.on ? Theme.onAccent : Theme.text
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            Label {
                Layout.fillWidth: true
                text: tile.title
                font.weight: Font.DemiBold
                color: tile.on ? Theme.onAccent : Theme.text
            }
            Label {
                Layout.fillWidth: true
                visible: text !== ""
                text: tile.detail
                size: 11
                color: tile.on ? Theme.alpha(Theme.onAccent, 0.75) : Theme.subtext
            }
        }
        HoverButton {
            visible: tile.more
            Layout.preferredWidth: 26
            Layout.preferredHeight: 40
            radius: 8
            onClicked: tile.expanded()
            Icon {
                anchors.centerIn: parent
                text: Icons.chevronRight
                color: tile.on ? Theme.onAccent : Theme.text
            }
        }
    }
}
