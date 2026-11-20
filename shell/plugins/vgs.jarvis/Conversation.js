.pragma library
.import "JarvisProtocol.js" as Protocol

var MAX_ENTRIES = 64;
var MAX_BYTES = 24 * 1024;

function start() { return []; }

function entry(segment) {
    var row = { gen: segment.gen, role: segment.role, text: segment.text, stage: segment.stage,
        at: segment.at, session: segment.session };
    if (segment.origin !== undefined) row.origin = segment.origin;
    return row;
}

function open(entry) { return entry.stage === "partial"; }

function sameSegment(a, b) { return a.gen === b.gen && a.role === b.role && a.origin === b.origin; }

function trim(rows) {
    while (rows.length > MAX_ENTRIES) rows.shift();
    while (rows.length > 0 && Protocol.bytes(JSON.stringify(rows)) > MAX_BYTES) rows.shift();
    return rows;
}

function update(log, segment) {
    var rows = Array.isArray(log) ? log.map(function (row) { return entry(row); }) : [];
    var next = entry(segment);
    var index = rows.length - 1;
    if (next.origin !== undefined)
        index = rows.findIndex(function (row) { return sameSegment(row, next) && row.session === next.session && open(row); });
    var last = index < 0 ? null : rows[index];
    if (last !== null && open(last) && sameSegment(last, next)) {
        // A caption keeps the time at which its first words arrived.
        next.at = last.at;
        if (next.text === "") rows.splice(index, 1);
        else rows[index] = next;
    } else if (next.text !== "") rows.push(next);
    return trim(rows);
}
