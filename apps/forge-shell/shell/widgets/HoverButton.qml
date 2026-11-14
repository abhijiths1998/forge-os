// Something you can click, with a soft highlight under the pointer.
import QtQuick
import qs.services

MouseArea {
    id: area
    property bool active: false
    property real radius: Theme.radius - 4
    property color activeColour: Theme.accent
    default property alias content: holder.data

    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

    Rectangle {
        anchors.fill: parent
        radius: area.radius
        color: area.active ? area.activeColour : (area.containsMouse ? Theme.hover : "transparent")
        Behavior on color { ColorAnimation { duration: 120 } }
    }
    Item {
        id: holder
        anchors.fill: parent
    }
}
