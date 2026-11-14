// A row of choices, one picked: power and cooling profiles.
import QtQuick
import QtQuick.Layouts
import qs.services

ColumnLayout {
    id: seg
    property string title
    property var options: []
    property var labels: ({})
    property string current
    signal picked(string value)
    spacing: 6

    Label { text: seg.title; dim: true; size: 12 }
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 34
        radius: 17
        color: Theme.faint
        RowLayout {
            anchors.fill: parent
            anchors.margins: 3
            spacing: 2
            Repeater {
                model: seg.options
                HoverButton {
                    required property string modelData
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: height / 2
                    active: modelData === seg.current
                    onClicked: seg.picked(modelData)
                    Label {
                        anchors.centerIn: parent
                        text: seg.labels[modelData] || modelData
                        size: 12
                        font.weight: Font.DemiBold
                        color: parent.active ? Theme.onAccent : Theme.text
                    }
                }
            }
        }
    }
}
