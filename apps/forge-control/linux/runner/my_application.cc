// Forge Control's GTK side: one long-lived, frameless, translucent window
// (KWin's Glass effect frosts it like the rest of the desktop), anchored
// under the top bar on the right with gtk-layer-shell when it's there.
//
// Like Forge Launcher, the application is unique on the session bus:
// `forge-control` (the top-bar button) reaches the running instance and
// toggles the panel. `forge-control --background` (autostart) starts it
// hidden, so the first click is instant too. Everything else, the state and
// the switches, comes from forged over D-Bus on the Dart side.
#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef HAVE_LAYER_SHELL
#include <gtk-layer-shell.h>
#endif

#include <cstring>

#include "flutter/generated_plugin_registrant.h"

namespace {
constexpr int kWidth = 380;
constexpr int kMinHeight = 120;
constexpr int kMaxHeight = 760;
#ifdef HAVE_LAYER_SHELL
constexpr int kMargin = 8;  // from the top bar and the screen's right edge
#endif
}  // namespace

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  GtkWindow* window;
  GtkWidget* view;
  FlMethodChannel* channel;
  int height;
  gboolean start_hidden;
  gboolean first_frame_done;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static void show_panel(MyApplication* self) {
  gtk_widget_set_size_request(self->view, kWidth, self->height);
  gtk_window_resize(self->window, kWidth, self->height);
  gtk_window_present(self->window);
  fl_method_channel_invoke_method(self->channel, "shown", nullptr, nullptr,
                                  nullptr, nullptr);
}

static void hide_panel(MyApplication* self) {
  if (!gtk_widget_get_visible(GTK_WIDGET(self->window))) return;
  gtk_widget_hide(GTK_WIDGET(self->window));
  fl_method_channel_invoke_method(self->channel, "hidden", nullptr, nullptr,
                                  nullptr, nullptr);
}

// Clicking anywhere else closes the panel, as macOS's Control Center does.
static gboolean focus_out_cb(GtkWidget*, GdkEvent*, MyApplication* self) {
  hide_panel(self);
  return FALSE;
}

static void first_frame_cb(MyApplication* self, FlView*) {
  self->first_frame_done = TRUE;
  if (!self->start_hidden) show_panel(self);
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

  if (strcmp(method, "hide") == 0) {
    hide_panel(self);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "setHeight") == 0) {
    // Only as tall as the content: any transparent area would still get
    // frosted by the Glass effect.
    self->height = CLAMP(int_arg(args, "height", kMinHeight), kMinHeight,
                         kMaxHeight);
    gtk_widget_set_size_request(self->view, kWidth, self->height);
    gtk_window_resize(self->window, kWidth, self->height);
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
  gtk_window_set_title(window, "Forge Control");
  gtk_window_set_decorated(window, FALSE);
  gtk_window_set_resizable(window, FALSE);
  gtk_window_set_skip_taskbar_hint(window, TRUE);
  gtk_window_set_skip_pager_hint(window, TRUE);
  gtk_window_set_keep_above(window, TRUE);
  gtk_window_set_type_hint(window, GDK_WINDOW_TYPE_HINT_DIALOG);

#ifdef HAVE_LAYER_SHELL
  if (gtk_layer_is_supported()) {
    gtk_layer_init_for_window(window);
    gtk_layer_set_namespace(window, "forge-control");
    gtk_layer_set_layer(window, GTK_LAYER_SHELL_LAYER_OVERLAY);
    gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_TOP, TRUE);
    gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_RIGHT, TRUE);
    gtk_layer_set_margin(window, GTK_LAYER_SHELL_EDGE_TOP, kMargin);
    gtk_layer_set_margin(window, GTK_LAYER_SHELL_EDGE_RIGHT, kMargin);
    // Focus when clicked into, so clicking elsewhere closes it.
    gtk_layer_set_keyboard_mode(window,
                                GTK_LAYER_SHELL_KEYBOARD_MODE_ON_DEMAND);
  }
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
  self->height = kMaxHeight;
  gtk_widget_set_size_request(self->view, kWidth, self->height);
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
      fl_engine_get_binary_messenger(engine), "forge/control",
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->channel, method_call_cb,
                                            self, nullptr);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Runs in the primary instance for every `forge-control` invocation.
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
    hide_panel(self);
  } else {
    show_panel(self);
  }
}

// `--background` only matters in the first (primary) instance; in a second
// process it's ignored and the running panel toggles.
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
       "Start hidden, ready for the first click", nullptr},
      {nullptr}};
  g_application_add_main_option_entries(G_APPLICATION(self), entries);
}

MyApplication* my_application_new() {
  g_set_prgname(APPLICATION_ID);
  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_DEFAULT_FLAGS, nullptr));
}
