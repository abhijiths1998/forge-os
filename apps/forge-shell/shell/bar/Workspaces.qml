// Workspaces on this screen: a dot each, the active one a wide pill in the
// accent colour; a click goes there, the wheel steps through them.
import QtQuick
import Quickshell.Hyprland
import qs.services

Row {
    id: row
    property string screenName
    spacing: 5
    leftPadding: 4
    rightPadding: 4

    Repeater {
        model: Hyprland.workspaces.values.filter(w => w.id > 0 && (!w.monitor || w.monitor.name === row.screenName))
        delegate: Rectangle {
            required property var modelData
            readonly property bool current: modelData.active
            anchors.verticalCenter: parent.verticalCenter
            width: current ? 26 : (mouse.containsMouse ? 12 : 9)
            height: 9
            radius: 4.5
            color: current ? Theme.accent : (modelData.urgent ? Theme.danger : Theme.alpha(Theme.text, mouse.containsMouse ? 0.6 : 0.35))
            Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: 140 } }
            MouseArea {
                id: mouse
                anchors.fill: parent
                anchors.margins: -5
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: modelData.activate()
            }
        }
    }
    WheelHandler {
        onWheel: e => Hyprland.dispatch(`hl.dsp.focus({ workspace = "${e.angleDelta.y > 0 ? "e-1" : "e+1"}" })`)
    }
}
