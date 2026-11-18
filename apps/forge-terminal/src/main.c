/* Forge Terminal: GTK4 + VTE. Tabs and splits in a client-side title strip
 * (Hyprland draws no titlebars), the desktop's theme applied live, and a
 * drop-down mode on a layer-shell surface. See README.md. */
#include <errno.h>
#include <gtk/gtk.h>
#include <gtk4-layer-shell.h>
#include <pwd.h>
#include <string.h>
#include <sys/types.h>
#include <unistd.h>
#include <vte/vte.h>

#include "theme.h"

#define APP_ID "org.forgeos.terminal"
#define DROPDOWN_ID "org.forgeos.terminal.dropdown"
#define FALLBACK_FONT "JetBrainsMono Nerd Font"
/* PCRE2 flags, so we needn't include pcre2.h for two constants. */
#define RX_CASELESS 0x00000008u
#define RX_MULTILINE 0x00000400u
#define URL_REGEX "(?:https?|ftp|file)://[^\\s<>\"'`]+[^\\s<>\"'`.,;:!?)\\]}]"

static const char HELP[] =
    "FORGE-TERMINAL(1)\n"
    "\n"
    "NAME\n"
    "    forge-terminal - Forge OS's terminal (GTK4 + VTE)\n"
    "\n"
    "SYNOPSIS\n"
    "    forge-terminal [--workdir DIR] [--hold] [-e COMMAND [ARG...]]\n"
    "    forge-terminal [DIR]\n"
    "    forge-terminal --dropdown\n"
    "    forge-terminal --help | --version\n"
    "\n"
    "OPTIONS\n"
    "    -w, --workdir DIR   start in DIR (a lone DIR argument does the same)\n"
    "    -e, -x COMMAND...   run COMMAND instead of the login shell; the rest\n"
    "                        of the line is its arguments\n"
    "        --hold          keep the tab open after the command exits\n"
    "        --dropdown      toggle the drop-down terminal: a layer-shell surface,\n"
    "                        60% of the screen high, sliding in from the top. The\n"
    "                        first call starts it, later calls hide and show it\n"
    "    -h, --help          show this text\n"
    "    -V, --version       show the version and what VTE was built with\n"
    "\n"
    "KEYS\n"
    "    Ctrl+Shift+T / W        new tab / close tab\n"
    "    Ctrl+PgUp / PgDn        previous / next tab\n"
    "    Ctrl+Shift+PgUp / PgDn  move the tab left / right\n"
    "    Ctrl+Shift+E / O        split side by side / stacked\n"
    "    Alt+arrows              move focus between panes\n"
    "    Ctrl+Shift+C / V        copy / paste\n"
    "    Ctrl+Shift+F            search (Enter next, Shift+Enter previous, Esc closes)\n"
    "    Ctrl+plus / minus / 0   zoom in / out / reset\n"
    "    Ctrl+click              open a link\n"
    "\n"
    "FILES\n"
    "    ~/.config/forge/theme.json     dark, accent, terminalOpacity (watched)\n"
    "    ~/.config/forge/terminal.json  fontSize, scrollback, font (optional)\n";

typedef struct _Win Win;
typedef struct {
    Win *win;
    GtkWidget *page; /* a box holding the pane tree */
    GtkWidget *button;
    GtkWidget *label;
    VteTerminal *focus; /* the pane that had focus last */
} Tab;

struct _Win {
    GtkWindow *window;
    GtkWidget *tabbox, *stack, *search_bar, *search_entry;
    GPtrArray *tabs;
    Tab *current;
    gboolean dropdown, hold;
    gboolean closing; /* the user confirmed; skip the prompt */
    char *workdir;
    /* drop-down slide */
    int dd_height, dd_margin;
    gint64 dd_start;
    gboolean dd_showing;
    guint dd_tick;
};

static ForgeTheme the_theme;
static ForgePalette the_palette;
static ForgeSettings the_settings;
static GtkCssProvider *css;
static GApplication *the_app;
static Win *dropdown_win;
static VteRegex *url_regex;
static char *font_name;

/* ---- theme and settings ------------------------------------------------ */

static char *css_rgba(GdkRGBA c, double alpha)
{
    c.alpha = alpha;
    return gdk_rgba_to_string(&c);
}

static char *pick_font(void)
{
    if (the_settings.font)
        return g_strdup_printf("%s %g", the_settings.font, the_settings.font_size);
    /* Pango resolves "monospace" through fontconfig's alias; if that gives no
     * fixed-width family at all (a bare system), use the Forge default. */
    PangoFontMap *map = pango_cairo_font_map_get_default();
    PangoFontFamily *fam = map ? pango_font_map_get_family(map, "monospace") : NULL;
    if (fam && pango_font_family_is_monospace(fam))
        return g_strdup_printf("monospace %g", the_settings.font_size);
    return g_strdup_printf("%s %g", FALLBACK_FONT, the_settings.font_size);
}

static void apply_css(void)
{
    double a = the_palette.bg.alpha;
    g_autofree char *bg = css_rgba(the_palette.bg, a);
    g_autofree char *bg_solid = css_rgba(the_palette.bg, MAX(a, 0.92));
    g_autofree char *fg = css_rgba(the_palette.fg, 1.0);
    g_autofree char *fg_dim = css_rgba(the_palette.fg, 0.62);
    g_autofree char *acc = css_rgba(the_theme.accent, 1.0);
    g_autofree char *acc_line = css_rgba(the_theme.accent, 0.30);
    g_autofree char *acc_bg = css_rgba(the_theme.accent, 0.22);
    g_autofree char *acc_hover = css_rgba(the_theme.accent, 0.14);

    g_autofree char *text = g_strdup_printf(
        "window.forge-term { background: transparent; box-shadow: none; color: %s; }\n"
        "window.forge-term.dropdown { border-radius: 0 0 14px 14px; }\n"
        ".forge-strip { background-color: %s; padding: 5px 8px; border-bottom: 1px solid %s; }\n"
        ".forge-tab { padding: 3px 4px 3px 10px; border-radius: 8px; color: %s; }\n"
        ".forge-tab:hover { background-color: %s; }\n"
        ".forge-tab.active { background-color: %s; color: %s; }\n"
        ".forge-tab label { min-width: 4em; }\n"
        ".forge-strip button { min-height: 0; min-width: 0; padding: 1px 8px; border-radius: 8px;"
        "  background: none; box-shadow: none; border: none; color: %s; }\n"
        ".forge-strip button:hover { background-color: %s; color: %s; }\n"
        ".forge-search { background-color: %s; padding: 5px 8px; border-top: 1px solid %s; }\n"
        "paned > separator { min-width: 1px; min-height: 1px; background-color: %s; }\n"
        "paned > separator { background-clip: border-box; }\n",
        fg, bg, acc_line, fg_dim, acc_hover, acc_bg, fg, fg_dim, acc_hover, acc, bg_solid, acc_line,
        acc_line);
    gtk_css_provider_load_from_string(css, text);

    GtkSettings *gs = gtk_settings_get_default();
    if (gs) {
#if GTK_CHECK_VERSION(4, 20, 0)
        g_object_set(gs, "gtk-interface-color-scheme",
                     the_theme.dark ? GTK_INTERFACE_COLOR_SCHEME_DARK : GTK_INTERFACE_COLOR_SCHEME_LIGHT, NULL);
#else
        g_object_set(gs, "gtk-application-prefer-dark-theme", the_theme.dark, NULL);
#endif
    }
}

