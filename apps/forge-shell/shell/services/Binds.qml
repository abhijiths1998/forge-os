pragma Singleton
// Every shortcut, read live from Hyprland (`hyprctl binds -j`), so the
// shortcut panel, the cheat sheet and the hold-Super popup never go stale.
// Forge's binds carry "[Category] description" (forge.bind in the session's
// keybinds.lua); binds without one (an app's own, a user's raw hl.bind) go
// under "Other".
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Singleton {
    id: root

    readonly property var order: ["Apps", "Shell", "Windows", "Workspaces", "Screenshots", "System", "Media", "Other"]
    // [{ name, entries: [{ keys: [["Super","E"], ...], description, category, submap }] }]
    property var categories: []
    // Flat list of the same entries, for search.
    property var all: []

    // Modifier bits, as Hyprland reports them.
    readonly property var mods: [[64, "Super"], [4, "Ctrl"], [8, "Alt"], [1, "Shift"]]

    readonly property var names: ({
        "Return": "Enter", "space": "Space", "Space": "Space", "grave": "`", "slash": "/", "period": ".",
        "comma": ",", "Escape": "Esc", "Print": "PrtSc", "Delete": "Del", "Tab": "Tab",
        "Left": "←", "Right": "→", "Up": "↑", "Down": "↓",
        "mouse:272": "Left drag", "mouse:273": "Right drag", "mouse_down": "Scroll ↓", "mouse_up": "Scroll ↑",
        "Super_L": "hold", "Alt_L": "release", "Caps_Lock": "Caps Lock",
        "XF86AudioRaiseVolume": "Volume +", "XF86AudioLowerVolume": "Volume −", "XF86AudioMute": "Mute",
        "XF86AudioMicMute": "Mic mute", "XF86MonBrightnessUp": "Brightness +",
        "XF86MonBrightnessDown": "Brightness −", "XF86KbdBrightnessUp": "Keyboard light +",
        "XF86KbdBrightnessDown": "Keyboard light −", "XF86AudioPlay": "Play", "XF86AudioPause": "Pause",
        "XF86AudioNext": "Next", "XF86AudioPrev": "Previous"
    })

    function keyName(k) {
        if (names[k] !== undefined) return names[k];
        if (k.length === 1) return k.toUpperCase();
        if (/^F\d+$/.test(k)) return k;
        return k.replace(/^XF86/, "").replace(/_/g, " ");
    }

    function combo(b) {
        const out = [];
        for (const [bit, name] of mods)
            if (b.modmask & bit) out.push(name);
        // A modifier key on its own (hold Super, release Alt) reads as itself.
        if (b.key === "Super_L" && out.length === 1 && out[0] === "Super") return ["Super", "hold"];
        out.push(keyName(b.key));
        return out;
    }

    function parse(json) {
        let binds;
        try { binds = JSON.parse(json); } catch (e) { return; }
        const byCat = {};
        const merged = {};   // "category|description" -> entry, so the same action's keys show together
        const ranges = {};   // "category|desc-without-number|mods" -> entry, for 1…9
        const flat = [];
        for (const b of binds) {
            if (b.submap && b.submap !== "") continue;              // resize/move modes show their own hint
            if (b.key === "Alt_L" || b.key === "Caps_Lock") continue; // helpers, not shortcuts to learn
            let cat = "Other", desc = b.description || "";
            const m = /^\[([^\]]+)\] (.*)$/.exec(desc);
            if (m) { cat = m[1]; desc = m[2]; }
            if (!desc) desc = b.dispatcher + (b.arg ? " " + b.arg : "");
            const keys = combo(b);
            // "Go to workspace 3" with Super+3: fold 1…9 into one row.
            const num = /^(.*?)(\d)$/.exec(desc);
            if (num && /^\d$/.test(b.key)) {
                const id = cat + "|" + num[1] + "|" + b.modmask;
                if (!ranges[id]) {
                    const e = { category: cat, description: num[1].trim(), keys: [], range: [] };
                    ranges[id] = e;
                    (byCat[cat] = byCat[cat] || []).push(e);
                    flat.push(e);
                }
                ranges[id].range.push(Number(b.key));
                const r = ranges[id].range.sort();
                const k = combo(b);
                k[k.length - 1] = r[0] + "–" + r[r.length - 1];
                ranges[id].keys = [k];
                continue;
            }
            const id = cat + "|" + desc;
            if (merged[id]) { merged[id].keys.push(keys); continue; }
            const e = { category: cat, description: desc, keys: [keys] };
            merged[id] = e;
            (byCat[cat] = byCat[cat] || []).push(e);
            flat.push(e);
        }
        const cats = [];
        for (const name of order)
            if (byCat[name]) cats.push({ name: name, entries: byCat[name] });
        for (const name in byCat)
            if (order.indexOf(name) < 0) cats.push({ name: name, entries: byCat[name] });
        categories = cats;
        all = flat;
    }

    // "screenshot" finds the Screenshots entries; "super e" finds Super+E.
    function search(text) {
        const words = text.toLowerCase().split(/\s+/).filter(w => w);
        if (!words.length) return all;
        return all.filter(e => {
            const hay = (e.category + " " + e.description + " " + e.keys.map(k => k.join(" ")).join(" ")).toLowerCase();
            return words.every(w => hay.indexOf(w) >= 0);
        });
    }

    function refresh() { reader.running = true; }

    Process {
        id: reader
        command: ["hyprctl", "binds", "-j"]
        running: true
        stdout: StdioCollector { onStreamFinished: root.parse(text) }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "configreloaded") root.refresh();
        }
    }
}
