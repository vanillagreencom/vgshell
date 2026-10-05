.pragma library

// Callers round seconds before formatting. Ages use one part; reset times
// omit seconds when their source has minute precision.
function format(seconds, maximumParts) {
    var units = [[86400, "d"], [3600, "h"], [60, "m"], [1, "s"]];
    var first = 0;
    while (first < units.length - 1 && seconds < units[first][0]) first++;
    var parts = [];
    var count = maximumParts === undefined ? 2 : maximumParts;
    for (var i = first; i < units.length && parts.length < count; i++) {
        parts.push(Math.floor(seconds / units[i][0]) + units[i][1]);
        seconds %= units[i][0];
    }
    return parts.join(" ");
}
