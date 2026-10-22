.pragma library

// Where a drawn line of a value may break. Qt's Text.Wrap breaks after a
// hyphen as well as at a space, so a command read `workspace-` / `write`
// and `--` / `sandbox` across two lines of a select (VGS-1987 sheet run A,
// Qt 6.12.0), where a reader takes the break for a space between words.

// TEXT broken at its spaces alone into lines no wider than WIDTH, joined by
// line feeds: each line takes the next word while it fits. It adds no
// character, so every line keeps the interface font's own height: a word
// joiner after each hyphen, which Inter Variable does not map, was laid out
// in a fallback font whose taller ascent dropped each line holding one by
// 1.5 px (VGS-1987 review). METRICS is a TextMetrics in the label's font,
// whose advanceWidth is the width the label lays a line out at, so the
// label's own wrap breaks no line it is handed. A FontMetrics measures at
// another rendering: under full hinting it read 400 px for a line the
// label laid out at 405 (VGS-1987 fix round 1, qml-unit, Qt 6.12.0, Inter
// Variable). The function writes METRICS.text, so a caller runs it from a
// handler; a binding would read its own writes as a loop. A word wider than
// WIDTH takes a line of its own, which the label's wrap breaks. With no
// width yet the text comes back whole. Only drawn text takes it; an
// accessible name or a stored value keeps the plain text.
function atSpaces(text, width, metrics) {
    if (!(width > 0)) return text;
    const lines = [];
    let line = null;
    for (const word of text.split(" ")) {
        const longer = line === null ? word : line + " " + word;
        metrics.text = longer;
        if (line === null || metrics.advanceWidth <= width) {
            line = longer;
        } else {
            lines.push(line);
            line = word;
        }
    }
    lines.push(line);
    return lines.join("\n");
}
