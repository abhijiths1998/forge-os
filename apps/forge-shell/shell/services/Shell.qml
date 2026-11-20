pragma Singleton
// Which of the shell's panels and overlays is open. One at a time: opening
// one closes the others, so Escape always means "back to the desktop".
import QtQuick
import Quickshell

Singleton {
    id: root

    property string open: ""          // "", or the name of what's showing
    property string submap: ""        // Hyprland's resize/move mode, for the bar's badge
    property bool wallpaperPaused: false

    function toggle(name) { open = (open === name) ? "" : name; }
    function show(name) { open = name; }
    function close(name) { if (!name || open === name) open = ""; }
    function isOpen(name) { return open === name; }
}
