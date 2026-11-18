// Sound: the level and the output it plays through.
import QtQuick
import qs.services
import qs.widgets

BarPopup {
    id: popup
    readonly property var v: Forged.volume

    Header {
        title: "Sound"
        on: !popup.v.muted
        onSwitched: Forged.set("volume", "toggle")
    }
    Slider {
        width: parent.width
        icon: popup.v.muted ? Icons.volumeMute : Icons.volume[2]
        value: (popup.v.level || 0) / 100
        onMoved: x => Forged.set("volume", Math.round(x * 100))
        onIconClicked: Forged.set("volume", "toggle")
    }
    Label { text: "Output"; dim: true; size: 12; topPadding: 4 }
    Repeater {
        model: popup.v.outputs || []
        ListRow {
            required property var modelData
            icon: ({ headphones: Icons.headphones, bluetooth: Icons.bluetooth, hdmi: Icons.hdmi, usb: Icons.usb })[modelData.kind] || Icons.speaker
            title: modelData.label
            current: modelData.default
            onClicked: Forged.set("output", modelData.name)
        }
    }
}
