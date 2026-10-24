// Forge Shot's GTK side. Each run does one thing:
//
//   forge-shot [region]   capture the active screen, then pick a region of it
//                         on a full-screen overlay showing that frozen image
//   forge-shot full       the whole desktop, straight to the thumbnail
//   forge-shot window     KWin asks for a click on a window, then the same
//   forge-shot edit FILE  the editor, in an ordinary window
//   --delay N             wait N seconds first
//
// The screenshot is taken here, before Flutter starts, so it shows the screen
// as it was when the key was pressed. The overlay is a layer-shell surface;
// afterwards the same surface turns into the thumbnail in the bottom-right
// corner (present: "thumbnail"). The editor is a separate run, so it can be
// a normal window. Clipboard and capture go through the method channel
// "forge/shot".
#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef HAVE_LAYER_SHELL
#include <gtk-layer-shell.h>
#endif

#include <unistd.h>

#include <cstdlib>
#include <initializer_list>
#include <cstring>

#include "capture.h"
#include "flutter/generated_plugin_registrant.h"

namespace {
constexpr int kThumbWidth = 336;
constexpr int kThumbHeight = 252;
constexpr int kMargin = 16;
}  // namespace

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  GtkWindow* window;
  GtkWidget* view;
  FlMethodChannel* channel;
  gboolean layered;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// --- Clipboard ----------------------------------------------------------------
// wl-copy keeps serving the clipboard after we quit; GTK's clipboard only
// while we run (Plasma's clipboard history usually takes over).

static gboolean wl_copy(const char* type, const guint8* data, gsize length) {
  g_autofree gchar* wl_copy_path = g_find_program_in_path("wl-copy");
  if (wl_copy_path == nullptr) return FALSE;
  const gchar* argv[] = {wl_copy_path, "--type", type, nullptr};
  gint stdin_fd = -1;
  GPid pid;
  if (!g_spawn_async_with_pipes(nullptr, const_cast<gchar**>(argv), nullptr,
                                G_SPAWN_DO_NOT_REAP_CHILD, nullptr, nullptr,
                                &pid, &stdin_fd, nullptr, nullptr, nullptr)) {
    return FALSE;
  }
  gsize written = 0;
  while (written < length) {
    ssize_t n = write(stdin_fd, data + written, length - written);
    if (n <= 0) break;
    written += n;
  }
  close(stdin_fd);
  g_child_watch_add(pid, [](GPid p, gint, gpointer) { g_spawn_close_pid(p); },
                    nullptr);
  return written == length;
}

static gboolean copy_image(const char* path) {
  gchar* contents = nullptr;
  gsize length = 0;
  if (!g_file_get_contents(path, &contents, &length, nullptr)) return FALSE;
  gboolean ok = wl_copy("image/png", reinterpret_cast<guint8*>(contents),
                        length);
  g_free(contents);
  if (ok) return TRUE;
  g_autoptr(GdkPixbuf) pixbuf = gdk_pixbuf_new_from_file(path, nullptr);
  if (pixbuf == nullptr) return FALSE;
  gtk_clipboard_set_image(gtk_clipboard_get(GDK_SELECTION_CLIPBOARD), pixbuf);
  gtk_clipboard_store(gtk_clipboard_get(GDK_SELECTION_CLIPBOARD));
  return TRUE;
}

static gboolean copy_text(const char* text) {
  if (wl_copy("text/plain;charset=utf-8",
              reinterpret_cast<const guint8*>(text), strlen(text))) {
    return TRUE;
  }
  gtk_clipboard_set_text(gtk_clipboard_get(GDK_SELECTION_CLIPBOARD), text, -1);
  gtk_clipboard_store(gtk_clipboard_get(GDK_SELECTION_CLIPBOARD));
  return TRUE;
}

// --- Presentation -------------------------------------------------------------

