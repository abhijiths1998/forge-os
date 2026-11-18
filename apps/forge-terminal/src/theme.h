/* Forge Terminal: the desktop theme (theme.json), the terminal's own
 * settings (terminal.json) and the colour palette made from them. No
 * widgets here, so the tests can run without a display. */
#pragma once

#include <gdk/gdk.h>
#include <glib.h>

typedef struct {
    gboolean dark;
    GdkRGBA accent;
    int opacity; /* percent, 0-100 */
} ForgeTheme;

typedef struct {
    GdkRGBA bg, fg, cursor, cursor_fg, selection;
    GdkRGBA ansi[16];
} ForgePalette;

typedef struct {
    double font_size;
    int scrollback;
    char *font; /* family override, or NULL for fontconfig's monospace */
} ForgeSettings;

#define FORGE_DEFAULT_ACCENT "#7F8EF5"
#define FORGE_DEFAULT_OPACITY 64
#define FORGE_DEFAULT_FONT_SIZE 11.0
#define FORGE_DEFAULT_SCROLLBACK 10000

void forge_theme_defaults(ForgeTheme *theme);
/* Missing or invalid keys keep their defaults; only broken JSON fails. */
gboolean forge_theme_parse(const char *json, ForgeTheme *theme, GError **error);
/* A missing or unreadable file gives the defaults and returns FALSE. */
gboolean forge_theme_load(const char *path, ForgeTheme *theme);
void forge_palette_for(const ForgeTheme *theme, ForgePalette *palette);

void forge_settings_defaults(ForgeSettings *s);
gboolean forge_settings_parse(const char *json, ForgeSettings *s, GError **error);
gboolean forge_settings_load(const char *path, ForgeSettings *s);
char *forge_settings_to_json(const ForgeSettings *s);
void forge_settings_clear(ForgeSettings *s);

char *forge_config_path(const char *name);
