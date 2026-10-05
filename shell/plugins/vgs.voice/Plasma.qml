import QtQuick
import Quickshell
import qs.Commons
import "Appearance.js" as Appearance

// The plasma orb of the owner's voxtype OSD (PlasmaSurface.qml), drawn by
// shaders/plasma.frag: a glass membrane round a ball of plasma filaments that
// swells and swirls with the voice, warm while recording and cool while
// transcribing. It draws only; the layer host owns its surface and screen.
// The driver eases the level and turns the swirl only while the orb is
// active, visible in a shown window and the motion scale is above 0, as
// VoiceOrb's does; a stopped driver holds the phases and draws the last
// level directly.
Item {
    id: root

    property bool active: false
    property bool transcribing: false
    readonly property var look: Theme.appearance(Appearance.TOKENS, Appearance.LIGHT)
    // The window the orb draws in, whose map the driver reads as VoiceOrb's does.
    readonly property var host: QsWindow.window
    // Cool at rest, so each recording fades in from cool to warm, as the
    // owner's design does.
    readonly property var tones: transcribing || !active ? look.plasma.cool : look.plasma.warm
    // The breathing level while the words are transcribed, which has no
    // audio, between the pulse's low and high levels; a motion scale of 0
    // makes the period 0 and holds the low level.
    readonly property real pulse: look.pulse.period <= 0 ? look.pulse.low : look.pulse.low
        + (look.pulse.high - look.pulse.low) * (0.5 + 0.5 * Math.sin(state.time * 2000 * Math.PI / look.pulse.period))

    implicitWidth: look.plasma.size
    implicitHeight: look.plasma.size
    Accessible.ignored: true

    // A bridge frame's level, which the driver eases towards and lets fall.
    function push(level) {
        state.target = Math.max(0, Math.min(1, level));
    }

    // The bridge lost voxtype's audio: the orb starts again from rest.
    function reset() {
        state.reset();
    }

    onActiveChanged: if (!active) state.reset()

    QtObject {
        id: state
        property real time: 0
        property real level: 0
        property real energy: 0
        property real target: 0
        property real swirl: 0
        property real amp: 0

        // Zeroing the phases while the orb is hidden keeps them small: a
        // large swirl winds the plasma into rings and a large time loses
        // precision in the shader's sines.
        function reset() {
            time = 0;
            level = 0;
            energy = 0;
            target = 0;
            swirl = 0;
            amp = 0;
        }

        function ease(seconds, constant) {
            return 1 - Math.exp(-seconds * 1000 / constant);
        }
    }

    ShaderEffect {
        id: shader
        anchors.fill: parent
        blending: true
        property real uTime: state.time
        property real uAmp: driver.running ? state.amp : root.transcribing ? root.look.pulse.low : state.target
        property real uEnergy: state.energy
        property real uSwirl: state.swirl
        property color uColA: root.tones.rim
        property color uColB: root.tones.edge
        property color uColC: root.tones.mid
        property color uColD: root.tones.hot
        Behavior on uColA { ColorAnimation { duration: root.look.plasma.fade } }
        Behavior on uColB { ColorAnimation { duration: root.look.plasma.fade } }
        Behavior on uColC { ColorAnimation { duration: root.look.plasma.fade } }
        Behavior on uColD { ColorAnimation { duration: root.look.plasma.fade } }
        fragmentShader: Qt.resolvedUrl("shaders/plasma.frag.qsb")
    }

    FrameAnimation {
        id: driver
        running: root.active && root.visible && root.look.motion.scale > 0
                 && root.host !== null && root.host.visible
        onTriggered: {
            // A frame after a stall moves the orb by at most 50 ms.
            const dt = Math.min(0.05, frameTime);
            state.time += dt;
            const target = state.target;
            state.level += (target - state.level) * state.ease(dt, target > state.level ? root.look.plasma.attack : root.look.plasma.release);
            state.energy += (target - state.energy) * state.ease(dt, root.look.plasma.energy);
            state.target *= 1 - state.ease(dt, root.look.plasma.decay);
            state.amp = root.transcribing ? Math.max(state.level, root.pulse) : state.level;
            // The swirl's turn rate in radians a second: slow at rest,
            // faster with the voice and a little faster while transcribing.
            state.swirl += dt * (0.04 + 1.1 * state.amp + (root.transcribing ? 0.25 : 0));
        }
    }
}
