#!/usr/bin/env node
"use strict";
const { assert, fs, path, cp, tree, environment, world, mutant } = require("./fixtures/jarvis/accounts-world.js");
const plugin = path.join(tree, "shell/plugins/vgs.jarvis");
const { PROVIDERS } = require(path.join(plugin, "AccountProviders.js"));

// gum table --print's rounded frame: 3 columns of border and padding per
// cell plus the closing rule.
const frame = columns => 3 * columns + 1;
const HASH = /[0-9a-f]{32}/;

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

world(async () => {
    fs.writeFileSync(path.join(process.env.JARVIS_TEST_ROOT, "standins/gum"), GUM, { mode: 0o700 });
    // The world's PATH holds no stty, which vgs_tui_columns reads the
    // terminal's width with.
    const stty = ["/usr/bin/stty", "/bin/stty"].find(file => fs.existsSync(file));
    assert.ok(stty, "stty");
    fs.symlinkSync(stty, path.join(process.env.JARVIS_TEST_ROOT, "standins/stty"));
    const env = environment();
    const hand = path.join(env.HOME, "manual-account");
    fs.mkdirSync(hand);
    const log = path.join(env.XDG_STATE_HOME, "vgshell/jarvis/setup.log");
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
            "show", "verify", "first", "", "yes", "close"]);
        const result = run(folder);
        assert.equal(result.error, undefined);
        assert.equal(result.status, 0, result.stdout + result.stderr);
        const accountFile = path.join(env.XDG_STATE_HOME, "vgshell/jarvis/accounts.json");
        const keyFile = path.join(env.XDG_STATE_HOME, "vgshell/jarvis/keys.json");
        assert.deepEqual(JSON.parse(fs.readFileSync(accountFile)), [{ provider: "claude", directory: hand, label: "my-account" }]);
        assert.deepEqual(JSON.parse(fs.readFileSync(keyFile)), [{ provider: "openai", account: "my-key", origin: "https://api.openai.com",
            attributes: { application: "other-tool", id: "api-key" } }]);
        // The first account is the absent default Claude directory: its
        // harness Verify refuses before any vendor program starts. The
        // result goes to the log, and no id or keyed line reaches the screen.
        const logged = fs.readFileSync(log, "utf8");
        assert.match(logged, /"kind":"unavailable","reason":"account-directory"/);
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
                assert.equal(record.env.VGSHELL_RUNNER_PID, undefined);
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
    // Add directory offers sign-in programs only, claude and codex among them.
    const cliIds = providerIds(plugin, "cli");
    assert.ok(cliIds.includes("claude") && cliIds.includes("codex"));
    assert.ok(cliIds.every(id => PROVIDERS.find(row => row.id === id)?.kind === "cli"));
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
    console.log("test-jarvis-accounts-tui: ok controls=" + controls);
});
