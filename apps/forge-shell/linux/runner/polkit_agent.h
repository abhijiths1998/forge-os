#ifndef FORGE_SHELL_POLKIT_AGENT_H_
#define FORGE_SHELL_POLKIT_AGENT_H_

#include <flutter_linux/flutter_linux.h>

// Forge's own password prompt for polkit (pkexec, the Store's installs,
// mounting disks...), in place of KDE's agent. polkit asks this process;
// the Dart side draws the dialog over the "forge/shell" channel:
//
//   native → Dart  authBegin {id, message, action, icon, users, program}
//                  authInfo  {id, text, error}   PAM's messages
//                  authDone  {id, ok}            ok false: wrong password
//                  authClose {id}                polkit gave up on it
//   Dart → native  authRespond {id, user, password}, authCancel {id}
//
// libpolkit-agent-1 does the PAM conversation (through polkit's helper), so
// the password never leaves this process except to that helper.

// Registers with polkit for this login session (or, for tests, for the
// process in $FORGE_POLKIT_PROCESS and its children). False if polkit
// refused, usually because another agent is registered already.
gboolean forge_polkit_register(FlMethodChannel* channel, GError** error);

// Handles authRespond / authCancel; false for any other method.
gboolean forge_polkit_method(const gchar* method, FlValue* args);

#endif  // FORGE_SHELL_POLKIT_AGENT_H_