static void style_terminal(VteTerminal *t)
{
    const ForgePalette *p = &the_palette;
    vte_terminal_set_colors(t, &p->fg, &p->bg, p->ansi, 16);
    vte_terminal_set_color_cursor(t, &p->cursor);
    vte_terminal_set_color_cursor_foreground(t, &p->cursor_fg);
    vte_terminal_set_color_highlight(t, &p->selection);
    vte_terminal_set_color_highlight_foreground(t, NULL);
    vte_terminal_set_cursor_shape(t, VTE_CURSOR_SHAPE_BLOCK);

    PangoFontDescription *fd = pango_font_description_from_string(font_name);
    vte_terminal_set_font(t, fd);
    pango_font_description_free(fd);
    vte_terminal_set_scrollback_lines(t, the_settings.scrollback);
}

static void for_each_term(GtkWidget *w, void (*fn)(VteTerminal *, gpointer), gpointer data)
{
    if (VTE_IS_TERMINAL(w)) {
        fn(VTE_TERMINAL(w), data);
    } else if (GTK_IS_PANED(w)) {
        for_each_term(gtk_paned_get_start_child(GTK_PANED(w)), fn, data);
        for_each_term(gtk_paned_get_end_child(GTK_PANED(w)), fn, data);
    } else if (GTK_IS_BOX(w)) {
        for (GtkWidget *c = gtk_widget_get_first_child(w); c; c = gtk_widget_get_next_sibling(c))
            for_each_term(c, fn, data);
    }
}

static void style_cb(VteTerminal *t, gpointer data)
{
    (void)data;
    style_terminal(t);
}

static void restyle_all(void)
{
    if (!the_app)
        return;
    for (GList *l = gtk_application_get_windows(GTK_APPLICATION(the_app)); l; l = l->next) {
        Win *w = g_object_get_data(G_OBJECT(l->data), "forge-win");
        if (!w)
            continue;
        for (guint i = 0; i < w->tabs->len; i++)
            for_each_term(((Tab *)g_ptr_array_index(w->tabs, i))->page, style_cb, NULL);
    }
}

static void reload_config(void)
{
    g_autofree char *tp = forge_config_path("theme.json");
    g_autofree char *sp = forge_config_path("terminal.json");
    forge_theme_load(tp, &the_theme);
    forge_settings_clear(&the_settings);
    forge_settings_load(sp, &the_settings);
    forge_palette_for(&the_theme, &the_palette);
    g_free(font_name);
    font_name = pick_font();
    apply_css();
    restyle_all();
}

static void on_config_changed(GFileMonitor *m, GFile *f, GFile *o, GFileMonitorEvent ev, gpointer d)
{
    (void)m; (void)f; (void)o; (void)d;
    /* Writers usually rename a temp file over it, so any of these will do. */
    if (ev == G_FILE_MONITOR_EVENT_CHANGED || ev == G_FILE_MONITOR_EVENT_CREATED
        || ev == G_FILE_MONITOR_EVENT_RENAMED || ev == G_FILE_MONITOR_EVENT_MOVED_IN
        || ev == G_FILE_MONITOR_EVENT_CHANGES_DONE_HINT || ev == G_FILE_MONITOR_EVENT_DELETED)
        reload_config();
}

static void watch_config(void)
{
    /* Watch the folder, not the files: they get replaced, and may not exist yet. */
    g_autofree char *dir = g_build_filename(g_get_user_config_dir(), "forge", NULL);
    g_mkdir_with_parents(dir, 0755);
    g_autoptr(GFile) f = g_file_new_for_path(dir);
    GFileMonitor *mon = g_file_monitor_directory(f, G_FILE_MONITOR_WATCH_MOVES, NULL, NULL);
    if (mon)
        g_signal_connect(mon, "changed", G_CALLBACK(on_config_changed), NULL);
}

/* ---- helpers ------------------------------------------------------------ */

static const char *user_shell(void)
{
    const char *s = g_getenv("SHELL");
    if (s && *s)
        return s;
    struct passwd *pw = getpwuid(getuid());
    if (pw && pw->pw_shell && *pw->pw_shell)
        return pw->pw_shell;
    return "/bin/sh";
}

static char *dir_of(VteTerminal *t)
{
    /* The termprop is a URI object with its own getter; this old one still
     * gives the OSC 7 string, which is all we want. */
    G_GNUC_BEGIN_IGNORE_DEPRECATIONS
    const char *uri = t ? vte_terminal_get_current_directory_uri(t) : NULL;
    G_GNUC_END_IGNORE_DEPRECATIONS
    return uri ? g_filename_from_uri(uri, NULL, NULL) : NULL;
}

static gboolean has_running_child(VteTerminal *t)
{
    VtePty *pty = vte_terminal_get_pty(t);
    GPid pid = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(t), "forge-pid"));
    if (!pty || pid <= 0)
        return FALSE;
    pid_t fg = tcgetpgrp(vte_pty_get_fd(pty));
    return fg > 0 && fg != pid;
}

static void running_cb(VteTerminal *t, gpointer data)
{
    if (has_running_child(t))
        *(gboolean *)data = TRUE;
}

static gboolean tab_running(Tab *tab)
{
    gboolean r = FALSE;
    for_each_term(tab->page, running_cb, &r);
    return r;
}

typedef struct { void (*yes)(gpointer); gpointer data; } AskCtx;

static void ask_done(GObject *src, GAsyncResult *res, gpointer ud)
{
    AskCtx *cx = ud;
    int r = gtk_alert_dialog_choose_finish(GTK_ALERT_DIALOG(src), res, NULL);
    if (r == 1)
        cx->yes(cx->data);
    g_free(cx);
}

