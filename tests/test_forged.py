"""forged's state logic, without D-Bus, NetworkManager or Hyprland:
JSON state files, toggles, relative values, tiling per workspace, quiet."""
import importlib.machinery
import importlib.util
import json
from pathlib import Path

import pytest

FORGED = Path(__file__).resolve().parent.parent / "profile/airootfs/usr/local/bin/forged"


@pytest.fixture
def forged(tmp_path, monkeypatch):
    monkeypatch.setenv("XDG_CONFIG_HOME", str(tmp_path / "config"))
    monkeypatch.setenv("XDG_STATE_HOME", str(tmp_path / "state"))
    loader = importlib.machinery.SourceFileLoader("forged", str(FORGED))
    spec = importlib.util.spec_from_loader("forged", loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    module.BACKLIGHT = tmp_path / "backlight"
    return module


@pytest.fixture
def desk(forged, monkeypatch):
    d = forged.Desktop(session=None, system=None)
    started = []
    monkeypatch.setattr(forged, "start", lambda *cmd, done=None: started.append(cmd) or (done and done()) or True)
    d.started = started
    return d


def test_json_roundtrip_and_broken_files(forged, tmp_path):
    path = tmp_path / "x" / "state.json"
    forged.write_json(path, {"a": 1})
    assert forged.read_json(path) == {"a": 1}
    path.write_text("{not json")
    assert forged.read_json(path) == {}
    assert forged.read_json(tmp_path / "missing.json") == {}
    path.write_text("[1, 2]")
    assert forged.read_json(path) == {}


def test_dnd_toggles_and_persists(forged, desk):
    assert desk.dnd() == {"available": True, "enabled": False}
    assert desk.set("dnd", "toggle", lambda: None) == ""
    assert desk.dnd()["enabled"] is True
    assert json.loads(forged.DND.read_text()) == {"enabled": True}
    # A new forged (after a restart) remembers it.
    assert forged.Desktop(None, None).dnd()["enabled"] is True
    assert desk.set("dnd", "off", lambda: None) == ""
    assert desk.dnd()["enabled"] is False


def test_switches_reject_nonsense(desk):
    assert "on, off or toggle" in desk.set("wifi", "maybe", lambda: None)
    assert desk.set("nothing", "on", lambda: None).startswith("no nothing")


def test_dark_from_theme_json(forged, desk):
    assert desk.dark()["enabled"] is True  # Forge Glass is dark when there's no theme yet
    forged.write_json(forged.CONFIG / "forge/theme.json", {"dark": False})
    assert desk.dark()["enabled"] is False


def test_tiling_per_workspace(forged, desk, monkeypatch):
    monkeypatch.setattr(desk, "_workspace", lambda: 3)
    assert desk.tiling() == {"available": True, "enabled": False, "workspace": 3, "default": False}
    assert desk.set("tiling", "toggle", lambda: None) == ""
    assert forged.read_json(forged.TILING) == {"default": False, "workspaces": {"3": True}}
    assert desk.tiling()["enabled"] is True
    assert desk.started[-1] == ("hyprctl", "eval", "forge.tiling.reload()")
    monkeypatch.setattr(desk, "_workspace", lambda: 4)
    assert desk.tiling()["enabled"] is False  # other workspaces keep the default


def test_tiling_outside_hyprland(desk, monkeypatch):
    monkeypatch.setattr(desk, "_workspace", lambda: None)
    assert desk.tiling() == {"available": False}
    assert "Hyprland" in desk.set("tiling", "on", lambda: None)


def _backlight(forged, level, top):
    dev = forged.BACKLIGHT / "intel_backlight"
    dev.mkdir(parents=True, exist_ok=True)
    (dev / "brightness").write_text(str(level))
    (dev / "max_brightness").write_text(str(top))
    (dev / "type").write_text("raw")
    return dev


def test_brightness_reads_sysfs(forged, desk):
    assert desk.brightness() == {"available": False}
    _backlight(forged, 480, 960)
    assert desk.brightness() == {"available": True, "level": 50, "display": "intel_backlight"}


def test_brightness_relative_is_clamped(forged, desk, monkeypatch):
    _backlight(forged, 960, 960)
    calls = []

    class Session:
        def SetBrightness(self, subsystem, name, value, dbus_interface):  # noqa: N802 (D-Bus name)
            calls.append((subsystem, name, int(value)))

    class System:
        def get_object(self, *_):
            return Session()

    desk.system = System()
    import sys
    import types
    fake = types.SimpleNamespace(UInt32=int, DBusException=Exception, Boolean=bool)
    monkeypatch.setitem(sys.modules, "dbus", fake)
    assert desk.set("brightness", "+10", lambda: None) == ""
    assert calls[-1] == ("backlight", "intel_backlight", 960)
    assert desk.set("brightness", "-150", lambda: None) == ""
    assert calls[-1] == ("backlight", "intel_backlight", 10)  # never fully off
    assert "0-100" in desk.set("brightness", "bright", lambda: None)
