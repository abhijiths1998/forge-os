// Forge Shell's GTK side: one frameless, translucent layer-shell surface per
// process, set up for the part of the desktop it draws, which is the first
// argument:
//
//   forge-shell bar         the top bar, floating 8 px in, reserving its space
//   forge-shell dock        the dock, centred at the bottom, as wide as its icons
//   forge-shell wallpaper   the wallpaper, under everything
//   forge-shell popups      everything Forge pops up: the start menu, menus,
//                           dialogs, the calendar and polkit's password
//                           prompt, on one screen-sized overlay that's only
//                           mapped while something is open
//
// Separate processes, so one part crashing or restarting leaves the others
// alone (forge-session starts each one and restarts it). The Dart side
// gets the same argument and asks this side for apps, icons, launching and
// its size over the "forge/shell" channel.
#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#include <gio/gdesktopappinfo.h>
#ifdef HAVE_LAYER_SHELL
#include <gtk-layer-shell.h>
#endif
#ifdef HAVE_POLKIT_AGENT
#include "polkit_agent.h"
#endif

#include <cstring>
#include <initializer_list>

#include "flutter/generated_plugin_registrant.h"

namespace {
constexpr int kMargin = 8;      // between the bar or dock and the screen edge
constexpr int kBarHeight = 34;
constexpr int kDockHeight = 76;  // icons plus room for the running dots
}  // namespace

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  GtkWindow* window;
  GtkWidget* view;
  FlMethodChannel* channel;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static const char* role_of(MyApplication* self) {
  char** args = self->dart_entrypoint_arguments;
  return args != nullptr && args[0] != nullptr ? args[0] : "bar";
}

// --- Method channel: apps, icons, launching, running, size --------------------

static FlValue* app_to_value(GDesktopAppInfo* info) {
  GAppInfo* app = G_APP_INFO(info);
  FlValue* m = fl_value_new_map();
  auto set = [m](const char* key, const char* value) {
    fl_value_set_string_take(m, key, fl_value_new_string(value ? value : ""));
  };
  set("id", g_app_info_get_id(app));
  set("name", g_app_info_get_display_name(app));
  set("exec", g_app_info_get_executable(app));
  set("wmclass", g_desktop_app_info_get_startup_wm_class(info));
  set("comment", g_app_info_get_description(app));
  set("generic", g_desktop_app_info_get_generic_name(info));
  set("categories", g_desktop_app_info_get_categories(info));
  // Keywords and categories as one ;-separated string each.
  const char* const* keywords = g_desktop_app_info_get_keywords(info);
  g_autofree gchar* joined =
      keywords ? g_strjoinv(";", const_cast<gchar**>(keywords)) : nullptr;
  set("keywords", joined);
  // Listed in menus: not NoDisplay, not hidden from this desktop.
  fl_value_set_string_take(m, "show",
                           fl_value_new_bool(g_app_info_should_show(app)));
  return m;
}

static FlValue* list_apps() {
  FlValue* list = fl_value_new_list();
  GList* all = g_app_info_get_all();
  for (GList* l = all; l != nullptr; l = l->next) {
    GAppInfo* app = G_APP_INFO(l->data);
    if (!G_IS_DESKTOP_APP_INFO(app)) continue;
    fl_value_append_take(list, app_to_value(G_DESKTOP_APP_INFO(app)));
  }
  g_list_free_full(all, g_object_unref);
  return list;
}

// PNG bytes for an app's icon (or a themed icon name), at `size` px, from the
// current GTK icon theme.
static FlValue* icon_png(const char* app_id, const char* icon_name, int size,
                         int scale) {
  GtkIconTheme* theme = gtk_icon_theme_get_default();
  g_autoptr(GtkIconInfo) icon_info = nullptr;
  const auto flags = GTK_ICON_LOOKUP_FORCE_SIZE;
  if (app_id != nullptr && *app_id) {
    g_autoptr(GDesktopAppInfo) info = g_desktop_app_info_new(app_id);
    GIcon* gicon = info ? g_app_info_get_icon(G_APP_INFO(info)) : nullptr;
    if (gicon != nullptr) {
      icon_info = gtk_icon_theme_lookup_by_gicon_for_scale(theme, gicon, size,
                                                           scale, flags);
    }
  }
  if (icon_info == nullptr && icon_name != nullptr && *icon_name) {
    icon_info = gtk_icon_theme_lookup_icon_for_scale(theme, icon_name, size,
                                                     scale, flags);
  }
  if (icon_info == nullptr) {
    icon_info = gtk_icon_theme_lookup_icon_for_scale(
        theme, "application-x-executable", size, scale, flags);
  }
  if (icon_info == nullptr) return fl_value_new_null();
  g_autoptr(GdkPixbuf) pixbuf = gtk_icon_info_load_icon(icon_info, nullptr);
  if (pixbuf == nullptr) return fl_value_new_null();
  gchar* buffer = nullptr;
  gsize length = 0;
  if (!gdk_pixbuf_save_to_buffer(pixbuf, &buffer, &length, "png", nullptr,
                                 nullptr)) {
    return fl_value_new_null();
  }
  FlValue* bytes =
      fl_value_new_uint8_list(reinterpret_cast<const uint8_t*>(buffer), length);
  g_free(buffer);
  return bytes;
}

