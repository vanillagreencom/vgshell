#!/usr/bin/env node
// The presentation library's calls and ordinal choices expose the guide's
// transitions without making its prose a test interface. Only fixture openers
// and an isolated, unused keyring stand-in run.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const cp = require("node:child_process");
const plugin = path.resolve(__dirname, "../shell/plugins/vgs.notifications");
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "vgs-slack-setup-"));
const script = path.join(plugin, "tui/setup-slack.sh");
const suppliedManifest = fs.readFileSync(path.join(plugin, "slack-app.json"), "utf8");
const shim = path.join(scratch, "bin");
const library = path.join(scratch, "tui.sh");
const helper = path.join(scratch, "opener.js");
const noise = ["fixture-browser-stdout", "fixture-browser-stderr"];
const initialSettings = '{"slackPhotos":false}\n';
const initialKeyring = '{"saved":true}\n';
let caseNumber = 0;
function scopes(manifest) {
    assert.deepEqual(Object.keys(manifest.oauth_config.scopes), ["user"]);
    assert.deepEqual(manifest.oauth_config.scopes.user.slice().sort(), ["emoji:read", "team:read", "users:read"]);
    assert.equal(manifest.features, undefined);
}
function creationUrl(args) {
    assert.equal(args.length, 1);
    const url = new URL(args[0]);
    assert.equal(url.origin, "https://api.slack.com");
    assert.equal(url.pathname, "/apps");
    assert.deepEqual([...url.searchParams.keys()].sort(), ["manifest_json", "new_app"]);
    assert.equal(url.searchParams.get("new_app"), "1");
    assert.equal(url.searchParams.get("manifest_json"), suppliedManifest);
    scopes(JSON.parse(url.searchParams.get("manifest_json")));
}
function caseEnv(choices, statuses = [0], preparationFails = false) {
    const root = path.join(scratch, String(++caseNumber));
    fs.mkdirSync(root);
    fs.mkdirSync(path.join(root, "vgshell"));
    fs.writeFileSync(path.join(root, "choices"), choices.join("\n") + "\n");
    fs.writeFileSync(path.join(root, "choice-index"), "0\n");
    fs.writeFileSync(path.join(root, "statuses.json"), JSON.stringify(statuses));
    fs.writeFileSync(path.join(root, "vgshell/shell.json"), initialSettings);
    fs.writeFileSync(path.join(root, "keyring.json"), initialKeyring);
    // This is an explicit stand-in PATH and environment: no display, session
    // bus or caller keyring reaches the guide or its children.
    return { root, env: {
        PATH: shim + ":/usr/bin:/bin", HOME: root, XDG_CONFIG_HOME: root,
        XDG_DATA_HOME: root, XDG_STATE_HOME: root, XDG_RUNTIME_DIR: root,
        TMPDIR: root, VGS_TEST_RUN: "1",
        VGS_TUI_LIB: library, SETUP_CASE: root, SETUP_NODE: process.execPath,
        SETUP_HELPER: helper, PREPARATION_FAILS: String(preparationFails), LANG: "C.UTF-8"
    } };
}
function result(fixture, run) {
    assert.equal(run.error, undefined);
    const read = name => fs.existsSync(path.join(fixture.root, name)) ? fs.readFileSync(path.join(fixture.root, name), "utf8") : "";
    const fields = read("trace").split("\0");
    const events = [];
    while (fields.length > 1) {
        const kind = fields.shift();
        const count = Number(fields.shift());
        events.push({ kind, args: fields.splice(0, count) });
    }
    const opens = read("opens").trim().split("\n").filter(Boolean).map(line => JSON.parse(line));
    for (const marker of noise) {
        assert.equal(run.stdout.includes(marker), false);
        assert.equal(run.stderr.includes(marker), false);
    }
    assert.equal(run.stdout.includes(suppliedManifest), false);
    assert.equal(read("vgshell/shell.json"), initialSettings);
    assert.equal(read("keyring.json"), initialKeyring);
    assert.equal(read("keyring-access"), "");
    const choices = events.filter(event => event.kind === "choose").map(event => event.args.length);
    const frames = [];
    for (const event of events) {
        if (event.kind === "clear") frames.push([]);
        else if (frames.length) frames.at(-1).push(event.kind);
    }
    return { ...run, events, opens, choices, frames };
}
function setup(choices, statuses, preparationFails) {
    const fixture = caseEnv(choices, statuses, preparationFails);
    return result(fixture, cp.spawnSync("/bin/bash", [script], {
        env: fixture.env, encoding: "utf8", timeout: 10000
    }));
}
async function cancelHeldOpener() {
    const fixture = caseEnv([1], ["hold"]);
    const guide = cp.spawn("/bin/bash", [script], {
        env: fixture.env, detached: true, stdio: ["ignore", "pipe", "pipe", "pipe"]
    });
    let stdout = "", stderr = "", openerReady = false;
    guide.stdout.setEncoding("utf8").on("data", chunk => { stdout += chunk; });
    guide.stderr.setEncoding("utf8").on("data", chunk => { stderr += chunk; });
    const ended = new Promise((resolve, reject) => {
        guide.once("error", reject);
        guide.once("close", (status, signal) => resolve({ status, signal }));
    });
    const deadline = setTimeout(() => {
        try { process.kill(-guide.pid, "SIGKILL"); } catch (error) { if (error.code !== "ESRCH") throw error; }
    }, 10000);
    guide.stdio[3].setEncoding("utf8").once("data", chunk => {
        assert.equal(JSON.parse(chunk).kind, "opener-ready");
        openerReady = true;
        // Ctrl+C reaches the foreground process group, as it does in the
        // floating terminal. The opener never releases its hold itself.
        process.kill(-guide.pid, "SIGINT");
    });
    try {
        const run = await ended;
        assert.equal(openerReady, true);
        assert.equal(run.signal, null);
        assert.equal(fs.existsSync(path.join(fixture.root, "opener-stopped")), true);
        return result(fixture, { ...run, stdout, stderr });
    } finally {
        clearTimeout(deadline);
    }
}
(async () => {
    try {
        fs.mkdirSync(shim);
        fs.writeFileSync(library, `
_record() { printf '%s\\0' "$1" "$(($# - 1))" "\${@:2}" >>"$SETUP_CASE/trace"; }
vgs_tui_clear() { _record clear; printf '\\033[2J\\033[H'; }
vgs_tui_header() { _record header; printf '%s\\n' "$@"; }
vgs_tui_text() { _record text; printf '%s\\n' "$@"; }
vgs_tui_step() { _record step; printf '%s\\n' "$@"; }
vgs_tui_cancelled() { _record cancelled; printf '%s\\n' "$@"; }
vgs_tui_choose() {
  local arg after=0 index answer options=() plan=()
  for arg; do
    if [[ $after == 1 ]]; then options+=("$arg"); elif [[ $arg == -- ]]; then after=1; fi
  done
  _record choose "\${options[@]}"
  read -r index <"$SETUP_CASE/choice-index"
  mapfile -t plan <"$SETUP_CASE/choices"
  printf '%s\\n' "$((index + 1))" >"$SETUP_CASE/choice-index"
  answer="\${plan[index]:-missing}"
  [[ $answer != cancel ]] || return 130
  [[ $answer =~ ^[1-9][0-9]*$ ]] && (( answer <= \${#options[@]} )) || return 97
  printf '%s\\n' "\${options[answer - 1]}"
}
`);
        fs.writeFileSync(helper, `
const fs = require('node:fs');
const path = require('node:path');
const root = process.env.SETUP_CASE;
const target = path.join(root, 'opens');
const count = fs.existsSync(target) ? fs.readFileSync(target, 'utf8').trim().split('\\n').length : 0;
fs.appendFileSync(target, JSON.stringify(process.argv.slice(2)) + '\\n');
process.stdout.write(${JSON.stringify(noise[0] + "\n")});
process.stderr.write(${JSON.stringify(noise[1] + "\n")});
const status = JSON.parse(fs.readFileSync(path.join(root, 'statuses.json'), 'utf8'))[count];
if (status === 'hold') {
    const timer = setInterval(() => {}, 1000);
    process.on('SIGINT', () => {
        clearInterval(timer);
        fs.writeFileSync(path.join(root, 'opener-stopped'), 'SIGINT\\n');
        process.exit(130);
    });
    fs.writeSync(3, JSON.stringify({kind: 'opener-ready'}) + '\\n');
} else {
    process.exit(status === undefined ? 96 : status);
}
`);
        for (const [name, source] of Object.entries({
            "xdg-open": '#!/bin/bash\nexec "$SETUP_NODE" "$SETUP_HELPER" "$@"\n',
            "node": '#!/bin/bash\nif [[ $PREPARATION_FAILS == true ]]; then printf "fixture-preparation-stderr\\n" >&2; exit 8; fi\nexec "$SETUP_NODE" "$@"\n',
            "secret-tool": '#!/bin/bash\nprintf "called\\n" >>"$SETUP_CASE/keyring-access"\nexit 95\n',
            "gum": '#!/bin/bash\nexit 94\n'
        })) fs.writeFileSync(path.join(shim, name), source, { mode: 0o755 });

        const manifest = JSON.parse(suppliedManifest);
        scopes(manifest);
        const control = structuredClone(manifest);
        control.oauth_config.scopes.user.push("channels:history");
        assert.throws(() => scopes(control), assert.AssertionError);

        for (const choice of [2, "cancel"]) {
            const cancelled = setup([choice]);
            assert.equal(cancelled.status, 130, cancelled.stderr);
            assert.deepEqual(cancelled.opens, []);
            assert.equal(cancelled.events.at(-1).kind, "cancelled");
        }
        const success = setup([1, 1, 1]);
        assert.equal(success.status, 0, success.stderr);
        assert.deepEqual(success.choices, [2, 4, 1]);
        assert.equal(success.opens.length, 1);
        creationUrl(success.opens[0]);
        // The old entry point's generic Apps URL is planted into a recorded
        // argv. This control exercises the same judge as the real opener data.
        const recordedControl = success.opens[0].slice();
        recordedControl[0] = "https://api.slack.com/apps";
        assert.throws(() => creationUrl(recordedControl), assert.AssertionError);

        const routes = [
            { choices: [1, 1, 1, 1], statuses: [9, 0], counts: [2, 3, 4, 1], opens: 2, status: 0 },
            { choices: [1, 1, 2, 1, 1], statuses: [9, 7], counts: [2, 3, 3, 4, 1], opens: 2, status: 0 },
            { choices: [1, 2, 1, 1], statuses: [9], counts: [2, 3, 4, 1], opens: 1, status: 0 },
            { choices: [1, 3], statuses: [9], counts: [2, 3], opens: 1, status: 130 },
            { choices: [1, 2, 1, 1], statuses: [0, 0], counts: [2, 4, 4, 1], opens: 2, status: 0 },
            { choices: [1, 2, 2, 1, 1], statuses: [0, 9], counts: [2, 4, 3, 4, 1], opens: 2, status: 0 },
            { choices: [1, 3, 1, 1, 1], statuses: [0], counts: [2, 4, 2, 4, 1], opens: 1, status: 0 },
            { choices: [1, 3, 2, 1], statuses: [0], counts: [2, 4, 2, 1], opens: 1, status: 0 }
        ];
        for (const row of routes) {
            const run = setup(row.choices, row.statuses);
            assert.equal(run.status, row.status, run.stderr);
            assert.deepEqual(run.choices, row.counts);
            assert.equal(run.opens.length, row.opens);
            for (const args of run.opens) creationUrl(args);
            for (const args of run.opens) assert.deepEqual(args, success.opens[0]);
            // Every instructions view is a fresh screen with the five spaced
            // library step blocks, including after reopening or approval.
            for (const frame of run.frames.filter(frame => frame.includes("step"))) {
                assert.equal(frame.filter(kind => kind === "step").length, 5);
                assert.equal(frame.filter(kind => kind === "header").length, 1);
            }
        }
        const preparationFailure = setup([1, 1], [0], true);
        assert.equal(preparationFailure.status, 69, preparationFailure.stderr);
        assert.deepEqual(preparationFailure.opens, []);
        assert.deepEqual(preparationFailure.choices, [2, 1]);
        assert.equal(preparationFailure.stderr, "");
        const held = await cancelHeldOpener();
        assert.equal(held.status, 130, held.stderr);
        assert.equal(held.opens.length, 1);
        assert.deepEqual(held.choices, [2]);
        assert.equal(held.events.at(-1).kind, "cancelled");
        console.log("test-notifications-slack-setup: ok controls=2");
    } finally {
        fs.rmSync(scratch, { recursive: true, force: true });
    }
})().catch(error => { console.error(error); process.exitCode = 1; });
