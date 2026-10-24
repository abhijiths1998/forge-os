// Forge Launcher's GTK side: one long-lived, frameless, translucent window
// (KWin's Glass effect frosts it like the rest of the desktop) and a method
// channel that hands the Dart UI what GIO already does well: the list of
// installed apps (desktop files, OnlyShowIn/NoDisplay rules, keywords), their
// icons from the current icon theme, and launching them.
//
// The application is unique on the session bus, so `forge-launcher` (bound to
// Meta+Space) reaches the running instance and toggles the window instead of
// starting a second Flutter engine. `forge-launcher --background` (autostart)
// starts it hidden, so the first Meta+Space is instant too.
#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#include <gio/gdesktopappinfo.h>

#include <cstring>

#include "flutter/generated_plugin_registrant.h"

namespace {
constexpr int kWidth = 680;
constexpr int kMinHeight = 64;
constexpr int kMaxHeight = 560;
}  // namespace

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  GtkWindow* window;
  GtkWidget* view;
  FlMethodChannel* channel;
  gboolean start_hidden;
  gboolean first_frame_done;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static void show_launcher(MyApplication* self) {
  // Map at full height: KWin centres the window (kwinrulesrc), which puts
  // its top edge high on the screen, Spotlight-style. The UI then shrinks it
  // to its content (setHeight) and the top edge stays put.
  gtk_widget_set_size_request(self->view, kWidth, kMaxHeight);
  gtk_window_resize(self->window, kWidth, kMaxHeight);
  gtk_window_present(self->window);
  fl_method_channel_invoke_method(self->channel, "shown", nullptr, nullptr,
                                  nullptr, nullptr);
}

static void hide_launcher(MyApplication* self) {
  if (!gtk_widget_get_visible(GTK_WIDGET(self->window))) return;
  gtk_widget_hide(GTK_WIDGET(self->window));
  fl_method_channel_invoke_method(self->channel, "hidden", nullptr, nullptr,
                                  nullptr, nullptr);
}

// Clicking anywhere else, or switching windows, closes the launcher, the way
// KRunner and Spotlight behave.
static gboolean focus_out_cb(GtkWidget*, GdkEvent*, MyApplication* self) {
  hide_launcher(self);
  return FALSE;
}

static void first_frame_cb(MyApplication* self, FlView*) {
  self->first_frame_done = TRUE;
  if (!self->start_hidden) show_launcher(self);
}

// --- Method channel: apps, icons, launching, window size --------------------

static FlValue* app_to_value(GDesktopAppInfo* info) {
  GAppInfo* app = G_APP_INFO(info);
  FlValue* m = fl_value_new_map();
  auto set = [m](const char* key, const char* value) {
    fl_value_set_string_take(m, key, fl_value_new_string(value ? value : ""));
  };
  set("id", g_app_info_get_id(app));
  set("name", g_app_info_get_display_name(app));
  set("comment", g_app_info_get_description(app));
  set("generic", g_desktop_app_info_get_generic_name(info));
  set("exec", g_app_info_get_executable(app));
  const char* const* keywords = g_desktop_app_info_get_keywords(info);
  g_autofree gchar* joined =
      keywords ? g_strjoinv(";", const_cast<gchar**>(keywords)) : nullptr;
  set("keywords", joined);
  const char* categories = g_desktop_app_info_get_categories(info);
  set("categories", categories);
  return m;
}

static FlValue* list_apps() {
  FlValue* list = fl_value_new_list();
  GList* all = g_app_info_get_all();
  for (GList* l = all; l != nullptr; l = l->next) {
    GAppInfo* app = G_APP_INFO(l->data);
    if (!g_app_info_should_show(app) || !G_IS_DESKTOP_APP_INFO(app)) continue;
    fl_value_append_take(list, app_to_value(G_DESKTOP_APP_INFO(app)));
  }
  g_list_free_full(all, g_object_unref);
  return list;
}

// PNG bytes for an app's icon (or a themed icon name), at `size` px, from the
// current GTK icon theme (KDE keeps it in sync with the Plasma one).
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

