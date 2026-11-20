// Super+Tab: every workspace with live previews of its windows. Click a
// window to go to it, a workspace to switch there; arrows and Enter work.
import QtQuick
import QtQuick.Layouts
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services
import qs.widgets

ShellOverlay {
    id: overview
    name: "overview"
    property int selected: 0

    readonly property var monitor: Hyprland.focusedMonitor
    readonly property var workspaces: {
        const ws = Hyprland.workspaces.values.filter(w => w.id > 0).sort((a, b) => a.id - b.id);
        const next = (ws.length ? ws[ws.length - 1].id : 0) + 1;
        return ws.map(w => ({ id: w.id, ws: w })).concat([{ id: next, ws: null }]);
    }
    readonly property real ratio: monitor ? monitor.width / Math.max(1, monitor.height) : 16 / 9

    onOpened: {
        Hyprland.refreshToplevels();
        selected = Math.max(0, workspaces.findIndex(w => w.ws && w.ws.active));
        grid.forceActiveFocus();
    }

    function go(entry) {
        Shell.close("overview");
        Hyprland.dispatch(`hl.dsp.focus({ workspace = ${entry.id} })`);
    }

    GridLayout {
        id: grid
        anchors.centerIn: parent
        columns: Math.min(4, overview.workspaces.length)
        columnSpacing: 22
        rowSpacing: 22
        focus: true
        Keys.onLeftPressed: overview.selected = Math.max(0, overview.selected - 1)
        Keys.onRightPressed: overview.selected = Math.min(overview.workspaces.length - 1, overview.selected + 1)
        Keys.onUpPressed: overview.selected = Math.max(0, overview.selected - columns)
        Keys.onDownPressed: overview.selected = Math.min(overview.workspaces.length - 1, overview.selected + columns)
        Keys.onReturnPressed: overview.go(overview.workspaces[overview.selected])
        Keys.onEscapePressed: Shell.close("overview")
        Keys.onTabPressed: overview.selected = (overview.selected + 1) % overview.workspaces.length

        Repeater {
            model: overview.workspaces
            Glass {
                id: card
                required property var modelData
                required property int index
                readonly property real scale: width / (overview.monitor ? overview.monitor.width / overview.monitor.scale : 1920)
                Layout.preferredWidth: 300
                Layout.preferredHeight: 300 / overview.ratio
                strong: true
                border.width: index === overview.selected ? 2 : 1
                border.color: index === overview.selected ? Theme.accent : Theme.edge
                clip: true

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: overview.selected = card.index
                    onClicked: overview.go(card.modelData)
                }
                Repeater {
                    model: card.modelData.ws ? card.modelData.ws.toplevels.values : []
                    Item {
                        id: win
                        required property var modelData
                        readonly property var ipc: modelData.lastIpcObject || {}
                        x: ((ipc.at || [0, 0])[0] - (overview.monitor ? overview.monitor.x : 0)) * card.scale
                        y: ((ipc.at || [0, 0])[1] - (overview.monitor ? overview.monitor.y : 0)) * card.scale
                        width: (ipc.size || [0, 0])[0] * card.scale
                        height: (ipc.size || [0, 0])[1] * card.scale
                        ScreencopyView {
                            anchors.fill: parent
                            captureSource: overview.visible && win.modelData.wayland ? win.modelData.wayland : null
                            live: true
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: 6
                            color: "transparent"
                            border.width: winMouse.containsMouse ? 2 : 0
                            border.color: Theme.accent
                        }
                        MouseArea {
                            id: winMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                Shell.close("overview");
                                Hyprland.dispatch(`hl.dsp.focus({ window = "address:0x${win.modelData.address}" })`);
                            }
                        }
                    }
                }
                Label {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.margins: 8
                    text: card.modelData.ws ? card.modelData.id : "New workspace"
                    font.weight: Font.Bold
                    dim: card.modelData.ws === null
                }
            }
        }
    }
}
