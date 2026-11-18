.pragma library

// Qt's Text.Wrap can break after a hyphen, making a command look as if it
// contains a space. Values break at spaces instead.

// TEXT broken at its spaces alone into lines no wider than WIDTH, joined by
// line feeds, the lines `rows` gives its words. It adds no character, so
// every line keeps the interface font's own height: a word joiner that the
// interface font lacks can select a fallback with a taller line box.
// With no width yet the text comes back whole.
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
// handed. FontMetrics can measure a different width under hinting.
// The function writes
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
