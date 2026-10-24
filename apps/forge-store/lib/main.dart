// Forge Store: browse, install, update and remove software (repos,
// Chaotic-AUR and, when pamac has it on, the AUR) in a Forge Glass window.
// libpamac answers the queries; the pamac CLI runs the transactions.
import 'dart:async';

import 'package:flutter/material.dart';

import 'pages.dart';
import 'palette.dart';
import 'pamac.dart';
import 'widgets.dart';

void main(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();
  String? arg(String flag) {
    final i = args.indexOf(flag);
    return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  }

  // `forge-store --search <words>` opens with a search (the launcher's
  // "install <pkg>" uses it), `--page updates|installed` on that page and
  // `--details <pkg>` on a package.
  final i = args.indexOf('--search');
  runApp(StoreApp(
    initialQuery: i >= 0 ? args.skip(i + 1).join(' ') : '',
    initialPage: arg('--page'),
    initialDetails: arg('--details'),
  ));
}

enum Section { discover, category, search, installed, updates }

class StoreApp extends StatefulWidget {
  const StoreApp(
      {super.key, this.initialQuery = '', this.initialPage, this.initialDetails});

  final String initialQuery;
  final String? initialPage;
  final String? initialDetails;

  @override
  State<StoreApp> createState() => _StoreAppState();
}

class _StoreAppState extends State<StoreApp> {
  final _palette = Palette.current();
  final _tx = Transactions();
  final _search = TextEditingController();
  Timer? _debounce;

  Section _section = Section.discover;
  String _category = '';
  String _query = '';
  Package? _details;
  bool _aur = false;
  int _updates = 0;

  @override
  void initState() {
    super.initState();
    Pamac.aurEnabled().then((v) => setState(() => _aur = v));
    _tx.addListener(() => setState(() {}));
    _countUpdates();
    if (widget.initialQuery.isNotEmpty) {
      _search.text = widget.initialQuery;
      _section = Section.search;
      _query = widget.initialQuery;
    }
    _section = switch (widget.initialPage) {
      'updates' => Section.updates,
      'installed' => Section.installed,
      _ => _section,
    };
    final name = widget.initialDetails;
    if (name != null) {
      Pamac.search(name).then((pkgs) {
        final match = pkgs.where((p) => p.name == name);
        if (match.isNotEmpty && mounted) setState(() => _details = match.first);
      });
    }
  }

  Future<void> _countUpdates() async {
    try {
      final u = await Pamac.updates();
      if (mounted) setState(() => _updates = u.repos.length + u.aur.length);
    } catch (_) {}
  }

  void _go(Section s, {String category = ''}) {
    setState(() {
      _section = s;
      _category = category;
      _details = null;
      if (s != Section.search) _search.clear();
    });
  }

