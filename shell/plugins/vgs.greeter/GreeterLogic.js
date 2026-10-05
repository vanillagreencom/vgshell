.pragma library

// Pure decisions for vgs.greeter: the accounts the login screen lists, the
// session entries it reads and how it starts one, which one it chooses
// first, what it remembers, and the status its service publishes. QML owns
// the processes, the files, greetd and the password; no password passes
// through here.

// The directory bin/vgshell-system's greeter step makes for the theme copy,
// root's, with a `vgs` directory the caller owns: the service copies into
// that `vgs` directory, and the greeter's XDG_CONFIG_HOME names this one,
// so Paths.configDir reads the copy. scripts/test-vgshell-system.sh reads it
// against the step's own path.
var THEME_DIR = "/var/lib/vgshell/greeter/theme";
// The copied background image's name in that `vgs` directory.
var BACKGROUND = "background";

// The accounts a person logs in to: uids 1000 to 59999, the range
// login.defs gives people, and a shell that allows a login.
var UID_MIN = 1000;
var UID_MAX = 59999;
var NO_LOGIN_SHELLS = ["nologin", "false"];

// The session directories under each XDG_DATA_DIRS entry, and the session
// type each one holds.
var SESSION_KINDS = { "wayland-sessions": "wayland", "xsessions": "x11" };
var DEFAULT_DATA_DIRS = "/usr/local/share:/usr/share";

// Field codes an Exec value may carry (Desktop Entry Specification 1.5,
// "The Exec key"); a login session takes no file or URL, so each is
// removed and `%%` reads as `%`.
var FIELD_CODES = "fFuUdDnNickvm";

// Remembered users: the file keeps at most this many, the listed accounts
// first, so it cannot grow with data another program supplies.
var MEMORY_USERS_MAX = 64;

function baseName(path) {
    var text = String(path);
    var slash = text.lastIndexOf("/");
    return slash === -1 ? text : text.slice(slash + 1);
}

// The accounts in getent passwd's TEXT a person can log in to, in the
// order getent lists them: [{ name, label }], `label` the account's full
// name from the comment field, or its name when that is empty.
function users(text) {
    var out = [];
    var lines = String(text).split("\n");
    for (var i = 0; i < lines.length; i++) {
        var fields = lines[i].split(":");
        if (fields.length !== 7 || fields[0] === "") continue;
        if (!/^[0-9]+$/.test(fields[2])) continue;
        var uid = Number(fields[2]);
        if (uid < UID_MIN || uid > UID_MAX) continue;
        if (NO_LOGIN_SHELLS.indexOf(baseName(fields[6])) !== -1) continue;
        var full = fields[4].split(",")[0].trim();
        out.push({ name: fields[0], label: full === "" ? fields[0] : full });
    }
    return out;
}

// XDG_DATA_DIRS VALUE as the list of absolute directories to read, in
// order; the specification's default when it names none.
function dataDirs(value) {
    var text = value === undefined || value === null || String(value) === "" ? DEFAULT_DATA_DIRS : String(value);
    var out = [];
    var parts = text.split(":");
    for (var i = 0; i < parts.length; i++) {
        var dir = parts[i].replace(/\/+$/, "");
        if (dir.charAt(0) === "/" && out.indexOf(dir) === -1) out.push(dir);
    }
    return out;
}

// bin/sessions' `list` output as [{ kind, path, text }]: a line
// `@ <kind> <path>` opens an entry and each `|<line>` adds one line of its
// file. Any other line is a defect of the helper and throws.
function listing(output) {
    var out = [];
    var lines = String(output).split("\n");
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i];
        if (line === "" && i === lines.length - 1) break;
        var head = /^@ (wayland-sessions|xsessions) (\/.+)$/.exec(line);
        if (head !== null) {
            out.push({ kind: head[1], path: head[2], lines: [] });
            continue;
        }
        if (line.charAt(0) === "|" && out.length > 0) {
            out[out.length - 1].lines.push(line.slice(1));
            continue;
        }
        throw new Error("greeter: sessions line " + JSON.stringify(line) + " is not the helper's");
    }
    return out.map(function (entry) { return { kind: entry.kind, path: entry.path, text: entry.lines.join("\n") }; });
}

