#!/usr/bin/env node
// NetworkManager profile parsing, actions, publication and icon visibility.
// Every control changes production behavior and must redden this suite.
"use strict";
const fs = require("fs");
const os = require("os");
const path = require("path");
const assert = require("node:assert/strict");
const { load } = require("../bin/lib/qml-library.js");
const file = path.join(__dirname, "../shell/plugins/vgs.vpn/VpnLogic.js");
const nmcliFile = path.join(__dirname, "../shell/Commons/Nmcli.js");
const commons = { "qs.Commons 1.0": { Nmcli: load(nmcliFile), SettingValues: load(path.join(__dirname, "../shell/Commons/SettingValues.js")) } };
const core = load(path.join(__dirname, "../shell/Core/PluginLogic.js"));
const manifest = JSON.parse(fs.readFileSync(path.join(__dirname, "../shell/plugins/vgs.vpn/manifest.json"), "utf8"));
const serviceSource = fs.readFileSync(path.join(__dirname, "../shell/plugins/vgs.vpn/Service.qml"), "utf8");
// The core's ceiling for one plugin's published status
// (PluginLogic.STATUS_MAX_BYTES).
const STATUS_MAX_BYTES = core.STATUS_MAX_BYTES;
const plain = value => JSON.parse(JSON.stringify(value));

