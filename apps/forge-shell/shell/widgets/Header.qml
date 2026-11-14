// A popup's header: a title and a switch.
import QtQuick
import QtQuick.Layouts
import qs.services

RowLayout {
    property alias title: label.text
    property bool on: false
    property bool showSwitch: true
    signal switched()
    width: parent ? parent.width : 280

    Label { id: label; Layout.fillWidth: true; size: 15; font.weight: Font.Bold }
    Rectangle {
        visible: parent.showSwitch
        implicitWidth: 40
        implicitHeight: 22
        radius: 11
        color: parent.on ? Theme.accent : Theme.faint
        Behavior on color { ColorAnimation { duration: 140 } }
        Rectangle {
            width: 16; height: 16; radius: 8
            y: 3
            x: parent.parent.on ? parent.width - width - 3 : 3
            color: parent.parent.on ? Theme.onAccent : Theme.text
            Behavior on x { NumberAnimation { duration: 140 } }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: parent.parent.switched() }
    }
}
