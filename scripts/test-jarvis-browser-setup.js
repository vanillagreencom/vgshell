#!/usr/bin/env node
// Runs the real setup flow in J09 on a private pseudo-terminal. No browser runs.
// A missing driver is a PATH without the agent-browser stand-in; the stand-in
// vgshell beside a copy of the TUI library answers the requirement judge and
// copies the stand-in onto that PATH for an install. No package is installed.
"use strict";
const { assert, fs, path, tree, world, mutant } = require("./fixtures/jarvis/policy.js");
const { standins, mode, calls } = require("./fixtures/jarvis/browser.js");
const cp = require("node:child_process");
world(async () => {
    const root = process.argv[3] || tree;
    const plugin = path.join(root, "shell/plugins/vgs.jarvis");
    const scratch = process.env.JARVIS_TEST_ROOT;
    // jarvis-env.sh's PATH: the stand-ins, then its allow-listed tools.
    const tools = path.join(scratch, "tools");
    assert.equal(process.env.PATH, path.join(scratch, "standins") + ":" + tools);
    const driverless = path.join(scratch, "driverless");
    fs.mkdirSync(driverless);
    fs.copyFileSync(path.join(scratch, "standins/gum"), path.join(driverless, "gum"));
    fs.chmodSync(path.join(driverless, "gum"), 0o700);
    const vgs = path.join(scratch, "vgs-tree");
    fs.mkdirSync(path.join(vgs, "bin/lib"), { recursive: true });
    fs.copyFileSync(path.join(tree, "bin/lib/tui.sh"), path.join(vgs, "bin/lib/tui.sh"));
    fs.copyFileSync(path.join(tree, "scripts/fixtures/jarvis/browser-vgshell.py"), path.join(vgs, "bin/vgshell"));
    fs.chmodSync(path.join(vgs, "bin/vgshell"), 0o700);
    const vgshellLog = path.join(scratch, "vgshell-calls.jsonl");
    const vgshellCalls = () => fs.readFileSync(vgshellLog, "utf8").trim().split("\n").filter(Boolean).map(JSON.parse);
    const driverPath = driverless + ":" + tools;
    assert.equal(cp.spawnSync("bash", ["-c", "command -v agent-browser"], { env: { PATH: driverPath } }).status, 1,
        "the driverless PATH reaches no agent-browser");
    const setup = (folder, PATH) => cp.spawnSync("python3", [path.join(tree, "scripts/fixtures/jarvis/accounts-tui.py"),
        path.join(folder, "tui/setup-browser.sh"), path.join(vgs, "bin/lib/tui.sh"), folder], {
        env: { PATH, HOME: process.env.HOME, XDG_CONFIG_HOME: process.env.XDG_CONFIG_HOME,
            XDG_STATE_HOME: process.env.XDG_STATE_HOME, XDG_DATA_HOME: process.env.XDG_DATA_HOME,
            XDG_RUNTIME_DIR: process.env.XDG_RUNTIME_DIR, DBUS_SESSION_BUS_ADDRESS: process.env.DBUS_SESSION_BUS_ADDRESS },
        encoding: "utf8", timeout: 15000 });
    const marker = path.join(process.env.XDG_DATA_HOME, "vgshell/jarvis/browser-ready.json");
    const log = path.join(process.env.XDG_STATE_HOME, "vgshell/jarvis/setup.log");
    // INSTALLS counts browser downloads, DRIVER the driver installs through
    // vgshell, KEY the keyed line the run must add to the setup log, VENDOR
    // the vendor text its browser-vendor line there must carry. No keyed
    // line reaches the screen.
    function check(folder, name, fixture, expected, installs, driver = 0, key = null, vendor = null) {
        mode(fixture);
        fs.rmSync(marker, { force: true });
        fs.rmSync(path.join(driverless, "agent-browser"), { force: true });
        fs.writeFileSync(vgshellLog, "");
        fs.rmSync(log, { force: true });
        const result = setup(folder, fixture.driverMissing ? driverPath : process.env.PATH);
        const logged = fs.existsSync(log) ? fs.readFileSync(log, "utf8") : "";
        assert.doesNotMatch(result.stdout, /jarvis: browser/, name + " keeps keyed lines off the screen");
        assert.equal(result.error, undefined);
        assert.equal(result.status, expected, name + ": " + result.stdout + result.stderr);
        assert.equal(calls().filter(row => row.args[0] === "install").length, installs, name);
        const pick = fixture.driverPackage === undefined ? { manager: "aur", name: "agent-browser-bin" } : fixture.driverPackage;
        assert.deepEqual(vgshellCalls().filter(row => row[0] === "pkg"),
            Array(driver).fill(["pkg", "run", "install", "--manager", pick === null ? "" : pick.manager, pick === null ? "" : pick.name]), name);
        for (const row of vgshellCalls().filter(row => row[0] !== "pkg"))
            assert.deepEqual(row, ["plugin", "requirements", "--json", "vgs.jarvis"], name);
        if (key !== null) assert.ok(logged.includes("jarvis: browser-setup=" + key + "\n"), name + " logs " + key);
        if (vendor !== null) {
            const line = /^jarvis: browser-vendor=(.*)$/m.exec(logged);
            assert.ok(line, name + " logs the vendor line");
            assert.match(JSON.parse(line[1]), vendor, name);
            assert.equal(calls().some(row => row.args.at(-1) === "close"), false, name + " closes no unopened session");
        }
        assert.equal(fs.existsSync(marker), expected === 0, name + " verifies before ready");
        for (const row of calls()) {
            assert.equal(row.env.OPENAI_API_KEY, undefined);
            assert.equal(row.env.VGSHELL_RUNNER_PID, undefined);
            assert.equal(row.args.includes("--with-deps"), false);
            if (row.args.includes("open")) assert.equal(row.args.at(-1), "about:blank");
        }
    }
    const cases = [
        ["installed", {}, 0, 0],
        ["download", { missing: true }, 0, 1],
        ["declined", { missing: true, confirmExit: 1 }, 130, 0],
        ["install-failed", { missing: true, installExit: 1 }, 1, 1],
        ["verify-failed", { verifyUrl: "https://unexpected.test/" }, 1, 0],
        ["unrelated-failure", { fail: true }, 1, 0],
        ["old-version", { version: "0.37.9" }, 1, 0],
        ["driver-installed", { driverMissing: true, driverPackage: { manager: "mise", name: "npm:agent-browser" } }, 0, 0, 1,
            "missing command=agent-browser"],
        ["driver-declined", { driverMissing: true, confirmExit: 1 }, 130, 0, 0, "missing command=agent-browser"],
        ["driver-no-package", { driverMissing: true, driverPackage: null }, 1, 0, 0, "no-package command=agent-browser"],
        ["driver-unreachable", { driverMissing: true, driverReachable: false }, 1, 0, 1, "still-missing command=agent-browser"],
        ["socket-refused", { socketRefused: true }, 1, 0, 0, null, /^Session name 'jarvis-[0-9a-f]{8}' is too long\./]
    ];
    for (const row of cases) check(plugin, ...row);
    // The installed stub is consumed by the real module, not merely inventoried.
    mode({});
    const Browser = require(path.join(plugin, "backend/Browser.js"));
    const owner = Browser.create({ environment: process.env });
    assert.match(owner.guidance(), /fixture installed core guide/);
    owner.close();
    let controls = 0;
    function scriptControl(name, needle, replacement, row, file = "tui/setup-browser.sh") {
        const copy = fs.mkdtempSync(path.join(process.env.JARVIS_TEST_ROOT, "browser-tui-mutant-"));
        try {
            fs.cpSync(plugin, copy, { recursive: true });
            const script = path.join(copy, file);
            const source = fs.readFileSync(script, "utf8");
            assert.equal(source.split(needle).length - 1, 1, name + " matches");
            const changed = source.replace(needle, replacement);
            assert.notEqual(source, changed); fs.writeFileSync(script, changed);
            assert.throws(() => check(copy, ...row), assert.AssertionError, name + " must turn red");
            controls++;
        } finally { fs.rmSync(copy, { recursive: true, force: true }); }
    }
    scriptControl("download-consent", 'vgs_tui_confirm "Download a private Chrome browser for Jarvis?" || exit 130',
        'true "Download a private Chrome browser for Jarvis?" || exit 130', cases.find(row => row[0] === "declined"));
    scriptControl("verify-after-download", '    browser verify || {', '    true verify || {', cases.find(row => row[0] === "download"));
    scriptControl("download-error", '    browser download ||', '    browser download || true ||', cases.find(row => row[0] === "install-failed"));
    scriptControl("cause-on-screen", 'browser() { vgs_tui_logged "$log" node "$program" "$@"; }', 'browser() { node "$program" "$@"; }',
        cases.find(row => row[0] === "verify-failed"));
    scriptControl("only-missing-browser", '  69)', '  1|69)', cases.find(row => row[0] === "unrelated-failure"));
    scriptControl("install-consent", 'vgs_tui_confirm "Install agent-browser now?" || exit 130',
        'true "Install agent-browser now?" || exit 130', cases.find(row => row[0] === "driver-declined"));
    scriptControl("judge-package", 'row.package.manager + " " + row.package.name', '"aur agent-browser-bin"',
        cases.find(row => row[0] === "driver-installed"));
    scriptControl("no-package", '[[ -n $package ]] ||', '[[ -n $package || 1 ]] ||', cases.find(row => row[0] === "driver-no-package"));
    scriptControl("recheck-after-install", 'command -v agent-browser >/dev/null ||\n    refuse 1 "still-missing',
        'true ||\n    refuse 1 "still-missing', cases.find(row => row[0] === "driver-unreachable"));
    scriptControl("continue-after-install", 'command -v agent-browser >/dev/null || install_driver',
        'command -v agent-browser >/dev/null || { install_driver; exit 0; }', cases.find(row => row[0] === "driver-installed"));
    scriptControl("vendor-log", 'process.stderr.write("jarvis: browser-vendor="', 'void ("jarvis: browser-vendor="',
        cases.find(row => row[0] === "socket-refused"), "backend/Browser.js");
    await mutant(path.join(plugin, "backend/Browser.js"), "skill-cache", 'if (guidanceCache === null || guidanceCache.version !== installed) {', 'if (true) {', (implementation, folder) => {
        fs.cpSync(path.join(plugin, "backend/skills"), path.join(folder, "skills"), { recursive: true });
        mode({}); const candidate = implementation.create({ environment: process.env });
        try {
            candidate.guidance(); candidate.guidance();
            assert.equal(calls().filter(row => row.args[0] === "skills").length, 1);
        } finally { candidate.close(); }
    }); controls++;
    console.log("test-jarvis-browser-setup: ok cases=" + cases.length + " controls=" + controls);
}, standins);
