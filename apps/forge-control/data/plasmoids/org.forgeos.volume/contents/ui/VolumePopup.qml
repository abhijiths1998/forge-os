// Forge Sound's popup: the output in use, a large volume slider with mute,
// and the outputs to play through (speakers, headphones, HDMI, Bluetooth).
import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.forgeos.panel

ColumnLayout {
    id: popup

    required property Forged forged
    signal settingsRequested()

    readonly property var volume: forged.part("volume")
    readonly property var outputs: volume.outputs || []
    readonly property color ink: Kirigami.Theme.textColor

    function kindIcon(kind) {
        return { "speaker": "audio-speakers-symbolic", "headphones": "audio-headphones-symbolic",
                 "hdmi": "video-display-symbolic", "bluetooth": "audio-headset-symbolic",
                 "usb": "audio-headphones-symbolic" }[kind] || "audio-speakers-symbolic";
    }

    width: Kirigami.Units.gridUnit * 18
    spacing: Kirigami.Units.smallSpacing

    PopupHeader {
        iconSource: "audio-volume-high-symbolic"
        title: i18n("Sound")
        subtitle: popup.volume.muted ? i18n("Muted") : (popup.volume.device || "")
        on: !popup.volume.muted
    }

    // --- Volume ------------------------------------------------------------
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.smallSpacing
        Layout.leftMargin: Kirigami.Units.smallSpacing
        Layout.rightMargin: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        Kirigami.Icon {
            implicitWidth: 18
            implicitHeight: 18
            source: popup.volume.muted ? "audio-volume-muted-symbolic" : "audio-volume-high-symbolic"
            color: popup.ink
            isMask: true
            opacity: muteHover.hovered ? 1 : 0.75
            HoverHandler { id: muteHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: popup.forged.set("volume", popup.volume.muted ? "unmute" : "mute") }
        }

        PlasmaComponents.Slider {
            id: slider
            Layout.fillWidth: true
            from: 0
            to: 100
            stepSize: 1
            // forged's value, except while dragging, when the hand leads.
            Binding on value {
                when: !slider.pressed
                value: popup.volume.level || 0
                restoreMode: Binding.RestoreNone
            }
            onMoved: send.restart()
            onPressedChanged: if (!pressed) popup.forged.set("volume", Math.round(value))

            // At most one change every 60 ms while dragging.
            Timer {
                id: send
                interval: 60
                onTriggered: popup.forged.set("volume", Math.round(slider.value))
            }
        }

        Text {
            Layout.minimumWidth: 34
            horizontalAlignment: Text.AlignRight
            text: Math.round(slider.value) + "%"
            color: Qt.rgba(popup.ink.r, popup.ink.g, popup.ink.b, 0.7)
            font.pixelSize: 12
            font.features: { "tnum": 1 }
        }
    }

    // --- Outputs -----------------------------------------------------------
    SectionLabel {
        visible: popup.outputs.length > 1
        text: i18n("Output")
    }

    Repeater {
        model: popup.outputs.length > 1 ? popup.outputs : []

        delegate: ListRow {
            required property var modelData

            iconSource: popup.kindIcon(modelData.kind)
            title: modelData.label
            subtitle: modelData.default ? i18n("Playing here") : ""
            trailingIcon: modelData.default ? "emblem-ok-symbolic" : ""
            current: modelData.default
            onClicked: if (!modelData.default) popup.forged.set("output", modelData.name)
        }
    }

    FooterLink {
        text: i18n("Sound settings…")
        onClicked: popup.settingsRequested()
    }
}
