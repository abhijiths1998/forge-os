// A popup's last line: a link to the matching System Settings page.
import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami

Text {
    id: link

    signal clicked()

    Layout.alignment: Qt.AlignRight
    Layout.bottomMargin: Kirigami.Units.smallSpacing
    Layout.rightMargin: Kirigami.Units.smallSpacing
    color: hover.hovered ? Kirigami.Theme.textColor : Kirigami.Theme.highlightColor
    font.pixelSize: 13
    font.weight: Font.DemiBold

    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: link.clicked() }
}