// A string value's escapes (`\s`, `\n`, `\t`, `\r`, `\\`); null for any
// other escape.
function unescapeValue(value) {
    var out = "";
    for (var i = 0; i < value.length; i++) {
        var c = value.charAt(i);
        if (c !== "\\") { out += c; continue; }
        var n = value.charAt(i + 1);
        var map = { "s": " ", "n": "\n", "t": "\t", "r": "\r", "\\": "\\" };
        if (!Object.prototype.hasOwnProperty.call(map, n)) return null;
        out += map[n];
        i++;
    }
    return out;
}

// A list value, `;`-separated with `\;` for a literal semicolon.
function listValue(value) {
    var out = [];
    var item = "";
    for (var i = 0; i < value.length; i++) {
        var c = value.charAt(i);
        if (c === "\\" && value.charAt(i + 1) === ";") { item += ";"; i++; continue; }
        if (c === ";") { out.push(item); item = ""; continue; }
        item += c;
    }
    if (item !== "") out.push(item);
    return out.filter(function (x) { return x !== ""; });
}

// The `[Desktop Entry]` group of a desktop file's TEXT as { ok, keys } or
// { ok: false, reason }: keys without a locale, the first of each, every
// other group and every comment ignored.
function desktopGroup(text) {
    var lines = String(text).split("\n");
    var group = null;
    var seen = false;
    var keys = {};
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].replace(/\r$/, "");
        if (/^\s*(#|$)/.test(line)) continue;
        var header = /^\[([^\[\]]+)\]\s*$/.exec(line);
        if (header !== null) {
            group = header[1];
            if (group === "Desktop Entry") {
                if (seen) return { ok: false, reason: "group-twice" };
                seen = true;
            }
            continue;
        }
        if (group === null) return { ok: false, reason: "line-before-group" };
        if (group !== "Desktop Entry") continue;
        var pair = /^([A-Za-z0-9-]+)(\[[^\]]+\])?\s*=\s*(.*)$/.exec(line);
        if (pair === null) return { ok: false, reason: "malformed-line" };
        if (pair[2] !== undefined && pair[2] !== "") continue;
        if (!Object.prototype.hasOwnProperty.call(keys, pair[1])) keys[pair[1]] = pair[3];
    }
    if (!seen) return { ok: false, reason: "no-desktop-entry" };
    return { ok: true, keys: keys };
}

// An Exec VALUE, its string escapes already read, as { ok, argv } or
// { ok: false, reason }: split at spaces outside double quotes, where `\"`,
// `` \` ``, `\$` and `\\` stand for the character, never at every space;
// an unquoted argument that is one field code is dropped, `%%` reads as
// `%`, and every other field code is removed.
function execArgv(value) {
    var args = [];
    var current = "";
    var started = false;
    var quoted = false;
    var wasQuoted = false;
    for (var i = 0; i < value.length; i++) {
        var c = value.charAt(i);
        if (quoted) {
            if (c === "\"") { quoted = false; continue; }
            if (c === "\\") {
                var n = value.charAt(i + 1);
                if ("\"`$\\".indexOf(n) === -1 || n === "") return { ok: false, reason: "exec-escape" };
                current += n;
                i++;
                continue;
            }
            current += c;
            continue;
        }
        if (c === " ") {
            if (started) args.push({ text: current, quoted: wasQuoted });
            current = "";
            started = false;
            wasQuoted = false;
            continue;
        }
        if (c === "\"") {
            quoted = true;
            started = true;
            wasQuoted = true;
            continue;
        }
        started = true;
        current += c;
    }
    if (quoted) return { ok: false, reason: "exec-quote" };
    if (started) args.push({ text: current, quoted: wasQuoted });
    var argv = [];
    for (var j = 0; j < args.length; j++) {
        var arg = args[j];
        if (!arg.quoted && arg.text.length === 2 && arg.text.charAt(0) === "%" && FIELD_CODES.indexOf(arg.text.charAt(1)) !== -1) continue;
        var out = "";
        for (var k = 0; k < arg.text.length; k++) {
            var ch = arg.text.charAt(k);
            if (ch !== "%") { out += ch; continue; }
            var code = arg.text.charAt(k + 1);
            if (code === "%") out += "%";
            else if (code === "" || FIELD_CODES.indexOf(code) === -1) return { ok: false, reason: "exec-field-code" };
            k++;
        }
        argv.push(out);
    }
    if (argv.length === 0) return { ok: false, reason: "exec-empty" };
    return { ok: true, argv: argv };
}

function isTrue(keys, key) {
    return Object.prototype.hasOwnProperty.call(keys, key) && keys[key] === "true";
}

