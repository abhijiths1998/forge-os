// A battery drawn macOS-style: an outline with a cap, filled to the charge,
// optionally with the percentage written inside it (in a contrasting colour
// where the fill reaches), and a bolt beside it while charging. Used in the
// top bar, in the popup's header, and in its previews of each style.
import QtQuick
import QtQuick.Shapes

Item {
    id: icon

    property int percent: 0
    property bool charging: false
    property bool digits: true
    // The bar's text colour, and the fill's (green, red, or the same ink).
    property color ink: "white"
    property color fillColor: ink
    property real bodyHeight: 13

    readonly property real bodyWidth: Math.round(bodyHeight * 2.05)
    readonly property real pad: Math.max(1.5, bodyHeight * 0.13)
    // The digits over the fill: dark on a light fill (the ink of a dark bar,
    // pastel green or red), white on a dark one.
    readonly property color onFill: (0.299 * fillColor.r + 0.587 * fillColor.g + 0.114 * fillColor.b) > 0.55
        ? "#16182e" : "white"

    function faded(c, a) { return Qt.rgba(c.r, c.g, c.b, a); }

    implicitWidth: battery.width + (bolt.visible ? bolt.width + spacing : 0)
    implicitHeight: bodyHeight
    readonly property real spacing: Math.round(bodyHeight * 0.12)

    Item {
        id: battery
        width: icon.bodyWidth + cap.width + 1
        height: icon.bodyHeight
        anchors.verticalCenter: parent.verticalCenter

        // The outline, quieter than the fill, like macOS.
        Rectangle {
            id: body
            width: icon.bodyWidth
            height: parent.height
            radius: height * 0.3
            color: "transparent"
            border.width: Math.max(1, height * 0.09)
            border.color: icon.faded(icon.ink, 0.45)
        }
        Rectangle {
            id: cap
            x: body.width + 1
            anchors.verticalCenter: body.verticalCenter
            width: Math.max(1.5, body.height * 0.14)
            height: body.height * 0.38
            radius: width / 2
            color: icon.faded(icon.ink, 0.45)
        }

        // The charge.
        Rectangle {
            id: fill
            x: icon.pad
            y: icon.pad
            height: body.height - 2 * icon.pad
            width: Math.max(height * 0.5, (body.width - 2 * icon.pad) * icon.percent / 100)
            radius: body.radius - icon.pad * 0.6
            color: icon.fillColor
            Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
        }

        // The percentage, twice: in the ink over the empty part, and in a
        // contrasting colour clipped to the fill, so it reads on both.
        Text {
            id: label
            visible: icon.digits
            anchors.centerIn: body
            text: icon.percent
            color: icon.ink
            font.pixelSize: Math.round(body.height * 0.72)
            font.weight: Font.Bold
            font.letterSpacing: -0.3
            font.features: { "tnum": 1 }
        }
        Item {
            visible: icon.digits
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
                color: icon.onFill
            }
        }
    }

    // A bolt while charging.
    Shape {
        id: bolt
        visible: icon.charging
        x: battery.width + icon.spacing
        width: icon.bodyHeight * 0.6
        height: icon.bodyHeight
        anchors.verticalCenter: parent.verticalCenter
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: 0
            fillColor: icon.ink
            scale: Qt.size(icon.bodyHeight * 0.6 / 6, icon.bodyHeight / 10)
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
