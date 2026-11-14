// What's playing (any MPRIS player): cover, title, artist, controls.
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris
import qs.services

Rectangle {
    id: card
    readonly property var player: Mpris.players.values.find(p => p.isPlaying) || Mpris.players.values[0] || null
    visible: player !== null
    implicitHeight: 72
    radius: Theme.radius - 2
    color: Theme.faint

    RowLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 12
        Rectangle {
            Layout.preferredWidth: 52
            Layout.preferredHeight: 52
            radius: 10
            color: Theme.hover
            clip: true
            Image {
                anchors.fill: parent
                source: card.player ? card.player.trackArtUrl : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            Label { Layout.fillWidth: true; text: card.player ? card.player.trackTitle || "Unknown" : ""; font.weight: Font.DemiBold }
            Label { Layout.fillWidth: true; text: card.player ? card.player.trackArtist || card.player.identity : ""; dim: true; size: 12 }
        }
        Repeater {
            model: [
                { icon: Icons.previous, run: () => card.player.previous(), on: () => card.player.canGoPrevious },
                { icon: card.player && card.player.isPlaying ? Icons.pause : Icons.play, run: () => card.player.togglePlaying(), on: () => card.player.canTogglePlaying },
                { icon: Icons.next, run: () => card.player.next(), on: () => card.player.canGoNext }
            ]
            HoverButton {
                required property var modelData
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                radius: 16
                enabled: card.player !== null && modelData.on()
                opacity: enabled ? 1 : 0.4
                onClicked: modelData.run()
                Icon { anchors.centerIn: parent; text: modelData.icon; size: 18 }
            }
        }
    }
}
