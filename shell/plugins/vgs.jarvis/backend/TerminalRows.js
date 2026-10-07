// The setup terminal's choice lines, shared by keys.js and accounts.js:
// LABEL<TAB>VALUE for `gum choose --label-delimiter=$'\t'`, which prints
// VALUE alone, so an id goes back to its judge and never reaches the
// screen. Each label fits a terminal width columns wide, cut with an
// ellipsis, after gum's two-column "> " cursor. Labels come from judges that
// refuse control characters, so none holds a tab. Width counts code points,
// so a wide character can overflow.
"use strict";
const { PROVIDERS, modelKeyProvider } = require("../AccountProviders.js");

const MIN_WIDTH = 20;
const MAX_WIDTH = 1000;
const CHOICE_CURSOR = 2;

/** The terminal width argument, or null when it is no integer from MIN_WIDTH to MAX_WIDTH. */
function parseWidth(text) {
    if (typeof text !== "string" || !/^[0-9]{1,4}$/.test(text)) return null;
    const value = Number(text);
    return value >= MIN_WIDTH && value <= MAX_WIDTH ? value : null;
}

function fitText(text, width) {
    const points = Array.from(text);
    return points.length <= width ? text : points.slice(0, width - 1).join("") + "…";
}

function choiceLine(label, value, width) {
    return fitText(label, width - CHOICE_CURSOR) + "\t" + value;
}

// Add directory offers the sign-in programs, "cli"; Add key and Use keyring
// item the AI model key providers, "key", Add key with the page that
// creates a key.
function providerChoices(kind, width, pages) {
    const rows = PROVIDERS.filter(row => {
        if (kind === "cli") return row.kind === "cli";
        if (kind === "key") return modelKeyProvider(row);
        throw new Error("jarvis-providers: kind=" + kind);
    });
    return rows.map(row => choiceLine(pages ? row.label + ": get a key at " + row.keyPage.replace(/^https:\/\//, "")
        : row.label, row.id, width));
}

module.exports = { parseWidth, fitText, choiceLine, providerChoices };
