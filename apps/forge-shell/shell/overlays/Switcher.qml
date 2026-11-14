// Alt+Tab: the open windows, most recent first, with live previews. Keep
// Alt held and press Tab to move on; let go of Alt to switch.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import qs.services
import qs.widgets

PanelWindow {
    id: switcher
    visible: Shell.isOpen("switcher")
    screen: Quickshell.screens.find(s => Hyprland.focusedMonitor && s.name === Hyprland.focusedMonitor.name) || Quickshell.screens[0]
    implicitWidth: Math.min(row.implicitWidth + 40, screen ? screen.width - 80 : 1400)
    implicitHeight: 230
    exclusiveZone: 0
    color: "transparent"
    WlrLayershell.namespace: "forge-switcher"
    WlrLayershell.layer: WlrLayer.Overlay

    property var windows: []
    property int selected: 0

    // Most recently focused first (Hyprland's focus history).
    function load() {
        Hyprland.refreshToplevels();
        // The focused window first, whatever the (possibly stale) history says.
        const active = Hyprland.activeToplevel;
        windows = Hyprland.toplevels.values
            .filter(t => t.lastIpcObject && t.lastIpcObject.mapped !== false && !(t.lastIpcObject.workspace || {}).name?.startsWith("special"))
            .sort((a, b) => (a === active ? -1 : b === active ? 1 : 0)
                            || (a.lastIpcObject.focusHistoryID ?? 99) - (b.lastIpcObject.focusHistoryID ?? 99));
    }
    function step(by) {
        if (!visible) {
            load();
            if (windows.length < 2) return;
            selected = by > 0 ? 1 : windows.length - 1;
            Shell.show("switcher");
            return;
        }
        selected = (selected + by + windows.length) % windows.length;
    }
    function commit() {
        if (!visible) return;
        const w = windows[selected];
        Shell.close("switcher");
        if (w) Hyprland.dispatch(`hl.dsp.focus({ window = "address:0x${w.address}" })`);
    }

    Glass {
        anchors.fill: parent
        strong: true
        Row {
            id: row
            anchors.centerIn: parent
            spacing: 14
            Repeater {
                model: switcher.windows
                Rectangle {
                    id: item
                    required property var modelData
                    required property int index
                    width: 220
                    height: 190
                    radius: Theme.radius - 2
                    color: index === switcher.selected ? Theme.alpha(Theme.accent, 0.28) : "transparent"
                    border.width: index === switcher.selected ? 2 : 0
                    border.color: Theme.accent
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 8
                        ScreencopyView {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            captureSource: switcher.visible && item.modelData.wayland ? item.modelData.wayland : null
                            live: true
                            constraintSize: Qt.size(200, 130)
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            IconImage {
                                implicitSize: 18
                                source: Quickshell.iconPath(DesktopEntries.heuristicLookup(item.modelData.lastIpcObject.class || "")?.icon
                                                            || item.modelData.lastIpcObject.class || "", "application-x-executable")
                                visible: Quickshell.iconPath(DesktopEntries.heuristicLookup(item.modelData.lastIpcObject.class || "")?.icon
                                                             || item.modelData.lastIpcObject.class || "", true) !== ""
                            }
                            Label { Layout.fillWidth: true; text: item.modelData.title; size: 12 }
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: { switcher.selected = item.index; switcher.commit(); }
                    }
                }
            }
        }
    }
}
