# Forge Files

Forge OS's file manager, in Flutter on `forge_ui`: Forge Glass, the
desktop's accent on folders and selection, and it follows theme changes.

- Places (home and the XDG folders), GTK bookmarks (shared with file
  dialogs; Ctrl+D or right-click a folder), drives and the trash in the
  sidebar. Drives mount and eject through udisks (Forge's polkit prompt
  asks for a password where it must); system partitions aren't listed.
- Icons or a list (Ctrl+1/2, Ctrl+=/− to size), sorted by name (numbers
  in order), date, size or kind, folders first. Hidden files with Ctrl+H.
- Thumbnails: pictures straight from the file, videos (ffmpeg) and PDFs
  (pdftoppm) rendered once into `~/.cache/forgeos/files/thumbs`.
- Search below the current folder as you type, results as they're found.
- Copy, cut, paste (also paths copied in other apps), drag onto folders,
  breadcrumbs or sidebar places (Ctrl copies; across drives always copies),
  rename (F2), new folder (Ctrl+Shift+N), trash (Delete), delete for good
  (Shift+Delete), restore from the trash, Open with (and make it the
  default), Properties (Alt+Enter), terminal here (F4, Forge Terminal).
- Nothing is overwritten: a name that's taken gets " (2)".
- Keys: Alt+Left/Right/Up, Backspace, arrows, Home/End, Enter, Ctrl+L to
  type a path, Ctrl+F to search, letters to jump to a name.

The file work is done by the system's own tools (`cp -a --reflink=auto`,
`mv -n`, `gio trash/open/launch`, `udisksctl`, `xdg-mime`, `lsblk`, `df`).
Settings: `~/.config/forge/files.json`.

`forge-files [FOLDER | FILE | trash:///]`: a file opens its folder with it
selected.

Build: `flutter build linux --release --no-tree-shake-icons`; try it with
`utils/dev-install-app.sh forge-files`.
