.pragma library

// The family names in TEXT, fontconfig's list of one name a line.
function listed(text) {
    return String(text).split("\n").filter(function (name) { return name !== ""; });
}

// The families of FAMILIES that NAMES, fontconfig's fixed-width names,
// holds, in the order of FAMILIES.
function fixedWidth(families, names) {
    return families.filter(function (family) { return names.indexOf(family) !== -1; });
}

// The families a select offers: FAMILIES, with SHOWN, the family in effect,
// first when FAMILIES does not hold it, so the select reads it.
function offers(families, shown) {
    return typeof shown !== "string" || families.indexOf(shown) !== -1 ? families : [shown].concat(families);
}
