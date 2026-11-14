pragma Singleton
// The shell's own settings, kept across logins in
// ~/.local/state/forge/shell.json: the shortcut panel's place and whether
// it's shown, night light, recent emoji.
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property alias panelVisible: data.panelVisible
    property alias panelCollapsed: data.panelCollapsed
    property alias panelRight: data.panelRight
    property alias panelTop: data.panelTop
    property alias nightLight: data.nightLight
    property alias recentEmoji: data.recentEmoji

    FileView {
        id: file
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/forge/shell.json"
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        // A first login has no file yet: write the defaults.
        onLoadFailed: error => { if (error === FileViewError.FileNotFound) writeAdapter(); }

        JsonAdapter {
            id: data
            // New users see the shortcut panel until they hide it.
            property bool panelVisible: true
            property bool panelCollapsed: false
            property int panelRight: 24
            property int panelTop: 64
            property bool nightLight: false
            property list<string> recentEmoji: []
        }
    }
}
