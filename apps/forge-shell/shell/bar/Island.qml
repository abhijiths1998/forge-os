// The island in the middle of the bar: the clock and date; while music
// plays, the song beside it. Ready for more (a download, a timer, a call):
// each is a state of the same pill. A click opens the notification centre.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris
import qs.services
import qs.widgets

Rectangle {
    id: island
    readonly property var player: Mpris.players.values.find(p => p.isPlaying) || null

    implicitWidth: row.implicitWidth + 28
    radius: height / 2
    color: mouse.containsMouse || Shell.isOpen("notifications") ? Theme.hover : "transparent"
    Behavior on implicitWidth { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

    SystemClock { id: clock; precision: SystemClock.Minutes }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 10

        Label {
            text: Qt.formatDateTime(clock.date, "ddd d MMM")
            dim: true
        }
        Label {
            text: Qt.formatDateTime(clock.date, "HH:mm")
            font.weight: Font.Bold
            size: 14
            font.features: { "tnum": 1 }
        }
        Row {
            visible: island.player !== null
            spacing: 6
            Rectangle { width: 1; height: 14; color: Theme.faint; anchors.verticalCenter: parent.verticalCenter }
            Icon { text: Icons.play; size: 13; color: Theme.accent; anchors.verticalCenter: parent.verticalCenter }
            Label {
                width: Math.min(implicitWidth, 220)
                text: island.player ? [island.player.trackTitle, island.player.trackArtist].filter(s => s).join(" · ") : ""
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: Shell.toggle("notifications")
    }
}
