.pragma library

// The Jarvis overlay's own look, the table the manifest's `appearance`
// names and ThemeLogic.acceptAppearance judges (D023, scoped to the files
// that bind it: D119). The overlay is the particle orb at the bottom of the
// screen, its state line, its icon row and Jarvis's words; it must look the
// same under every theme, as vgs.voice's plasma does. The console, the bar
// widget and the power card bind no look and follow the theme.
//
// The theme reaches this table through `palette.accent`, which draws an
// icon toggle's glyph while it is on, `motion.scale`, which scales every
// duration here (0 stills the orb and shows the words whole). The icon row
// and every line stand on the same neutral glass in both modes (`plate`).
// Its black tint dims the blurred backdrop without adding a colour, and
// each light ink reads against its brightest ground, the tint over white.
// Nothing stands behind the orb: each point carries a thin dark edge, so one
// recipe reads on a light, a dark and a busy wallpaper in both modes. Text
// takes its family and size from its qs.Ui Label role; this table hands it
// its colour.
//
// Each state is one set of the orb shader's inputs (shaders/particleorb.frag).
// Palette stops run top, upper, lower, bottom over the orb's height; `core`
// tints the interior's centre and `hot` is the spark colour.
//
// The motion model (owner: "no state should be completely still. its only
// the rate of movement that should change"): every state moves at its own
// base rate, its flow (the noise field's rate) and its quarter turn (the
// swirl), with its own character: scatter, displacement, brightness and
// presence, and confirming's throb. Input adds to the base: `drive` names
// the level that does, the capture level while listening and the playback
// level while speaking, passed through one curve, `orb.response`, and the
// `drive*` numbers and `levelFlow` are what the curve's 1 adds. A state
// that can show all day, waiting, idle, muted or showing a fault, draws at
// most `frameRate` frames a second; the others draw every frame the screen
// does. Its rates are in units a second, so the frame rate changes how
// often the orb draws, never how fast it moves.

function color(value) { return { type: "color", value: value }; }
function length(value) { return { type: "length", value: value }; }
function duration(value) { return { type: "duration", value: value }; }
function number(value, min, max) { return { type: "number", value: value, min: min, max: max }; }
function share(value) { return number(value, 0, 1); }
function gain(value) { return number(value, 0, 4); }
function choice(value, options) { return { type: "choice", value: value, options: options }; }
function easing(value) { return { type: "easing", value: value }; }

// The reference palette: the owner's orb (tmp/vgs-2210 ref-colour.png).
var REFERENCE = { top: "#478cfa", upper: "#8052eb", lower: "#f24285", bottom: "#ff6b29", core: "#125c80", hot: "#ffd18c" };

// The reference at rest with no clock, which each state changes.
var REST = {
    palette: REFERENCE, radius: 0.69, amp: 0.18, scatter: 1.0, sparks: 0.012,
    interior: 0.58, rim: 1.2, saturation: 1.3, presence: 1.0, brightness: 1.0, fold: 1.0,
    flow: 0.05, levelFlow: 0, quarterTurn: 9000, throb: 0, throbDepth: 0,
    drive: "none", driveAmp: 0, driveScatter: 0, driveBright: 0, driveRadius: 0,
    frameRate: 0
};

// REST changed by OVER.
function changed(over) {
    var base = {};
    for (var rest in REST) base[rest] = REST[rest];
    for (var key in over) base[key] = over[key];
    return base;
}

// One state's leaves.
function state(over) {
    var base = changed(over);
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
        // The noise field's base rate in units a second, and what the
        // input curve's 1 adds.
        flow: gain(base.flow),
        levelFlow: gain(base.levelFlow),
        // A quarter turn about the vertical axis, the swirl's base rate.
        quarterTurn: duration(base.quarterTurn),
        // The brightness throb's period and depth; period 0 does not throb.
        throb: duration(base.throb),
        throbDepth: share(base.throbDepth),
        drive: choice(base.drive, ["none", "capture", "playback"]),
        driveAmp: share(base.driveAmp),
        driveScatter: gain(base.driveScatter),
        driveBright: gain(base.driveBright),
        driveRadius: share(base.driveRadius),
        // The most frames a second the orb draws in this state; 0 draws
        // every frame the screen does.
        frameRate: number(base.frameRate, 0, 240)
    };
}

