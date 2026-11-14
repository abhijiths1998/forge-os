// Forge Files' state: where we are, what's there, what's selected, the
// clipboard, and every action the UI can take on them.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'fs.dart';

enum ViewMode { grid, list }

class FilesController extends ChangeNotifier {
  FilesController(String start, {String? select}) {
    _loadSettings();
    _go(start, record: false, select: select);
    _drivesTimer = Timer.periodic(const Duration(seconds: 4), (_) => refreshDrives());
    refreshDrives();
  }

  // ------------------------------------------------------------ where we are
  String path = home;
  final List<String> _back = [];
  final List<String> _forward = [];
  bool get canBack => _back.isNotEmpty;
  bool get canForward => _forward.isNotEmpty;
  bool get inTrash => path == trashFolder;
  bool get canUp => !inTrash && path != '/';

  List<Entry> _all = [];
  List<Entry> entries = [];
  bool loading = false;
  String? error; // the folder couldn't be read
  (int, int)? space;

  // ------------------------------------------------------------ view
  ViewMode view = ViewMode.grid;
  SortBy sortBy = SortBy.name;
  bool descending = false;
  bool showHidden = false;
  double zoom = 1;

  // ------------------------------------------------------------ selection
  final Set<String> selected = {};
  int? anchor; // where a Shift-selection starts
  int? cursor; // the keyboard's position

  List<Entry> get selection => [for (final e in entries) if (selected.contains(e.path)) e];

  // ------------------------------------------------------------ search
  String query = '';
  bool searching = false;
  StreamSubscription<Entry>? _search;

  // ------------------------------------------------------------ clipboard
  static List<String> _clip = [];
  static bool _clipCut = false;
  bool get canPaste => _clip.isNotEmpty;
  bool isCut(String p) => _clipCut && _clip.contains(p);

  // ------------------------------------------------------------ messages
  String? toast;
  bool toastIsError = false;
  Timer? _toastTimer;
  String? busy; // "Copying 3 items…"

  List<Drive> drives = [];
  Timer? _drivesTimer;
  StreamSubscription<FileSystemEvent>? _watch;
  Timer? _reloadDebounce;

  @override
  void dispose() {
    _drivesTimer?.cancel();
    _watch?.cancel();
    _search?.cancel();
    _toastTimer?.cancel();
    _reloadDebounce?.cancel();
    super.dispose();
  }

  // ------------------------------------------------------------ navigation

  void go(String to) => _go(to);

  Future<void> _go(String to, {bool record = true, String? select}) async {
    if (to != trashFolder) {
      to = to.length > 1 && to.endsWith('/') ? to.substring(0, to.length - 1) : to;
      if (to.startsWith('~')) to = '$home${to.substring(1)}';
      if (!Directory(to).existsSync()) {
        say('"$to" isn\'t there', error: true);
        return;
      }
    }
    if (record && to != path) {
      _back.add(path);
      _forward.clear();
    }
    _cancelSearch();
    path = to;
    selected.clear();
    anchor = null;
    cursor = null;
    await reload();
    if (select != null) {
      final i = entries.indexWhere((e) => e.path == select);
      if (i >= 0) {
        selected.add(select);
        cursor = anchor = i;
      }
    }
    _watchFolder();
    notifyListeners();
  }

  void back() {
    if (_back.isEmpty) return;
    _forward.add(path);
    _go(_back.removeLast(), record: false);
  }

  void forward() {
    if (_forward.isEmpty) return;
    _back.add(path);
    _go(_forward.removeLast(), record: false);
  }

  void up() {
    if (!canUp) return;
    _go(dirname(path), select: path);
  }

  Future<void> reload() async {
    loading = true;
    notifyListeners();
    try {
      _all = await listFolder(path);
      error = null;
    } on FileSystemException catch (e) {
      _all = [];
      error = e.osError?.errorCode == 13 ? 'You don\'t have permission to see this folder' : (e.osError?.message ?? e.message);
    }
    space = inTrash ? null : await diskSpace(path);
    loading = false;
    _apply();
  }

  void _watchFolder() {
    _watch?.cancel();
    if (inTrash) return;
    try {
      _watch = Directory(path).watch().listen((_) {
        _reloadDebounce?.cancel();
        _reloadDebounce = Timer(const Duration(milliseconds: 250), () {
          if (!searching) reload();
        });
      }, onError: (_) {});
    } catch (_) {}
  }

  /// Hidden files, sort and search applied to the listing.
  void _apply() {
    if (searching) return;
    final list = [for (final e in _all) if (showHidden || !e.hidden) e];
    sortEntries(list, sortBy, descending);
    entries = list;
    selected.removeWhere((p) => !entries.any((e) => e.path == p));
    if (cursor != null && cursor! >= entries.length) cursor = entries.isEmpty ? null : entries.length - 1;
    notifyListeners();
  }

  void setView(ViewMode v) {
    view = v;
    _saveSettings();
    notifyListeners();
  }

