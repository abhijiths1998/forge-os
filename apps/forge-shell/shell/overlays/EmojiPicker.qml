// Super+.: emoji by name ("heart", "thumbs up"), recent ones first. Enter
// types the emoji into the window you were in (and copies it).
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.widgets

Picker {
    id: picker
    name: "emoji"
    title: "Emoji"
    icon: Icons.emoji
    placeholder: "Search emoji: heart, smile, fire…"
    columns: 10
    count: shown.length

    property var all: []              // [{ e: "😀", n: "grinning face" }]
    readonly property var shown: {
        const q = query.toLowerCase().trim();
        if (!q) {
            const recent = Settings.recentEmoji.map(e => ({ e: e, n: "recent" }));
            return recent.concat(all.filter(x => Settings.recentEmoji.indexOf(x.e) < 0)).slice(0, 400);
        }
        const words = q.split(/\s+/);
        return all.filter(x => words.every(w => x.n.indexOf(w) >= 0)).slice(0, 400);
    }

    // Unicode's own list (the unicode-emoji package): fully-qualified only.
    FileView {
        path: "/usr/share/unicode/emoji/emoji-test.txt"
        onLoaded: {
            const out = [];
            for (const line of text().split("\n")) {
                const m = /; fully-qualified\s+#\s(\S+)\sE[\d.]+\s(.+)$/.exec(line);
                if (m) out.push({ e: m[1], n: m[2].toLowerCase() });
            }
            picker.all = out;
        }
    }

    onPicked: i => {
        const x = shown[i];
        if (!x) return;
        Shell.close("emoji");
        Settings.recentEmoji = [x.e].concat(Settings.recentEmoji.filter(e => e !== x.e)).slice(0, 20);
        Quickshell.execDetached(["sh", "-c", 'printf %s "$1" | wl-copy; sleep 0.15; wtype "$1"', "sh", x.e]);
    }

    GridView {
        anchors.fill: parent
        model: picker.shown
        cellWidth: width / picker.columns
        cellHeight: cellWidth
        currentIndex: picker.selected
        delegate: HoverButton {
            required property var modelData
            required property int index
            width: GridView.view.cellWidth
            height: width
            radius: 10
            active: index === picker.selected
            activeColour: Theme.alpha(Theme.accent, 0.35)
            onClicked: picker.picked(index)
            Text { anchors.centerIn: parent; text: modelData.e; font.pixelSize: 26 }
        }
    }
    Label {
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        text: picker.shown.length && picker.selected < picker.shown.length ? picker.shown[picker.selected].n : ""
        dim: true
        size: 11
    }
}