// One session file's entry: { ok, entry } with entry { id, kind, type,
// name, argv, tryExec, desktopNames, shown }, `shown` false for a
// `NoDisplay` entry; { ok: true, entry: null, hidden: true } for a
// `Hidden` one, which deletes the id; { ok: false, reason } otherwise.
function sessionEntry(kind, path, text) {
    if (!Object.prototype.hasOwnProperty.call(SESSION_KINDS, kind)) throw new Error("greeter: session kind " + JSON.stringify(kind) + " is not one of " + Object.keys(SESSION_KINDS).join(", "));
    var file = baseName(path);
    if (!/\.desktop$/.test(file)) return { ok: false, reason: "not-desktop" };
    var group = desktopGroup(text);
    if (!group.ok) return group;
    var keys = group.keys;
    var id = kind + "/" + file;
    if (isTrue(keys, "Hidden")) return { ok: true, entry: null, hidden: true, id: id };
    var name = keys.Name === undefined ? null : unescapeValue(keys.Name);
    if (name === null || name.trim() === "") return { ok: false, reason: "name-missing" };
    var exec = keys.Exec === undefined ? null : unescapeValue(keys.Exec);
    if (exec === null || exec.trim() === "") return { ok: false, reason: "exec-missing" };
    var argv = execArgv(exec);
    if (!argv.ok) return argv;
    var tryExec = keys.TryExec === undefined ? "" : unescapeValue(keys.TryExec);
    if (tryExec === null || /[\x00-\x1f\x7f]/.test(tryExec)) return { ok: false, reason: "tryexec-malformed" };
    var names = keys.DesktopNames === undefined ? [] : listValue(keys.DesktopNames);
    return {
        ok: true,
        entry: {
            id: id, kind: kind, type: SESSION_KINDS[kind], name: name.trim(), argv: argv.argv,
            tryExec: tryExec, desktopNames: names, shown: !isTrue(keys, "NoDisplay")
        }
    };
}

// FILES, the `listing` result, each read once by sessionEntry:
// [{ path, read }].
function readEntries(files) {
    return files.map(function (f) { return { path: f.path, read: sessionEntry(f.kind, f.path, f.text) }; });
}

// The commands bin/sessions `which` must look up for ENTRIES, the
// readEntries result: every TryExec, and startx while an X entry is read.
function commandsToCheck(entries) {
    var out = [];
    for (var i = 0; i < entries.length; i++) {
        var e = entries[i].read.ok ? entries[i].read.entry : null;
        if (e === null) continue;
        if (e.tryExec !== "" && out.indexOf(e.tryExec) === -1) out.push(e.tryExec);
        if (e.type === "x11" && out.indexOf("startx") === -1) out.push("startx");
    }
    return out;
}

// bin/sessions' `which` output, one `found <name>` or `missing <name>`
// line per name, as { name: bool }.
function foundCommands(output) {
    var found = {};
    var lines = String(output).split("\n");
    for (var i = 0; i < lines.length; i++) {
        if (lines[i] === "" && i === lines.length - 1) break;
        var m = /^(found|missing) (.+)$/.exec(lines[i]);
        if (m === null) throw new Error("greeter: which line " + JSON.stringify(lines[i]) + " is not the helper's");
        found[m[2]] = m[1] === "found";
    }
    return found;
}

// The sessions the picker lists, from ENTRIES, the readEntries result in
// XDG_DATA_DIRS order, and FOUND, the `foundCommands` answer: { sessions,
// refused }. An earlier directory's file of the same name and kind wins,
// a Hidden one deleting the id; a NoDisplay entry and one whose TryExec is
// not found are left out; an X entry reads unavailable while startx is
// not found. Each session is { id, type, name, argv, desktopNames,
// available }. `refused` lists { path, reason } for every file that is no
// valid entry.
function sessions(entries, found) {
    var claimed = {};
    var out = [];
    var refused = [];
    for (var i = 0; i < entries.length; i++) {
        var read = entries[i].read;
        if (!read.ok) {
            refused.push({ path: entries[i].path, reason: read.reason });
            continue;
        }
        var id = read.hidden ? read.id : read.entry.id;
        if (Object.prototype.hasOwnProperty.call(claimed, id)) continue;
        claimed[id] = true;
        if (read.hidden) continue;
        var e = read.entry;
        if (!e.shown) continue;
        if (e.tryExec !== "") {
            if (!Object.prototype.hasOwnProperty.call(found, e.tryExec)) throw new Error("greeter: TryExec " + JSON.stringify(e.tryExec) + " was not looked up");
            if (!found[e.tryExec]) continue;
        }
        var available = true;
        if (e.type === "x11") {
            if (!Object.prototype.hasOwnProperty.call(found, "startx")) throw new Error("greeter: startx was not looked up");
            available = found.startx;
        }
        out.push({ id: e.id, type: e.type, name: e.name, argv: e.argv, desktopNames: e.desktopNames, available: available });
    }
    return { sessions: out, refused: refused };
}

