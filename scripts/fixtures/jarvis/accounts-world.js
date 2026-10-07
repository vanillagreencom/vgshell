// Synthetic CLI/status and public Secret Service metadata, authored 2026-09-30.
// Sources: https://code.claude.com/docs/en/cli-reference (auth status JSON);
// https://github.com/openai/codex/blob/main/codex-rs/cli/src/login.rs
// (login status stderr); Secret Service 0.2 SearchItems and Item properties:
// https://specifications.freedesktop.org/secret-service/0.2/
// No recording, login, token file, keyring or inference endpoint is used.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const cp = require("node:child_process");
const tree = path.resolve(__dirname, "../../..");
const { FILES: CORE_FILES, useTree, scratchTree } = require("./core.js");
const prefix = `#!/usr/bin/env node
const fs=require("node:fs"), path=require("node:path");
const state=process.env.XDG_STATE_HOME;
const args=process.argv.slice(2);
function record(name) {
    fs.appendFileSync(path.join(state,name), JSON.stringify({args,env:process.env})+"\\n");
}
function mode(name, fallback) {
    try { return fs.readFileSync(path.join(state,name),"utf8").trim(); }
    catch(e) { if(e.code!=="ENOENT") throw e; return fallback; }
}
`;

function standins(directory) {
    fs.mkdirSync(directory, { recursive: true });
    fs.writeFileSync(path.join(directory, "claude"), prefix + `
record("cli-calls");
if(JSON.stringify(args)!==JSON.stringify(["auth","status"])) process.exit(9);
const selected=mode("claude-mode","signed-in");
if(selected==="late-link" && process.env.CLAUDE_CONFIG_DIR.endsWith("/late-account")
    && !fs.existsSync(process.env.CLAUDE_CONFIG_DIR))
    fs.symlinkSync(path.join(process.env.HOME,".claude"),process.env.CLAUDE_CONFIG_DIR);
if(selected==="failed"){console.error("fixture-secret-private");process.exit(7);}
if(selected==="junk"){console.log("fixture-secret-private");process.exit(0);}
// A folder's fixture-email file names its sign-in email; empty names none.
function email() {
    try { return fs.readFileSync(path.join(process.env.CLAUDE_CONFIG_DIR,"fixture-email"),"utf8").trim(); }
    catch(e) { if(e.code!=="ENOENT") throw e; return "team@example.invalid"; }
}
if(selected==="signed-in"||selected==="late-link") console.log(JSON.stringify({loggedIn:true, email:email(),subscriptionType:"pro",
    ignoredSecret:"fixture-secret-private"}));
else {console.log(JSON.stringify({loggedIn:false}));process.exit(1);}
`, { mode: 0o700 });
    fs.writeFileSync(path.join(directory, "codex"), prefix + `
// app-server answers initialize and account/read without a token refresh,
// as codex-rs/app-server-protocol v2 account.rs shapes them. The account's
// email is CODEX_HOME's fixture-email file, else codex@example.invalid.
if(JSON.stringify(args)===JSON.stringify(["app-server"])){
    record("app-calls");
    const appMode=mode("codex-app-mode","chatgpt");
    if(appMode==="exit") process.exit(3);
    // A silent program answers no account/read and ends on its own later.
    if(appMode==="silent") setTimeout(()=>process.exit(0),3000);
    let email="codex@example.invalid";
    try { email=fs.readFileSync(path.join(process.env.CODEX_HOME,"fixture-email"),"utf8").trim(); }
    catch(e) { if(e.code!=="ENOENT") throw e; }
    const reply=(id,result)=>process.stdout.write(JSON.stringify({id,result})+"\\n");
    let tail="";
    process.stdin.setEncoding("utf8");
    process.stdin.on("data",chunk=>{
        tail+=chunk;
        let at;
        while((at=tail.indexOf("\\n"))>=0){
            const message=JSON.parse(tail.slice(0,at));
            tail=tail.slice(at+1);
            if(message.method==="initialize") reply(message.id,{userAgent:"fixture"});
            else if(message.method==="account/read"&&appMode!=="silent"){
                if(JSON.stringify(message.params)!==JSON.stringify({refreshToken:false})) process.exit(8);
                reply(message.id,{account:appMode==="api"?{type:"apiKey"}:{type:"chatgpt",email,planType:"plus"},requiresOpenaiAuth:true});
            }
        }
    });
    process.stdin.on("end",()=>process.exit(0));
}else{
record("cli-calls");
if(JSON.stringify(args)!==JSON.stringify(["login","status"])) process.exit(9);
const selected=mode("codex-mode","signed-in");
if(selected==="failed"){console.error("fixture-secret-private");process.exit(7);}
if(selected==="junk"){console.error("fixture-secret-private");process.exit(0);}
if(selected==="signed-in") console.error("Logged in using ChatGPT");
else if(selected==="api") console.error("Logged in using an API key - fixture-secret-private");
else {console.error("Not logged in");process.exit(1);}
}
`, { mode: 0o700 });
    fs.writeFileSync(path.join(directory, "ss"), prefix + `
record("port-calls");
if(JSON.stringify(args)!==JSON.stringify(["-H","-ltn"])) process.exit(9);
const selected=mode("ports-mode","present");
if(selected==="failed"){console.error("fixture-secret-private");process.exit(7);}
if(selected==="junk"){console.log("fixture-secret-private");process.exit(0);}
if(selected==="present") console.log("LISTEN 0 4096 127.0.0.1:11434 0.0.0.0:*\\nLISTEN 0 4096 127.0.0.1:8080 0.0.0.0:*\\nLISTEN 0 4096 127.0.0.1:1234 0.0.0.0:*");
`, { mode: 0o700 });
    fs.writeFileSync(path.join(directory, "busctl"), prefix + `
record("bus-calls");
if(!args.includes("--auto-start=no")||!args.includes("--allow-interactive-authorization=no"))process.exit(9);
const selected=mode("bus-mode","present");
if(selected==="failed"){console.error("fixture-secret-private");process.exit(7);}
if(selected==="junk"){console.log('{"type":"s","data":["fixture-secret-private"]}');process.exit(0);}
const api="/org/freedesktop/secrets/collection/test/api";
const login="/org/freedesktop/secrets/collection/test/cli";
if(args.includes("SearchItems")){
    const all=args[args.indexOf("a{ss}")+1]==="0";
    const items=selected==="absent"?[]:selected==="too-many"?Array.from({length:33},(_,i)=>api+i):
        selected==="duplicate"?[api,api]:all?[api,login]:[api];
    console.log(JSON.stringify({type:"aoao",data:selected==="locked"?[[],items]:[items,[]]}));
}else if(args.includes("get-property")){
    const isLogin=args.includes(login);
    const property=args.at(-1);
    if(property==="Label") {
        const label=isLogin?"Claude Code-credentials":selected==="unicode-label"?"Other tool API clé":"Other tool API key";
        const data=selected==="property-extra"?[label,"extra"]:selected==="property-object"?{0:label,length:1}:
            [selected==="empty-label"?"":label];
        console.log(JSON.stringify({type:selected==="property-type"?"b":"s",data}));
    }
    else if(property==="Attributes") console.log(JSON.stringify({type:"a{ss}",data:[isLogin?
        {service:"Claude Code",account:"login"}:{application:"other-tool",id:"api-key"}]}));
    else process.exit(9);
}else process.exit(9);
`, { mode: 0o700 });
    fs.writeFileSync(path.join(directory, "secret-tool"), prefix + `
record("secret-calls");
if(args[0]==="lookup") {process.stdout.write("fixture-secret-private\\n");process.exit(0);}
console.error("fixture-secret-private");
process.exit(9);
`, { mode: 0o700 });
    fs.writeFileSync(path.join(directory, "gum"), prefix + `
record("gum-calls");
if(args[0]==="style") process.exit(0);
const queueFile=path.join(state,"gum-queue");
const queue=JSON.parse(fs.readFileSync(queueFile,"utf8"));
if(!queue.length) process.exit(9);
const answer=queue.shift();
fs.writeFileSync(queueFile,JSON.stringify(queue));
if(args[0]==="confirm") process.exit(answer==="no"?1:0);
if(answer==="first"){
    const lines=fs.readFileSync(0,"utf8").trim().split("\\n");
    console.log(lines[0]);
}else console.log(answer);
`, { mode: 0o700 });
}

