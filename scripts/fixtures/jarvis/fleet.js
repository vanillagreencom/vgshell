// The home's package routes of backend/fleet-setup.js, run through its
// command line in the daemon suite's private world (D126): Setup's order,
// its refusals and its read-back, and the second-computer clone's. git,
// kendex and the package's jarvis-session are synthetic programs that
// record their argv in HOME/fleet-calls and write what the real ones would
// write in a home, without a download: kendex's add writes the package the
// way `kendex add --bundle jarvis` lays it out, and init the starting files
// .agents/skills/jarvis/references/home-layout.md § Initialize names
// (kendex 6c00d3e19). Each case is named, so that a control runs only the
// case its guard holds.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const cp = require("node:child_process");
const { once } = require("node:events");

const SESSION = ".agents/skills/jarvis/scripts/jarvis-session";
const MAIL = ".agents/skills/mailbox/scripts/lane-mail";
// The git probes judge a folder and change nothing; the steps are what
// changed it.
const PROBES = ["rev-parse", "ls-files", "log"];

// The synthetic programs, each a node script on the fixture's PATH. A
// fault is a file HOME/faults/<folder name>.<fault>.
function programs(bin) {
    const program = (name, source) => fs.writeFileSync(path.join(bin, name), "#!" + process.execPath + "\n" + source, { mode: 0o755 });
    const log = `const fs=require('node:fs'),path=require('node:path');
const log=entry=>fs.appendFileSync(path.join(process.env.HOME,'fleet-calls'),JSON.stringify(entry)+'\\n');
const fault=(folder,name)=>fs.existsSync(path.join(process.env.HOME,'faults',path.basename(folder)+'.'+name));`;
    // git: rev-parse names the work tree with links resolved, as git does
    // (setup.c); a clone takes the allowed transports and the user's SSH
    // agent, and without a checkout copies the history alone, and reset
    // --hard then writes the files. log answers for the private env file
    // over every ref, where history-env puts its commit, and with
    // --full-history, which merged-env needs: its commit lies on a merged
    // branch that added and then removed the file, which git log's default
    // simplification skips (git-log(1) § History Simplification). A
    // checkout under hang-checkout says so on stderr and blocks until a
    // signal ends it.
    program("git", `${log}
let a=process.argv.slice(2), cwd=process.cwd();
while(a[0]==='-c') a=a.slice(2);
if(a[0]==='-C'){cwd=path.resolve(a[1]);a=a.slice(2);}
log(['git',...process.argv.slice(2)]);
if(a[0]==='rev-parse'){let d=cwd;for(;;){if(fs.existsSync(path.join(d,'.git'))){console.log(fs.realpathSync(d));process.exit(0);}const up=path.dirname(d);if(up===d)break;d=up;}
 process.stderr.write('fatal: not a git repository (or any of the parent directories): .git\\n');process.exit(128);}
if(a[0]==='init'){fs.mkdirSync(path.join(cwd,'.git'),{recursive:true});process.exit(0);}
if(a[0]==='clone'){if(process.env.GIT_ALLOW_PROTOCOL!=='ssh:https:file')process.exit(97);if(process.env.SSH_AUTH_SOCK!==path.join(process.env.HOME,'fleet-agent.sock'))process.exit(95);const [from,to]=a.slice(a.indexOf('--')+1);
 if(!a.includes('--no-checkout')){fs.cpSync(from,to,{recursive:true});process.exit(0);}
 fs.mkdirSync(to,{recursive:true});fs.cpSync(path.join(from,'.git'),path.join(to,'.git'),{recursive:true});
 fs.writeFileSync(path.join(to,'.git','fixture-origin'),path.resolve(from));process.exit(0);}
if(a[0]==='reset'){if(fault(cwd,'fail-checkout'))process.exit(1);if(fault(cwd,'hang-checkout')){process.stderr.write('fixture: checkout=hung\\n');Atomics.wait(new Int32Array(new SharedArrayBuffer(4)),0,0);}const origin=path.join(cwd,'.git','fixture-origin');if(!fs.existsSync(origin))process.exit(0);const from=fs.readFileSync(origin,'utf8');
 for(const name of fs.readdirSync(from))if(name!=='.git')fs.cpSync(path.join(from,name),path.join(cwd,name),{recursive:true});process.exit(0);}
if(a[0]==='log'){if(fault(cwd,'log-fails')){process.stderr.write('fatal: bad object HEAD\\n');process.exit(128);}
 if(a.includes('--all')&&fault(cwd,'history-env')||a.includes('--full-history')&&fault(cwd,'merged-env'))console.log('0123456789abcdef0123456789abcdef01234567');process.exit(0);}
if(a[0]==='ls-files'){if(fault(cwd,'tracked-env'))process.stdout.write('.env.local\\0');process.exit(0);}
process.exit(96);`);
    const session = `#!${process.execPath}
const fs=require('node:fs'),path=require('node:path');
fs.appendFileSync(path.join(process.env.HOME,'fleet-calls'),JSON.stringify(['jarvis-session',...process.argv.slice(2)])+'\\n');
const fault=(folder,name)=>fs.existsSync(path.join(process.env.HOME,'faults',path.basename(folder)+'.'+name));
const a=process.argv.slice(2), home=a[a.indexOf('--home')+1];
if(a[0]==='init'){
 if(fault(home,'refuse-init')){process.stderr.write('jarvis-session: init=refused cause=other-entry entry="notes.txt"\\n');process.exit(1);}
 const created=[];
 if(!fault(home,'init-lies')){
  for(const [file,text] of [['AGENTS.md','Read \\x60.agents/skills/jarvis/persona.md\\x60 and follow it.\\n'],['memory/MEMORY.md','# Memory index\\n']])
   if(!fs.existsSync(path.join(home,file))){fs.mkdirSync(path.dirname(path.join(home,file)),{recursive:true});fs.writeFileSync(path.join(home,file),text);created.push(file);}
  fs.mkdirSync(path.join(home,'state'),{recursive:true});
 }
 console.log(JSON.stringify({v:1,home,created,kept:[],settings:[]}));process.exit(0);}
if(a[0]==='main-host'&&a[1]==='--set'){if(!fault(home,'set-lost'))fs.writeFileSync(path.join(home,'.env.local'),'JARVIS_MAIN_HOST='+a[2]+'\\n');console.log(JSON.stringify({JARVIS_MAIN_HOST:a[2]}));process.exit(0);}
if(a[0]==='main-host'&&a[1]==='--get'){if(fault(home,'get-fails')){process.stderr.write('jarvis-session: main-host=unreadable\\n');process.exit(1);}const file=path.join(home,'.env.local');const line=fs.existsSync(file)?fs.readFileSync(file,'utf8').match(/^JARVIS_MAIN_HOST=(.*)$/m):null;
 console.log(JSON.stringify({JARVIS_MAIN_HOST:line?line[1]:''}));process.exit(0);}
process.exit(2);
`;
    program("kendex", `${log}
const a=process.argv.slice(2), home=process.cwd();
log(['kendex',...a]);
if(a[0]==='add'){
 if(fault(home,'fail-add'))process.exit(43);
 for(const [file,text,mode] of [['.agents/skills/jarvis/SKILL.md','---\\nname: jarvis\\ndescription: The Jarvis package\\n---\\n',0o644],
  ['.agents/skills/jarvis/persona.md','# Jarvis persona\\n',0o644],['${SESSION}',${JSON.stringify(session)},0o755],['${MAIL}','#!/bin/sh\\nexit 0\\n',0o755]]){
  fs.mkdirSync(path.dirname(path.join(home,file)),{recursive:true});fs.writeFileSync(path.join(home,file),text,{mode});}
 fs.writeFileSync(path.join(home,'.kendex-lock.json'),JSON.stringify({version:12,entries:{'skill:jarvis':{kind:'skill',name:'jarvis'}}}));
 process.exit(0);}
if(a[0]==='guard'&&a[1]==='install'){if(fault(home,'fail-guard'))process.exit(1);fs.writeFileSync(path.join(home,'.git','guards-armed'),'');process.exit(0);}
process.exit(2);`);
}