static void ask(Win *w, const char *message, void (*yes)(gpointer), gpointer data)
{
    GtkAlertDialog *d = gtk_alert_dialog_new("%s", message);
    const char *buttons[] = { "Cancel", "Close anyway", NULL };
    gtk_alert_dialog_set_buttons(d, buttons);
    gtk_alert_dialog_set_cancel_button(d, 0);
    gtk_alert_dialog_set_default_button(d, 0);
    AskCtx *c = g_new(AskCtx, 1);
    c->yes = yes;
    c->data = data;
    gtk_alert_dialog_choose(d, w->window, NULL, ask_done, c);
    g_object_unref(d);
}

/* ---- tabs and panes ------------------------------------------------------ */

static void tab_select(Win *w, Tab *tab);
static VteTerminal *new_pane(Win *w, Tab *tab, const char *workdir, char **command);
static void tab_close_now(Tab *tab);

static void update_title(Tab *tab)
{
    const char *t = tab->focus ? vte_terminal_get_termprop_string_by_id(
                                     tab->focus, VTE_PROPERTY_ID_XTERM_TITLE, NULL)
                                : NULL;
    g_autofree char *dir = dir_of(tab->focus);
    g_autofree char *base = dir ? g_path_get_basename(dir) : NULL;
    gtk_label_set_text(GTK_LABEL(tab->label), (t && *t) ? t : (base ? base : "Terminal"));
}

static void on_termprop(VteTerminal *t, const char *prop, gpointer data)
{
    (void)t;
    if (!strcmp(prop, VTE_TERMPROP_XTERM_TITLE) || !strcmp(prop, VTE_TERMPROP_CURRENT_DIRECTORY_URI))
        update_title(data);
}

static void on_focus_enter(GtkEventControllerFocus *c, gpointer data)
{
    Tab *tab = data;
    tab->focus = VTE_TERMINAL(gtk_event_controller_get_widget(GTK_EVENT_CONTROLLER(c)));
    update_title(tab);
}

static VteTerminal *first_term(GtkWidget *w)
{
    if (VTE_IS_TERMINAL(w))
        return VTE_TERMINAL(w);
    if (GTK_IS_PANED(w)) {
        VteTerminal *t = first_term(gtk_paned_get_start_child(GTK_PANED(w)));
        return t ? t : first_term(gtk_paned_get_end_child(GTK_PANED(w)));
    }
    if (GTK_IS_BOX(w) && gtk_widget_get_first_child(w))
        return first_term(gtk_widget_get_first_child(w));
    return NULL;
}

/* Replace a pane (or a paned) by another widget in its parent. */
static void replace_child(GtkWidget *old, GtkWidget *repl)
{
    GtkWidget *parent = gtk_widget_get_parent(old);
    g_object_ref(old);
    if (GTK_IS_PANED(parent)) {
        gboolean start = gtk_paned_get_start_child(GTK_PANED(parent)) == old;
        if (start)
            gtk_paned_set_start_child(GTK_PANED(parent), repl);
        else
            gtk_paned_set_end_child(GTK_PANED(parent), repl);
    } else {
        gtk_box_remove(GTK_BOX(parent), old);
        gtk_box_append(GTK_BOX(parent), repl);
    }
    g_object_unref(old);
}

static void close_pane(VteTerminal *t)
{
    Tab *tab = g_object_get_data(G_OBJECT(t), "forge-tab");
    GtkWidget *parent = gtk_widget_get_parent(GTK_WIDGET(t));
    if (!GTK_IS_PANED(parent)) {
        tab_close_now(tab);
        return;
    }
    GtkPaned *p = GTK_PANED(parent);
    GtkWidget *sib = gtk_paned_get_start_child(p) == GTK_WIDGET(t) ? gtk_paned_get_end_child(p)
                                                                   : gtk_paned_get_start_child(p);
    g_object_ref(sib);
    gtk_paned_set_start_child(p, NULL);
    gtk_paned_set_end_child(p, NULL);
    replace_child(GTK_WIDGET(p), sib);
    g_object_unref(sib);
    VteTerminal *next = first_term(sib);
    if (tab->focus == t)
        tab->focus = next;
    if (next)
        gtk_widget_grab_focus(GTK_WIDGET(next));
}

static void on_child_exited(VteTerminal *t, int status, gpointer data)
{
    Win *w = data;
    (void)status;
    if (w->hold)
        return;
    close_pane(t);
}

static void on_spawned(VteTerminal *t, GPid pid, GError *err, gpointer data)
{
    (void)data;
    if (err) {
        g_autofree char *m = g_strdup_printf("\r\nCould not start the shell: %s\r\n", err->message);
        vte_terminal_feed(t, m, -1);
        return;
    }
    g_object_set_data(G_OBJECT(t), "forge-pid", GINT_TO_POINTER(pid));
}

static void open_link(GtkWidget *w, const char *uri)
{
    GtkUriLauncher *l = gtk_uri_launcher_new(uri);
    gtk_uri_launcher_launch(l, GTK_WINDOW(gtk_widget_get_root(w)), NULL, NULL, NULL);
    g_object_unref(l);
}

static void on_click(GtkGestureClick *g, int n, double x, double y, gpointer data)
{
    (void)n; (void)data;
    GdkModifierType st = gtk_event_controller_get_current_event_state(GTK_EVENT_CONTROLLER(g));
    if (!(st & GDK_CONTROL_MASK))
        return;
    VteTerminal *t = VTE_TERMINAL(gtk_event_controller_get_widget(GTK_EVENT_CONTROLLER(g)));
    g_autofree char *uri = vte_terminal_check_hyperlink_at(t, x, y);
    if (!uri) {
        int tag;
        uri = vte_terminal_check_match_at(t, x, y, &tag);
    }
    if (uri) {
        gtk_gesture_set_state(GTK_GESTURE(g), GTK_EVENT_SEQUENCE_CLAIMED);
        open_link(GTK_WIDGET(t), uri);
    }
}

