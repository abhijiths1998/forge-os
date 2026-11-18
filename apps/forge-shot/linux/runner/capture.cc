// Screenshots on Hyprland: grim reads the screen (wlr-screencopy), and
// Hyprland itself says where the screens and windows are (hyprctl), so a
// window is just its rectangle. Saved straight to PNG by grim.
#include "capture.h"

#include <gio/gio.h>

#include <cstring>
#include <string>

namespace {

// Runs a shell pipeline; its trimmed stdout, or false with error set.
bool run(const std::string& script, std::string* out, GError** error) {
  const char* argv[] = {"/bin/sh", "-c", script.c_str(), nullptr};
  g_autofree gchar* std_out = nullptr;
  g_autofree gchar* std_err = nullptr;
  gint status = 0;
  if (!g_spawn_sync(nullptr, const_cast<gchar**>(argv), nullptr, G_SPAWN_SEARCH_PATH, nullptr,
                    nullptr, &std_out, &std_err, &status, error)) {
    return false;
  }
  if (!g_spawn_check_wait_status(status, nullptr)) {
    g_set_error(error, G_SPAWN_ERROR, G_SPAWN_ERROR_FAILED, "%s",
                std_err != nullptr && *std_err != '\0' ? g_strstrip(std_err) : "the screenshot failed");
    return false;
  }
  if (out != nullptr) *out = std_out != nullptr ? g_strstrip(std_out) : "";
  return true;
}

std::string quote(const char* s) {
  g_autofree gchar* q = g_shell_quote(s);
  return q;
}

}  // namespace

gboolean forge_capture(const char* mode, const char* png_path, GError** error) {
  const std::string path = quote(png_path);
  std::string geometry;
  if (strcmp(mode, "workspace") == 0) {
    // Every screen, as one image.
    return run("grim " + path, nullptr, error);
  }
  if (strcmp(mode, "screen") == 0) {
    // The screen in use (Hyprland's focused monitor).
    std::string output;
    if (!run("hyprctl monitors -j | jq -r '.[] | select(.focused) | .name'", &output, error)) return FALSE;
    return run("grim -o " + quote(output.c_str()) + " " + path, nullptr, error);
  }
  if (strcmp(mode, "active-window") == 0) {
    if (!run("hyprctl activewindow -j | jq -r 'select(.at) | \"\\(.at[0]),\\(.at[1]) \\(.size[0])x\\(.size[1])\"'",
             &geometry, error)) {
      return FALSE;
    }
  } else if (strcmp(mode, "window") == 0) {
    // Pick one with a click: slurp offers the windows on screen as the
    // rectangles to choose from.
    if (!run("hyprctl clients -j | jq -r --argjson ws \"$(hyprctl monitors -j | jq '[.[].activeWorkspace.id]')\" "
             "'.[] | select(.mapped and (.workspace.id as $w | $ws | index($w))) "
             "| \"\\(.at[0]),\\(.at[1]) \\(.size[0])x\\(.size[1])\"' | slurp -r -b '#1b1d2b55' -c '#7f8ef5ff' -w 2",
             &geometry, error)) {
      return FALSE;
    }
  } else {
    g_set_error(error, G_IO_ERROR, G_IO_ERROR_INVALID_ARGUMENT, "no capture mode %s", mode);
    return FALSE;
  }
  if (geometry.empty()) {
    g_set_error(error, G_IO_ERROR, G_IO_ERROR_NOT_FOUND, "no window to capture");
    return FALSE;
  }
  return run("grim -g " + quote(geometry.c_str()) + " " + path, nullptr, error);
}