function environment() {
    const env = {};
    for (const name of ["PATH", "HOME", "XDG_CONFIG_HOME", "XDG_STATE_HOME", "XDG_DATA_HOME",
        "XDG_RUNTIME_DIR", "DBUS_SESSION_BUS_ADDRESS"]) env[name] = process.env[name];
    return env;
}

function world(main) {
    if (process.argv[2] === "--inside") return Promise.resolve(main()).catch(error => { console.error(error); process.exitCode = 1; });
    const parent = path.join(tree, "tmp");
    fs.mkdirSync(parent, { recursive: true });
    const root = fs.realpathSync(fs.mkdtempSync(path.join(parent, "ja-")));
    try {
        standins(path.join(root, "standins"));
        const result = cp.spawnSync("/bin/bash", [path.join(tree, "scripts/lib/jarvis-env.sh"),
            path.join(root, "standins"), "--", "node", process.argv[1], "--inside"], {
            env: { PATH: "/usr/bin:/bin", HOME: root, JARVIS_TEST_SCRATCH_ROOT: parent },
            encoding: "utf8", timeout: 120000 });
        process.stdout.write(result.stdout || "");
        process.stderr.write(result.stderr || "");
        if (result.error) throw result.error;
        assert.equal(result.signal, null);
        process.exitCode = result.status;
    } finally { fs.rmSync(root, { recursive: true, force: true }); }
}

