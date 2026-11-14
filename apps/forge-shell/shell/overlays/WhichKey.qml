// Hold Super for half a second: what each next key does, as keycaps.
// Gone as soon as Super is let go (or a key is pressed).
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services
import qs.widgets

PanelWindow {
    id: popup
    visible: Shell.isOpen("whichkey")
    screen: Quickshell.screens.find(s => Hyprland.focusedMonitor && s.name === Hyprland.focusedMonitor.name) || Quickshell.screens[0]
    anchors { bottom: true }
    margins { bottom: 40 }
    implicitWidth: Math.min(screen ? screen.width - 80 : 1200, 1100)
    implicitHeight: grid.implicitHeight + 40
    exclusiveZone: 0
    color: "transparent"
    mask: Region {}
    WlrLayershell.namespace: "forge-whichkey"
    WlrLayershell.layer: WlrLayer.Overlay

    // Super + one key (or Super+Shift + key), the commonest first.
    readonly property var entries: Binds.all.filter(e => e.keys.some(k => k[0] === "Super" && k.length <= 3 && k[1] !== "hold"))

    Timer { running: popup.visible; interval: 8000; onTriggered: Shell.close("whichkey") }
    Connections {
        target: Hyprland
        function onRawEvent(e) { if (e.name === "activewindow" || e.name === "workspace") Shell.close("whichkey"); }
    }

    Glass {
        anchors.fill: parent
        strong: true
        GridLayout {
            id: grid
            anchors.fill: parent
            anchors.margins: 20
            columns: 4
            columnSpacing: 22
            rowSpacing: 8
            Repeater {
                model: popup.entries
                RowLayout {
                    required property var modelData
                    readonly property var combo: modelData.keys.find(k => k[0] === "Super")
                    spacing: 8
                    Layout.fillWidth: true
                    KeyCombo { combos: [parent.combo.slice(1)]; size: 12 }
                    Label { Layout.fillWidth: true; text: modelData.description; size: 12 }
                }
            }
        }
    }
}
