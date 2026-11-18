// A key, drawn like a keycap: "Super", "E", "PrtSc".
import QtQuick
import qs.services

Rectangle {
    property alias text: label.text
    property real size: 12
    implicitWidth: Math.max(implicitHeight, label.implicitWidth + 12)
    implicitHeight: size + 12
    radius: 6
    color: Theme.faint
    border.width: 1
    border.color: Theme.alpha(Theme.text, 0.16)

    Text {
        id: label
        anchors.centerIn: parent
        color: Theme.text
        font.family: Theme.font
        font.pixelSize: parent.size
        font.weight: Font.DemiBold
    }
}
