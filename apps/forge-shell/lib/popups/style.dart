// What every Forge popup shares: the card it sits on, its icons by name,
// and the little pieces (menu rows, buttons, fields) they're built from.
import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

/// Icons that callers (forge-dialog, the dock...) can name in JSON.
const popupIcons = <String, IconData>{
  'info': Icons.info_rounded,
  'warning': Icons.warning_amber_rounded,
  'error': Icons.error_rounded,
  'question': Icons.help_rounded,
  'lock': Icons.lock_rounded,
  'power': Icons.power_settings_new_rounded,
  'restart': Icons.restart_alt_rounded,
  'logout': Icons.logout_rounded,
  'sleep': Icons.bedtime_rounded,
  'pin': Icons.push_pin_rounded,
  'unpin': Icons.push_pin_outlined,
  'close': Icons.close_rounded,
  'window': Icons.web_asset_rounded,
  'new': Icons.add_rounded,
  'terminal': Icons.terminal_rounded,
  'files': Icons.folder_rounded,
  'wallpaper': Icons.wallpaper_rounded,
  'appearance': Icons.palette_rounded,
  'settings': Icons.settings_rounded,
  'apps': Icons.apps_rounded,
  'search': Icons.search_rounded,
  'trash': Icons.delete_rounded,
  'download': Icons.download_rounded,
  'check': Icons.check_rounded,
  'star': Icons.star_rounded,
  'minimize': Icons.minimize_rounded,
  'maximize': Icons.crop_square_rounded,
};

/// The surface of a popup. The compositor doesn't frost the popups part
/// (it's a whole-screen layer), so it's nearly solid, tinted as the theme.
class PopupCard extends StatelessWidget {
  const PopupCard({
    super.key,
    required this.palette,
    required this.child,
    this.width,
    this.padding = const EdgeInsets.all(8),
    this.radius,
  });

  final ForgePalette palette;
  final Widget child;
  final double? width;
  final EdgeInsets padding;
  final double? radius;

  static Color colour(ForgePalette p) =>
      p.surface.a < 0.94 ? p.surface.withValues(alpha: 0.94) : p.surface;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Container(
      width: width,
      padding: padding,
      decoration: BoxDecoration(
        color: colour(p),
        borderRadius: BorderRadius.circular(
          radius ?? p.cornerRadius.clamp(10, 22).toDouble(),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: p.dark ? 0.45 : 0.18),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Material(type: MaterialType.transparency, child: child),
    );
  }
}

/// Comes in with a quick fade and scale, from [origin].
class PopIn extends StatelessWidget {
  const PopIn({
    super.key,
    required this.child,
    this.origin = Alignment.topCenter,
  });

  final Widget child;
  final Alignment origin;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.scale(
          scale: 0.96 + 0.04 * t,
          alignment: origin,
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// A button in a dialog: the accent for the main choice, red for a
/// destructive one, quiet otherwise.
class DialogButton extends StatelessWidget {
  const DialogButton({
    super.key,
    required this.palette,
    required this.label,
    required this.onTap,
    this.primary = false,
    this.danger = false,
    this.icon,
  });

  final ForgePalette palette;
  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final bool danger;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final bg = danger
        ? p.negative
        : primary
        ? p.accent
        : p.hover;
    final fg = danger || primary ? Colors.white : p.text;
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: fg),
                  const SizedBox(width: 7),
                ],
                Text(
                  label,
                  style: TextStyle(
                    color: fg,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A rounded text field in the Forge look.
class ForgeField extends StatelessWidget {
  const ForgeField({
    super.key,
    required this.palette,
    required this.controller,
    this.focusNode,
    this.hint,
    this.password = false,
    this.autofocus = false,
    this.onSubmitted,
    this.onChanged,
    this.icon,
    this.error = false,
  });

  final ForgePalette palette;
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String? hint;
  final bool password;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final IconData? icon;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    OutlineInputBorder border(Color c, double w) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: c, width: w),
    );
    return TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      obscureText: password,
      onSubmitted: onSubmitted,
      onChanged: onChanged,
      style: TextStyle(color: p.text, fontSize: 14),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: p.hover,
        hintText: hint,
        hintStyle: TextStyle(color: p.dimText, fontSize: 14),
        prefixIcon: icon == null
            ? null
            : Icon(icon, size: 18, color: p.dimText),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        enabledBorder: border(
          error ? p.negative : Colors.transparent,
          error ? 1.5 : 0,
        ),
        focusedBorder: border(error ? p.negative : p.accent, 1.5),
      ),
    );
  }
}
