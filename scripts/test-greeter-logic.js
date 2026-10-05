#!/usr/bin/env node
// Table-driven checks for vgs.greeter's pure decisions, GreeterLogic.js:
// the accounts the login screen lists, the session entries it reads (the
// [Desktop Entry] group, the Exec quoting and field codes, Hidden,
// NoDisplay and TryExec), the uwsm-managed Hyprland session it chooses on
// first use, the last choice it remembers per user, what it launches, how
// it answers greetd's prompts, the copy its service runs and the status
// its service publishes.
// Expected values are written by hand. Controls edit a copy of the module,
// one rule each, and require this suite to fail.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { load } = require("../bin/lib/qml-library.js");

const file = path.join(__dirname, "..", "shell", "plugins", "vgs.greeter", "GreeterLogic.js");
const judge = load(path.join(__dirname, "..", "shell", "Core", "PluginLogic.js"));
const same = (got, want, message) => assert.deepEqual(JSON.parse(JSON.stringify(got)), JSON.parse(JSON.stringify(want)), message || "");

// A session file's text from its [Desktop Entry] lines.
const entry = (...lines) => ["[Desktop Entry]"].concat(lines).join("\n");
const read = (logic, files) => logic.readEntries(files.map(([kind, p, text]) => ({ kind, path: p, text })));
const listed = (logic, files, found) => logic.sessions(read(logic, files), found || {});
const argvOf = (logic, exec) => {
    const r = logic.sessionEntry("wayland-sessions", "/s/wayland-sessions/x.desktop", entry("Name=X", "Exec=" + exec));
    return r.ok ? r.entry.argv : r.reason;
};

const ARCH_PLAIN = ["wayland-sessions", "/usr/share/wayland-sessions/hyprland.desktop", entry("Name=Hyprland", "Exec=/usr/bin/start-hyprland", "DesktopNames=Hyprland", "Type=Application")];
const ARCH_UWSM = ["wayland-sessions", "/usr/share/wayland-sessions/hyprland-uwsm.desktop", entry("Name=Hyprland (uwsm-managed)", "Exec=uwsm start -e -D Hyprland hyprland.desktop", "TryExec=uwsm", "DesktopNames=Hyprland", "Type=Application")];
const PLASMA = ["wayland-sessions", "/usr/share/wayland-sessions/plasma.desktop", entry("Name=Plasma (Wayland)", "Exec=/usr/lib/plasma-dbus-run-session-if-needed /usr/bin/startplasma-wayland", "DesktopNames=KDE")];
const XFCE = ["xsessions", "/usr/share/xsessions/xfce.desktop", entry("Name=Xfce Session", "Exec=startxfce4", "DesktopNames=XFCE")];

