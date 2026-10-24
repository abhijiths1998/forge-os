// Building blocks shared by the store's pages.
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'palette.dart';
import 'pamac.dart';

/// The app's AppStream icon if it has one, else the package name (or a
/// generic package icon) from the desktop's icon theme.
class PackageIcon extends StatelessWidget {
  const PackageIcon(this.pkg, {super.key, this.size = 48});

  final Package pkg;
  final double size;

  /// AppStream icons are JPEG XL, so they go through the runner too.
  Future<Uint8List?> _load() async {
    final px = size.round();
    if (pkg.icon.startsWith('/')) {
      final file = await Pamac.icon(pkg.icon, size: px);
      if (file != null) return file;
    }
    return Pamac.icon(pkg.name, size: px);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: FutureBuilder<Uint8List?>(
        future: _load(),
        builder: (context, snap) => snap.data == null
            ? const SizedBox()
            : Image.memory(snap.data!,
                width: size, height: size, filterQuality: FilterQuality.medium),
      ),
    );
  }
}

/// Install / Open / Update / Remove for one package, or its place in the
/// queue while a transaction is pending.
class PackageButton extends StatelessWidget {
  const PackageButton({
    super.key,
    required this.pkg,
    required this.tx,
    required this.palette,
    this.showRemove = false,
  });

  final Package pkg;
  final Transactions tx;
  final Palette palette;
  final bool showRemove;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    if (tx.pending(pkg.name)) {
      return _Pill(
        label: tx.current?.args.contains(pkg.name) ?? false
            ? 'Working…'
            : 'Queued',
        color: p.hover,
        textColor: p.dimText,
      );
    }
    if (!pkg.installed) {
      return _Pill(
        label: 'Install',
        color: p.accent,
        textColor: p.onAccent,
        onTap: () => tx.add(Job('Installing ${pkg.title}',
            [pkg.aur ? 'build' : 'install', pkg.name])),
      );
    }
    final buttons = <Widget>[
      // Only AUR packages update one at a time. A repo package updated on
      // its own would be a partial upgrade, which Arch doesn't support:
      // those go through "Update all" (pamac upgrade).
      if (pkg.hasUpdate && pkg.aur)
        _Pill(
          label: 'Update',
          color: p.accent,
          textColor: p.onAccent,
          onTap: () => tx.add(Job('Updating ${pkg.title}',
              [pkg.aur ? 'build' : 'install', pkg.name])),
        )
      else if (pkg.launchable.isNotEmpty)
        _Pill(
          label: 'Open',
          color: p.hover,
          textColor: p.text,
          onTap: () => Pamac.launch(pkg.launchable),
        ),
      if (showRemove || (pkg.launchable.isEmpty && !pkg.hasUpdate))
        _Pill(
          label: 'Remove',
          color: p.hover,
          textColor: p.negative,
          onTap: () =>
              tx.add(Job('Removing ${pkg.title}', ['remove', pkg.name])),
        ),
    ];
    return Wrap(spacing: 8, children: buttons);
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.color,
    required this.textColor,
    this.onTap,
  });

  final String label;
  final Color color;
  final Color textColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          child: Text(label,
              style: TextStyle(
                  color: textColor, fontWeight: FontWeight.w600, fontSize: 13)),
        ),
      ),
    );
  }
}

/// A rounded translucent panel, the store's basic surface.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.palette,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
  });

  final Palette palette;
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: palette.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        // No outline: the glass runs to the edge.
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        hoverColor: palette.hover,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Grid of app cards (Discover, categories).
class AppGrid extends StatelessWidget {
  const AppGrid({
    super.key,
    required this.packages,
    required this.palette,
    required this.tx,
    required this.onOpen,
  });

  final List<Package> packages;
  final Palette palette;
  final Transactions tx;
  final void Function(Package) onOpen;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return SliverGrid.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 340,
        mainAxisExtent: 128,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
      ),
      itemCount: packages.length,
      itemBuilder: (context, i) {
        final pkg = packages[i];
        return GlassCard(
          palette: p,
          onTap: () => onOpen(pkg),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PackageIcon(pkg, size: 56),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(pkg.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: p.text)),
                    const SizedBox(height: 2),
                    Expanded(
                      child: Text(pkg.desc,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12.5, color: p.dimText)),
                    ),
                    PackageButton(pkg: pkg, tx: tx, palette: p),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Rows of packages (search, installed, updates).
class PackageRows extends StatelessWidget {
  const PackageRows({
    super.key,
    required this.packages,
    required this.palette,
    required this.tx,
    required this.onOpen,
    this.showRemove = false,
    this.showUpgrade = false,
  });

  final List<Package> packages;
  final Palette palette;
  final Transactions tx;
  final void Function(Package) onOpen;
  final bool showRemove;
  final bool showUpgrade;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return SliverList.separated(
      itemCount: packages.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, i) {
        final pkg = packages[i];
        final version = showUpgrade
            ? '${pkg.installedVersion}  →  ${pkg.version}'
            : pkg.installed
                ? pkg.installedVersion
                : pkg.version;
        return GlassCard(
          palette: p,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          onTap: () => onOpen(pkg),
          child: Row(
            children: [
              PackageIcon(pkg, size: 36),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(
                        child: Text(pkg.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: p.text)),
                      ),
                      const SizedBox(width: 8),
                      Tag(pkg.aur ? 'AUR' : pkg.repo, palette: p),
                    ]),
                    Text(pkg.desc,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: p.dimText)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(version, style: TextStyle(fontSize: 12, color: p.dimText)),
              const SizedBox(width: 14),
              PackageButton(
                  pkg: pkg, tx: tx, palette: p, showRemove: showRemove),
            ],
          ),
        );
      },
    );
  }
}

class Tag extends StatelessWidget {
  const Tag(this.label, {super.key, required this.palette});

  final String label;
  final Palette palette;

  @override
  Widget build(BuildContext context) {
    if (label.isEmpty) return const SizedBox();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        color: palette.accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11,
              color: palette.accent,
              fontWeight: FontWeight.w600)),
    );
  }
}

/// A page heading with an optional trailing widget.
class Heading extends StatelessWidget {
  const Heading(this.text,
      {super.key, required this.palette, this.subtitle, this.trailing});

  final String text;
  final String? subtitle;
  final Palette palette;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text,
                    style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: palette.text)),
                if (subtitle != null)
                  Text(subtitle!,
                      style: TextStyle(fontSize: 13, color: palette.dimText)),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Spinner, empty state or error, centred in the page.
class PageMessage extends StatelessWidget {
  const PageMessage(
      {super.key, required this.palette, this.text, this.loading = false});

  final Palette palette;
  final String? text;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: loading
            ? CircularProgressIndicator(color: palette.accent, strokeWidth: 3)
            : Text(text ?? '',
                style: TextStyle(color: palette.dimText, fontSize: 14)),
      ),
    );
  }
}
