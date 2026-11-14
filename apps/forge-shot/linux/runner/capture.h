// Screenshots on Hyprland (grim, with hyprctl for where things are), as PNG.
#ifndef RUNNER_CAPTURE_H_
#define RUNNER_CAPTURE_H_

#include <glib.h>

// mode: "screen" (the focused screen), "workspace" (every screen), "window"
// (a click picks one) or "active-window".
gboolean forge_capture(const char* mode, const char* png_path, GError** error);

#endif  // RUNNER_CAPTURE_H_
