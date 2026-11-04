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

// Audit publishes operation/effect categories, never their argument values.
// These labels preserve what failed without inventing a target or filename.
function operation(row) {
    var labels = {
        "help": "Reading help", "memory.search": "Searching memory notes", "memory.read": "Reading memory notes",
        "memory.propose": "Adding a memory note", "memory.replace": "Replacing a memory note",
        "fleet.request": "Sending a fleet request", "fleet.forward": "Forwarding a request to your main Jarvis",
        "windows.list": "Listing windows", "windows.focus": "Focusing a window",
        "windows.reveal": "Revealing a window", "windows.move": "Moving a window", "windows.resize": "Resizing a window",
        "windows.close": "Closing a window", "windows.fullscreen": "Changing a window's full-screen state",
        "windows.float": "Changing a window's floating state", "windows.workspace": "Moving a window to a workspace",
        "workspaces.list": "Listing workspaces", "workspaces.focus": "Showing a workspace",
        "workspaces.special": "Toggling a special workspace", "windows.monitor": "Focusing a monitor",
        "apps.list": "Listing applications", "apps.launch": "Launching an application", "apps.terminal": "Opening a terminal",
        "apps.open": "Opening a file or folder", "apps.url": "Opening a web address",
        "input.text": "Typing text", "input.key": "Pressing a key", "input.click": "Clicking", "input.scroll": "Scrolling",
        "clipboard.read": "Reading the clipboard", "clipboard.write": "Writing to the clipboard",
        "media.play": "Playing media", "media.pause": "Pausing media", "media.next": "Playing the next media item",
        "media.volumeStep": "Changing the volume", "media.volume": "Setting the volume", "media.mute": "Changing mute",
        "media.brightness": "Changing brightness", "notify.notification": "Showing a notification",
        "files.list": "Listing files", "files.read": "Reading a file", "files.search": "Searching files",
        "files.write": "Writing a file", "files.move": "Moving a file", "files.delete": "Deleting a file",
        "vision.screen": "Reading the screen", "vision.monitor": "Reading a monitor", "vision.window": "Reading a window",
        "vision.region": "Reading a screen region", "vision.area": "Reading a selected screen area",
        "task.start": "Starting a coding task", "harness.files": "Changing files through the brain's program",
        "harness.command": "Running a command through the brain's program", "release": "Sending content"
    };
    if (row.tool === "browser") return row.effect === "read" ? "Reading a web page"
        : row.effect === "input" ? "Interacting with a web page" : row.effect === "external" ? "Submitting a web form" : "Using the browser";
    if (row.tool === "shell.argv") return row.effect === "read" ? "Reading command output"
        : row.effect === "external" ? "Running a command with network access" : "Running a command";
    if (row.tool === "shell.line") return row.effect === "external" ? "Running shell text with network access" : "Running shell text";
    return labels[row.tool] === undefined ? "The action" : labels[row.tool];
}

function problem(row) {
    var voice = {
        "input-silent": "The microphone sent only silence.",
        "unheard": "The voice service heard no words.",
        "key-refused": "The voice service refused the saved key.",
        "voice-stopped": "The voice service stopped before finishing."
    };
    if (row.cause !== null) return { title: "Voice stopped.", body: voice[row.cause], action: "Voice settings", settings: true };
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
    // The record keeps a cause only for a refused or withheld release and a
    // failed voice stream (Audit.js); every other problem says that none was
    // recorded and what is safe to do next.
    var body = row.refusal !== null ? causes[row.refusal]
        : row.decision === "refuse" ? "Jarvis did not run this action and recorded no reason."
        : row.decision === "withhold" ? "Jarvis did not send the content and recorded no reason."
        : row.outcome === "failed" ? "The action started but did not finish. Jarvis recorded no cause."
        : "Jarvis lost the result, so the action may have run. Check the result before you ask again.";
    return { title: operation(row) + outcome, body: body, action: "Ask Jarvis again", settings: false };
}

function problems(rows, query) {
    return rows.map(function (row) {
        var shown = problem(row);
        return { at: Date.parse(row.time), title: shown.title, body: shown.body, action: shown.action, settings: shown.settings };
    }).filter(function (row) { return matches(query, [row.title, row.body]); });
}