static gboolean launch_app(const char* app_id, GError** error) {
  g_autoptr(GDesktopAppInfo) info = g_desktop_app_info_new(app_id);
  if (info == nullptr) {
    g_set_error(error, G_IO_ERROR, G_IO_ERROR_NOT_FOUND, "no app %s", app_id);
    return FALSE;
  }
  GdkAppLaunchContext* ctx =
      gdk_display_get_app_launch_context(gdk_display_get_default());
  gboolean ok = g_app_info_launch(G_APP_INFO(info), nullptr,
                                  G_APP_LAUNCH_CONTEXT(ctx), error);
  g_object_unref(ctx);
  return ok;
}

static const char* string_arg(FlValue* args, const char* key) {
  FlValue* v = args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP
                   ? fl_value_lookup_string(args, key)
                   : nullptr;
  return v && fl_value_get_type(v) == FL_VALUE_TYPE_STRING
             ? fl_value_get_string(v)
             : nullptr;
}

static int64_t int_arg(FlValue* args, const char* key, int64_t fallback) {
  FlValue* v = args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP
                   ? fl_value_lookup_string(args, key)
                   : nullptr;
  return v && fl_value_get_type(v) == FL_VALUE_TYPE_INT ? fl_value_get_int(v)
                                                        : fallback;
}

static GdkRectangle screen_area() {
  GdkRectangle area = {0, 0, 1920, 1080};
  GdkDisplay* display = gdk_display_get_default();
  GdkMonitor* monitor = gdk_display_get_primary_monitor(display);
  if (monitor == nullptr) monitor = gdk_display_get_monitor(display, 0);
  if (monitor != nullptr) gdk_monitor_get_geometry(monitor, &area);
  return area;
}

static void method_call_cb(FlMethodChannel*, FlMethodCall* call,
                           gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  const gchar* method = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);
  g_autoptr(FlMethodResponse) response = nullptr;
  g_autoptr(GError) error = nullptr;

#ifdef HAVE_POLKIT_AGENT
  if (forge_polkit_method(method, args)) {
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    fl_method_call_respond(call, response, nullptr);
    return;
  }
#endif

  if (strcmp(method, "apps") == 0) {
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(list_apps()));
  } else if (strcmp(method, "icon") == 0) {
    g_autoptr(FlValue) png = icon_png(
        string_arg(args, "app"), string_arg(args, "name"),
        int_arg(args, "size", 48),
        gtk_widget_get_scale_factor(GTK_WIDGET(self->window)));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(png));
  } else if (strcmp(method, "launch") == 0) {
    const char* app = string_arg(args, "app");
    if (app != nullptr && launch_app(app, &error)) {
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    } else {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "launch", error ? error->message : "no app", nullptr));
    }
  } else if (strcmp(method, "run") == 0) {
    // A command line (forge-launcher, forge-control), left running on its
    // own. GLib reaps the child, so no zombies pile up in the bar.
    const char* command = string_arg(args, "command");
    if (command != nullptr && g_spawn_command_line_async(command, &error)) {
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    } else {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "run", error ? error->message : "no command", nullptr));
    }
  } else if (strcmp(method, "setWidth") == 0) {
    // The dock: as wide as its icons, so the glass ends where they do.
    const int width = int_arg(args, "width", 400);
    int height = 0;
    gtk_window_get_size(self->window, nullptr, &height);
    gtk_widget_set_size_request(self->view, width, height);
    gtk_window_resize(self->window, width, height);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "screen") == 0) {
    // The screen's size in logical pixels, for placing popups.
    const GdkRectangle area = screen_area();
    g_autoptr(FlValue) size = fl_value_new_map();
    fl_value_set_string_take(size, "width", fl_value_new_int(area.width));
    fl_value_set_string_take(size, "height", fl_value_new_int(area.height));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(size));
  } else if (strcmp(method, "show") == 0) {
    // The popups overlay: mapped while something is open, so it takes the
    // keyboard and the clicks only then.
    gtk_widget_show(GTK_WIDGET(self->window));
    gtk_window_present(self->window);
    gtk_widget_grab_focus(self->view);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "hide") == 0) {
    gtk_widget_hide(GTK_WIDGET(self->window));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "polkitRegister") == 0) {
    // The Dart side is listening: polkit can ask us now.
#ifdef HAVE_POLKIT_AGENT
    if (forge_polkit_register(self->channel, &error)) {
      response =
          FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    } else {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "polkit", error ? error->message : "refused", nullptr));
    }
#else
    response = FL_METHOD_RESPONSE(fl_method_error_response_new(
        "polkit", "built without polkit-agent-1", nullptr));
#endif
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(call, response, nullptr);
}

// --- The surface ---------------------------------------------------------------

