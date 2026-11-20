pragma Singleton
// The desktop's state from forged (Wi-Fi, Bluetooth, volume, brightness,
// power, cooling, dark mode, tiling, do not disturb, battery, media), the
// same D-Bus service the rest of Forge uses. Quickshell has no D-Bus client
// for QML, so `forged watch` streams the state as JSON lines; changes go
// through `forged set` and `forged do`.
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property var state: ({})
    readonly property bool ready: Object.keys(state).length > 0

    function part(name) { return state[name] || ({ available: false }); }
    readonly property var wifi: part("wifi")
    readonly property var bluetooth: part("bluetooth")
    readonly property var volume: part("volume")
    readonly property var brightness: part("brightness")
    readonly property var power: part("power")
    readonly property var thermal: part("thermal")
    readonly property var dark: part("dark")
    readonly property var tiling: part("tiling")
    readonly property var dnd: part("dnd")
    readonly property var battery: part("battery")
    readonly property var media: part("media")

    function set(key, value) {
        Quickshell.execDetached(["forged", "set", key, String(value)]);
    }

    // A slow action (joining a network, connecting a device): done(error)
    // runs with "" when it worked.
    function run(action, arg, extra, done) {
        const p = doer.createObject(root, { command: ["forged", "do", action, arg || "", extra || ""] });
        p.finished.connect(err => { if (done) done(err); p.destroy(); });
        p.running = true;
    }

    Component {
        id: doer
        Process {
            signal finished(string err)
            stderr: StdioCollector { id: errs }
            onExited: code => finished(code === 0 ? "" : (errs.text.replace(/^forged: /, "").trim() || "failed"))
        }
    }

    Process {
        id: watcher
        command: ["forged", "watch"]
        running: true
        stdout: SplitParser {
            onRead: line => {
                try { root.state = JSON.parse(line); } catch (e) {}
            }
        }
        onExited: retry.start()
    }
    Timer {
        id: retry
        interval: 3000
        onTriggered: watcher.running = true
    }
}