// Each state's changes to REST. The table in docs/architecture/jarvis.md
// § Overlay motion states each state's line; tst_jarvis_orb.qml holds the
// base rates to it.
var STATES = {
    // Waiting for the wake word, possibly all day: a slow drift and one
    // turn in 36 s.
    // Up with capture closed: the lattice gathers and drifts slower.
    idle: { presence: 0.55, brightness: 0.72, flow: 0.04, quarterTurn: 10000, frameRate: 30 },
    // The silent room drifts a little faster than waiting; the
    // microphone's level raises the band and speeds the field.
    listening: {
        palette: { top: "#40d4ff", upper: "#4a7dff", lower: "#8a4dff", bottom: "#e0409a", core: "#0f5f86", hot: "#c8f4ff" },
        amp: 0.16, flow: 0.08, quarterTurn: 8000, levelFlow: 0.7, drive: "capture", driveAmp: 0.12, driveScatter: 0.8, driveBright: 0.35
    },
    thinking: {
        palette: { top: "#9a8cff", upper: "#5a46e8", lower: "#2ab7c8", bottom: "#3f58d8", core: "#162a6a", hot: "#d9f3ff" },
        amp: 0.13, scatter: 0.7, flow: 0.12, quarterTurn: 1750, sparks: 0.02
    },
    // Working on an action: thinking's family, turning faster, with
    // amber sparks.
    acting: {
        palette: { top: "#9a8cff", upper: "#5a46e8", lower: "#2ab7c8", bottom: "#d8a040", core: "#162a6a", hot: "#ffc35a" },
        amp: 0.14, scatter: 0.8, flow: 0.2, quarterTurn: 1125, sparks: 0.045
    },
    // The voice's level swells the orb and its band.
    speaking: {
        flow: 0.3, quarterTurn: 7500, drive: "playback",
        driveAmp: 0.12, driveScatter: 0.6, driveBright: 0.3, driveRadius: 0.03
    },
    // Waiting on the user's answer: amber, throbbing.
    confirming: {
        palette: { top: "#ffe08a", upper: "#ffa53d", lower: "#ff6a2b", bottom: "#e8344a", core: "#4a2a08", hot: "#fff2c8" },
        amp: 0.14, scatter: 0.8, flow: 0.1, quarterTurn: 7000, throb: 1400, throbDepth: 0.22, sparks: 0.02
    },
    // A fault stays until the next Talk press: the lattice stands
    // broken and drifts slowly.
    error: {
        palette: { top: "#ff8a80", upper: "#f0444a", lower: "#c41a35", bottom: "#7d0e2a", core: "#3a0a14", hot: "#ffd0c8" },
        amp: 0.24, scatter: 1.8, presence: 0.72, sparks: 0, saturation: 1.2, flow: 0.04, quarterTurn: 10000, frameRate: 30
    },
    // Stopping: grey, thin and smaller, at the slowest rate.
    down: { saturation: 0.12, presence: 0.4, brightness: 0.55, radius: 0.62, sparks: 0, flow: 0.03, quarterTurn: 10000 },
    // The microphone is off: the reference in white, at the slowest rate.
    muting: { saturation: 0, brightness: 0.8, sparks: 0.01, flow: 0.03, quarterTurn: 10000, frameRate: 30 }
};