  void setSort(SortBy by) {
    if (sortBy == by) {
      descending = !descending;
    } else {
      sortBy = by;
      descending = by == SortBy.modified || by == SortBy.size; // newest/biggest first
    }
    _saveSettings();
    if (searching) {
      sortEntries(entries, sortBy, descending);
      notifyListeners();
    } else {
      _apply();
    }
  }

  void toggleHidden() {
    showHidden = !showHidden;
    _saveSettings();
    _apply();
  }

  void zoomBy(double by) {
    zoom = (zoom + by).clamp(0.6, 2.0);
    _saveSettings();
    notifyListeners();
  }

  // ------------------------------------------------------------ search

  void setQuery(String q) {
    query = q;
    _cancelSearch();
    if (q.trim().isEmpty) {
      _apply();
      return;
    }
    if (inTrash) {
      entries = [for (final e in _all) if (e.name.toLowerCase().contains(q.toLowerCase())) e];
      notifyListeners();
      return;
    }
    searching = true;
    entries = [];
    selected.clear();
    cursor = null;
    notifyListeners();
    _search = search(path, q.trim(), hidden: showHidden).listen((e) {
      entries.add(e);
      _searchTick();
    }, onDone: () {
      sortEntries(entries, sortBy, descending);
      notifyListeners();
    });
  }

  Timer? _tick;
  void _searchTick() {
    _tick ??= Timer(const Duration(milliseconds: 120), () {
      _tick = null;
      notifyListeners();
    });
  }

  void _cancelSearch() {
    _search?.cancel();
    _search = null;
    if (searching) {
      searching = false;
      query = '';
    }
  }

  void clearSearch() {
    _cancelSearch();
    query = '';
    _apply();
  }

  // ------------------------------------------------------------ selection

  void click(int i, {bool ctrl = false, bool shift = false}) {
    final p = entries[i].path;
    if (shift && anchor != null) {
      if (!ctrl) selected.clear();
      final (a, b) = anchor! < i ? (anchor!, i) : (i, anchor!);
      for (var k = a; k <= b; k++) {
        selected.add(entries[k].path);
      }
    } else if (ctrl) {
      selected.contains(p) ? selected.remove(p) : selected.add(p);
      anchor = i;
    } else {
      selected
        ..clear()
        ..add(p);
      anchor = i;
    }
    cursor = i;
    notifyListeners();
  }

  /// A right-click on an item: it joins the selection, or becomes it.
  void ensureSelected(int i) {
    if (!selected.contains(entries[i].path)) click(i);
  }

  void clearSelection() {
    selected.clear();
    anchor = null;
    notifyListeners();
  }

  void selectAll() {
    selected.addAll(entries.map((e) => e.path));
    notifyListeners();
  }

  void moveCursor(int by, {bool shift = false}) {
    if (entries.isEmpty) return;
    final to = ((cursor ?? (by > 0 ? -1 : entries.length)) + by).clamp(0, entries.length - 1);
    click(to, shift: shift);
  }

  // Type to jump: letters typed quickly find the first name starting so.
  String _typed = '';
  Timer? _typedTimer;
  void typeAhead(String ch) {
    _typedTimer?.cancel();
    _typed += ch.toLowerCase();
    _typedTimer = Timer(const Duration(milliseconds: 900), () => _typed = '');
    final i = entries.indexWhere((e) => e.name.toLowerCase().startsWith(_typed));
    if (i >= 0) click(i);
  }

  // ------------------------------------------------------------ open

  Future<void> open(Entry e) async {
    if (e.isDir) {
      go(e.path);
      return;
    }
    if (inTrash) {
      say('Restore it first to open it');
      return;
    }
    final err = await openFile(e.path);
    if (err != null) say(err.isEmpty ? 'Nothing here opens ${e.name}' : err, error: true);
  }

  void openSelection() {
    final s = selection;
    if (s.length == 1) {
      open(s.first);
    } else {
      for (final e in s.where((e) => !e.isDir)) {
        openFile(e.path);
      }
    }
  }

  // ------------------------------------------------------------ clipboard

  void copy({bool cut = false}) {
    if (selected.isEmpty || inTrash) return;
    _clip = selected.toList();
    _clipCut = cut;
    // Other apps get the paths as text.
    Clipboard.setData(ClipboardData(text: _clip.join('\n')));
    say('${cut ? 'Cut' : 'Copied'} ${_count(_clip.length)}');
    notifyListeners();
  }

  Future<void> paste() async {
    if (inTrash) return;
    var paths = _clip;
    var cut = _clipCut;
    if (paths.isEmpty) {
      // Paths or file:// URIs copied in another app.
      final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
      paths = [
        for (final l in const LineSplitter().convert(text))
          if (l.trim().startsWith('file://'))
            Uri.parse(l.trim()).toFilePath()
          else if (l.trim().startsWith('/') && FileSystemEntity.typeSync(l.trim()) != FileSystemEntityType.notFound)
            l.trim(),
      ];
      cut = false;
    }
    if (paths.isEmpty) return;
    await _transfer(paths, path, move: cut);
    if (cut) _clip = [];
  }

