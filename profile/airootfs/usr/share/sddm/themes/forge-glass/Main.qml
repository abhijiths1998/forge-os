/*
 * Forge Glass SDDM theme (Qt 6 greeter).
 *
 * Big thin clock over the wallpaper, and one frosted-glass card holding the
 * user, password and session fields. The session picker matters: it's how
 * people reach the Gamescope/Steam session.
 */
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Effects

Rectangle {
    id: root
    width: 1920
    height: 1080
    color: "#EEEEF8"

    readonly property color ink: "#1E2140"
    readonly property color soft: "#6E7391"
    readonly property color accent: "#6C7CF0"
    readonly property real u: Math.max(1, height / 1080)   // 1 unit = 1px at 1080p
    property date now: new Date()

    Timer {
        interval: 1000; running: true; repeat: true
        onTriggered: root.now = new Date()
    }

    Image {
        id: bg
        anchors.fill: parent
        source: config.background
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: root.width
        sourceSize.height: root.height
    }

    // --- Clock ---------------------------------------------------------
    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.height * 0.16
        spacing: 6 * u

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatTime(root.now, "hh:mm")
            font.family: config.font
            font.weight: Font.Thin
            font.pixelSize: 150 * u
            color: "white"
            style: Text.Raised
            styleColor: "#221E2140"
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDate(root.now, "dddd, MMMM d")
            font.family: config.font
            font.weight: Font.Medium
            font.pixelSize: 22 * u
            color: "white"
            style: Text.Raised
            styleColor: "#221E2140"
        }
    }

    // --- Glass card ----------------------------------------------------
    Item {
        id: card
        width: 380 * u
        height: fields.implicitHeight + 48 * u
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.height * 0.56

        ShaderEffectSource {
            id: behind
            sourceItem: bg
            sourceRect: Qt.rect(card.x, card.y, card.width, card.height)
            visible: false
        }
        Rectangle {
            id: cardMask
            anchors.fill: parent
            radius: 26 * u
            visible: false
            layer.enabled: true
        }
        MultiEffect {
            anchors.fill: parent
            source: behind
            blurEnabled: true
            autoPaddingEnabled: false
            blur: 1.0
            blurMax: 64
            blurMultiplier: 1.5
            saturation: 0.2
            maskEnabled: true
            maskSource: cardMask
        }
        Rectangle {
            anchors.fill: parent
            radius: 26 * u
            color: "#80FFFFFF"
            border.color: "#B3FFFFFF"
            border.width: 1
        }

        Column {
            id: fields
            anchors.centerIn: parent
            width: parent.width - 48 * u
            spacing: 12 * u

            Image {
                anchors.horizontalCenter: parent.horizontalCenter
                source: "logo.png"
                width: 64 * u
                height: width
                sourceSize.width: width
                sourceSize.height: height
            }

            GlassField {
                id: userField
                width: parent.width
                text: userModel.lastUser
                placeholderText: "Username"
                onAccepted: passwordField.forceActiveFocus()
            }

            Row {
                width: parent.width
                spacing: 8 * u

                GlassField {
                    id: passwordField
                    width: parent.width - goButton.width - parent.spacing
                    echoMode: TextInput.Password
                    placeholderText: "Password"
                    focus: true
                    onAccepted: root.doLogin()
                }

                Button {
                    id: goButton
                    width: 44 * u
                    height: passwordField.height
                    onClicked: root.doLogin()
                    contentItem: Text {
                        text: "→"
                        color: "white"
                        font.pixelSize: 20 * u
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        radius: 12 * u
                        color: goButton.down ? Qt.darker(root.accent, 1.15) : root.accent
                    }
                }
            }

            ComboBox {
                id: session
                width: parent.width
                height: 36 * u
                model: sessionModel
                textRole: "name"
                currentIndex: sessionModel.lastIndex
                font.family: config.font
                font.pixelSize: 13 * u
                contentItem: Text {
                    leftPadding: 14 * u
                    text: session.displayText
                    font: session.font
                    color: root.soft
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }
                background: Rectangle {
                    radius: 12 * u
                    color: "#40FFFFFF"
                    border.color: "#80FFFFFF"
                }
            }

            Text {
                id: message
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                font.family: config.font
                font.pixelSize: 13 * u
                color: "#D9576E"
                text: ""
                visible: text.length > 0
            }
        }
    }

    // --- Power ---------------------------------------------------------
    Row {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 28 * u
        spacing: 18 * u

        Repeater {
            model: [
                { label: "Sleep", enabled: sddm.canSuspend, act: function() { sddm.suspend() } },
                { label: "Restart", enabled: sddm.canReboot, act: function() { sddm.reboot() } },
                { label: "Shut down", enabled: sddm.canPowerOff, act: function() { sddm.powerOff() } }
            ]
            delegate: Text {
                visible: modelData.enabled
                text: modelData.label
                font.family: config.font
                font.pixelSize: 14 * u
                color: mouse.containsMouse ? "white" : "#E6FFFFFF"
                style: Text.Raised
                styleColor: "#331E2140"
                MouseArea {
                    id: mouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: modelData.act()
                }
            }
        }
    }

    function doLogin() {
        message.text = ""
        sddm.login(userField.text, passwordField.text, session.currentIndex)
    }

    Connections {
        target: sddm
        function onLoginFailed() {
            message.text = "That didn't work. Try again?"
            passwordField.text = ""
            passwordField.forceActiveFocus()
        }
    }

    Component.onCompleted: {
        if (userField.text.length === 0)
            userField.forceActiveFocus()
        else
            passwordField.forceActiveFocus()
    }
}
