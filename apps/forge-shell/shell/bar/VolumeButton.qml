// Sound: the level in the bar (the wheel changes it, a middle click
// mutes); the popup has the slider and the outputs.
import QtQuick
import QtQuick.Layouts
import qs.services
import qs.widgets
import qs.popups

HoverButton {
    id: button
    readonly property var v: Forged.volume
    visible: v.available === true
    Layout.preferredWidth: 30
    Layout.fillHeight: true
    Layout.margins: 3
    radius: height / 2
    onClicked: e => {
        if (e.button === Qt.MiddleButton) Forged.set("volume", "toggle");
        else popup.visible = !popup.visible;
    }
    onWheel: w => Forged.set("volume", w.angleDelta.y > 0 ? "+5" : "-5")
    Icon {
        anchors.centerIn: parent
        size: 17
        text: button.v.muted || button.v.level === 0 ? Icons.volumeMute
            : Icons.volume[Math.min(2, Math.floor((button.v.level || 0) / 34))]
    }
    VolumePopup { id: popup; button: button }
}
