.pragma library

// VGS's own symbols, for a mark Lucide does not draw, such as Jarvis's J
// (docs/decisions/D111-own-symbols-in-lucides-grid.md). Each is drawn as
// Lucide draws its icons, so it reads as one of them: a 24 by 24 unit box,
// a stroke of 2 units with round caps and joins, its ink centred on the
// box. Per name, prefixed `vgs-` so no Lucide name can take it: the stroked
// path and the filled path, as in Lucide.js, which merges these into its
// set (scripts/vendor-lucide writes that trailer).

// REVISIT(D111): a symbol goes once Lucide ships its mark.
var ICONS = {
    // The letter J: a top bar and a stem that hooks left, its ink 10 units
    // wide and 15 tall about the box's centre.
    "vgs-letter-j": ["M10 4.5h7 M17 4.5v10a5 5 0 0 1 -10 0", ""]
};
