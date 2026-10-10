#!/usr/bin/env node
"use strict";
const { assert, fs, path, cp, tree, environment, world, mutant } = require("./fixtures/jarvis/accounts-world.js");
const plugin = path.join(tree, "shell/plugins/vgs.jarvis");
const { PROVIDERS } = require(path.join(plugin, "AccountProviders.js"));

// gum table --print's rounded frame: 3 columns of border and padding per
// cell plus the closing rule.
const frame = columns => 3 * columns + 1;
const HASH = /[0-9a-f]{32}/;
// A script's own list of gum's words in place of the library's: GUM_*,
// TERM and COLORTERM, without the base colours gum style reads.
const OWN_GUM_LIST = 'gum_env=(TERM="${TERM:-}" COLORTERM="${COLORTERM:-}"); ' +
    'while IFS= read -r name; do gum_env+=("$name=${!name}"); done < <(compgen -e GUM_)';

// RFC 4180 lines, as gum table reads them.
function parseCsv(line) {
    const cells = [];
    const pattern = /"((?:[^"]|"")*)"(,|$)/y;
    let match;
    while (pattern.lastIndex < line.length && (match = pattern.exec(line)) !== null) {
        cells.push(match[1].replace(/""/g, "\""));
        if (match[2] === "") break;
    }
    assert.equal(pattern.lastIndex, line.length, "a whole CSV line: " + line);
    return cells;
}
const chars = text => Array.from(text).length;

// The world's gum stand-in, replaced for this screen: choose answers with
// an option's value, "first" for the first one, and prints the value as
// gum 2.0.2 does under --label-delimiter; an answer no option carries
// fails the run. table echoes the CSV it draws.
const GUM = `#!/usr/bin/env node
const fs = require("node:fs"), path = require("node:path");
const state = process.env.XDG_STATE_HOME, args = process.argv.slice(2);
fs.appendFileSync(path.join(state, "gum-calls"), JSON.stringify({ args, env: process.env }) + "\\n");
if (args[0] === "style") process.exit(0);
if (args[0] === "table") { process.stdout.write(fs.readFileSync(0, "utf8")); process.exit(0); }
const file = path.join(state, "gum-queue");
const queue = JSON.parse(fs.readFileSync(file, "utf8"));
if (!queue.length) process.exit(9);
const answer = queue.shift();
fs.writeFileSync(file, JSON.stringify(queue));
if (args[0] === "confirm") process.exit(answer === "no" ? 1 : 0);
if (args[0] !== "choose") { console.log(answer); process.exit(0); }
const delimiter = args.find(arg => arg.startsWith("--label-delimiter="))?.slice("--label-delimiter=".length);
const values = fs.readFileSync(0, "utf8").replace(/\\n$/, "").split("\\n")
    .map(line => delimiter ? line.slice(line.indexOf(delimiter) + delimiter.length) : line);
const value = answer === "first" ? values[0] : values.find(item => item === answer);
if (value === undefined) process.exit(9);
console.log(value);
`;

// node, first on the world's PATH: records the program and the
// environment of each start in XDG_STATE_HOME/node-calls, then runs the
// real node.
const NODE = `#!/bin/sh
if [ -n "\${XDG_STATE_HOME:-}" ]; then { printf -- '--- %s\\n' "$1"; env; } >>"$XDG_STATE_HOME/node-calls"; fi
exec '${process.execPath.replace(/'/g, "'\\''")}' "$@"
`;

