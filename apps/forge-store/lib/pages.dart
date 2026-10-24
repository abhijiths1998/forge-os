// The store's pages: Discover, a category, search results, installed,
// updates and one package's details.
import 'package:flutter/material.dart';

import 'palette.dart';
import 'pamac.dart';
import 'widgets.dart';

/// AppStream categories, as libpamac names them.
const categories = [
  ('Photo & Video', Icons.photo_camera_back_rounded),
  ('Music & Audio', Icons.headphones_rounded),
  ('Productivity', Icons.edit_note_rounded),
  ('Communication & News', Icons.forum_rounded),
  ('Education & Science', Icons.school_rounded),
  ('Games', Icons.sports_esports_rounded),
  ('Utilities', Icons.handyman_rounded),
  ('Development', Icons.code_rounded),
];

/// Loads a list of packages and reloads it after every transaction.
abstract class ListPage extends StatefulWidget {
  const ListPage({
    super.key,
    required this.palette,
    required this.tx,
    required this.onOpen,
  });

  final Palette palette;
  final Transactions tx;
  final void Function(Package) onOpen;
}

abstract class ListPageState<T extends ListPage> extends State<T> {
  Future<List<Package>>? future;
  int _generation = -1;

  Future<List<Package>> load();

  void reload() => setState(() => future = load());

  @override
  void initState() {
    super.initState();
    widget.tx.addListener(_onTx);
    _generation = widget.tx.generation;
    future = load();
  }

  @override
  void dispose() {
    widget.tx.removeListener(_onTx);
    super.dispose();
  }

  void _onTx() {
    if (widget.tx.generation != _generation) {
      _generation = widget.tx.generation;
      reload();
    } else {
      setState(() {}); // queue/progress changed: refresh buttons
    }
  }

  Widget page(List<Widget> slivers) => CustomScrollView(slivers: [
        for (final s in slivers)
          SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 28), sliver: s),
        const SliverToBoxAdapter(child: SizedBox(height: 28)),
      ]);

  Widget body(String title, String? subtitle,
      Widget Function(List<Package>) content,
      {String empty = 'Nothing here', Widget? trailing}) {
    final p = widget.palette;
    return FutureBuilder<List<Package>>(
      future: future,
      builder: (context, snap) {
        final head = SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Heading(title,
                palette: p, subtitle: subtitle, trailing: trailing),
          ),
        );
        if (snap.hasError) {
          return page([head, PageMessage(palette: p, text: '${snap.error}')]);
        }
        if (!snap.hasData) {
          return page([head, PageMessage(palette: p, loading: true)]);
        }
        if (snap.data!.isEmpty) {
          return page([head, PageMessage(palette: p, text: empty)]);
        }
        return page([head, content(snap.data!)]);
      },
    );
  }
}

class DiscoverPage extends ListPage {
  const DiscoverPage({
    super.key,
    required super.palette,
    required super.tx,
    required super.onOpen,
    this.category,
  });

  /// null for Discover (AppStream's featured apps).
  final String? category;

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends ListPageState<DiscoverPage> {
  @override
  Future<List<Package>> load() =>
      Pamac.category(widget.category ?? 'Featured');

  @override
  void didUpdateWidget(DiscoverPage old) {
    super.didUpdateWidget(old);
    if (old.category != widget.category) reload();
  }

  @override
  Widget build(BuildContext context) {
    return body(
      widget.category ?? 'Discover',
      widget.category == null ? 'Hand-picked apps for Forge OS' : null,
      (pkgs) => AppGrid(
          packages: pkgs,
          palette: widget.palette,
          tx: widget.tx,
          onOpen: widget.onOpen),
    );
  }
}

class SearchPage extends ListPage {
  const SearchPage({
    super.key,
    required super.palette,
    required super.tx,
    required super.onOpen,
    required this.query,
    required this.aur,
  });

