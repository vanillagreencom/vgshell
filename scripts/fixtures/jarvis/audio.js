// Synthetic audio world. Only setpriv/unshare are allow-listed host effects;
// every PipeWire command is a fixture. Auth commands have no PATH entry.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const os = require("node:os");
const cp = require("node:child_process");
const tree = path.resolve(__dirname, "../../..");
const { runBounded, hungWorldControl } = require("./bounded.js");
const launcher = path.join(tree, "scripts/lib/jarvis-env.sh");

function standins(folder) {
    fs.mkdirSync(folder, { recursive: true });
    for (const command of ["pw-record", "pw-cat", "pw-dump"])
        fs.writeFileSync(path.join(folder, command), "#!/bin/bash\nexec python3 -I " +
            JSON.stringify(path.join(__dirname, "audio-tool.py")) + " " + command + ' "$@"\n', { mode: 0o700 });
}

// A scratch home with the audio stand-ins, removed when RUN returns.
function scratch(run) {
    const parent = os.tmpdir();
    fs.mkdirSync(parent, { recursive: true });
    const root = fs.realpathSync(fs.mkdtempSync(path.join(parent, "ja-")));
    try {
        standins(path.join(root, "standins"));
        return run(path.join(root, "standins"), { PATH: "/usr/bin:/bin", HOME: root, JARVIS_TEST_SCRATCH_ROOT: parent });
    } finally { fs.rmSync(root, { recursive: true, force: true }); }
}

async function world(main) {
    if (process.argv[2] === "--inside") {
        for (const name of ["sudo", "pkexec", "pamtester", "secret-tool", "faillock"])
            assert.equal(cp.spawnSync("bash", ["-c", "command -v " + name], {
                env: { PATH: process.env.PATH }, encoding: "utf8"
            }).status, 1, "no real auth call is possible");
        return main();
    }
    scratch((folder, env) => {
        const result = runBounded("/bin/bash", [launcher, folder, "--", "node", process.argv[1], "--inside",
            ...process.argv.slice(2)], { env });
        if (result.error) throw result.error;
        assert.equal(result.signal, null);
        process.exitCode = result.status;
    });
}

// The must-fail control of the audio world: a planted hung one is stopped.
function hungWorld() {
    scratch((folder, env) => hungWorldControl(launcher, folder, env));
}

// ms bounds a missing observation, not a latency budget. A timeout carries
// operator "until", so a caller tells an observation that never came from
// one that came with the wrong value.
async function until(check, message, ms = 5000, poll = 10) {
    const deadline = performance.now() + ms;
    while (!check()) {
        if (performance.now() >= deadline)
            throw new assert.AssertionError({ message, actual: false, expected: true, operator: "until" });
        // Observe child pipe/lock state. This is not a latency measurement.
        await new Promise(resolve => setTimeout(resolve, poll));
    }
}

function unlocked() {
    const result = cp.spawnSync("python3", ["-I", "-c",
        "import fcntl,pathlib,sys\nfor p in pathlib.Path(sys.argv[1]).glob('*.lock'):\n" +
        " try:\n  f=p.open(); fcntl.flock(f,fcntl.LOCK_EX|fcntl.LOCK_NB)\n" +
        " except BlockingIOError:\n  sys.exit(1)\n", process.env.HOME], {
        env: { PATH: process.env.PATH, HOME: process.env.HOME }, encoding: "utf8"
    });
    assert.equal(result.error, undefined);
    return result.status === 0;
}

function copyBackend(folder) {
    fs.mkdirSync(folder, { recursive: true });
    // Backend modules load ../AccountProviders.js, and ../manifest.json for
    // the version floors.
    for (const beside of ["AccountProviders.js", "manifest.json"])
        fs.copyFileSync(path.join(tree, "shell/plugins/vgs.jarvis", beside), path.join(folder, "..", beside));
    for (const file of fs.readdirSync(path.join(tree, "shell/plugins/vgs.jarvis/backend")))
        fs.cpSync(path.join(tree, "shell/plugins/vgs.jarvis/backend", file), path.join(folder, file), { recursive: true });
}

module.exports = { assert, fs, path, cp, tree, standins, world, hungWorld, until, unlocked, copyBackend };