function namesHyprland(names) {
    for (var i = 0; i < names.length; i++) if (names[i].toLowerCase() === "hyprland") return true;
    return false;
}

// Whether SESSION is the uwsm-managed Hyprland session: its Exec starts
// `uwsm start`, and the entry or the argument uwsm starts names Hyprland.
// It is matched by its command, never by its name, so a translated or
// renamed entry still matches.
function isUwsmHyprland(session) {
    var argv = session.argv;
    if (argv.length < 3 || baseName(argv[0]) !== "uwsm" || argv[1] !== "start") return false;
    if (namesHyprland(session.desktopNames)) return true;
    for (var i = 2; i < argv.length; i++) {
        if (/^(hyprland|start-hyprland)(\.desktop)?$/.test(baseName(argv[i]).toLowerCase())) return true;
    }
    return false;
}

// The id of the session to choose for USER: the one MEMORY remembers for
// them while it is listed and available, else the uwsm-managed Hyprland
// session, else another Hyprland session, else the first available; ""
// when none is available.
function preselect(list, memory, user) {
    var available = list.filter(function (s) { return s.available; });
    var remembered = Object.prototype.hasOwnProperty.call(memory.sessions, user) ? memory.sessions[user] : null;
    for (var i = 0; i < available.length; i++) if (available[i].id === remembered) return remembered;
    for (var j = 0; j < available.length; j++) if (isUwsmHyprland(available[j])) return available[j].id;
    for (var k = 0; k < available.length; k++) if (namesHyprland(available[k].desktopNames)) return available[k].id;
    return available.length > 0 ? available[0].id : "";
}

// The index in USERS of the account to choose first: the last user who
// logged in while listed, else the first; -1 for no account.
function preselectUser(list, memory) {
    for (var i = 0; i < list.length; i++) if (list[i].name === memory.lastUser) return i;
    return list.length > 0 ? 0 : -1;
}

// What greetd launches for SESSION: { command, environment }. A Wayland
// entry runs its own argv; an X entry runs through `startx /usr/bin/env`,
// as tuigreet does. XDG_SESSION_DESKTOP is the first desktop name, else
// the file's name without `.desktop`; XDG_CURRENT_DESKTOP joins the
// desktop names with `:`.
function launchRequest(session) {
    if (!session.available) throw new Error("greeter: session " + session.id + " is unavailable");
    var desktop = session.desktopNames.length > 0 ? session.desktopNames[0] : baseName(session.id).replace(/\.desktop$/, "");
    var environment = ["XDG_SESSION_TYPE=" + session.type, "XDG_SESSION_DESKTOP=" + desktop];
    if (session.desktopNames.length > 0) environment.push("XDG_CURRENT_DESKTOP=" + session.desktopNames.join(":"));
    switch (session.type) {
    case "wayland": return { command: session.argv.slice(), environment: environment };
    case "x11": return { command: ["startx", "/usr/bin/env"].concat(session.argv), environment: environment };
    }
    throw new Error("greeter: session type " + JSON.stringify(session.type) + " is not one of wayland, x11");
}

function emptyMemory() {
    return { lastUser: "", sessions: {} };
}

// The memory file's TEXT as { ok, memory }: `lastUser` and `sessions`, a
// map of user to session id; an unreadable document is { ok: false,
// memory: emptyMemory() }, and any key of another type is dropped.
function readMemory(text) {
    var doc;
    try {
        doc = JSON.parse(text);
    } catch (e) {
        return { ok: false, memory: emptyMemory() };
    }
    if (doc === null || typeof doc !== "object" || Array.isArray(doc)) return { ok: false, memory: emptyMemory() };
    var memory = emptyMemory();
    if (typeof doc.lastUser === "string") memory.lastUser = doc.lastUser;
    if (doc.sessions !== null && typeof doc.sessions === "object" && !Array.isArray(doc.sessions)) {
        for (var user in doc.sessions) {
            if (Object.prototype.hasOwnProperty.call(doc.sessions, user) && typeof doc.sessions[user] === "string") memory.sessions[user] = doc.sessions[user];
        }
    }
    return { ok: true, memory: memory };
}