static void present_thumbnail(MyApplication* self) {
#ifdef HAVE_LAYER_SHELL
  if (self->layered) {
    GtkWindow* w = self->window;
    gtk_layer_set_layer(w, GTK_LAYER_SHELL_LAYER_TOP);
    gtk_layer_set_anchor(w, GTK_LAYER_SHELL_EDGE_TOP, FALSE);
    gtk_layer_set_anchor(w, GTK_LAYER_SHELL_EDGE_LEFT, FALSE);
    gtk_layer_set_anchor(w, GTK_LAYER_SHELL_EDGE_BOTTOM, TRUE);
    gtk_layer_set_anchor(w, GTK_LAYER_SHELL_EDGE_RIGHT, TRUE);
    gtk_layer_set_margin(w, GTK_LAYER_SHELL_EDGE_BOTTOM, kMargin);
    gtk_layer_set_margin(w, GTK_LAYER_SHELL_EDGE_RIGHT, kMargin);
    gtk_layer_set_keyboard_mode(w, GTK_LAYER_SHELL_KEYBOARD_MODE_NONE);
  }
#endif
  gtk_widget_set_size_request(self->view, kThumbWidth, kThumbHeight);
  gtk_window_resize(self->window, kThumbWidth, kThumbHeight);
  gtk_widget_show(GTK_WIDGET(self->window));
}

// --- Method channel -------------------------------------------------------------

static const char* string_arg(FlValue* args, const char* key) {
  FlValue* v = args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP
                   ? fl_value_lookup_string(args, key)
                   : nullptr;
  return v && fl_value_get_type(v) == FL_VALUE_TYPE_STRING
             ? fl_value_get_string(v)
             : nullptr;
}

static void method_call_cb(FlMethodChannel*, FlMethodCall* call,
                           gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  const gchar* method = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);
  g_autoptr(FlMethodResponse) response = nullptr;

  if (strcmp(method, "copyImage") == 0) {
    const char* path = string_arg(args, "path");
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(
        fl_value_new_bool(path && copy_image(path))));
  } else if (strcmp(method, "copyText") == 0) {
    const char* text = string_arg(args, "text");
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(
        fl_value_new_bool(text && copy_text(text))));
  } else if (strcmp(method, "present") == 0) {
    if (g_strcmp0(string_arg(args, "mode"), "thumbnail") == 0) {
      present_thumbnail(self);
    } else if (g_strcmp0(string_arg(args, "mode"), "hidden") == 0) {
      gtk_widget_hide(GTK_WIDGET(self->window));
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "capture") == 0) {
    // Another capture from a running Forge Shot (the editor's "Retake").
    g_autoptr(GError) error = nullptr;
    const char* mode = string_arg(args, "mode");
    const char* path = string_arg(args, "path");
    if (path && forge_capture(mode ? mode : "screen", path, &error)) {
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    } else {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "capture", error ? error->message : "no path", nullptr));
    }
  } else if (strcmp(method, "quit") == 0) {
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    fl_method_call_respond(call, response, nullptr);
    g_application_quit(G_APPLICATION(self));
    return;
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(call, response, nullptr);
}

// --- Window -----------------------------------------------------------------

static void first_frame_cb(MyApplication* self, FlView*) {
  gtk_widget_show(GTK_WIDGET(self->window));
}

static void create_window(MyApplication* self, const char* mode) {
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(self)));
  self->window = window;
  const gboolean editor = g_strcmp0(mode, "edit") == 0;
  gtk_window_set_title(window, editor ? "Forge Shot" : "Forge Shot capture");
  gtk_window_set_icon_name(window, "applets-screenshooter");

  if (editor) {
    gtk_window_set_default_size(window, 1180, 780);
  } else {
    gtk_window_set_decorated(window, FALSE);
    gtk_window_set_skip_taskbar_hint(window, TRUE);
#ifdef HAVE_LAYER_SHELL
    if (gtk_layer_is_supported()) {
      self->layered = TRUE;
      gtk_layer_init_for_window(window);
      gtk_layer_set_namespace(window, "forge-shot");
      if (g_strcmp0(mode, "region") == 0) {
        // Over everything, the whole screen, keys to us (Esc, Enter...).
        gtk_layer_set_layer(window, GTK_LAYER_SHELL_LAYER_OVERLAY);
        gtk_layer_set_exclusive_zone(window, -1);
        for (auto edge : {GTK_LAYER_SHELL_EDGE_TOP, GTK_LAYER_SHELL_EDGE_BOTTOM,
                          GTK_LAYER_SHELL_EDGE_LEFT,
                          GTK_LAYER_SHELL_EDGE_RIGHT}) {
          gtk_layer_set_anchor(window, edge, TRUE);
        }
        gtk_layer_set_keyboard_mode(window,
                                    GTK_LAYER_SHELL_KEYBOARD_MODE_EXCLUSIVE);
      }
    }
#endif
    if (!self->layered) gtk_window_fullscreen(window);
  }

  // Translucent: the thumbnail's rounded glass.
  GdkScreen* screen = gtk_window_get_screen(window);
  GdkVisual* visual = gdk_screen_get_rgba_visual(screen);
  if (visual != nullptr) gtk_widget_set_visual(GTK_WIDGET(window), visual);
  gtk_widget_set_app_paintable(GTK_WIDGET(window), TRUE);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);
  FlView* view = fl_view_new(project);
  self->view = GTK_WIDGET(view);
  GdkRGBA transparent = {0, 0, 0, 0};
  fl_view_set_background_color(view, &transparent);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));
  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)), "forge/shot",
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->channel, method_call_cb,
                                            self, nullptr);
  if (g_strcmp0(mode, "region") != 0 && !editor) {
    present_thumbnail(self);  // full and window go straight to the thumbnail
  }
  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// --- GApplication -------------------------------------------------------------

