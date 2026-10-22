/*
 * Forge Glass splash: shown by ksplashqml between login and the desktop.
 * Plain QtQuick only, so it can't break on a Plasma internals change.
 * ksplashqml raises `stage` from 1 to 6 as the session starts up.
 */
import QtQuick

Rectangle {
    id: root
    color: "#EEEEF8"

    property int stage

    Image {
        anchors.fill: parent
        source: "file:///usr/share/wallpapers/ForgeGlass/contents/images/3840x2160.png"
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: root.width
        sourceSize.height: root.height
        asynchronous: false
    }

    Column {
        id: content
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -root.height * 0.04
        spacing: root.height * 0.012
        opacity: 0
        scale: 0.96

        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            source: "images/logo.png"
            width: Math.round(root.height * 0.15)
            height: width
            sourceSize.width: width
            sourceSize.height: height
            smooth: true
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            Text {
                text: "Forge "
                font.family: "Plus Jakarta Sans"
                font.weight: Font.DemiBold
                font.pixelSize: root.height * 0.05
                color: "#1E2140"
            }
            Text {
                text: "OS"
                font.family: "Plus Jakarta Sans"
                font.weight: Font.Light
                font.pixelSize: root.height * 0.05
                color: "#6E7391"
            }
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: root.height * 0.22
            height: 4
            radius: 2
            color: "#281E2140"

            Rectangle {
                height: parent.height
                radius: 2
                width: parent.width * Math.min(1, Math.max(0.08, root.stage / 6))
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: "#F39670" }
                    GradientStop { position: 1; color: "#6C7CF0" }
                }
                Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
            }
        }
    }

    ParallelAnimation {
        running: true
        NumberAnimation { target: content; property: "opacity"; to: 1; duration: 500; easing.type: Easing.OutCubic }
        NumberAnimation { target: content; property: "scale"; to: 1; duration: 700; easing.type: Easing.OutCubic }
    }
}
