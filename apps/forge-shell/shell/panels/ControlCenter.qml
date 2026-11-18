// The Control Center (Super+A, or the button at the end of the bar):
// Wi-Fi, Bluetooth, quiet, dark mode, tiling and night light; brightness
// and volume; power and cooling profiles; what's playing.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Hyprland
import qs.services
import qs.widgets

PanelWindow {
    id: panel
    visible: Shell.isOpen("control")
    screen: Quickshell.screens.find(s => Hyprland.focusedMonitor && s.name === Hyprland.focusedMonitor.name) || Quickshell.screens[0]
    anchors { top: true; right: true }
    margins { top: 6; right: 10 }
    implicitWidth: 380
    implicitHeight: body.implicitHeight + 32
    exclusiveZone: 0
    color: "transparent"
    WlrLayershell.namespace: "forge-control"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    HyprlandFocusGrab {
        windows: [panel]
        active: panel.visible
        onCleared: Shell.close("control")
    }

    Glass {
        anchors.fill: parent
        strong: true
        focus: true
        Keys.onEscapePressed: Shell.close("control")

        ColumnLayout {
            id: body
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 8
                rowSpacing: 8
                Toggle {
                    Layout.fillWidth: true
                    icon: Forged.wifi.enabled ? Icons.wifi[4] : Icons.wifiOff
                    title: "Wi-Fi"
                    detail: Forged.wifi.wired ? "Cable" : (Forged.wifi.ssid || (Forged.wifi.enabled ? "Not connected" : "Off"))
                    on: Forged.wifi.enabled === true
                    available: Forged.wifi.available !== false
                    onToggled: Forged.set("wifi", "toggle")
                }
                Toggle {
                    Layout.fillWidth: true
                    icon: Forged.bluetooth.enabled ? Icons.bluetooth : Icons.bluetoothOff
                    title: "Bluetooth"
                    detail: (Forged.bluetooth.connected || []).join(", ") || (Forged.bluetooth.enabled ? "On" : "Off")
                    on: Forged.bluetooth.enabled === true
                    available: Forged.bluetooth.available === true
                    onToggled: Forged.set("bluetooth", "toggle")
                }
                Toggle {
                    Layout.fillWidth: true
                    icon: Forged.dnd.enabled ? Icons.bellOff : Icons.bell
                    title: "Do not disturb"
                    detail: Forged.dnd.enabled ? "On" : "Off"
                    on: Forged.dnd.enabled === true
                    onToggled: Forged.set("dnd", "toggle")
                }
                Toggle {
                    Layout.fillWidth: true
                    icon: Forged.dark.enabled === false ? Icons.sun : Icons.moon
                    title: "Dark mode"
                    detail: Forged.dark.enabled === false ? "Light" : "Dark"
                    on: Forged.dark.enabled !== false
                    onToggled: Forged.set("dark", "toggle")
                }
                Toggle {
                    Layout.fillWidth: true
                    icon: Icons.tiles
                    title: "Tiling"
                    detail: Forged.tiling.available ? "Workspace " + Forged.tiling.workspace : ""
                    on: Forged.tiling.enabled === true
                    available: Forged.tiling.available === true
                    onToggled: Forged.set("tiling", "toggle")
                }
                Toggle {
                    Layout.fillWidth: true
                    icon: Icons.nightLight
                    title: "Night light"
                    detail: Settings.nightLight ? "Warm" : "Off"
                    on: Settings.nightLight
                    onToggled: Settings.nightLight = !Settings.nightLight
                }
            }

            Slider {
                Layout.fillWidth: true
                visible: Forged.brightness.available === true
                icon: Icons.brightness
                value: (Forged.brightness.level || 0) / 100
                onMoved: x => Forged.set("brightness", Math.max(1, Math.round(x * 100)))
            }
            Slider {
                Layout.fillWidth: true
                available: Forged.volume.available === true
                icon: Forged.volume.muted ? Icons.volumeMute : Icons.volume[2]
                value: (Forged.volume.level || 0) / 100
                onMoved: x => Forged.set("volume", Math.round(x * 100))
                onIconClicked: Forged.set("volume", "toggle")
            }

            // Power profiles (power-profiles-daemon) and cooling (Forge Thermal).
            Segmented {
                Layout.fillWidth: true
                visible: Forged.power.available === true
                title: "Power"
                options: Forged.power.profiles || []
                labels: ({ "power-saver": "Saver", "balanced": "Balanced", "performance": "Performance" })
                current: Forged.power.profile || ""
                onPicked: v => Forged.set("power", v)
            }
            Segmented {
                Layout.fillWidth: true
                visible: Forged.thermal.available === true
                title: "Cooling" + (Forged.thermal.cpu_temp ? "  ·  CPU " + Forged.thermal.cpu_temp + " °C" : "")
                options: Forged.thermal.profiles || []
                labels: ({ "silent": "Silent", "cool": "Cool", "balanced": "Balanced", "gaming": "Game", "performance": "Max" })
                current: Forged.thermal.profile || ""
                onPicked: v => Forged.set("thermal", v)
            }

            NowPlaying { Layout.fillWidth: true }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Label { Layout.fillWidth: true; dim: true; size: 12; text: Quickshell.env("USER") + "@" + Quickshell.env("HOSTNAME") }
                Repeater {
                    model: [
                        { icon: Icons.settings, run: () => Quickshell.execDetached(["forge-open", "settings"]) },
                        { icon: Icons.lock, run: () => Quickshell.execDetached(["loginctl", "lock-session"]) },
                        { icon: Icons.power, run: () => Shell.show("power") }
                    ]
                    HoverButton {
                        required property var modelData
                        Layout.preferredWidth: 34
                        Layout.preferredHeight: 34
                        radius: 17
                        onClicked: { Shell.close("control"); modelData.run(); }
                        Icon { anchors.centerIn: parent; text: modelData.icon; size: 17 }
                    }
                }
            }
        }
    }

    // Night light: hyprsunset while it's on.
    Process {
        running: Settings.nightLight
        command: ["hyprsunset", "--temperature", "4300"]
    }
}