// Disposable copies keep real behavior and sibling imports. RELATIVE is a
// path in the plugin, or one of the core files by its path in the tree,
// whose mutation lands in a scratch tree the copy reads the core from. Each
// mutation must break its owning assertion, not merely make a process
// return nonzero.
async function mutant(relative, name, needle, replacement, check) {
    const plugin = path.join(tree, "shell/plugins/vgs.jarvis");
    const core = CORE_FILES.includes(relative);
    const source = fs.readFileSync(core ? path.join(tree, relative) : path.join(plugin, relative), "utf8");
    assert.equal(source.split(needle).length - 1, 1, name + " match");
    const changed = source.replace(needle, replacement);
    assert.notEqual(changed, source);
    const folder = fs.mkdtempSync(path.join(process.env.JARVIS_TEST_ROOT, "mutation-"));
    fs.mkdirSync(path.join(folder, "backend"));
    fs.mkdirSync(path.join(folder, "tui"));
    for (const file of ["AccountProviders.js", "AccountStatus.js", "backend/Accounts.js", "backend/Core.js",
        "backend/Secrets.js", "backend/accounts.js",
        "tui/accounts.sh", "tui/sign-in.sh", "backend/net.js", "backend/Policy.js", "backend/Audit.js", "backend/Private.js", "backend/Redact.js",
        "backend/Tools.js", "backend/ClaudeCode.js", "backend/Providers.js", "backend/CodexHarness.js",
        "backend/CopilotHarness.js", "backend/CopilotAcp.js", "backend/CodexAppServer.js"])
        fs.copyFileSync(path.join(plugin, file), path.join(folder, file));
    if (core) useTree(path.join(folder, "backend"), scratchTree(folder, { [relative]: changed }));
    else {
        fs.writeFileSync(path.join(folder, relative), changed);
        useTree(path.join(folder, "backend"));
    }
    try { await assert.rejects(async () => check(folder), assert.AssertionError, name + " must turn red"); }
    finally { fs.rmSync(folder, { recursive: true, force: true }); }
}

module.exports = { assert, fs, path, cp, tree, environment, world, standins, mutant };

// The nested service launches this worker inside J09. Fixture mode lives
// outside that fresh world so an accounts TUI end changes the next snapshot.
if (require.main === module) {
    const env = environment();
    const mode = fs.readFileSync(process.argv[3], "utf8").trim();
    if (mode === "invalid-output") {
        process.stdout.write("fixture-secret-private");
        process.exit(0);
    }
    if (mode === "raw-error" || mode === "oversize-error") {
        process.stderr.write(mode === "raw-error" ? "node: fixture-secret-private"
            : "jarvis-accounts: added=json\n" + "x".repeat(1024) + "fixture-secret-private");
        process.exit(1);
    }
    // "none" leaves no account: no folder, no signed-in default and no
    // listening local server.
    if (mode !== "none") fs.mkdirSync(path.join(env.HOME, ".claude-team"));
    fs.writeFileSync(path.join(env.XDG_STATE_HOME, "claude-mode"), ["found", "none"].includes(mode) ? "found" : "signed-in");
    if (mode === "none") {
        fs.writeFileSync(path.join(env.XDG_STATE_HOME, "codex-mode"), "found");
        fs.writeFileSync(path.join(env.XDG_STATE_HOME, "ports-mode"), "absent");
    }
    const directory = path.join(env.XDG_STATE_HOME, "vgshell/jarvis");
    fs.mkdirSync(directory, { recursive: true });
    if (mode === "failed") fs.writeFileSync(path.join(directory, "accounts.json"), "broken");
    // More home names than bin/lib/account-folders.js MAX_PARENT_ENTRIES, and a
    // folder in the config home: a partial search. The labels of the folders
    // among the first 10000 home names fs.opendirSync hands out, and the
    // config home's, go beside the mode file for the row to compare.
    if (mode === "entry-limit") {
        for (let index = 0; index < 8; index++) fs.mkdirSync(path.join(env.HOME, ".claude-" + index));
        for (let index = 0; index <= 10000; index++) fs.writeFileSync(path.join(env.HOME, String(index)), "");
        fs.mkdirSync(path.join(env.XDG_CONFIG_HOME, ".claude-work"), { recursive: true });
        const labels = ["work"];
        const listing = fs.opendirSync(env.HOME);
        try {
            for (let read = 0, entry; read < 10000 && (entry = listing.readSync()) !== null; read++)
                if (entry.isDirectory() && entry.name.startsWith(".claude-")) labels.push(entry.name.slice(".claude-".length));
        } finally { listing.closeSync(); }
        fs.writeFileSync(path.join(path.dirname(process.argv[3]), "account-labels"), JSON.stringify(labels.sort()) + "\n");
    }
    // A linked config home: the search does not follow it.
    if (mode === "parent-unreadable") {
        const target = path.join(env.HOME, "config-target");
        fs.mkdirSync(path.join(target, ".claude-behind"), { recursive: true });
        fs.rmSync(env.XDG_CONFIG_HOME, { recursive: true, force: true });
        fs.symlinkSync(target, env.XDG_CONFIG_HOME);
    }
    const result = cp.spawnSync("node", [process.argv[2], "--tree", process.argv[4], "presence", process.argv[5]], {
        env, stdio: "inherit" });
    process.exit(result.status ?? 1);
}
