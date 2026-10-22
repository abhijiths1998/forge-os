/*
 * forge-os install slideshow, Forge Glass style: glass wallpaper, a small
 * monospace eyebrow and one big line per slide.
 */
import QtQuick 2.0;
import calamares.slideshow 1.0;

Presentation
{
    id: presentation

    function nextSlide() {
        presentation.goToNextSlide();
    }

    Timer {
        id: advanceTimer
        interval: 6000
        running: presentation.activatedInCalamares
        repeat: true
        onTriggered: nextSlide()
    }

    Image {
        anchors.fill: parent
        source: "forge-os-wallpaper.png"
        fillMode: Image.PreserveAspectCrop
        z: -1
    }

    component GlassSlide: Slide {
        id: slide
        property string eyebrow
        property string headline
        property string body

        Column {
            anchors.centerIn: parent
            width: presentation.width * 0.82
            spacing: 10

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: slide.eyebrow
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 11
                font.letterSpacing: 3
                color: "#6C7CF0"
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: slide.headline
                font.family: "Plus Jakarta Sans"
                font.weight: Font.DemiBold
                font.pixelSize: 26
                color: "#1E2140"
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: slide.body
                font.family: "Plus Jakarta Sans"
                font.pixelSize: 14
                color: "#55597A"
            }
        }
    }

    Slide {
        Image {
            id: logo
            source: "forge-os-logo.png"
            width: 128; height: 128
            fillMode: Image.PreserveAspectFit
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -50
        }
        Row {
            id: wordmark
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: logo.bottom
            anchors.topMargin: 12
            Text { text: "Forge "; font.family: "Plus Jakarta Sans"; font.weight: Font.DemiBold; font.pixelSize: 34; color: "#1E2140" }
            Text { text: "OS"; font.family: "Plus Jakarta Sans"; font.weight: Font.Light; font.pixelSize: 34; color: "#6E7391" }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: wordmark.bottom
            anchors.topMargin: 6
            text: qsTr("Built hot. Runs cool.")
            font.family: "Plus Jakarta Sans"
            font.pixelSize: 15
            color: "#6E7391"
        }
    }

    GlassSlide {
        eyebrow: "01 — DESKTOP"
        headline: qsTr("Soft glass. Sharp focus.")
        body: qsTr("Forge Glass: a slim top bar, a floating dock, and frosted panels, in light or dark.")
    }

    GlassSlide {
        eyebrow: "02 — COMMAND BAR"
        headline: qsTr("Super + Space, and go.")
        body: qsTr("Launch apps, find files, do quick maths. The command bar shows up when you call it.")
    }

    GlassSlide {
        eyebrow: "03 — GAMING"
        headline: qsTr("Steam is already here.")
        body: qsTr("NVIDIA drivers, Steam, Lutris, Heroic, GameMode, MangoHud and Gamescope, all installed and set up.")
    }

    GlassSlide {
        eyebrow: "04 — TERMINAL"
        headline: qsTr("One command.")
        body: qsTr("forge install, forge update, forge theme dark. Repos, Chaotic-AUR and Flatpak behind one word.")
    }

    GlassSlide {
        eyebrow: "05 — TILING"
        headline: qsTr("Windows that tidy themselves.")
        body: qsTr("Run forge tile on for auto-tiling, and spread out over three workspaces with Super + W.")
    }

    function onActivate() {
        presentation.currentSlide = 0;
    }

    function onLeave() {
    }

}
