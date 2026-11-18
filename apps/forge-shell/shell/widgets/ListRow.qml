// A row in a popup list: icon, name, detail, and a busy spinner or a tick.
import QtQuick
import QtQuick.Layouts
import qs.services

HoverButton {
    id: row
    property string icon
    property string title
    property string detail
    property bool current: false
    property bool busy: false
    implicitHeight: 44
    width: parent ? parent.width : 280
    radius: 10

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        spacing: 10
        Icon { text: row.icon; size: 17; color: row.current ? Theme.accent : Theme.text }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            Label { Layout.fillWidth: true; text: row.title; font.weight: row.current ? Font.DemiBold : Font.Normal }
            Label { Layout.fillWidth: true; visible: text !== ""; text: row.detail; dim: true; size: 11 }
        }
        Icon {
            visible: row.busy
            text: Icons.restart
            size: 15
            color: Theme.subtext
            RotationAnimation on rotation { running: row.busy; from: 0; to: 360; duration: 900; loops: Animation.Infinite }
        }
        Icon { visible: row.current && !row.busy; text: Icons.check; size: 16; color: Theme.accent }
    }
}
