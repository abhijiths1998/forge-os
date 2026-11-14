// The focused window's title.
import QtQuick
import Quickshell.Hyprland
import qs.widgets

Label {
    text: Hyprland.activeToplevel && Hyprland.activeToplevel.workspace
          && Hyprland.activeToplevel.workspace.active ? Hyprland.activeToplevel.title : ""
    dim: true
    font.weight: Font.Medium
}
