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
        color: parent.activeFocus ? "#B3FFFFFF" : "#66FFFFFF"
        border.color: parent.activeFocus ? root.accent : "#99FFFFFF"
        border.width: parent.activeFocus ? 1.5 : 1
        Behavior on color { ColorAnimation { duration: 150 } }
    }
}
