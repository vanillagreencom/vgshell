pragma Singleton
import QtQuick
import Quickshell
import "Tokens.js" as Tokens
import "ThemeLogic.js" as ThemeLogic
import "Glass.js" as Glass
import "Inset.js" as Inset

// The design tokens as QML values: one read-only group per top-level group
// of Tokens.js, so a file reads `Theme.color.accent` or `Theme.text.body`.
// Every group is a deep-frozen object of primitives, so a write from any
// file changes nothing: a colour is the string `#aarrggbb` a colour
// property takes, never a colour value, whose channels a frozen object
// cannot protect. A theme change replaces the groups whose values it
// changes and rebuilds no component: a binding on such a group
// re-evaluates, and a group whose values stay keeps its object, so no
// binding on it runs. A handler that needs every group from one theme runs
// on `revisionChanged`, which fires after the last group holds the new
// values, also when no group changed. `documentRevision` rises after it,
// and only for another theme document: a handler that reads what a theme
// package or an apply changed runs on it, so an edit of the user's
// Appearance values does not start it. The bundled fonts load here, so
// their families are available before any component asks for them; a
// family a theme names that Qt does not list is logged once and drawn with
// the bundled family the token's default names.
Singleton {
    id: root

    readonly property string name: source.name
    readonly property int revision: source.revision
    readonly property int documentRevision: source.documentRevision
    // The theme file's state as ThemeSource last read it: `pending`, then
    // `loaded`, `absent`, `refused` or `unreadable`. A refused edit moves it
    // without a new revision.
    readonly property string fileState: source.state
    // The user's Appearance values, shell.json `appearance` as JSON text,
    // "" for none. Config alone binds it; scripts/check-plugin-boundary.py
    // refuses a plugin that names it.
    property string appearanceInput: ""
    // Where each Appearance value comes from, frozen: { values, theme,
    // sources, hyprland } (ThemeLogic.withAppearance). The groups below
    // already hold the resolved values.
    readonly property var appearanceState: source.appearance
    // VGlass, the one shared glass look (Glass.js), resolved as a plugin's
    // own look is: it follows the theme's mode, accent and motion scale
    // alone. GlassSurface of qs.Ui draws it.
    readonly property var glass: appearance(Glass.TOKENS, Glass.LIGHT)

    // Whether a surface whose own VGlass choice is OPTIN draws glass under
    // the user's Appearance values (ThemeLogic.glassOn).
    function glassOn(optIn) {
        return ThemeLogic.glassOn(appearanceState.values, optIn);
    }

    readonly property var scheme: published.scheme
    readonly property var palette: published.palette
    readonly property var color: published.color
    readonly property var space: published.space
    readonly property var radius: published.radius
    readonly property var border: published.border
    readonly property var opacity: published.opacity
    readonly property var motion: published.motion
    readonly property var hyprland: published.hyprland
    readonly property var size: published.size
    readonly property var icon: published.icon
    readonly property var font: published.font
    readonly property var text: published.text
    readonly property var control: published.control
    readonly property var row: published.row
    readonly property var inset: published.inset
    readonly property var stack: published.stack
    readonly property var surface: published.surface
    readonly property var divider: published.divider
    readonly property var groupList: published.groupList
    readonly property var card: published.card
    readonly property var focusRing: published.focusRing
    readonly property var button: published.button
    readonly property var segmented: published.segmented
    readonly property var tileGroup: published.tileGroup
    readonly property var toggle: published.toggle
    readonly property var checkbox: published.checkbox
    readonly property var radio: published.radio
    readonly property var slider: published.slider
    readonly property var textField: published.textField
    readonly property var field: published.field
    readonly property var spinner: published.spinner
    readonly property var progress: published.progress
    readonly property var voiceOrb: published.voiceOrb
    readonly property var voiceBubble: published.voiceBubble
    readonly property var badge: published.badge
    readonly property var kbd: published.kbd
    readonly property var keyHints: published.keyHints
    readonly property var codeLine: published.codeLine
    readonly property var avatarGroup: published.avatarGroup
    readonly property var qrMatrix: published.qrMatrix
    readonly property var tabs: published.tabs
    readonly property var listItem: published.listItem
    readonly property var deviceRow: published.deviceRow
    readonly property var sectionHeader: published.sectionHeader
    readonly property var scrollArea: published.scrollArea
    readonly property var titleButton: published.titleButton
    readonly property var rowAction: published.rowAction
    readonly property var popover: published.popover
    readonly property var tooltip: published.tooltip
    readonly property var menu: published.menu
    readonly property var select: published.select
    readonly property var osd: published.osd
    readonly property var saveBar: published.saveBar
    readonly property var dialog: published.dialog
    readonly property var angledCard: published.angledCard
    readonly property var carousel: published.carousel
    readonly property var bar: published.bar

    // The accepted values converted once, as one frozen tree. It follows
    // the fonts too, so a family judged before a bundled font was ready is
    // judged again.
    readonly property var convertedValues: convert(source.values, [mono, sans].filter(font => font.status === FontLoader.Ready).map(font => font.name))
    readonly property real bodyLineBox: Math.max(Math.round(convertedValues.text.body.size * convertedValues.text.body.lineHeight), Math.ceil(bodyMetrics.height))
    // A group property whose binding answers the object it holds emits no
    // change signal, and no binding on it runs (a run under qmltestrunner,
    // Qt 6.11.2).
    readonly property var published: identity.keep(convertBodyLines(Tokens.TOKENS, convertedValues, bodyLineBox))

    // A resolved colour is `#rrggbbaa`; Qt reads eight digits with alpha
    // first, so the alpha moves to the front here and nowhere else.
    // A control's side padding under a rounded corner: `pad`, or more
    // until its content clears the drawn corner by `inset.cornerStep`
    // (Inset.controlPadding).
    function controlPadding(pad, radius, height, contentHeight) {
        return Inset.controlPadding(pad, radius, height, contentHeight, inset.cornerStep);
    }

    // The top and bottom inset of the list of a menu or a select `width`
    // wide, inside the menu's border: the border alone while an entry's
    // corner is as round as the menu's, more under a menu corner rounder
    // than an entry's (Inset.listInset). The side inset is the border.
    function menuListInset(width) {
        return Inset.listInset(Math.min(menu.radius, width / 2), border.thin, Math.min(menu.item.radius, menu.item.height / 2));
    }

    // WCAG 2 contrast ratio of two opaque colours, and WCAG 2.2 SC 1.4.11's
    // floor for a boundary against what lies beside it.
    readonly property real boundaryFloor: ThemeLogic.BOUNDARY_FLOOR
    function contrastRatio(a, b) {
        return ThemeLogic.contrastRatio(a, b);
    }
    // White or black, whichever contrasts more with `color`: the rule of
    // the `contrast()` token function.
    function contrastOf(color) {
        return toColor(ThemeLogic.formatColor(ThemeLogic.contrastColor(color)));
    }

    // The room a row takes under its sub-text, a hint, error or warning
    // line, so the next row of `column` starts `stack.group` below that
    // line: the group space less the column's spacing. A row without
    // sub-text, outside a positioner (`index` -1) or last of the shown rows
    // takes none, so the space after a section or a page stays its own. A
    // positioner gives a hidden or zero-sized child index -1 and judges
    // `isLastItem` over the children it places (Qt 6.11
    // qquickpositioners.cpp, updateAttachedProperties).
    function subTextRoom(subText, index, last, column) {
        const spacing = column && column.spacing !== undefined ? column.spacing : 0;
        return subText && index >= 0 && !last ? Math.max(0, stack.group - spacing) : 0;
    }

    function toColor(text) {
        return "#" + text.slice(7, 9) + text.slice(1, 7);
    }

    // Every easing the judge accepts, by its QML enumerator. A name the
    // engine lacks is a defect of this file, not of a theme.
    readonly property var easings: {
        const out = {};
        for (const name of ThemeLogic.EASINGS) {
            const key = name[0].toUpperCase() + name.slice(1);
            if (Easing[key] === undefined) throw new Error("theme: easing " + name + " has no QML enumerator");
            out[name] = Easing[key];
        }
        return out;
    }

    // The QML value of one resolved token. `fallback` is the token's
    // default value, `loaded` the bundled families that are ready, and
    // `families` the families Qt knows, read once per conversion. A family
    // stands until the one its default names is loaded, so an unavailable
    // family always has a bundled family to draw in its place.
    function convertLeaf(leaf, value, fallback, loaded, families, missing) {
        switch (leaf.type) {
        case "color":
            return toColor(value);
        case "easing":
            return easings[value];
        case "family":
            if (loaded.indexOf(fallback) === -1 || loaded.indexOf(value) !== -1 || families().indexOf(value) !== -1) return value;
            const substitution = value + "\n" + fallback;
            if (missing.indexOf(substitution) === -1) {
                missing.push(substitution);
                console.warn("theme: font=" + value + " unavailable; drawing " + fallback);
            }
            return fallback;
        default:
            return value;
        }
    }

    // `values` resolved from `table` as one deep-frozen tree of QML values.
    // `defaults` holds each family's fallback, in the same shape.
    function convertTree(table, values, defaults, loaded) {
        const missing = [];
        let known = null;
        const families = () => {
            if (known === null) known = Qt.fontFamilies();
            return known;
        };
        const walk = (level, node, fallback) => {
            const out = {};
            for (const key of Object.keys(level))
                out[key] = ThemeLogic.isLeaf(level[key]) ? convertLeaf(level[key], node[key], fallback[key], loaded, families, missing) : walk(level[key], node[key], fallback[key]);
            return Object.freeze(out);
        };
        return walk(table, values, defaults);
    }

    // Match Label's font. Its inputs precede unit conversion, so changing
    // a body family cannot create a publication/measurement binding loop.
    FontMetrics {
        id: bodyMetrics
        font.family: root.convertedValues.text.body.family
        font.pixelSize: root.convertedValues.text.body.size
        font.weight: root.convertedValues.text.body.weight
        font.variableAxes: ({ wght: root.convertedValues.text.body.weight })
        font.letterSpacing: root.convertedValues.text.body.letterSpacing * root.convertedValues.text.body.size
        font.capitalization: root.convertedValues.text.body.uppercase ? Font.AllUppercase : Font.MixedCase
    }

    // A body-lines token is a count in the portable table. Convert that
    // unit here, after font families are converted, into drawn pixels.
    function convertBodyLines(table, values, lineBox) {
        const walk = (level, node) => {
            let out = node;
            for (const key of Object.keys(level)) {
                let value = node[key];
                if (ThemeLogic.isLeaf(level[key])) {
                    if (level[key].type === "body-lines") {
                        value = Math.ceil(value * lineBox);
                    }
                } else value = walk(level[key], value);
                if (value !== node[key]) {
                    if (out === node) out = Object.assign({}, node);
                    out[key] = value;
                }
            }
            return out === node ? node : Object.freeze(out);
        };
        return walk(table, values);
    }

    // Keeps a group's object across a publication that leaves its values.
    // `held.tree` is the tree `published` last answered, a member of a
    // plain object and no property: the write in `keep` emits nothing, so
    // `published` does not depend on its own value.
    QtObject {
        id: identity

        readonly property var held: ({ tree: null })

        // `tree`, with each subtree that holds the values of its
        // counterpart in the tree last answered replaced by that
        // counterpart. Both trees have the table's shape.
        function keep(tree) {
            const walk = (previous, next) => {
                if (typeof next !== "object") return next;
                let same = true;
                const out = {};
                for (const key of Object.keys(next)) {
                    out[key] = walk(previous[key], next[key]);
                    same = same && out[key] === previous[key];
                }
                return same ? previous : Object.freeze(out);
            };
            held.tree = held.tree === null ? tree : walk(held.tree, tree);
            return held.tree;
        }
    }

    function convert(values, loaded) {
        return convertTree(Tokens.TOKENS, values, source.defaults.values, loaded);
    }

    // A plugin's own look, for a plugin whose manifest declares
    // `appearance`: its table resolved against the active theme's
    // `scheme.mode`, `palette.accent` and `motion.scale` and nothing else
    // of it, converted as the shell's groups are. A binding on it follows
    // the theme and answers the same values for any theme with those three.
    // A refusal is logged and answers null, so the caller fails loudly
    // instead of drawing a look the judge did not accept. A family is the
    // plugin's own and is never substituted.
    function appearance(table, light) {
        const accepted = ThemeLogic.acceptAppearance(table, light, source.values);
        if (!accepted.ok) {
            console.error("appearance: refused: " + ThemeLogic.refusalLine(accepted).replace(/^theme: refused: /, ""));
            return null;
        }
        const converted = convertTree(table, accepted.values, accepted.values, []);
        return convertBodyLines(table, converted, bodyLineBox);
    }

    FontLoader {
        id: mono
        source: Qt.resolvedUrl("../assets/fonts/JetBrainsMono-Variable.ttf")
        onStatusChanged: if (status === FontLoader.Error) console.error("theme: bundled font failed to load: " + source)
    }

    FontLoader {
        id: sans
        source: Qt.resolvedUrl("../assets/fonts/InterVariable.ttf")
        onStatusChanged: if (status === FontLoader.Error) console.error("theme: bundled font failed to load: " + source)
    }

    ThemeSource {
        id: source
        userText: root.appearanceInput
    }
}
