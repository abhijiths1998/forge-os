pragma Singleton
// The Forge theme for the shell, from ~/.config/forge/theme.json (the
// Theming Kit and `forge theme` write it); Forge Glass dark until then.
// Changes apply live.
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property var data: ({})
    readonly property bool dark: data.dark !== false
    readonly property color accent: data.accent || "#7F8EF5"
    // Shell surfaces use the menu opacity: panels read like menus.
    readonly property real glassAlpha: Math.max(0.35, Math.min(0.95, (data.menuOpacity || 58) / 100))
    readonly property int radius: Math.max(6, Math.min(28, data.cornerRadius || 14))

    readonly property color base: dark ? "#1b1d2b" : "#f4f5fb"
    readonly property color glass: Qt.rgba(base.r, base.g, base.b, glassAlpha)
    readonly property color glassStrong: Qt.rgba(base.r, base.g, base.b, Math.min(0.96, glassAlpha + 0.22))
    readonly property color text: dark ? "#f4f5fb" : "#1f2236"
    readonly property color subtext: dark ? Qt.rgba(0.957, 0.961, 0.984, 0.62) : Qt.rgba(0.12, 0.13, 0.21, 0.62)
    readonly property color faint: dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)
    readonly property color hover: dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08)
    readonly property color edge: dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.6)
    readonly property color onAccent: (0.299 * accent.r + 0.587 * accent.g + 0.114 * accent.b) > 0.6 ? "#16182e" : "white"
    readonly property color danger: "#f07f8e"
    readonly property color good: "#7fd6a4"
    readonly property color warn: "#f5c97f"

    readonly property string font: "Plus Jakarta Sans"
    readonly property string mono: "JetBrainsMono Nerd Font"
    readonly property string icons: "JetBrainsMono Nerd Font Propo"

    function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a); }

    FileView {
        path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/forge/theme.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try { root.data = JSON.parse(text()); } catch (e) { root.data = {}; }
        }
        onLoadFailed: root.data = {}
    }
}
