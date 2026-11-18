// One or more key combinations: [["Super","E"], ["Alt","F4"]] as keycaps,
// "+" between keys and "or" between combinations.
import QtQuick
import qs.services

Row {
    id: combo
    property var combos: []
    property real size: 12
    spacing: 4

    Repeater {
        model: combo.combos
        Row {
            required property var modelData
            required property int index
            spacing: 4
            Text {
                visible: index > 0
                anchors.verticalCenter: parent.verticalCenter
                text: "or"
                color: Theme.subtext
                font.family: Theme.font
                font.pixelSize: combo.size - 1
            }
            Repeater {
                model: modelData
                Row {
                    required property string modelData
                    required property int index
                    spacing: 3
                    Text {
                        visible: index > 0
                        anchors.verticalCenter: parent.verticalCenter
                        text: "+"
                        color: Theme.subtext
                        font.pixelSize: combo.size - 1
                    }
                    KeyCap { text: modelData; size: combo.size }
                }
            }
        }
    }
}
