# Forge Shot

Forge OS's screenshot tool, on the Print keys in place of Spectacle (which
stays, for screen recording).

| Keys | Does |
|---|---|
| Print, Meta+Shift+S | an area: drag on the frozen screen |
| Shift+Print | the whole screen |
| Meta+Print | a window: KWin asks you to click one |

**Choosing an area.** The screen freezes as it was when the key was pressed;
drag to select (a loupe shows the pixels and their position), then adjust:
drag the handles or the selection, arrows nudge it (Shift: 10px), Ctrl+A
takes everything. Enter or a double-click saves and copies it; the toolbar,
or its keys, copies (Ctrl+C), saves (Ctrl+S), annotates (E) or copies the
text in it (T). Esc cancels.

**Afterwards** a thumbnail sits in the bottom-right corner for a few
seconds (longer while the pointer is on it): annotate, copy, show in the
folder, delete. Screenshots go to `~/Pictures/Screenshots` (the Pictures
folder from `xdg-user-dir`), named by date and time.

**The editor** (`forge-shot edit FILE`): arrow A, box R, ellipse O, line L,
pen P, highlighter H, text T, pixelate (to hide things) B, numbered steps N,
crop C; eight colours, three widths; Ctrl+Z / Ctrl+Shift+Z; copy, copy the
text, save (over the file if it's in the Screenshots folder), save as.

```sh
forge-shot                 # an area (forge-shot region)
forge-shot full            # the whole screen
forge-shot window          # a window
forge-shot --delay 5 full  # wait first
forge-shot edit FILE       # mark up an image
```

How it works: each run takes the screenshot first, in the GTK runner
(`linux/runner/capture.cc`, KWin's `org.kde.KWin.ScreenShot2`, which needs
the desktop file's `X-KDE-DBUS-Restricted-Interfaces` and an `Exec` naming
the real binary), then starts Flutter. The area picker is a full-screen
layer-shell surface that turns into the thumbnail; the editor is a separate
run, in an ordinary window. Copying goes through `wl-copy` (it keeps the
clipboard after Forge Shot quits); text recognition through tesseract.

Build: `flutter build linux --release --no-tree-shake-icons` (tree-shaking
the icon font dropped most of the app's icons).