function suite(logic, service = serviceSource) {
    const profiles = plain(logic.profiles(0, "Office\\:west\\\\desk:vpn:\nHome tunnel:wireguard:activated\nWifi:wifi:activated\n"));
    assert.deepEqual(profiles, { state: "available", rows: [
        { id: "Office:west\\desk", name: "Office:west\\desk", type: "vpn", active: false, ambiguous: false },
        { id: "Home tunnel", name: "Home tunnel", type: "wireguard", active: true, ambiguous: false }
    ], count: 2, activeCount: 1 });
    for (const [code, output, state] of [[0, "", "available"], [10, "x:vpn:", "unavailable"],
        [0, "bad:vpn", "unavailable"], [0, "bad:vpn:ending\\", "unavailable"]])
        assert.equal(logic.profiles(code, output).state, state);
    for (const [request, argv, refusal] of [
        [{ kind: "profile-up", id: "Office:west\\desk" }, ["nmcli", "connection", "up", "id", "Office:west\\desk"], undefined],
        [{ kind: "profile-down", id: "Home tunnel" }, ["nmcli", "connection", "down", "id", "Home tunnel"], undefined],
        [{ kind: "profile-up", id: "Home tunnel" }, undefined, "refused: profile=state"],
        [{ kind: "profile-down", id: "gone" }, undefined, "refused: profile=absent"]
    ]) assert.deepEqual(plain(logic.profileCommand(request, profiles)), argv ? { argv } : { refusal });
    assert.equal(logic.profileCommand({ kind: "profile-up", id: "Office:west\\desk" }, { state: "available", rows: [profiles.rows[0], profiles.rows[0]] }).refusal, "refused: profile=ambiguous");
    assert.equal(logic.profileCommand({ kind: "profile-up", id: "Home tunnel" }, logic.emptyProfiles()).refusal, "refused: profile=unavailable");
    assert.equal(logic.barView(profiles).shown, true);
    assert.equal(logic.barView(profiles).icon, "shield-check");
    assert.equal(logic.barView(logic.profiles(0, "")).shown, false);
    assert.equal(logic.barView(logic.emptyProfiles()).shown, false);
    assert.equal(logic.profileCommand({ kind: "connect" }, profiles).refusal, "refused: profile=action");
    assert.equal(logic.profileCommand({ kind: "login" }, profiles).refusal, "refused: profile=action");
    // Names resolve across every type and across rows beyond the view bound.
    for (const otherType of ["wifi", "vpn", "wireguard"]) {
        for (const active of [false, true]) {
            const inventory = "Shared:wireguard:" + (active ? "activated" : "deactivated") + "\n" +
                Array.from({ length: logic.PROFILE_MAX }, (_, i) => "Other" + i + ":vpn:deactivated").join("\n") +
                "\nShared:" + otherType + ":activated";
            const listed = plain(logic.profiles(0, inventory));
            assert.equal(listed.rows[0].ambiguous, true);
            for (const kind of ["profile-up", "profile-down"])
                assert.equal(logic.profileCommand({ kind, id: "Shared" }, listed).refusal, "refused: profile=ambiguous");
        }
    }
    const hiddenActive = plain(logic.profiles(0, Array.from({ length: logic.PROFILE_MAX }, (_, i) => "Idle" + i + ":vpn:deactivated").join("\n") + "\nActive:wireguard:activated"));
    assert.equal(hiddenActive.rows.some(row => row.active), false);
    assert.equal(hiddenActive.activeCount, 1);
    assert.equal(logic.barView(hiddenActive).icon, "shield-check");
    assert.equal(logic.barView(profiles).icon, "shield-check");
    assert.equal(logic.barView(logic.profiles(0, "Idle:wireguard:deactivated")).icon, "shield-off");
    // Execute the shipped profile completion body. start-order reads its
    // log severity; process output can contain private profile data.
    const completionBody = /id: profilesReader[\s\S]*?onRunningChanged: \{([\s\S]*?)\n        \}/.exec(service);
    const codeBody = /function codeOf\(completion\) \{([\s\S]*?)\n    \}/.exec(service);
    assert.ok(completionBody);
    assert.ok(codeBody);
    const complete = new Function("running", "completion", "root", "Logic", "profilesText", "profilesDeadline", "again", "console", completionBody[1]);
    for (const [code, output, state, level, kind] of [
        [1, "/private/fixture.conf", "unavailable", "log", "failed"],
        [8, "/private/fixture.conf", "unavailable", "log", "failed"],
        [10, "PRIVATE-FIXTURE-PROFILE-ERROR", "unavailable", "warn", "failed"],
        [-1, "PRIVATE-FIXTURE-PROFILE-ERROR", "unavailable", "warn", "interrupted"],
        [0, "malformed", "unavailable", "warn", "invalid-reply"],
        [0, "", "available", null, null]
    ]) {
        const messages = [];
        const owner = { codeOf: new Function("completion", codeBody[1]) };
        let stopped = false;
        complete(false, { code, status: 0 }, owner, logic, { text: output }, { stop() { stopped = true; } }, false,
            { log(message) { messages.push(["log", message]); }, warn(message) { messages.push(["warn", message]); } });
        assert.equal(owner.profileSnapshot.state, state);
        assert.equal(stopped, true);
        assert.deepEqual(messages, level === null ? [] : [[level, "vpn: operation=profile-read completion=" + kind + " code=" + code]]);
    }
    const trimmedProfiles = logic.statusWrites({ tone: "ok", text: "" },
        Object.assign({}, hiddenActive, { rows: hiddenActive.rows.map(row => Object.assign({}, row, { id: "界".repeat(logic.TARGET_MAX), name: "界".repeat(logic.TEXT_MAX) })), action: "", problem: "" }))[1][1];
    assert.ok(trimmedProfiles.rows.length < hiddenActive.rows.length);
    assert.equal(trimmedProfiles.activeCount, 1);
    assert.equal(logic.barView(trimmedProfiles).icon, "shield-check");

    // Execute the production Import callback with private capability doubles.
    const importBody = /function importWireguard\(\) \{([\s\S]*?)\n    \}/.exec(service);
    assert.ok(importBody);
    const importRun = new Function("profiles", "shell", "root", importBody[1]);
    // A shown notice answers the press and opens the import once it installs.
    for (const [state, missing, offerAnswer, refusal, offered, launched] of [
        ["available", [], "ok", undefined, [], 1],
        ["available", ["gum"], "ok", undefined, [[["gum"], "import-wireguard"]], 0],
        ["available", ["nmcli", "gum"], "ok", undefined, [[["nmcli", "gum"], "import-wireguard"]], 0],
        ["available", ["gum"], "refused: notices=full limit=8", "refused: import=missing-tool", [[["gum"], "import-wireguard"]], 0],
        ["unavailable", [], "ok", "refused: import=unavailable", [], 0]
    ]) {
        const offers = [], launches = [];
        let refreshed = 0;
        const answer = importRun({ state }, { requirements: { missing, offer(commands, tui) { offers.push([plain(commands), tui]); return offerAnswer; } },
            tui: { run(name, args, done) { launches.push([name, args]); done(); return "ok"; } } }, { readProfiles() { refreshed++; } });
        assert.equal(answer, refusal === undefined ? "ok" : refusal);
        assert.deepEqual(offers, offered);
        assert.equal(launches.length, launched);
        assert.equal(refreshed, launched);
        if (launched) assert.deepEqual(launches[0], ["import-wireguard", []]);
    }
    const profileCrowd = Array.from({ length: 100 }, (_, i) => String(i).padStart(3, "0") + "\u0001".repeat(250) + ":vpn:").join("\n");
    const profileBound = plain(logic.profiles(0, profileCrowd));
    assert.equal(profileBound.rows.length, logic.PROFILE_MAX);
    assert.equal(profileBound.count, 100);
    assert.ok(Buffer.byteLength(JSON.stringify(Object.assign(profileBound, { action: "x".repeat(logic.TARGET_MAX), problem: "" }))) < STATUS_MAX_BYTES);

    assert.equal(logic.line("a<b>\u0007c\n"), "ab>c");
    // Publish bounded profile lists through the production service callback.
    const publishBody = /function publish\(\) \{([\s\S]*?)\n    \}\n    onConnectionChanged/.exec(service);
    assert.ok(publishBody);
    const publish = new Function("shell", "connection", "profiles", "Logic", publishBody[1]);
    const unicodeProfiles = plain(logic.profiles(0, Array.from({ length: 100 }, (_, i) => i + "界".repeat(250) + ":wireguard:activated").join("\n")));
    let values = {};
    const shell = { status: { set(key, value) {
        const result = core.statusWrite(manifest, values, key, value);
        assert.equal(result.ok, true, key + ": " + result.error);
        values = plain(result.values);
        assert.ok(Buffer.byteLength(JSON.stringify(values)) <= STATUS_MAX_BYTES);
        return "ok";
    } } };
    for (const list of [profiles, profileBound, unicodeProfiles, logic.emptyProfiles()]) {
        const original = JSON.stringify(list);
        const line = logic.connection(false, list);
        publish(shell, line, list, logic);
        assert.equal(JSON.stringify(list), original);
        assert.equal(values.profiles.count, list.count);
        assert.equal(values.profiles.activeCount, list.activeCount);
        assert.ok(values.profiles.rows.length > 0 || list.rows.length === 0);
        assert.equal(logic.barView(values.profiles).shown, list.state === "available" && list.count > 0);
        for (const row of values.profiles.rows) {
            assert.deepEqual(row, list.rows.find(input => input.id === row.id));
            assert.deepEqual(plain(logic.profileCommand({ kind: row.active ? "profile-down" : "profile-up", id: row.id }, values.profiles)).argv,
                ["nmcli", "connection", row.active ? "down" : "up", "id", row.id]);
        }
    }
}

