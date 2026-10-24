// Forge Sound: the top bar's speaker (its level, or muted) and its popup
// (VolumePopup.qml): the volume, mute, and which output plays. Scrolling on
// the icon changes the volume and a middle click mutes, as Plasma's did.
// The state and the switches are forged's.
import QtQuick

import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as P5Support
import org.kde.plasma.plasmoid
import org.forgeos.panel

PlasmoidItem {
    id: root

    readonly property var volume: forged.part("volume")
    readonly property int level: volume.level || 0

    preferredRepresentation: fullRepresentation
    toolTipMainText: i18n("Sound %1%", level)
    toolTipSubText: volume.muted ? i18n("Muted") : (volume.device || "")

    Forged { id: forged }

    P5Support.DataSource {
        id: runner
        engine: "executable"
        onNewData: source => disconnectSource(source)
    }

    fullRepresentation: BarButton {
        id: button

        property real wheelDelta: 0

        visible: root.volume.available !== false
        iconSource: root.volume.muted || root.level === 0 ? "audio-volume-muted-symbolic"
                  : "audio-volume-" + (root.level >= 66 ? "high" : root.level >= 33 ? "medium" : "low") + "-symbolic"
        location: Plasmoid.location
        vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
        onClicked: mouse => {
            if (mouse.button === Qt.MiddleButton)
                forged.set("volume", root.volume.muted ? "unmute" : "mute");
        }
        // Five points per notch of the wheel; touchpads send smaller steps.
        onWheel: wheel => {
            wheelDelta += wheel.angleDelta.y;
            const steps = Math.trunc(wheelDelta / 120);
            if (steps === 0) return;
            wheelDelta -= steps * 120;
            forged.set("volume", Math.max(0, Math.min(100, root.level + steps * 5)));
        }

        popup: VolumePopup {
            forged: forged
            onSettingsRequested: {
                button.close();
                runner.connectSource("systemsettings kcm_pulseaudio");
            }
        }
    }
}
