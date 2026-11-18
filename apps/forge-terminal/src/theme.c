#include "theme.h"

#include <json-glib/json-glib.h>
#include <string.h>

char *forge_config_path(const char *name)
{
    return g_build_filename(g_get_user_config_dir(), "forge", name, NULL);
}

static gboolean parse_hex(const char *s, GdkRGBA *out)
{
    /* Only "#rrggbb": gdk_rgba_parse would also take names and rgb(). */
    if (!s || s[0] != '#' || strlen(s) != 7)
        return FALSE;
    return gdk_rgba_parse(out, s);
}

static GdkRGBA hex(const char *s)
{
    GdkRGBA c;
    gdk_rgba_parse(&c, s);
    return c;
}

static JsonObject *parse_object(const char *json, GError **error)
{
    g_autoptr(JsonParser) parser = json_parser_new();
    if (!json_parser_load_from_data(parser, json, -1, error))
        return NULL;
    JsonNode *root = json_parser_get_root(parser);
    if (!root || !JSON_NODE_HOLDS_OBJECT(root)) {
        g_set_error_literal(error, JSON_PARSER_ERROR, JSON_PARSER_ERROR_INVALID_DATA,
                            "expected a JSON object");
        return NULL;
    }
    return json_object_ref(json_node_get_object(root));
}

static gboolean get_number(JsonObject *o, const char *key, double *out)
{
    JsonNode *n = json_object_get_member(o, key);
    if (!n || !JSON_NODE_HOLDS_VALUE(n))
        return FALSE;
    GType t = json_node_get_value_type(n);
    if (t != G_TYPE_INT64 && t != G_TYPE_DOUBLE)
        return FALSE;
    *out = json_node_get_double(n);
    return TRUE;
}

void forge_theme_defaults(ForgeTheme *theme)
{
    theme->dark = TRUE;
    gdk_rgba_parse(&theme->accent, FORGE_DEFAULT_ACCENT);
    theme->opacity = FORGE_DEFAULT_OPACITY;
}

gboolean forge_theme_parse(const char *json, ForgeTheme *theme, GError **error)
{
    forge_theme_defaults(theme);
    g_autoptr(JsonObject) o = parse_object(json, error);
    if (!o)
        return FALSE;

    JsonNode *dark = json_object_get_member(o, "dark");
    if (dark && JSON_NODE_HOLDS_VALUE(dark) && json_node_get_value_type(dark) == G_TYPE_BOOLEAN)
        theme->dark = json_node_get_boolean(dark);

    JsonNode *accent = json_object_get_member(o, "accent");
    if (accent && JSON_NODE_HOLDS_VALUE(accent) && json_node_get_value_type(accent) == G_TYPE_STRING) {
        GdkRGBA c;
        if (parse_hex(json_node_get_string(accent), &c))
            theme->accent = c;
    }

    double op;
    if (get_number(o, "terminalOpacity", &op))
        theme->opacity = (int)CLAMP(op + 0.5, 0, 100);
    return TRUE;
}

gboolean forge_theme_load(const char *path, ForgeTheme *theme)
{
    g_autofree char *data = NULL;
    if (!g_file_get_contents(path, &data, NULL, NULL) || !forge_theme_parse(data, theme, NULL)) {
        forge_theme_defaults(theme);
        return FALSE;
    }
    return TRUE;
}

static GdkRGBA mix(GdkRGBA a, GdkRGBA b, double t)
{
    GdkRGBA c = { a.red + (b.red - a.red) * t, a.green + (b.green - a.green) * t,
                  a.blue + (b.blue - a.blue) * t, 1.0 };
    return c;
}

void forge_palette_for(const ForgeTheme *theme, ForgePalette *p)
{
    /* The navy glass palette the Theming Kit used for Konsole, with the
     * background and foreground moved to Forge Glass's own. */
    static const char *dark[16] = {
        "#2e3254", "#f28b9b", "#8fd3a8", "#f6cfa8", "#8a9bf7", "#c3b7ee", "#9dbef0", "#d8dbee",
        "#5a5f86", "#f7a9b6", "#a9e2bf", "#f9ddbf", "#a3b0fa", "#d6cdf5", "#b9d2f5", "#ffffff",
    };
    /* Darker, more saturated colours that read on a pale background. */
    static const char *light[16] = {
        "#23263a", "#c0334f", "#2a7d4f", "#9a6a1c", "#3b4fd0", "#7a5bc0", "#2a73a8", "#b8bbd0",
        "#5a5f86", "#d94f6b", "#3a9a64", "#b88226", "#5568e8", "#9374d6", "#3d8fc4", "#8e92ad",
    };
    const char **src = theme->dark ? dark : light;
    for (int i = 0; i < 16; i++)
        p->ansi[i] = hex(src[i]);

    p->bg = hex(theme->dark ? "#1b1d2b" : "#f4f5fb");
    p->fg = hex(theme->dark ? "#e4e6f4" : "#23263a");
    p->cursor_fg = p->bg;
    p->cursor_fg.alpha = 1.0;
    p->cursor = theme->accent;
    /* Opaque, so the selection doesn't vary with the window's alpha. */
    p->selection = mix(p->bg, theme->accent, 0.38);
    p->bg.alpha = theme->opacity / 100.0;
}

void forge_settings_defaults(ForgeSettings *s)
{
    s->font_size = FORGE_DEFAULT_FONT_SIZE;
    s->scrollback = FORGE_DEFAULT_SCROLLBACK;
    s->font = NULL;
}

void forge_settings_clear(ForgeSettings *s)
{
    g_clear_pointer(&s->font, g_free);
}

gboolean forge_settings_parse(const char *json, ForgeSettings *s, GError **error)
{
    forge_settings_clear(s);
    forge_settings_defaults(s);
    g_autoptr(JsonObject) o = parse_object(json, error);
    if (!o)
        return FALSE;

    double v;
    if (get_number(o, "fontSize", &v))
        s->font_size = CLAMP(v, 6.0, 48.0);
    if (get_number(o, "scrollback", &v))
        s->scrollback = (int)CLAMP(v, 0, 1000000);

    JsonNode *font = json_object_get_member(o, "font");
    if (font && JSON_NODE_HOLDS_VALUE(font) && json_node_get_value_type(font) == G_TYPE_STRING) {
        const char *f = json_node_get_string(font);
        if (f && *f)
            s->font = g_strdup(f);
    }
    return TRUE;
}

gboolean forge_settings_load(const char *path, ForgeSettings *s)
{
    g_autofree char *data = NULL;
    if (!g_file_get_contents(path, &data, NULL, NULL) || !forge_settings_parse(data, s, NULL)) {
        forge_settings_clear(s);
        forge_settings_defaults(s);
        return FALSE;
    }
    return TRUE;
}

char *forge_settings_to_json(const ForgeSettings *s)
{
    g_autoptr(JsonBuilder) b = json_builder_new();
    json_builder_begin_object(b);
    json_builder_set_member_name(b, "fontSize");
    json_builder_add_double_value(b, s->font_size);
    json_builder_set_member_name(b, "scrollback");
    json_builder_add_int_value(b, s->scrollback);
    if (s->font) {
        json_builder_set_member_name(b, "font");
        json_builder_add_string_value(b, s->font);
    }
    json_builder_end_object(b);
    g_autoptr(JsonGenerator) g = json_generator_new();
    g_autoptr(JsonNode) root = json_builder_get_root(b);
    json_generator_set_root(g, root);
    json_generator_set_pretty(g, TRUE);
    return json_generator_to_data(g, NULL);
}
