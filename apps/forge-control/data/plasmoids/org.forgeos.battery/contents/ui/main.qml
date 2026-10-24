// Forge Battery: the top bar's battery, macOS-style. An outline with a cap,
// filled to the charge, the percentage written inside it (in a contrasting
// colour where the fill reaches), and a bolt while charging. Green while
// plugged in, red at 20% and below. A click opens Forge Control. Takes no
// space on machines without a battery.
//
// Data: Plasma's powermanagement engine (PowerDevil), sources "Battery"
// (Has Battery, Percent, State, Smoothed Remaining msec) and "AC Adapter"
// (Plugged in).
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes

import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as P5Support
import org.kde.plasma.plasmoid

PlasmoidItem {
    id: root

    readonly property var battery: pm.data["Battery"] || {}
    readonly property bool present: battery["Has Battery"] === true
    readonly property int percent: battery["Percent"] || 0
    readonly property string batteryState: battery["State"] || ""
    readonly property bool charging: batteryState === "Charging"
    readonly property bool pluggedIn: (pm.data["AC Adapter"] || {})["Plugged in"] === true
    readonly property bool low: percent <= 20 && !pluggedIn
    readonly property int minutesLeft: Math.round((battery["Smoothed Remaining msec"] || 0) / 60000)

    // A button, not a popup: Forge Control is its own window.
    preferredRepresentation: fullRepresentation
    toolTipMainText: i18n("Battery %1%", percent)
    toolTipSubText: {
        if (batteryState === "FullyCharged") return i18n("Fully charged");
        if (charging) return i18n("Charging");
        if (pluggedIn) return i18n("Plugged in, not charging");
        if (minutesLeft > 0)
            return i18n("%1 h %2 min left", Math.floor(minutesLeft / 60), minutesLeft % 60);
        return i18n("On battery");
    }

    P5Support.DataSource {
        id: pm
        engine: "powermanagement"
        connectedSources: ["Battery", "AC Adapter"]
    }

    P5Support.DataSource {
        id: runner
        engine: "executable"
        onNewData: source => disconnectSource(source)
    }

    fullRepresentation: MouseArea {
        id: button

        readonly property color ink: Kirigami.Theme.textColor
        readonly property color fillColor: root.low ? Kirigami.Theme.negativeTextColor
            : root.pluggedIn ? Kirigami.Theme.positiveTextColor : ink

        // The digits over the fill: dark on a light fill (the ink of a dark
        // bar, pastel green or red), white on a dark one.
        readonly property color onFill: (0.299 * fillColor.r + 0.587 * fillColor.g + 0.114 * fillColor.b) > 0.55
            ? "#16182e" : "white"

        function faded(c, a) { return Qt.rgba(c.r, c.g, c.b, a); }
        // Body: about 55% of the bar's height, twice as wide as tall.
        readonly property real bodyHeight: Math.round(Math.max(11, height * 0.56))
        readonly property real bodyWidth: Math.round(bodyHeight * 2.05)
        readonly property real pad: Math.max(1.5, bodyHeight * 0.13)

        visible: root.present
        Layout.minimumWidth: root.present ? row.implicitWidth + Kirigami.Units.smallSpacing * 2 : 0
        Layout.maximumWidth: Layout.minimumWidth
        Layout.fillHeight: true
        hoverEnabled: true
        onClicked: runner.connectSource("forge-control")

        Row {
            id: row
            anchors.centerIn: parent
            spacing: Math.round(button.bodyHeight * 0.12)

            Item {
                width: button.bodyWidth + cap.width + 1
                height: button.bodyHeight
                anchors.verticalCenter: parent.verticalCenter

                // The outline, quieter than the fill, like macOS.
                Rectangle {
                    id: body
                    width: button.bodyWidth
                    height: parent.height
                    radius: height * 0.3
                    color: "transparent"
                    border.width: Math.max(1, height * 0.09)
                    border.color: button.faded(button.ink, button.containsMouse ? 0.7 : 0.45)
                }
                Rectangle {
                    id: cap
                    x: body.width + 1
                    anchors.verticalCenter: body.verticalCenter
                    width: Math.max(1.5, body.height * 0.14)
                    height: body.height * 0.38
                    radius: width / 2
                    color: button.faded(button.ink, 0.45)
                }

                // The charge.
                Rectangle {
                    id: fill
                    x: button.pad
                    y: button.pad
                    height: body.height - 2 * button.pad
                    width: Math.max(height * 0.5, (body.width - 2 * button.pad) * root.percent / 100)
                    radius: body.radius - button.pad * 0.6
                    color: button.fillColor
                    Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                }

                // The percentage, twice: in the ink over the empty part, and in
                // a contrasting colour clipped to the fill, so it reads on both.
                Text {
                    id: label
                    anchors.centerIn: body
                    text: root.percent
                    color: button.ink
                    font.pixelSize: Math.round(body.height * 0.72)
                    font.weight: Font.Bold
                    font.letterSpacing: -0.3
                    font.features: { "tnum": 1 }
                }
                Item {
                    x: fill.x
                    y: fill.y
                    width: fill.width
                    height: fill.height
                    clip: true

                    Text {
                        x: label.x - parent.x
                        y: label.y - parent.y
                        text: label.text
                        font: label.font
                        color: button.onFill
                    }
                }
            }

            // A bolt while charging.
            Shape {
                visible: root.charging
                width: visible ? button.bodyHeight * 0.6 : 0
                height: button.bodyHeight
                anchors.verticalCenter: parent.verticalCenter
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    strokeWidth: 0
                    fillColor: button.ink
                    scale: Qt.size(button.bodyHeight * 0.6 / 6, button.bodyHeight / 10)
                    startX: 3.6; startY: 0
                    PathLine { x: 0.2; y: 5.8 }
                    PathLine { x: 2.8; y: 5.8 }
                    PathLine { x: 2.2; y: 10 }
                    PathLine { x: 5.8; y: 4.0 }
                    PathLine { x: 3.2; y: 4.0 }
                    PathLine { x: 3.6; y: 0 }
                }
            }
        }
    }
}