// Takes the screenshot (unless editing), then hands Dart its arguments:
//   region <png> | thumbnail <png> | edit <png>
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  gchar** argv = *arguments;
  const char* mode = "region";
  const char* file = nullptr;
  int delay = 0;
  for (int i = 1; argv[i] != nullptr; i++) {
    if (g_strcmp0(argv[i], "--delay") == 0 && argv[i + 1] != nullptr) {
      delay = CLAMP(atoi(argv[++i]), 0, 60);
    } else if (g_strcmp0(argv[i], "edit") == 0 && argv[i + 1] != nullptr) {
      mode = "edit";
      file = argv[++i];
    } else if (g_strcmp0(argv[i], "region") == 0 ||
               g_strcmp0(argv[i], "full") == 0 ||
               g_strcmp0(argv[i], "window") == 0 ||
               g_strcmp0(argv[i], "active-window") == 0) {
      mode = argv[i];
    } else {
      g_printerr(
          "usage: forge-shot [region|full|window|active-window] [--delay N]\n"
          "       forge-shot edit FILE\n");
      *exit_status = 2;
      return TRUE;
    }
  }

  g_autofree gchar* path = nullptr;
  if (file != nullptr) {
    path = g_canonicalize_filename(file, nullptr);
  } else {
    if (delay > 0) g_usleep(static_cast<gulong>(delay) * G_USEC_PER_SEC);
    g_autofree gchar* dir =
        g_build_filename(g_get_user_runtime_dir(), "forge-shot", nullptr);
    g_mkdir_with_parents(dir, 0700);
    g_autofree gchar* name = g_strdup_printf(
        "capture-%" G_GINT64_FORMAT ".png", g_get_real_time());
    path = g_build_filename(dir, name, nullptr);
    const char* what = g_strcmp0(mode, "region") == 0 ? "screen"
                       : g_strcmp0(mode, "full") == 0 ? "workspace"
                                                      : mode;
    g_autoptr(GError) error = nullptr;
    if (!forge_capture(what, path, &error)) {
      // Cancelling KWin's window picker lands here too.
      g_printerr("forge-shot: no screenshot (%s)\n", error->message);
      *exit_status = 1;
      return TRUE;
    }
  }

  const char* dart_mode = g_strcmp0(mode, "edit") == 0     ? "edit"
                          : g_strcmp0(mode, "region") == 0 ? "region"
                                                           : "thumbnail";
  const gchar* dart_args[] = {dart_mode, path, nullptr};
  self->dart_entrypoint_arguments = g_strdupv(const_cast<gchar**>(dart_args));

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }
  create_window(self, dart_mode);
  *exit_status = 0;
  return TRUE;  // handled here; the main loop runs while the app is held
}

static void my_application_activate(GApplication*) {}

static void my_application_startup(GApplication* application) {
  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
  g_application_hold(application);  // until Dart says quit
}

static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_object(&self->channel);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication*) {}

MyApplication* my_application_new() {
  g_set_prgname(APPLICATION_ID);
  // Each run is its own: a capture and an editor can be open together.
  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
