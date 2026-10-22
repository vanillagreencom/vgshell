.pragma library

// Where a drawn line of a value may break. Qt's Text.Wrap breaks after a
// hyphen as well as at a space, so a command read `workspace-` / `write`
// and `--` / `sandbox` across two lines of a select (VGS-1987 sheet run A,
// Qt 6.12.0), where a reader takes the break for a space between words.

// TEXT with a word joiner (U+2060) after each hyphen, so its lines break at
// spaces alone. The joiner draws nothing in Inter Variable (VGS-1987 sheet
// run A2). The no-break hyphen U+2011 would not serve: Inter draws two of
// them in a row as one long dash, so `--sandbox` read as a dash and a word
// (run A2nbh). Only drawn text takes it; an accessible name or a stored
// value keeps the plain text.
function atSpaces(text) {
    return text.replace(/-/g, "-\u2060");
}