static VteTerminal *new_pane(Win *w, Tab *tab, const char *workdir, char **command)
{
    GtkWidget *w_t = vte_terminal_new();
    VteTerminal *t = VTE_TERMINAL(w_t);
    gtk_widget_set_hexpand(w_t, TRUE);
    gtk_widget_set_vexpand(w_t, TRUE);
    g_object_set_data(G_OBJECT(t), "forge-tab", tab);
    style_terminal(t);

    vte_terminal_set_allow_hyperlink(t, TRUE);
    vte_terminal_set_audible_bell(t, FALSE);
    vte_terminal_set_scroll_on_keystroke(t, TRUE);
    vte_terminal_set_mouse_autohide(t, TRUE);
    vte_terminal_set_enable_sixel(t, !!(vte_get_feature_flags() & VTE_FEATURE_FLAG_SIXEL));
    if (url_regex) {
        int tag = vte_terminal_match_add_regex(t, url_regex, 0);
        vte_terminal_match_set_cursor_name(t, tag, "pointer");
    }

    GtkEventController *fc = gtk_event_controller_focus_new();
    g_signal_connect(fc, "enter", G_CALLBACK(on_focus_enter), tab);
    gtk_widget_add_controller(w_t, fc);
    GtkGesture *click = gtk_gesture_click_new();
    gtk_gesture_single_set_button(GTK_GESTURE_SINGLE(click), 1);
    gtk_event_controller_set_propagation_phase(GTK_EVENT_CONTROLLER(click), GTK_PHASE_CAPTURE);
    g_signal_connect(click, "pressed", G_CALLBACK(on_click), NULL);
    gtk_widget_add_controller(w_t, GTK_EVENT_CONTROLLER(click));

    g_signal_connect(t, "termprop-changed", G_CALLBACK(on_termprop), tab);
    g_signal_connect(t, "child-exited", G_CALLBACK(on_child_exited), w);

    /* A login shell, as other terminals do; or the command we were given. */
    const char *shell = user_shell();
    char *shell_argv[] = { (char *)shell, "-l", NULL };
    char **argv = command ? command : shell_argv;
    g_auto(GStrv) env = g_get_environ();
    env = g_environ_setenv(env, "TERM", "xterm-256color", TRUE);
    env = g_environ_setenv(env, "COLORTERM", "truecolor", TRUE);
    env = g_environ_unsetenv(env, "TERM_PROGRAM");
    const char *dir = (workdir && g_file_test(workdir, G_FILE_TEST_IS_DIR)) ? workdir : g_get_home_dir();
    vte_terminal_spawn_async(t, VTE_PTY_DEFAULT, dir, argv, env, G_SPAWN_SEARCH_PATH, NULL, NULL,
                             NULL, -1, NULL, on_spawned, NULL);
    return t;
}

static void split(Win *w, GtkOrientation o)
{
    Tab *tab = w->current;
    if (!tab || !tab->focus)
        return;
    VteTerminal *cur = tab->focus;
    g_autofree char *dir = dir_of(cur);
    GtkWidget *paned = gtk_paned_new(o);
    gtk_widget_set_hexpand(paned, TRUE);
    gtk_widget_set_vexpand(paned, TRUE);
    gtk_paned_set_wide_handle(GTK_PANED(paned), FALSE);
    gtk_paned_set_resize_start_child(GTK_PANED(paned), TRUE);
    gtk_paned_set_resize_end_child(GTK_PANED(paned), TRUE);
    gtk_paned_set_shrink_start_child(GTK_PANED(paned), FALSE);
    gtk_paned_set_shrink_end_child(GTK_PANED(paned), FALSE);

    GtkWidget *old = GTK_WIDGET(cur);
    g_object_ref(old);
    replace_child(old, paned);
    gtk_paned_set_start_child(GTK_PANED(paned), old);
    g_object_unref(old);
    VteTerminal *nt = new_pane(w, tab, dir, NULL);
    gtk_paned_set_end_child(GTK_PANED(paned), GTK_WIDGET(nt));
    gtk_widget_grab_focus(GTK_WIDGET(nt));
}

static void tab_select(Win *w, Tab *tab)
{
    if (w->current && w->current->button)
        gtk_widget_remove_css_class(w->current->button, "active");
    w->current = tab;
    gtk_widget_add_css_class(tab->button, "active");
    gtk_stack_set_visible_child(GTK_STACK(w->stack), tab->page);
    VteTerminal *t = tab->focus ? tab->focus : first_term(tab->page);
    if (t)
        gtk_widget_grab_focus(GTK_WIDGET(t));
}

static int tab_index(Win *w, Tab *tab)
{
    for (guint i = 0; i < w->tabs->len; i++)
        if (g_ptr_array_index(w->tabs, i) == tab)
            return (int)i;
    return -1;
}

static void dropdown_hide(Win *w);

static void tab_close_now(Tab *tab)
{
    Win *w = tab->win;
    int i = tab_index(w, tab);
    if (i < 0)
        return;
    g_ptr_array_remove_index(w->tabs, i);
    gtk_box_remove(GTK_BOX(w->tabbox), tab->button);
    gtk_stack_remove(GTK_STACK(w->stack), tab->page);
    if (w->current == tab)
        w->current = NULL;
    g_free(tab);
    if (w->tabs->len == 0) {
        if (w->dropdown)
            dropdown_hide(w); /* a fresh tab opens next time it's shown */
        else
            gtk_window_destroy(w->window);
        return;
    }
    if (!w->current)
        tab_select(w, g_ptr_array_index(w->tabs, MIN(i, (int)w->tabs->len - 1)));
}

static void tab_close_confirmed(gpointer data)
{
    tab_close_now(data);
}

static void tab_close(Win *w, Tab *tab)
{
    if (tab_running(tab))
        ask(w, "This tab is running a program. Close it anyway?", tab_close_confirmed, tab);
    else
        tab_close_now(tab);
}

static void on_tab_pressed(GtkGestureClick *g, int n, double x, double y, gpointer data)
{
    (void)n; (void)x; (void)y;
    Tab *tab = data;
    guint button = gtk_gesture_single_get_current_button(GTK_GESTURE_SINGLE(g));
    if (button == 2)
        tab_close(tab->win, tab);
    else
        tab_select(tab->win, tab);
}

static void on_tab_close_clicked(GtkButton *b, gpointer data)
{
    (void)b;
    Tab *tab = data;
    tab_close(tab->win, tab);
}

