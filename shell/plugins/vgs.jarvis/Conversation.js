.pragma library
.import "JarvisProtocol.js" as Protocol

var MAX_ENTRIES = 64;
var MAX_BYTES = 48 * 1024;

function start() { return []; }

function entry(segment) {
    return { gen: segment.gen, role: segment.role, text: segment.text, stage: segment.stage };
}

function open(entry) { return entry.stage === "partial"; }

function sameSegment(a, b) { return a.gen === b.gen && a.role === b.role; }

function trim(rows) {
    while (rows.length > MAX_ENTRIES) rows.shift();
    while (rows.length > 0 && Protocol.bytes(JSON.stringify(rows)) > MAX_BYTES) rows.shift();
    return rows;
}

function update(log, segment) {
    var rows = Array.isArray(log) ? log.map(function (row) { return entry(row); }) : [];
    var next = entry(segment);
    var last = rows.length === 0 ? null : rows[rows.length - 1];
    if (last !== null && open(last) && sameSegment(last, next)) rows[rows.length - 1] = next;
    else rows.push(next);
    return trim(rows);
}
