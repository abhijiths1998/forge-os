// A search box over a list, centred: the clipboard and emoji pickers.
// Type to filter, arrows to move, Enter to pick, Escape to leave.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.services
import qs.widgets

ShellOverlay {
    id: picker
    property string title
    property string icon
    property string placeholder: "Search"
    property alias query: search.text
    property int count: 0
    property int selected: 0
    property int columns: 1
    default property alias body: area.data
    signal picked(int index)
    signal removed(int index)
    dim: false

    onOpened: { search.text = ""; selected = 0; search.forceActiveFocus(); }
    onQueryChanged: selected = 0

    Glass {
        anchors.centerIn: parent
        width: 560
        height: 520
        strong: true
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12
            RowLayout {
                spacing: 10
                Icon { text: picker.icon; size: 20; color: Theme.accent }
                Label { text: picker.title; size: 16; font.weight: Font.Bold }
            }
            TextField {
                id: search
                Layout.fillWidth: true
                placeholderText: picker.placeholder
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: 14
                background: Rectangle { radius: 10; color: Theme.faint }
                Keys.onEscapePressed: Shell.close(picker.name)
                Keys.onDownPressed: picker.selected = Math.min(picker.count - 1, picker.selected + picker.columns)
                Keys.onUpPressed: picker.selected = Math.max(0, picker.selected - picker.columns)
                Keys.onRightPressed: e => { if (picker.columns > 1) picker.selected = Math.min(picker.count - 1, picker.selected + 1); else e.accepted = false; }
                Keys.onLeftPressed: e => { if (picker.columns > 1) picker.selected = Math.max(0, picker.selected - 1); else e.accepted = false; }
                Keys.onDeletePressed: e => { if (picker.columns === 1 && text === "") picker.removed(picker.selected); else e.accepted = false; }
                onAccepted: if (picker.count > 0) picker.picked(picker.selected)
            }
            Item {
                id: area
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
            }
        }
    }
}
