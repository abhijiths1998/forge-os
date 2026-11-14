// The desktop shortcut panel: a glass card on the desktop (under windows)
// listing the shortcuts by category, read live from Hyprland so it's never
// out of date. New users see it until they hide it. It can be collapsed
// (just its title), moved (drag the title) or hidden ("I know these");
// Super+Shift+K brings it back, Super+/ shows every shortcut.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.services
import qs.widgets

PanelWindow {
    id: panel
    required property var modelData
    screen: modelData
    // Only on the first screen.
    visible: Settings.panelVisible && modelData === Quickshell.screens[0] && Binds.categories.length > 0
    anchors { top: true; right: true }
    margins { top: Settings.panelTop; right: Settings.panelRight }
    implicitWidth: 330
    implicitHeight: card.implicitHeight
    exclusiveZone: 0
    color: "transparent"
    WlrLayershell.namespace: "forge-desktop"
    WlrLayershell.layer: WlrLayer.Bottom

    // The categories and how many rows each shows here; Super+/ has them all.
    readonly property var shown: ({ "Apps": 5, "Windows": 6, "Workspaces": 3, "Shell": 4, "Screenshots": 3, "System": 3 })

    Glass {
        id: card
        width: parent.width
        implicitHeight: column.implicitHeight + 24

        ColumnLayout {
            id: column
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            // The title doubles as the handle: drag to move, click to collapse.
            RowLayout {
                Layout.fillWidth: true
                MouseArea {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 26
                    cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                    property point start
                    property int startTop
                    property int startRight
                    property bool moved: false
                    onPressed: e => {
                        const g = mapToGlobal(e.x, e.y);
                        start = Qt.point(g.x, g.y); startTop = Settings.panelTop; startRight = Settings.panelRight; moved = false;
                    }
                    onPositionChanged: e => {
                        const g = mapToGlobal(e.x, e.y);
                        const dx = g.x - start.x, dy = g.y - start.y;
                        if (Math.abs(dx) + Math.abs(dy) > 4) moved = true;
                        Settings.panelRight = Math.max(0, startRight - dx);
                        Settings.panelTop = Math.max(0, startTop + dy);
                    }
                    onClicked: if (!moved) Settings.panelCollapsed = !Settings.panelCollapsed
                    RowLayout {
                        anchors.fill: parent
                        spacing: 8
                        Icon { text: Icons.keyboard; size: 17; color: Theme.accent }
                        Label { text: "Shortcuts"; font.weight: Font.Bold; size: 14 }
                        Label { Layout.fillWidth: true; text: "Super + / for all"; dim: true; size: 11 }
                        Icon { text: Settings.panelCollapsed ? Icons.chevronDown : Icons.chevronUp; size: 15; color: Theme.subtext }
                    }
                }
            }

            Repeater {
                model: Settings.panelCollapsed ? [] : Binds.categories.filter(c => panel.shown[c.name])
                ColumnLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 4
                    Label { text: modelData.name.toUpperCase(); size: 10; dim: true; font.weight: Font.Bold; font.letterSpacing: 1 }
                    Repeater {
                        model: modelData.entries.slice(0, panel.shown[modelData.name])
                        RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 8
                            Label { Layout.fillWidth: true; text: modelData.description; size: 12 }
                            KeyCombo { combos: modelData.keys.slice(0, 1); size: 10 }
                        }
                    }
                }
            }

            RowLayout {
                visible: !Settings.panelCollapsed
                Layout.fillWidth: true
                Layout.topMargin: 2
                HoverButton {
                    Layout.preferredWidth: hideLabel.implicitWidth + 20
                    Layout.preferredHeight: 26
                    radius: 13
                    onClicked: {
                        Settings.panelVisible = false;
                        Quickshell.execDetached(["notify-send", "--app-name=Forge", "--icon=input-keyboard",
                            "Shortcut panel hidden", "Super+Shift+K brings it back; Super+/ shows every shortcut."]);
                    }
                    Label { id: hideLabel; anchors.centerIn: parent; text: "I know these, hide"; size: 11; dim: true }
                }
                Item { Layout.fillWidth: true }
                HoverButton {
                    Layout.preferredWidth: allLabel.implicitWidth + 20
                    Layout.preferredHeight: 26
                    radius: 13
                    onClicked: Shell.show("cheatsheet")
                    Label { id: allLabel; anchors.centerIn: parent; text: "All shortcuts"; size: 11; color: Theme.accent; font.weight: Font.DemiBold }
                }
            }
        }
    }
}
