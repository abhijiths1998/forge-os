#include "capture.h"
#include "my_application.h"

int main(int argc, char** argv) {
  // forge-shot --hyprland-ready: Forge Shot captures on Hyprland (grim);
  // forge-screenshot asks before handing it the Print keys.
  if (argc == 2 && g_strcmp0(argv[1], "--hyprland-ready") == 0) return 0;
  // forge-shot --test-capture <mode> <file.png>: only take a screenshot.
  if (argc == 4 && g_strcmp0(argv[1], "--test-capture") == 0) {
    g_autoptr(GError) error = nullptr;
    if (!forge_capture(argv[2], argv[3], &error)) {
      g_printerr("forge-shot: %s\n", error->message);
      return 1;
    }
    return 0;
  }
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
