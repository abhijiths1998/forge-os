#ifndef RUNNER_PAMAC_CHANNEL_H_
#define RUNNER_PAMAC_CHANNEL_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

// The "forge/store" method channel: package queries straight from libpamac,
// transactions through the pamac CLI (so polkit and Plasma's auth dialog
// work as they do for `forge install`), and icons from the GTK icon theme.
void pamac_channel_register(FlBinaryMessenger* messenger, GtkWindow* window);

#endif  // RUNNER_PAMAC_CHANNEL_H_
