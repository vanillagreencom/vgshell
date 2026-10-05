.pragma library

// The one rule for where the AI command-line harnesses keep their sign-ins,
// read by Jarvis and AI usage, which run this file under node through
// bin/lib/qml-library.js, and by their QML. The harnesses document
// their folders beside each other: Claude Code keeps `~/.claude`
// (CLAUDE_CONFIG_DIR overrides it) and Codex `~/.codex` (CODEX_HOME), and a
// second account is a sibling such as `~/.claude-work` or `~/.2codex`.
// `marker` is the file each harness writes once it is signed in.
var HARNESSES = [
    { id: "claude", folder: "claude", variable: "CLAUDE_CONFIG_DIR", marker: ".credentials.json" },
    { id: "codex", folder: "codex", variable: "CODEX_HOME", marker: "auth.json" }
];

// harness(ID): the row of harness ID, else null.
function harness(id) {
    for (var i = 0; i < HARNESSES.length; i++)
        if (HARNESSES[i].id === id) return HARNESSES[i];
    return null;
}

/**
 * The account directory name rule, shared by discovery and the protected
 * path judge. An entry `depth` levels below HOME, the XDG config home or the
 * XDG data home is an account directory when depth is 1 to ACCOUNT_DEPTH
 * and its name is ".", a tag of up to 8 lowercase letters or digits, a
 * harness's `folder` name and anything after it: `.claude`, `.claude-work`,
 * `.5claude` and `.2codex` are account directories. Returns that harness's
 * row, else null. The caller supplies the three bases and the depth.
 */
var ACCOUNT_DEPTH = 2;
function accountDirectory(name, depth) {
    if (depth < 1 || depth > ACCOUNT_DEPTH) return null;
    for (var i = 0; i < HARNESSES.length; i++) {
        var row = HARNESSES[i];
        if (new RegExp("^\\.[a-z0-9]{0,8}" + row.folder).test(name)) return row;
    }
    return null;
}

// The account name less its harness's folder name and the separators
// around it: a tag before and a suffix after, joined by "-", or "default".
function label(name, row) {
    var at = name.indexOf(row.folder, 1);
    var parts = [name.slice(1, at), name.slice(at + row.folder.length).replace(/^[-_.]+|[-_.]+$/g, "")];
    return parts.filter(Boolean).join("-") || "default";
}

// The harnesses' explicit root variables, read through read(name), so a
// child sees the same explicit account roots discovery does.
function accountVariables(read) {
    var result = {};
    for (var i = 0; i < HARNESSES.length; i++) result[HARNESSES[i].variable] = read(HARNESSES[i].variable);
    return result;
}
