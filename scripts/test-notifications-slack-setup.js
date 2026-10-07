#!/usr/bin/env node
// Only fixture openers and presenters run. Controls plant message access
// and the generic Apps URL used by the former setup entry point.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const cp = require("node:child_process");
const plugin = path.resolve(__dirname, "../shell/plugins/vgs.notifications");
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "vgs-slack-setup-"));
function scopes(manifest) {
    assert.deepEqual(Object.keys(manifest.oauth_config.scopes), ["user"]);
    assert.deepEqual(manifest.oauth_config.scopes.user.slice().sort(), ["emoji:read", "team:read", "users:read"]);
    assert.equal(manifest.features, undefined);
}
function creationUrl(args, suppliedManifest) {
    assert.equal(args.length, 1);
    const url = new URL(args[0]);
    assert.equal(url.origin, "https://api.slack.com");
    assert.equal(url.pathname, "/apps");
    assert.deepEqual([...url.searchParams.keys()].sort(), ["manifest_json", "new_app"]);
    assert.equal(url.searchParams.get("new_app"), "1");
    assert.equal(url.searchParams.get("manifest_json"), suppliedManifest);
    scopes(JSON.parse(url.searchParams.get("manifest_json")));
}
try {
    const suppliedManifest = fs.readFileSync(path.join(plugin, "slack-app.json"), "utf8");
    const manifest = JSON.parse(suppliedManifest);
    scopes(manifest);
    const control = structuredClone(manifest);
    control.oauth_config.scopes.user.push("channels:history");
    assert.throws(() => scopes(control), assert.AssertionError);
    const shim = path.join(scratch, "bin");
    fs.mkdirSync(shim);
    const library = path.join(scratch, "tui.sh");
    fs.writeFileSync(library, 'vgs_tui_header() { :; }\n');
    for (const [name, source] of Object.entries({
        "xdg-open": '#!/bin/bash\nprintf "%s\\n" "$@" >"$SETUP_SCRATCH/open-args"\nexit "$OPENER_STATUS"\n',
        "gum": '#!/bin/bash\nif [[ ! -f $SETUP_SCRATCH/chosen ]]; then touch "$SETUP_SCRATCH/chosen"; printf "Show details\\n"; else printf "Close\\n"; fi\n'
    })) fs.writeFileSync(path.join(shim, name), source, { mode: 0o755 });
    const script = path.join(plugin, "tui/setup-slack.sh");
    function setup(scriptPath, openerStatus = 0) {
        fs.rmSync(path.join(scratch, "chosen"), { force: true });
        return cp.spawnSync("/bin/bash", [scriptPath], {
            env: { PATH: shim + ":/usr/bin:/bin", VGS_TUI_LIB: library, SETUP_SCRATCH: scratch, OPENER_STATUS: String(openerStatus), LANG: "C.UTF-8" },
            encoding: "utf8", timeout: 10000
        });
    }
    const openedArgs = () => fs.readFileSync(path.join(scratch, "open-args"), "utf8").trim().split("\n");
    const run = setup(script);
    assert.equal(run.status, 0, run.stderr);
    creationUrl(openedArgs(), suppliedManifest);
    assert.ok(run.stdout.includes(suppliedManifest));
    const mutant = path.join(scratch, "plugin");
    fs.mkdirSync(path.join(mutant, "tui"), { recursive: true });
    fs.writeFileSync(path.join(mutant, "slack-app.json"), suppliedManifest);
    const source = fs.readFileSync(script, "utf8");
    const opener = 'xdg-open "$slack_url"';
    assert.equal(source.split(opener).length, 2);
    const mutantScript = path.join(mutant, "tui/setup-slack.sh");
    fs.writeFileSync(mutantScript, source.replace(opener, "xdg-open https://api.slack.com/apps"));
    const oldEntry = setup(mutantScript);
    assert.equal(oldEntry.status, 0, oldEntry.stderr);
    assert.throws(() => creationUrl(openedArgs(), suppliedManifest), assert.AssertionError);
    const failedOpen = setup(script, 9);
    assert.equal(failedOpen.status, 9, failedOpen.stderr);
    assert.equal(fs.existsSync(path.join(scratch, "chosen")), false);
    console.log("test-notifications-slack-setup: ok controls=2");
} finally {
    fs.rmSync(scratch, { recursive: true, force: true });
}