  void _onSearch(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      final q = text.trim();
      if (q.length < 2) {
        if (_section == Section.search) _go(Section.discover);
        return;
      }
      setState(() {
        _section = Section.search;
        _query = q;
        _details = null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = _palette;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Forge Store',
      color: Colors.transparent,
      theme: p.materialTheme(),
      home: Scaffold(
        backgroundColor: p.window,
        body: Row(
          children: [
            _sidebar(p),
            VerticalDivider(width: 1, thickness: 1, color: p.rim),
            Expanded(
              child: Column(
                children: [
                  _topBar(p),
                  Expanded(child: _page(p)),
                  _ActivityBar(tx: _tx, palette: p),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _page(Palette p) {
    void open(Package pkg) => setState(() => _details = pkg);
    if (_details != null) {
      return DetailsPage(
        key: ValueKey('details:${_details!.name}'),
        pkg: _details!,
        palette: p,
        tx: _tx,
        onBack: () => setState(() => _details = null),
      );
    }
    switch (_section) {
      case Section.discover:
        return DiscoverPage(palette: p, tx: _tx, onOpen: open);
      case Section.category:
        return DiscoverPage(
            palette: p, tx: _tx, onOpen: open, category: _category);
      case Section.search:
        return SearchPage(
            palette: p, tx: _tx, onOpen: open, query: _query, aur: _aur);
      case Section.installed:
        return InstalledPage(palette: p, tx: _tx, onOpen: open);
      case Section.updates:
        return UpdatesPage(
          palette: p,
          tx: _tx,
          onOpen: open,
          aur: _aur,
          onCount: (n) => WidgetsBinding.instance.addPostFrameCallback(
              (_) => mounted ? setState(() => _updates = n) : null),
        );
    }
  }

  Widget _topBar(Palette p) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 18, 28, 0),
      child: TextField(
        controller: _search,
        onChanged: _onSearch,
        onSubmitted: _onSearch,
        style: TextStyle(color: p.text, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Search apps and packages',
          hintStyle: TextStyle(color: p.dimText),
          prefixIcon: Icon(Icons.search_rounded, color: p.dimText),
          filled: true,
          fillColor: p.card,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: p.rim),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: p.accent, width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _sidebar(Palette p) {
    Widget item(String label, IconData icon, bool selected, VoidCallback onTap,
        {int badge = 0}) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
        child: Material(
          color: selected ? p.accent.withValues(alpha: 0.88) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            hoverColor: p.hover,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                children: [
                  Icon(icon,
                      size: 19, color: selected ? p.onAccent : p.dimText),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.w500,
                            color: selected ? p.onAccent : p.text)),
                  ),
                  if (badge > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 1),
                      decoration: BoxDecoration(
                        color: selected ? p.onAccent : p.accent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('$badge',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: selected ? p.accent : p.onAccent)),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final none = _details == null;
    return Container(
      width: 236,
      color: p.sidebar,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 18),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
            child: Row(children: [
              Image.asset('assets/forge-os-emblem.png', width: 26, height: 26),
              const SizedBox(width: 10),
              Text('Forge Store',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: p.text)),
            ]),
          ),
          item('Discover', Icons.auto_awesome_rounded,
              none && _section == Section.discover, () => _go(Section.discover)),
          item('Installed', Icons.inventory_2_rounded,
              none && _section == Section.installed,
              () => _go(Section.installed)),
          item('Updates', Icons.system_update_alt_rounded,
              none && _section == Section.updates, () => _go(Section.updates),
              badge: _updates),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 6),
            child: Text('CATEGORIES',
                style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w700,
                    color: p.dimText)),
          ),
          for (final (name, icon) in categories)
            item(name, icon,
                none && _section == Section.category && _category == name,
                () => _go(Section.category, category: name)),
        ],
      ),
    );
  }
}

/// The running transaction: what it is, pamac's latest line, and the full
/// log on demand. Shows the last result for a while after it's done.
class _ActivityBar extends StatefulWidget {
  const _ActivityBar({required this.tx, required this.palette});

  final Transactions tx;
  final Palette palette;

  @override
  State<_ActivityBar> createState() => _ActivityBarState();
}

class _ActivityBarState extends State<_ActivityBar> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final tx = widget.tx;
    final job = tx.current ?? tx.lastJob;
    if (job == null) return const SizedBox();
    final running = tx.current != null;
    final status = running
        ? (tx.log.isNotEmpty ? tx.log.last : 'Starting…')
        : tx.lastOk
            ? 'Done'
            : 'Failed — open the log for details';
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: GlassCard(
        palette: p,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        onTap: () => setState(() => _expanded = !_expanded),
        child: Column(
          children: [
            Row(
              children: [
                if (running)
                  SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.4, color: p.accent),
                  )
                else
                  Icon(tx.lastOk ? Icons.check_circle_rounded : Icons.error_rounded,
                      size: 20, color: tx.lastOk ? p.positive : p.negative),
                const SizedBox(width: 12),
                Text(job.title,
                    style: TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13.5, color: p.text)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: p.dimText)),
                ),
                if (tx.queue.isNotEmpty)
                  Text('${tx.queue.length} queued',
                      style: TextStyle(fontSize: 12, color: p.dimText)),
                Icon(
                    _expanded
                        ? Icons.expand_more_rounded
                        : Icons.expand_less_rounded,
                    color: p.dimText),
              ],
            ),
            if (_expanded)
              Container(
                height: 200,
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: p.dark ? 0.25 : 0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: ListView(
                  reverse: true,
                  children: [
                    for (final line in tx.log.reversed)
                      Text(line,
                          style: TextStyle(
                              fontFamily: 'JetBrainsMono Nerd Font',
                              fontSize: 11.5,
                              color: p.text)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
