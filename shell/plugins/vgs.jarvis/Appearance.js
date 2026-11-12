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
// duration here (0 stills the orb and shows the words whole), and its
// `scheme.mode`, which applies LIGHT. Nothing meets the wallpaper: the orb,
// the icon row and every line stand on a plate of glass (`plate`), and each
// ink is chosen against the worst ground its plate can show. Dark mode
// uses light ink on dark plates; LIGHT uses dark ink on light plates and
// draws the orb in darker stops on its light disc. Text takes its family
// and size from its qs.Ui Label role; this table hands it its colour and
// its shadow.
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

// Light mode's orb stands on a light disc, where a dot shows by being
// darker than its ground, not brighter: each stop is mixed toward black by
// `deep`, the lattice's and the rim's weights and the saturation are
// multiplied, and a dot is larger (LIGHT `orb.dot`). The weights set a
// dot's coverage; the shader's tone curve lightens a colour as weight
// stacks, so the rim takes less weight to keep its hue and the lattice
// more to cover its ground. Motion and shape are dark mode's. A thinned
// lattice reads as blots at the larger dot, so the two lasting states that
// thin it keep more of it (`thinned`), the fault's at a lighter weight.
var LIGHT_ORB = {
    deep: 0.55, interior: 2.8, rim: 0.5, saturation: 1.7,
    thinned: { idle: { presence: 0.8 }, error: { presence: 0.95, interior: 1.04 } }
};

function lightStates() {
    var out = {};
    for (var name in STATES) {
        var base = changed(STATES[name]);
        var light = {};
        var stops = ["top", "upper", "lower", "bottom", "core"];
        for (var i = 0; i < stops.length; i++)
            light[stops[i]] = "mix(" + base.palette[stops[i]] + ", #000000, " + LIGHT_ORB.deep + ")";
        // The shader lifts a spark's colour halfway to white, so black is
        // the darkest spark: a grey point on the light disc.
        light.hot = "#000000";
        light.interior = Math.min(4, base.interior * LIGHT_ORB.interior);
        light.rim = Math.min(4, base.rim * LIGHT_ORB.rim);
        light.saturation = Math.min(4, base.saturation * LIGHT_ORB.saturation);
        for (var key in LIGHT_ORB.thinned[name]) light[key] = LIGHT_ORB.thinned[name][key];
        out[name] = light;
    }
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
        rest: color("#b9bcc6"),
        active: color("#f4f5f8"),
        on: color("readable({palette.accent}, {plate.card.nearInk}, readable(mix({palette.accent}, {icon.active}, 0.5), {plate.card.nearInk}, {icon.active}))"),
        ring: color("#f4f5f8"),
        fade: duration(400),
        easing: easing("inOutQuad"),
        hold: number(250, 0, 1000)
    },
    // Each line's ink on the text card; LIGHT supplies the dark inks for
    // its light card. The look hands a Label its colour alone.
    ink: {
        state: color("#e6e8ee"),
        title: color("#f4f5f8"),
        action: color("#b9bcc6"),
        link: color("#9cc3ff"),
        words: color("#f4f5f8"),
        question: color("#ffffff"),
        path: color("#e6e8ee"),
        payload: color("#f4f5f8"),
        hint: color("#e6e8ee")
    },
    // Light text lifts off the dark card; dark text in LIGHT draws no
    // shadow.
    shadow: {
        color: color("#000000"),
        opacity: share(0.1275),
        blur: length(9)
    },
    // The approval prompt's answers in the soft form, the owner's preferred
    // one; this group and Bubble.qml's Answer are the one place the form is
    // chosen. Confirm (Yes) stands on a faint white fill that rises under
    // the pointer, where its label dims a step and the shimmer crosses it;
    // Cancel (No) is bare words, a dimmer ink that brightens under the
    // pointer. A press drops either to the faintest fill.
    answer: {
        height: length(26),
        paddingX: length(13),
        radius: length(13),
        gap: length(6),
        fill: color("alpha(#ffffff, 0.075)"),
        hoverFill: color("alpha(#ffffff, 0.1125)"),
        pressedFill: color("alpha(#ffffff, 0.06)"),
        // Neither fill nor border: Cancel's rest and hover, every border.
        clear: color("alpha(#ffffff, 0)"),
        ink: color("#ffffff"),
        hoverInk: color("#d3d5dc"),
        bareInk: color("#f4f5f8"),
        bareHoverInk: color("#ffffff"),
        // One sweep of the band and the pause after it, repeated while the
        // pointer rests on Confirm, and the band's half-width as a share of
        // the label.
        shimmer: {
            sweep: duration(1600),
            pause: duration(600),
            band: share(0.16),
            easing: easing("inOutCubic")
        }
    },
    // The plates the overlay stands on, each one qs.Ui GlassSurface with no
    // drop shadow: the compositor blurs the wallpaper behind a plate where
    // a layer rule asks, and the plate's fill alone holds every ink's
    // contrast where it does not. A plate without glass draws its `base`
    // opaque inside `border`. `gap` parts two plates.
    plate: {
        gap: length(8),
        // Larger than any side, so a plate rounds to a circle or a capsule.
        full: length(4096),
        // The orb's disc: dark under dark mode's orb, whose points are
        // light, and the card's light base under LIGHT's darker orb.
        // `reach` is the disc's radius as a share of the canvas
        // half-width; the shader draws nothing past 1.3 of a state's
        // radius (shaders/particleorb.frag), 0.92 of the half-width at the
        // widest, speaking at its loudest.
        orb: {
            reach: share(0.94),
            base: color("#020308"),
            opacity: share(0.9),
            fill: color("alpha({plate.orb.base}, {plate.orb.opacity})"),
            border: color("#1b1d24")
        },
        // The card under the words, and under the state line, the fault or
        // the held request: it holds the lines it shows inside its
        // padding. One line of the state rounds to a capsule.
        card: {
            base: color("#101010"),
            opacity: share(0.8),
            fill: color("alpha({plate.card.base}, {plate.card.opacity})"),
            // The card as drawn over the wallpaper nearest its ink: white
            // under the dark card, black under the light one. An ink that
            // reads at 4.5:1 on it reads so over any wallpaper.
            nearInk: color("mix(#ffffff, {plate.card.base}, {plate.card.opacity})"),
            border: color("#2a2a2a"),
            radius: length(20),
            paddingX: length(16),
            paddingY: length(12)
        },
        // The capsule of the card's fill behind the icon row, which
        // stands beside the disc, top to bottom.
        pill: {
            paddingX: length(4),
            paddingY: length(8)
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
        middle: share(0.8),
        oldest: share(0.62)
    }
};

