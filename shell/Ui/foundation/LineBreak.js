.pragma library

// Where a drawn line of a value may break. Qt's Text.Wrap breaks after a
// hyphen as well as at a space, so a command read `workspace-` / `write`
// and `--` / `sandbox` across two lines of a select (VGS-1987 sheet run A,
// Qt 6.12.0), where a reader takes the break for a space between words.

// TEXT broken at its spaces alone into lines no wider than WIDTH, joined by
// line feeds, the lines `rows` gives its words. It adds no character, so
// every line keeps the interface font's own height: a word joiner after
// each hyphen, which Inter Variable does not map, was laid out in a
// fallback font whose taller ascent dropped each line holding one by
// 1.5 px (VGS-1987 review). With no width yet the text comes back whole.
// Only drawn text takes it; an accessible name or a stored value keeps the
// plain text.
function atSpaces(text, width, metrics) {
    if (!(width > 0)) return text;
    const words = text.split(" ");
    const lines = rows(words, width, metrics).map(row => words.slice(row.from, row.to).join(" "));
    return lines.join("\n");
}

// WORDS, a list of words, broken into rows no wider than WIDTH, each
// { from, to }, the indices of its first word and of the word after its
// last: each row takes the next word while it fits. METRICS is a
// TextMetrics in the label's font, whose advanceWidth is the width the
// label lays a line out at, so the label's own wrap breaks no row it is
// handed. A FontMetrics measures at another rendering: under full hinting
// it read 400 px for a line the label laid out at 405 (VGS-1987 fix round
// 1, qml-unit, Qt 6.12.0, Inter Variable). The function writes
// METRICS.text, so a caller runs it from a handler; a binding would read
// its own writes as a loop. A word wider than WIDTH takes a row of its
// own, which the label's wrap breaks. No words make no rows.
function rows(words, width, metrics) {
    const out = [];
    let line = null;
    let first = 0;
    for (let i = 0; i < words.length; i++) {
        const longer = line === null ? words[i] : line + " " + words[i];
        metrics.text = longer;
        if (line === null || metrics.advanceWidth <= width) {
            line = longer;
        } else {
            out.push({ from: first, to: i });
            line = words[i];
            first = i;
        }
    }
    if (line !== null) out.push({ from: first, to: words.length });
    return out;
}
