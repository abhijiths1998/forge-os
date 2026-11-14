// Every shortcut, full screen (Super+/), with search: type "screenshot"
// and only those show, with their keys.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.services
import qs.widgets

ShellOverlay {
    id: sheet
    name: "cheatsheet"
    onOpened: { search.text = ""; search.forceActiveFocus(); }

    readonly property var results: Binds.search(search.text)

    Glass {
        anchors.centerIn: parent
        width: Math.min(parent.width - 80, 1180)
        height: Math.min(parent.height - 80, 760)
        strong: true
        MouseArea { anchors.fill: parent }   // clicks inside don't close

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 16

            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                Icon { text: Icons.keyboard; size: 24; color: Theme.accent }
                Label { text: "Keyboard shortcuts"; size: 22; font.weight: Font.Bold }
                Item { Layout.fillWidth: true }
                Label { text: "Esc to close"; dim: true; size: 12 }
            }
            TextField {
                id: search
                Layout.fillWidth: true
                placeholderText: "Search: screenshot, workspace, volume, Super E…"
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: 15
                leftPadding: 40
                background: Rectangle {
                    radius: 12
                    color: Theme.faint
                    border.width: 1
                    border.color: search.activeFocus ? Theme.accent : "transparent"
                    Icon { x: 12; anchors.verticalCenter: parent.verticalCenter; text: Icons.search; size: 17; color: Theme.subtext }
                }
                Keys.onEscapePressed: Shell.close("cheatsheet")
            }
            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                Flow {
                    id: flow
                    width: parent.width
                    spacing: 16
                    Repeater {
                        model: Binds.order.concat(Binds.categories.map(c => c.name).filter(n => Binds.order.indexOf(n) < 0))
                        ColumnLayout {
                            required property string modelData
                            readonly property var entries: sheet.results.filter(e => e.category === modelData)
                            visible: entries.length > 0
                            width: (flow.width - 32) / 3
                            spacing: 6
                            Label { text: modelData.toUpperCase(); size: 11; dim: true; font.weight: Font.Bold; font.letterSpacing: 1.2 }
                            Repeater {
                                model: parent.entries
                                RowLayout {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: 10
                                    Label { Layout.fillWidth: true; text: modelData.description; size: 13; wrapMode: Text.Wrap; elide: Text.ElideNone }
                                    KeyCombo { combos: modelData.keys; size: 11 }
                                }
                            }
                        }
                    }
                }
            }
            Label {
                visible: sheet.results.length === 0
                Layout.alignment: Qt.AlignHCenter
                text: "No shortcut matches “" + search.text + "”"
                dim: true
            }
        }
    }
}
