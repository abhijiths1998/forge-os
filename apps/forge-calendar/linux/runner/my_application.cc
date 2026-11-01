// Forge Calendar's GTK side. The application is unique on the session bus,
// and keeps running with its window hidden so reminders come on time:
//   forge-calendar               opens (or shows) the window
//   forge-calendar --background  starts hidden (autostart at login)
// Closing the window hides it; "Quit" in the dock or `pkill` ends it.
#include "my_application.h"

#include <flutter_linux/flutter_linux.h>

#include <cstring>

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  GtkWindow* window;
  gboolean start_hidden;
  gboolean first_frame_done;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static void first_frame_cb(MyApplication* self, FlView* view) {
  self->first_frame_done = TRUE;
  if (!self->start_hidden) gtk_window_present(self->window);
}

// "forge/window": present (a reminder the desktop couldn't show).
static void window_method_cb(FlMethodChannel* channel, FlMethodCall* call,
                             gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  g_autoptr(FlMethodResponse) response = nullptr;
  if (strcmp(fl_method_call_get_name(call), "present") == 0) {
    self->start_hidden = FALSE;
    gtk_window_present(self->window);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(call, response, nullptr);
}

static void create_window(MyApplication* self) {
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(self)));
  self->window = window;
  gtk_window_set_title(window, "Forge Calendar");
  gtk_window_set_icon_name(window, "x-office-calendar");
  gtk_window_set_default_size(window, 1180, 760);
  GdkVisual* visual = gdk_screen_get_rgba_visual(gtk_window_get_screen(window));
  if (visual != nullptr) gtk_widget_set_visual(GTK_WIDGET(window), visual);
  gtk_widget_set_app_paintable(GTK_WIDGET(window), TRUE);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA transparent = {0, 0, 0, 0};
  fl_view_set_background_color(view, &transparent);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  // Closing hides: the reminders keep running.
  g_signal_connect(window, "delete-event", G_CALLBACK(gtk_widget_hide_on_delete),
                   nullptr);
  gtk_widget_realize(GTK_WIDGET(view));
  fl_register_plugins(FL_PLUGIN_REGISTRY(view));
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  FlMethodChannel* channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)), "forge/window",
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, window_method_cb, self,
                                            nullptr);
  gtk_widget_grab_focus(GTK_WIDGET(view));
}

static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  if (self->window == nullptr) {
    create_window(self);  // first_frame_cb shows it, unless --background
    return;
  }
  self->start_hidden = FALSE;
  if (self->first_frame_done) gtk_window_present(self->window);
}

static gint my_application_handle_local_options(GApplication* application,
                                                GVariantDict* options) {
  MY_APPLICATION(application)->start_hidden =
      g_variant_dict_contains(options, "background");
  return -1;
}

static void my_application_startup(GApplication* application) {
  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
  g_application_hold(application);
}

static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
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
       "Start hidden, for reminders", nullptr},
      {nullptr}};
  g_application_add_main_option_entries(G_APPLICATION(self), entries);
}

MyApplication* my_application_new() {
  g_set_prgname(APPLICATION_ID);
  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_DEFAULT_FLAGS, nullptr));
}