static Tab *new_tab(Win *w, const char *workdir, char **command)
{
    Tab *tab = g_new0(Tab, 1);
    tab->win = w;
    tab->page = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
    gtk_widget_set_hexpand(tab->page, TRUE);
    gtk_widget_set_vexpand(tab->page, TRUE);

    tab->button = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 2);
    gtk_widget_add_css_class(tab->button, "forge-tab");
    tab->label = gtk_label_new("Terminal");
    gtk_label_set_ellipsize(GTK_LABEL(tab->label), PANGO_ELLIPSIZE_END);
    gtk_label_set_max_width_chars(GTK_LABEL(tab->label), 22);
    GtkWidget *x = gtk_button_new_with_label("×");
    gtk_widget_set_focus_on_click(x, FALSE);
    gtk_widget_set_focusable(x, FALSE);
    gtk_widget_set_tooltip_text(x, "Close tab");
    g_signal_connect(x, "clicked", G_CALLBACK(on_tab_close_clicked), tab);
    gtk_box_append(GTK_BOX(tab->button), tab->label);
    gtk_box_append(GTK_BOX(tab->button), x);
    GtkGesture *g = gtk_gesture_click_new();
    gtk_gesture_single_set_button(GTK_GESTURE_SINGLE(g), 0);
    g_signal_connect(g, "pressed", G_CALLBACK(on_tab_pressed), tab);
    gtk_widget_add_controller(tab->button, GTK_EVENT_CONTROLLER(g));

    /* After the current tab, as most terminals do. */
    int at = w->current ? tab_index(w, w->current) + 1 : (int)w->tabs->len;
    g_ptr_array_insert(w->tabs, at, tab);
    gtk_box_append(GTK_BOX(w->tabbox), tab->button);
    if (at > 0)
        gtk_box_reorder_child_after(GTK_BOX(w->tabbox), tab->button,
                                    ((Tab *)g_ptr_array_index(w->tabs, at - 1))->button);
    else
        gtk_box_reorder_child_after(GTK_BOX(w->tabbox), tab->button, NULL);
    gtk_stack_add_child(GTK_STACK(w->stack), tab->page);

    VteTerminal *t = new_pane(w, tab, workdir, command);
    tab->focus = t;
    gtk_box_append(GTK_BOX(tab->page), GTK_WIDGET(t));
    tab_select(w, tab);
    return tab;
}

static void new_tab_here(Win *w)
{
    g_autofree char *dir = (w->current) ? dir_of(w->current->focus) : NULL;
    new_tab(w, dir ? dir : w->workdir, NULL);
}

static void tab_step(Win *w, int delta)
{
    if (!w->current || w->tabs->len < 2)
        return;
    int n = (int)w->tabs->len;
    tab_select(w, g_ptr_array_index(w->tabs, (tab_index(w, w->current) + delta + n) % n));
}

static void tab_move(Win *w, int delta)
{
    if (!w->current)
        return;
    int i = tab_index(w, w->current), j = i + delta;
    if (j < 0 || j >= (int)w->tabs->len)
        return;
    Tab *other = g_ptr_array_index(w->tabs, j);
    g_ptr_array_remove_index(w->tabs, i);
    g_ptr_array_insert(w->tabs, j, w->current);
    gtk_box_reorder_child_after(GTK_BOX(w->tabbox), w->current->button,
                                delta > 0 ? other->button
                                          : (j > 0 ? ((Tab *)g_ptr_array_index(w->tabs, j - 1))->button
                                                   : NULL));
}

/* ---- shortcuts ----------------------------------------------------------- */

typedef struct {
    VteTerminal *best;
    double best_d;
    graphene_rect_t cur;
    GtkWidget *page;
    int dx, dy;
} FocusSearch;

static void focus_cb(VteTerminal *t, gpointer data)
{
    FocusSearch *s = data;
    graphene_rect_t r;
    if (!gtk_widget_compute_bounds(GTK_WIDGET(t), s->page, &r))
        return;
    double cx = s->cur.origin.x + s->cur.size.width / 2, cy = s->cur.origin.y + s->cur.size.height / 2;
    double rx = r.origin.x + r.size.width / 2, ry = r.origin.y + r.size.height / 2;
    double ddx = rx - cx, ddy = ry - cy;
    /* Along the direction; the cross axis counts double so a pane straight
     * across beats one that's merely nearer. */
    double along = ddx * s->dx + ddy * s->dy;
    double across = s->dx ? ddy : ddx;
    if (along < 1.0)
        return;
    double d = along + 2 * (across < 0 ? -across : across);
    if (!s->best || d < s->best_d) {
        s->best = t;
        s->best_d = d;
    }
}

static void focus_dir(Win *w, int dx, int dy)
{
    if (!w->current || !w->current->focus)
        return;
    FocusSearch s = { NULL, 0, { { 0, 0 }, { 0, 0 } }, w->current->page, dx, dy };
    if (!gtk_widget_compute_bounds(GTK_WIDGET(w->current->focus), s.page, &s.cur))
        return;
    for_each_term(s.page, focus_cb, &s);
    if (s.best)
        gtk_widget_grab_focus(GTK_WIDGET(s.best));
}

static void zoom(Win *w, double factor)
{
    if (!w->current || !w->current->focus)
        return;
    VteTerminal *t = w->current->focus;
    double s = factor == 0 ? 1.0 : CLAMP(vte_terminal_get_font_scale(t) * factor, 0.4, 5.0);
    vte_terminal_set_font_scale(t, s);
}

static void search_show(Win *w)
{
    gtk_widget_set_visible(w->search_bar, TRUE);
    gtk_widget_grab_focus(w->search_entry);
    gtk_editable_select_region(GTK_EDITABLE(w->search_entry), 0, -1);
}

static void search_hide(Win *w)
{
    gtk_widget_set_visible(w->search_bar, FALSE);
    if (w->current && w->current->focus) {
        vte_terminal_search_set_regex(w->current->focus, NULL, 0);
        gtk_widget_grab_focus(GTK_WIDGET(w->current->focus));
    }
}

static void search_changed(GtkSearchEntry *e, gpointer data)
{
    Win *w = data;
    if (!w->current || !w->current->focus)
        return;
    VteTerminal *t = w->current->focus;
    const char *text = gtk_editable_get_text(GTK_EDITABLE(e));
    if (!*text) {
        vte_terminal_search_set_regex(t, NULL, 0);
        return;
    }
    g_autofree char *esc = g_regex_escape_string(text, -1);
    g_autoptr(GError) err = NULL;
    VteRegex *rx = vte_regex_new_for_search(esc, -1, RX_CASELESS | RX_MULTILINE, &err);
    if (!rx)
        return;
    vte_terminal_search_set_regex(t, rx, 0);
    vte_terminal_search_set_wrap_around(t, TRUE);
    vte_terminal_search_find_next(t);
    vte_regex_unref(rx);
}

static void search_next(GtkWidget *e, gpointer data)
{
    (void)e;
    Win *w = data;
    if (w->current && w->current->focus)
        vte_terminal_search_find_next(w->current->focus);
}

static void search_prev(GtkWidget *e, gpointer data)
{
    (void)e;
    Win *w = data;
    if (w->current && w->current->focus)
        vte_terminal_search_find_previous(w->current->focus);
}

static void search_stop(GtkSearchEntry *e, gpointer data)
{
    (void)e;
    search_hide(data);
}