// One world over the fleet-setup.js of BACKEND: the command line, a fresh
// folder each call, faults, and the assertions every case shares.
function world(backend, tree, base) {
    const bin = path.join(base, "bin");
    fs.mkdirSync(bin, { recursive: true });
    programs(bin);
    const env = { PATH: bin + ":" + process.env.PATH, HOME: process.env.HOME, SSH_AUTH_SOCK: path.join(process.env.HOME, "fleet-agent.sock"),
        XDG_RUNTIME_DIR: process.env.XDG_RUNTIME_DIR, XDG_DATA_HOME: process.env.XDG_DATA_HOME };
    const calls = path.join(process.env.HOME, "fleet-calls");
    // One run of the command line: its exit, output and the steps it ran.
    const run = (...args) => {
        fs.rmSync(calls, { force: true });
        const result = cp.spawnSync(process.execPath, [path.join(backend, "fleet-setup.js"), "--tree", tree, ...args],
            { env, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"], timeout: 60000 });
        assert.equal(result.error, undefined);
        const made = fs.existsSync(calls) ? fs.readFileSync(calls, "utf8").trim().split("\n").map(line => JSON.parse(line)) : [];
        return { code: result.status, stdout: result.stdout, stderr: result.stderr,
            steps: made.filter(entry => !(entry[0] === "git" && PROBES.some(probe => entry.includes(probe)))) };
    };
    require(path.join(backend, "Core.js")).use(tree);
    let serial = 0;
    fs.rmSync(path.join(process.env.HOME, "faults"), { recursive: true, force: true });
    const ok = (result, name) => assert.equal(result.code, 0, name + ": " + result.stderr);
    const refused = (result, key, name) => {
        assert.notEqual(result.code, 0, name);
        assert.match(result.stderr, new RegExp("^jarvis: fleet-setup=" + key + "\\b", "m"), name + ": " + result.stderr);
    };
    const ADD = ["kendex", "add", "vanillagreencom/kendex", "--bundle", "jarvis", "--harness", "claude,codex", "--yes", "--allow-repo-effects", "--leave"];
    return {
        run, ok, refused, ADD,
        Home: require(path.join(backend, "Home.js")),
        fresh: (prefix = "home") => path.join(base, prefix + "-" + ++serial),
        // A fault the synthetic programs read for FOLDER, kept outside it.
        fault(folder, name) {
            fs.mkdirSync(path.join(process.env.HOME, "faults"), { recursive: true });
            fs.writeFileSync(path.join(process.env.HOME, "faults", path.basename(folder) + "." + name), "");
        },
        clear(folder, name) { fs.rmSync(path.join(process.env.HOME, "faults", path.basename(folder) + "." + name)); },
        // The command line started as a terminal starts it, leading its own
        // process group, and hung up as closing the window hangs it up:
        // SIGHUP to that whole group once a step writes HUNG on stderr.
        // Resolves once every member's output has closed.
        async hangUp(hung, ...args) {
            const child = cp.spawn(process.execPath, [path.join(backend, "fleet-setup.js"), "--tree", tree, ...args],
                { env, detached: true, stdio: ["ignore", "pipe", "pipe"] });
            const group = signal => {
                try { process.kill(-child.pid, signal); }
                catch (error) { if (error.code !== "ESRCH") throw error; }
            };
            let stderr = "", sent = false;
            child.stdout.resume();
            child.stderr.setEncoding("utf8");
            child.stderr.on("data", text => {
                stderr += text;
                if (!sent && stderr.includes(hung)) { sent = true; group("SIGHUP"); }
            });
            // A recovery bound, not a measured latency: a group still running
            // then is killed, and the case fails on what it left.
            const timer = setTimeout(() => group("SIGKILL"), 60000);
            const [code] = await once(child, "close");
            clearTimeout(timer);
            assert.equal(sent, true, "the step hangs before the hangup: " + stderr);
            return { code, stderr };
        },
        // A main home made by Setup, without init's state folder, so that a
        // clone's state folder is its own init's.
        main() {
            const folder = path.join(base, "main-" + ++serial);
            ok(run("setup", folder, ""), "the main home is set up");
            fs.rmSync(path.join(folder, "state"), { recursive: true });
            return folder;
        }
    };
}

// The plan the TUI shows for ARGS, as argv, with the package's session
// command named as the steps record it.
function planned(w, ...args) {
    const result = w.run("plan", ...args);
    w.ok(result, "the plan prints");
    return result.stdout.trimEnd().split("\n").map(line => line.split(" ").map(word => word === SESSION ? "jarvis-session" : word));
}

const CASES = {
    // A new home: the folder, git init, the bundle, then init, in order,
    // the plan the TUI showed, and a home Jarvis then judges ready.
    setup(w) {
        const made = w.fresh();
        const setup = w.run("setup", made, "");
        w.ok(setup, "a new folder is set up");
        assert.deepEqual(setup.steps, [["git", "-C", made, "init"], w.ADD, ["jarvis-session", "init", "--home", made]],
            "Setup runs its steps in D126's order");
        assert.deepEqual(planned(w, made, "new"), setup.steps, "the TUI shows the steps Setup runs");
        assert.doesNotThrow(() => w.Home.judge(made), "the home reads back ready");
        assert.equal(w.run("ready", made).code, 0, "and the TUI's probe agrees");
        const again = w.run("setup", made, "");
        w.ok(again, "a home kendex installed the package in can be set up again");
        assert.deepEqual(again.steps, [w.ADD, ["jarvis-session", "init", "--home", made]], "without a second git init");
    },
    // Never convert a project or a folder of other files.
    "setup-refusals"(w) {
        const occupied = w.fresh();
        fs.mkdirSync(occupied);
        fs.writeFileSync(path.join(occupied, "notes.txt"), "mine\n");
        const occupiedRun = w.run("setup", occupied, "");
        w.refused(occupiedRun, "occupied", "a folder of other files is refused");
        assert.deepEqual(occupiedRun.steps, [], "and nothing runs in it");
        assert.deepEqual(fs.readdirSync(occupied), ["notes.txt"]);
        const project = w.fresh("project");
        fs.mkdirSync(path.join(project, ".git"), { recursive: true });
        const inside = path.join(project, "Jarvis");
        const insideRun = w.run("setup", inside, "");
        w.refused(insideRun, "inside-project", "a folder inside another work tree is refused");
        assert.deepEqual(insideRun.steps, []);
        assert.equal(fs.existsSync(inside), false, "and is not made");
    },
    // A computer that forwards to a main Jarvis takes the clone: a new home
    // there would hold a second memory.
    "setup-main-host"(w) {
        const folder = w.fresh();
        const result = w.run("setup", folder, "main-pc");
        w.refused(result, "main-host-set", "Setup refuses while Main Jarvis host names another computer");
        assert.deepEqual(result.steps, [], "and runs nothing");
        assert.equal(fs.existsSync(folder), false, "and makes no folder");
    },
    // A home reached through a linked folder is its own work tree, as git
    // names it with the link resolved.
    "setup-linked"(w) {
        const disk = w.fresh("disk");
        const home = path.join(disk, "Jarvis");
        fs.mkdirSync(path.join(home, ".git"), { recursive: true });
        const link = w.fresh("link");
        fs.symlinkSync(disk, link);
        const folder = path.join(link, "Jarvis");
        const result = w.run("setup", folder, "");
        w.ok(result, "a home that holds only Git's entry, reached through a link, is set up");
        assert.deepEqual(result.steps, [w.ADD, ["jarvis-session", "init", "--home", folder]], "with no second git init");
        assert.doesNotThrow(() => w.Home.judge(home));
    },
    // A failed step stops the steps after it; the package's refusal reaches
    // the terminal as it wrote it; success is read back, never assumed.
    "setup-step-fails"(w) {
        const addFails = w.fresh();
        w.fault(addFails, "fail-add");
        const addRun = w.run("setup", addFails, "");
        w.refused(addRun, "install-failed", "a failed kendex add fails Setup");
        assert.deepEqual(addRun.steps.map(step => step[0]), ["git", "kendex"], "and runs no init after it");
        const initRefuses = w.fresh();
        w.fault(initRefuses, "refuse-init");
        const initRun = w.run("setup", initRefuses, "");
        w.refused(initRun, "init-refused", "a refused init fails Setup");
        assert.match(initRun.stderr, /^jarvis-session: init=refused cause=other-entry entry="notes.txt"$/m, "with the package's own line");
        const lying = w.fresh();
        w.fault(lying, "init-lies");
        w.refused(w.run("setup", lying, ""), "still-missing cause=home=not-set-up", "an init that exits 0 without the starting files fails Setup");
    },
    // The clone: the history alone, then the checkout, its guards armed,
    // init's state folder, the main-host setting and its read-back.
    clone(w) {
        const main = w.main();
        const clone = w.fresh();
        const cloned = w.run("clone", clone, main, "main-pc");
        w.ok(cloned, "a clone of the main home is set up");
        const set = ["jarvis-session", "main-host", "--set", "main-pc", "--home", clone];
        assert.deepEqual(cloned.steps, [["git", "clone", "--no-checkout", "--", main, clone], ["git", "-C", clone, "reset", "--hard", "--quiet", "HEAD"],
            ["kendex", "guard", "install"], ["jarvis-session", "init", "--home", clone], set, ["jarvis-session", "main-host", "--get", "--home", clone]],
            "the clone runs its steps in D126's order");
        assert.deepEqual(planned(w, clone, "clone", main, "main-pc"), cloned.steps.slice(0, -1), "the TUI shows the steps the clone runs");
        assert.equal(fs.existsSync(path.join(clone, ".git", "guards-armed")), true, "its commit guards are armed");
        assert.equal(fs.readFileSync(path.join(clone, ".env.local"), "utf8"), "JARVIS_MAIN_HOST=main-pc\n", "and its main host set");
        assert.doesNotThrow(() => w.Home.judge(clone));
    },
    "clone-refusals"(w) {
        const main = w.main();
        for (const [name, prepare, args, key] of [
            ["an occupied destination is never replaced", folder => { fs.mkdirSync(folder); fs.writeFileSync(path.join(folder, "x"), ""); }, folder => [folder, main, "main-pc"], "occupied"],
            ["a source git reads as an option is refused", () => {}, folder => [folder, "--upload-pack=touch", "main-pc"], "clone-source"],
            ["an empty main host is refused", () => {}, folder => [folder, main, ""], "main-host-unset"]
        ]) {
            const folder = w.fresh();
            prepare(folder);
            const result = w.run("clone", ...args(folder));
            w.refused(result, key, name);
            assert.deepEqual(result.steps, [], name + " runs nothing");
        }
    },
    // A history that holds the private env file on any ref stops before a
    // file of it is checked out, and leaves nothing of it on this computer:
    // the folder the run made, or the entries of the empty folder it found.
    "clone-history"(w) {
        const main = w.main();
        const made = w.fresh();
        w.fault(made, "history-env");
        const leak = w.run("clone", made, main, "main-pc");
        w.refused(leak, "credentials-committed", "a main home whose history holds its credentials is refused");
        assert.equal(leak.code, 3, "with the exit that tells the TUI nothing was kept");
        assert.deepEqual(leak.steps, [["git", "clone", "--no-checkout", "--", main, made]], "and nothing is checked out or run in the clone");
        assert.equal(fs.existsSync(made), false, "and the folder the clone made is removed");
        const empty = w.fresh();
        fs.mkdirSync(empty);
        w.fault(empty, "history-env");
        w.refused(w.run("clone", empty, main, "main-pc"), "credentials-committed", "the same history into an empty folder is refused");
        assert.deepEqual(fs.readdirSync(empty), [], "and the folder is left empty");
        const merged = w.fresh();
        w.fault(merged, "merged-env");
        w.refused(w.run("clone", merged, main, "main-pc"), "credentials-committed", "a merged branch, its ref deleted, that held the credentials is refused");
        assert.equal(fs.existsSync(merged), false, "and nothing of it stays");
    },
    // A clone that ends before its checkout holds the package leaves the
    // folder as it was, so a retry clones again and completes.
    "clone-retry"(w) {
        const main = w.main();
        const plain = w.fresh("plain");
        fs.mkdirSync(path.join(plain, ".git"), { recursive: true });
        for (const [name, fault, from, key] of [
            ["a source without the package", null, plain, "clone-not-home"],
            ["a failed checkout", "fail-checkout", main, "checkout-failed"],
            ["an unreadable history", "log-fails", main, "git-unreadable"]
        ]) {
            const folder = w.fresh();
            if (fault !== null) w.fault(folder, fault);
            w.refused(w.run("clone", folder, from, "main-pc"), key, name + " stops the clone");
            assert.equal(fs.existsSync(folder), false, name + ": the folder the clone made is removed");
            if (fault !== null) w.clear(folder, fault);
            const retry = w.run("clone", folder, main, "main-pc");
            w.ok(retry, name + ": a retry from the main home completes");
            assert.deepEqual(retry.steps[0], ["git", "clone", "--no-checkout", "--", main, folder], name + ": and clones again");
        }
    },
    // Closing the terminal window during a step hangs up the whole run,
    // and the clone still removes what it wrote, so a retry completes.
    async "clone-hangup"(w) {
        const main = w.main();
        const folder = w.fresh();
        w.fault(folder, "hang-checkout");
        const hung = await w.hangUp("fixture: checkout=hung", "clone", folder, main, "main-pc");
        assert.notEqual(hung.code, 0, "a hung-up clone does not succeed");
        assert.equal(fs.existsSync(folder), false, "the folder the hung-up clone made is removed: " + hung.stderr);
        w.clear(folder, "hang-checkout");
        const retry = w.run("clone", folder, main, "main-pc");
        w.ok(retry, "a retry after the hangup completes");
        assert.deepEqual(retry.steps[0], ["git", "clone", "--no-checkout", "--", main, folder], "and clones again");
    },
    // A clone an earlier run left after its checkout continues from the
    // guards; one whose history or index holds the private env file is
    // occupied, and stays as it was.
    "clone-resume"(w) {
        const main = w.main();
        const clone = w.fresh();
        w.fault(clone, "fail-guard");
        w.refused(w.run("clone", clone, main, "main-pc"), "guard-failed", "a failed guard install stops the clone");
        w.clear(clone, "fail-guard");
        const resumed = w.run("clone", clone, main, "main-pc");
        w.ok(resumed, "the clone resumes");
        assert.deepEqual(resumed.steps, [["kendex", "guard", "install"], ["jarvis-session", "init", "--home", clone],
            ["jarvis-session", "main-host", "--set", "main-pc", "--home", clone], ["jarvis-session", "main-host", "--get", "--home", clone]],
            "from the guards, without a second clone");
        for (const fault of ["history-env", "tracked-env"]) {
            const leaked = w.fresh();
            w.fault(leaked, "fail-guard");
            w.refused(w.run("clone", leaked, main, "main-pc"), "guard-failed", fault + ": the first run stops");
            w.fault(leaked, fault);
            const before = fs.readdirSync(leaked).sort();
            const result = w.run("clone", leaked, main, "main-pc");
            w.refused(result, "occupied", fault + ": a left clone that holds the private env file is not resumed");
            assert.deepEqual(result.steps, [], fault + ": and nothing runs in it");
            assert.deepEqual(fs.readdirSync(leaked).sort(), before, fault + ": and it stays as it was");
        }
    },
    // The setting is read back through the package's own reader, and a
    // read that fails is its own refusal, never an unset setting.
    "clone-read-back"(w) {
        const main = w.main();
        const clone = w.fresh();
        w.fault(clone, "set-lost");
        w.refused(w.run("clone", clone, main, "main-pc"), "main-host-unset cause=read-back", "a main host the package did not keep fails the clone");
        const unread = w.fresh();
        w.fault(unread, "get-fails");
        w.refused(w.run("clone", unread, main, "main-pc"), "main-host-read cause=exit=1", "a failed read-back fails the clone with its exit");
    }
};

// Every case, or the case ONLY, over the fleet-setup.js beside DAEMON.
async function verify(daemon, tree, only = null) {
    const backend = path.dirname(daemon);
    const names = only === null ? Object.keys(CASES) : [only];
    // A plain Error, so a control naming no case fails its own harness
    // rather than read as detected.
    for (const name of names) if (!Object.hasOwn(CASES, name)) throw new Error("fleet case unknown: " + name);
    for (const name of names) {
        const base = fs.mkdtempSync(path.join(process.env.HOME, "fleet-" + name + "-"));
        await CASES[name](world(backend, tree, base));
    }
    if (only === null) console.log("test-jarvis-daemon: fleet=" + names.join(","));
}
module.exports = { verify };