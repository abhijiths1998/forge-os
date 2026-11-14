//@ pragma UseQApplication
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
// Forge's shell: the bar, the Control Center and popups, notifications,
// on-screen displays, the desktop shortcut panel and the overlays (cheat
// sheet, hold-Super keys, overview, window switcher, clipboard, emoji,
// power). Started by forge-shell.service; `forge-shell <action>` and the
// Hyprland binds (global shortcuts "forge:<name>") drive it.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.services
import qs.bar
import qs.panels
import qs.overlays

ShellRoot {
    id: root

    Variants { model: Quickshell.screens; Bar {} }
    Variants { model: Quickshell.screens; ShortcutPanel {} }

    ControlCenter {}
    NotificationCenter {}
    NotificationPopups {}
    Osd { id: osdView }
    CheatSheet {}
    WhichKey {}
    Overview {}
    Switcher { id: switcherView }
    ClipboardPicker {}
    EmojiPicker {}
    PowerMenu {}

    // Hyprland's mode (resize, move) for the bar's badge.
    Connections {
        target: Hyprland
        function onRawEvent(e) {
            if (e.name === "submap") Shell.submap = e.data === "reset" ? "" : e.data;
        }
    }

    // The binds in the session's keybinds.lua call these: instant, and
    // they know when a key is let go (hold Super, release Alt).
    component Key: GlobalShortcut { appid: "forge" }
    Key { name: "control"; onPressed: Shell.toggle("control") }
    Key { name: "notifications"; onPressed: Shell.toggle("notifications") }
    Key { name: "cheatsheet"; onPressed: Shell.toggle("cheatsheet") }
    Key { name: "clipboard"; onPressed: Shell.toggle("clipboard") }
    Key { name: "emoji"; onPressed: Shell.toggle("emoji") }
    Key { name: "overview"; onPressed: Shell.toggle("overview") }
    Key { name: "power"; onPressed: Shell.toggle("power") }
    Key { name: "shortcutsPanel"; onPressed: Settings.panelVisible = !Settings.panelVisible }
    Key { name: "whichkey"; onPressed: if (Shell.open === "") Shell.show("whichkey"); onReleased: Shell.close("whichkey") }
    Key { name: "whichkeyHide"; onPressed: Shell.close("whichkey") }
    Key { name: "switcherNext"; onPressed: switcherView.step(1) }
    Key { name: "switcherPrevious"; onPressed: switcherView.step(-1) }
    Key { name: "switcherCommit"; onPressed: switcherView.commit() }
    Key { name: "capsLock"; onPressed: osdView.capsLock() }

    // The same for scripts: forge-shell <action> (qs ipc call shell ...).
    IpcHandler {
        target: "shell"
        function control(): void { Shell.toggle("control"); }
        function notifications(): void { Shell.toggle("notifications"); }
        function cheatsheet(): void { Shell.toggle("cheatsheet"); }
        function clipboard(): void { Shell.toggle("clipboard"); }
        function emoji(): void { Shell.toggle("emoji"); }
        function overview(): void { Shell.toggle("overview"); }
        function power(): void { Shell.show("power"); }
        function whichkey(): void { Shell.toggle("whichkey"); }
        function shortcutsPanel(): void { Settings.panelVisible = !Settings.panelVisible; }
        function switcher(direction: string): void {
            if (direction === "commit") switcherView.commit(); else switcherView.step(direction === "previous" ? -1 : 1);
        }
        function osd(kind: string): void { if (kind === "capslock") osdView.capsLock(); }
        function wallpaperPause(): void { Shell.wallpaperPaused = true; }
        function wallpaperResume(): void { Shell.wallpaperPaused = false; }
        function close(): void { Shell.close(); }
        function state(): string { return Shell.open; }
        function notificationCount(): int { return Notifs.history.length; }
        function popupCount(): int { return Notifs.popups.length; }
        function dismissPopups(): void { Notifs.popups = []; }
    }
}