typedef enum {
    A_NEW_TAB, A_CLOSE_TAB, A_PREV, A_NEXT, A_MOVE_L, A_MOVE_R, A_SPLIT_H, A_SPLIT_V,
    A_LEFT, A_RIGHT, A_UP, A_DOWN, A_COPY, A_PASTE, A_FIND, A_ZIN, A_ZOUT, A_ZRESET
} Action;

static gboolean run_action(GtkWidget *widget, GVariant *args, gpointer data)
{
    (void)widget;
    Win *w = g_object_get_data(G_OBJECT(widget), "forge-win");
    Action a = GPOINTER_TO_INT(data);
    (void)args;
    if (!w)
        return FALSE;
    VteTerminal *t = w->current ? w->current->focus : NULL;
    switch (a) {
    case A_NEW_TAB: new_tab_here(w); break;
    case A_CLOSE_TAB: if (w->current) tab_close(w, w->current); break;
    case A_PREV: tab_step(w, -1); break;
    case A_NEXT: tab_step(w, 1); break;
    case A_MOVE_L: tab_move(w, -1); break;
    case A_MOVE_R: tab_move(w, 1); break;
    case A_SPLIT_H: split(w, GTK_ORIENTATION_HORIZONTAL); break;
    case A_SPLIT_V: split(w, GTK_ORIENTATION_VERTICAL); break;
    case A_LEFT: focus_dir(w, -1, 0); break;
    case A_RIGHT: focus_dir(w, 1, 0); break;
    case A_UP: focus_dir(w, 0, -1); break;
    case A_DOWN: focus_dir(w, 0, 1); break;
    case A_COPY: if (t) vte_terminal_copy_clipboard_format(t, VTE_FORMAT_TEXT); break;
    case A_PASTE: if (t) vte_terminal_paste_clipboard(t); break;
    case A_FIND: search_show(w); break;
    case A_ZIN: zoom(w, 1.1); break;
    case A_ZOUT: zoom(w, 1.0 / 1.1); break;
    case A_ZRESET: zoom(w, 0); break;
    }
    return TRUE;
}

static void add_shortcuts(Win *w)
{
    static const struct { const char *keys; Action a; } table[] = {
        { "<Control><Shift>t", A_NEW_TAB }, { "<Control><Shift>w", A_CLOSE_TAB },
        { "<Control>Page_Up", A_PREV }, { "<Control>Page_Down", A_NEXT },
        { "<Control><Shift>Page_Up", A_MOVE_L }, { "<Control><Shift>Page_Down", A_MOVE_R },
        { "<Control><Shift>e", A_SPLIT_H }, { "<Control><Shift>o", A_SPLIT_V },
        { "<Alt>Left", A_LEFT }, { "<Alt>Right", A_RIGHT }, { "<Alt>Up", A_UP }, { "<Alt>Down", A_DOWN },
        { "<Control><Shift>c", A_COPY }, { "<Control><Shift>v", A_PASTE },
        { "<Control><Shift>f", A_FIND },
        { "<Control>plus", A_ZIN }, { "<Control>equal", A_ZIN }, { "<Control>KP_Add", A_ZIN },
        { "<Control><Shift>plus", A_ZIN },
        { "<Control>minus", A_ZOUT }, { "<Control>KP_Subtract", A_ZOUT },
        { "<Control>0", A_ZRESET }, { "<Control>KP_0", A_ZRESET },
    };
    /* Capture phase, so they win over the terminal's own key handling. */
    GtkEventController *sc = gtk_shortcut_controller_new();
    gtk_event_controller_set_propagation_phase(sc, GTK_PHASE_CAPTURE);
    gtk_shortcut_controller_set_scope(GTK_SHORTCUT_CONTROLLER(sc), GTK_SHORTCUT_SCOPE_LOCAL);
    for (guint i = 0; i < G_N_ELEMENTS(table); i++) {
        GtkShortcut *s = gtk_shortcut_new(
            gtk_shortcut_trigger_parse_string(table[i].keys),
            gtk_callback_action_new(run_action, GINT_TO_POINTER(table[i].a), NULL));
        gtk_shortcut_controller_add_shortcut(GTK_SHORTCUT_CONTROLLER(sc), s);
    }
    gtk_widget_add_controller(GTK_WIDGET(w->window), sc);
}

/* ---- windows --------------------------------------------------------------- */

static void close_window_now(gpointer data)
{
    Win *w = data;
    w->closing = TRUE;
    gtk_window_destroy(w->window);
}

static gboolean on_close_request(GtkWindow *window, gpointer data)
{
    Win *w = data;
    if (w->dropdown) {
        dropdown_hide(w);
        return TRUE;
    }
    if (w->closing)
        return FALSE;
    for (guint i = 0; i < w->tabs->len; i++) {
        if (tab_running(g_ptr_array_index(w->tabs, i))) {
            ask(w, "A program is still running in this window. Close it anyway?", close_window_now, w);
            return TRUE;
        }
    }
    (void)window;
    return FALSE;
}

static void on_window_destroy(GtkWidget *widget, gpointer data)
{
    (void)widget;
    Win *w = data;
    g_ptr_array_free(w->tabs, TRUE); /* tab structs are leaked with the window: it's closing */
    g_free(w->workdir);
    g_free(w);
}

static void on_new_tab_clicked(GtkButton *b, gpointer data)
{
    (void)b;
    new_tab_here(data);
}

static void on_close_clicked(GtkButton *b, gpointer data)
{
    (void)b;
    Win *w = data;
    gtk_window_close(w->window);
}

static void on_strip_pressed(GtkGestureClick *g, int n, double x, double y, gpointer data)
{
    (void)x; (void)y;
    Win *w = data;
    (void)g;
    if (n == 2 && !w->dropdown) {
        if (gtk_window_is_maximized(w->window))
            gtk_window_unmaximize(w->window);
        else
            gtk_window_maximize(w->window);
    }
}