function states() {
    var out = {};
    for (var name in STATES) out[name] = state(STATES[name]);
    return out;
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
        // The state line's and the approval prompt's widths, each held to the
        // overlay's width on a narrower screen.
        line: length(340),
        prompt: length(400),
        // The least height the held request's payload scrolls in when it
        // does not fit the room the layer leaves it, about eight lines of
        // body text (24 px a line at scale 1, tst_jarvis_prompt.qml's
        // 20-line write under scripts/qml-unit.sh, Qt 6.12.0); a payload
        // that fits draws whole.
        payload: length(200),
        gap: length(8),
        // The square over the orb's centre that takes the pointer while
        // the overlay is active (D026): the right click that opens the
        // menu and the hover that shows the icon row. The orb's whole
        // canvas would take clicks meant for the window under its faint
        // edge.
        hit: length(150),
        // How far right of and above the orb's centre the icon row's input
        // rectangle starts, inside the hit square, so the pointer moving
        // from the orb to an icon never leaves the input region.
        bridge: length(40),
        // The item at a right click that the menu opens from: one pixel
        // keeps its rectangle non-empty, as qs.Ui's Menu anchors to it.
        anchor: length(1)
    },
    orb: {
        // The canvas, 15% under the first build's 300 px (owner, revision
        // 5); the icon row, the hit square and the shader instrument's
        // scene follow it.
        size: length(255),
        // Cells per cube edge, full and reduced (the reduced look draws no
        // inner rim strand and the rim's front faces alone).
        cells: number(40, 8, 64),
        reducedCells: number(34, 8, 64),
        // A dot's radius as a share of the canvas half-width: 0.61 px at
        // the 255 px canvas.
        dot: number(0.0048, 0, 0.05),
        // The point edge, the one value that sets it: how dark the thin
        // edge round a point of the front face draws at full brightness.
        // On a light ground a point reads by its edge, on a dark one by
        // its core; 0 draws none. The shader scales it by the state's
        // brightness, throb included, and sets its width from `dot`
        // (shaders/particleorb.frag).
        edge: share(0.66),
        // The share of the canvas half-width the plates stand outside. It
        // holds the orb's band in every state: the outermost strand rests
        // at 1.095 of a state's radius (shaders/particleorb.frag), 0.78
        // of the half-width at the widest, speaking at its loudest. Past
        // it the shader draws only the thin spray, to 1.3 of the radius.
        reach: share(0.84),
        frequency: number(2.4, 0, 8),
        warp: share(0.22),
        // The fixed tilt about the horizontal axis, in radians.
        tilt: number(0.32, -1.6, 1.6),
        // The input curve: a level x from 0 to 1 drives the orb by
        // (1 - e^(-k x)) / (1 - e^(-k)) with k this steepness, an
        // exponential ease-out that is 0 at 0 and 1 at 1, continuous and
        // rising, with no step or threshold. At k 3 quiet speech, level
        // 0.1, moves the orb 27% of the way and a loud voice, level 0.5,
        // 82%. Capture and playback share it.
        response: number(3, 0.1, 10),
        // One state's change to the next, and the level's rise and fall.
        transition: duration(400),
        attack: duration(70),
        release: duration(250)
    },
    state: states(),
    // The icon row's glyphs: at rest, under the pointer or pressed, and the
    // focus ring. A toggle that is on draws `on`: the theme's accent where
    // it reads at 4.5:1 on the capsule over any wallpaper, else the accent
    // mixed halfway to the active ink where that reads, else the active
    // ink. The row shows only
    // while the pointer is over the orb in an active state: it fades in
    // and out over `fade`, and stays `hold` milliseconds after the pointer
    // leaves the orb, the row or the way between them, so a path that
    // cuts the corner between the two keeps it. The hold is a wait, not
    // motion, so the motion scale leaves it.
    icon: {
        rest: color("#dcdee4"),
        active: color("#ffffff"),
        on: color("readable({palette.accent}, {plate.card.nearInk}, readable(mix({palette.accent}, {icon.active}, 0.5), {plate.card.nearInk}, {icon.active}))"),
        ring: color("#f4f5f8"),
        fade: duration(400),
        easing: easing("inOutQuad"),
        hold: number(250, 0, 1000)
    },
    // Each line's ink on the text card, one plain ink a plate: weight and
    // size carry the hierarchy, since a dimmer ink would need a stronger
    // tint. The look hands a Label its colour alone, in both modes.
    ink: {
        state: color("#f4f5f8"),
        title: color("#f4f5f8"),
        action: color("#f4f5f8"),
        link: color("#c4dcff"),
        words: color("#f4f5f8"),
        question: color("#ffffff"),
        path: color("#f4f5f8"),
        payload: color("#f4f5f8")
    },
    // The approval prompt's answers: two capsules of equal width that fill
    // the card's row. Cancel (No) is quiet, a faint fill on the card;
    // Confirm (Yes) stands on the theme's accent with the ink that reads
    // on it, and its fill moves away from that ink under the pointer and,
    // less far, while pressed, so the label reads in every state under
    // every accent. They are fills, not glass: a plate inside a plate
    // draws solid.
    answer: {
        height: length(36),
        paddingX: length(16),
        radius: length(18),
        gap: length(8),
        // No border on either.
        clear: color("alpha(#ffffff, 0)"),
        quiet: {
            fill: color("alpha(#ffffff, 0.1)"),
            hoverFill: color("alpha(#ffffff, 0.13)"),
            pressedFill: color("alpha(#ffffff, 0.07)"),
            ink: color("#ffffff")
        },
        tinted: {
            fill: color("{palette.accent}"),
            hoverFill: color("mix({palette.accent}, contrast({answer.tinted.ink}), 0.12)"),
            pressedFill: color("mix({palette.accent}, contrast({answer.tinted.ink}), 0.05)"),
            ink: color("contrast({palette.accent})")
        }
    },
    // The plates the overlay stands on, each one qs.Ui GlassSurface in the
    // lens form with no drop shadow: the compositor blurs the backdrop
    // under a plate's body where a layer rule asks, the body's fill alone
    // holds every ink's contrast where it does not, and the rim's band is
    // clear. A plate without glass draws its `base` opaque inside
    // `border`. `gap` parts two plates.
    plate: {
        gap: length(8),
        // Larger than any side, so a plate rounds to a capsule.
        full: length(4096),
        // The glass tint's strength, the one value that sets it: the
        // alpha of every plate's fill in both modes. The band's tint, the
        // ground each ink is judged on and the shader's body all derive
        // from it. It stays above the blur thresholds, the manifest
        // rule's 0.6 and the core rule's 0.7, and above the floor one
        // plain ink needs on the opposite ground, about 0.6
        // (tst_jarvis_plates.qml, scripts/check-theme-contrast.js).
        tint: share(0.71),
        // The lens (qs.Ui shaders/glasslens.frag): the bezel band's
        // width; the share of the tint the band loses, which takes it
        // under the blur threshold; the glint on the rim and the glow
        // inside it; the share of that light the far wall takes; the dark
        // line outside the rim; and the line where the band meets the
        // body.
        lens: {
            bezel: length(3),
            clarity: share(0.4),
            glint: share(0.85),
            glow: share(0.2),
            exit: share(0.8),
            outline: share(0.3),
            seam: share(0.1)
        },
        // The card under the words, and under the state line, the fault or
        // the held request: it holds the lines it shows inside its
        // padding, which is wider than the bezel. One line of the state
        // rounds to a capsule.
        card: {
            base: color("#000000"),
            fill: color("alpha({plate.card.base}, {plate.tint})"),
            // The card over its brightest wallpaper, white in both modes.
            // An ink that reads at 4.5:1 on it reads so over any wallpaper.
            nearInk: color("mix(#ffffff, {plate.card.base}, {plate.tint})"),
            border: color("#34343a"),
            radius: length(26),
            paddingX: length(18),
            paddingY: length(14)
        },
        // The capsule of the card's fill behind the icon row, which
        // stands beside the orb, top to bottom.
        pill: {
            paddingX: length(9),
            paddingY: length(12)
        }
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
        // Every settled line holds 4.5:1 on the card over white; `oldest`
        // is the top line of the three. The line leaving fades from it.
        middle: share(0.9),
        oldest: share(0.82)
    }
};

// acceptAppearance takes a light-mode override object; this material has
// no mode-dependent values.
var LIGHT = {};
