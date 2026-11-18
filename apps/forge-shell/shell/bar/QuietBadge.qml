// Do not disturb is on.
import QtQuick
import QtQuick.Layouts
import qs.services
import qs.widgets

HoverButton {
    visible: Forged.dnd.enabled === true
    Layout.preferredWidth: 30
    Layout.fillHeight: true
    Layout.margins: 3
    radius: height / 2
    onClicked: Forged.set("dnd", "off")
    Icon { anchors.centerIn: parent; text: Icons.bellOff; size: 16; color: Theme.accent }
}
