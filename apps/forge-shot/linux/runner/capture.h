// Screenshots through KWin (org.kde.KWin.ScreenShot2), saved as PNG.
#ifndef RUNNER_CAPTURE_H_
#define RUNNER_CAPTURE_H_

#include <glib.h>

// mode: "screen" (the screen with the pointer), "workspace" (every screen),
// "window" (KWin asks the user to click one) or "active-window".
gboolean forge_capture(const char* mode, const char* png_path, GError** error);

#endif  // RUNNER_CAPTURE_H_