static Win *build_window(GtkApplication *app, gboolean dropdown)
{
    Win *w = g_new0(Win, 1);
    w->tabs = g_ptr_array_new();
    w->dropdown = dropdown;
    w->window = GTK_WINDOW(gtk_window_new());
    gtk_window_set_application(w->window, app);
    gtk_window_set_title(w->window, "Forge Terminal");
    gtk_window_set_icon_name(w->window, "utilities-terminal");
    gtk_window_set_decorated(w->window, FALSE);
    gtk_window_set_default_size(w->window, 920, 580);
    gtk_widget_add_css_class(GTK_WIDGET(w->window), "forge-term");
    if (dropdown)
        gtk_widget_add_css_class(GTK_WIDGET(w->window), "dropdown");
    g_object_set_data(G_OBJECT(w->window), "forge-win", w);

    /* The title strip: tabs, new tab, spacer, close. The handle moves the
     * window when dragged anywhere that isn't a button. */
    GtkWidget *strip = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 4);
    gtk_widget_add_css_class(strip, "forge-strip");
    w->tabbox = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 2);
    GtkWidget *plus = gtk_button_new_with_label("+");
    gtk_widget_set_focusable(plus, FALSE);
    gtk_widget_set_tooltip_text(plus, "New tab (Ctrl+Shift+T)");
    g_signal_connect(plus, "clicked", G_CALLBACK(on_new_tab_clicked), w);
    GtkWidget *spacer = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
    gtk_widget_set_hexpand(spacer, TRUE);
    GtkWidget *close = gtk_button_new_with_label("×");
    gtk_widget_set_focusable(close, FALSE);
    gtk_widget_set_tooltip_text(close, dropdown ? "Hide" : "Close window");
    g_signal_connect(close, "clicked", G_CALLBACK(on_close_clicked), w);
    gtk_box_append(GTK_BOX(strip), w->tabbox);
    gtk_box_append(GTK_BOX(strip), plus);
    gtk_box_append(GTK_BOX(strip), spacer);
    gtk_box_append(GTK_BOX(strip), close);
    GtkWidget *handle = gtk_window_handle_new();
    gtk_window_handle_set_child(GTK_WINDOW_HANDLE(handle), strip);
    GtkGesture *dbl = gtk_gesture_click_new();
    g_signal_connect(dbl, "pressed", G_CALLBACK(on_strip_pressed), w);
    gtk_widget_add_controller(spacer, GTK_EVENT_CONTROLLER(dbl));

    w->stack = gtk_stack_new();
    gtk_widget_set_vexpand(w->stack, TRUE);
    gtk_widget_set_hexpand(w->stack, TRUE);

    w->search_bar = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6);
    gtk_widget_add_css_class(w->search_bar, "forge-search");
    w->search_entry = gtk_search_entry_new();
    gtk_widget_set_hexpand(w->search_entry, TRUE);
    GtkWidget *prev = gtk_button_new_with_label("↑");
    GtkWidget *next = gtk_button_new_with_label("↓");
    gtk_box_append(GTK_BOX(w->search_bar), w->search_entry);
    gtk_box_append(GTK_BOX(w->search_bar), prev);
    gtk_box_append(GTK_BOX(w->search_bar), next);
    gtk_widget_set_visible(w->search_bar, FALSE);
    g_signal_connect(w->search_entry, "search-changed", G_CALLBACK(search_changed), w);
    g_signal_connect(w->search_entry, "activate", G_CALLBACK(search_next), w);
    g_signal_connect(w->search_entry, "next-match", G_CALLBACK(search_next), w);
    g_signal_connect(w->search_entry, "previous-match", G_CALLBACK(search_prev), w);
    g_signal_connect(w->search_entry, "stop-search", G_CALLBACK(search_stop), w);
    g_signal_connect(prev, "clicked", G_CALLBACK(search_prev), w);
    g_signal_connect(next, "clicked", G_CALLBACK(search_next), w);

    GtkWidget *box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
    gtk_box_append(GTK_BOX(box), handle);
    gtk_box_append(GTK_BOX(box), w->stack);
    gtk_box_append(GTK_BOX(box), w->search_bar);
    gtk_window_set_child(w->window, box);

    add_shortcuts(w);
    g_signal_connect(w->window, "close-request", G_CALLBACK(on_close_request), w);
    g_signal_connect(w->window, "destroy", G_CALLBACK(on_window_destroy), w);
    return w;
}

/* ---- drop-down ------------------------------------------------------------- */

static int primary_monitor_height(void)
{
    GListModel *mons = gdk_display_get_monitors(gdk_display_get_default());
    GdkMonitor *m = g_list_model_get_n_items(mons) ? g_list_model_get_item(mons, 0) : NULL;
    int h = 1080;
    if (m) {
        GdkRectangle r;
        gdk_monitor_get_geometry(m, &r);
        h = r.height;
        g_object_unref(m);
    }
    return h;
}

#define DD_GAP 8
#define DD_MS 180

/* A timeout, not a frame-clock tick: the clock is gone while the window is
 * hidden, and the slide has to start again on the next show. */
static gboolean dd_tick(gpointer data)
{
    Win *w = data;
    double t = (g_get_monotonic_time() - w->dd_start) / (DD_MS * 1000.0);
    t = CLAMP(t, 0.0, 1.0);
    double e = 1.0 - (1.0 - t) * (1.0 - t) * (1.0 - t); /* ease out */
    int from = w->dd_showing ? -w->dd_height : DD_GAP;
    int to = w->dd_showing ? DD_GAP : -w->dd_height;
    w->dd_margin = from + (int)((to - from) * e);
    if (gtk_layer_is_layer_window(w->window))
        gtk_layer_set_margin(w->window, GTK_LAYER_SHELL_EDGE_TOP, w->dd_margin);
    /* The margin only reaches the compositor with the next commit. */
    gtk_widget_queue_draw(GTK_WIDGET(w->window));
    if (t >= 1.0) {
        w->dd_tick = 0;
        if (!w->dd_showing) {
            /* A layer surface stays mapped, just off screen: unmapping it and
             * mapping it again leaves it blank on some compositors. */
            if (gtk_layer_is_layer_window(w->window))
                gtk_layer_set_keyboard_mode(w->window, GTK_LAYER_SHELL_KEYBOARD_MODE_NONE);
            else
                gtk_widget_set_visible(GTK_WIDGET(w->window), FALSE);
        }
        return G_SOURCE_REMOVE;
    }
    return G_SOURCE_CONTINUE;
}

static void dd_animate(Win *w, gboolean show)
{
    w->dd_showing = show;
    w->dd_start = g_get_monotonic_time();
    if (!w->dd_tick)
        w->dd_tick = g_timeout_add(12, dd_tick, w);
}

static void dd_on_map(GtkWidget *widget, gpointer data)
{
    g_signal_handlers_disconnect_by_func(widget, dd_on_map, data);
    dd_animate(data, TRUE);
}

