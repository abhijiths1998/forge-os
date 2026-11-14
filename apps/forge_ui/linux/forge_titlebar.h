// A title bar for Forge's Flutter apps. Hyprland draws no titlebars, so
// each app window gets a GTK header bar: its title, maximise and close, and
// something to drag. It's transparent, so the window's glass (and the blur
// Hyprland puts behind it) runs right to the top; Hyprland's own rounding
// and shadow stand in for GTK's client-side ones.
//
// Runners include it by relative path (apps/<app>/linux/runner ->
// apps/forge_ui/linux); apps/build-packages.sh copies forge_ui beside each
// app, so the path holds in the ISO build too.
#ifndef FORGE_TITLEBAR_H_
#define FORGE_TITLEBAR_H_

#include <gtk/gtk.h>

static inline void forge_add_titlebar(GtkWindow* window, const char* title) {
  GtkWidget* bar = gtk_header_bar_new();
  gtk_header_bar_set_title(GTK_HEADER_BAR(bar), title);
  gtk_header_bar_set_show_close_button(GTK_HEADER_BAR(bar), TRUE);
  gtk_header_bar_set_decoration_layout(GTK_HEADER_BAR(bar), ":maximize,close");
  gtk_widget_set_name(bar, "forge-titlebar");

  static gboolean styled = FALSE;
  if (!styled) {
    styled = TRUE;
    GtkCssProvider* css = gtk_css_provider_new();
    gtk_css_provider_load_from_data(
        css,
        "#forge-titlebar { background: transparent; background-image: none;"
        "  box-shadow: none; border: none; min-height: 36px; }"
        "#forge-titlebar button { min-width: 24px; min-height: 24px;"
        "  border-radius: 12px; }"
        "window.forge-glass, window.forge-glass decoration {"
        "  background: transparent; box-shadow: none; border: none;"
        "  border-radius: 0; margin: 0; }",
        -1, nullptr);
    gtk_style_context_add_provider_for_screen(
        gdk_screen_get_default(), GTK_STYLE_PROVIDER(css),
        GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
    g_object_unref(css);
  }
  gtk_style_context_add_class(gtk_widget_get_style_context(GTK_WIDGET(window)),
                              "forge-glass");
  gtk_widget_show(bar);
  gtk_window_set_titlebar(window, bar);
}

#endif  // FORGE_TITLEBAR_H_
