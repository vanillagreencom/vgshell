import QtQuick
import Quickshell

// Jarvis's particle orb, drawn by shaders/particleorb.frag: one look per
// Session phase from the plugin's own table (Appearance.js `state`), in
// the look its bubble hands it. It draws only; the bubble owns its
// surface, screen and phase.
//
// A phase change eases every drawn value to the next look over the look's
// transition, with Qt animations that end on their own. The driver, which
// advances the noise field, the turn, the throb and the spark clock, runs
// while the orb is active and visible in a shown window and the motion
// scale is above 0, in every look: each moves at its own base rate, and
// the driving level, through the look's one input curve, adds to it
// (Appearance.js, the motion model). At motion scale 0 the driver stops
// and the orb draws its last frame in every look
// (docs/architecture/design-system.md § Motion).
Item {
    id: root

    // A key of the look's `state` group.
    property string phase: "armed"
    property real capture: 0
    property real playback: 0
    property bool active: false
    // The reduced look for an integrated GPU. Nothing selects it yet: the
    // rule waits for the px13 and MacBook readings (VGS-2210).
    property bool reduced: false
    required property var look
    readonly property var tone: look.state[phase]
    // The window the orb draws in, read as vgs.voice's Plasma reads it: a
    // plugin may not import QtQuick.Window (scripts/check-plugin-boundary.py).
    readonly property var host: QsWindow.window
    // The driving level through the input curve.
    readonly property real target: response(tone.drive === "capture" ? capture
        : tone.drive === "playback" ? playback : 0)
    // The eased level while the driver runs, the target while it stands.
    readonly property real driven: driver.running ? clock.level : target

    // The look's input curve, (1 - e^(-k x)) / (1 - e^(-k)): 0 at 0, 1 at 1,
    // continuous and rising.
    function response(level) {
        const x = Math.max(0, Math.min(1, level));
        const k = look.orb.response;
        return (1 - Math.exp(-k * x)) / (1 - Math.exp(-k));
    }

    implicitWidth: look.orb.size
    implicitHeight: look.orb.size
    Accessible.ignored: true

    onActiveChanged: if (!active) clock.reset()

    QtObject {
        id: clock
        property real time: 0
        property real flow: 0
        property real swirl: 0
        property real throb: 0
        property real level: 0

        // Zeroing the clocks while the orb is inactive keeps them small, as
        // Plasma.qml does: an unbounded flow loses precision in the
        // shader's noise coordinates.
        function reset() {
            time = 0;
            flow = 0;
            swirl = 0;
            throb = 0;
            level = 0;
        }

        function smooth(current, target, seconds) {
            const duration = target > current ? root.look.orb.attack : root.look.orb.release;
            return duration > 0 ? current + (target - current) * (1 - Math.exp(-seconds * 1000 / duration)) : target;
        }
    }

    // The look's values, eased over one transition when the phase changes.
    Item {
        id: eased
        visible: false
        readonly property int transition: root.look.orb.transition
        property color topStop: root.tone.top
        property color upperStop: root.tone.upper
        property color lowerStop: root.tone.lower
        property color bottomStop: root.tone.bottom
        property color coreTint: root.tone.core
        property color hotTint: root.tone.hot
        property real ringRadius: root.tone.radius
        property real amp: root.tone.amp
        property real scatter: root.tone.scatter
        property real sparks: root.tone.sparks
        property real interior: root.tone.interior
        property real rim: root.tone.rim
        property real saturation: root.tone.saturation
        property real presence: root.tone.presence
        property real brightness: root.tone.brightness
        property real fold: root.tone.fold
        property real throbDepth: root.tone.throbDepth
        property real driveAmp: root.tone.driveAmp
        property real driveScatter: root.tone.driveScatter
        property real driveBright: root.tone.driveBright
        property real driveRadius: root.tone.driveRadius
        Behavior on topStop { ColorAnimation { duration: eased.transition } }
        Behavior on upperStop { ColorAnimation { duration: eased.transition } }
        Behavior on lowerStop { ColorAnimation { duration: eased.transition } }
        Behavior on bottomStop { ColorAnimation { duration: eased.transition } }
        Behavior on coreTint { ColorAnimation { duration: eased.transition } }
        Behavior on hotTint { ColorAnimation { duration: eased.transition } }
        Behavior on ringRadius { NumberAnimation { duration: eased.transition } }
        Behavior on amp { NumberAnimation { duration: eased.transition } }
        Behavior on scatter { NumberAnimation { duration: eased.transition } }
        Behavior on sparks { NumberAnimation { duration: eased.transition } }
        Behavior on interior { NumberAnimation { duration: eased.transition } }
        Behavior on rim { NumberAnimation { duration: eased.transition } }
        Behavior on saturation { NumberAnimation { duration: eased.transition } }
        Behavior on presence { NumberAnimation { duration: eased.transition } }
        Behavior on brightness { NumberAnimation { duration: eased.transition } }
        Behavior on fold { NumberAnimation { duration: eased.transition } }
        Behavior on throbDepth { NumberAnimation { duration: eased.transition } }
        Behavior on driveAmp { NumberAnimation { duration: eased.transition } }
        Behavior on driveScatter { NumberAnimation { duration: eased.transition } }
        Behavior on driveBright { NumberAnimation { duration: eased.transition } }
        Behavior on driveRadius { NumberAnimation { duration: eased.transition } }
    }

    ShaderEffect {
        id: shader
        anchors.fill: parent
        blending: true
        property real uTime: clock.time
        property real uFlow: clock.flow
        property real uSwirl: clock.swirl
        property color uTop: eased.topStop
        property color uUpper: eased.upperStop
        property color uLower: eased.lowerStop
        property color uBottom: eased.bottomStop
        property color uCore: eased.coreTint
        property color uHot: eased.hotTint
        property vector4d uShape: Qt.vector4d(eased.ringRadius * (1 + eased.driveRadius * root.driven),
            root.reduced ? root.look.orb.reducedCells : root.look.orb.cells,
            root.look.orb.dot, eased.amp + eased.driveAmp * root.driven)
        property vector4d uField: Qt.vector4d(root.look.orb.frequency, root.look.orb.warp,
            eased.scatter + eased.driveScatter * root.driven, eased.sparks)
        property vector4d uTone: Qt.vector4d(eased.interior, eased.rim, eased.saturation, eased.presence)
        property vector4d uExtra: Qt.vector4d(eased.brightness + eased.driveBright * root.driven
            + eased.throbDepth * Math.sin(clock.throb), root.look.orb.tilt, eased.fold, 0)
        property real uReduce: root.reduced ? 1 : 0
        fragmentShader: Qt.resolvedUrl("shaders/particleorb.frag.qsb")
    }

    FrameAnimation {
        id: driver
        // Motion scale 0 stills every look: the clocks' rates divide by it.
        running: root.active && root.visible && root.look.motion.scale > 0
                 && root.host !== null && root.host.visible
        onTriggered: {
            // A frame after a stall moves the orb by at most 50 ms.
            const dt = Math.min(0.05, frameTime);
            const scale = root.look.motion.scale;
            clock.level = clock.smooth(clock.level, root.target, dt);
            // The turn and throb periods are durations, which the motion
            // scale already lengthens; the rates divide by it.
            clock.time += dt / scale;
            clock.flow += dt * (root.tone.flow * (1 + clock.level) + root.tone.levelFlow * clock.level) / scale;
            if (root.tone.quarterTurn > 0)
                clock.swirl = (clock.swirl + dt * 500 * Math.PI / root.tone.quarterTurn) % (2 * Math.PI);
            if (root.tone.throb > 0)
                clock.throb = (clock.throb + dt * 2000 * Math.PI / root.tone.throb) % (2 * Math.PI);
        }
    }
}