  final String query;
  final bool aur;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ListPageState<SearchPage> {
  @override
  Future<List<Package>> load() async {
    final q = widget.query.trim();
    final results = await Future.wait([
      Pamac.search(q),
      if (widget.aur) Pamac.searchAur(q),
    ]);
    final repo = results.first;
    final names = {for (final p in repo) p.name};
    // Repos first; AUR entries that a repo already has are left out.
    final aur = results.length > 1
        ? results[1].where((p) => !names.contains(p.name)).toList()
        : <Package>[];
    final ql = q.toLowerCase();
    int rank(Package p) => p.name == ql || p.title.toLowerCase() == ql
        ? 0
        : p.name.startsWith(ql) || p.title.toLowerCase().startsWith(ql)
            ? 1
            : 2;
    repo.sort((a, b) => rank(a).compareTo(rank(b)));
    aur.sort((a, b) => rank(a).compareTo(rank(b)));
    return [...repo, ...aur];
  }

  @override
  void didUpdateWidget(SearchPage old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query) reload();
  }

  @override
  Widget build(BuildContext context) {
    return body(
      'Results for “${widget.query.trim()}”',
      widget.aur ? 'Repos, Chaotic-AUR and AUR' : 'Repos and Chaotic-AUR',
      (pkgs) => PackageRows(
          packages: pkgs,
          palette: widget.palette,
          tx: widget.tx,
          onOpen: widget.onOpen),
      empty: 'No packages match',
    );
  }
}

class InstalledPage extends ListPage {
  const InstalledPage({
    super.key,
    required super.palette,
    required super.tx,
    required super.onOpen,
  });

  @override
  State<InstalledPage> createState() => _InstalledPageState();
}

class _InstalledPageState extends ListPageState<InstalledPage> {
  String _filter = '';

  @override
  Future<List<Package>> load() async {
    final pkgs = await Pamac.installed();
    pkgs.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return pkgs;
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    return body(
      'Installed',
      'Packages you installed (not their dependencies)',
      (pkgs) {
        final f = _filter.toLowerCase();
        final shown = f.isEmpty
            ? pkgs
            : pkgs
                .where((x) =>
                    x.name.contains(f) || x.title.toLowerCase().contains(f))
                .toList();
        return PackageRows(
            packages: shown,
            palette: p,
            tx: widget.tx,
            onOpen: widget.onOpen,
            showRemove: true);
      },
      trailing: SizedBox(
        width: 220,
        child: TextField(
          onChanged: (v) => setState(() => _filter = v),
          style: TextStyle(color: p.text, fontSize: 13),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Filter',
            hintStyle: TextStyle(color: p.dimText),
            prefixIcon: Icon(Icons.filter_list_rounded,
                size: 18, color: p.dimText),
            filled: true,
            fillColor: p.card,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none),
          ),
        ),
      ),
    );
  }
}

class UpdatesPage extends ListPage {
  const UpdatesPage({
    super.key,
    required super.palette,
    required super.tx,
    required super.onOpen,
    required this.aur,
    required this.onCount,
  });

  final bool aur;
  final void Function(int) onCount;

  @override
  State<UpdatesPage> createState() => _UpdatesPageState();
}

