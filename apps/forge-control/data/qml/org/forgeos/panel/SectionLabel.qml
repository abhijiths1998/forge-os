// A small upper-case heading over a part of a popup, with room on the right
// for a small action (Wi-Fi's rescan).
import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami

RowLayout {
    id: label

    property string text
    default property alias actions: actionsRow.data

    Layout.fillWidth: true
    Layout.leftMargin: Kirigami.Units.smallSpacing
    Layout.topMargin: Kirigami.Units.smallSpacing

    Text {
        Layout.fillWidth: true
        text: label.text.toUpperCase()
        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.6)
        font.pixelSize: 11
        font.weight: Font.DemiBold
        font.letterSpacing: 0.8
    }
    Row { id: actionsRow }
}
