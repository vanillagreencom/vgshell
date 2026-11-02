.pragma library

// Voice's own look, the table the manifest's `appearance` names and
// ThemeLogic.acceptAppearance judges (D023): the on-screen display's plasma
// orb, which must look the same under every theme. Every value is the owner's
// voxtype plasma OSD's (PlasmaSurface.qml): its 300 px canvas 25 px above the
// screen's bottom edge, its level smoothing, its transcribing pulse and its
// two four-colour palettes, warm while recording and cool while
// transcribing, in the shader's order: glass rim, plasma edge, plasma middle
// and plasma core. The active theme reaches this table through
// `palette.accent`, which tints the bar mic while recording, `motion.scale`
// and its `scheme.mode`, which applies LIGHT; the orb's dark backdrop is
// the same in both modes, so LIGHT changes nothing.

function color(value) { return { type: "color", value: value }; }
function length(value) { return { type: "length", value: value }; }
function duration(value) { return { type: "duration", value: value }; }
function number(value, min, max) { return { type: "number", value: value, min: min, max: max }; }
function share(value) { return number(value, 0, 1); }
function choice(value, options) { return { type: "choice", value: value, options: options }; }

var TOKENS = {
    palette: {
        accent: color("#ff5a36")
    },
    motion: {
        scale: number(1, 0, 4)
    },
    osd: {
        // The gap between the orb's canvas and the screen's bottom edge.
        margin: length(25)
    },
    plasma: {
        // The owner's canvas, which the backdrop fills.
        size: length(300),
        // The plasma's own pass, centred in the canvas: the reach of its
        // embers, 300 / 1.36 px, where the owner's shader scaled its
        // coordinates by 1.36 to leave its backdrop a margin to fade into.
        // A number, since the judge rounds a length to a whole pixel and
        // this one keeps every pixel's coordinates as they were.
        orb: number(220.59, 0, 300),
        // Time constants of the level's rise and fall towards each frame's
        // level, of that level's own fall between frames, and of the slower
        // energy the core's brightness follows.
        attack: duration(50),
        release: duration(220),
        decay: duration(280),
        energy: duration(600),
        // The palette change between recording and transcribing.
        fade: duration(500),
        warm: {
            rim: color("#5a52e8"),
            edge: color("#d83a86"),
            mid: color("#fb6450"),
            hot: color("#ffd9d2")
        },
        cool: {
            rim: color("#4a72e0"),
            edge: color("#6a4ad0"),
            mid: color("#3fc0e8"),
            hot: color("#d8f4ff")
        }
    },
    // The dark disc behind the plasma, as the owner's shader drew it: solid
    // to 0.53 of its scaled coordinates, then exp(-(d / 0.15)²) at peak 0.9,
    // which is 58.46 px and 16.54 px at the 300 px canvas: numbers, since
    // the judge rounds a length to a whole pixel. It draws through qs.Ui's
    // RadialBackdrop, the same in both modes.
    backdrop: {
        corner: number(58.46, 0, 150),
        fade: number(16.54, 0, 150),
        peak: share(0.9),
        ink: color("#000000"),
        falloff: choice("gaussian", ["eased", "gaussian"])
    },
    // The level both orbs breathe between while the words are transcribed,
    // and one breath's period.
    pulse: {
        low: share(0.4),
        high: share(0.85),
        period: duration(3142)
    }
};

var LIGHT = {};
