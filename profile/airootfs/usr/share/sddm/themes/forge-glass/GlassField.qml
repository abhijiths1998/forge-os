// A text field drawn as a lighter pane of glass on the login card.
import QtQuick
import QtQuick.Controls.Basic

TextField {
    height: 40 * root.u
    leftPadding: 14 * root.u
    font.family: config.font
    font.pixelSize: 14 * root.u
    color: root.ink
    placeholderTextColor: root.soft
    selectionColor: root.accent
    selectedTextColor: "white"
    passwordCharacter: "•"
    background: Rectangle {
        radius: 12 * root.u
        color: root.glass(parent.activeFocus ? 0.7 : 0.4)
        border.color: parent.activeFocus ? root.accent : root.glass(0.6)
        border.width: parent.activeFocus ? 1.5 : 1
        Behavior on color { ColorAnimation { duration: 150 } }
    }
}