  Future<void> drop(List<String> paths, String dir, {required bool copy}) async {
    if (paths.isEmpty || paths.contains(dir)) return;
    if (dir == trashFolder) {
      await moveToTrash(paths);
      return;
    }
    // Across drives a drop copies, as everywhere else.
    var move = !copy;
    if (move) {
      final r = await Process.run('stat', ['-c', '%d', paths.first, dir]);
      final devs = (r.stdout as String).trim().split('\n');
      if (devs.length == 2 && devs[0] != devs[1]) move = false;
    }
    await _transfer(paths, dir, move: move);
  }

  Future<void> _transfer(List<String> paths, String dir, {required bool move}) async {
    busy = '${move ? 'Moving' : 'Copying'} ${_count(paths.length)}…';
    notifyListeners();
    final err = await transfer(paths, dir, move: move);
    busy = null;
    if (err != null) {
      say(err, error: true);
    } else {
      say('${move ? 'Moved' : 'Copied'} ${_count(paths.length)} to ${basename(dir)}');
    }
    await reload();
  }

  // ------------------------------------------------------------ changes

  Future<void> moveToTrash([List<String>? paths]) async {
    final list = paths ?? selected.toList();
    if (list.isEmpty) return;
    if (inTrash) return;
    final err = await trash(list);
    if (err != null) {
      say(err, error: true);
    } else {
      say('Moved ${_count(list.length)} to the trash');
    }
    await reload();
  }

  Future<void> deleteSelected() async {
    final list = selected.toList();
    if (list.isEmpty) return;
    final err = await deleteForever(list);
    if (err != null) say(err, error: true);
    await reload();
  }

  Future<void> restoreSelected() async {
    final err = await restore(selection);
    if (err != null) {
      say(err, error: true);
    } else {
      say('Restored ${_count(selected.length)}');
    }
    await reload();
  }

  Future<void> empty() async {
    await emptyTrash();
    say('The trash is empty');
    await reload();
  }

  Future<String?> renameEntry(Entry e, String name) async {
    final err = await rename(e.path, name);
    if (err == null) {
      await reload();
      final i = entries.indexWhere((x) => x.path == join(dirname(e.path), name));
      if (i >= 0) click(i);
    }
    return err;
  }

  Future<String?> createNew(String name, {required bool folder}) async {
    final (made, err) = await create(path, name, folder: folder);
    if (made != null) {
      await reload();
      final i = entries.indexWhere((x) => x.path == made);
      if (i >= 0) click(i);
    }
    return err;
  }

  // ------------------------------------------------------------ drives

  Future<void> refreshDrives() async {
    final d = await listDrives();
    if (d.map((x) => '${x.device}${x.mountpoint}').join() != drives.map((x) => '${x.device}${x.mountpoint}').join()) {
      drives = d;
      // The drive we were looking at went away.
      if (!inTrash && !Directory(path).existsSync()) {
        _go(home);
      }
      notifyListeners();
    }
  }

  Future<void> openDrive(Drive d) async {
    if (d.mounted) {
      go(d.mountpoint!);
      return;
    }
    busy = 'Mounting ${d.label}…';
    notifyListeners();
    final (at, err) = await mount(d);
    busy = null;
    await refreshDrives();
    if (err != null) {
      say(err, error: true);
    } else if (at != null) {
      go(at);
    }
    notifyListeners();
  }

  Future<void> ejectDrive(Drive d) async {
    if (d.mounted && (path == d.mountpoint || path.startsWith('${d.mountpoint}/'))) go(home);
    final err = await unmount(d, eject: d.removable);
    if (err != null) {
      say(err, error: true);
    } else {
      say(d.removable ? '${d.label} can be unplugged' : '${d.label} unmounted');
    }
    await refreshDrives();
  }

  // ------------------------------------------------------------ messages

  void say(String text, {bool error = false}) {
    toast = text;
    toastIsError = error;
    _toastTimer?.cancel();
    _toastTimer = Timer(Duration(seconds: error ? 6 : 3), () {
      toast = null;
      notifyListeners();
    });
    notifyListeners();
  }

  static String _count(int n) => n == 1 ? '1 item' : '$n items';

  // ------------------------------------------------------------ settings

  static File get _settings =>
      File('${Platform.environment['XDG_CONFIG_HOME'] ?? '$home/.config'}/forge/files.json');

  void _loadSettings() {
    try {
      final j = jsonDecode(_settings.readAsStringSync()) as Map<String, dynamic>;
      view = ViewMode.values.asNameMap()[j['view']] ?? ViewMode.grid;
      sortBy = SortBy.values.asNameMap()[j['sortBy']] ?? SortBy.name;
      descending = j['descending'] as bool? ?? false;
      showHidden = j['showHidden'] as bool? ?? false;
      zoom = (j['zoom'] as num?)?.toDouble() ?? 1;
    } catch (_) {}
  }

  void _saveSettings() {
    try {
      _settings.parent.createSync(recursive: true);
      _settings.writeAsStringSync(jsonEncode({
        'view': view.name,
        'sortBy': sortBy.name,
        'descending': descending,
        'showHidden': showHidden,
        'zoom': zoom,
      }));
    } catch (_) {}
  }
}