#ifdef HAVE_LAYER_SHELL
static void place(GtkWindow* window, const char* role) {
  gtk_layer_init_for_window(window);
  if (strcmp(role, "wallpaper") == 0) {
    gtk_layer_set_namespace(window, "forge-wallpaper");
    gtk_layer_set_layer(window, GTK_LAYER_SHELL_LAYER_BACKGROUND);
    for (auto edge : {GTK_LAYER_SHELL_EDGE_TOP, GTK_LAYER_SHELL_EDGE_BOTTOM,
                      GTK_LAYER_SHELL_EDGE_LEFT, GTK_LAYER_SHELL_EDGE_RIGHT}) {
      gtk_layer_set_anchor(window, edge, TRUE);
    }
    gtk_layer_set_exclusive_zone(window, -1);  // under the bar too
  } else if (strcmp(role, "dock") == 0) {
    gtk_layer_set_namespace(window, "forge-dock");
    gtk_layer_set_layer(window, GTK_LAYER_SHELL_LAYER_TOP);
    gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_BOTTOM, TRUE);
    gtk_layer_set_margin(window, GTK_LAYER_SHELL_EDGE_BOTTOM, kMargin);
    gtk_layer_set_exclusive_zone(window, kDockHeight);
  } else if (strcmp(role, "popups") == 0) {
    gtk_layer_set_namespace(window, "forge-popups");
    gtk_layer_set_layer(window, GTK_LAYER_SHELL_LAYER_OVERLAY);
    for (auto edge : {GTK_LAYER_SHELL_EDGE_TOP, GTK_LAYER_SHELL_EDGE_BOTTOM,
                      GTK_LAYER_SHELL_EDGE_LEFT, GTK_LAYER_SHELL_EDGE_RIGHT}) {
      gtk_layer_set_anchor(window, edge, TRUE);
    }
    gtk_layer_set_exclusive_zone(window, -1);  // over the bar and dock too
    // Menus and dialogs take the keyboard while they're up.
    gtk_layer_set_keyboard_mode(window,
                                GTK_LAYER_SHELL_KEYBOARD_MODE_EXCLUSIVE);
  } else {
    gtk_layer_set_namespace(window, "forge-bar");
    gtk_layer_set_layer(window, GTK_LAYER_SHELL_LAYER_TOP);
    for (auto edge : {GTK_LAYER_SHELL_EDGE_TOP, GTK_LAYER_SHELL_EDGE_LEFT,
                      GTK_LAYER_SHELL_EDGE_RIGHT}) {
      gtk_layer_set_anchor(window, edge, TRUE);
      gtk_layer_set_margin(window, edge, kMargin);
    }
    gtk_layer_set_exclusive_zone(window, kBarHeight);
  }
}
#endif

static void create_window(MyApplication* self) {
  const char* role = role_of(self);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(self)));
  self->window = window;
  g_autofree gchar* title = g_strdup_printf("Forge %s", role);
  gtk_window_set_title(window, title);
  gtk_window_set_decorated(window, FALSE);

  const bool popups = strcmp(role, "popups") == 0;
  int width = 600, height = kBarHeight;
  if (strcmp(role, "dock") == 0) height = kDockHeight;
  if (strcmp(role, "wallpaper") == 0 || popups) {
    const GdkRectangle area = screen_area();
    width = area.width;
    height = area.height;
  }
  gtk_window_set_default_size(window, width, height);

#ifdef HAVE_LAYER_SHELL
  if (gtk_layer_is_supported()) place(window, role);
#endif

  // Translucent: an RGBA visual and a transparent Flutter background.
  GdkScreen* screen = gtk_window_get_screen(window);
  GdkVisual* visual = gdk_screen_get_rgba_visual(screen);
  if (visual != nullptr) gtk_widget_set_visual(GTK_WIDGET(window), visual);
  gtk_widget_set_app_paintable(GTK_WIDGET(window), TRUE);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  self->view = GTK_WIDGET(view);
  // The bar stretches between its anchors; the others keep this size.
  gtk_widget_set_size_request(self->view, strcmp(role, "bar") == 0 ? -1 : width,
                              height);
  GdkRGBA transparent = {0, 0, 0, 0};
  fl_view_set_background_color(view, &transparent);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  FlEngine* engine = fl_view_get_engine(view);
  self->channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(engine), "forge/shell",
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->channel, method_call_cb,
                                            self, nullptr);

  if (popups) {
    // Hidden until something opens; realised, so Flutter runs meanwhile.
    gtk_widget_realize(GTK_WIDGET(view));
    return;
  }
  gtk_widget_show(GTK_WIDGET(window));
}

// --- GApplication ------------------------------------------------------------

static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  if (self->window == nullptr) create_window(self);
}

static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }
  g_application_activate(application);
  *exit_status = 0;
  return TRUE;
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
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication*) {}

MyApplication* my_application_new() {
  g_set_prgname(APPLICATION_ID);
  // Not unique: the bar, dock and wallpaper are separate processes.
  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
