// polkit's password prompt, Forge's way (the runner's polkit_agent.cc does
// the talking to polkit). Shown when an app asks for something that needs
// an administrator: installing software, pkexec, mounting a disk...
import 'package:flutter/material.dart';
import 'package:forge_ui/forge_ui.dart';

import 'style.dart';

class AuthRequest {
  AuthRequest.fromJson(Map<Object?, Object?> m)
    : id = m['id'] as int,
      message = m['message'] as String? ?? '',
      action = m['action'] as String? ?? '',
      program = m['program'] as String? ?? '',
      users = [for (final u in m['users'] as List? ?? const []) u as String];

  final int id;
  final String message;
  final String action;
  final String program;
  final List<String> users;
}

/// What the dialog hears back while it's up.
class AuthState extends ChangeNotifier {
  bool busy = false;
  String? error;
  String? info;

  void failed(String why) {
    busy = false;
    error = why;
    notifyListeners();
  }

  void message(String text, bool isError) {
    if (isError) {
      error = text;
    } else {
      info = text;
    }
    notifyListeners();
  }
}

class AuthCard extends StatefulWidget {
  const AuthCard({
    super.key,
    required this.palette,
    required this.request,
    required this.state,
    required this.onRespond,
    required this.onCancel,
  });

  final ForgePalette palette;
  final AuthRequest request;
  final AuthState state;
  final void Function(String user, String password) onRespond;
  final VoidCallback onCancel;

  @override
  State<AuthCard> createState() => _AuthCardState();
}

class _AuthCardState extends State<AuthCard>
    with SingleTickerProviderStateMixin {
  final _password = TextEditingController();
  final _focus = FocusNode();
  late String _user = widget.request.users.firstOrNull ?? '';
  bool _details = false;
  late final _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_changed);
  }

  void _changed() {
    if (!mounted) return;
    if (widget.state.error != null && !widget.state.busy) {
      _password.clear();
      _shake.forward(from: 0);
      _focus.requestFocus();
    }
    setState(() {});
  }

  @override
  void dispose() {
    widget.state.removeListener(_changed);
    _password.dispose();
    _focus.dispose();
    _shake.dispose();
    super.dispose();
  }

  void _submit() {
    if (widget.state.busy || _password.text.isEmpty) return;
    widget.state
      ..busy = true
      ..error = null
      ..info = null;
    setState(() {});
    widget.onRespond(_user, _password.text);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final r = widget.request;
    final st = widget.state;
    final small = TextStyle(color: p.dimText, fontSize: 12, height: 1.35);

    return AnimatedBuilder(
      animation: _shake,
      builder: (context, child) {
        // A short side-to-side shake for a wrong password.
        final t = _shake.value;
        final dx = t == 0 || t == 1 ? 0.0 : 10 * (1 - t) * _wave(t);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: PopupCard(
        palette: p,
        width: 440,
        padding: const EdgeInsets.fromLTRB(26, 26, 26, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: p.accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(Icons.lock_rounded, color: p.accent, size: 23),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Authentication required',
                    style: TextStyle(
                      color: p.text,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              r.message.isEmpty
                  ? 'An app wants to make a change that needs an '
                        "administrator's password."
                  : r.message,
              style: TextStyle(
                color: p.text.withValues(alpha: 0.8),
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            if (r.users.length > 1) ...[
              _UserPicker(
                palette: p,
                users: r.users,
                value: _user,
                onChanged: (u) => setState(() => _user = u),
              ),
              const SizedBox(height: 10),
            ],
            ForgeField(
              palette: p,
              controller: _password,
              focusNode: _focus,
              autofocus: true,
              password: true,
              icon: Icons.key_rounded,
              hint: r.users.length == 1
                  ? 'Password for ${r.users.first}'
                  : 'Password',
              error: st.error != null,
              onSubmitted: (_) => _submit(),
            ),
            SizedBox(
              height: 26,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  st.error ?? st.info ?? '',
                  style: TextStyle(
                    color: st.error != null ? p.negative : p.dimText,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            if (_details) ...[
              if (r.program.isNotEmpty)
                Text('Program: ${r.program}', style: small),
              Text('Action: ${r.action}', style: small),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => setState(() => _details = !_details),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 6,
                    ),
                    child: Text(
                      _details ? 'Hide details' : 'Details',
                      style: TextStyle(
                        color: p.accent,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                DialogButton(
                  palette: p,
                  label: 'Cancel',
                  onTap: widget.onCancel,
                ),
                const SizedBox(width: 8),
                DialogButton(
                  palette: p,
                  label: st.busy ? 'Checking…' : 'Authenticate',
                  primary: true,
                  onTap: st.busy ? null : _submit,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

double _wave(double t) {
  const n = 4; // swings
  final x = (t * n * 2) % 2;
  return x < 1 ? (x * 2 - 1) : (1 - (x - 1) * 2);
}

class _UserPicker extends StatelessWidget {
  const _UserPicker({
    required this.palette,
    required this.users,
    required this.value,
    required this.onChanged,
  });

  final ForgePalette palette;
  final List<String> users;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final u in users)
          ChoiceChip(
            label: Text(u),
            selected: u == value,
            onSelected: (_) => onChanged(u),
            avatar: Icon(Icons.person_rounded, size: 16, color: p.text),
            showCheckmark: false,
            backgroundColor: p.hover,
            selectedColor: p.accent.withValues(alpha: 0.25),
            side: BorderSide.none,
            labelStyle: TextStyle(color: p.text, fontWeight: FontWeight.w600),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9),
            ),
          ),
      ],
    );
  }
}
