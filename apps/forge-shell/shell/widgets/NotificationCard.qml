// One notification: app icon or image, title, text, its actions.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Notifications
import qs.services

Glass {
    id: card
    property var notification
    property bool popup: false
    strong: true
    implicitHeight: body.implicitHeight + 24
    border.color: notification && notification.urgency === NotificationUrgency.Critical ? Theme.danger : Theme.edge

    // Pop-ups go away on their own after a while (critical ones stay).
    Timer {
        running: card.popup && !hover.containsMouse && card.notification
                 && card.notification.urgency !== NotificationUrgency.Critical
        interval: card.notification && card.notification.expireTimeout > 0 ? card.notification.expireTimeout : 6000
        onTriggered: Notifs.hidePopup(card.notification)
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        onClicked: {
            const def = (card.notification.actions || []).find(a => a.identifier === "default");
            if (def) def.invoke();
            if (card.popup) Notifs.hidePopup(card.notification);
        }
    }

    RowLayout {
        id: body
        anchors.fill: parent
        anchors.margins: 12
        spacing: 12

        Item {
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: 40
            Layout.preferredHeight: 40
            Image {
                id: image
                anchors.fill: parent
                visible: status === Image.Ready
                source: card.notification ? card.notification.image : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }
            // The app's icon, if the icon theme has it; else a bell.
            readonly property string iconPath: card.notification
                ? Quickshell.iconPath(card.notification.appIcon || card.notification.desktopEntry || "", true) : ""
            IconImage {
                anchors.fill: parent
                visible: !image.visible && parent.iconPath !== ""
                source: parent.iconPath
            }
            Icon {
                anchors.centerIn: parent
                visible: !image.visible && parent.iconPath === ""
                text: Icons.bell
                size: 24
                color: Theme.accent
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 3
            RowLayout {
                Layout.fillWidth: true
                Label { Layout.fillWidth: true; text: card.notification ? card.notification.summary : ""; font.weight: Font.Bold }
                Label { text: card.notification ? card.notification.appName : ""; dim: true; size: 11 }
                HoverButton {
                    Layout.preferredWidth: 22
                    Layout.preferredHeight: 22
                    radius: 11
                    onClicked: card.notification.dismiss()
                    Icon { anchors.centerIn: parent; text: Icons.close; size: 13; color: Theme.subtext }
                }
            }
            Label {
                Layout.fillWidth: true
                visible: text !== ""
                text: card.notification ? card.notification.body : ""
                textFormat: Text.StyledText
                wrapMode: Text.Wrap
                maximumLineCount: card.popup ? 4 : 12
                dim: true
                size: 12
                onLinkActivated: link => Qt.openUrlExternally(link)
            }
            Flow {
                Layout.fillWidth: true
                visible: actions.count > 0
                spacing: 6
                Repeater {
                    id: actions
                    model: card.notification ? card.notification.actions.filter(a => a.identifier !== "default") : []
                    HoverButton {
                        required property var modelData
                        width: actionLabel.implicitWidth + 24
                        height: 28
                        radius: 14
                        onClicked: { modelData.invoke(); if (card.popup) Notifs.hidePopup(card.notification); }
                        Rectangle { anchors.fill: parent; radius: 14; color: Theme.faint; z: -1 }
                        Label { id: actionLabel; anchors.centerIn: parent; text: modelData.text; size: 12; font.weight: Font.DemiBold }
                    }
                }
            }
        }
    }
}
