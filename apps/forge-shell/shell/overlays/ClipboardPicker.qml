// Super+V: the clipboard history (cliphist), newest first. Enter pastes
// the chosen entry into the window you were in; Delete forgets it.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.services
import qs.widgets

Picker {
    id: picker
    name: "clipboard"
    title: "Clipboard history"
    icon: Icons.clipboard
    placeholder: "Search what you copied"
    count: shown.length

    property var entries: []          // [{ id, text }]
    readonly property var shown: entries.filter(e => e.text.toLowerCase().indexOf(query.toLowerCase()) >= 0)

    onOpened: lister.running = true
    Process {
        id: lister
        command: ["cliphist", "list"]
        stdout: StdioCollector {
            onStreamFinished: picker.entries = text.split("\n").filter(l => l).map(l => {
                const tab = l.indexOf("\t");
                return { id: l.slice(0, tab), text: l.slice(tab + 1) };
            })
        }
    }

    onPicked: i => {
        const e = shown[i];
        Shell.close("clipboard");
        // Terminals paste with Ctrl+Shift+V.
        const cls = (Hyprland.activeToplevel && Hyprland.activeToplevel.lastIpcObject.class || "").toLowerCase();
        const terminal = /term|foot|kitty|alacritty|wezterm|ghostty|konsole/.test(cls);
        Quickshell.execDetached(["sh", "-c",
            `cliphist decode "$1" | wl-copy && sleep 0.15 && wtype -M ctrl ${terminal ? "-M shift " : ""}-k v -m ctrl ${terminal ? "-m shift" : ""}`,
            "sh", e.id]);
    }
    onRemoved: i => {
        const e = shown[i];
        if (!e) return;
        Quickshell.execDetached(["sh", "-c", `printf '%s\t%s\n' "$1" "$2" | cliphist delete`, "sh", e.id, e.text]);
        entries = entries.filter(x => x.id !== e.id);
    }

    ListView {
        anchors.fill: parent
        model: picker.shown
        currentIndex: picker.selected
        spacing: 2
        delegate: ListRow {
            required property var modelData
            required property int index
            width: ListView.view.width
            readonly property bool image: modelData.text.startsWith("[[ binary data")
            icon: image ? Icons.image : Icons.clipboard
            title: image ? modelData.text.replace(/^\[\[ binary data /, "Image, ").replace(/ \]\]$/, "") : modelData.text
            current: index === picker.selected
            onClicked: picker.picked(index)
        }
        Label {
            anchors.centerIn: parent
            visible: picker.shown.length === 0
            text: picker.entries.length ? "Nothing matches" : "Copy something and it shows up here"
            dim: true
        }
    }
    Label {
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        text: "Enter pastes · Delete forgets"
        dim: true
        size: 11
    }
}
