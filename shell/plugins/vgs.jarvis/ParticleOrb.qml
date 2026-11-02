import QtQuick
import Quickshell

// Jarvis's particle orb, drawn by shaders/particleorb.frag: one look per
// Session phase from the plugin's own table (Appearance.js `state`), in
// the look its bubble hands it. It draws only; the bubble owns its
// surface, screen and phase.
//
// A phase change eases every drawn value to the next look over the look's
// transition, with Qt animations that end on their own. The clocks, the
// noise field, the turn, the throb and the spark clock, move while the orb
// is active and visible in a shown window and the motion scale is above 0,
// in every look: each moves at its own base rate, and the driving level,
// through the look's one input curve, adds to it (Appearance.js, the
// motion model). A look with a `frameRate` draws at most that many frames
// a second and a look with 0 draws every frame the screen does; either way
// the clocks advance by the time that passed, so the motion's speed is the
// same. At motion scale 0 the clocks stop and the orb draws its last frame
// in every look (docs/architecture/design-system.md § Motion).
Item {
    id: root

    // A key of the look's `state` group.
    property string phase: "armed"
    property real capture: 0
    property real playback: 0
    property bool active: false
    // The reduced look, a lighter pass with no inner rim strand. Nothing
    // selects it: the full look draws on every device (overseer answer
    // 1793749461-1774370-11999), and the shader instrument measures both.
    property bool reduced: false
    required property var look
    readonly property var tone: look.state[phase]
    // The window the orb draws in, read as vgs.voice's Plasma reads it: a
    // plugin may not import QtQuick.Window (scripts/check-plugin-boundary.py).
    readonly property var host: QsWindow.window
    // The driving level through the input curve.
    readonly property real target: response(tone.drive === "capture" ? capture
        : tone.drive === "playback" ? playback : 0)
    // Whether the clocks move.
    readonly property bool moving: root.active && root.visible && root.look.motion.scale > 0
                                   && root.host !== null && root.host.visible
    // The eased level while the clocks move, the target while they stand.
    readonly property real driven: moving ? clock.level : target
    // The palette as drawn now, top to bottom, eased with the look: the
    // bubble's field rings the orb with it.
    readonly property var stops: [eased.topStop, eased.upperStop, eased.lowerStop, eased.bottomStop]
    // The clocks wrap where the drawn motion repeats, so a look shown for
    // days keeps float32 precision in the shader's uniforms with no visible
    // jump. The noise lattice repeats every `latticePeriod` cells on each
    // axis (shaders/particleorb.frag reads it as uExtra.w). The flow moves
    // the noise by 1, 1.6 and 0.5 times itself along y and by 0.6 and 0.4
    // times itself along x and z, so after `flowTurn`, ten periods, every
    // move is a whole number of periods and the field is the same. The
    // twinkle, sin(3 t), repeats every 2π/3 of `time`, and 2π is three of
    // those.
    readonly property real latticePeriod: 32
    readonly property real flowTurn: 10 * latticePeriod
    readonly property real twinkleTurn: 2 * Math.PI

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

        // An inactive orb starts its clocks again from 0; the driver keeps
        // them within their turns while it runs.
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

        // One drawn frame, `elapsed` seconds after the last.
        function advance(elapsed) {
            // A frame after a stall moves the orb by at most 50 ms.
            const dt = Math.max(0, Math.min(0.05, elapsed));
            const scale = root.look.motion.scale;
            level = smooth(level, root.target, dt);
            // The turn and throb periods are durations, which the motion
            // scale already lengthens; the rates divide by it.
            time = (time + dt / scale) % root.twinkleTurn;
            flow = (flow + dt * (root.tone.flow * (1 + level) + root.tone.levelFlow * level) / scale) % root.flowTurn;
            if (root.tone.quarterTurn > 0)
                swirl = (swirl + dt * 500 * Math.PI / root.tone.quarterTurn) % (2 * Math.PI);
            if (root.tone.throb > 0)
                throb = (throb + dt * 2000 * Math.PI / root.tone.throb) % (2 * Math.PI);
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
            + eased.throbDepth * Math.sin(clock.throb), root.look.orb.tilt, eased.fold, root.latticePeriod)
        property real uReduce: root.reduced ? 1 : 0
        fragmentShader: Qt.resolvedUrl("shaders/particleorb.frag.qsb")
    }

    // How a window presents at a look's rate (Qt 6.12.0, qtdeclarative v6.12.0
    // sources): a running FrameAnimation is a leaf animation job, which keeps
    // the scene graph's animation driver running, and while it runs with one
    // window exposed the threaded render loop requests the next update after
    // every frame it advances (qsgthreadedrenderloop.cpp, polishAndSync), and
    // in Qt 6 every update it syncs is rendered and swapped (syncAndRender:
    // "this function always completes and presents a frame"). So no
    // FrameAnimation may run in a paced look, or its window swaps at the
    // screen's rate whatever the uniforms do. A QML Timer is a pause animation
    // job (qmlmeta/types/qqmltimer.cpp), and with only pause jobs running the
    // animation timer pauses the driver and waits on a plain timer for the
    // next to end (qabstractanimationjob.cpp,
    // QQmlAnimationTimer::restartAnimationTimer). No window.update() is
    // called: each tick changes the ShaderEffect's uniforms, which updates the
    // item and schedules one frame of its window. The armed overlay, alone in
    // its layer, read 30.3 swaps a second this way on cachy's nested 60 Hz
    // output, and thinking 60.0 (VGS-2210 fix round 3 run 1793761130-2,
    // docs/architecture/jarvis.md § Overlay motion).
    FrameAnimation {
        id: driver
        // Motion scale 0 stills every look: the clocks' rates divide by it.
        running: root.moving && root.tone.frameRate === 0
        onTriggered: clock.advance(frameTime)
    }

    Timer {
        id: pacer
        // The wall clock of the last paced frame, in ms; advance() bounds
        // the step a wall clock change makes.
        property real last: 0
        interval: Math.round(1000 / Math.max(1, root.tone.frameRate))
        repeat: true
        running: root.moving && root.tone.frameRate > 0
        onRunningChanged: last = Date.now()
        onTriggered: {
            const now = Date.now();
            clock.advance((now - last) / 1000);
            last = now;
        }
    }
}
