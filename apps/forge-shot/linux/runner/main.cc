#include "capture.h"
#include "my_application.h"

int main(int argc, char** argv) {
  // forge-shot --test-capture <mode> <file.png>: only take a screenshot, to
  // check KWin lets this binary (see capture.cc).
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
