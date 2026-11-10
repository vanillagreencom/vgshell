#!/usr/bin/env node
// Scratch Homes, terminal input and namespace leases for Repair, which is
// also the package update: kendex refreshes the home's packages (D126).
// kendex is a stand-in; no installed VGS tree or kendex package is changed.
"use strict";
const cp = require("node:child_process");
const { assert, fs, path, tree, world } = require("./fixtures/jarvis/policy.js");
const { scratchTree } = require("./fixtures/jarvis/core.js");
const { jarvisHome } = require("./fixtures/jarvis/home.js");
const backendSource = process.argv.find(arg => arg.startsWith("--backend="))?.slice(10) || path.join(tree, "shell/plugins/vgs.jarvis/backend");
const persona = ".agents/skills/jarvis/persona.md";
const quote = value => "'" + value.replaceAll("'", "'\\''") + "'";

async function verify() {
    const root = fs.mkdtempSync(path.join(process.env.JARVIS_TEST_ROOT, "repair-"));
    const backend = path.join(root, "backend");
    fs.mkdirSync(backend);
    for (const name of ["Home.js", "Tools.js", "Core.js", "Child.js", "fleet-setup.js", "audio-child.py"])
        fs.copyFileSync(path.join(backendSource, name), path.join(backend, name));
    const core = scratchTree(root, {});
    require(path.join(backend, "Core.js")).use(core);
    const Home = require(path.join(backend, "Home.js"));
    const baseline = fs.readFileSync(path.join(tree, persona), "utf8");
    const kendex = path.join(root, "kendex");
    const toolLog = path.join(root, "tool.json");
    fs.writeFileSync(kendex, `#!${process.execPath}
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process");
const args=process.argv.slice(2), folder=args[args.indexOf("--project-path")+1];
let controlling=false;try{const fd=fs.openSync("/dev/tty","r+");fs.closeSync(fd);controlling=true;}catch{}
fs.writeFileSync(${JSON.stringify(toolLog)},JSON.stringify({args,tty:[process.stdin.isTTY,process.stdout.isTTY,process.stderr.isTTY],controlling}));
process.stdout.write("REPAIR_QUESTION\\n");
let answer="",one=Buffer.alloc(1); while(fs.readSync(0,one,0,1,null)&&one[0]!==10) answer+=one.toString();
if(answer.trim()==="hold") {
 cp.spawn(process.execPath,["-e","require('node:fs').writeFileSync(process.argv[1],require('node:fs').readlinkSync('/proc/self'));setInterval(()=>{},1000)",path.join(folder,"descendant")],{detached:true,stdio:"ignore"});
 setInterval(()=>{},1000);
} else if(answer.trim()==="replace") fs.writeFileSync(path.join(folder,${JSON.stringify(persona)}),${JSON.stringify(baseline)});
else process.exit(23);
`, { mode: 0o755 });
    const env = { ...process.env, PATH: root + ":" + process.env.PATH };
    const command = setting => [process.execPath, path.join(backend, "fleet-setup.js"), "--tree", core, "repair", setting];
    function invoke(args, options = {}) {
        const out = cp.spawnSync(args[0], args.slice(1), { env, encoding: "utf8", timeout: 20000, ...options });
        assert.equal(out.error, undefined, String(out.error));
        return out;
    }
    function terminal(setting, answer) {
        return invoke(["script", "-qec", command(setting).map(quote).join(" "), "/dev/null"], { input: answer + "\n" });
    }
    const probe = setting => {
        const out = invoke([process.execPath, path.join(backend, "fleet-setup.js"), "--tree", core, "repair-status", setting]);
        assert.equal(out.status, 0, out.stderr);
        return JSON.parse(out.stdout);
    };
    const folder = jarvisHome(path.join(process.env.HOME, "kendex-home"), tree);
    fs.rmSync(path.join(folder, persona));
    assert.throws(() => Home.judge(folder), /^Error: jarvis: home=package$/);
    assert.equal(probe(folder).kind, "home");
    assert.equal(terminal(folder, "replace").status, 0);
    assert.doesNotThrow(() => Home.judge(folder));
    const called = JSON.parse(fs.readFileSync(toolLog));
    assert.deepEqual(called.args, ["refresh", "--scope", "project", "--project-path", folder, "--leave"]);
    assert.deepEqual(called.tty, [true, true, true]);
    assert.equal(called.controlling, true);
    assert.equal(probe(folder).lastRepair.kind, "complete", "repair-outcome");
    console.log("case=kendex-missing-render repaired=true terminal-input=true");

    fs.writeFileSync(path.join(folder, persona), "user edit\n");
    fs.rmSync(path.join(folder, ".agents/skills/jarvis/SKILL.md"));
    assert.throws(() => Home.judge(folder), /^Error: jarvis: home=package$/);
    assert.equal(terminal(folder, "keep").status, 23);
    assert.equal(fs.readFileSync(path.join(folder, persona), "utf8"), "user edit\n");
    assert.equal(fs.existsSync(path.join(folder, ".agents/skills/jarvis/SKILL.md")), false);
    assert.deepEqual(probe(folder).lastRepair, { kind: "failed", cause: "refresh-failed", code: 23 });
    console.log("case=edited-render choice=keep preserved=true cause=refresh-failed");

    // A home kendex did not install the package in has no Repair: Setup
    // is its route, and Repair runs nothing there.
    const bare = jarvisHome(path.join(process.env.HOME, "bare-home"), tree, { lock: false });
    assert.equal(probe(bare).kind, "setup");
    fs.rmSync(toolLog, { force: true });
    const refused = invoke(command(bare));
    assert.equal(refused.status, 1);
    assert.match(refused.stderr, /^jarvis: fleet-setup=not-set-up$/m);
    assert.equal(fs.existsSync(toolLog), false, "kendex never ran");
    assert.deepEqual(probe(bare).lastRepair, { kind: "failed", cause: "not-set-up" });
    console.log("case=not-set-up repair=refused kendex=not-run");

    const lock = path.join(process.env.XDG_RUNTIME_DIR, "vgs-tui-jarvis-fleet-setup.lock");
    const ready = path.join(root, "locked");
    const holder = cp.spawn("flock", [lock, process.execPath, "-e", "require('node:fs').writeFileSync(process.argv[1],'held');process.stdin.resume();", ready], { env, stdio: ["pipe", "ignore", "inherit"] });
    const ended = new Promise(resolve => holder.once("close", resolve));
    const waitFor = async file => {
        for (let i = 0; i < 1000 && !fs.existsSync(file); i++) await new Promise(resolve => setTimeout(resolve, 5));
        assert.ok(fs.existsSync(file), file);
    };
    try {
        await waitFor(ready);
        assert.equal(invoke(command(folder)).status, 1);
        assert.equal(fs.readFileSync(ready, "utf8"), "held");
    } finally { holder.stdin.end(); await ended; }
    console.log("case=shared-fleet-lock concurrent-repair=refused");

    const running = cp.spawn(command(folder)[0], command(folder).slice(1), { env, stdio: ["pipe", "ignore", "inherit"] });
    const stopped = new Promise(resolve => running.once("close", resolve));
    running.stdin.end("hold\n");
    await waitFor(path.join(folder, "descendant"));
    const descendant = Number(fs.readFileSync(path.join(folder, "descendant"), "utf8"));
    running.kill("SIGTERM");
    assert.notEqual(await stopped, 0);
    for (let i = 0; i < 1000 && fs.existsSync("/proc/" + descendant); i++) {
        if (fs.readFileSync("/proc/" + descendant + "/stat", "utf8").split(") ")[1].startsWith("Z")) break;
        await new Promise(resolve => setTimeout(resolve, 5));
    }
    assert.ok(!fs.existsSync("/proc/" + descendant) || fs.readFileSync("/proc/" + descendant + "/stat", "utf8").split(") ")[1].startsWith("Z"));
    console.log("case=cancel-repair detached-descendant=ended");

}

