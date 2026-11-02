.pragma library

// The Jarvis overlay's own look, the table the manifest's `appearance`
// names and ThemeLogic.acceptAppearance judges (D023, scoped to the files
// that bind it: D118). The overlay is the particle orb at the bottom of the
// screen, its state line, its icon row and Jarvis's words; it must look the
// same under every theme, as vgs.voice's plasma does. The console, the bar
// widget and the power card bind no look and follow the theme.
//
// The theme reaches this table through `palette.accent`, which draws an
// icon toggle's glyph while it is on, `motion.scale`, which scales every
// duration here (0 stills the orb and shows the words whole), and its
// `scheme.mode`, which applies LIGHT. The overlay draws on a dark field in
// both modes, so LIGHT changes nothing. Text takes its family and size from
// its qs.Ui Label role; this table hands it its colour alone.
//
// Each state is one set of the orb shader's inputs (shaders/particleorb.frag).
// Palette stops run top, upper, lower, bottom over the orb's height; `core`
// tints the interior's centre and `hot` is the spark colour. A state's own
// clock is its flow rate, its quarter turn and its throb period; a phase the
// Session bounds with no deadline has none, so it stands still once its
// transition ends. `drive` names the level that moves the orb, and the
// `drive*` numbers are what that level adds at level 1.

function color(value) { return { type: "color", value: value }; }
function length(value) { return { type: "length", value: value }; }
function duration(value) { return { type: "duration", value: value }; }
function number(value, min, max) { return { type: "number", value: value, min: min, max: max }; }
function share(value) { return number(value, 0, 1); }
function gain(value) { return number(value, 0, 4); }
function choice(value, options) { return { type: "choice", value: value, options: options }; }

// The reference palette: the owner's orb (tmp/vgs-2210 ref-colour.png).
var REFERENCE = { top: "#478cfa", upper: "#8052eb", lower: "#f24285", bottom: "#ff6b29", core: "#125c80", hot: "#ffd18c" };

// One state: the reference at rest with no clock, changed by OVER.
function state(over) {
    var base = {
        palette: REFERENCE, radius: 0.69, amp: 0.18, scatter: 1.0, sparks: 0.012,
        interior: 0.58, rim: 1.2, saturation: 1.3, presence: 1.0, brightness: 1.0, fold: 1.0,
        flow: 0, levelFlow: 0, quarterTurn: 0, throb: 0, throbDepth: 0,
        drive: "none", driveAmp: 0, driveScatter: 0, driveBright: 0, driveRadius: 0
    };
    for (var key in over) base[key] = over[key];
    return {
        top: color(base.palette.top),
        upper: color(base.palette.upper),
        lower: color(base.palette.lower),
        bottom: color(base.palette.bottom),
        core: color(base.palette.core),
        hot: color(base.palette.hot),
        // The orb's radius as a share of the canvas half-width.
        radius: share(base.radius),
        // The band's displacement and the outer strand's outward scatter.
        amp: share(base.amp),
        scatter: gain(base.scatter),
        // The share of dots drawn as white sparks.
        sparks: share(base.sparks),
        interior: gain(base.interior),
        rim: gain(base.rim),
        saturation: gain(base.saturation),
        // The share of the lattice's dots drawn.
        presence: share(base.presence),
        brightness: gain(base.brightness),
        fold: share(base.fold),
        // The noise field's rate in units a second, and what level 1 adds.
        flow: gain(base.flow),
        levelFlow: gain(base.levelFlow),
        // A quarter turn about the vertical axis; 0 does not turn.
        quarterTurn: duration(base.quarterTurn),
        // The brightness throb's period and depth; period 0 does not throb.
        throb: duration(base.throb),
        throbDepth: share(base.throbDepth),
        drive: choice(base.drive, ["none", "capture", "playback"]),
        driveAmp: share(base.driveAmp),
        driveScatter: gain(base.driveScatter),
        driveBright: gain(base.driveBright),
        driveRadius: share(base.driveRadius)
    };
}

