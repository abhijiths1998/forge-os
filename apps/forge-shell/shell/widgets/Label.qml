import QtQuick
import qs.services

Text {
    property bool dim: false
    property real size: 13
    color: dim ? Theme.subtext : Theme.text
    font.family: Theme.font
    font.pixelSize: size
    elide: Text.ElideRight
    verticalAlignment: Text.AlignVCenter
}