world(async () => {
    await verify();
    if (process.argv.includes("--control")) return;
    const control = fs.mkdtempSync(path.join(process.env.XDG_RUNTIME_DIR, "repair-control-"));
    try {
        const backend = path.join(control, "backend");
        fs.cpSync(backendSource, backend, { recursive: true });
        const file = path.join(backend, "fleet-setup.js");
        const original = fs.readFileSync(file, "utf8");
        const needle = 'Home.repairResult(folder, { kind: "complete" });';
        assert.equal(original.split(needle).length - 1, 1, "repair-outcome mutation match");
        const changed = original.replace(needle, 'Home.repairResult(folder, { kind: "running" });');
        assert.notEqual(changed, original);
        fs.writeFileSync(file, changed);
        const env = { ...process.env, HOME: path.join(control, "home"), JARVIS_TEST_ROOT: control,
            XDG_RUNTIME_DIR: path.join(control, "runtime") };
        fs.mkdirSync(env.HOME); fs.mkdirSync(env.XDG_RUNTIME_DIR);
        const result = cp.spawnSync(process.execPath, [__filename, "--inside", "--backend=" + backend, "--control"],
            { env, encoding: "utf8", timeout: 20000 });
        assert.equal(result.error, undefined);
        assert.equal(result.status, 1);
        assert.match(result.stderr, /AssertionError[^]*repair-outcome/);
        console.log("control=repair-outcome detected");
    } finally { fs.rmSync(control, { recursive: true, force: true }); }
}, standins => {
    for (const name of ["script"]) {
        fs.copyFileSync("/usr/bin/" + name, path.join(standins, name));
        fs.chmodSync(path.join(standins, name), 0o755);
    }
});