var TOKENS = {
    palette: {
        accent: color("#ff5a36")
    },
    motion: {
        scale: number(1, 0, 4)
    },
    layout: {
        // The gap between the overlay and the layer's bottom edge.
        margin: length(12),
        // The overlay's width, which holds the orb, its icon row and the
        // widest line under it.
        width: length(480),
        // The state line's and the approval prompt's widths.
        line: length(340),
        prompt: length(400),
        // The gap between the orb's ring and the line under it.
        below: length(26),
        gap: length(8)
    },
    orb: {
        size: length(300),
        // Cells per cube edge, full and reduced (the reduced look draws no
        // inner rim strand and the rim's front faces alone).
        cells: number(40, 8, 64),
        reducedCells: number(34, 8, 64),
        // A dot's radius as a share of the canvas half-width: 0.72 px at
        // the 300 px canvas.
        dot: number(0.0048, 0, 0.05),
        frequency: number(2.4, 0, 8),
        warp: share(0.22),
        // The fixed tilt about the horizontal axis, in radians.
        tilt: number(0.32, -1.6, 1.6),
        // A driving level at or below this moves nothing.
        floor: share(0.02),
        // One state's change to the next, and the level's rise and fall.
        transition: duration(400),
        attack: duration(70),
        release: duration(250)
    },
    state: {
        // Waiting for the wake word, possibly all day: still.
        armed: state({ brightness: 0.9 }),
        // Up with capture closed and no deadline: the lattice gathers.
        idle: state({ presence: 0.55, brightness: 0.72 }),
        // The microphone's level raises the band and moves the field; a
        // silent room moves nothing.
        listening: state({
            palette: { top: "#40d4ff", upper: "#4a7dff", lower: "#8a4dff", bottom: "#e0409a", core: "#0f5f86", hot: "#c8f4ff" },
            amp: 0.16, levelFlow: 0.7, drive: "capture", driveAmp: 0.12, driveScatter: 0.8, driveBright: 0.35
        }),
        thinking: state({
            palette: { top: "#9a8cff", upper: "#5a46e8", lower: "#2ab7c8", bottom: "#3f58d8", core: "#162a6a", hot: "#d9f3ff" },
            amp: 0.13, scatter: 0.7, flow: 0.12, quarterTurn: 1750, sparks: 0.02
        }),
        // Working on an action: thinking's family, turning faster, with
        // amber sparks.
        acting: state({
            palette: { top: "#9a8cff", upper: "#5a46e8", lower: "#2ab7c8", bottom: "#d8a040", core: "#162a6a", hot: "#ffc35a" },
            amp: 0.14, scatter: 0.8, flow: 0.2, quarterTurn: 1125, sparks: 0.045
        }),
        // The voice's level swells the orb and its band.
        speaking: state({
            flow: 0.3, quarterTurn: 7500, drive: "playback",
            driveAmp: 0.12, driveScatter: 0.6, driveBright: 0.3, driveRadius: 0.03
        }),
        // Waiting on the user's answer: amber, throbbing.
        confirming: state({
            palette: { top: "#ffe08a", upper: "#ffa53d", lower: "#ff6a2b", bottom: "#e8344a", core: "#4a2a08", hot: "#fff2c8" },
            amp: 0.14, scatter: 0.8, flow: 0.1, throb: 1400, throbDepth: 0.22, sparks: 0.02
        }),
        // A fault stays until the next Talk press: the lattice stands
        // broken and still.
        error: state({
            palette: { top: "#ff8a80", upper: "#f0444a", lower: "#c41a35", bottom: "#7d0e2a", core: "#3a0a14", hot: "#ffd0c8" },
            amp: 0.24, scatter: 1.8, presence: 0.72, sparks: 0, saturation: 1.2
        }),
        // Stopping: grey, thin and smaller, then still.
        down: state({ saturation: 0.12, presence: 0.4, brightness: 0.55, radius: 0.62, sparks: 0 }),
        // The microphone is off: the reference in white, still.
        muting: state({ saturation: 0, brightness: 0.8, sparks: 0.01 })
    },
    // The icon row's glyphs: at rest, under the pointer or pressed, and the
    // focus ring. A toggle that is on draws the accent.
    icon: {
        rest: color("#a3a7b3"),
        active: color("#f4f5f8"),
        ring: color("#f4f5f8")
    },
    // Each line's ink. The look hands a Label its colour alone.
    ink: {
        state: color("#c4c7d0"),
        title: color("#f4f5f8"),
        action: color("#b9bcc6"),
        link: color("#9cc3ff"),
        words: color("#f4f5f8"),
        question: color("#f4f5f8"),
        path: color("#a9adb8"),
        payload: color("#d3d5dc"),
        hint: color("#9a9eaa")
    },
    // Jarvis's words while its voice is muted: one more word each step
    // until the caption is caught up, the newest fading in, a full line
    // moving up and the oldest of the three fading out.
    words: {
        lines: number(3, 1, 6),
        step: duration(180),
        fade: duration(150),
        lift: duration(250),
        newest: share(1),
        middle: share(0.55),
        oldest: share(0.22)
    }
};

var LIGHT = {};
