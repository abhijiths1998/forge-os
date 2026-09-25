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

    Slide {
        Image {
            id: logo
            source: "forge-os-logo.png"
            width: 160; height: 160
            fillMode: Image.PreserveAspectFit
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 20
        }
        Text {
            id: title
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: logo.bottom
            anchors.topMargin: 20
            text: "Welcome to forge-os"
            font.pixelSize: 22
            font.bold: true
            color: "#FFFFFF"
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: title.bottom
            anchors.topMargin: 10
            width: presentation.width * 0.8
            text: "An Arch-based distro built for NVIDIA + gaming + KDE Plasma,\ncherry-picking the best ideas from CachyOS, Nobara, Garuda, and more."
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.Center
            color: "#CCCCCC"
        }
    }

    Slide {
        centeredText: qsTr("NVIDIA drivers are already installed and configured —\nnvidia-open-dkms, with mkinitcpio and kernel cmdline set up for you.")
    }

    Slide {
        centeredText: qsTr("A full gaming stack out of the box: Steam, Lutris, Heroic,\nGameMode, MangoHud, vkBasalt, ProtonUp-Qt, and Gamescope.")
    }

    Slide {
        centeredText: qsTr("Pamac gives you one app store for official repos, Chaotic-AUR,\nand Flatpak — no more juggling three different tools.")
    }

    Slide {
        centeredText: qsTr("A macOS-style KDE Plasma desktop: WhiteSur theme, a top menu\nbar, a dock, and frosted-glass panels — all set up by default.")
    }

    function onActivate() {
        presentation.currentSlide = 0;
    }

    function onLeave() {
    }

}