// Light mode draws light plates with dark text, icons and answers, and
// the orb in its darker stops (LIGHT_ORB).
var LIGHT = {
    orb: {
        // 0.87 px at the 255 px canvas.
        dot: 0.0068
    },
    state: lightStates(),
    plate: {
        // The card's light base at the dark disc's own thickness: the
        // orb's points are finer than text.
        orb: {
            base: "#f2f2f2",
            border: "#d2d2d2"
        },
        card: {
            base: "#f2f2f2",
            opacity: 0.85,
            nearInk: "mix(#000000, {plate.card.base}, {plate.card.opacity})",
            border: "#d2d2d2"
        }
    },
    icon: {
        rest: "#424956",
        active: "#171c25",
        ring: "#171c25"
    },
    ink: {
        state: "#262c36",
        title: "#171c25",
        action: "#424956",
        link: "#214b81",
        words: "#171c25",
        question: "#171c25",
        path: "#363d4a",
        payload: "#262c36",
        hint: "#424956"
    },
    shadow: {
        opacity: 0
    },
    // Older settled caption lines keep their hierarchy without fading dark
    // ink back into the light card. Reveal and lift timing stay shared.
    words: {
        middle: 0.85,
        oldest: 0.75
    },
    answer: {
        fill: "alpha(#000000, 0.075)",
        hoverFill: "alpha(#000000, 0.1125)",
        pressedFill: "alpha(#000000, 0.06)",
        clear: "alpha(#000000, 0)",
        ink: "#171c25",
        hoverInk: "#363d4a",
        bareInk: "#262c36",
        bareHoverInk: "#171c25"
    }
};
