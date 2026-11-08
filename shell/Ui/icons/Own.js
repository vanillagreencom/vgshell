.pragma library

// VGS's own symbols, for a mark Lucide does not draw, such as Jarvis's J
// (docs/decisions/D111-own-symbols-in-lucides-grid.md). Each is drawn as
// Lucide draws its icons, so it reads as one of them: a 24 by 24 unit box,
// a stroke of 2 units with round caps and joins, its ink centred on the
// box. Per name, prefixed `vgs-` so no Lucide name can take it: the stroked
// path and the filled path, as in Lucide.js, which merges these into its
// set (scripts/vendor-lucide writes that trailer).

// REVISIT(D111): a symbol goes once Lucide ships its mark.
var LETTER_J = ["M10 4.5h7 M17 4.5v10a5 5 0 0 1 -10 0", ""];
// Lucide's `star` at Lucide.VERSION: Lucide draws no filled star.
var STAR = "M11.525 2.295a.53 .53 0 0 1 .95 0l2.31 4.679a2.123 2.123 0 0 0 1.595 1.16l5.166.756a.53 .53 0 0 1 .294 .904l-3.736 3.638a2.123 2.123 0 0 0 -.611 1.878l.882 5.14a.53 .53 0 0 1 -.771 .56l-4.618-2.428a2.122 2.122 0 0 0 -1.973 0L6.396 21.01a.53 .53 0 0 1 -.77 -.56l.881-5.139a2.122 2.122 0 0 0 -.611 -1.879L2.16 9.795a.53 .53 0 0 1 .294 -.906l5.165-.755a2.122 2.122 0 0 0 1.597 -1.16z";
var ICONS = {
    // A star filled in its own colour, as a checked star toggle draws.
    "vgs-star-filled": [STAR, STAR],
    // The letter J: a top bar and a stem that hooks left, its ink 10 units
    // wide and 15 tall about the box's centre.
    "vgs-letter-j": LETTER_J,
    // Icon owns drawing this held-state variant through the same paths.
    "vgs-letter-j-hidden": LETTER_J
};
var VARIANTS = { "vgs-letter-j-hidden": "lower-disabled" };
