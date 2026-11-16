.pragma library

// A list of names as a sentence reads it: "a", "a and b", "a, b and c".
function listed(names) {
    if (names.length <= 1) return names.join("");
    return names.slice(0, -1).join(", ") + " and " + names[names.length - 1];
}
