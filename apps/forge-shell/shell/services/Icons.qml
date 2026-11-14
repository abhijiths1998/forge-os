pragma Singleton
// Icon glyphs (Material Design, from the JetBrains Mono Nerd Font Forge
// ships). Widgets/Icon.qml draws them.
import QtQuick
import Quickshell

Singleton {
    function g(code) { return String.fromCodePoint(code); }

    readonly property string forge: g(0xF0238)        // fire
    readonly property string wifiOff: g(0xF092E)
    readonly property var wifi: [g(0xF092F), g(0xF091F), g(0xF0922), g(0xF0925), g(0xF0928)]
    readonly property string wired: g(0xF0200)        // ethernet
    readonly property string lock: g(0xF033E)
    readonly property string bluetooth: g(0xF00AF)
    readonly property string bluetoothOff: g(0xF00B2)
    readonly property string bluetoothOn: g(0xF00B1)
    readonly property string volumeMute: g(0xF075F)
    readonly property var volume: [g(0xF057F), g(0xF0580), g(0xF057E)]
    readonly property string mic: g(0xF036C)
    readonly property string bell: g(0xF009A)
    readonly property string bellOff: g(0xF009B)
    readonly property string moon: g(0xF0594)
    readonly property string sun: g(0xF0599)
    readonly property string brightness: g(0xF00E0)
    readonly property string control: g(0xF0493)      // cog
    readonly property string tiles: g(0xF0570)        // view-grid
    readonly property string power: g(0xF0425)
    readonly property string logout: g(0xF0343)
    readonly property string restart: g(0xF0709)
    readonly property string search: g(0xF0349)
    readonly property string keyboard: g(0xF030C)
    readonly property string close: g(0xF0156)
    readonly property string thermometer: g(0xF050F)
    readonly property string leaf: g(0xF032A)
    readonly property string speed: g(0xF04C5)
    readonly property string play: g(0xF040A)
    readonly property string pause: g(0xF03E4)
    readonly property string next: g(0xF04AD)
    readonly property string previous: g(0xF04AE)
    readonly property string clipboard: g(0xF014C)
    readonly property string emoji: g(0xF0785)
    readonly property string check: g(0xF012C)
    readonly property string chevronDown: g(0xF0140)
    readonly property string chevronUp: g(0xF0143)
    readonly property string chevronRight: g(0xF0142)
    readonly property string drag: g(0xF01DD)
    readonly property string eyeOff: g(0xF0209)
    readonly property string capsLock: g(0xF0632)
    readonly property string nightLight: g(0xF0594)
    readonly property string speaker: g(0xF04C3)
    readonly property string headphones: g(0xF02CB)
    readonly property string hdmi: g(0xF0379)       // monitor
    readonly property string usb: g(0xF0553)
    readonly property string image: g(0xF021F)
    readonly property string trash: g(0xF0A7A)
    readonly property string bolt: g(0xF140B)
    readonly property string battery: g(0xF0079)
    readonly property string settings: g(0xF08BB)   // cog-outline
    readonly property string plus: g(0xF0415)
    readonly property string record: g(0xF044A)
}