world(async () => {
    fs.writeFileSync(path.join(process.env.JARVIS_TEST_ROOT, "standins/gum"), GUM, { mode: 0o700 });
    fs.writeFileSync(path.join(process.env.JARVIS_TEST_ROOT, "standins/node"), NODE, { mode: 0o700 });
    // The world's PATH holds no stty, which vgs_tui_columns reads the
    // terminal's width with.
    const stty = ["/usr/bin/stty", "/bin/stty"].find(file => fs.existsSync(file));
    assert.ok(stty, "stty");
    fs.symlinkSync(stty, path.join(process.env.JARVIS_TEST_ROOT, "standins/stty"));
    const env = environment();
    const hand = path.join(env.HOME, "manual-account");
    fs.mkdirSync(hand);
    const log = path.join(env.XDG_STATE_HOME, "vgshell/jarvis/setup.log");
    // The words gum is handed: a gum.env colour of each kind the presenter
    // exports, and the terminal's colour support.
    const gumWords = { GUM_CHOOSE_CURSOR_FOREGROUND: "#112233", FOREGROUND: "#445566", BACKGROUND: "#778899",
        BORDER_FOREGROUND: "#aabbcc", TERM: "xterm-256color", COLORTERM: "truecolor" };
    Object.assign(env, gumWords);
    env.ANTHROPIC_API_KEY = "fixture-secret-private";
    // The names in the environment of each accounts helper the scripts
    // started, from node-calls line FROM on; the helper is the only node
    // program the scripts start.
    const nodeCalls = () => {
        let text = "";
        try { text = fs.readFileSync(path.join(env.XDG_STATE_HOME, "node-calls"), "utf8"); }
        catch (e) { if (e.code !== "ENOENT") throw e; }
        return text.split("\n");
    };
    const helperNames = from => {
        const calls = [];
        for (const line of nodeCalls().slice(from)) {
            if (line.startsWith("--- ")) calls.push({ program: line.slice(4), names: new Set() });
            else if (calls.length > 0 && /^[A-Za-z_][A-Za-z0-9_]*=/.test(line)) calls.at(-1).names.add(line.slice(0, line.indexOf("=")));
        }
        const helpers = calls.filter(call => call.program.endsWith("/backend/accounts.js"));
        assert.ok(helpers.length > 0, "the script started its node helper");
        return helpers.map(call => call.names);
    };
    const queue = choices => fs.writeFileSync(path.join(env.XDG_STATE_HOME, "gum-queue"), JSON.stringify(choices));
    const run = (folder, columns = 64) => cp.spawnSync("python3", [path.join(tree, "scripts/fixtures/jarvis/accounts-tui.py"),
        path.join(folder, "tui/accounts.sh"), path.join(tree, "bin/lib/tui.sh"), folder, String(columns)], {
        env, encoding: "utf8", timeout: 20000 });
    const cli = (folder, ...args) => {
        const result = cp.spawnSync("node", [path.join(folder, "backend/accounts.js"), "--tree", tree, ...args],
            { env, encoding: "utf8", timeout: 15000 });
        assert.equal(result.status, 0, args.join(" ") + ": " + result.stdout + result.stderr);
        return result.stdout;
    };
    const check = folder => {
        fs.rmSync(log, { force: true });
        queue(["add", "claude", hand, "my-account", "item", "first", "openai", "my-key",
            "show", "verify", "first", "-fixture", "yes", "close"]);
        const from = nodeCalls().length - 1;
        const result = run(folder);
        assert.equal(result.error, undefined);
        assert.equal(result.status, 0, result.stdout + result.stderr);
        for (const names of helperNames(from))
            for (const name of Object.keys(gumWords)) assert.equal(names.has(name), false, "the node helper got " + name);
        const accountFile = path.join(env.XDG_STATE_HOME, "vgshell/jarvis/accounts.json");
        const keyFile = path.join(env.XDG_STATE_HOME, "vgshell/jarvis/keys.json");
        assert.deepEqual(JSON.parse(fs.readFileSync(accountFile)), [{ provider: "claude", directory: hand, label: "my-account" }]);
        assert.deepEqual(JSON.parse(fs.readFileSync(keyFile)), [{ provider: "openai", account: "my-key", origin: "https://api.openai.com",
            attributes: { application: "other-tool", id: "api-key" } }]);
        // Verify of the first account with a model name no program takes
        // refuses before any vendor program or request starts. The result
        // goes to the log, and no id or keyed line reaches the screen.
        const logged = fs.readFileSync(log, "utf8");
        assert.match(logged, /"kind":"unavailable","reason":"model-invalid"/);
        assert.doesNotMatch(result.stdout, /"kind"|jarvis-accounts:/);
        assert.doesNotMatch(result.stdout, HASH);
        assert.equal((result.stdout + result.stderr + logged).includes("fixture-secret-private"), false);
        // Show accounts draws the table the gum stand-in echoes: a header
        // and the signed-in account's row, each row within the pty's 64
        // columns once gum frames it.
        const drawn = result.stdout.split(/\r?\n/).filter(line => line.startsWith("\"")).map(parseCsv);
        assert.ok(drawn.length >= 2 && drawn.every(row => row.length === 4), "Show accounts draws its table");
        // A cut cell keeps the start of its text before the ellipsis.
        const shows = (cell, text) => cell === text || (cell.length > 1 && cell.endsWith("…") && text.startsWith(cell.slice(0, -1)));
        assert.ok(drawn.some(row => shows(row[1], "team@example.invalid")), "the signed-in account's row is drawn");
        for (const row of drawn)
            assert.ok(row.reduce((sum, cell) => sum + chars(cell), 0) + frame(4) <= 64, "fits the terminal: " + row);
        for (const file of ["cli-calls", "port-calls", "bus-calls", "gum-calls"]) {
            const records = fs.readFileSync(path.join(env.XDG_STATE_HOME, file), "utf8").trim().split("\n").map(JSON.parse);
            for (const record of records) {
                assert.equal(record.env.OPENAI_API_KEY, undefined);
                assert.equal(record.env.ANTHROPIC_API_KEY, undefined);
                assert.equal(record.env.VGSHELL_RUNNER_PID, undefined);
                for (const [name, value] of Object.entries(gumWords))
                    assert.equal(record.env[name], file === "gum-calls" ? value : undefined, file + " " + name);
                assert.ok(record.args.every(arg => arg !== "-p" && arg !== "exec"), "no inference during discovery or unavailable Verify");
            }
        }
        assert.equal(fs.existsSync(path.join(env.XDG_STATE_HOME, "secret-calls")), false);
    };
    // Show accounts: four columns, one row per account, the hand-added
    // signed-in account named by its email with its plan, no id or keyed
    // value in a cell, and every row within the width.
    const table = (folder, columns) => {
        const rows = cli(folder, "table", String(columns)).trimEnd().split("\n").map(parseCsv);
        const accounts = JSON.parse(cli(folder, "list"));
        assert.equal(rows.length, accounts.length + 1, "a header and a row per account");
        for (const row of rows) {
            assert.equal(row.length, 4);
            assert.ok(row.reduce((sum, cell) => sum + chars(cell), 0) + frame(4) <= columns, "fits " + columns + ": " + row);
            for (const cell of row) assert.doesNotMatch(cell, /=|cli:|keyring:|local:/);
            for (const cell of row) assert.doesNotMatch(cell, HASH);
        }
        for (const account of accounts) assert.equal(rows.some(row => row.includes(account.state.kind)), false,
            "status in words, not the state " + account.state.kind);
        return rows;
    };
    const wide = folder => {
        const rows = table(folder, 120);
        assert.ok(rows.some(row => row[1] === "team@example.invalid" && row[3] === "pro"), "the account is its email, with its plan");
        assert.equal(rows.some(row => row[1] === "my-account"), false, "an account with an email is not named by its label");
    };
    const narrow = folder => {
        const rows = table(folder, 40);
        assert.ok(rows.flat().some(cell => cell.endsWith("…")), "a cut cell ends with an ellipsis");
    };
    // Choices: one tab per line, its value an account id, its label free of
    // ids and within the width after the cursor.
    const choices = folder => {
        const ids = JSON.parse(cli(folder, "list")).map(account => account.id);
        const lines = cli(folder, "accounts", "30").trimEnd().split("\n");
        assert.deepEqual(lines.map(line => line.split("\t")[1]), ids);
        for (const line of lines) {
            const [label, ...rest] = line.split("\t");
            assert.equal(rest.length, 1);
            assert.ok(chars(label) <= 28, label);
            assert.doesNotMatch(label, HASH);
            assert.doesNotMatch(label, /\b(cli|keyring|local|variable):/);
        }
    };
    const providerIds = (folder, kind) => cli(folder, "providers", kind, "80").trimEnd().split("\n").map(line => line.split("\t")[1]);
    check(plugin);
    wide(plugin);
    narrow(plugin);
    choices(plugin);
    // Add directory offers CLI providers, including Copilot, even when a
    // provider has no sign-in command.
    const cliIds = providerIds(plugin, "cli");
    assert.ok(cliIds.includes("claude") && cliIds.includes("codex") && cliIds.includes("copilot"));
    assert.ok(cliIds.every(id => PROVIDERS.find(row => row.id === id)?.kind === "cli"));
    // The Sign in screen offers only CLI providers with a sign-in command:
    // Copilot among them, never Pi, which has none.
    const signInProviders = folder => {
        const ids = providerIds(folder, "sign-in");
        assert.ok(ids.includes("claude") && ids.includes("codex") && ids.includes("copilot"));
        assert.equal(ids.includes("pi"), false);
        assert.ok(ids.every(id => Array.isArray(PROVIDERS.find(row => row.id === id)?.signIn)));
    };
    signInProviders(plugin);
    // Use keyring item offers the AI model key providers Add key does: key
    // rows with a model, openai among them, never the speech-only
    // ElevenLabs key or Cerebras, whose row names no model.
    const keyProviders = folder => {
        const ids = providerIds(folder, "key");
        assert.ok(ids.includes("openai"));
        for (const id of ["elevenlabs", "cerebras"]) assert.equal(ids.includes(id), false, "offered [" + id + "]");
        for (const id of ids) {
            const row = PROVIDERS.find(item => item.id === id);
            assert.ok(row && row.kind === "key" && row.probe.model !== "", "offered [" + id + "]");
        }
    };
    keyProviders(plugin);
    // A width that is no integer from 20 to 1000 is refused, each rule by
    // its own row.
    const widthRows = { format: ["3e1", "8x"], minimum: ["0", "19"], maximum: ["1001"] };
    const widths = (folder, rule) => {
        for (const value of widthRows[rule]) {
            const result = cp.spawnSync("node", [path.join(folder, "backend/accounts.js"), "--tree", tree, "table", value],
                { env, encoding: "utf8", timeout: 15000 });
            assert.deepEqual([result.status, result.stderr], [1, "jarvis-accounts: arguments=width\n"], "table " + value);
        }
        const providers = cp.spawnSync("node", [path.join(folder, "backend/accounts.js"), "--tree", tree, "providers", "cli", "0"],
            { env, encoding: "utf8", timeout: 15000 });
        assert.deepEqual([providers.status, providers.stderr], [1, "jarvis-accounts: arguments=width\n"], "providers cli 0");
    };
    for (const rule of Object.keys(widthRows)) widths(plugin, rule);
    let controls = 0;
    const control = async (file, name, needle, replacement, assertion) => { await mutant(file, name, needle, replacement, assertion); controls++; };
    await control("tui/accounts.sh", "tui-wrong-directory", 'accounts add "$selected" "$dir" "$label"',
        'accounts add "$selected" "$HOME" "$label"', check);
    await control("tui/accounts.sh", "tui-no-explicit-verify", 'accounts verify "$selected" user',
        'accounts verify "$selected" automatic', check);
    await control("tui/accounts.sh", "tui-result-on-screen", 'accounts verify "$selected" user "$model" >>"$log"',
        'accounts verify "$selected" user "$model"', check);
    await control("backend/accounts.js", "table-frame", "const TABLE_FRAME = 3 * TABLE_COLUMNS.length + 1;",
        "const TABLE_FRAME = 2 * TABLE_COLUMNS.length;", narrow);
    await control("backend/accounts.js", "table-label", "if (account.email) return account.email;", "", wide);
    await control("AccountStatus.js", "table-state", 'case "signed-in": return "Signed in";', 'case "signed-in": return state;', wide);
    await control("tui/accounts.sh", "screen-no-table", 'gum table --print <<<"$table"', ':', check);
    await control("tui/accounts.sh", "screen-width", 'columns="$(vgs_tui_columns)"', 'columns=1000', check);
    await control("tui/accounts.sh", "gum-words", 'gum() { "${child_env[@]}" "${gum_env[@]}" gum "$@"; }',
        'gum() { "${child_env[@]}" gum "$@"; }', check);
    await control("tui/accounts.sh", "gum-own-list", 'vgs_tui_gum_env gum_env', OWN_GUM_LIST, check);
    await control("tui/accounts.sh", "gum-words-to-node", '"${child_env[@]}" node "$program"',
        '"${child_env[@]}" "${gum_env[@]}" node "$program"', check);
    await control("AccountProviders.js", "width-format", '!/^[0-9]{1,4}$/.test(text)', 'false', folder => widths(folder, "format"));
    await control("AccountProviders.js", "width-minimum", 'return value >= MIN_WIDTH && value <= MAX_WIDTH ? value : null;',
        'return value <= MAX_WIDTH ? value : null;', folder => widths(folder, "minimum"));
    await control("AccountProviders.js", "width-maximum", 'return value >= MIN_WIDTH && value <= MAX_WIDTH ? value : null;',
        'return value >= MIN_WIDTH ? value : null;', folder => widths(folder, "maximum"));
    await control("backend/accounts.js", "choice-id", 'lines = judge.accounts.map(account => choiceLine(label(account.provider) + ": "',
        'lines = judge.accounts.map(account => choiceLine(account.id + ": "', choices);
    await control("AccountProviders.js", "speech-key-offered", 'if (kind === "key") return modelKeyProvider(row);',
        'if (kind === "key") return keyProvider(row);', keyProviders);
    await control("AccountProviders.js", "model-less-offered", 'return row.kind === "key" && modelProvider(row);',
        'return row.kind === "key";', keyProviders);
    await control("AccountProviders.js", "choice-fit", "fitText(label, width - CHOICE_CURSOR)", "label", choices);
    queue(["verify", "first", "", "no", "close"]);
    fs.rmSync(log, { force: true });
    const cancelled = run(plugin);
    assert.equal(cancelled.status, 0);
    assert.doesNotMatch(fs.readFileSync(log, "utf8"), /"kind":"unavailable"/);

    // Synthetic vendor login. A successful process must also report a
    // signed-in account before the folder is remembered or offered.
    for (const [vendor, args] of [["claude", ["auth", "login"]], ["codex", ["login"]]]) {
        const file = path.join(process.env.JARVIS_TEST_ROOT, "standins", vendor);
        const source = fs.readFileSync(file, "utf8");
        const needle = 'record("cli-calls");';
        assert.equal(source.split(needle).length - 1, 1);
        fs.writeFileSync(file, source.replace(needle, needle + `
if(JSON.stringify(args)===${JSON.stringify(JSON.stringify(args))}) {
    const outcome=mode("sign-in-mode","success");
    console.log("fixture-login-code-private");
    if(outcome==="failure") process.exit(7);
    if(outcome!=="no-account") fs.writeFileSync(path.join(state,"${vendor}-mode"),"signed-in");
    if(outcome==="failure-signed-in") process.exit(7);
    process.exit(0);
}
`));
    }
    // Copilot has no status command; its login writes COPILOT_HOME's
    // config.json, the marker its sign-in is proved by.
    fs.writeFileSync(path.join(process.env.JARVIS_TEST_ROOT, "standins/copilot"), `#!/usr/bin/env node
const fs=require("node:fs"), path=require("node:path");
const state=process.env.XDG_STATE_HOME, args=process.argv.slice(2);
fs.appendFileSync(path.join(state,"cli-calls"), JSON.stringify({args,env:process.env})+"\\n");
if(JSON.stringify(args)!==JSON.stringify(["login"])) process.exit(9);
const outcome=fs.readFileSync(path.join(state,"sign-in-mode"),"utf8").trim();
console.log("fixture-login-code-private");
if(outcome==="failure") process.exit(7);
if(outcome!=="no-account") fs.writeFileSync(path.join(process.env.COPILOT_HOME,"config.json"),"{}");
if(outcome==="failure-signed-in") process.exit(7);
`, { mode: 0o700 });
    const records = () => fs.readFileSync(path.join(env.XDG_STATE_HOME, "cli-calls"), "utf8")
        .trim().split("\n").map(JSON.parse);
    const accountFile = path.join(env.XDG_STATE_HOME, "vgshell/jarvis/accounts.json");
    const clearSignIns = () => {
        fs.rmSync(accountFile, { force: true });
        for (const name of fs.readdirSync(env.HOME))
            if (/^\.(claude|codex|copilot)(-|$)/.test(name)) fs.rmSync(path.join(env.HOME, name), { recursive: true, force: true });
    };
    const signIn = (folder, vendor, selection, label, outcome, confirm = "yes", roots = {}) => {
        fs.writeFileSync(path.join(env.XDG_STATE_HOME, vendor + "-mode"), "found");
        fs.writeFileSync(path.join(env.XDG_STATE_HOME, "sign-in-mode"), outcome);
        queue([vendor, selection, ...(selection === "new" ? [label] : []), confirm]);
        return cp.spawnSync("python3", [path.join(tree, "scripts/fixtures/jarvis/accounts-tui.py"),
            path.join(folder, "tui/sign-in.sh"), path.join(tree, "bin/lib/tui.sh"), folder], {
            env: { ...env, ...roots }, encoding: "utf8", timeout: 20000 });
    };
    const successfulSignIn = folder => {
        for (const [vendor, argv, variable] of [["claude", ["auth", "login"], "CLAUDE_CONFIG_DIR"],
            ["codex", ["login"], "CODEX_HOME"], ["copilot", ["login"], "COPILOT_HOME"]]) {
          clearSignIns();
          for (const [label, suffix] of [["login-account", ""], ["work_2", "-work_2"]]) {
            const target = path.join(env.HOME, "." + vendor + suffix);
            const before = records().length;
            const gumBefore = fs.readFileSync(path.join(env.XDG_STATE_HOME, "gum-calls"), "utf8").trim().split("\n").length;
            const result = signIn(folder, vendor, "new", label, "success");
            assert.equal(result.status, 0, result.stdout + result.stderr);
            assert.equal(result.error, undefined);
            assert.ok(result.stdout.includes("fixture-login-code-private"), "vendor output stays on the terminal");
            assert.equal(fs.readFileSync(log, "utf8").includes("fixture-login-code-private"), false, "no vendor login output in log");
            const saved = JSON.parse(fs.readFileSync(accountFile));
            assert.ok(saved.some(item => item.provider === vendor && item.directory === target && item.label === label));
            assert.equal(saved.filter(item => item.provider === vendor).length, suffix === "" ? 1 : 2);
            const calls = fs.readFileSync(path.join(env.XDG_STATE_HOME, "gum-calls"), "utf8").trim().split("\n").slice(gumBefore).map(JSON.parse);
            assert.equal(calls.filter(item => item.args[0] === "input").length, 1, "new account asks for a name only");
            const confirmation = calls.find(item => item.args[0] === "confirm");
            assert.ok(confirmation?.args.at(-1).includes("~/." + vendor + suffix), "confirmation shows the derived folder");
            const login = records().slice(before).find(item => JSON.stringify(item.args) === JSON.stringify(argv));
            assert.ok(login, "the vendor login ran");
            assert.equal(login.env[variable], target);
            assert.equal(login.env.OPENAI_API_KEY, undefined);
            assert.equal(login.env.VGSHELL_RUNNER_PID, undefined);
            const accounts = JSON.parse(cli(folder, "list"));
            const account = accounts.find(item => item.source.directory === target);
            assert.equal(account.state.kind, vendor === "copilot" ? "unchecked" : "signed-in");
            const presence = Object.fromEntries(PROVIDERS.filter(row => row.variable).map(row => [row.variable, false]));
            const listsBefore = records().filter(item => item.args.includes("--input-format")).length;
            const shown = JSON.parse(cli(folder, "presence", JSON.stringify(presence)));
            assert.ok(shown.brains.some(item => item.value === account.id), "signed-in account offered as AI model");
            // The account answer starts no model list read: the Jarvis page
            // asks for the chosen sign-in's list in a request of its own.
            assert.equal(records().filter(item => item.args.includes("--input-format")).length, listsBefore, "no list read in the account answer");
            if (vendor === "claude") {
                const status = () => records().filter(item => JSON.stringify(item.args) === JSON.stringify(["auth", "status"]));
                const statusBefore = status().length;
                assert.equal(JSON.parse(cli(folder, "models", account.id)).kind, "read");
                assert.equal(records().filter(item => item.args.includes("--input-format")).length, listsBefore + 1, "one list read for the request");
                // The request judges its own sign-in alone: one status
                // command, for its folder, whatever other accounts exist.
                assert.deepEqual(status().slice(statusBefore).map(item => item.env[variable]), [target], "the list read runs its sign-in's status command and no other");
            }
          }
        }
    };
    const themedSignIn = folder => {
        clearSignIns();
        const colors = { GUM_CHOOSE_SELECTED_BACKGROUND: "#124578",
            GUM_INPUT_PROMPT_FOREGROUND: "#2468ab", GUM_CONFIRM_SELECTED_BACKGROUND: "#3579bc",
            FOREGROUND: "#13579b", BACKGROUND: "#2468ac", BORDER_FOREGROUND: "#369cf0" };
        const terminal = { TERM: "xterm-kitty", COLORTERM: "truecolor" };
        const gumBefore = fs.readFileSync(path.join(env.XDG_STATE_HOME, "gum-calls"), "utf8").trim().split("\n").length;
        const vendorBefore = records().length;
        const from = nodeCalls().length - 1;
        const result = signIn(folder, "claude", "new", "themed", "success", "yes", { ...colors, ...terminal });
        assert.equal(result.status, 0, result.stdout + result.stderr);
        for (const names of helperNames(from))
            for (const name of [...Object.keys(colors), ...Object.keys(terminal)])
                assert.equal(names.has(name), false, "the node helper got " + name);
        const calls = fs.readFileSync(path.join(env.XDG_STATE_HOME, "gum-calls"), "utf8").trim().split("\n")
            .slice(gumBefore).map(JSON.parse);
        for (const kind of ["choose", "input", "confirm"]) {
            const prompts = calls.filter(item => item.args[0] === kind);
            assert.ok(prompts.length > 0, "the themed prompt ran: " + kind);
            for (const prompt of prompts) {
                for (const [name, value] of Object.entries(colors)) assert.equal(prompt.env[name], value);
                for (const [name, value] of Object.entries(terminal)) assert.equal(prompt.env[name], value);
            }
        }
        const vendors = records().slice(vendorBefore);
        assert.ok(vendors.some(item => JSON.stringify(item.args) === JSON.stringify(["auth", "login"])));
        for (const vendor of vendors) {
            for (const name of Object.keys(colors)) assert.equal(vendor.env[name], undefined);
            for (const name of Object.keys(terminal)) assert.equal(vendor.env[name], undefined);
        }
    };
    themedSignIn(plugin);
    const incompleteSignIn = folder => {
        for (const vendor of ["claude", "copilot"])
        for (const outcome of ["failure", "failure-signed-in", "no-account"] ) {
            clearSignIns();
            const result = signIn(folder, vendor, "new", "login-account", outcome);
            assert.equal(result.status, 1, vendor + " " + outcome);
            const terminal = result.stdout + result.stderr;
            assert.equal(terminal.includes(log), false, "failed login does not refer to a log without its details");
            assert.equal(terminal.includes(log.replace(env.HOME, "~")), false, "the abbreviated log path is also absent");
            assert.equal(fs.existsSync(accountFile), false, "failed or unconfirmed login is not remembered");
        }
    };
    successfulSignIn(plugin);
    incompleteSignIn(plugin);
    const existingSignIn = folder => {
      for (const [suffix, registered] of [["work", true], ["a".repeat(65), false]]) {
        clearSignIns();
        const target = path.join(env.HOME, ".claude-" + suffix);
        fs.mkdirSync(target);
        if (registered) cli(folder, "add", "claude", target, suffix);
        const options = cli(folder, "sign-in-folders", "claude", "1000").trimEnd().split("\n").map(line => line.split("\t"));
        const option = options.find(([label]) => label.includes("~/.claude-" + suffix));
        assert.ok(option, "a discovered folder is offered for signing in again");
        const before = records().length;
        const result = signIn(folder, "claude", option[1], "", "success");
        assert.equal(result.status, 0, result.stdout + result.stderr);
        assert.deepEqual(JSON.parse(fs.readFileSync(accountFile)), [{ provider: "claude", directory: target, label: suffix.slice(0, 60) }]);
        assert.equal(records().slice(before).find(item => JSON.stringify(item.args) === JSON.stringify(["auth", "login"]))?.env.CLAUDE_CONFIG_DIR, target);
      }
    };
    existingSignIn(plugin);
    const explicitSignIn = folder => {
        const variables = ["CLAUDE_CONFIG_DIR", "CODEX_HOME", "COPILOT_HOME"];
        for (const [vendor, variable, argv] of [["claude", "CLAUDE_CONFIG_DIR", ["auth", "login"]],
            ["codex", "CODEX_HOME", ["login"]], ["copilot", "COPILOT_HOME", ["login"]]]) {
            clearSignIns();
            const target = path.join(env.HOME, "manual-" + vendor);
            fs.mkdirSync(target, { recursive: true });
            const roots = { [variable]: target };
            const choices = cp.spawnSync("node", [path.join(folder, "backend/accounts.js"), "--tree", tree,
                "sign-in-folders", vendor, "1000"], { env: { ...env, ...roots }, encoding: "utf8", timeout: 15000 });
            assert.equal(choices.status, 0, choices.stderr);
            const option = choices.stdout.trimEnd().split("\n").map(line => line.split("\t"))
                .find(([label]) => label.includes("~/manual-" + vendor));
            assert.ok(option, "explicit configured root is offered");
            const before = records().length;
            const result = signIn(folder, vendor, option[1], "", "success", "yes", roots);
            assert.equal(result.status, 0, result.stdout + result.stderr);
            assert.deepEqual(JSON.parse(fs.readFileSync(accountFile)), [{ provider: vendor, directory: target, label: "manual-" + vendor }]);
            const login = records().slice(before).find(item => JSON.stringify(item.args) === JSON.stringify(argv));
            assert.equal(login?.env[variable], target);
            for (const other of variables.filter(name => name !== variable)) assert.equal(login.env[other], undefined, other);
        }
    };
    explicitSignIn(plugin);
    const safeName = folder => {
        clearSignIns();
        for (const label of ["../escape", "a/b", "a\\b", "", ".hidden", "a\tbad", "a".repeat(61)]) {
            const result = cp.spawnSync("node", [path.join(folder, "backend/accounts.js"), "--tree", tree,
                "sign-in-entry", "claude", "new", label], { env, encoding: "utf8", timeout: 15000 });
            assert.equal(result.status, 1, JSON.stringify(label));
            assert.equal(result.stderr, "jarvis-accounts: sign-in=name-invalid\n");
        }
    };
    safeName(plugin);
    const cancelledSignIn = folder => {
        clearSignIns();
        const before = records().length;
        const result = signIn(folder, "claude", "new", "work", "success", "no");
        assert.equal(result.status, 130);
        assert.equal(records().slice(before).some(item => JSON.stringify(item.args) === JSON.stringify(["auth", "login"])), false);
        assert.equal(fs.existsSync(accountFile), false);
    };
    cancelledSignIn(plugin);
    const unavailableFolder = folder => {
        clearSignIns();
        fs.mkdirSync(path.join(env.HOME, ".claude-work"));
        const result = cp.spawnSync("node", [path.join(folder, "backend/accounts.js"), "--tree", tree,
            "sign-in-entry", "claude", "cli:" + "0".repeat(32), ""], { env, encoding: "utf8", timeout: 15000 });
        assert.equal(result.status, 1);
        assert.equal(result.stderr, "jarvis-accounts: sign-in=folder-unavailable\n");
    };
    unavailableFolder(plugin);
    const nameInUse = folder => {
        clearSignIns();
        fs.mkdirSync(path.join(env.HOME, ".claude-work"));
        const result = cp.spawnSync("node", [path.join(folder, "backend/accounts.js"), "--tree", tree,
            "sign-in-entry", "claude", "new", "work"], { env, encoding: "utf8", timeout: 15000 });
        assert.equal(result.status, 1);
        assert.equal(result.stderr, "jarvis-accounts: sign-in=name-in-use\n");
    };
    nameInUse(plugin);
    const partialFolders = folder => {
        const held = env.XDG_CONFIG_HOME + "-held";
        fs.renameSync(env.XDG_CONFIG_HOME, held);
        fs.symlinkSync(env.HOME, env.XDG_CONFIG_HOME);
        try {
            const result = cp.spawnSync("node", [path.join(folder, "backend/accounts.js"), "--tree", tree,
                "sign-in-entry", "claude", "new", "work"], { env, encoding: "utf8", timeout: 15000 });
            assert.equal(result.status, 1);
            assert.equal(result.stderr, "jarvis-accounts: sign-in=search-incomplete\n");
        } finally { fs.unlinkSync(env.XDG_CONFIG_HOME); fs.renameSync(held, env.XDG_CONFIG_HOME); }
    };
    partialFolders(plugin);
    const terminalRequired = folder => {
        fs.writeFileSync(path.join(env.XDG_STATE_HOME, "sign-in-mode"), "success");
        const result = cp.spawnSync("node", [path.join(folder, "backend/accounts.js"), "--tree", tree,
            "sign-in", "claude", hand, "login-account"], { env, encoding: "utf8", timeout: 15000 });
        assert.equal(result.status, 1, "sign-in starts only from an interactive terminal");
        assert.equal(result.stdout, "", "no vendor output without a terminal");
    };
    terminalRequired(plugin);
    // Pi has no sign-in command, so every sign-in verb refuses it.
    const piRefused = folder => {
        for (const [verb, args] of [
            ["sign-in-folders", ["pi", "1000"]],
            ["sign-in-entry", ["pi", "new", "work"]],
            ["sign-in", ["pi", hand, "work"]]
        ]) {
            const before = records().length;
            const result = cp.spawnSync("node", [path.join(folder, "backend/accounts.js"), "--tree", tree, verb, ...args],
                { env, encoding: "utf8", timeout: 15000 });
            assert.equal(result.status, 1, verb);
            if (verb !== "sign-in") assert.equal(result.stderr, "jarvis-accounts: sign-in=provider\n");
            assert.equal(records().length, before, "no vendor program for " + verb);
        }
    };
    piRefused(plugin);
    await control("backend/Accounts.js", "sign-in-terminal-required", 'if (process.stdin.isTTY !== true)',
        'if (false)', terminalRequired);
    await control("AccountProviders.js", "sign-in-provider-list", 'if (kind === "sign-in") return row.kind === "cli" && Array.isArray(row.signIn);',
        'if (kind === "sign-in") return row.kind === "cli";', signInProviders);
    await control("AccountProviders.js", "sign-in-copilot-row", 'command: null, signIn: ["copilot", "login"] }',
        'command: null }', signInProviders);
    await control("AccountProviders.js", "sign-in-copilot-argv", 'signIn: ["copilot", "login"]',
        'signIn: ["copilot", "auth", "login"]', successfulSignIn);
    await control("backend/Accounts.js", "sign-in-copilot-marker", '(account.state.kind === "unchecked" && account.marker === "present")',
        'account.state.kind === "unchecked"', incompleteSignIn);
    await control("backend/Accounts.js", "sign-in-provider-refusal", 'if (row.kind !== "cli" || !Array.isArray(row.signIn)) fail("sign-in=provider");',
        'if (row.kind !== "cli") fail("sign-in=provider");', piRefused);
    await control("tui/sign-in.sh", "sign-in-gum-words", 'gum() { "${child_env[@]}" "${gum_env[@]}" gum "$@"; }',
        'gum() { "${child_env[@]}" gum "$@"; }', themedSignIn);
    await control("tui/sign-in.sh", "sign-in-gum-own-list", 'vgs_tui_gum_env gum_env', OWN_GUM_LIST, themedSignIn);
    await control("tui/sign-in.sh", "sign-in-gum-words-to-node", '"${child_env[@]}" node "$program" --tree "$tree" sign-in "$selected"',
        '"${child_env[@]}" "${gum_env[@]}" node "$program" --tree "$tree" sign-in "$selected"', themedSignIn);
    await control("tui/sign-in.sh", "sign-in-picked-directory", 'sign-in "$selected" "$dir" "$label"',
        'sign-in "$selected" "$HOME" "$label"', successfulSignIn);
    await control("backend/Accounts.js", "sign-in-default-folder", 'folders.length === 0 ? "" : "-" + label',
        '"-" + label', successfulSignIn);
    await control("backend/accounts.js", "presence-list-read", "await Promise.all([judge.readEmails(), judge.readModels()]);\n        value = judge.status();",
        "await Promise.all([judge.readEmails(), judge.readModels(), ...judge.accounts.map(item => judge.readOffers(item.id))]);\n        value = judge.status();", successfulSignIn);
    await control("backend/accounts.js", "models-one-status", "value = await judge.readOffers(args[1]);",
        "judge.discover();\n        value = await judge.readOffers(args[1]);", successfulSignIn);
    await control("backend/Accounts.js", "sign-in-additional-folder", 'folders.length === 0 ? "" : "-" + label',
        '""', successfulSignIn);
    await control("backend/Accounts.js", "sign-in-existing-folder", 'directory: entry.directory, label: entry.label };',
        'directory: this.home, label: entry.label };', existingSignIn);
    await control("backend/Accounts.js", "sign-in-reuse-registration", 'if (index < 0) entries.push(entry); else entries[index] = entry;',
        'entries.push(entry);', existingSignIn);
    await control("backend/Accounts.js", "sign-in-discovered-label", 'label: item.label.slice(0, 60),',
        'label: item.label,', existingSignIn);
    await control("tui/sign-in.sh", "sign-in-explicit-roots", 'CLAUDE_CONFIG_DIR="${CLAUDE_CONFIG_DIR:-}" CODEX_HOME="${CODEX_HOME:-}" COPILOT_HOME="${COPILOT_HOME:-}"',
        'CLAUDE_CONFIG_DIR="" CODEX_HOME="" COPILOT_HOME=""', explicitSignIn);
    await control("tui/sign-in.sh", "sign-in-copilot-root", 'COPILOT_HOME="${COPILOT_HOME:-}"', 'COPILOT_HOME=""', explicitSignIn);
    await control("tui/sign-in.sh", "sign-in-no-manual-folder", 'label="$(vgs_tui_input --header "A name for this account"',
        'dir="$(vgs_tui_input)"; label="$(vgs_tui_input --header "A name for this account"', successfulSignIn);
    await control("backend/Accounts.js", "sign-in-safe-name", '!/^[A-Za-z0-9][A-Za-z0-9_-]{0,59}$/.test(label)',
        'false', safeName);
    await control("tui/sign-in.sh", "sign-in-confirmed-folder", 'vgs_tui_confirm "Sign in to $label using $shown_dir?" || exit 130',
        ':', cancelledSignIn);
    await control("backend/Accounts.js", "sign-in-name-in-use", 'if (folders.some(item => item.directory === target))',
        'if (false)', nameInUse);
    await control("backend/Accounts.js", "sign-in-complete-search", 'if (found.partial)', 'if (false)', partialFolders);
    await control("backend/Accounts.js", "sign-in-selected-folder", 'folders.find(item => item.id === selected)',
        'folders[0]', unavailableFolder);
    await control("backend/Accounts.js", "sign-in-account-confirmed", 'if (!signedIn)',
        'if (false)', incompleteSignIn);
    await control("backend/Accounts.js", "sign-in-process-failed", 'result.error || result.signal || result.status !== 0',
        'result.error || result.signal', incompleteSignIn);
    await control("tui/sign-in.sh", "sign-in-empty-log-promise", 'vgs_tui_error "Sign in did not complete.";',
        'vgs_tui_failed "$log" "Sign in did not complete.";', incompleteSignIn);
    console.log("test-jarvis-accounts-tui: ok controls=" + controls);
});