// The memory file's text after USER logged in to SESSIONID: USER is the
// last user and their session is SESSIONID; the other remembered users
// stay, the listed accounts USERS first, at most MEMORY_USERS_MAX of them.
function remember(memory, user, sessionId, list) {
    var names = list.map(function (u) { return u.name; });
    var kept = [user];
    for (var other in memory.sessions) {
        if (Object.prototype.hasOwnProperty.call(memory.sessions, other) && other !== user && names.indexOf(other) !== -1) kept.push(other);
    }
    for (var unlisted in memory.sessions) {
        if (Object.prototype.hasOwnProperty.call(memory.sessions, unlisted) && kept.indexOf(unlisted) === -1) kept.push(unlisted);
    }
    var sessionsOut = {};
    for (var i = 0; i < kept.length && i < MEMORY_USERS_MAX; i++) sessionsOut[kept[i]] = kept[i] === user ? sessionId : memory.sessions[kept[i]];
    return JSON.stringify({ lastUser: user, sessions: sessionsOut }) + "\n";
}

// The answer to a greetd prompt: the PENDING password goes to the first
// prompt that hides what is typed, and only to it; every other prompt
// waits for the person. { respond, ask, pending }: `respond` the text to
// send now or null, `ask` whether the field asks for an answer, and
// `pending` the password still held for a later prompt, null once one
// took it.
function promptAnswer(responseRequired, echoResponse, pending) {
    if (!responseRequired) return { respond: null, ask: false, pending: pending };
    if (!echoResponse && pending !== null) return { respond: pending, ask: false, pending: null };
    return { respond: null, ask: true, pending: pending };
}

// The `greeter` status: the step's reading as the Settings row shows it,
// with Set up offered while it reads needed or nixos.
var STEP_STATES = ["ready", "needed", "nixos", "absent", "denied", "unknown"];
var REASON_TEXTS = {
    "greetd-missing": "Needs greetd",
    "hyprland-missing": "Needs Hyprland",
    "greeter-user-missing": "Needs the greeter account greetd makes",
    "other-display-manager": "Another login screen is turned on",
    "install-untrusted": "Needs VGS installed from a package",
    "install-path-unsupported": "VGS is installed in a folder the login screen cannot use",
    "other-account": "Another account set up the login screen",
    "unit-masked": "greetd is turned off by the system"
};
function stepState(step) {
    var state = step === null || step === undefined ? "unknown" : step.state;
    var reason = step === null || step === undefined ? "" : step.reason;
    switch (state) {
    case "ready": return { tone: "ok", text: "Set up", action: false };
    case "needed": return { tone: "warning", text: "Not set up", action: true };
    case "nixos": return { tone: "warning", text: "Needs your NixOS configuration", action: true };
    case "absent":
    case "denied":
        return { tone: state === "denied" ? "danger" : "info", text: Object.prototype.hasOwnProperty.call(REASON_TEXTS, reason) ? REASON_TEXTS[reason] : "Not available on this computer", action: false };
    case "unknown": return { tone: "warning", text: "Could not be checked", action: false };
    }
    throw new Error("greeter: step state " + JSON.stringify(state) + " is not one of " + STEP_STATES.join(", "));
}

// bin/copy-theme's arguments for a copy now: the theme file under
// CONFIGDIR, the background link under STATEDIR and THEME_DIR, in that
// order; null while the step does not read READY, since the directory is
// the step's.
function copyArguments(ready, configDir, stateDir) {
    if (!ready) return null;
    return [configDir + "/theme.json", stateDir + "/background", THEME_DIR];
}

// bin/copy-theme's one line, `theme=<what> background=<what>`, each
// `copied`, `unchanged` or `removed`, as { theme, background }; null for
// any other text.
function copyLine(text) {
    var m = /^theme=(copied|unchanged|removed) background=(copied|unchanged|removed)\n?$/.exec(String(text));
    return m === null ? null : { theme: m[1], background: m[2] };
}

// The `theme` status: READY, whether the step reads ready, and COPY, the
// last copy's result: null before one, { ok: true } or { ok: false }. The
// entry offers no action, so the value carries none.
function themeState(ready, copy) {
    if (!ready) return { tone: "info", text: "Waits for the login screen" };
    if (copy === null) return { tone: "info", text: "Copying" };
    if (copy.ok) return { tone: "ok", text: "Up to date" };
    return { tone: "danger", text: "Could not be copied" };
}