suite(load(file, commons));
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "vpn-logic-"));
try {
    const source = fs.readFileSync(file, "utf8");
    const parserSource = fs.readFileSync(nmcliFile, "utf8");
    const parserNeedle = 'else if (c === "\\\\") escaped = true;';
    assert.equal(parserSource.split(parserNeedle).length - 1, 1);
    const parserMutant = path.join(scratch, "Nmcli.js");
    fs.writeFileSync(parserMutant, parserSource.replace(parserNeedle, 'else if (c === "\\\\") out[out.length - 1] += c;'));
    assert.throws(() => suite(load(file, { "qs.Commons 1.0": Object.assign({}, commons["qs.Commons 1.0"], { Nmcli: load(parserMutant) }) })));
    console.log("vpn-logic: control=nmcli escaping red");
    for (const [name, needle, replacement] of [
        ["all types contribute to name ambiguity", 'names[fields[0]] = (names[fields[0]] || 0) + 1;', 'if (fields[1] === "vpn" || fields[1] === "wireguard") names[fields[0]] = (names[fields[0]] || 0) + 1;'],
        ["duplicates beyond the bound remain ambiguous", 'row.ambiguous = names[row.id] > 1;', 'row.ambiguous = retained.filter(other => other.id === row.id).length > 1;'],
        ["ambiguous profile commands refuse", 'if (row.ambiguous)', 'if (false)'],
        ["active profiles survive list limits", 'const activeCount = rows.filter(row => row.active).length;', 'const activeCount = rows.slice(0, PROFILE_MAX).filter(row => row.active).length;'],
        ["VPN profiles exclude other types", 'fields[1] !== "vpn" && fields[1] !== "wireguard"', 'false'],
        ["profile argv names id", '"down", "id", row.id]', '"down", row.id]'],
        ["profile lists are bounded", 'const retained = rows.slice(0, PROFILE_MAX);', 'const retained = rows.slice(0);'],
        ["no profiles hides the icon", ' || profiles.count === 0', ''],
        ["a drawn line holds no markup start", "\\u007f<]/g", "\\u007f]/g"]
    ]) {
        assert.equal(source.split(needle).length - 1, 1, name + " mutation must match once");
        const mutant = path.join(scratch, "VpnLogic.js");
        fs.writeFileSync(mutant, source.replace(needle, replacement));
        assert.throws(() => suite(load(mutant, commons)), undefined, "control: " + name);
        console.log("vpn-logic: control=" + name + " red");
    }
    for (const [name, old, replacement] of [
        ["optional profile absence is informational", "if (code === 1 || code === 8) console.log(diagnostic);", "if (code === 1 || code === 8) console.warn(diagnostic);"],
        ["missing import tools offer setup", "if (needed.length > 0)", "if (false)"],
        ["import availability", 'if (profiles.state !== "available")', 'if (false)'],
        ["import completion refreshes", '() => root.readProfiles()', '() => {}']
    ]) {
        assert.equal(serviceSource.split(old).length - 1, 1, name);
        assert.throws(() => suite(load(file, commons), serviceSource.replace(old, replacement)));
        console.log("vpn-logic: control=" + name + " red");
    }
} finally { fs.rmSync(scratch, { recursive: true, force: true }); }
console.log("vpn-logic: passed");
