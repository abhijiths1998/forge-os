"""forge-theme-sync's writers: GTK and Qt colours from theme.json, without
touching the user's own settings, and nothing rewritten when nothing changed."""
import importlib.machinery
import importlib.util
import json
from pathlib import Path

import pytest

SYNC = Path(__file__).resolve().parent.parent / "profile/airootfs/usr/local/bin/forge-theme-sync"


@pytest.fixture
def sync(tmp_path, monkeypatch):
    monkeypatch.setenv("XDG_CONFIG_HOME", str(tmp_path))
    monkeypatch.setenv("PATH", "/nonexistent")  # no gsettings, hyprctl or flatpak
    loader = importlib.machinery.SourceFileLoader("forge_theme_sync", str(SYNC))
    spec = importlib.util.spec_from_loader("forge_theme_sync", loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


def set_theme(sync, **values):
    sync.THEME.parent.mkdir(parents=True, exist_ok=True)
    sync.THEME.write_text(json.dumps(values))


def test_theme_defaults_and_bad_values(sync):
    assert sync.theme() == {"dark": True, "accent": "#7F8EF5"}
    set_theme(sync, dark=False, accent="ff8800")
    assert sync.theme() == {"dark": False, "accent": "#FF8800"}
    set_theme(sync, dark="yes", accent="#123")
    assert sync.theme() == {"dark": True, "accent": "#7F8EF5"}


def test_gtk_writes_colours_and_keeps_user_css(sync, tmp_path):
    user_css = tmp_path / "gtk-4.0/gtk.css"
    user_css.parent.mkdir(parents=True)
    user_css.write_text("label { color: red; }\n")
    set_theme(sync, dark=False, accent="#FF8800")
    sync.gtk(sync.theme())
    forge_css = (tmp_path / "gtk-4.0/forge.css").read_text()
    assert "@define-color accent_bg_color #FF8800;" in forge_css
    assert "@define-color window_bg_color #F4F5FB;" in forge_css
    text = user_css.read_text()
    assert text.startswith(sync.IMPORT) and "label { color: red; }" in text
    settings = (tmp_path / "gtk-3.0/settings.ini").read_text()
    assert "gtk-theme-name=adw-gtk3" in settings and "gtk-application-prefer-dark-theme=false" in settings
    # Running again changes nothing and doesn't import twice.
    assert sync.gtk(sync.theme()) == "already in step"
    assert user_css.read_text().count(sync.IMPORT) == 1


def test_qt_palette_has_every_role(sync, tmp_path):
    sync.qt(sync.theme())
    scheme = (tmp_path / "qt6ct/colors/ForgeGlass.conf").read_text()
    active = scheme.split("active_colors=")[1].splitlines()[0].split(", ")
    assert len(active) == len(sync.QT_ROLES) == 22
    assert active[sync.QT_ROLES.index("Highlight")] == "#ff7f8ef5"
    conf = (tmp_path / "qt6ct/qt6ct.conf").read_text()
    assert "custom_palette=true" in conf and "ForgeGlass.conf" in conf
    assert sync.qt(sync.theme()).endswith("already in step")


def test_text_on_accent_is_readable(sync):
    assert sync.text_on("#FFEE88") == "#16182E"
    assert sync.text_on("#3344AA") == "#FFFFFF"