static void dropdown_show(Win *w)
{
    if (w->tabs->len == 0)
        new_tab(w, g_get_home_dir(), NULL);
    if (gtk_layer_is_layer_window(w->window)) {
        gtk_layer_set_keyboard_mode(w->window, GTK_LAYER_SHELL_KEYBOARD_MODE_EXCLUSIVE);
        if (!gtk_widget_get_mapped(GTK_WIDGET(w->window)))
            gtk_layer_set_margin(w->window, GTK_LAYER_SHELL_EDGE_TOP, -w->dd_height);
    }
    /* Slide once the surface exists; margins set before that are lost. */
    if (gtk_widget_get_mapped(GTK_WIDGET(w->window)))
        dd_animate(w, TRUE);
    else
        g_signal_connect_data(w->window, "map", G_CALLBACK(dd_on_map), w, NULL, G_CONNECT_AFTER);
    gtk_window_present(w->window);
    if (w->current)
        tab_select(w, w->current);
}

static void dropdown_hide(Win *w)
{
    if (w->dd_showing)
        dd_animate(w, FALSE);
}

static void dropdown_toggle(GtkApplication *app)
{
    if (!dropdown_win) {
        Win *w = build_window(app, TRUE);
        dropdown_win = w;
        w->dd_height = primary_monitor_height() * 60 / 100;
        gtk_window_set_default_size(w->window, -1, w->dd_height);
        if (gtk_layer_is_supported()) {
            gtk_layer_init_for_window(w->window);
            gtk_layer_set_namespace(w->window, "forge-terminal");
            gtk_layer_set_layer(w->window, GTK_LAYER_SHELL_LAYER_TOP);
            gtk_layer_set_keyboard_mode(w->window, GTK_LAYER_SHELL_KEYBOARD_MODE_ON_DEMAND);
            gtk_layer_set_anchor(w->window, GTK_LAYER_SHELL_EDGE_TOP, TRUE);
            gtk_layer_set_anchor(w->window, GTK_LAYER_SHELL_EDGE_LEFT, TRUE);
            gtk_layer_set_anchor(w->window, GTK_LAYER_SHELL_EDGE_RIGHT, TRUE);
            gtk_layer_set_margin(w->window, GTK_LAYER_SHELL_EDGE_LEFT, 12);
            gtk_layer_set_margin(w->window, GTK_LAYER_SHELL_EDGE_RIGHT, 12);
            gtk_layer_set_margin(w->window, GTK_LAYER_SHELL_EDGE_TOP, -w->dd_height);
        } else {
            /* No layer-shell (not a wlroots-style compositor): a plain window
             * that still toggles. */
            gtk_window_set_default_size(w->window, 1200, w->dd_height);
        }
        g_signal_connect_swapped(w->window, "destroy", G_CALLBACK(g_nullify_pointer), &dropdown_win);
        dropdown_show(w);
        return;
    }
    if (dropdown_win->dd_showing)
        dropdown_hide(dropdown_win);
    else
        dropdown_show(dropdown_win);
}

/* ---- application ------------------------------------------------------------ */

static int on_command_line(GApplication *app, GApplicationCommandLine *cl, gpointer data)
{
    gboolean dropdown = GPOINTER_TO_INT(data);
    int argc;
    g_auto(GStrv) argv = g_application_command_line_get_arguments(cl, &argc);
    const char *cwd = g_application_command_line_get_cwd(cl);
    char *workdir = NULL;
    gboolean hold = FALSE;
    char **command = NULL;

    for (int i = 1; i < argc; i++) {
        const char *a = argv[i];
        if (!strcmp(a, "-e") || !strcmp(a, "-x") || !strcmp(a, "--command")) {
            if (i + 1 < argc)
                command = g_strdupv(&argv[i + 1]);
            break;
        } else if ((!strcmp(a, "-w") || !strcmp(a, "--workdir")) && i + 1 < argc) {
            g_free(workdir);
            workdir = g_strdup(argv[++i]);
        } else if (!strncmp(a, "--workdir=", 10)) {
            g_free(workdir);
            workdir = g_strdup(a + 10);
        } else if (!strcmp(a, "--hold")) {
            hold = TRUE;
        } else if (a[0] != '-' && !workdir) {
            workdir = g_strdup(a);
        }
    }
    if (workdir && !g_path_is_absolute(workdir) && cwd) {
        char *abs = g_build_filename(cwd, workdir, NULL);
        g_free(workdir);
        workdir = abs;
    }
    if (!workdir && cwd)
        workdir = g_strdup(cwd);

    if (dropdown) {
        if (!dropdown_win)
            g_application_hold(app); /* stay alive while it is hidden */
        dropdown_toggle(GTK_APPLICATION(app));
    } else {
        Win *w = build_window(GTK_APPLICATION(app), FALSE);
        w->workdir = workdir;
        workdir = NULL;
        w->hold = hold;
        new_tab(w, w->workdir, command);
        gtk_window_present(w->window);
    }
    g_free(workdir);
    g_strfreev(command);
    return 0;
}

static void on_startup(GApplication *app, gpointer data)
{
    (void)app; (void)data;
    GdkDisplay *d = gdk_display_get_default();
    css = gtk_css_provider_new();
    gtk_style_context_add_provider_for_display(d, GTK_STYLE_PROVIDER(css),
                                               GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
    g_autoptr(GError) err = NULL;
    url_regex = vte_regex_new_for_match(URL_REGEX, -1, RX_MULTILINE, &err);
    if (!url_regex)
        g_warning("URL matching is off: %s", err->message);
    reload_config();
    watch_config();
}

int main(int argc, char **argv)
{
    gboolean dropdown = FALSE;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "-e") || !strcmp(argv[i], "-x") || !strcmp(argv[i], "--command"))
            break;
        if (!strcmp(argv[i], "-h") || !strcmp(argv[i], "--help")) {
            fputs(HELP, stdout);
            return 0;
        }
        if (!strcmp(argv[i], "-V") || !strcmp(argv[i], "--version")) {
            printf("forge-terminal %s\nVTE %u.%u.%u, sixel: %s\n", FORGE_VERSION, vte_get_major_version(),
                   vte_get_minor_version(), vte_get_micro_version(),
                   (vte_get_feature_flags() & VTE_FEATURE_FLAG_SIXEL) ? "yes" : "no");
            return 0;
        }
        if (!strcmp(argv[i], "--dropdown"))
            dropdown = TRUE;
    }

    /* The drop-down is its own application id, so a second call finds the
     * running one and toggles it, and ordinary windows are left alone. */
    GtkApplication *app = gtk_application_new(dropdown ? DROPDOWN_ID : APP_ID,
                                              G_APPLICATION_HANDLES_COMMAND_LINE);
    the_app = G_APPLICATION(app);
    g_signal_connect(app, "startup", G_CALLBACK(on_startup), NULL);
    g_signal_connect(app, "command-line", G_CALLBACK(on_command_line), GINT_TO_POINTER(dropdown));
    int status = g_application_run(the_app, argc, argv);
    g_object_unref(app);
    return status;
}
