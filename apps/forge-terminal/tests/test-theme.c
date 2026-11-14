#include "../src/theme.h"

#include <math.h>

static gboolean same(GdkRGBA c, const char *spec)
{
    GdkRGBA e;
    gdk_rgba_parse(&e, spec);
    return fabs(c.red - e.red) < 0.002 && fabs(c.green - e.green) < 0.002
        && fabs(c.blue - e.blue) < 0.002;
}

static void test_theme_defaults(void)
{
    ForgeTheme t;
    g_assert_true(forge_theme_parse("{}", &t, NULL));
    g_assert_true(t.dark);
    g_assert_true(same(t.accent, "#7F8EF5"));
    g_assert_cmpint(t.opacity, ==, 64);
}

static void test_theme_values(void)
{
    ForgeTheme t;
    g_assert_true(forge_theme_parse(
        "{\"dark\": false, \"accent\": \"#12ab9c\", \"terminalOpacity\": 80, \"other\": 1}", &t, NULL));
    g_assert_false(t.dark);
    g_assert_true(same(t.accent, "#12ab9c"));
    g_assert_cmpint(t.opacity, ==, 80);
}

static void test_theme_bad_values(void)
{
    ForgeTheme t;
    /* Wrong types, a named colour and an out-of-range opacity. */
    g_assert_true(forge_theme_parse(
        "{\"dark\": \"yes\", \"accent\": \"red\", \"terminalOpacity\": 250.0}", &t, NULL));
    g_assert_true(t.dark);
    g_assert_true(same(t.accent, "#7F8EF5"));
    g_assert_cmpint(t.opacity, ==, 100);

    GError *err = NULL;
    g_assert_false(forge_theme_parse("{nope", &t, &err));
    g_assert_nonnull(err);
    g_clear_error(&err);
    g_assert_false(forge_theme_parse("[1]", &t, NULL));
    g_assert_true(t.dark); /* defaults after a failure */
}

static void test_theme_missing_file(void)
{
    ForgeTheme t;
    g_assert_false(forge_theme_load("/nonexistent/theme.json", &t));
    g_assert_cmpint(t.opacity, ==, 64);
}

static void test_palette(void)
{
    ForgeTheme t;
    ForgePalette p;
    forge_theme_defaults(&t);
    forge_palette_for(&t, &p);
    g_assert_true(same(p.bg, "#1b1d2b"));
    g_assert_cmpfloat_with_epsilon(p.bg.alpha, 0.64, 0.001);
    g_assert_true(same(p.cursor, "#7F8EF5"));
    g_assert_true(same(p.ansi[4], "#8a9bf7"));
    g_assert_true(same(p.ansi[15], "#ffffff"));
    g_assert_cmpfloat(p.cursor_fg.alpha, ==, 1.0);

    t.dark = FALSE;
    t.opacity = 100;
    forge_palette_for(&t, &p);
    g_assert_true(same(p.bg, "#f4f5fb"));
    g_assert_true(same(p.fg, "#23263a"));
    g_assert_cmpfloat(p.bg.alpha, ==, 1.0);
    /* Light text on the light background would be unreadable. */
    g_assert_cmpfloat(p.fg.red, <, p.bg.red);
}

static void test_settings(void)
{
    ForgeSettings s = { 0 };
    g_assert_true(forge_settings_parse("{}", &s, NULL));
    g_assert_cmpfloat(s.font_size, ==, 11.0);
    g_assert_cmpint(s.scrollback, ==, 10000);
    g_assert_null(s.font);

    g_assert_true(forge_settings_parse(
        "{\"fontSize\": 13.5, \"scrollback\": 500, \"font\": \"Iosevka\"}", &s, NULL));
    g_assert_cmpfloat(s.font_size, ==, 13.5);
    g_assert_cmpint(s.scrollback, ==, 500);
    g_assert_cmpstr(s.font, ==, "Iosevka");

    g_assert_true(forge_settings_parse("{\"fontSize\": 1, \"scrollback\": -4}", &s, NULL));
    g_assert_cmpfloat(s.font_size, ==, 6.0);
    g_assert_cmpint(s.scrollback, ==, 0);
    g_assert_null(s.font);

    /* Round trip. */
    ForgeSettings a = { 12.0, 2000, g_strdup("Mono") }, b = { 0 };
    char *json = forge_settings_to_json(&a);
    g_assert_true(forge_settings_parse(json, &b, NULL));
    g_assert_cmpfloat(b.font_size, ==, 12.0);
    g_assert_cmpint(b.scrollback, ==, 2000);
    g_assert_cmpstr(b.font, ==, "Mono");
    g_free(json);
    forge_settings_clear(&a);
    forge_settings_clear(&b);
    forge_settings_clear(&s);

    ForgeSettings m = { 0 };
    g_assert_false(forge_settings_load("/nonexistent/terminal.json", &m));
    g_assert_cmpint(m.scrollback, ==, 10000);
    forge_settings_clear(&m);
}

int main(int argc, char **argv)
{
    g_test_init(&argc, &argv, NULL);
    g_test_add_func("/theme/defaults", test_theme_defaults);
    g_test_add_func("/theme/values", test_theme_values);
    g_test_add_func("/theme/bad-values", test_theme_bad_values);
    g_test_add_func("/theme/missing-file", test_theme_missing_file);
    g_test_add_func("/theme/palette", test_palette);
    g_test_add_func("/settings/all", test_settings);
    return g_test_run();
}
