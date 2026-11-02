.pragma library

function matches(query, values) {
    var wanted = String(query).trim().toLocaleLowerCase();
    return wanted === "" || values.some(function (value) { return String(value).toLocaleLowerCase().indexOf(wanted) !== -1; });
}

// Conversation owns these wall-clock instants and session identities in
// memory. Filtering never invents a date or writes a transcript store.
function conversations(rows, query) {
    var groups = [];
    for (var row of rows) {
        if (!matches(query, [row.text, row.role === "user" ? "You" : "Jarvis"])) continue;
        var day = new Date(row.at);
        var key = row.session + ":" + day.getFullYear() + ":" + day.getMonth() + ":" + day.getDate();
        var group = groups.find(function (value) { return value.id === key; });
        if (group === undefined) {
            group = { id: key, at: row.at, startedAt: row.startedAt, rows: [] };
            groups.push(group);
        }
        group.rows.push(row);
        group.at = Math.max(group.at, row.at);
    }
    return groups.sort(function (a, b) { return b.at - a.at; });
}

function tasks(rows, query) {
    return rows.filter(function (row) { return matches(query, [row.goal, row.agent, row.state]); });
}

function problem(row) {
    var voice = {
        "input-silent": "The microphone sent only silence.",
        "unheard": "The voice service heard no words.",
        "key-refused": "The voice service refused the saved key.",
        "voice-stopped": "The voice service stopped before finishing."
    };
    if (row.cause !== null) return { title: "Voice stopped.", body: voice[row.cause], action: "Voice settings", settings: true };
    var operation = row.tool === "files.delete" ? "Deleting a file" : row.tool === "files.write" ? "Writing a file"
        : row.tool === "release" ? "Sending content" : "The action";
    var outcome = row.decision === "refuse" ? " was refused." : row.decision === "withhold" ? " was withheld."
        : row.outcome === "failed" ? " failed." : " has an unknown result.";
    var causes = {
        expired: "The approval expired before the action ran.",
        "no-hold": "There was no request waiting for approval.",
        identity: "The request changed before approval.",
        source: "This source could not authorize the action.",
        early: "The request was answered before it was shown.",
        "voice-physical": "This approval needs your keyboard or pointer.",
        "voice-timing": "The spoken answer arrived outside the approval time."
    };
    return { title: operation + outcome,
        body: row.refusal === null ? "Jarvis could not confirm the result. Review it before trying again." : causes[row.refusal],
        action: "Ask Jarvis again", settings: false };
}

function problems(rows, query) {
    return rows.map(function (row) {
        var shown = problem(row);
        return { at: Date.parse(row.time), title: shown.title, body: shown.body, action: shown.action, settings: shown.settings };
    }).filter(function (row) { return matches(query, [row.title, row.body]); });
}
