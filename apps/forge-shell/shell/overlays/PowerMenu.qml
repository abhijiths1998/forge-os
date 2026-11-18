// Ctrl+Alt+Delete: lock, log out, restart or shut down.
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.widgets

ShellOverlay {
    id: menu
    name: "power"
    property int selected: 0
    readonly property var choices: [
        { icon: Icons.lock, label: "Lock", cmd: ["loginctl", "lock-session"] },
        { icon: Icons.logout, label: "Log out", cmd: ["forge-logout"] },
        { icon: Icons.restart, label: "Restart", cmd: ["systemctl", "reboot"] },
        { icon: Icons.power, label: "Shut down", cmd: ["systemctl", "poweroff"] }
    ]
    onOpened: { selected = 0; row.forceActiveFocus(); }
    function pick(i) { Shell.close("power"); Quickshell.execDetached(choices[i].cmd); }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 18
        focus: true
        Keys.onLeftPressed: menu.selected = Math.max(0, menu.selected - 1)
        Keys.onRightPressed: menu.selected = Math.min(menu.choices.length - 1, menu.selected + 1)
        Keys.onReturnPressed: menu.pick(menu.selected)
        Keys.onEscapePressed: Shell.close("power")
        Repeater {
            model: menu.choices
            Glass {
                required property var modelData
                required property int index
                implicitWidth: 140
                implicitHeight: 140
                strong: true
                border.width: index === menu.selected ? 2 : 1
                border.color: index === menu.selected ? Theme.accent : Theme.edge
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: menu.selected = parent.index
                    onClicked: menu.pick(parent.index)
                }
                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 10
                    Icon { Layout.alignment: Qt.AlignHCenter; text: modelData.icon; size: 38; color: index === menu.selected ? Theme.accent : Theme.text }
                    Label { Layout.alignment: Qt.AlignHCenter; text: modelData.label; font.weight: Font.DemiBold }
                }
            }
        }
    }
}