function verify(logic) {
    // Accounts: uids 1000 to 59999 with a login shell, in getent's order.
    const PASSWD = [
        "root:x:0:0::/root:/usr/bin/bash",
        "greeter:x:958:958:greetd greeter user:/:/bin/bash",
        "edge-low:x:999:999::/home/e:/bin/bash",
        "alice:x:1000:1000:Alice Liddell,Room 1,,:/home/alice:/usr/bin/zsh",
        "bob:x:1001:1001::/home/bob:/bin/bash",
        "svc:x:1002:1002::/var/svc:/usr/bin/nologin",
        "off:x:1003:1003::/home/off:/bin/false",
        "edge-high:x:59999:59999::/home/h:/bin/sh",
        "past:x:60000:60000::/home/p:/bin/bash",
        "nobody:x:65534:65534:Kernel Overflow User:/:/usr/bin/nologin",
        "broken:x:1004",
        "letters:x:abc:1::/:/bin/sh",
        ""
    ].join("\n");
    same(logic.users(PASSWD), [{ name: "alice", label: "Alice Liddell" }, { name: "bob", label: "bob" }, { name: "edge-high", label: "edge-high" }], "the people's accounts");

    const DIRS = [
        ["unset reads the specification's default", undefined, ["/usr/local/share", "/usr/share"]],
        ["empty reads the default", "", ["/usr/local/share", "/usr/share"]],
        ["a trailing slash and a duplicate fold", "/opt/s/:/usr/share:/opt/s", ["/opt/s", "/usr/share"]],
        ["a relative entry is dropped", "share:/usr/share", ["/usr/share"]]
    ];
    for (const [label, value, want] of DIRS) same(logic.dataDirs(value), want, label);

    same(logic.listing("@ wayland-sessions /a/wayland-sessions/x.desktop\n|[Desktop Entry]\n|Name=X\n@ xsessions /a/xsessions/y.desktop\n|Exec=y\n"),
        [{ kind: "wayland-sessions", path: "/a/wayland-sessions/x.desktop", text: "[Desktop Entry]\nName=X" }, { kind: "xsessions", path: "/a/xsessions/y.desktop", text: "Exec=y" }], "the helper's listing");
    assert.throws(() => logic.listing("stray\n"), /sessions line "stray" is not the helper's/, "a stray line is the helper's defect");

    // The [Desktop Entry] group alone, without locales, first key wins.
    const GROUPS = [
        ["another group's Exec is not the entry's", "[Desktop Action x]\nName=B\nExec=b\n[Desktop Entry]\nName=A\nExec=a", ["a"]],
        ["a localized Name before the plain one is ignored", "[Desktop Entry]\nName[de]=Deutsch\nName = Plain\nExec=a", "Plain"],
        ["comments and blank lines are skipped", "# c\n\n[Desktop Entry]\n# Exec=no\nName=A\nExec=a", ["a"]],
        ["a line before the group is refused", "Name=A\n[Desktop Entry]\nExec=a", "line-before-group"],
        ["no group is refused", "Name=A\nExec=a", "line-before-group"],
        ["no Exec is refused", "[Desktop Entry]\nName=A", "exec-missing"],
        ["no Name is refused", "[Desktop Entry]\nExec=a", "name-missing"]
    ];
    for (const [label, text, want] of GROUPS) {
        const r = logic.sessionEntry("wayland-sessions", "/s/wayland-sessions/a.desktop", text);
        const got = !r.ok ? r.reason : typeof want === "string" && !Array.isArray(want) && r.entry.name === want ? want : Array.isArray(want) ? r.entry.argv : r.entry.name;
        same(got, want, label);
    }

    // Exec: quoting, then field codes; never a split at every space.
    const EXECS = [
        ["a plain command", "/usr/bin/start-hyprland", ["/usr/bin/start-hyprland"]],
        ["spaces separate arguments, repeated ones once", "uwsm  start -e -D Hyprland hyprland.desktop", ["uwsm", "start", "-e", "-D", "Hyprland", "hyprland.desktop"]],
        ["a quoted argument keeps its spaces", "sh -c \"echo a b\"", ["sh", "-c", "echo a b"]],
        ["a quoted path keeps its spaces", "\"/opt/my session/run\" --flag", ["/opt/my session/run", "--flag"]],
        ["an escaped quote inside quotes, after the string escape", "sh -c \"say \\\\\"hi\\\\\"\"", ["sh", "-c", "say \"hi\""]],
        ["an escaped dollar inside quotes", "sh -c \"echo \\\\$HOME\"", ["sh", "-c", "echo $HOME"]],
        ["an empty quoted argument stays", "run \"\" x", ["run", "", "x"]],
        ["a lone field code is dropped", "app %U", ["app"]],
        ["%% reads as %", "printf 100%%", ["printf", "100%"]],
        ["a field code inside an argument is removed", "app --file=%f", ["app", "--file="]],
        ["an unknown field code is refused", "app %z", "exec-field-code"],
        ["a trailing % is refused", "app 5%", "exec-field-code"],
        ["an unterminated quote is refused", "sh -c \"echo", "exec-quote"],
        ["an unknown escape inside quotes is refused", "sh \"\\\\a\"", "exec-escape"],
        ["only field codes is empty", "%U", "exec-empty"]
    ];
    for (const [label, exec, want] of EXECS) same(argvOf(logic, exec), want, label);
    assert.equal(logic.sessionEntry("wayland-sessions", "/s/wayland-sessions/a.desktop", entry("Name=A\\sB", "Exec=a")).entry.name, "A B", "a string escape reads");
    assert.equal(logic.sessionEntry("wayland-sessions", "/s/wayland-sessions/a.desktop", entry("Name=A", "Exec=a\\q")).reason, "exec-missing", "an unknown string escape is no Exec");
    assert.equal(logic.sessionEntry("wayland-sessions", "/s/wayland-sessions/a.txt", entry("Name=A", "Exec=a")).reason, "not-desktop", "a file that is no .desktop");
    same(logic.sessionEntry("xsessions", "/s/xsessions/a.desktop", entry("Name=A", "Exec=a", "DesktopNames=X\\;Y;Z;")).entry.desktopNames, ["X;Y", "Z"], "DesktopNames is a list");
    assert.throws(() => logic.sessionEntry("other", "/s/other/a.desktop", entry("Name=A", "Exec=a")), /session kind "other"/, "an unknown kind throws");

    // Which commands the helper looks up: every TryExec, startx for X.
    same(logic.commandsToCheck(read(logic, [ARCH_PLAIN, ARCH_UWSM, XFCE])), ["uwsm", "startx"], "TryExec and startx are looked up");
    same(logic.foundCommands("found uwsm\nmissing startx\n"), { uwsm: true, startx: false }, "the helper's which answer");
    assert.throws(() => logic.foundCommands("maybe uwsm\n"), /which line/, "a stray which line is the helper's defect");

    // The picker's list.
    const both = listed(logic, [ARCH_PLAIN, ARCH_UWSM, PLASMA, XFCE], { uwsm: true, startx: true });
    same(both.sessions.map(s => [s.id, s.type, s.available]),
        [["wayland-sessions/hyprland.desktop", "wayland", true], ["wayland-sessions/hyprland-uwsm.desktop", "wayland", true], ["wayland-sessions/plasma.desktop", "wayland", true], ["xsessions/xfce.desktop", "x11", true]], "every installed session");
    same(listed(logic, [ARCH_PLAIN, ARCH_UWSM], { uwsm: false }).sessions.map(s => s.id), ["wayland-sessions/hyprland.desktop"], "a TryExec not found leaves the entry out");
    same(listed(logic, [XFCE], { startx: false }).sessions.map(s => [s.id, s.available]), [["xsessions/xfce.desktop", false]], "an X entry reads unavailable without startx");
    const nodisplay = ["wayland-sessions", "/usr/share/wayland-sessions/nd.desktop", entry("Name=ND", "Exec=nd", "NoDisplay=true")];
    same(listed(logic, [nodisplay, ARCH_PLAIN]).sessions.map(s => s.id), ["wayland-sessions/hyprland.desktop"], "a NoDisplay entry is left out");
    const local = ["wayland-sessions", "/usr/local/share/wayland-sessions/hyprland.desktop", entry("Name=Local Hyprland", "Exec=/opt/hyprland")];
    same(listed(logic, [local, ARCH_PLAIN]).sessions.map(s => s.name), ["Local Hyprland"], "an earlier directory's file of the same name wins");
    const hidden = ["wayland-sessions", "/usr/local/share/wayland-sessions/hyprland.desktop", entry("Hidden=true")];
    same(listed(logic, [hidden, ARCH_PLAIN]).sessions.map(s => s.id), [], "a Hidden file deletes the id for later directories");
    same(listed(logic, [["wayland-sessions", "/a/wayland-sessions/b.desktop", "junk"], ARCH_PLAIN]).refused, [{ path: "/a/wayland-sessions/b.desktop", reason: "line-before-group" }], "a file that is no entry is refused by path");
    same(listed(logic, [["wayland-sessions", "/a/wayland-sessions/t.desktop", entry("Name=T", "Exec=t", "TryExec=a\\nb")]]).refused.map(r => r.reason), ["tryexec-malformed"], "a TryExec with a control character is refused");

    // The first choice: the uwsm-managed Hyprland session, by its command.
    const empty = logic.emptyMemory();
    assert.equal(logic.preselect(both.sessions, empty, "alice"), "wayland-sessions/hyprland-uwsm.desktop", "first use chooses the uwsm-managed Hyprland session");
    const renamed = ["wayland-sessions", "/usr/share/wayland-sessions/hyprland-uwsm.desktop", entry("Name=Hyprland (gestionnaire)", "Exec=uwsm start -e -D Hyprland hyprland.desktop")];
    assert.equal(logic.preselect(listed(logic, [ARCH_PLAIN, renamed]).sessions, empty, "alice"), "wayland-sessions/hyprland-uwsm.desktop", "a renamed uwsm entry still matches");
    const decoy = ["wayland-sessions", "/usr/share/wayland-sessions/a-decoy.desktop", entry("Name=Hyprland (uwsm-managed)", "Exec=/usr/bin/start-hyprland", "DesktopNames=Hyprland")];
    assert.equal(logic.preselect(listed(logic, [decoy, ARCH_UWSM], { uwsm: true }).sessions, empty, "alice"), "wayland-sessions/hyprland-uwsm.desktop", "a name alone does not match");
    const uwsmOther = ["wayland-sessions", "/usr/share/wayland-sessions/sway-uwsm.desktop", entry("Name=Sway (uwsm)", "Exec=uwsm start -e -D sway sway.desktop", "DesktopNames=sway")];
    assert.equal(logic.preselect(listed(logic, [uwsmOther, ARCH_PLAIN]).sessions, empty, "alice"), "wayland-sessions/hyprland.desktop", "uwsm starting another compositor is not it; another Hyprland session is next");
    assert.equal(logic.preselect(listed(logic, [PLASMA]).sessions, empty, "alice"), "wayland-sessions/plasma.desktop", "with no Hyprland the first available");
    assert.equal(logic.preselect(listed(logic, [XFCE], { startx: false }).sessions, empty, "alice"), "", "nothing available chooses nothing");

    // After that, each user's last choice.
    const memory = { lastUser: "bob", sessions: { bob: "wayland-sessions/plasma.desktop", carol: "xsessions/xfce.desktop", dave: "wayland-sessions/gone.desktop" } };
    assert.equal(logic.preselect(both.sessions, memory, "bob"), "wayland-sessions/plasma.desktop", "a user's last session");
    assert.equal(logic.preselect(both.sessions, memory, "alice"), "wayland-sessions/hyprland-uwsm.desktop", "another user's choice is theirs alone");
    assert.equal(logic.preselect(both.sessions, memory, "dave"), "wayland-sessions/hyprland-uwsm.desktop", "a remembered session no longer listed");
    const noStartx = listed(logic, [ARCH_PLAIN, ARCH_UWSM, XFCE], { uwsm: true, startx: false }).sessions;
    assert.equal(logic.preselect(noStartx, memory, "carol"), "wayland-sessions/hyprland-uwsm.desktop", "a remembered session that cannot start");
    const people = [{ name: "alice", label: "Alice" }, { name: "bob", label: "bob" }];
    assert.equal(logic.preselectUser(people, memory), 1, "the last user");
    assert.equal(logic.preselectUser(people, { lastUser: "zed", sessions: {} }), 0, "a last user no longer listed");
    assert.equal(logic.preselectUser([], memory), -1, "no account");

    // What greetd launches.
    const byId = id => both.sessions.find(s => s.id === id);
    same(logic.launchRequest(byId("wayland-sessions/hyprland-uwsm.desktop")),
        { command: ["uwsm", "start", "-e", "-D", "Hyprland", "hyprland.desktop"], environment: ["XDG_SESSION_TYPE=wayland", "XDG_SESSION_DESKTOP=Hyprland", "XDG_CURRENT_DESKTOP=Hyprland"] }, "a Wayland session");
    same(logic.launchRequest(byId("xsessions/xfce.desktop")),
        { command: ["startx", "/usr/bin/env", "startxfce4"], environment: ["XDG_SESSION_TYPE=x11", "XDG_SESSION_DESKTOP=XFCE", "XDG_CURRENT_DESKTOP=XFCE"] }, "an X session through startx");
    const bare = listed(logic, [["wayland-sessions", "/s/wayland-sessions/bare.desktop", entry("Name=Bare", "Exec=bare")]]).sessions[0];
    same(logic.launchRequest(bare).environment, ["XDG_SESSION_TYPE=wayland", "XDG_SESSION_DESKTOP=bare"], "no desktop names: the file's name");
    assert.throws(() => logic.launchRequest(noStartx.find(s => s.type === "x11")), /is unavailable/, "an unavailable session is never launched");

    // The memory file.
    same(logic.readMemory("not json"), { ok: false, memory: { lastUser: "", sessions: {} } }, "an unreadable file");
    same(logic.readMemory("[1]"), { ok: false, memory: { lastUser: "", sessions: {} } }, "a list is no memory");
    same(logic.readMemory('{"lastUser":7,"sessions":{"a":"x","b":3}}'), { ok: true, memory: { lastUser: "", sessions: { a: "x" } } }, "keys of another type are dropped");
    same(JSON.parse(logic.remember(memory, "alice", "wayland-sessions/hyprland.desktop", people)),
        { lastUser: "alice", sessions: { alice: "wayland-sessions/hyprland.desktop", bob: "wayland-sessions/plasma.desktop", carol: "xsessions/xfce.desktop", dave: "wayland-sessions/gone.desktop" } }, "a login is remembered beside the others");
    assert.ok(logic.remember(memory, "alice", "x", people).endsWith("}\n"), "the file ends with a newline");
    const crowd = { lastUser: "", sessions: {} };
    for (let i = 0; i < 100; i++) crowd.sessions["u" + i] = "s";
    const kept = Object.keys(JSON.parse(logic.remember(crowd, "alice", "x", [{ name: "u99", label: "u99" }])).sessions);
    assert.equal(kept.length, logic.MEMORY_USERS_MAX, "the file keeps at most its ceiling of users");
    same(kept.slice(0, 2), ["alice", "u99"], "the user who logged in, then the listed accounts, come first");

    // greetd's prompts.
    const PROMPTS = [
        ["a hidden prompt takes the typed password", [true, false, "pw"], { respond: "pw", ask: false, pending: null }],
        ["a shown prompt waits for the person and keeps the password", [true, true, "pw"], { respond: null, ask: true, pending: "pw" }],
        ["a hidden prompt with nothing typed waits", [true, false, null], { respond: null, ask: true, pending: null }],
        ["a message needs no answer and keeps the password", [false, false, "pw"], { respond: null, ask: false, pending: "pw" }]
    ];
    for (const [label, args, want] of PROMPTS) same(logic.promptAnswer(...args), want, label);
    // Two hidden prompts, a password then a one-time code: the view keeps
    // the pending value each answer returns, so the second waits.
    const first = logic.promptAnswer(true, false, "pw");
    const second = logic.promptAnswer(true, false, first.pending);
    same([first.respond, second], ["pw", { respond: null, ask: true, pending: null }], "the typed password answers only the first of two hidden prompts");

    // The statuses.
    const STEPS = [
        ["ready", { state: "ready", reason: "granted" }, { tone: "ok", text: "Set up", action: false }],
        ["needed offers Set up", { state: "needed", reason: "not-set-up" }, { tone: "warning", text: "Not set up", action: true }],
        ["nixos offers the snippet", { state: "nixos", reason: "not-set-up" }, { tone: "warning", text: "Needs your NixOS configuration", action: true }],
        ["another display manager", { state: "denied", reason: "other-display-manager" }, { tone: "danger", text: "Another login screen is turned on", action: false }],
        ["an install its owner can write", { state: "denied", reason: "install-untrusted" }, { tone: "danger", text: "Needs VGS installed from a package", action: false }],
        ["no greetd", { state: "absent", reason: "greetd-missing" }, { tone: "info", text: "Needs greetd", action: false }],
        ["an unnamed reason", { state: "absent", reason: "other" }, { tone: "info", text: "Not available on this computer", action: false }],
        ["unknown", { state: "unknown", reason: "probe-failed" }, { tone: "warning", text: "Could not be checked", action: false }],
        ["no reading yet", null, { tone: "warning", text: "Could not be checked", action: false }]
    ];
    for (const [label, step, want] of STEPS) same(logic.stepState(step), want, label);
    assert.throws(() => logic.stepState({ state: "odd", reason: "x" }), /step state "odd"/, "an unknown state throws");
    // The service's copy: nothing until the step reads ready, then the
    // theme file, the background link and the step's directory, in that
    // order.
    assert.equal(logic.copyArguments(false, "/home/a/.config/vgs", "/home/a/.local/state/vgs"), null, "no copy before the step reads ready");
    same(logic.copyArguments(true, "/home/a/.config/vgs", "/home/a/.local/state/vgs"),
        ["/home/a/.config/vgs/theme.json", "/home/a/.local/state/vgs/background", "/var/lib/vgs/greeter/theme"], "the copy's arguments");
    same(logic.copyLine("theme=copied background=removed\n"), { theme: "copied", background: "removed" }, "the copy's line");
    assert.equal(logic.copyLine("theme=copied"), null, "a cut line");
    same(logic.themeState(false, null), { tone: "info", text: "Waits for the login screen" }, "no copy before setup");
    same(logic.themeState(true, { ok: true }), { tone: "ok", text: "Up to date" }, "a copy");
    same(logic.themeState(true, { ok: false }), { tone: "danger", text: "Could not be copied" }, "a failed copy");
    // Every value the service publishes is one the manifest judge accepts
    // for its entry.
    const manifest = judge.validateManifest(JSON.parse(fs.readFileSync(path.join(path.dirname(file), "manifest.json"), "utf8")), path.dirname(file)).manifest;
    const published = STEPS.map(([label, step]) => ["greeter", logic.stepState(step), label])
        .concat([[false, null], [true, null], [true, { ok: true }], [true, { ok: false }]].map(([ready, copy]) => ["theme", logic.themeState(ready, copy), "theme " + JSON.stringify(copy)]));
    for (const [key, value, label] of published) assert.equal(judge.statusWrite(manifest, {}, key, value).ok, true, "the manifest judge accepts the " + key + " value: " + label);
}

verify(load(file));

const CONTROLS = [
    ["accounts start at uid 1000", "if (uid < UID_MIN || uid > UID_MAX) continue;", "if (uid > UID_MAX) continue;"],
    ["accounts end at uid 59999", "if (uid < UID_MIN || uid > UID_MAX) continue;", "if (uid < UID_MIN) continue;"],
    ["a no-login shell is left out", "if (NO_LOGIN_SHELLS.indexOf(baseName(fields[6])) !== -1) continue;", ""],
    ["unset XDG_DATA_DIRS reads the default", 'var text = value === undefined || value === null || String(value) === "" ? DEFAULT_DATA_DIRS : String(value);', "var text = String(value);"],
    ["a stray helper line throws", 'throw new Error("greeter: sessions line "', 'continue;\n        throw new Error("greeter: sessions line "'],
    ["only the Desktop Entry group", 'if (group !== "Desktop Entry") continue;', ""],
    ["a localized key is ignored", 'if (pair[2] !== undefined && pair[2] !== "") continue;', ""],
    ["quotes group an argument", "        if (quoted) {", "        if (false) {"],
    ["an escape inside quotes reads its character", "                current += n;", "                current += c + n;"],
    ["a lone field code is dropped", "if (!arg.quoted && arg.text.length === 2", "if (false && arg.text.length === 2"],
    ["%% reads as %", 'if (code === "%") out += "%";', 'if (code === "%") out += "%%";'],
    ["an unknown field code is refused", 'else if (code === "" || FIELD_CODES.indexOf(code) === -1) return', "else if (false) return"],
    ["Hidden deletes the entry", 'if (isTrue(keys, "Hidden")) return', "if (false) return"],
    ["an earlier directory wins", "if (Object.prototype.hasOwnProperty.call(claimed, id)) continue;", ""],
    ["NoDisplay leaves the entry out", "if (!e.shown) continue;", ""],
    ["a TryExec not found leaves the entry out", "if (!found[e.tryExec]) continue;", ""],
    ["an X entry needs startx", "available = found.startx;", "available = true;"],
    ["uwsm is matched by its command, not its name", "    var argv = session.argv;\n    if (argv.length < 3", "    if (/uwsm/i.test(session.name)) return true;\n    var argv = session.argv;\n    if (argv.length < 3"],
    ["uwsm must start Hyprland", "    if (namesHyprland(session.desktopNames)) return true;\n    for (var i = 2;", "    return true;\n    for (var i = 2;"],
    ["a user's last session wins", "if (available[i].id === remembered) return remembered;", ""],
    ["only an available session is chosen", "var available = list.filter(function (s) { return s.available; });", "var available = list;"],
    ["an X session starts through startx", 'case "x11": return { command: ["startx", "/usr/bin/env"].concat(session.argv)', 'case "x11": return { command: session.argv.slice()'],
    ["the session type is the entry's", 'var environment = ["XDG_SESSION_TYPE=" + session.type,', 'var environment = ["XDG_SESSION_TYPE=wayland",'],
    ["the memory has a ceiling", "i < kept.length && i < MEMORY_USERS_MAX;", "i < kept.length;"],
    ["a memory value of another type is dropped", 'typeof doc.sessions[user] === "string"', "true"],
    ["the password answers only a hidden prompt", "if (!echoResponse && pending !== null)", "if (pending !== null)"],
    ["the password answers only one prompt", 'return { respond: pending, ask: false, pending: null };', 'return { respond: pending, ask: false, pending: pending };'],
    ["the theme is copied only once the step reads ready", "    if (!ready) return null;\n    return [configDir", "    return [configDir"],
    ["the copy's arguments are the theme, the link, then the directory", 'return [configDir + "/theme.json", stateDir + "/background", THEME_DIR];', 'return [stateDir + "/background", configDir + "/theme.json", THEME_DIR];'],
    ["the theme status carries no action", 'if (!ready) return { tone: "info", text: "Waits for the login screen" };', 'if (!ready) return { tone: "info", text: "Waits for the login screen", action: false };'],
    ["a needed step offers Set up", 'case "needed": return { tone: "warning", text: "Not set up", action: true };', 'case "needed": return { tone: "warning", text: "Not set up", action: false };']
];
const scratch = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), "test-greeter-logic-")));
try {
    const source = fs.readFileSync(file, "utf8");
    for (const [label, needle, replacement] of CONTROLS) {
        assert.equal(source.split(needle).length - 1, 1, `control pattern occurs once: ${label}`);
        const mutant = path.join(scratch, "GreeterLogic.js");
        fs.writeFileSync(mutant, source.replace(needle, replacement));
        assert.notEqual(fs.readFileSync(mutant, "utf8"), source, `control changed the copy: ${label}`);
        let red = false;
        try { verify(load(mutant)); } catch (e) { red = true; }
        assert.equal(red, true, `control passed the suite: ${label}`);
    }
} finally {
    fs.rmSync(scratch, { recursive: true, force: true });
}

console.log(`test-greeter-logic: ok controls=${CONTROLS.length}`);
