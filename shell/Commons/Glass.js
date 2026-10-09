.pragma library

// VGlass, the one shared glass look, in the appearance-table format a
// plugin's own look takes, which ThemeLogic.acceptAppearance judges and
// Theme publishes once as `Theme.glass`. Every surface that draws VGlass
// draws it from here through GlassSurface of qs.Ui, handing only its own
// fill, rounding and elevation. The values are the Spotlight launcher's and
// notification stack's (px13 dotfiles, spotlight/Theme.qml, GlassSurface.qml
// and hooks/theme-set.d/spotlight-menu-tokens.sh), which the two drew alike;
// the default fill is the notification toast's. `window` holds what
// Hyprland draws its own windows with while window glass is on. The active
// theme reaches this table through two inputs alone, `palette.accent` and
// `motion.scale`, plus its `scheme.mode`, which applies LIGHT; no other
// theme value can.

function color(value) { return { type: "color", value: value }; }
function length(value) { return { type: "length", value: value }; }
function number(value, min, max) { return { type: "number", value: value, min: min, max: max }; }
function share(value) { return number(value, 0, 1); }
// A signed pixel offset, such as a shadow's negative spread.
function offset(value) { return number(value, -512, 512); }
// A whole count Hyprland reads as an integer, within its bounds.
function whole(value, min, max) { return { type: "length", value: value, min: min, max: max }; }
// The foreground at one alpha: every tint the glass draws over its fill.
function ink(alpha) { return color("alpha({text.foreground}, " + alpha + ")"); }

var TOKENS = {
    // The theme's accent; the glass itself draws none of it.
    palette: {
        accent: color("#ff5a36")
    },

    motion: {
        scale: number(1, 0, 4)
    },

    text: {
        // The hook's own neutral for a dark theme.
        foreground: color("#e8e8e8")
    },

    glass: {
        // The fill a surface takes when it hands none of its own.
        fill: color("alpha(#101010, 0.8)"),
        sheen: ink(0.045),
        sheenEnd: ink(0),
        sheenHeight: length(48),
        hairline: ink(0.09),
        hairlineWidth: length(1)
    },

    // `wide` for a large card, `tight` for a small or transient surface.
    shadow: {
        wide: { color: color("alpha(#000000, 0.55)"), blur: length(90), offsetY: offset(28), spread: offset(-4) },
        tight: { color: color("alpha(#000000, 0.45)"), blur: length(30), offsetY: offset(10), spread: offset(-4) }
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
        shadowColor: color("{shadow.tight.color}")
    }
};

// Light mode: the hook's light glass and neutral, and the reference's light
// alphas.
var LIGHT = {
    text: {
        foreground: "#2a2a2a"
    },
    glass: {
        fill: "alpha(#f2f2f2, 0.85)",
        sheen: "alpha({text.foreground}, 0.35)",
        hairline: "alpha({text.foreground}, 0.1)"
    },
    shadow: {
        wide: { color: "alpha(#000000, 0.2)" },
        tight: { color: "alpha(#000000, 0.16)" }
    }
};
