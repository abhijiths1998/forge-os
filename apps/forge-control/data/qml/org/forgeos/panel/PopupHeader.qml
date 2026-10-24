// A popup's head: an icon in an accent bubble, a title and the state under
// it, and optionally a switch on the right (Wi-Fi, Bluetooth).
import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami

RowLayout {
    id: header

    property alias iconSource: icon.source
    property string title
    property string subtitle
    property bool on: true
    property bool showSwitch: false
    signal toggled(bool checked)

    readonly property color ink: Kirigami.Theme.textColor

    Layout.fillWidth: true
    Layout.topMargin: Kirigami.Units.smallSpacing
    spacing: Kirigami.Units.largeSpacing

    Rectangle {
        implicitWidth: 38
        implicitHeight: 38
        radius: width / 2
        color: header.on ? Kirigami.Theme.highlightColor
                         : Qt.rgba(header.ink.r, header.ink.g, header.ink.b, 0.12)
        Behavior on color { ColorAnimation { duration: 140 } }

        Kirigami.Icon {
            id: icon
            anchors.centerIn: parent
            width: 20
            height: 20
            color: header.on ? "white" : header.ink
            isMask: true
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 0
        Text {
            text: header.title
            color: header.ink
            font.pixelSize: 16
            font.weight: Font.DemiBold
        }
        Text {
            Layout.fillWidth: true
            visible: text.length > 0
            text: header.subtitle
            elide: Text.ElideRight
            color: Qt.rgba(header.ink.r, header.ink.g, header.ink.b, 0.6)
            font.pixelSize: 12
        }
    }

    ForgeSwitch {
        visible: header.showSwitch
        checked: header.on
        onToggled: checked => header.toggled(checked)
    }
}
