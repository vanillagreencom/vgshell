.pragma library

// The one rule for where the AI command-line harnesses keep their sign-ins,
// read by Jarvis and AI usage, which run this file under node through
// bin/lib/qml-library.js, and by their QML. The harnesses document
// their folders beside each other: Claude Code keeps `~/.claude`
// (CLAUDE_CONFIG_DIR overrides it), Codex keeps `~/.codex` (CODEX_HOME),
// and Copilot CLI keeps `~/.copilot`, overridden by COPILOT_HOME
// (`copilot help environment`: "COPILOT_HOME: override the directory where
// configuration and state files are stored; defaults to $HOME/.copilot").
// A second account is a sibling such as `~/.claude-work`, `~/.2codex` or
// `~/.1copilot`. Pi's config.ts getAgentDir uses `~/.pi/agent`, overridden
// by PI_CODING_AGENT_DIR. Jarvis's own/accounts/scripts/agent-cli selects
// `~/.spi/agent` for its work account, so Pi sibling roots use accountSubdir
// for their existing agent directory. `home` is each default folder under HOME.
// `marker` is the file each harness writes once it is signed in.
// `outranks` names the environment variables the harness uses in place of
// the sign-in its folder holds, which a launch on a chosen folder clears:
// Claude Code's cloud provider switches, bearer token, API key (always used
// under -p), long-lived OAuth token, named profile and federation pair
// (code.claude.com/docs/en/authentication § Authentication precedence and
// § Anthropic profiles and federation credentials). `strays` are the ones
// an automatic launch, on the harness's own choice of folder, clears: an
// API key, which -p uses with no approval, and the OAuth token an
// agent-runtime session exports for its own account. The provider
// switches, bearer token, named profile and federation pair stay, since
// for that user they are the account itself. No source read names such a
// variable for another harness, so the other rows name none.
var HARNESSES = [
    { id: "claude", folder: "claude", home: ".claude", variable: "CLAUDE_CONFIG_DIR", marker: ".credentials.json",
        outranks: ["CLAUDE_CODE_USE_BEDROCK", "CLAUDE_CODE_USE_VERTEX", "CLAUDE_CODE_USE_FOUNDRY", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_API_KEY",
            "CLAUDE_CODE_OAUTH_TOKEN", "ANTHROPIC_PROFILE", "ANTHROPIC_FEDERATION_RULE_ID", "ANTHROPIC_ORGANIZATION_ID"],
        strays: ["ANTHROPIC_API_KEY", "CLAUDE_CODE_OAUTH_TOKEN"] },
    { id: "codex", folder: "codex", home: ".codex", variable: "CODEX_HOME", marker: "auth.json" },
    { id: "copilot", folder: "copilot", home: ".copilot", variable: "COPILOT_HOME", marker: "config.json" },
    { id: "pi", folder: "pi", accountSubdir: "agent", home: ".pi/agent", variable: "PI_CODING_AGENT_DIR", marker: "auth.json" }
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
 * `.5claude`, `.2codex` and `.1copilot` are account directories. A tag must
 * be immediately before the folder name, so `.github-copilot-cli` is not one.
 * Returns that harness's row, else null. The caller supplies the three bases
 * and the depth.
 */
var ACCOUNT_DEPTH = 2;
function accountDirectory(name, depth) {
    if (depth < 1 || depth > ACCOUNT_DEPTH) return null;
    for (var i = 0; i < HARNESSES.length; i++) {
        var row = HARNESSES[i];
        if (row.folder === null) continue;
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
