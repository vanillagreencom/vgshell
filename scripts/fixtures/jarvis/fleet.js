// Shared setup and first-hello startup in the daemon suite's private world.
// Synthetic git/kendex programs record argv without downloading a package.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const cp = require("node:child_process");
const { once } = require("node:events");

async function verify(daemon, tree, hello) {
    const backend = path.dirname(daemon);
    require(path.join(backend, "Core.js")).use(tree);
    const Fleet = require(path.join(backend, "fleet-setup.js"));
    const Home = require(path.join(backend, "Home.js"));
    const base = fs.mkdtempSync(path.join(process.env.HOME, "fleet-"));
    const bin = path.join(base, "bin");
    fs.mkdirSync(bin);
    const canonical = ".agents/skills/mailbox/scripts/lane-mail";
    const legacy = [".agents", "skills", "orch", "scripts", "lane-mail"].join("/");
    const marker = ".vgs-mailbox-cutover.json";
    const program = (name, source) => fs.writeFileSync(path.join(bin, name), "#!" + process.execPath + "\n" + source, { mode: 0o755 });
    program("git", `const fs=require('node:fs'); if(process.argv.includes('init')) fs.mkdirSync('.git',{recursive:true}); else console.log(process.cwd());`);
    program("kendex", `const fs=require('node:fs'), cp=require('node:child_process');
fs.appendFileSync('calls',JSON.stringify(process.argv.slice(2))+'\\n');
if(fs.existsSync('require-consumed') && fs.readFileSync('${marker}','utf8')!=='{"consumed":true}\\n') process.exit(42);
if(fs.existsSync('require-released') && (fs.existsSync('.vgs-package.json') || fs.existsSync('.claude/agents/owned.md'))) process.exit(44);
if(fs.existsSync('fail')) process.exit(43);
if(fs.existsSync('hold')) {
 const child=cp.spawn(process.execPath,['-e',"const fs=require('node:fs');const pid=fs.readFileSync('/proc/self/stat','utf8').split(' ')[0];if(fs.existsSync('delay-pid')){fs.writeFileSync('descendant','');const publish=()=>{if(fs.existsSync('pid-read'))fs.writeFileSync('descendant',pid);else setTimeout(publish,10)};publish()}else fs.writeFileSync('descendant',pid);setInterval(()=>{},1000)"],{detached:true,env:{},stdio:'ignore'});
 child.unref();
 const next=()=>{if(fs.existsSync('hold'))setTimeout(next,10);else finish()};next();
} else finish();
function finish(){fs.mkdirSync('${path.dirname(canonical)}',{recursive:true});fs.writeFileSync('${canonical}','#!/bin/sh\\nexit 0\\n',{mode:0o755});}
`);
    const env = { PATH: bin + ":" + process.env.PATH, HOME: process.env.HOME,
        XDG_RUNTIME_DIR: process.env.XDG_RUNTIME_DIR, XDG_DATA_HOME: process.env.XDG_DATA_HOME };
    let serial = 0;
    function home(ready = false) {
        const folder = path.join(base, "h" + ++serial);
        fs.mkdirSync(path.join(folder, path.dirname(legacy)), { recursive: true });
        fs.mkdirSync(path.join(folder, ".git"));
        fs.writeFileSync(path.join(folder, legacy), "#!/bin/sh\ntouch legacy-ran\nexit 99\n", { mode: 0o755 });
        // Kendex ownership stops layout from supplying the shipped reader
        // before the genuine old-only fixture reaches automatic startup.
        fs.writeFileSync(path.join(folder, ".kendex-lock.json"), JSON.stringify({ entries: { jarvis: { kind: "skill", name: "jarvis" } } }));
        fs.cpSync(path.join(tree, "packaging/jarvis-home/.agents/skills/jarvis"), path.join(folder, ".agents/skills/jarvis"), { recursive: true });
        if (ready) {
            fs.mkdirSync(path.join(folder, path.dirname(canonical)), { recursive: true });
            fs.writeFileSync(path.join(folder, canonical), "#!/bin/sh\n", { mode: 0o755 });
        }
        return folder;
    }
    const count = folder => fs.existsSync(path.join(folder, "calls")) ? fs.readFileSync(path.join(folder, "calls"), "utf8").trim().split("\n").length : 0;
    async function wait(test) {
        const end = Date.now() + 10000;
        while (!test()) {
            assert.ok(Date.now() < end, "fleet fixture acknowledgement deadline");
            await new Promise(resolve => setTimeout(resolve, 10));
        }
    }
    const install = (folder, automatic, signal) => Fleet.install(tree, folder, automatic, env, signal);
    const okay = result => { assert.equal(result.kind, "exited", JSON.stringify(result)); assert.equal(result.code, 0, result.stderr); };
    const ready = home(true);
    okay(await install(ready, true));
    assert.equal(count(ready), 0);
    assert.equal(fs.existsSync(path.join(ready, marker)), false);
    const old = home();
    fs.writeFileSync(path.join(old, "require-consumed"), "");
    fs.writeFileSync(path.join(old, "require-released"), "");
    fs.mkdirSync(path.join(old, ".claude/agents"), { recursive: true });
    fs.writeFileSync(path.join(old, ".claude/agents/owned.md"), "owned");
    fs.writeFileSync(path.join(old, ".claude/agents/mine.md"), "mine");
    fs.writeFileSync(path.join(old, ".vgs-package.json"), JSON.stringify({ files: [".claude/agents/owned.md"] }));
    okay(await install(old, true));
    assert.equal(fs.readFileSync(path.join(old, ".claude/agents/mine.md"), "utf8"), "mine");
    assert.equal(fs.existsSync(path.join(old, ".vgs-package.json")), false);
    assert.equal(fs.existsSync(path.join(old, ".claude/agents/owned.md")), false);
    assert.equal(Home.mailTool(old), path.join(old, canonical));
    assert.deepEqual(JSON.parse(fs.readFileSync(path.join(old, "calls"), "utf8")), ["add", "vanillagreencom/kendex", "--skill", "orch", "--yes", "--leave"]);
    okay(await install(old, true));
    assert.equal(count(old), 1);
    assert.equal(fs.existsSync(path.join(old, "legacy-ran")), false);
    const failed = home();
    fs.writeFileSync(path.join(failed, "fail"), "");
    const failure = await install(failed, true);
    assert.equal(failure.kind, "exited");
    assert.notEqual(failure.code, 0);
    okay(await install(failed, true));
    assert.equal(count(failed), 1, "failure remains consumed in another process");
    fs.rmSync(path.join(failed, "fail"));
    okay(await install(failed, false));
    assert.equal(count(failed), 2, "manual retry uses the same installer");
    const cancelled = home();
    fs.writeFileSync(path.join(cancelled, "hold"), "");
    // Hold publication until the reader has observed the create/write gap.
    fs.writeFileSync(path.join(cancelled, "delay-pid"), "");
    const controller = new AbortController();
    const pending = install(cancelled, true, controller.signal);
    let descendant;
    await wait(() => {
        if (!fs.existsSync(path.join(cancelled, "descendant"))) return false;
        descendant = fs.readFileSync(path.join(cancelled, "descendant"), "utf8");
        if (descendant === "") fs.writeFileSync(path.join(cancelled, "pid-read"), "");
        return /^[0-9]+$/.test(descendant);
    });
    const busy = await install(home(), false);
    assert.equal(busy.kind, "exited");
    assert.equal(busy.code, 75, "manual and automatic attempts share serialization");
    controller.abort();
    assert.equal((await pending).kind, "stopped");
    await wait(() => {
        try { return fs.readFileSync("/proc/" + descendant + "/stat", "utf8").split(") ")[1].startsWith("Z"); }
        catch (error) { if (error.code === "ENOENT") return true; throw error; }
    });
    okay(await install(cancelled, true));
    assert.equal(count(cancelled), 1, "interruption remains consumed");
    fs.rmSync(path.join(cancelled, "hold"));
    okay(await install(cancelled, false));
    assert.equal(count(cancelled), 2);
    const malformed = home();
    fs.writeFileSync(path.join(malformed, marker), "{");
    assert.notEqual((await install(malformed, true)).code, 0);
    assert.equal(count(malformed), 0);
    const linked = home();
    fs.mkdirSync(path.join(linked, path.dirname(canonical)), { recursive: true });
    fs.symlinkSync(path.join(linked, legacy), path.join(linked, canonical));
    okay(await install(linked, true));
    assert.equal(count(linked), 0);
    assert.equal(fs.existsSync(path.join(linked, marker)), false);

    const selected = home();
    const later = home();
    // Observe calls while keeping the real installer. A later hello's
    // accidentally started child can otherwise be cancelled before it writes.
    const observed = path.join(base, "observed");
    fs.cpSync(backend, path.join(observed, "backend"), { recursive: true });
    for (const name of ["JarvisProtocol.js", "Session.js", "AccountProviders.js", "manifest.json"])
        fs.copyFileSync(path.join(backend, "..", name), path.join(observed, name));
    const watched = path.join(observed, "backend/fleet-setup.js");
    const original = fs.readFileSync(watched, "utf8");
    const needle = "async function install(tree, folder, automatic, source, signal) {";
    assert.equal(original.split(needle).length, 2);
    const end = "\n}\n\nfunction locked";
    assert.equal(original.split(end).length, 2);
    const launch = '    return locked(tree, folder, automatic ? "automatic-worker" : "manual-worker", source, signal);';
    assert.equal(original.split(launch).length, 2);
    const instrumented = original.replace(needle, needle + '\n    require("node:fs").appendFileSync(require("node:path").join(folder, "launches"), "x");\n    try {')
        .replace(launch, launch.replace("return locked", "return await locked"))
        .replace(end, '\n    } finally { require("node:fs").writeFileSync(require("node:path").join(folder, "setup-finished"), ""); }\n}\n\nfunction locked');
    assert.notEqual(instrumented, original);
    fs.writeFileSync(watched, instrumented);
    const child = cp.spawn(process.execPath, [path.join(observed, "backend/jarvisd.js"), "--tree", tree], { env, stdio: ["pipe", "pipe", "pipe"] });
    let out = "", err = "";
    child.stdout.on("data", bytes => { out += bytes; });
    child.stderr.on("data", bytes => { err += bytes; });
    child.stdin.on("error", error => { if (error.code !== "EPIPE") throw error; });
    const closed = once(child, "close");
    const timeout = setTimeout(() => child.kill("SIGKILL"), 15000);
    const send = folder => child.stdin.write(JSON.stringify({ ...hello, settings: { ...hello.settings, home: folder } }) + "\n");
    const frames = () => out.split("\n").slice(0, -1).map(line => JSON.parse(line));
    try {
        send(selected);
        try { await wait(() => Home.mailTool(selected) !== null && frames().filter(frame => frame.type === "homes").length >= 3); }
        catch { assert.fail("fleet startup: " + out + err + " exit=" + child.exitCode + " calls=" + count(selected)); }
        send(later);
        await wait(() => frames().some(frame => frame.type === "homes" && frame.current === Home.relativeHome(later, env.HOME)));
        child.stdin.end();
        assert.deepEqual(await closed, [0, null], err);
        assert.equal(count(selected), 1);
        assert.equal(count(later), 0, "a later judgement starts no installer");
        assert.equal(fs.existsSync(path.join(later, marker)), false);
        assert.equal(fs.existsSync(path.join(later, "launches")), false, "later judgements do not call setup");
    } finally { clearTimeout(timeout); if (child.exitCode === null) { child.kill("SIGKILL"); await closed; } }

    const pendingHome = home();
    const changedHome = home(true);
    fs.writeFileSync(path.join(pendingHome, "hold"), "");
    const changed = cp.spawn(process.execPath, [path.join(observed, "backend/jarvisd.js"), "--tree", tree], { env, stdio: ["pipe", "pipe", "pipe"] });
    let changedOut = "", changedErr = "";
    changed.stdout.on("data", bytes => { changedOut += bytes; });
    changed.stderr.on("data", bytes => { changedErr += bytes; });
    changed.stdin.on("error", error => { if (error.code !== "EPIPE") throw error; });
    const changedClosed = once(changed, "close");
    const changedTimeout = setTimeout(() => changed.kill("SIGKILL"), 15000);
    const changedSend = folder => changed.stdin.write(JSON.stringify({ ...hello, settings: { ...hello.settings, home: folder } }) + "\n");
    const changedFrames = () => changedOut.split("\n").slice(0, -1).map(line => JSON.parse(line));
    try {
        changedSend(pendingHome);
        await wait(() => fs.existsSync(path.join(pendingHome, "descendant")));
        changedSend(changedHome);
        await wait(() => changedFrames().some(frame => frame.type === "homes" && frame.current === Home.relativeHome(changedHome, env.HOME)));
        fs.rmSync(path.join(pendingHome, "hold"));
        await wait(() => fs.existsSync(path.join(pendingHome, "setup-finished")));
        const statuses = changedFrames().filter(frame => frame.type === "status").length;
        changedSend(changedHome);
        await wait(() => changedFrames().filter(frame => frame.type === "status").length > statuses);
        changed.stdin.end();
        assert.deepEqual(await changedClosed, [0, null], changedErr);
        assert.equal(changedFrames().filter(frame => frame.type === "homes" && frame.current === Home.relativeHome(changedHome, env.HOME)).length, 2,
            "completion for the former home publishes no judgement for the new home");
    } finally { clearTimeout(changedTimeout); if (changed.exitCode === null) { changed.kill("SIGKILL"); await changedClosed; } }
    console.log("test-jarvis-daemon: fleet=shared-once-and-startup");
}
module.exports = { verify };