static void method_call_cb(FlMethodChannel*, FlMethodCall* call,
                           gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  const gchar* method = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);
  g_autoptr(FlMethodResponse) response = nullptr;

  if (strcmp(method, "apps") == 0) {
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(list_apps()));
  } else if (strcmp(method, "icon") == 0) {
    int size = int_arg(args, "size", 32);
    int scale = gtk_widget_get_scale_factor(GTK_WIDGET(self->window));
    g_autoptr(FlValue) png = icon_png(string_arg(args, "app"),
                                      string_arg(args, "name"), size, scale);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(png));
  } else if (strcmp(method, "launch") == 0) {
    g_autoptr(GError) error = nullptr;
    if (launch_app(string_arg(args, "app"), &error)) {
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    } else {
      response = FL_METHOD_RESPONSE(
          fl_method_error_response_new("launch", error->message, nullptr));
    }
  } else if (strcmp(method, "hide") == 0) {
    hide_launcher(self);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "setHeight") == 0) {
    // The window is only as tall as its content: any transparent area
    // would still get frosted by the Glass effect.
    int height = CLAMP(int_arg(args, "height", kMinHeight), kMinHeight,
                       kMaxHeight);
    gtk_widget_set_size_request(self->view, kWidth, height);
    gtk_window_resize(self->window, kWidth, height);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(call, response, nullptr);
}

// --- GApplication -----------------------------------------------------------

static void create_window(MyApplication* self) {
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(self)));
  self->window = window;
  gtk_window_set_title(window, "Forge Launcher");
  gtk_window_set_decorated(window, FALSE);
  gtk_window_set_resizable(window, FALSE);
  gtk_window_set_skip_taskbar_hint(window, TRUE);
  gtk_window_set_skip_pager_hint(window, TRUE);
  gtk_window_set_keep_above(window, TRUE);
  gtk_window_set_type_hint(window, GDK_WINDOW_TYPE_HINT_DIALOG);

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
  gtk_widget_set_size_request(self->view, kWidth, kMaxHeight);
  GdkRGBA transparent = {0, 0, 0, 0};
  fl_view_set_background_color(view, &transparent);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  g_signal_connect(window, "focus-out-event", G_CALLBACK(focus_out_cb), self);
  g_signal_connect(window, "delete-event", G_CALLBACK(gtk_widget_hide_on_delete),
                   nullptr);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  FlEngine* engine = fl_view_get_engine(view);
  self->channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(engine), "forge/launcher",
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->channel, method_call_cb,
                                            self, nullptr);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Runs in the primary instance for every `forge-launcher` invocation.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  if (self->window == nullptr) {
    create_window(self);
    return;  // first_frame_cb shows it, unless started with --background
  }
  self->start_hidden = FALSE;
  if (!self->first_frame_done) {
    // Started with --background and not drawn yet: mapping the window is
    // what gets Flutter to render, and first_frame_cb then presents it.
    gtk_widget_show(GTK_WIDGET(self->window));
    return;
  }
  if (gtk_widget_get_visible(GTK_WIDGET(self->window))) {
    hide_launcher(self);
  } else {
    show_launcher(self);
  }
}

// Runs in whichever process was started. `--background` only matters in the
// first (primary) instance: activate then builds the window without showing
// it. In a second process it is ignored and the running launcher toggles.
static gint my_application_handle_local_options(GApplication* application,
                                                GVariantDict* options) {
  MY_APPLICATION(application)->start_hidden =
      g_variant_dict_contains(options, "background");
  return -1;  // default handling: register, then activate
}

static void my_application_startup(GApplication* application) {
  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
  // Keep running with the window hidden.
  g_application_hold(application);
}

static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_object(&self->channel);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->handle_local_options =
      my_application_handle_local_options;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {
  const GOptionEntry entries[] = {
      {"background", 0, 0, G_OPTION_ARG_NONE, nullptr,
       "Start hidden, ready for the next Meta+Space", nullptr},
      {nullptr}};
  g_application_add_main_option_entries(G_APPLICATION(self), entries);
}

MyApplication* my_application_new() {
  g_set_prgname(APPLICATION_ID);
  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_DEFAULT_FLAGS, nullptr));
}
