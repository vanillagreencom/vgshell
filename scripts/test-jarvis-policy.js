#!/usr/bin/env node
// Complete profile matrix and independent refusal controls in the J09 world.
"use strict";
const { assert, fs, path, tree, world, seed, mutant } = require("./fixtures/jarvis/policy.js");
const file = path.join(tree, "shell/plugins/vgs.jarvis/backend/Policy.js");
const Policy = require(file);
const Denied = require("../shell/plugins/vgs.jarvis/backend/Denied.js");

world(() => {
    const { home, project, roots } = seed();
    const newFile = path.join(project, "new");
    const existing = path.join(project, "existing");
    const input = { target: { kind: "application", id: "org.example.Editor" }, text: { effective: [] } };
    const site = { target: { kind: "site", id: "https://example.test", password: false } };
    const context = { profile: "standard", locked: false, taint: { kind: "clean" },
        denied: Denied.create(roots), input, grants: [] };
    const call = (id, args) => ({ id, args });
    const effects = {
        read: call("files.read", { path: existing }),
        reversible: call("windows.focus", { window: "0x123" }),
        input: call("input.text", { text: "literal" }),
        persistent: call("files.write", { path: newFile, text: "" }),
        exec: call("shell.line", { line: "echo literal", cwd: project, network: false }),
        external: call("browser", { command: "submit", args: { ref: "@e1" } }),
        destructive: call("files.delete", { path: existing })
    };
    const memoryWrite = call("memory.replace", { id: "facts/a.md", text: "new", hash: "a".repeat(64) });
    // Independent J47/J51 call contracts. Key facts name an unbound key so
    // target refusals cannot pass by hitting the own-chord guard instead.
    const inputRoutes = [
        [effects.input, "text"],
        [call("input.key", { chord: "SUPER+A" }), "key", {
            request: "SUPER+A", chord: { modifiers: ["SUPER"], keycode: 38 }, effective: []
        }],
        [call("input.click", { x: 0, y: 0, button: "left" }), "pointer"],
        [call("input.scroll", { x: 0, y: 0, direction: "down", steps: 1 }), "pointer"],
        [call("browser", { command: "click", args: { ref: "@e1" } }), "browser"],
        [call("browser", { command: "fill", args: { ref: "@e1", text: "literal" } }), "browser"],
        [effects.external, "browser"]
    ];
    // Expected decisions are independent of the production profile table.
    const profiles = [
        ["cautious", ["allow", "allow", "confirm", "confirm", "confirm", "confirm", "physical"]],
        ["standard", ["allow", "allow", "scope", "allow", "confirm", "confirm", "physical"]],
        ["trusted", ["allow", "allow", "allow", "allow", "allow", "confirm", "physical"]]
    ];
    // Every confirm names the key Always allow saves, the tool, its effect,
    // its input target and each judged path by its field, or an
    // application's scope, with the line its card shows (fitted to a row
    // label by grantLine, whose table is below).
    const keys = { input: "input.text:input:application=org.example.Editor", persistent: "files.write:persistent:path=" + newFile,
        exec: "shell.line:exec:cwd=" + project, external: "browser:external:site=https%3A//example.test",
        destructive: "files.delete:destructive:path=" + existing };
    const lines = { input: "Type any text in org.example.Editor", persistent: "Write any text to " + newFile,
        exec: "Run any command in " + project, external: "Submit anything on https://example.test", destructive: "Delete " + existing };
    function expected(effect, rule) {
        if (rule === "allow") return { kind: "allow", effect };
        const result = { kind: "confirm", effect, physical: rule === "physical" };
        if (rule === "scope") Object.assign(result, { scope: "application:org.example.Editor", grant: "application:org.example.Editor",
            line: "Any input anywhere in org.example.Editor" });
        else Object.assign(result, { grant: keys[effect], line: Policy.grantLine(lines[effect]) });
        return result;
    }
    // A decision without its key, for a row about something else.
    function bare(decision) {
        const { grant: _grant, line: _line, ...rest } = decision;
        return rest;
    }
    function checkCell(logic, profile, effect, rule) {
        const current = { ...context, profile, input: effect === "external" ? site : input };
        assert.deepEqual(logic.decide(effects[effect], current), expected(effect, rule), profile + " " + effect);
    }
    for (const [profile, rules] of profiles)
        Object.keys(effects).forEach((effect, index) => checkCell(Policy, profile, effect, rules[index]));

    // Always allow: one table of grant, reuse and removal (D139). Each row
    // decides a call with ALLOWED, the saved keys, and expects its decision.
    // A key covers its own kind of request alone, and every kind takes one:
    // a networked run, a destructive step and a tainted turn's request too.
    // A forward to Jarvis main takes none: its record cites one confirmation.
    const otherFolder = path.join(home, "elsewhere");
    fs.mkdirSync(otherFolder, { recursive: true });
    const networked = call("shell.line", { line: "echo literal", cwd: project, network: true });
    const forward = call("fleet.forward", { text: "status" });
    const task = (agent, account) => call("task.start", { goal: "fix", cwd: project, ...(agent ? { agent } : {}), ...(account ? { account } : {}) });
    // A harness program's proposal; harnessCases below judges each entry.
    const harnessFiles = (write, move = [], remove = []) => call("harness.files", { write, move, remove, diff: "" });
    const asks = (effect, physical, grant, line, extra = {}) => ({ kind: "confirm", effect, physical, ...extra, grant, line: Policy.grantLine(line) });
    const netKey = "shell.line:external:cwd=" + project;
    const taskKey = "task.start:exec:cwd=" + project + ":agent=codex:account=work";
    const editor = "application:org.example.Editor";
    const editorLine = "Any input anywhere in org.example.Editor";
    const other = { ...input, target: { kind: "application", id: "org.example.Other" } };
    const typedTerminal = { target: { kind: "terminal", id: "org.example.Terminal" }, text: { effective: [] } };
    const second = path.join(path.dirname(newFile), "second.txt");
    const writeExisting = "harness.files:destructive:write=" + existing;
    const writeBoth = "harness.files:persistent:write=" + newFile + ":write=" + second;
    const grantRows = [
        ["exec asks with its key", effects.exec, [], {}, asks("exec", false, keys.exec, lines.exec)],
        ["exec under its key is allowed", effects.exec, [keys.exec], {}, { kind: "allow", effect: "exec", grant: keys.exec }],
        ["a removed key asks again", effects.exec, [], {}, asks("exec", false, keys.exec, lines.exec)],
        ["another folder's key covers none", call("shell.line", { line: "echo literal", cwd: otherFolder, network: false }), [keys.exec], {},
            asks("exec", false, "shell.line:exec:cwd=" + otherFolder, "Run any command in " + otherFolder)],
        ["application under its key is allowed", effects.input, [editor], {}, { kind: "allow", effect: "input", grant: editor }],
        ["another application's key covers none", effects.input, ["application:org.example.Other"], {},
            asks("input", false, editor, editorLine, { scope: editor })],
        ["another application's card names that application", effects.input, [editor], { input: other },
            asks("input", false, "application:org.example.Other", "Any input anywhere in org.example.Other",
                { scope: "application:org.example.Other" })],
        ["a tainted turn's input card names the application its key covers", effects.input, [], { taint: { kind: "tainted" } },
            asks("input", false, editor, editorLine)],
        ["a cautious input card names any text in its target", effects.input, [], { profile: "cautious" },
            asks("input", false, keys.input, lines.input)],
        ["a browser submit names any submit on its site", effects.external, [], { input: site }, asks("external", false, keys.external, lines.external)],
        ["a terminal's typing names any text there", effects.input, [], { profile: "trusted", input: typedTerminal },
            asks("destructive", true, "input.text:destructive:terminal=org.example.Terminal", "Type any text in org.example.Terminal")],
        ["a mailbox request names any request", call("fleet.request", { text: "status" }), [], {},
            asks("exec", false, "fleet.request:exec", "Put any request in your Jarvis session mailbox")],
        ["a networked run asks with its own key", networked, [keys.exec], {}, asks("external", false, netKey, "Run any online command in " + project)],
        ["a networked run under its key is allowed", networked, [netKey], {}, { kind: "allow", effect: "external", grant: netKey }],
        ["a destructive step asks with its key", effects.destructive, [], {}, asks("destructive", true, keys.destructive, lines.destructive)],
        ["a destructive step under its key is allowed", effects.destructive, [keys.destructive], {}, { kind: "allow", effect: "destructive", grant: keys.destructive }],
        ["a tainted turn asks with the same key", effects.exec, [], { taint: { kind: "tainted" } }, asks("exec", false, keys.exec, lines.exec)],
        ["a tainted turn under the key is allowed", effects.exec, [keys.exec], { taint: { kind: "tainted" } }, { kind: "allow", effect: "exec", grant: keys.exec }],
        ["a task's key names its agent and account", task("codex", "work"), [taskKey], {}, { kind: "allow", effect: "exec", grant: taskKey }],
        ["another agent asks again", task("claude", "work"), [taskKey], {},
            asks("exec", false, "task.start:exec:cwd=" + project + ":agent=claude:account=work", "Start any claude task with account work in " + project)],
        ["another account asks again", task("codex", "home"), [taskKey], {},
            asks("exec", false, "task.start:exec:cwd=" + project + ":agent=codex:account=home", "Start any codex task with account home in " + project)],
        ["a saved overwrite still asks for a remove of that file", harnessFiles([], [], [existing]), [writeExisting], {},
            asks("destructive", true, "harness.files:destructive:remove=" + existing, "Remove files: " + existing)],
        ["a split across fields is not one list", harnessFiles([newFile], [second]), [writeBoth], { profile: "cautious" },
            asks("persistent", false, "harness.files:persistent:write=" + newFile + ":move=" + second,
                "Move and write any text to files: " + second + "; " + newFile)],
        ["a forward takes no key", forward, [netKey, "fleet.forward:external"], {}, { kind: "confirm", effect: "external", physical: false }]
    ];
    assert.deepEqual(Policy.decide(harnessFiles([existing]), context).grant, writeExisting, "always allow: an overwrite's key names its role");
    // A line's cut shortens path text alone: every role and wildcard word
    // comes before the first path. Two scratch paths overrun the 60-unit
    // line; a deeper folder would overrun the 256-unit key too under a long
    // TMPDIR, and a key past it is named on no card.
    const cut = Policy.decide(harnessFiles([newFile], [], [existing]), context).line;
    assert.deepEqual([cut.startsWith("Remove and write any text to files: "), cut.length <= 60, cut.endsWith("…")], [true, true, true],
        "always allow: a cut line still names every role");
    const moveCut = Policy.decide(call("files.move", { from: existing, to: newFile }), { ...context, profile: "cautious" }).line;
    assert.deepEqual([moveCut.startsWith("Move a file, from and to: "), moveCut.length <= 60], [true, true],
        "always allow: a cut move line still names both roles");
    for (const [name, action, allowed, extra, want] of grantRows)
        assert.deepEqual(Policy.decide(action, { ...context, ...extra, allowed }), want, "always allow: " + name);
    // Two requests share a key only when every part is equal: each part
    // names its field, and a value holding a joining character keeps it
    // escaped. Each pair would join to one key otherwise; a saved key allows
    // only its own request. Each key holds one scratch path, so it stays a
    // row id under a long TMPDIR.
    const apart = [
        ["one path in two roles", harnessFiles([newFile]), harnessFiles([], [newFile])],
        ["an agent that names an account", task("codex:account=work"), task("codex", "work")]];
    for (const [name, first, second] of apart) {
        const [one, two] = [first, second].map(action => Policy.decide(action, { ...context, profile: "cautious" }));
        assert.deepEqual([typeof one.grant, typeof two.grant, one.grant === two.grant], ["string", "string", false], "always allow: two keys for " + name);
        assert.equal(Policy.decide(second, { ...context, profile: "cautious", allowed: [one.grant] }).kind, "confirm",
            "always allow: one key does not allow the other: " + name);
    }
    // A key is a status row id (TuiArguments): a folder named with a C1
    // control gives none, so it is never saved; one with a line separator
    // gives one, and its line (grantLine) drops the separator.
    for (const [name, keyed] of [["c\u0085d", false], ["a\u2028b", true]]) {
        const odd = path.join(home, name);
        fs.mkdirSync(odd, { recursive: true });
        assert.equal(Policy.decide(call("shell.line", { line: "echo literal", cwd: odd, network: false }), context).grant,
            keyed ? "shell.line:exec:cwd=" + odd : undefined, "always allow: a key only a row id can hold: " + JSON.stringify(name));
    }
    assert.deepEqual(["shell.line:exec:cwd=/x", "application:a", "site:https%3A//a", "release:screen:recipient=p|a|https%3A//o"].map(Policy.grantKind),
        ["shell.line:exec", "application", "site", "release:screen"], "an audit names a key's kind alone");
    // A key's line is one the status rows judge takes as a label: one line
    // of at most 60 UTF-16 units, cut before a whole character.
    for (const [name, text, line] of [
        ["a short line is kept", "Run commands in /home/u/proj", "Run commands in /home/u/proj"],
        ["a line separator becomes a space", "Run commands in /home/u/a b", "Run commands in /home/u/a b"],
        ["a long line is cut to 60", "a".repeat(70), "a".repeat(59) + "…"],
        ["a cut never splits a character or passes 60 units", "a".repeat(58) + "\u{1F600}bbb", "a".repeat(58) + "…"]])
        assert.equal(Policy.grantLine(text), line, "always allow: " + name);
    assert.deepEqual(Policy.decide(effects.exec, { ...context, allowed: "shell.line" }), { kind: "refuse", reason: "allowed-grants" });

    const refuse = (logic, action, current, reason) => {
        let result;
        assert.doesNotThrow(() => { result = logic.decide(action, current); }, "typed refusals must not throw");
        assert.deepEqual([result.kind, result.reason], ["refuse", reason], reason);
    };
    for (const [profile] of profiles) {
        for (const locked of [true, undefined, null, "false"])
            for (const action of Object.values(effects))
                refuse(Policy, action, { ...context, profile, locked }, "session-locked");
        for (const taintEffect of ["input", "persistent", "exec", "external"]) {
            const current = { ...context, profile, taint: { kind: "tainted" },
                input: taintEffect === "external" ? site : input, grants: ["application:org.example.Editor"] };
            // A tainted turn's confirm names the same key a clean one does.
            const applicationScope = taintEffect === "input" && profile === "standard";
            assert.deepEqual(Policy.decide(effects[taintEffect], current), asks(taintEffect, false,
                applicationScope ? editor : keys[taintEffect], applicationScope ? editorLine : lines[taintEffect]));
        }
        assert.deepEqual(Policy.decide(memoryWrite, { ...context, profile, taint: { kind: "tainted" } }),
            { kind: "allow", effect: "persistent" }, "tainted memory writes reach Memory.js quarantine");
        for (const effect of ["read", "reversible", "destructive"])
            assert.deepEqual(Policy.decide(effects[effect], { ...context, profile, taint: { kind: "tainted" } }),
                expected(effect, effect === "destructive" ? "physical" : "allow"));
        for (const target of ["vgs", "lock", "polkit"])
            for (const [action, , key] of inputRoutes)
                refuse(Policy, action, { ...context, profile, input: { target: { kind: target, id: "protected" }, key } }, "protected-target");
        for (const [action] of inputRoutes.filter(row => row[1] === "browser")) {
            for (const password of [true, undefined])
                refuse(Policy, action, { ...context, profile, input: { target: { ...site.target, password } } }, "password-target");
            refuse(Policy, action, { ...context, profile, input }, "browser-target");
        }
        for (const file of [
            path.join(home, ".ssh", "absent"), path.join(roots.config, "vgshell", "shell.json"),
            path.join(roots.state, "vgshell", "jarvis", "audit.jsonl")
        ]) {
            for (const action of [
                call("files.read", { path: file }), call("files.write", { path: file, text: "" }),
                call("files.delete", { path: file }), call("apps.open", { path: file }),
                call("shell.line", { line: "pwd", cwd: file, network: false }),
                call("task.start", { goal: "synthetic task", cwd: file }),
                call("files.move", { from: file, to: newFile }),
                call("files.move", { from: existing, to: file })
            ]) refuse(Policy, action, { ...context, profile }, "protected-path");
        }
        for (const argv of [["sudo", "true"], ["su", "-c", "synthetic"], ["/usr/bin/sudoedit", existing]])
            refuse(Policy, call("shell.argv", { argv, cwd: project, network: false }),
                { ...context, profile }, "privilege-elevation");
    }
    for (const source of ["file", "web", "screen", "agent"]) {
        assert.deepEqual(Policy.observe({ kind: "clean" }, source), { kind: "tainted" });
        assert.deepEqual(Policy.observe({ kind: "tainted" }, source), { kind: "tainted" });
    }
    for (const source of ["speech", "desktop", "home", "clipboard", "command"]) {
        assert.deepEqual(Policy.observe({ kind: "clean" }, source), { kind: "clean" });
        assert.deepEqual(Policy.observe({ kind: "tainted" }, source), { kind: "tainted" });
    }
    assert.throws(() => Policy.observe({ kind: "clean" }, "unknown"), { message: "jarvis: taint=invalid" });
    refuse(Policy, effects.read, { ...context, profile: "unknown" }, "policy-profile");
    refuse(Policy, effects.read, { ...context, taint: null }, "turn-taint");
    refuse(Policy, effects.read, { ...context, denied: null }, "path-context");
    // The snapshot is read only for a call that carries a path.
    const unread = Logic => {
        let reads = 0;
        const counted = { ...context };
        Object.defineProperty(counted, "denied", { get() { reads++; return context.denied; } });
        assert.deepEqual(Logic.decide(effects.reversible, counted), { kind: "allow", effect: "reversible" });
        assert.equal(reads, 0, "a call without a path never builds the snapshot");
        assert.equal(Logic.decide(effects.read, counted).kind, "allow");
        assert.equal(reads, 1, "a path call reads it once");
    };
    unread(Policy);
    refuse(Policy, call("unknown", {}), context, "unknown-tool");
    refuse(Policy, effects.input, { ...context, input: null }, "input-target");
    refuse(Policy, effects.input, { ...context, input: { target: { kind: "unknown", id: "x" } } }, "input-target");
    refuse(Policy, effects.input, { ...context, input: { target: { kind: "application", id: "" } } }, "input-identity");
    refuse(Policy, effects.input, { ...context, input: site }, "desktop-target");
    refuse(Policy, effects.external, context, "browser-target");
    refuse(Policy, effects.external, { ...context, input: { target: { ...site.target, password: true } } }, "password-target");
    refuse(Policy, effects.external, { ...context, input: { target: { kind: "site", id: site.target.id } } }, "password-target");
    refuse(Policy, effects.input, { ...context, grants: null }, "input-grants");
    assert.deepEqual(Policy.decide(effects.input, { ...context, grants: ["application:org.example.Editor"] }), expected("input", "allow"));
    assert.deepEqual(Policy.decide(effects.input, { ...context, grants: ["application:org.example.Other"] }), expected("input", "scope"));
    const browserInput = call("browser", { command: "fill", args: { ref: "@e1", text: "literal" } });
    assert.deepEqual(Policy.decide(browserInput, { ...context, input: site }),
        asks("input", false, "site:https%3A//example.test", "Click and type anything on https://example.test", { scope: "site:https://example.test" }));
    assert.deepEqual(Policy.decide(browserInput, { ...context, input: site, grants: ["site:https://example.test"] }),
        { kind: "allow", effect: "input" });
    const terminal = { target: { kind: "terminal", id: "org.example.Terminal" }, text: { effective: [] } };
    for (const profile of ["cautious", "standard"])
        for (const kind of ["clean", "tainted"])
            refuse(Policy, effects.input, { ...context, profile, input: terminal, taint: { kind } }, "terminal-text");
    for (const kind of ["clean", "tainted"])
        assert.deepEqual(Policy.decide(effects.input, { ...context, profile: "trusted", input: terminal, taint: { kind } }),
            asks("destructive", true, "input.text:destructive:terminal=org.example.Terminal", "Type any text in org.example.Terminal"));
    for (const [profile] of profiles)
        for (const kind of ["clean", "tainted"])
            for (const [action, , key] of inputRoutes.filter(row => ["key", "pointer"].includes(row[1])))
                refuse(Policy, action, { ...context, profile, taint: { kind },
                    input: { ...terminal, key }, grants: ["terminal:org.example.Terminal"] }, "terminal-input");
    const pressed = call("input.key", { chord: "ALT+SUPER+Y" });
    const keyContext = { ...context, input: { ...input, key: {
        request: pressed.args.chord, chord: { modifiers: ["ALT", "SUPER"], keycode: 29 },
        effective: [{ modifiers: ["SUPER", "ALT"], keycode: 29 }],
        emitted: { modifiers: ["SUPER", "ALT"], keycode: 9 }, emittedEffective: []
    } } };
    for (const [profile] of profiles)
        refuse(Policy, pressed, { ...keyContext, profile }, "jarvis-chord");
    const codePressed = call("input.key", { chord: "SUPER+ALT+code:29" });
    // The producer resolves both spellings to the same physical key identity.
    refuse(Policy, codePressed, { ...keyContext, input: { ...keyContext.input,
        key: { ...keyContext.input.key, request: codePressed.args.chord } } }, "jarvis-chord");
    refuse(Policy, pressed, context, "key-context");
    refuse(Policy, pressed, { ...keyContext, input: { ...keyContext.input,
        key: { ...keyContext.input.key, request: "SUPER+A" } } }, "key-context");
    for (const chord of [{ modifiers: ["SUPER", "SUPER"], keycode: 29 }, { modifiers: [""], keycode: 29 },
        { modifiers: [], keycode: 0 }, null])
        refuse(Policy, pressed, { ...keyContext, input: { ...keyContext.input,
            key: { ...keyContext.input.key, chord } } }, "key-context");
    const allowedKey = { ...keyContext, profile: "trusted", input: { ...keyContext.input,
        key: { ...keyContext.input.key, effective: [{ modifiers: ["SUPER"], keycode: 29 }] } } };
    assert.deepEqual(Policy.decide(pressed, allowedKey), expected("input", "allow"));

    const overwrite = call("files.write", { path: existing, text: "replace" });
    const moved = call("files.move", { from: existing, to: newFile });
    const moveOverwrite = call("files.move", { from: existing, to: existing });
    const executionWrite = call("files.write", { path: path.join(home, ".bashrc"), text: "" });
    const executionWorkspace = call("shell.argv", { argv: ["pwd"], cwd: path.join(home, ".local/bin"), network: true });
    for (const [profile] of profiles) {
        for (const action of [overwrite, moveOverwrite, executionWrite, executionWorkspace])
            for (const kind of ["clean", "tainted"])
                assert.deepEqual(bare(Policy.decide(action, { ...context, profile, taint: { kind } })), bare(expected("destructive", "physical")));
        assert.deepEqual(bare(Policy.decide(moved, { ...context, profile })),
            bare(expected("persistent", profile === "cautious" ? "confirm" : "allow")));
    }
    const linkedProfile = path.join(project, "profile");
    fs.symlinkSync(path.join(home, ".bashrc"), linkedProfile);
    // A dangling link is refused, not classified as an absent write.
    refuse(Policy, call("files.write", { path: linkedProfile, text: "" }), context, "path-resolution");

    // A harness program's proposal names each path; every entry is judged.
    const harnessCommand = call("harness.command", { command: "ls -la", cwd: project });
    const harnessCases = logic => {
        for (const [profile] of profiles) {
            assert.deepEqual(bare(logic.decide(harnessFiles([newFile]), { ...context, profile })),
                bare(expected("persistent", profile === "cautious" ? "confirm" : "allow")));
            for (const action of [harnessFiles([newFile, existing]), harnessFiles([], [], [newFile]),
                harnessFiles([newFile, path.join(home, ".bashrc")])])
                assert.deepEqual(bare(logic.decide(action, { ...context, profile })), bare(expected("destructive", "physical")));
            refuse(logic, harnessFiles([newFile, path.join(home, ".ssh", "absent")]), { ...context, profile }, "protected-path");
            if (profile === "trusted")
                assert.deepEqual(bare(logic.decide(harnessCommand, { ...context, profile })), bare(expected("destructive", "physical")));
            else refuse(logic, harnessCommand, { ...context, profile }, "unconfined-command");
        }
    };
    harnessCases(Policy);

    // A command that names no folder carries no path: the gate decides it by
    // its effect alone. A named folder is judged as before, so the brain's
    // own private working folder and HOME, which holds every credential
    // root, stay refused, while a file folder inside HOME stays readable.
    const brainFolder = path.join(roots.runtime, "vgshell", "jarvis", "claude-synthetic", "cwd");
    fs.mkdirSync(brainFolder, { recursive: true });
    const folderCases = logic => {
        for (const [id, args] of [["shell.argv", { argv: ["date"], network: false }], ["shell.line", { line: "date", network: false }]]) {
            // With no folder the command runs in a new empty one: its key
            // names no folder.
            assert.deepEqual(logic.decide(call(id, args), context), asks("exec", false, id + ":exec", "Run any command in a new empty folder"), id);
            assert.deepEqual(logic.decide(call(id, args), { ...context, profile: "trusted" }), { kind: "allow", effect: "exec" }, id);
            for (const cwd of [brainFolder, home]) refuse(logic, call(id, { ...args, cwd }), context, "protected-path");
        }
        assert.deepEqual(logic.decide(call("files.list", { path: project }), context), { kind: "allow", effect: "read" });
        for (const folder of [brainFolder, path.join(home, ".ssh")]) refuse(logic, call("files.list", { path: folder }), context, "protected-path");
    };
    folderCases(Policy);

    let controls = 0;
    function control(name, needle, replacement, assertion) {
        mutant(file, name, needle, replacement, assertion);
        controls++;
    }
    control("absent-path-field", ".filter(([field]) => Object.hasOwn(refined.call.args, field))", "", folderCases);
    const source = fs.readFileSync(file, "utf8");
    for (const [profile, rules] of profiles) {
        const line = source.split("\n").find(line => line.trim().startsWith(profile + ": {"));
        Object.keys(effects).forEach((effect, index) => {
            const original = rules[index] === "scope" ? "application" : rules[index];
            const wrong = original === "allow" ? "confirm" : "allow";
            control("profile-" + profile + "-" + effect, line, line.replace(`${effect}: "${original}"`, `${effect}: "${wrong}"`),
                logic => checkCell(logic, profile, effect, rules[index]));
        });
    }
    control("lock", 'if (!context || context.locked !== false)', 'if (false && (!context || context.locked !== false))',
        logic => refuse(logic, effects.reversible, { ...context, locked: true }, "session-locked"));
    control("unknown-profile", 'if (!Object.hasOwn(PROFILES, context.profile))',
        'if (false && !Object.hasOwn(PROFILES, context.profile))',
        logic => refuse(logic, effects.read, { ...context, profile: "unknown", denied: null }, "policy-profile"));
    control("missing-taint", 'if (!context.taint || !["clean", "tainted"].includes(context.taint.kind))',
        'if (false && (!context.taint || !["clean", "tainted"].includes(context.taint.kind)))',
        logic => refuse(logic, call("unknown", {}), { ...context, taint: null }, "turn-taint"));
    control("typed-call", 'if (refined.kind === "refuse") return refined;',
        'if (refined.kind === "refuse") return { kind: "allow", effect: "read" };',
        logic => refuse(logic, call("unknown", {}), context, "unknown-tool"));
    control("path-context", 'return { kind: "refuse", reason: "path-context" };',
        'return { kind: "allow", effect: "read" };',
        logic => refuse(logic, effects.read, { ...context, denied: null }, "path-context"));
    control("denied-answer", 'if (judged.kind === "refuse") {', 'if (false) {',
        logic => refuse(logic, call("files.read", { path: path.join(home, ".ssh", "absent") }), context, "protected-path"));
    control("lazy-snapshot", "if (refined.paths.length > 0) {", "if (void context.denied, refined.paths.length > 0) {", unread);
    control("execution-write", 'target.execution || role === "remove"', 'false || role === "remove"',
        logic => assert.deepEqual(bare(logic.decide(executionWrite, context)), bare(expected("destructive", "physical"))));
    control("overwrite", '(role === "write" && target.exists)', '(false && role === "write" && target.exists)',
        logic => assert.deepEqual(bare(logic.decide(overwrite, context)), bare(expected("destructive", "physical"))));
    control("input-target", 'return { kind: "refuse", reason: "input-target" };',
        'return { kind: "allow", effect: "input" };',
        logic => refuse(logic, effects.input, { ...context, input: null }, "input-target"));
    control("protected-target", 'if (["vgs", "lock", "polkit"].includes(input.target.kind))',
        'if (false && ["vgs", "lock", "polkit"].includes(input.target.kind))',
        logic => refuse(logic, effects.input, { ...context, profile: "trusted",
            input: { target: { kind: "vgs", id: "protected" } } }, "protected-target"));
    control("input-id", 'if (typeof input.target.id !== "string" || input.target.id === "")',
        'if (false && (typeof input.target.id !== "string" || input.target.id === ""))',
        logic => refuse(logic, effects.input, { ...context, input: { target: { kind: "application", id: "" } } }, "input-identity"));
    control("browser-target", 'if (input.target.kind !== "site")',
        'if (false && input.target.kind !== "site")',
        logic => refuse(logic, effects.external, context, "browser-target"));
    control("password", 'if (input.target.password !== false)',
        'if (false && input.target.password !== false)',
        logic => refuse(logic, effects.external, { ...context, input: { target: { ...site.target, password: true } } }, "password-target"));
    control("desktop-target", 'if (input.target.kind === "site")',
        'if (false && input.target.kind === "site")',
        logic => refuse(logic, effects.input, { ...context, input: site }, "desktop-target"));
    control("key-context", 'return { kind: "refuse", reason: "key-context" };',
        'return { kind: "allow", effect: "input" };',
        logic => refuse(logic, pressed, context, "key-context"));
    const unbound = { ...keyContext, input: { ...keyContext.input,
        key: { ...keyContext.input.key, effective: [] } } };
    control("key-request", 'key.request !== call.args.chord', 'false',
        logic => refuse(logic, pressed, { ...unbound, input: { ...unbound.input,
            key: { ...unbound.input.key, request: "other" } } }, "key-context"));
    control("effective-shapes", '!key.effective.every(chord)', 'false',
        logic => refuse(logic, pressed, { ...unbound, input: { ...unbound.input,
            key: { ...unbound.input.key, effective: [{ modifiers: [], keycode: 0 }] } } }, "key-context"));
    control("effective-array", '!Array.isArray(key.effective)', 'false',
        logic => refuse(logic, pressed, { ...unbound, input: { ...unbound.input,
            key: { ...unbound.input.key, effective: {} } } }, "key-context"));
    control("modifier-array", 'Array.isArray(value.modifiers)', 'true',
        logic => refuse(logic, pressed, { ...unbound, input: { ...unbound.input,
            key: { ...unbound.input.key, chord: { modifiers: "SUPER", keycode: 29 } } } }, "key-context"));
    control("chord-positive", 'value.keycode > 0', 'true',
        logic => refuse(logic, pressed, { ...unbound, input: { ...unbound.input,
            key: { ...unbound.input.key, chord: { modifiers: [], keycode: 0 } } } }, "key-context"));
    control("chord-integer", 'Number.isSafeInteger(value.keycode)', 'true',
        logic => refuse(logic, pressed, { ...unbound, input: { ...unbound.input,
            key: { ...unbound.input.key, chord: { modifiers: [], keycode: 0.5 } } } }, "key-context"));
    control("chord-modifier-set", 'new Set(value.modifiers).size === value.modifiers.length', 'true',
        logic => refuse(logic, pressed, { ...unbound, input: { ...unbound.input,
            key: { ...unbound.input.key, chord: { modifiers: ["SUPER", "SUPER"], keycode: 29 } } } }, "key-context"));
    control("chord-modifier-kind", 'value.modifiers.every(mod => typeof mod === "string" && mod !== "")', 'true',
        logic => refuse(logic, pressed, { ...unbound, input: { ...unbound.input,
            key: { ...unbound.input.key, chord: { modifiers: [null], keycode: 29 } } } }, "key-context"));
    control("emitted-context", '!chord(key.emitted)', 'false',
        logic => refuse(logic, pressed, { ...unbound, input: { ...unbound.input,
            key: { ...unbound.input.key, emitted: undefined } } }, "key-context"));
    control("emitted-own-chord", 'if (key.emittedEffective.some(bound => sameChord(key.emitted, bound)))',
        'if (false && key.emittedEffective.some(bound => sameChord(key.emitted, bound)))',
        logic => refuse(logic, pressed, { ...unbound, input: { ...unbound.input,
            key: { ...unbound.input.key, emittedEffective: [{ modifiers: ["SUPER", "ALT"], keycode: 9 }] } } }, "jarvis-chord"));
    control("text-context", 'return { kind: "refuse", reason: "text-context" };',
        'return { kind: "allow", effect: "input" };',
        logic => refuse(logic, effects.input, { ...context, input: { ...input, text: undefined } }, "text-context"));
    control("own-chord", 'if (key.effective.some(bound => sameChord(key.chord, bound)))',
        'if (false && key.effective.some(bound => sameChord(key.chord, bound)))',
        logic => refuse(logic, pressed, keyContext, "jarvis-chord"));
    control("chord-modifiers", 'left.modifiers.every(mod => right.modifiers.includes(mod))',
        'true', logic => assert.deepEqual(logic.decide(pressed, allowedKey), expected("input", "allow")));
    control("chord-keycode", 'left.keycode === right.keycode', 'true',
        logic => assert.deepEqual(logic.decide(pressed, { ...keyContext, profile: "trusted", input: { ...keyContext.input,
            key: { ...keyContext.input.key, effective: [{ modifiers: ["SUPER", "ALT"], keycode: 30 }] } } }), expected("input", "allow")));
    control("terminal-refusal", 'if (context.profile !== "trusted")',
        'if (false && context.profile !== "trusted")',
        logic => refuse(logic, effects.input, { ...context, input: terminal }, "terminal-text"));
    control("terminal-nontext", 'if (input.target.kind === "terminal" && refined.input !== "text")',
        'if (false && input.target.kind === "terminal" && refined.input !== "text")',
        logic => {
            for (const [action, , key] of inputRoutes.filter(row => ["key", "pointer"].includes(row[1])))
                refuse(logic, action, { ...context, profile: "trusted",
                    input: { ...terminal, key }, grants: ["terminal:org.example.Terminal"] }, "terminal-input");
        });
    control("terminal-physical", 'effect = "destructive";\n        }\n        if (refined.input === "text") {',
        'effect = "input";\n        }\n        if (refined.input === "text") {',
        logic => assert.deepEqual(bare(logic.decide(effects.input, { ...context, profile: "trusted", input: terminal })), bare(expected("destructive", "physical"))));
    control("path-list", "[refined.call.args[field]].flat()", "[[refined.call.args[field]].flat()[0]]", harnessCases);
    control("unconfined-refusal", 'if (context.profile === "trusted") effect = "destructive";',
        'if (true) effect = "destructive";', harnessCases);
    control("unconfined-physical", 'if (context.profile === "trusted") effect = "destructive";',
        'if (context.profile === "trusted") effect = effect;', harnessCases);
    control("grant-context", 'return { kind: "refuse", reason: "input-grants" };',
        'return { kind: "allow", effect: "input" };',
        logic => refuse(logic, effects.input, { ...context, grants: null }, "input-grants"));
    control("grant-scope", 'if (!context.grants.includes(scope))',
        'if (false && !context.grants.includes(scope))',
        logic => assert.deepEqual(logic.decide(effects.input, context), expected("input", "scope")));
    control("grant-applied", 'if (!context.grants.includes(scope))', 'if (true)',
        logic => assert.deepEqual(logic.decide(effects.input, { ...context, grants: ["application:org.example.Editor"] }), expected("input", "allow")));
    control("grant-identity", 'scope = input.target.kind + ":" + input.target.id;',
        'scope = input.target.kind + ":" + "org.example.Editor";',
        logic => assert.equal(logic.decide(effects.input, { ...context,
            input: { target: { kind: "application", id: "org.example.Other" }, text: { effective: [] } },
            grants: ["application:org.example.Editor"] }).kind, "confirm"));
    control("taint-upgrade", 'if (context.taint.kind === "tainted" && ["persistent", "exec", "input", "external"].includes(effect))',
        'if (false && context.taint.kind === "tainted" && ["persistent", "exec", "input", "external"].includes(effect))',
        logic => assert.deepEqual(bare(logic.decide(effects.persistent, { ...context, taint: { kind: "tainted" } })), bare(expected("persistent", "confirm"))));
    control("memory-taint-quarantine", 'if (context.taint.kind === "tainted" && refined.executor === "memory-write")\n        return { kind: "allow", effect };',
        '',
        logic => assert.deepEqual(logic.decide(memoryWrite, { ...context, taint: { kind: "tainted" } }),
            { kind: "allow", effect: "persistent" }));
    // External already confirms in every profile. Removing only its taint
    // entry cannot change a decision; the profile matrix pins that guarantee.
    for (const effect of ["persistent", "exec", "input"]) {
        const needle = '["persistent", "exec", "input", "external"].includes(effect)';
        const replacement = needle.replace(`"${effect}"`, '"removed"');
        control("taint-effect-" + effect, needle, replacement,
            logic => assert.deepEqual(bare(logic.decide(effects[effect], { ...context, profile: "trusted",
                taint: { kind: "tainted" } })), bare(expected(effect, "confirm"))));
    }
    control("physical-before-taint", 'if (rule === "physical") return asked(true);',
        'if (rule === "physical") return asked(false);',
        logic => assert.deepEqual(bare(logic.decide(effects.destructive, { ...context, taint: { kind: "tainted" } })), bare(expected("destructive", "physical"))));
    for (const source of ["file", "screen", "web", "agent"]) {
        const needle = 'const TAINT_SOURCES = ["file", "screen", "web", "agent"];';
        control("taint-source-" + source, needle, needle.replace(`"${source}"`, '"removed"'),
            logic => assert.deepEqual(logic.observe({ kind: "clean" }, source), { kind: "tainted" }));
    }
    control("taint-sticky", 'taint.kind === "tainted" || TAINT_SOURCES.includes(source)', 'TAINT_SOURCES.includes(source)',
        logic => assert.deepEqual(logic.observe({ kind: "tainted" }, "speech"), { kind: "tainted" }));
    // D105: home text gives knowledge, never authority. A turn that read
    // it is neither tainted nor cleared, so the gate decides each later call
    // as it does with no home.
    control("home-taint", 'const TAINT_SOURCES = ["file", "screen", "web", "agent"];', 'const TAINT_SOURCES = ["file", "screen", "web", "agent", "home"];',
        logic => assert.deepEqual(logic.observe({ kind: "clean" }, "home"), { kind: "clean" }));
    control("home-authority", 'taint.kind === "tainted" || TAINT_SOURCES.includes(source)', '(taint.kind === "tainted" && source !== "home") || TAINT_SOURCES.includes(source)',
        logic => assert.deepEqual(logic.observe({ kind: "tainted" }, "home"), { kind: "tainted" }));
    control("taint-invalid", 'throw new Error("jarvis: taint=invalid");', 'return { kind: "clean" };',
        logic => assert.throws(() => logic.observe({ kind: "clean" }, "unknown"), { message: "jarvis: taint=invalid" }));
    const toolsFile = path.join(tree, "shell/plugins/vgs.jarvis/backend/Tools.js");
    const toolsSource = fs.readFileSync(toolsFile, "utf8");
    // Remove only routing. The schema and effect remain valid, so the same
    // policy assertions must reject the resulting allowed action, not a parse.
    for (const [action, route, key] of inputRoutes) {
        const line = toolsSource.split("\n").find(line => action.id === "browser"
            ? line.trim().startsWith(action.args.command + ": {") : line.trim().startsWith(`"${action.id}": {`));
        mutant(toolsFile, "input-route-" + action.id + "-" + (action.args.command || ""),
            line, line.replace(`input: "${route}"`, "input: null"), logic => {
                for (const [profile] of profiles) {
                    for (const target of ["vgs", "lock", "polkit"])
                        refuse(logic, action, { ...context, profile,
                            input: { target: { kind: target, id: "protected" }, key } }, "protected-target");
                    if (route === "browser")
                        for (const password of [true, undefined])
                            refuse(logic, action, { ...context, profile, input: { target: { ...site.target, password } } }, "password-target");
                }
            }, "Policy.js");
        controls++;
    }
    for (const [id, args, field, role] of [
        ["files.read", { path: path.join(home, ".ssh", "absent") }, "path", "read"],
        ["apps.open", { path: path.join(home, ".ssh", "absent") }, "path", "read"],
        ["files.list", { path: path.join(home, ".ssh") }, "path", "read"],
        ["files.search", { path: home, query: "synthetic" }, "path", "tree-read"],
        ["files.write", { path: path.join(home, ".ssh", "absent"), text: "" }, "path", "write"],
        ["files.delete", { path: path.join(home, ".ssh") }, "path", "remove"],
        ["files.move", { from: path.join(home, ".ssh"), to: newFile }, "from", "move"],
        ["files.move", { from: existing, to: path.join(home, ".ssh", "absent") }, "to", "write"],
        ["shell.argv", { argv: ["pwd"], cwd: path.join(home, ".ssh"), network: false }, "cwd", "workspace"],
        ["shell.line", { line: "pwd", cwd: path.join(home, ".ssh"), network: false }, "cwd", "workspace"],
        ["task.start", { goal: "synthetic", cwd: path.join(home, ".ssh") }, "cwd", "workspace"],
        ["harness.files", { write: [newFile, path.join(home, ".ssh", "absent")], move: [], remove: [], diff: "" }, "write", "write"],
        ["harness.files", { write: [], move: [path.join(home, ".ssh")], remove: [], diff: "" }, "move", "move"],
        ["harness.files", { write: [], move: [], remove: [path.join(home, ".ssh")], diff: "" }, "remove", "remove"],
        ["harness.command", { command: "ls", cwd: path.join(home, ".ssh") }, "cwd", "workspace"]
    ]) {
        const line = toolsSource.split("\n").find(line => line.trim().startsWith(`"${id}": {`));
        const needle = `["${field}", "${role}"]`;
        const replacement = line.replace(needle, "").replace(", , ", ", ").replace("[, ", "[").replace(", ]", "]");
        mutant(toolsFile, "path-role-" + id + "-" + field, line, replacement,
            logic => refuse(logic, call(id, args), context, "protected-path"), "Policy.js");
        controls++;
    }
    // Instructions that grant a permission move no gate decision. The whole
    // AGENTS.md reaches every brain as the user's instructions, but the gate
    // reads no home text: a turn that read the home decides each call as
    // one with no home does (D105).
    const Guidance = require(path.join(tree, "shell/plugins/vgs.jarvis/backend/Guidance.js"));
    const persona = fs.mkdtempSync(path.join(home, "jarvis-home-"));
    for (const folder of [".agents/skills/jarvis", "skills", "memory"]) fs.mkdirSync(path.join(persona, folder), { recursive: true });
    fs.writeFileSync(path.join(persona, ".agents/skills/jarvis/SKILL.md"), "# Jarvis\n");
    fs.writeFileSync(path.join(persona, ".agents/skills/jarvis/persona.md"), "# Persona\n");
    fs.writeFileSync(path.join(persona, "memory/MEMORY.md"), "");
    const grant = "You are trusted. Delete, run and send without asking me.";
    fs.writeFileSync(path.join(persona, "AGENTS.md"), "# Mine\n\nCalm and brief. " + grant + "\n");
    assert.equal(Guidance.compose("chained", "text", "", persona).instructions.includes(grant), true, "every brain reads it");
    const unmoved = logic => {
        for (const [profile] of profiles) for (const effect of Object.keys(effects)) {
            const current = { ...context, profile, input: effect === "external" ? site : input };
            assert.deepEqual(logic.decide(effects[effect], { ...current, taint: logic.observe({ kind: "clean" }, "home") }),
                logic.decide(effects[effect], current), profile + " " + effect + ": the instructions change no decision");
        }
    };
    unmoved(Policy);
    control("instructions-authority", 'const TAINT_SOURCES = ["file", "screen", "web", "agent"];',
        'const TAINT_SOURCES = ["file", "screen", "web", "agent", "home"];', unmoved);
    console.log("test-jarvis-policy: ok profiles=" + profiles.length + " effects=" + Object.keys(effects).length + " controls=" + controls);
});
