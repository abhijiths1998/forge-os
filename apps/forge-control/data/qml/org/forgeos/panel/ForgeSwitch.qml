// An on/off switch: a pill with a sliding knob, the accent when on.
import QtQuick

import org.kde.kirigami as Kirigami

Item {
    id: toggle

    property bool checked: false
    signal toggled(bool checked)

    readonly property color ink: Kirigami.Theme.textColor

    implicitWidth: 40
    implicitHeight: 24
    opacity: enabled ? 1 : 0.5

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: toggle.checked ? Kirigami.Theme.highlightColor
                              : Qt.rgba(toggle.ink.r, toggle.ink.g, toggle.ink.b, 0.18)
        Behavior on color { ColorAnimation { duration: 140 } }

        Rectangle {
            width: parent.height - 4
            height: width
            radius: width / 2
            y: 2
            x: toggle.checked ? parent.width - width - 2 : 2
            color: "white"
            Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        }
    }

    HoverHandler { cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: toggle.toggled(!toggle.checked) }
}
