#!/usr/bin/env node
// Scratch Homes, terminal input and namespace leases. Package commands are
// stand-ins; no installed VGS tree or Kendex package is changed.
"use strict";
const cp = require("node:child_process");
const { assert, fs, path, tree, world } = require("./fixtures/jarvis/policy.js");
const { scratchTree } = require("./fixtures/jarvis/core.js");
const backendSource = process.argv.find(arg => arg.startsWith("--backend="))?.slice(10) || path.join(tree, "shell/plugins/vgs.jarvis/backend");
const source = path.join(tree, "packaging/jarvis-home");
const persona = ".agents/skills/jarvis/persona.md";
const quote = value => "'" + value.replaceAll("'", "'\\''") + "'";

world(async () => {
    const root = fs.mkdtempSync(path.join(process.env.JARVIS_TEST_ROOT, "repair-"));
    const backend = path.join(root, "backend");
    fs.mkdirSync(backend);
    for (const name of ["Home.js", "Tools.js", "Core.js", "Child.js", "fleet-setup.js", "audio-child.py"])
        fs.copyFileSync(path.join(backendSource, name), path.join(backend, name));
    const core = scratchTree(root, {});
    const render = path.join(core, "packaging/jarvis-home");
    fs.cpSync(source, render, { recursive: true });
    require(path.join(backend, "Core.js")).use(core);
    const Home = require(path.join(backend, "Home.js"));
    const baseline = fs.readFileSync(path.join(render, persona), "utf8");
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
    const folder = path.join(process.env.HOME, "kendex-home");
    Home.layout(folder);
    fs.copyFileSync(path.join(render, ".kendex-lock.json"), path.join(folder, ".kendex-lock.json"));
    fs.rmSync(path.join(folder, persona));
    assert.throws(() => Home.layout(folder), /^Error: jarvis: home=package$/);
    assert.equal(probe(folder).kind, "home");
    assert.equal(terminal(folder, "replace").status, 0);
    assert.doesNotThrow(() => Home.layout(folder));
    const called = JSON.parse(fs.readFileSync(toolLog));
    assert.deepEqual(called.args, ["refresh", "--scope", "project", "--project-path", folder, "--leave"]);
    assert.deepEqual(called.tty, [true, true, true]);
    assert.equal(called.controlling, true);
    assert.equal(probe(folder).lastRepair.kind, "complete");
    console.log("case=kendex-missing-render repaired=true terminal-input=true");

    fs.writeFileSync(path.join(folder, persona), "user edit\n");
    fs.rmSync(path.join(folder, ".agents/skills/jarvis/SKILL.md"));
    assert.throws(() => Home.layout(folder), /^Error: jarvis: home=package$/);
    assert.equal(terminal(folder, "keep").status, 23);
    assert.equal(fs.readFileSync(path.join(folder, persona), "utf8"), "user edit\n");
    assert.equal(fs.existsSync(path.join(folder, ".agents/skills/jarvis/SKILL.md")), false);
    assert.deepEqual(probe(folder).lastRepair, { kind: "failed", cause: "refresh-failed", code: 23 });
    console.log("case=edited-render choice=keep preserved=true cause=refresh-failed");

    const vgs = path.join(process.env.HOME, "vgs-home");
    Home.layout(vgs);
    fs.rmSync(path.join(render, persona));
    assert.throws(() => Home.layout(vgs), /^Error: jarvis: home=package$/);
    const installTool = path.join(core, "bin/vgshell");
    fs.writeFileSync(installTool, `#!${process.execPath}
const fs=require("node:fs");const args=process.argv.slice(2);
if(args.join(" ")==="self repair --plan" && fs.existsSync(${JSON.stringify(path.join(core, "probe-hold"))})) {
 require("node:child_process").spawn(process.execPath,["-e","require('node:fs').writeFileSync(process.argv[1],require('node:fs').readlinkSync('/proc/self'));setInterval(()=>{},1000)",${JSON.stringify(path.join(core, "probe-descendant"))}],{detached:true,stdio:"ignore"});
 setInterval(()=>{},1000);
} else if(args.join(" ")==="self repair --plan") process.stdout.write(JSON.stringify({kind:"run",method:"package",reason:null,command:["stand-in"]})+"\\n");
else if(args.join(" ")==="self repair") fs.writeFileSync(${JSON.stringify(path.join(render, persona))},${JSON.stringify(baseline)});
else process.exit(99);
`, { mode: 0o755 });
    fs.renameSync(kendex, kendex + ".off");
    assert.equal(probe(vgs).kind, "install");
    assert.equal(terminal(vgs, "unused").status, 0);
    assert.doesNotThrow(() => Home.layout(vgs));
    assert.equal(Home.packageOwner(vgs), "vgs");
    console.log("case=vgs-shipped-render repaired=true kendex-present=false ownership=vgs");
    fs.renameSync(kendex + ".off", kendex);

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

    fs.writeFileSync(path.join(core, "probe-hold"), "hold");
    const checking = cp.spawn(process.execPath, [path.join(backend, "fleet-setup.js"), "--tree", core, "repair-status", vgs], { env, stdio: "ignore" });
    const checked = new Promise(resolve => checking.once("close", resolve));
    await waitFor(path.join(core, "probe-descendant"));
    const probeChild = Number(fs.readFileSync(path.join(core, "probe-descendant"), "utf8"));
    checking.kill("SIGTERM");
    await checked;
    for (let i = 0; i < 1000 && fs.existsSync("/proc/" + probeChild); i++) {
        if (fs.readFileSync("/proc/" + probeChild + "/stat", "utf8").split(") ")[1].startsWith("Z")) break;
        await new Promise(resolve => setTimeout(resolve, 5));
    }
    assert.ok(!fs.existsSync("/proc/" + probeChild) || fs.readFileSync("/proc/" + probeChild + "/stat", "utf8").split(") ")[1].startsWith("Z"));
    console.log("case=dispose-install-probe detached-descendant=ended");
}, standins => {
    for (const name of ["script"]) {
        fs.copyFileSync("/usr/bin/" + name, path.join(standins, name));
        fs.chmodSync(path.join(standins, name), 0o755);
    }
});
