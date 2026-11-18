// A wide, rounded slider with an icon, Control Center style.
import QtQuick
import qs.services

Item {
    id: slider
    property string icon
    property real value: 0          // 0-1
    property bool available: true
    signal moved(real value)
    signal iconClicked()

    implicitHeight: 36
    opacity: available ? 1 : 0.45

    Rectangle {
        id: track
        anchors.fill: parent
        radius: height / 2
        color: Theme.faint
        clip: true

        Rectangle {
            width: Math.max(track.height, track.width * Math.max(0, Math.min(1, slider.value)))
            height: parent.height
            radius: height / 2
            color: Theme.accent
            Behavior on width { enabled: !drag.pressed; NumberAnimation { duration: 140 } }
        }
    }
    MouseArea {
        id: drag
        anchors.fill: parent
        enabled: slider.available
        cursorShape: Qt.PointingHandCursor
        function at(x) { return Math.max(0, Math.min(1, x / width)); }
        onPressed: e => slider.moved(at(e.x))
        onPositionChanged: e => { if (pressed) slider.moved(at(e.x)); }
        onWheel: w => slider.moved(Math.max(0, Math.min(1, slider.value + (w.angleDelta.y > 0 ? 0.05 : -0.05))))
    }
    HoverButton {
        x: 4
        width: track.height - 8
        height: track.height - 8
        anchors.verticalCenter: parent.verticalCenter
        radius: height / 2
        onClicked: slider.iconClicked()
        Icon {
            anchors.centerIn: parent
            text: slider.icon
            size: 17
            color: slider.value > 0.06 ? Theme.onAccent : Theme.text
        }
    }
}
