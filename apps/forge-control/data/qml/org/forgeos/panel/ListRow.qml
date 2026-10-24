// A row in a popup's list (a network, a device, an output): an icon, a
// title and a line under it, something on the right, and a highlight when
// it's the current one. Anything put inside it goes under the row (the
// password field when joining a network).
import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

Rectangle {
    id: row

    property alias iconSource: icon.source
    property string title
    property string subtitle
    /// Small text on the right (a battery level).
    property string trailing
    /// A small icon on the right (a lock).
    property alias trailingIcon: trailingIcon.source
    property bool current: false
    property bool busy: false
    default property alias extra: below.data

    signal clicked()

    readonly property color ink: Kirigami.Theme.textColor

    Layout.fillWidth: true
    implicitHeight: column.implicitHeight + 2 * 6
    radius: 10
    color: current ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g,
                             Kirigami.Theme.highlightColor.b, 0.16)
         : hover.hovered ? Qt.rgba(ink.r, ink.g, ink.b, 0.07) : "transparent"
    Behavior on color { ColorAnimation { duration: 110 } }

    ColumnLayout {
        id: column
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
        spacing: Kirigami.Units.smallSpacing

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.largeSpacing

            Rectangle {
                implicitWidth: 30
                implicitHeight: 30
                radius: width / 2
                color: row.current ? Kirigami.Theme.highlightColor : Qt.rgba(row.ink.r, row.ink.g, row.ink.b, 0.09)

                Kirigami.Icon {
                    id: icon
                    anchors.centerIn: parent
                    width: 16
                    height: 16
                    color: row.current ? "white" : row.ink
                    isMask: true
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Text {
                    Layout.fillWidth: true
                    text: row.title
                    elide: Text.ElideRight
                    color: row.ink
                    font.pixelSize: 13
                    font.weight: row.current ? Font.DemiBold : Font.Normal
                }
                Text {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: row.subtitle
                    elide: Text.ElideRight
                    color: Qt.rgba(row.ink.r, row.ink.g, row.ink.b, 0.6)
                    font.pixelSize: 11
                }
            }

            PlasmaComponents.BusyIndicator {
                visible: row.busy
                running: row.busy
                implicitWidth: 18
                implicitHeight: 18
            }
            Text {
                visible: row.trailing.length > 0
                text: row.trailing
                color: Qt.rgba(row.ink.r, row.ink.g, row.ink.b, 0.6)
                font.pixelSize: 11
                font.features: { "tnum": 1 }
            }
            Kirigami.Icon {
                id: trailingIcon
                visible: source !== ""
                implicitWidth: 13
                implicitHeight: 13
                color: Qt.rgba(row.ink.r, row.ink.g, row.ink.b, 0.55)
                isMask: true
            }
        }

        ColumnLayout {
            id: below
            Layout.fillWidth: true
            visible: visibleChildren.length > 0
        }
    }

    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: row.clicked() }
}
