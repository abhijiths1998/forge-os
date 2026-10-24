// Forge Battery's popup: the battery large, its charge and state, health
// and model, and where the top bar shows the percentage (inside the battery,
// beside it, or hidden), each choice previewed with the real charge.
import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami

ColumnLayout {
    id: popup

    property int percent: 0
    property bool charging: false
    property string status: ""
    property string details: ""
    property string mode: "inside"
    property color fillColor: Kirigami.Theme.textColor

    signal modeChosen(string mode)
    signal settingsRequested()

    readonly property color ink: Kirigami.Theme.textColor
    readonly property color dim: Qt.rgba(ink.r, ink.g, ink.b, 0.6)
    readonly property color accent: Kirigami.Theme.highlightColor

    width: Kirigami.Units.gridUnit * 17
    spacing: Kirigami.Units.largeSpacing

    // --- The battery, large -------------------------------------------------
    RowLayout {
        Layout.topMargin: Kirigami.Units.smallSpacing
        Layout.leftMargin: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.largeSpacing * 1.5

        BatteryIcon {
            percent: popup.percent
            charging: popup.charging
            digits: false
            ink: popup.ink
            fillColor: popup.fillColor
            bodyHeight: 30
        }

        ColumnLayout {
            spacing: 0
            Text {
                text: popup.percent + "%"
                color: popup.ink
                font.pixelSize: 30
                font.weight: Font.Light
                font.features: { "tnum": 1 }
            }
            Text {
                text: popup.status
                color: popup.dim
                font.pixelSize: 13
            }
        }
    }

    Text {
        visible: text.length > 0
        Layout.leftMargin: Kirigami.Units.smallSpacing
        text: popup.details
        color: popup.dim
        font.pixelSize: 12
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 1
        color: Qt.rgba(popup.ink.r, popup.ink.g, popup.ink.b, 0.12)
    }

    // --- Where the percentage goes -----------------------------------------
    Text {
        Layout.leftMargin: Kirigami.Units.smallSpacing
        text: i18n("Percentage in the top bar").toUpperCase()
        color: popup.dim
        font.pixelSize: 11
        font.weight: Font.DemiBold
        font.letterSpacing: 0.8
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing * 1.5

        Repeater {
            model: [
                { mode: "inside", label: i18n("Inside") },
                { mode: "beside", label: i18n("Beside") },
                { mode: "hidden", label: i18n("Hidden") },
            ]

            delegate: Rectangle {
                id: card
                required property var modelData
                readonly property bool chosen: popup.mode === modelData.mode

                Layout.fillWidth: true
                implicitHeight: Kirigami.Units.gridUnit * 3.6
                radius: 10
                color: chosen ? Qt.rgba(popup.accent.r, popup.accent.g, popup.accent.b, 0.18)
                     : hover.hovered ? Qt.rgba(popup.ink.r, popup.ink.g, popup.ink.b, 0.10)
                     : Qt.rgba(popup.ink.r, popup.ink.g, popup.ink.b, 0.05)
                border.width: chosen ? 1.5 : 0
                border.color: popup.accent
                Behavior on color { ColorAnimation { duration: 120 } }

                Column {
                    anchors.centerIn: parent
                    spacing: Kirigami.Units.smallSpacing

                    // The top bar's look in this style, with the real charge.
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 4
                        height: 14
                        Text {
                            visible: card.modelData.mode === "beside"
                            anchors.verticalCenter: parent.verticalCenter
                            text: popup.percent + "%"
                            color: popup.ink
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            font.features: { "tnum": 1 }
                        }
                        BatteryIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            percent: popup.percent
                            digits: card.modelData.mode === "inside"
                            ink: popup.ink
                            fillColor: popup.fillColor
                            bodyHeight: 13
                        }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: card.modelData.label
                        color: card.chosen ? popup.ink : popup.dim
                        font.pixelSize: 12
                        font.weight: card.chosen ? Font.DemiBold : Font.Normal
                    }
                }

                HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: popup.modeChosen(card.modelData.mode) }
            }
        }
    }

    // --- Footer ------------------------------------------------------------
    Text {
        Layout.alignment: Qt.AlignRight
        Layout.bottomMargin: Kirigami.Units.smallSpacing
        Layout.rightMargin: Kirigami.Units.smallSpacing
        text: i18n("Power settings…")
        color: link.hovered ? popup.ink : popup.accent
        font.pixelSize: 13
        font.weight: Font.DemiBold

        HoverHandler { id: link; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: popup.settingsRequested() }
    }
}
