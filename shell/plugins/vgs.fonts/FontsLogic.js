.pragma library

// The code points a terminal font draws: printable ASCII, the letters,
// digits and punctuation of a shell's prompt. An icon font maps letters for
// its ligatures and an emoji font maps digits, and neither maps all of these.
var TEXT_FIRST = 0x20;
var TEXT_LAST = 0x7e;
var FIXED_WIDTH = "100";

// Whether CHARSET, fontconfig's charset text of ascending `hex` and
// `hex-hex` ranges a space apart, holds every code point FIRST..LAST. The
// scan stops past LAST: the charset of a large font runs to kilobytes.
function covers(charset, first, last) {
    var range = /([0-9a-f]+)(?:-([0-9a-f]+))?/g;
    var next = first;
    var found;
    while ((found = range.exec(charset)) !== null) {
        var low = parseInt(found[1], 16);
        if (low > next) return false;
        var high = found[2] === undefined ? low : parseInt(found[2], 16);
        if (high >= next) next = high + 1;
        if (next > last) return true;
    }
    return false;
}

// The fonts in TEXT, fontconfig's list of one font a line: its spacing, its
// charset and then each of its family names, a tab before each. A font's
// first name is its family; the rest are its other names, such as a style
// name. `terminal` is a fixed-width font that draws printable ASCII.
function listed(text) {
    return String(text).split("\n").filter(function (line) { return line !== ""; }).map(function (line) {
        var fields = line.split("\t");
        return {
            names: fields.slice(2),
            terminal: fields[0] === FIXED_WIDTH && covers(fields[1] || "", TEXT_FIRST, TEXT_LAST)
        };
    });
}

// The families of QT_FAMILIES, Qt's list in its order, less each name
// fontconfig lists for a font in FONTS that no font has as its first name:
// a style name. A family fontconfig does not list, such as one the shell
// loads itself, stays.
function families(qtFamilies, fonts) {
    var first = Object.create(null);
    var other = Object.create(null);
    fonts.forEach(function (font) {
        font.names.forEach(function (name, at) { (at === 0 ? first : other)[name] = true; });
    });
    return qtFamilies.filter(function (family) { return first[family] === true || other[family] !== true; });
}

// The families of QT_FAMILIES, in Qt's order, that are the first name of a
// terminal font in FONTS.
function terminal(qtFamilies, fonts) {
    var first = Object.create(null);
    fonts.forEach(function (font) { if (font.terminal && font.names.length > 0) first[font.names[0]] = true; });
    return qtFamilies.filter(function (family) { return first[family] === true; });
}

// The families a select offers: FAMILIES, with SHOWN, the family in effect,
// first when FAMILIES does not hold it, so the select reads it.
function offers(families, shown) {
    return typeof shown !== "string" || families.indexOf(shown) !== -1 ? families : [shown].concat(families);
}
