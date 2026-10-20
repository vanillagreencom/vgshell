.pragma library

// The least inset from each side that keeps the corners of rectangular
// content at least `step` inside the drawn rounded corner, when the
// content's top and bottom edges stand `top` in from the container's. The
// drawn corner is `radius` clamped to half the smaller side; a square
// corner keeps `pad`. Content within one step of the edge clears the whole
// corner instead, since no inset keeps its corner inside the curve.
function clearing(pad, radius, width, height, step, top) {
    var corner = Math.min(radius, width / 2, height / 2);
    if (corner <= 0) return pad;
    var dy = Math.max(0, corner - top);
    var reach = corner - step;
    if (dy > reach) return Math.max(pad, corner + step);
    return Math.max(pad, corner - Math.sqrt(reach * reach - dy * dy));
}

// The side padding of a one-line control whose content, `contentHeight`
// tall, centres in its `height`: the least whole inset from `pad` that
// keeps the content's corners `step` inside the drawn corner, which the
// control's height bounds, since a one-line control is wider than tall.
function controlPadding(pad, radius, height, contentHeight, step) {
    return Math.ceil(clearing(pad, radius, 2 * height, height, step, (height - contentHeight) / 2));
}

// The top and bottom inset of a list of rows whose fills reach the side of a
// container `border` wide with drawn corner `radius`, when a row's drawn
// corner is `rowRadius`: the border alone while the row's corner is at least
// as round as the container's inner corner, so the first and last rows'
// fills meet the border and their corners stay inside its curve. Otherwise
// the list starts lower by the difference, where the first row's corner
// centre meets the container's, so its corner still stays inside the curve.
// This places an unscrolled list; a row a scroll cuts at an edge is the
// container's own mask to keep inside the curve.
function listInset(radius, border, rowRadius) {
    return border + Math.max(0, radius - border - rowRadius);
}

// How far under a baseline a text's underline starts, from `depth`, the
// descender letters' ink under it (DescenderInk), and the screen's device
// pixel ratio: the fewest whole device pixels that keep one clear device
// row between that ink and the line wherever the baseline falls inside a
// device pixel. The line fills the device rows whose centres it covers,
// so with the baseline at B and its top t under it, both in device
// pixels, its first row is ceil(B + t - 0.5); the ink ends in row
// ceil(B + depth) - 1; one clear row between them for every B needs
// t >= depth + 1.5. A row the ink reaches by less than an eighth of a
// device pixel reads as clear, `SEEN_INK`: the depth is read to a pixel of
// a large size, rounded outward (DescenderInk): Inter Variable's g, j, p,
// q and y at 15 px read 3.25 px at 64 times the size and, at 256 times,
// past the 3.25 that 8 device px at 2x allow (scripts/qml-unit.sh,
// 2026-10-19). In Inter Variable the line starts 5 px under the baseline
// at 1x and 8 device px at 2x, at 13 and at 15 px. Jarvis decision
// 1792451829-3591639-28142. Qt Quick draws a link's or `<u>`'s underline
// at the font's underline position, which a descender meets (Qt 6.11
// qquicktextnodeengine.cpp, addTextDecorations).
var SEEN_INK = 0.125;
function underlineTop(depth, ratio) {
    return Math.ceil(depth * ratio + 1.5 - SEEN_INK) / ratio;
}

// An underline's thickness: the font's own line width, as Qt draws one,
// kept to whole pixels.
function underlineWidth(lineWidth) {
    return Math.max(1, Math.round(lineWidth));
}
