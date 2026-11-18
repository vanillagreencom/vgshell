.pragma library

// Glass, the one shared glass material, in the appearance-table format a
// plugin's own look takes, which ThemeLogic.acceptAppearance judges and
// Theme publishes once as `Theme.glass`, in the style the Glass page's
// Style chooses (ThemeLogic.glassStyle): TOKENS is Dark, LIGHT and CLEAR
// change it for Light and Clear. A style is these values alone; qs.Ui's
// GlassSurface draws every style with one pass (design-system.md § Glass
// plates over wallpaper). `window` holds what Hyprland draws its own
// windows with while window glass is on. Only declared appearance inputs
// reach this table (ThemeLogic.acceptAppearance).

function color(value) { return { type: "color", value: value }; }
function length(value) { return { type: "length", value: value }; }
function number(value, min, max) { return { type: "number", value: value, min: min, max: max }; }
function share(value) { return number(value, 0, 1); }
// A whole count Hyprland reads as an integer, within its bounds.
function whole(value, min, max) { return { type: "length", value: value, min: min, max: max }; }

var TOKENS = {
    // The theme's accent, which a lit edge light takes. Each style draws
    // its own neutral body, whatever the theme's surfaces.
    palette: {
        accent: color("#ff5a36")
    },

    motion: {
        scale: number(1, 0, 4)
    },

    glass: {
        // The body: its colour and alpha over the compositor's blur.
        base: color("#101010"),
        opacity: share(0.8),
        fill: color("alpha({glass.base}, {glass.opacity})"),
        // The reading ink on the body, and the ground it is judged on: the
        // body over its brightest backdrop, white, for a dark body. An ink
        // that reads at 4.5:1 on it reads so over any backdrop.
        ink: color("#e8e8e8"),
        ground: color("mix(#ffffff, {glass.base}, {glass.opacity})"),
        // The glass drawn solid, over content its own window draws, which
        // no compositor blur reaches: the body made opaque, so it hides
        // that content, and mixed toward white by this share, so it reads a
        // step above the glass it lies on.
        solidLift: share(0.05)
    },

    // The rim: one thin line at the body's edge and no bevel, brightest
    // where it faces the light at the upper left. `glint` is its strength
    // there, `ambient` the share it keeps on the walls beside the light's
    // diagonal and `far` the share the wall the light leaves by takes.
    rim: {
        width: number(1.25, 0.5, 4),
        glint: share(0.35),
        ambient: share(0.3),
        far: share(0.6)
    },

    // The edge light on the rim: two point lights orbit `lift` outside the
    // surface at `speed` px a second and the rim catches each where it
    // faces it, within `reach`, at `strengthA` and `strengthB`, a faint
    // glow, `glow` of the light, reaching into the body. `neutral` is the
    // light's colour, the rim's too; a surface that marks itself lit blends
    // it to the accent. `frameRate` is the most frames a second the light
    // moves at on a surface that can stay up all day.
    edge: {
        neutral: color("#fbfbfb"),
        reach: number(150, 0, 2000),
        lift: number(22, 0, 512),
        speed: number(95, 0, 2000),
        strengthA: number(1.25, 0, 8),
        strengthB: number(0.7, 0, 8),
        glow: share(0.22),
        frameRate: number(30, 1, 240)
    },

    // Hyprland's own windows: their opacity while focused and while not,
    // the blur behind them, and their drop shadow, within the ranges
    // Hyprland 0.56.2 accepts for decoration.blur and decoration.shadow.
    window: {
        opacity: share(0.92),
        inactiveOpacity: share(0.86),
        blurSize: whole(8, 1, 64),
        blurPasses: whole(2, 1, 8),
        shadowRange: whole(30, 0, 256),
        shadowPower: whole(3, 1, 4),
        shadowColor: color("alpha(#000000, 0.45)")
    }
};

// Light: the pale body today's light notifications and launcher draw, and
// dark ink, judged on the body over black.
var LIGHT = {
    glass: {
        base: "#f2f2f2",
        opacity: 0.85,
        ink: "#2a2a2a",
        ground: "mix(#000000, {glass.base}, {glass.opacity})",
        solidLift: 0.1
    },
    // Keep the edge light brighter than the pale body; a darker light reads
    // as a mark on it.
    edge: {
        neutral: "#ffffff"
    },
    window: {
        shadowColor: "alpha(#000000, 0.16)"
    }
};

// Clear: a faint neutral body, white ink and the rim, over the compositor's
// layer glass, whose own adaptive dimming (HyprlandLayer.CLEAR_PRESET)
// shades the body by how bright the blurred backdrop is (VGS-2594, approved
// third Clear candidate, comment 015d8e66). The body is 20/255 black. Over a
// white window that shading draws #6e6e6e under the text, the ground white
// is judged on: 4.85:1 by ThemeLogic.drawnTextRatio (contrast-third.json on
// VGS-2594). Without layer glass Clear draws its opaque reading ground
// (ThemeLogic.glassFor).
var CLEAR = {
    glass: {
        base: "#000000",
        opacity: 0.0784,
        ink: "#ffffff",
        ground: "#6e6e6e"
    },
    rim: {
        glint: 0.5
    },
    edge: {
        neutral: "#ffffff"
    }
};
