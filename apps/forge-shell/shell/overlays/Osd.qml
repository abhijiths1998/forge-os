// On-screen display for volume, brightness and Caps Lock: a small glass
// pill near the bottom of the focused screen, gone after a moment.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import Quickshell.Io
import qs.services
import qs.widgets

Scope {
    id: osd
    property string kind: ""         // "volume", "brightness", "caps"
    property real value: 0
    property bool caps: false

    function show(k) { kind = k; hide.restart(); }

    // Volume: PipeWire's default output, whoever changed it.
    PwObjectTracker { objects: [Pipewire.defaultAudioSink] }
    Connections {
        target: Pipewire.defaultAudioSink ? Pipewire.defaultAudioSink.audio : null
        function onVolumesChanged() { osd.value = Pipewire.defaultAudioSink.audio.volume; osd.show("volume"); }
        function onMutedChanged() { osd.value = Pipewire.defaultAudioSink.audio.volume; osd.show("volume"); }
    }
    // Brightness: forged follows the backlight, from keys and sliders alike.
    property int lastBrightness: -1
    Connections {
        target: Forged
        function onStateChanged() {
            const b = Forged.brightness;
            if (!b.available) return;
            if (osd.lastBrightness >= 0 && b.level !== osd.lastBrightness && !Shell.isOpen("control")) {
                osd.value = b.level / 100;
                osd.show("brightness");
            }
            osd.lastBrightness = b.level;
        }
    }
    // Caps Lock: its LED, read just after the key (keybinds.lua calls us).
    function capsLock() { capsReader.running = true; }
    Process {
        id: capsReader
        command: ["sh", "-c", "sleep 0.1; cat /sys/class/leds/*::capslock/brightness 2>/dev/null | head -1"]
        stdout: StdioCollector {
            onStreamFinished: { osd.caps = text.trim() !== "" && text.trim() !== "0"; osd.show("caps"); }
        }
    }

    Timer { id: hide; interval: 1400; onTriggered: osd.kind = "" }

    PanelWindow {
        visible: osd.kind !== ""
        screen: Quickshell.screens.find(s => Hyprland.focusedMonitor && s.name === Hyprland.focusedMonitor.name) || Quickshell.screens[0]
        anchors { bottom: true }
        margins { bottom: 90 }
        implicitWidth: 300
        implicitHeight: 52
        exclusiveZone: 0
        color: "transparent"
        mask: Region {}
        WlrLayershell.namespace: "forge-osd"
        WlrLayershell.layer: WlrLayer.Overlay

        Glass {
            anchors.fill: parent
            radius: height / 2
            strong: true
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 18
                anchors.rightMargin: 20
                spacing: 14
                Icon {
                    size: 20
                    text: osd.kind === "caps" ? Icons.capsLock
                        : osd.kind === "brightness" ? Icons.brightness
                        : (Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio.muted) ? Icons.volumeMute
                        : Icons.volume[Math.min(2, Math.floor(osd.value * 3))]
                }
                Rectangle {
                    visible: osd.kind !== "caps"
                    Layout.fillWidth: true
                    implicitHeight: 6
                    radius: 3
                    color: Theme.faint
                    Rectangle {
                        width: parent.width * Math.max(0, Math.min(1, osd.value))
                        height: parent.height
                        radius: 3
                        color: Theme.accent
                        Behavior on width { NumberAnimation { duration: 100 } }
                    }
                }
                Label {
                    Layout.fillWidth: osd.kind === "caps"
                    text: osd.kind === "caps" ? (osd.caps ? "Caps Lock on" : "Caps Lock off") : Math.round(osd.value * 100) + "%"
                    font.weight: Font.DemiBold
                    font.features: { "tnum": 1 }
                }
            }
        }
    }
}
