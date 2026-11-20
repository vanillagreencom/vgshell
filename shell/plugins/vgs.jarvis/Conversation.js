.pragma library
.import "JarvisProtocol.js" as Protocol

var MAX_ENTRIES = 64;
var MAX_BYTES = 24 * 1024;

function start() { return []; }

function open(entry) { return entry.stage === "partial"; }

function sameSegment(a, b) { return a.gen === b.gen && a.role === b.role && a.session === b.session && a.origin === b.origin; }

function sessionId(row) { return row.session + ":" + row.gen; }

function shortTitle(text) {
    var words = text.trim().replace(/\s+/g, " ");
    var chars = Array.from(words);
    return chars.length > 64 ? chars.slice(0, 63).join("").trim() + "…" : words;
}

function sessions(rows) {
    var result = [];
    var byId = Object.create(null);
    for (var row of rows) {
        // Only an older, unmarked assistant caption needs the fixed
        // Settings preview wording. Marked real turns may say these words.
        if (row.source === undefined && row.role === "assistant" && row.text === "This is how I sound when I answer you.") continue;
        var id = sessionId(row);
        var session = byId[id];
        if (session === undefined) {
            session = { id: id, started: row.started === undefined ? row.at : row.started,
                title: row.priorTitle || "", expired: row.expired === true, turns: [] };
            byId[id] = session;
            result.push(session);
        }
        if (!session.title && row.role === "user") session.title = shortTitle(row.text);
        session.turns.push(row);
    }
    return result.reverse().sort(function (a, b) { return b.started - a.started; });
}

// The next retained turn inherits the original title and the truncation
// marker. The opening time is stamped on each incoming turn by Service.
function dropOldest(rows) {
    var old = rows.shift();
    // A single native utterance can itself exceed the log. Track what
    // expired from that input separately from older turns in its session.
    if (old.role === "user" && old.origin != null) {
        var continuation = rows.find(function (row) { return row.gen === old.gen && row.origin === old.origin; });
        if (continuation !== undefined) continuation.inputTitle = old.inputTitle || shortTitle(old.text);
    }
    var next = rows.find(function (row) { return sessionId(row) === sessionId(old); });
    if (next !== undefined) {
        next.expired = true;
        next.priorTitle = old.priorTitle || (old.role === "user" ? shortTitle(old.text) : "");
    }
}

function trim(rows) {
    while (rows.length > MAX_ENTRIES) dropOldest(rows);
    while (rows.length > 0 && Protocol.bytes(JSON.stringify(rows)) > MAX_BYTES) dropOldest(rows);
    return rows;
}

function update(log, segment) {
    if (segment.source === "preview") return log;
    var rows = log.map(function (row) { return Object.assign({}, row); });
    var next = Object.assign({}, segment);
    // The engine learns that the context is full after the user's caption
    // was published. Its second publication has the same brain operation.
    if (next.origin != null) {
        var input = rows.filter(function (row) { return row.gen === next.gen && row.origin === next.origin; });
        if (input.length && next.source === "context-reset") {
            // A native input can span several bounded captions. Transfer
            // all its retained segments, including any still-open partial.
            for (var row of input) {
                row.session = next.session;
                row.started = next.started;
                delete row.expired;
                delete row.priorTitle;
            }
            if (input[0].inputTitle !== undefined) {
                input[0].expired = true;
                input[0].priorTitle = input[0].inputTitle;
            }
            return trim(rows);
        }
        if (input.length) {
            next.session = input[0].session;
            next.started = input[0].started;
            var partial = input.find(open);
            if (partial !== undefined) {
                Object.assign(partial, next, { at: partial.at });
                return trim(rows);
            }
        }
    }
    var last = rows.length === 0 ? null : rows[rows.length - 1];
    if (last !== null && open(last) && sameSegment(last, next)) {
        // One caption keeps the wall-clock instant at which its first
        // words arrived; partial updates do not move it through History.
        next.at = last.at;
        rows[rows.length - 1] = Object.assign(last, next);
    }
    else rows.push(next);
    return trim(rows);
}
