#!/usr/bin/env node
// Only fixture openers and a fixture clipboard run. The permission control
// plants permission to read messages and must fail the same contract.
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
try {
    const manifest = JSON.parse(fs.readFileSync(path.join(plugin, "slack-app.json"), "utf8"));
    scopes(manifest);
    const control = structuredClone(manifest);
    control.oauth_config.scopes.user.push("channels:history");
    assert.throws(() => scopes(control), assert.AssertionError);
    const shim = path.join(scratch, "bin");
    fs.mkdirSync(shim);
    const library = path.join(scratch, "tui.sh");
    fs.writeFileSync(library, 'vgs_tui_header() { :; }\n');
    for (const [name, source] of Object.entries({
        "wl-copy": '#!/bin/bash\ncat >"$SETUP_SCRATCH/copied.json"\nprintf "%s\\n" "$@" >"$SETUP_SCRATCH/copy-args"\n',
        "xdg-open": '#!/bin/bash\nprintf "%s\\n" "$@" >"$SETUP_SCRATCH/open-args"\n',
        "gum": '#!/bin/bash\nif [[ ! -f $SETUP_SCRATCH/chosen ]]; then touch "$SETUP_SCRATCH/chosen"; printf "Show details\\n"; else printf "Close\\n"; fi\n'
    })) fs.writeFileSync(path.join(shim, name), source, { mode: 0o755 });
    const run = cp.spawnSync("/bin/bash", [path.join(plugin, "tui/setup-slack.sh")], {
        env: { PATH: shim + ":/usr/bin:/bin", VGS_TUI_LIB: library, SETUP_SCRATCH: scratch, LANG: "C.UTF-8" },
        encoding: "utf8", timeout: 10000
    });
    assert.equal(run.status, 0, run.stderr);
    assert.deepEqual(JSON.parse(fs.readFileSync(path.join(scratch, "copied.json"), "utf8")), manifest);
    assert.deepEqual(fs.readFileSync(path.join(scratch, "copy-args"), "utf8").trim().split("\n"), ["--type", "text/plain"]);
    assert.equal(fs.readFileSync(path.join(scratch, "open-args"), "utf8").trim(), "https://api.slack.com/apps");
    assert.ok(run.stdout.includes(fs.readFileSync(path.join(plugin, "slack-app.json"), "utf8")));
    console.log("test-notifications-slack-setup: ok controls=1");
} finally {
    fs.rmSync(scratch, { recursive: true, force: true });
}