class _UpdatesPageState extends ListPageState<UpdatesPage> {
  @override
  Future<List<Package>> load() async {
    final u = await Pamac.updates();
    final all = [...u.repos, ...u.aur];
    widget.onCount(all.length);
    return all;
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final busy = widget.tx.pending('upgrade');
    return body(
      'Updates',
      'System packages${widget.aur ? ' and AUR' : ''}',
      (pkgs) => PackageRows(
          packages: pkgs,
          palette: p,
          tx: widget.tx,
          onOpen: widget.onOpen,
          showUpgrade: true),
      empty: 'Everything is up to date',
      trailing: FilledButton.icon(
        onPressed: busy
            ? null
            : () => widget.tx.add(Job('Updating the system',
                ['upgrade', if (widget.aur) '--aur'])),
        icon: const Icon(Icons.system_update_alt_rounded, size: 18),
        label: Text(busy ? 'Updating…' : 'Update all'),
        style: FilledButton.styleFrom(
          backgroundColor: p.accent,
          foregroundColor: p.onAccent,
          textStyle: const TextStyle(
              fontFamily: fontFamily, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// One package: description, screenshots, details, dependencies.
class DetailsPage extends StatefulWidget {
  const DetailsPage({
    super.key,
    required this.pkg,
    required this.palette,
    required this.tx,
    required this.onBack,
  });

  final Package pkg;
  final Palette palette;
  final Transactions tx;
  final VoidCallback onBack;

  @override
  State<DetailsPage> createState() => _DetailsPageState();
}

class _DetailsPageState extends State<DetailsPage> {
  late Future<Package?> _future = Pamac.details(widget.pkg);
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _generation = widget.tx.generation;
    widget.tx.addListener(_onTx);
  }

  @override
  void dispose() {
    widget.tx.removeListener(_onTx);
    super.dispose();
  }

  void _onTx() {
    setState(() {
      if (widget.tx.generation != _generation) {
        _generation = widget.tx.generation;
        _future = Pamac.details(widget.pkg);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    return FutureBuilder<Package?>(
      future: _future,
      builder: (context, snap) {
        // The list's copy until the full details arrive.
        final pkg = snap.data ?? widget.pkg;
        final shots = pkg.list('screenshots');
        final info = <(String, String)>[
          ('Version', pkg.installed && pkg.hasUpdate
              ? '${pkg.installedVersion} → ${pkg.version}'
              : pkg.installed ? pkg.installedVersion : pkg.version),
          ('Source', pkg.aur ? 'AUR' : pkg.repo),
          ('Download', formatSize(pkg.downloadSize)),
          ('Installed size', formatSize(pkg.installedSize)),
          ('License', pkg.str('license')),
          ('Packager', pkg.str('packager')),
          ('Maintainer', pkg.str('maintainer')),
          ('Built', pkg.str('buildDate')),
          ('Installed on', pkg.str('installDate')),
          ('Out of date since', pkg.str('outOfDate')),
        ].where((e) => e.$2.isNotEmpty).toList();

        return ListView(
          padding: const EdgeInsets.fromLTRB(28, 16, 28, 28),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: widget.onBack,
                icon: Icon(Icons.arrow_back_rounded, color: p.dimText),
                label: Text('Back', style: TextStyle(color: p.dimText)),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                PackageIcon(pkg, size: 88),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(pkg.title,
                          style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              color: p.text)),
                      Text(pkg.desc,
                          style: TextStyle(fontSize: 14, color: p.dimText)),
                      const SizedBox(height: 12),
                      PackageButton(
                          pkg: pkg, tx: widget.tx, palette: p, showRemove: true),
                    ],
                  ),
                ),
              ],
            ),
            if (shots.isNotEmpty) ...[
              const SizedBox(height: 24),
              SizedBox(
                height: 240,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: shots.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (context, i) => ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(shots[i],
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const SizedBox()),
                  ),
                ),
              ),
            ],
            if (pkg.str('longDesc').isNotEmpty) ...[
              const SizedBox(height: 24),
              Text(pkg.str('longDesc'),
                  style: TextStyle(fontSize: 14, height: 1.5, color: p.text)),
            ],
            const SizedBox(height: 24),
            GlassCard(
              palette: p,
              child: Column(
                children: [
                  for (final (label, value) in info)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 160,
                            child: Text(label,
                                style: TextStyle(color: p.dimText, fontSize: 13)),
                          ),
                          Expanded(
                            child: SelectableText(value,
                                style: TextStyle(color: p.text, fontSize: 13)),
                          ),
                        ],
                      ),
                    ),
                  if (pkg.str('url').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(children: [
                        SizedBox(
                          width: 160,
                          child: Text('Website',
                              style: TextStyle(color: p.dimText, fontSize: 13)),
                        ),
                        Expanded(
                          child: SelectableText(pkg.str('url'),
                              style: TextStyle(color: p.accent, fontSize: 13)),
                        ),
                      ]),
                    ),
                ],
              ),
            ),
            for (final (title, key) in [
              ('Depends on', 'depends'),
              ('Optional', 'optdepends'),
              ('Required by', 'requiredBy'),
            ])
              if (pkg.list(key).isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(title,
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: p.text)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final d in pkg.list(key))
                      Chip(
                        label: Text(d,
                            style: TextStyle(fontSize: 12, color: p.text)),
                        backgroundColor: p.card,
                        side: BorderSide(color: p.rim),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ],
          ],
        );
      },
    );
  }
}
