#!/usr/bin/env node
// vgs.google-drive's pure decisions, shell/plugins/vgs.google-drive/
// GoogleDriveLogic.js: the judge of the runner's status record and probe
// answer, the headline, the status values the service publishes, what the
// bar widget, its tooltip and the window draw, the notification, and when
// idle data turns old. One table holds a row per state of the sync and
// pins the headline's words and tone; every surface (the bar's tone, icon
// and count, the tooltip's title, the window's subtitle and the Settings
// `sync` value) must read that one headline. The words are pinned because
// the issue (VGS-1314) makes them the contract of the four surfaces. The
// tooltip and the Settings lines never carry a file name, and the Google
// account a connection stored reaches the connection hint alone.
// Controls edit a copy of the logic, one rule each, and require this suite
// to fail on it.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { load } = require("../bin/lib/qml-library.js");

const file = path.join(__dirname, "..", "shell", "plugins", "vgs.google-drive", "GoogleDriveLogic.js");
const Timestamp = load(path.join(__dirname, "..", "shell", "Commons", "Timestamp.js"));
const same = (got, want, message) => assert.deepEqual(JSON.parse(JSON.stringify(got)), JSON.parse(JSON.stringify(want)), message || "");

const NOW = Date.parse("2026-10-10T12:00:00Z");
const HOUR = 3600 * 1000;
const iso = ms => new Date(ms).toISOString();
const ADDRESS = "a.person@example.com";

// A record as bin/google-drive renderStatus writes it: a account pair that
// synced an hour ago, an account pair whose connection Google refused, and one
// conflict of each kind.
const DOCS = { id: "docs", label: "Documents", remote: "Docs", state: "idle", lastSuccess: iso(NOW - HOUR), staleAfter: iso(NOW + HOUR), lastError: null, changes: { added: 1, updated: 0 } };
const INBOX = { id: "inbox", label: "Agent uploads", remote: "Inbox", state: "authorization-required", lastSuccess: iso(NOW - 2 * HOUR), staleAfter: iso(NOW), lastError: { kind: "authorization-refused", at: iso(NOW - 60000), exit: 1 }, changes: null };
// A new name longer than a window row, with no space to break at.
const RENAMED_TO = "Quarterly-planning-notes-for-the-agent-uploads-review-with-every-attachment-from-the-October-meeting.txt";
const CONFLICTS = [
    { kind: "both-changed", pair: "docs", pairLabel: "Documents", path: "taxes/2025.xlsx", localPath: "/home/me/gdrive/taxes/2025.xlsx", storedPath: "/home/me/.local/state/vgshell/google-drive/pairs/docs/conflicts/20261010T110000Z-7/taxes/2025.xlsx", since: iso(NOW - HOUR) },
    { kind: "removed-on-drive", pair: "docs", pairLabel: "Documents", path: "old.txt", localPath: "/home/me/gdrive/old.txt", since: iso(NOW - HOUR) },
    { kind: "renamed", pair: "inbox", pairLabel: "Agent uploads", path: "a.txt", to: RENAMED_TO, localPath: "/home/me/outbox/a.txt", since: iso(NOW - HOUR) },
    { kind: "removed-locally", pair: "docs", pairLabel: "Documents", path: "taxes/receipts.pdf", localPath: "/home/me/gdrive/taxes/receipts.pdf", since: iso(NOW - HOUR) }
];
// The two kinds a download leg records: a file it could not copy, with no
// copy here and so no local path, then one with an older copy here, with
// rclone's reason, and a name Drive holds twice.
const DRIVE_CONFLICTS = [
    { kind: "unreadable-on-drive", pair: "docs", pairLabel: "Documents", path: "reports/Plan \u2013 first draft.pdf", reason: "failed to open source object: can't read dangling shortcut", since: iso(NOW - HOUR) },
    { kind: "unreadable-on-drive", pair: "docs", pairLabel: "Documents", path: "reports/Second gone.pdf", localPath: "/home/me/gdrive/reports/Second gone.pdf", reason: "failed to open source object: can't read dangling shortcut", since: iso(NOW - HOUR) },
    { kind: "duplicate-different", pair: "docs", pairLabel: "Documents", path: "reports/Twice listed.txt", localPath: "/home/me/gdrive/reports/Twice listed.txt", since: iso(NOW - HOUR) }
];
function record(over) {
    return Object.assign({
        state: "authorization-required",
        paused: false,
        units: "installed",
        lastSuccess: iso(NOW - HOUR),
        staleAfter: iso(NOW + HOUR),
        lastError: { kind: "authorization-refused", at: iso(NOW - 60000), pair: "inbox", exit: 1 },
        pairs: [DOCS, INBOX],
        conflicts: CONFLICTS,
        attention: { reasons: ["authorization-required", "conflicts"], key: "0123456789abcdef", notified: false },
        writtenAt: iso(NOW)
    }, over || {});
}
// A world with nothing wrong: one current account pair, no conflict.
const WELL = { state: "idle", lastError: null, pairs: [DOCS], conflicts: [], attention: null };
const well = over => record(Object.assign({}, WELL, over || {}));

// The probe answer: every key present, the account token with the
// account it connected as, every key needed.
const ACCOUNTS = ["client-id", "client-secret", "token"];
function probe(over) {
    return { credentials: ACCOUNTS.map(account => Object.assign({ account, presence: "present", needed: true }, account === "token" ? { user: ADDRESS } : {}, (over || {})[account] || {})) };
}

// The bar's tone for each headline tone, stated here apart from the logic.
const BAR = { ok: "calm", info: "calm", warning: "warning", danger: "danger" };

const SIGNED_OUT = "Google Drive is not connected. [Select Connect on the Google Drive page](page:vgs.google-drive/Setup).";
const SIGNED_OUT_PAGE = "Google Drive is not connected. Select Connect below.";
const REFUSED_PAGE = "Google Drive did not accept Connect. Select Connect again below.";
const INVALID = "The folder pair list is not valid, so VGS copies nothing.";
const signedOut = { kind: "credential-absent", account: "token" };
// The pair list the runner could not read: it reads no pair and refuses
// every pair change (bin/google-drive readPairs).
const invalid = detail => record({ state: "error", lastError: { kind: "pairs-invalid", detail: detail || "pair=docs rule=repository-inside" }, pairs: [], conflicts: [], attention: { reasons: ["error"], key: "k", notified: false } });

// The window footer's primary: [action, enabled].
const SYNC = ["sync", true];
const NO_SYNC = ["sync", false];
const SETUP = ["setup", true];
const RESUME = ["resume", true];
// A pair as the runner renders it under a pause (bin/google-drive
// renderStatus): its own state reads paused.
const PAUSED_DOCS = Object.assign({}, DOCS, { state: "paused" });

// One row per state of the sync: the record, then the headline's text,
// tone and icon every surface must show, the window footer's primary, the
// Settings hint, and whether the bar hides its icon.
const STATES = [
    ["first run", { state: "not-set-up", units: "absent", lastSuccess: null, staleAfter: null, lastError: null, pairs: [], conflicts: [], attention: null }, "Not set up", "warning", "cloud", SETUP, undefined, true],
    ["no keys", well({ state: "authorization-required", pairs: [Object.assign({}, DOCS, { state: "authorization-required", lastError: { kind: "credential-absent", account: "client-id" } })], lastError: { kind: "credential-absent", account: "client-id", pair: "docs" } }), "Connect needed", "danger", "cloud-alert", NO_SYNC, "A Google Drive key or connection is missing. Add the client ID and secret, then select Connect below."],
    ["no folder pair", { state: "not-set-up", units: "installed", lastSuccess: null, staleAfter: null, lastError: null, pairs: [], conflicts: [], attention: null }, "No folder pairs", "warning", "cloud", NO_SYNC, undefined, true],
    ["pair list not readable", invalid(), "Sync failed", "danger", "cloud-alert", NO_SYNC, INVALID, false],
    ["signed out", well({ state: "authorization-required", pairs: [Object.assign({}, DOCS, { state: "authorization-required", lastError: signedOut })], lastError: Object.assign({ pair: "docs" }, signedOut) }), "Connect needed", "danger", "cloud-alert", NO_SYNC, SIGNED_OUT_PAGE],
    ["syncing while another pair needs a connection", record({ state: "running", pairs: [Object.assign({}, DOCS, { state: "running" }), INBOX], conflicts: [] }), "Connect needed", "danger", "cloud-alert", NO_SYNC, REFUSED_PAGE],
    ["syncing while another pair failed", well({ state: "running", pairs: [Object.assign({}, DOCS, { state: "running" }), Object.assign({}, INBOX, { state: "error", lastError: { kind: "source-missing" } })], lastError: { kind: "source-missing", pair: "inbox" }, conflicts: CONFLICTS.slice(0, 1) }), "Sync failed", "danger", "cloud-alert", NO_SYNC, "A Google Drive folder of a folder pair does not exist."],
    ["empty review", well(), "Up to date", "ok", "cloud-check", SYNC, undefined],
    ["data old", well({ staleAfter: iso(NOW) }), "Out of date", "warning", "cloud-alert", SYNC, undefined],
    ["never synced", well({ lastSuccess: null, staleAfter: null }), "Not synced yet", "info", "cloud", SYNC, undefined],
    ["syncing", well({ state: "running", pairs: [Object.assign({}, DOCS, { state: "running" })] }), "Syncing", "info", "cloud-sync", NO_SYNC, undefined],
    ["paused", well({ state: "paused", paused: true, pairs: [PAUSED_DOCS] }), "Paused", "info", "cloud-off", RESUME, undefined],
    ["every pair paused on its own", well({ state: "paused", pairs: [PAUSED_DOCS] }), "Paused", "info", "cloud-off", NO_SYNC, undefined],
    ["error", well({ state: "error", lastError: { kind: "source-missing", pair: "docs" } }), "Sync failed", "danger", "cloud-alert", SYNC, "A Google Drive folder of a folder pair does not exist."],
    ["offline", well({ state: "offline", lastError: { kind: "offline", pair: "docs" } }), "Offline", "warning", "cloud-off", SYNC, "Google Drive cannot be reached. VGS tries again at the next sync."],
    ["keyring locked", well({ state: "authorization-required", pairs: [Object.assign({}, DOCS, { state: "authorization-required", lastError: { kind: "credential-locked", account: "client-id" } })], lastError: { kind: "credential-locked", account: "client-id", pair: "docs" } }), "Connect needed", "danger", "cloud-alert", SYNC, "Your keyring is locked. Unlock it to sync."],
    ["connection needed", record({ conflicts: [] }), "Connect needed", "danger", "cloud-alert", SYNC, REFUSED_PAGE],
    ["set up with files to review", well({ conflicts: CONFLICTS.slice(0, 2) }), "2 files to review", "warning", "cloud-alert", SYNC, "Open the Google Drive window to review them."],
    ["one file to review", well({ conflicts: CONFLICTS.slice(1, 2) }), "1 file to review", "warning", "cloud-alert", SYNC, "Open the Google Drive window to review them."],
    ["files to review while paused", well({ state: "paused", paused: true, pairs: [PAUSED_DOCS], conflicts: CONFLICTS.slice(0, 2) }), "2 files to review", "warning", "cloud-alert", RESUME, "Open the Google Drive window to review them."],
    ["connection needed with files to review", record(), "Connect needed", "danger", "cloud-alert", SYNC, REFUSED_PAGE]
];

function verify(L) {
    // The record judge: the runner's record passes; each malformed field
    // is named.
    const good = L.parseStatus(JSON.stringify(record()));
    assert.equal(good.ok, true, JSON.stringify(good));
    const bad = [
        ["not JSON", "{", "status=not-json"],
        ["an unknown state", JSON.stringify(record({ state: "busy" })), "status=state"],
        ["paused as text", JSON.stringify(record({ paused: "no" })), "status=paused"],
        ["unknown units", JSON.stringify(record({ units: "maybe" })), "status=units"],
        ["a time that is no time", JSON.stringify(record({ lastSuccess: "yesterday" })), "status=time"],
        ["a pair of no direction", JSON.stringify(record({ pairs: [Object.assign({}, DOCS, { direction: "both" })] })), "status=pairs"],
        ["a conflict with a relative path", JSON.stringify(record({ conflicts: [Object.assign({}, CONFLICTS[1], { localPath: "gdrive/old.txt" })] })), "status=conflicts"],
        ["a Drive deletion with no local path", JSON.stringify(record({ conflicts: [Object.assign({}, CONFLICTS[1], { localPath: undefined })] })), "status=conflicts"],
        ["a file not copied with no reason", JSON.stringify(record({ conflicts: [Object.assign({}, DRIVE_CONFLICTS[0], { reason: undefined })] })), "status=conflicts"],
        ["a local edit with no kept copy", JSON.stringify(record({ conflicts: [Object.assign({}, CONFLICTS[0], { storedPath: "relative" })] })), "status=conflicts"],
        ["attention with no key", JSON.stringify(record({ attention: { reasons: [], notified: false } })), "status=attention"],
        ["attention with no notified", JSON.stringify(record({ attention: { reasons: [], key: "k" } })), "status=attention"]
    ];
    for (const [label, text, error] of bad) same(L.parseStatus(text), { ok: false, error }, label);

    // The probe judge: a token's row may carry the account it connected
    // as; no other row may, and a value that is no address is refused.
    const judged = L.parseProbe(JSON.stringify(probe({ "token": { presence: "locked" } })));
    assert.equal(judged.ok, true, JSON.stringify(judged));
    same(judged.presence["token"], { presence: "locked", needed: true, user: ADDRESS });
    same(L.parseProbe(JSON.stringify({ credentials: probe().credentials.slice(1) })), { ok: false, error: "probe=missing account=client-id" });
    same(L.parseProbe(JSON.stringify({ credentials: [{ account: "token", presence: "maybe", needed: true }] })), { ok: false, error: "probe=credential" });
    const users = [
        ["a user on a client row", { "client-id": { user: ADDRESS } }, "probe=user account=client-id"],
        ["two @", { "token": { user: "a@b@example.com" } }, "probe=user account=token"],
        ["no @", { "token": { user: "a.person.example.com" } }, "probe=user account=token"],
        ["a line break", { "token": { user: "a.person@example.com\nx" } }, "probe=user account=token"],
        ["empty", { "token": { user: "" } }, "probe=user account=token"],
        ["too long", { "token": { user: "a".repeat(243) + "@example.com" } }, "probe=user account=token"],
        ["not text", { "token": { user: 7 } }, "probe=user account=token"]
    ];
    for (const [label, over, error] of users) same(L.parseProbe(JSON.stringify(probe(over))), { ok: false, error }, label);
    assert.equal(L.parseProbe(JSON.stringify(probe({ "token": { user: "a".repeat(242) + "@example.com" } }))).ok, true, "254 characters fit");

    // A pair's state: idle reads by the data's age.
    const pairStates = [
        ["idle, current", "idle", NOW + 1, "Up to date", "ok"],
        ["idle, old", "idle", NOW, "Out of date", "warning"],
        ["idle, never synced", "idle", null, "Not synced yet", "info"],
        ["running", "running", null, "Syncing", "info"],
        ["paused", "paused", null, "Paused", "info"],
        ["offline", "offline", null, "Offline", "warning"],
        ["connection", "authorization-required", null, "Connect needed", "danger"],
        ["failed", "error", null, "Sync failed", "danger"]
    ];
    for (const [label, state, staleAfter, text, tone] of pairStates) {
        const v = L.stateView(state, staleAfter, NOW);
        same([v.text, v.tone], [text, tone], label);
    }
    assert.throws(() => L.stateView("busy", null, NOW), /state "busy"/);

    // The headline, and every surface reading it.
    assert.equal(L.headline(undefined, NOW), null, "no record, no headline");
    for (const [label, rec, text, tone, icon, primary, hint, hidden] of STATES) {
        const cloud = L.cloudValue(rec, "");
        const head = L.headline(cloud, NOW);
        same([head.text, head.tone, head.icon], [text, tone, icon], label + ": headline");
        const sync = L.statusValues(rec, null, "", "", NOW).sync;
        same([sync.text, sync.tone, sync.hint], [text, tone, hint], label + ": the Settings sync value");
        const window = L.windowStatus(cloud, NOW, Timestamp.text);
        same([window.text, window.tone], [text, tone], label + ": the window subtitle");
        const foot = L.footerView(cloud).primary;
        same([foot.action, foot.enabled], primary, label + ": the window footer's primary");
        const tip = L.widgetTooltip(cloud, NOW, Timestamp.text);
        assert.equal(tip.title, "Google Drive: " + text, label + ": the tooltip title");
        const bar = L.widgetView(cloud, NOW);
        if (hidden === true) {
            assert.equal(bar.hidden, true, label + ": no folder pair hides the icon");
            continue;
        }
        same([bar.hidden, bar.tone, bar.icon, bar.badge], [false, BAR[tone], icon, cloud.conflictCount > 0 ? String(cloud.conflictCount) : ""], label + ": the bar");
        assert.equal(bar.spinning, rec.state === "running", label + ": the spinner");
    }

    // The published values of the record and the probe.
    const presence = L.parseProbe(JSON.stringify(probe())).presence;
    const values = L.statusValues(good.record, presence, "", "", NOW);
    same(Object.keys(values).sort(), ["account", "cloud", "connection", "firstPair", "keys", "lastSync", "pairs", "schedule", "sync"]);
    same(values.sync.lines, ["Documents: 3 files to review", "Agent uploads: Connect needed"], "a line per pair, each by its own state and files");
    assert.equal(values.lastSync, NOW - HOUR);
    same(Object.keys(L.statusValues(null, null, "", "", NOW)), [], "nothing is published before the first answers");
    same(Object.keys(L.statusValues(null, presence, "", "", NOW)).sort(), ["account", "connection", "keys"]);

    for (const [label, record, expected] of [
        ["first pair missing", well({ state: "not-set-up", pairs: [] }), ["warning", true]],
        ["first pair exists", good.record, ["ok", false]]
    ]) {
        const first = L.statusValues(record, null, "", "", NOW).firstPair;
        same([first.tone, first.action], expected, label);
    }
    const disconnected = L.parseProbe(JSON.stringify(probe({ token: { presence: "absent" } }))).presence;
    const disconnectedValues = L.statusValues(good.record, disconnected, "", "", NOW);
    same([disconnectedValues.connection.action, disconnectedValues.account.action], [true, undefined], "only the connection step offers Connect");

    // schedule: the hourly units.
    const hourly = "VGS syncs Google Drive every hour while you are logged in.";
    same(L.scheduleValue("installed"), { tone: "ok", text: "On", hint: hourly });
    same(L.scheduleValue("absent"), { tone: "warning", text: "Not set up", action: true, hint: hourly });
    same(L.scheduleValue("stale"), { tone: "warning", text: "Needs setup", action: true, hint: hourly });
    same(values.schedule, L.scheduleValue("installed"));

    // pairs: each pair's Drive folder, Add while none, Remove once one exists.
    const pairsOf = rec => L.pairsValue(L.cloudValue(rec, ""));
    const genericPairListProblem = L.errorText({ kind: "pairs-invalid" });
    same(pairsOf(well({ state: "not-set-up", pairs: [] })), { tone: "warning", text: "None", action: "add", hint: "Add a folder pair to choose what VGS keeps in step with Google Drive." });
    same(values.pairs, { tone: "ok", text: "2 folder pairs", lines: ["Documents: Docs", "Agent uploads: Inbox"], action: "remove" });
    same(pairsOf(well()).text, "1 folder pair");
    // A pair's second line, the same in the window row and the Settings
    // line: its Drive folder, or Both ways where that folder carries its name.
    const pairDrives = [
        ["a Drive folder named as the pair", "Documents", "Both ways"],
        ["a differing Drive folder", "Docs", "Docs"],
        ["a nested Drive folder", "Work/Documents", "Work/Documents"]
    ];
    for (const [label, remote, line] of pairDrives) {
        const rec = well({ pairs: [Object.assign({}, DOCS, { remote })] });
        assert.equal(L.pairRow(L.cloudValue(rec, "").pairs[0], NOW).secondary, line, label + ": the window row");
        same(pairsOf(rec).lines, ["Documents: " + line], label + ": the Settings line");
    }
    const invalidPairs = pairsOf(invalid());
    assert.equal(invalidPairs.tone, "danger", "an unreadable list is danger");
    assert.equal(invalidPairs.text, "Not readable", "an unreadable list states that it is not readable");
    assert.equal(invalidPairs.action, "reset", "an unreadable list offers the repair the runner accepts");
    assert.ok(invalidPairs.hint.length <= L.HINT_MAX, "an unreadable list hint stays under its ceiling");
    assert.ok(invalidPairs.hint.includes("docs"), "a pair detail names its pair id");
    assert.ok(invalidPairs.hint !== genericPairListProblem, "a known detail is not the generic sentence");
    assert.ok(!invalidPairs.hint.includes("rule=") && !invalidPairs.hint.includes("pairs-file=") && !invalidPairs.hint.includes("pair="), "keyed detail is hidden");
    assert.equal(L.pairListValid(L.cloudValue(invalid(), "")), false);
    assert.equal(L.pairListValid(L.cloudValue(well(), "")), true);
    const pairProblems = [
        ["not JSON", "pairs-file=not-json", "file is damaged"],
        ["unreadable", "pairs-file=unreadable-EACCES", "read"],
        ["wrong shape", "pairs-file=shape", "list"],
        ["pair rule", "pair=docs rule=local-overlap", "docs"],
        ["unknown pair", "pair=? rule=shape", "entry"]
    ];
    const seenPairProblemText = new Set();
    for (const [label, detail, word] of pairProblems) {
        const value = pairsOf(invalid(detail));
        assert.equal(value.tone, "danger", label + ": tone");
        assert.equal(value.text, "Not readable", label + ": text");
        assert.equal(value.action, "reset", label + ": action");
        assert.ok(value.hint.length <= L.HINT_MAX, label + ": hint ceiling");
        assert.ok(value.hint.includes(word), label + ": sentence category");
        assert.ok(value.hint !== genericPairListProblem, label + ": known detail is not generic");
        assert.ok(!value.hint.includes("rule=") && !value.hint.includes("pairs-file=") && !value.hint.includes("pair="), label + ": keyed detail hidden");
        seenPairProblemText.add(value.hint.split(". ")[0]);
    }
    assert.equal(seenPairProblemText.size, pairProblems.length, "each pair-list problem class has its own sentence");
    const unknownPairProblem = pairsOf(invalid("not-a-runner-detail"));
    assert.equal(unknownPairProblem.action, "reset", "an unknown detail still offers reset");
    assert.ok(unknownPairProblem.hint.includes(genericPairListProblem), "an unknown detail falls back to the generic sentence");
    assert.ok(unknownPairProblem.hint.length <= L.HINT_MAX, "the unknown detail hint stays under its ceiling");

    // keys: the client ID and secret.
    same(values.keys, [{ label: "Client ID", value: "present", secret: "client-id" }, { label: "Client secret", value: "present", secret: "client-secret" }]);

    // account: the connection.
    const withUser = (user, extra) => L.parseProbe(JSON.stringify(probe(Object.assign({ "token": user === undefined ? {} : { user } }, extra || {})))).presence;
    const signIn = [
        ["keyring locked", withUser(undefined, { "token": { presence: "locked" } }), null, { tone: "warning", text: "Keyring locked", hint: "Unlock your keyring to sync." }],
        ["keyring unreadable", withUser(undefined, { "client-id": { presence: "unavailable" } }), null, { tone: "warning", text: "Unknown", hint: "VGS cannot read your keyring." }],
        ["no client", withUser(undefined, { "client-secret": { presence: "absent" }, "token": { presence: "absent" } }), null, { tone: "info", text: "Not connected", hint: "Add the client ID and secret first." }],
        ["no connection", withUser(undefined, { "token": { presence: "absent" } }), null, { tone: "warning", text: "Not connected", action: "signIn" }],
        ["refused", withUser(ADDRESS), good.record, { tone: "danger", text: "Connect refused", action: "reconnect", hint: "Google Drive did not accept Connect." }],
        ["connected with the account", withUser(ADDRESS), null, { tone: "ok", text: "Connected", hint: "Connected as " + ADDRESS + ".", action: "signOut" }],
        ["connected, account too long for a hint", withUser("a".repeat(200) + "@example.com"), null, { tone: "ok", text: "Connected", hint: "Connected.", action: "signOut" }]
    ];
    for (const [label, p, rec, want] of signIn) same(L.signInValue(p, rec), want, "account: " + label);
    same(values.account, { tone: "danger", text: "Connect refused", action: "reconnect", hint: "Google Drive did not accept Connect." });
    // The account reaches the connection hint alone.
    for (const key of Object.keys(values).filter(k => k !== "account"))
        assert.ok(!JSON.stringify(values[key]).includes(ADDRESS), "the account shows in " + key);

    // The window's data: times as milliseconds, each conflict with the
    // folders Open folders opens, the list capped under the ceiling.
    const cloud = values.cloud;
    same(cloud.conflicts.map(c => c.dirs), [
        ["/home/me/gdrive/taxes", "/home/me/.local/state/vgshell/google-drive/pairs/docs/conflicts/20261010T110000Z-7/taxes"],
        ["/home/me/gdrive"],
        ["/home/me/outbox"],
        ["/home/me/gdrive/taxes"]
    ]);
    assert.equal(cloud.conflicts[2].to, RENAMED_TO);
    const many = record({ conflicts: Array.from({ length: 500 }, (_, i) => Object.assign({}, CONFLICTS[1], { path: "f" + i + ".txt", localPath: "/home/me/gdrive/" + "x".repeat(3000) + "/f" + i + ".txt" })) });
    const capped = L.cloudValue(many, "");
    assert.equal(capped.conflictCount, 500);
    assert.ok(capped.conflicts.length > 0 && capped.conflicts.length <= L.CONFLICTS_MAX);
    assert.ok(JSON.stringify(capped).length <= L.CLOUD_BYTES_MAX, "the data stays under its ceiling");
    assert.equal(L.moreConflicts(capped), (500 - capped.conflicts.length) + " more files to review");

    // Writes: a key the next values lack is cleared with null.
    same(L.changedKeys({ sync: 1, lastSync: 5 }, { sync: 1 }), ["lastSync"]);
    same(L.changedKeys({ lastSync: null }, { lastSync: null }), []);

    // The tooltip: pairs and states, never a file name; the count of files
    // to review when the headline does not say it.
    const tip = L.widgetTooltip(cloud, NOW, Timestamp.text);
    same(tip.details.split("\n"), ["Documents: 3 files to review", "Agent uploads: Connect needed", "4 files to review", "Last sync " + Timestamp.text(NOW - HOUR, NOW)]);
    same(L.widgetTooltip(L.cloudValue(well({ conflicts: CONFLICTS.slice(0, 2) }), ""), NOW, Timestamp.text).details.split("\n"), ["Documents: 2 files to review", "Last sync " + Timestamp.text(NOW - HOUR, NOW)], "the headline says the whole count once");
    same(L.widgetTooltip(undefined, NOW, Timestamp.text), { title: "Google Drive", details: "" });
    for (const text of [tip.title, tip.details].concat(values.sync.lines))
        for (const c of CONFLICTS) assert.ok(!text.includes(c.path) && !text.includes(c.localPath), "a file name shows: " + text);

    // The window: the subtitle's lines, each pair's direction in the long
    // form, the review list under each pair's label.
    const subtitle = w => w.lines.map(l => [l.text, l.tone]);
    same(subtitle(L.windowStatus(cloud, NOW, Timestamp.text)), [
        ["Last complete sync " + Timestamp.text(NOW - HOUR, NOW), ""],
        ["First file to review: taxes/2025.xlsx", ""],
        ["Google Drive did not accept Connect. [Select Connect again on the Google Drive page](page:vgs.google-drive/Setup).", "danger"]
    ]);
    same(subtitle(L.windowStatus(L.cloudValue(well({ state: "paused", paused: true, lastSuccess: null, staleAfter: null }), "VGS could not pause the Google Drive sync."), NOW, Timestamp.text)), [
        ["No complete sync yet", ""], ["The hourly sync copies nothing until you resume it.", ""], ["VGS could not pause the Google Drive sync.", "danger"]
    ], "a paused headline");
    same(subtitle(L.windowStatus(L.cloudValue(well({ state: "paused", paused: true, conflicts: CONFLICTS.slice(0, 1) }), ""), NOW, Timestamp.text)), [
        ["Last complete sync " + Timestamp.text(NOW - HOUR, NOW), ""], ["First file to review: taxes/2025.xlsx", ""], ["Paused. The hourly sync copies nothing until you resume it.", ""]
    ], "files to review while paused say the pause");
    same(L.windowStatus(L.cloudValue(well({ state: "offline", lastError: { kind: "offline" } }), ""), NOW, Timestamp.text).lines[1], { text: "Google Drive cannot be reached. VGS tries again at the next sync.", tone: "" });
    // A pair's badge: its own files to review, a state that needs the
    // user or stops the sync before them, and Up to date only with none.
    same(L.pairRow(cloud.pairs[0], NOW), { id: "docs", label: "Documents", secondary: "Docs", icon: "folder-sync", text: "3 files to review", tone: "warning" });
    same(L.cloudValue(good.record, "").pairs.map(p => p.review), [3, 1]);
    const badge = rec => { const p = L.pairRow(L.cloudValue(rec, "").pairs[0], NOW); return [p.text, p.tone]; };
    same(badge(well()), ["Up to date", "success"]);
    same(badge(well({ conflicts: DRIVE_CONFLICTS.slice(0, 1) })), ["1 file to review", "warning"]);
    same(badge(well({ conflicts: CONFLICTS.slice(2, 3) })), ["Up to date", "success"], "another pair's file");
    same(badge(well({ state: "paused", paused: true, pairs: [PAUSED_DOCS], conflicts: CONFLICTS.slice(0, 1) })), ["Paused", "info"]);
    same(L.pairRow(cloud.pairs[1], NOW), { id: "inbox", label: "Agent uploads", secondary: "Inbox", icon: "folder-sync", text: "Connect needed", tone: "danger" });
    // The footer: one primary, Resume while paused; Pause or Resume and
    // Add a folder pair only while a folder pair exists, since the empty
    // pair list offers Add.
    const footer = rec => L.footerView(rec === undefined ? undefined : L.cloudValue(rec, ""));
    const footers = [
        ["before the first value", undefined, { primary: { text: "Sync now", icon: "refresh-cw", action: "sync", enabled: false }, pause: null, add: false }],
        ["first run", well({ state: "not-set-up", units: "absent", pairs: [] }), { primary: { text: "Set up hourly sync", icon: "cloud-cog", action: "setup", enabled: true }, pause: null, add: false }],
        ["no folder pair", well({ state: "not-set-up", pairs: [] }), { primary: { text: "Sync now", icon: "refresh-cw", action: "sync", enabled: false }, pause: null, add: false }],
        ["units stale with a pair", well({ units: "stale" }), { primary: { text: "Set up hourly sync", icon: "cloud-cog", action: "setup", enabled: true }, pause: { text: "Pause", icon: "pause", action: "pause" }, add: true }],
        ["set up", well(), { primary: { text: "Sync now", icon: "refresh-cw", action: "sync", enabled: true }, pause: { text: "Pause", icon: "pause", action: "pause" }, add: true }],
        ["paused", well({ state: "paused", paused: true, pairs: [PAUSED_DOCS] }), { primary: { text: "Resume", icon: "play", action: "resume", enabled: true }, pause: null, add: true }],
        ["units stale while paused", well({ units: "stale", state: "paused", paused: true, pairs: [PAUSED_DOCS] }), { primary: { text: "Set up hourly sync", icon: "cloud-cog", action: "setup", enabled: true }, pause: { text: "Resume", icon: "play", action: "resume" }, add: true }]
    ];
    for (const [label, rec, want] of footers) same(footer(rec), want, "footer: " + label);
    // Each review row whole, one of each kind: its full text, uncut, the
    // folder line of the copy its text speaks of, and the folders Open
    // folders opens.
    const KEPT = "/home/me/.local/state/vgshell/google-drive/pairs/docs/conflicts/20261010T110000Z-7/taxes";
    same(L.conflictGroups(cloud.conflicts), [
        { label: "Documents", rows: [
            { label: "taxes/2025.xlsx", detail: "Changed here and on Google Drive. The older copy is kept for 30 days.", folder: "The older copy is in this folder: " + KEPT, dirs: ["/home/me/gdrive/taxes", KEPT] },
            { label: "old.txt", detail: "Removed from Google Drive. The copy here stays.", folder: "The copy here is in this folder: /home/me/gdrive", dirs: ["/home/me/gdrive"] },
            { label: "taxes/receipts.pdf", detail: "Removed here. VGS copied it back from Google Drive.", folder: "", dirs: ["/home/me/gdrive/taxes"] }
        ] },
        { label: "Agent uploads", rows: [
            { label: "a.txt", detail: "Renamed on Google Drive. The old name was copied back to Google Drive. New name: " + RENAMED_TO + ".", folder: "", dirs: ["/home/me/outbox"] }
        ] }
    ]);
    // A file not copied reads with rclone's reason and has no
    // folder to open; a doubled name opens the folder of the copy here.
    const driveSide = L.parseStatus(JSON.stringify(well({ conflicts: DRIVE_CONFLICTS })));
    assert.equal(driveSide.ok, true, driveSide.error);
    const driveCloud = L.cloudValue(driveSide.record, "");
    same(L.conflictGroups(driveCloud.conflicts), [
        { label: "Documents", rows: [
            { label: DRIVE_CONFLICTS[0].path, detail: "VGS could not copy this file from Google Drive. It is a Google Drive shortcut to a file that no longer exists.", folder: "", dirs: [] },
            { label: DRIVE_CONFLICTS[1].path, detail: "VGS could not copy this file from Google Drive. It is a Google Drive shortcut to a file that no longer exists.", folder: "The older copy here is in this folder: /home/me/gdrive/reports", dirs: ["/home/me/gdrive/reports"] },
            { label: DRIVE_CONFLICTS[2].path, detail: "Google Drive holds two files with this name. VGS copied one of them.", folder: "", dirs: ["/home/me/gdrive/reports"] }
        ] }
    ]);
    same(L.headline(driveCloud, NOW).text, "3 files to review");
    // A reason the table does not know reads in the default words, and no
    // published value holds rclone's text.
    const unknown = L.cloudValue(well({ conflicts: [Object.assign({}, DRIVE_CONFLICTS[0], { reason: "failed to open source object: stand-in cause" })] }), "");
    same(L.conflictRow(unknown.conflicts[0]).detail, "VGS could not copy this file from Google Drive. Google Drive did not let VGS read it.");
    for (const value of [driveCloud, unknown]) assert.ok(!JSON.stringify(value).includes("failed to open source object"), "rclone's text is published");
    same(subtitle(L.windowStatus(driveCloud, NOW, Timestamp.text))[1], ["First file to review: " + DRIVE_CONFLICTS[0].path, ""]);
    // A change on both sides with no kept copy names no folder.
    same(L.conflictRow(L.cloudValue(well({ conflicts: [Object.assign({}, CONFLICTS[0], { storedPath: undefined })] }), "").conflicts[0]).folder, "");

    // The notification: one per reason in order of need.
    same(L.notification(good.record), { title: "Google Drive needs Connect", message: "Google Drive did not accept Connect. [Select Connect again on the Google Drive page](page:vgs.google-drive/Setup).", tone: "danger" });
    same(L.notification(record({ attention: { reasons: ["conflicts"], key: "k", notified: false } })), { title: "Google Drive sync kept files for review", message: "4 files to review. Open the Google Drive window to see them.", tone: "warning" });
    same(L.notification(record({ lastError: { kind: "offline" }, attention: { reasons: ["error"], key: "k", notified: false } })).tone, "danger");
    same(L.notification(record({ attention: { reasons: ["units-stale"], key: "k", notified: false } })), { title: "Google Drive needs setup", message: "[Select Set up hourly sync in Google Drive Details](page:vgs.google-drive/Details).", tone: "warning" });
    assert.equal(L.notification(record({ attention: null })), null);
    same(L.notification(record({ lastError: Object.assign({ pair: "docs" }, signedOut) })).message, SIGNED_OUT, "a missing token is a connection");
    assert.equal(L.errorText({ kind: "credential-absent", account: "token" }), "Google Drive is not connected. [Select Connect on the Google Drive page](page:vgs.google-drive/Setup).");
    assert.equal(L.errorText({ kind: "credential-absent", account: "client-id" }), "A Google Drive key or connection is missing. Add the client ID and secret, then [select Connect on the Google Drive page](page:vgs.google-drive/Setup).");
    // The Settings page names its own fields instead of sending the user to itself.
    assert.equal(L.errorText({ kind: "credential-absent", account: "token" }, true), "Google Drive is not connected. Select Connect below.");
    assert.equal(L.errorText({ kind: "credential-absent", account: "client-id" }, true), "A Google Drive key or connection is missing. Add the client ID and secret, then select Connect below.");
    assert.equal(L.errorText({ kind: "authorization-refused" }, true), REFUSED_PAGE);
    for (const error of [signedOut, { kind: "credential-absent", account: "client-id" }, { kind: "authorization-refused" }])
        assert.ok(!L.errorText(error, true).includes("page:"), "the on-page text holds no page reference");
    assert.equal(L.errorText({ kind: "offline" }, true), L.errorText({ kind: "offline" }), "a sentence that names no place reads the same on the page");

    // A failed request reads as a sentence.
    assert.equal(L.problemText("start", "start exit=1 google-drive: refused: units=absent"), "Set up hourly sync first.");
    assert.equal(L.problemText("pause", "pause exit=1 google-drive: refused: state-lock=timeout"), "VGS could not pause the Google Drive sync.");
    assert.equal(L.problemText("", ""), "");

    // A held answer reads by its reason, in the line RunnerClient hands the
    // service: the operation, the exit and the runner's refusal
    // (bin/google-drive holdRename). The Settings sync value says why it
    // waits with or without a record, and holds no failure.
    const heldLines = [
        ["running previous sync", "status exit=75 google-drive: refused: migration=held reason=old-service-activating", "old-sync", "info"],
        ["sync started during the disable", "probe exit=75 google-drive: refused: migration=held reason=old-service-active restore=systemctl=failed args=enable,--now,vgs-cloud-sync.timer exit=1", "old-sync", "info"],
        ["unknown is-active word", "status exit=75 google-drive: refused: migration=held reason=old-service-unknown", "old-sync-unknown", "warning"],
        ["systemctl missing", "status exit=75 google-drive: refused: migration=held systemctl=missing", "systemd-missing", "warning"],
        ["failed disable", "start exit=75 google-drive: refused: migration=held systemctl=failed args=disable,--now,vgs-cloud-sync.timer exit=1", "old-timer", "warning"],
        ["unnamed hold", "status exit=75 google-drive: refused: migration=held", "other", "warning"]
    ];
    for (const [label, line, reason, tone] of heldLines) {
        assert.equal(L.heldReason(line), reason, label);
        for (const rec of [null, good.record]) {
            const sync = L.statusValues(rec, null, "", reason, NOW).sync;
            same([sync.tone, typeof sync.hint, sync.action], [tone, "string", undefined], label + (rec === null ? ": no record" : ": with a record"));
        }
    }
    assert.throws(() => L.statusValues(null, null, "", "busy", NOW), /held reason "busy"/);

    // The next moment idle data turns old.
    assert.equal(L.nextStale(record(), NOW), NOW + HOUR);
    assert.equal(L.nextStale(record({ staleAfter: null, pairs: [] }), NOW), null);
}

verify(load(file));

const controls = [
    ["first pair cannot finish empty", 'pairListValid(cloud) && cloud.pairs.length > 0', 'pairListValid(cloud)'],
    ["connection offers Connect when missing", 'values.account.action === "signIn" || values.account.action === "reconnect"', 'false'],
    ["account maintenance cannot offer Connect", 'if (values.account.action === "signIn") delete values.account.action;', 'if (false) delete values.account.action;'],

    ["the missing-key text links to Setup", "then [select Connect on the Google Drive page](page:vgs.google-drive/Setup).", "then select Connect on the Google Drive page."],
    ["the judge refuses an unknown state", "if (STATES.indexOf(doc.state) === -1) return", "if (false) return"],
    ["the judge needs attention.notified", "\n        && typeof doc.attention.notified === \"boolean\")", ")"],
    ["a both-changed stored path is absolute", "&& (c.kind !== \"both-changed\" || !hasOwn(c, \"storedPath\") || (isText(c.storedPath) && c.storedPath.charAt(0) === \"/\"))", ""],
    ["an address holds one @", " && value.split(\"@\").length === 2", ""],
    ["only a token's row carries a user", '(c.account !== "token" || !isAddress(c.user))', "!isAddress(c.user)"],
    ["idle data reads by its age", "return now < staleAfter ? CURRENT : OUT_OF_DATE;", "return CURRENT;"],
    ["units absent read not set up, not no folder pair", "return cloud.units === \"absent\" ?", "return false ?"],
    ["a connection needed or a failure wins over files to review", "if (danger.length > 0) return", "if (false) return"],
    ["another pair's failure wins over a running sync", "return cloud.state === state || cloud.pairs.some(function (p) { return p.state === state; });", "return cloud.state === state;"],
    ["a missing token reads as a connection", "if (error.kind === \"credential-absent\" && error.account === \"token\")", "if (false)"],
    ["the published error keeps its account", "return isText(error.account) ? { kind: error.kind, account: error.account } : { kind: error.kind };", "return { kind: error.kind };"],
    ["the published pair-list error keeps its detail", "if (error.kind === \"pairs-invalid\" && isText(error.detail)) return { kind: error.kind, detail: error.detail };\n    ", ""],
    ["an unreadable pair list offers Reset", "hint: pairListResetHint(cloud.lastError), action: \"reset\"", "hint: pairListResetHint(cloud.lastError)"],
    ["an unreadable pair list takes its repair path", "if (!pairListValid(cloud)) return { tone: \"danger\"", "if (false) return { tone: \"danger\""],
    ["an unreadable pair list keeps the bar", "(cloud.pairs.length === 0 && pairListValid(cloud))", "cloud.pairs.length === 0"],
    ["files to review win over the state", "if (cloud.conflictCount > 0) return {", "if (false) return {"],
    ["the bar reads the headline", "var head = headline(cloud, now);\n    return { hidden: false", "var head = stateView(cloud.state, cloud.staleAfter, now);\n    return { hidden: false"],
    ["the tooltip reads the headline", "var head = headline(cloud, now);\n    var lines = pairLines(cloud.pairs, now);", "var head = stateView(cloud.state, cloud.staleAfter, now);\n    var lines = pairLines(cloud.pairs, now);"],
    ["the window reads the headline", "var head = headline(cloud, now);\n    var lines = [{", "var head = stateView(cloud.state, cloud.staleAfter, now);\n    var lines = [{"],
    ["the Settings sync value reads the headline", "var head = headline(cloud, now);\n    var value = {", "var head = stateView(cloud.state, cloud.staleAfter, now);\n    var value = {"],
    ["Set up hourly sync while the units are absent", "text: \"Not set up\", action: true,", "text: \"Not set up\","],
    ["Sign in again for a refused connection", "if (refused) return", "if (false) return"],
    ["the account reaches the connection hint", "var named = user === undefined ? \"\" : \"Connected as \" + user + \".\";", "var named = \"\";"],
    ["a hint over its ceiling falls back", "named !== \"\" && named.length <= HINT_MAX ? named", "named !== \"\" ? named"],
    ["a locked keyring comes first", "if (states.indexOf(\"locked\") !== -1) return", "if (false) return"],
    ["the review list stays under its ceiling", "while (value.conflicts.length > 0 && JSON.stringify(value).length > CLOUD_BYTES_MAX) value.conflicts.pop();", ""],
    ["a cleared key is written as null", "if (!hasOwn(next, k) && previous[k] !== null) keys.push(k);", ""],
    ["the tooltip names pairs, not files", "var lines = pairLines(cloud.pairs, now);\n    if (cloud.conflictCount > 0 && head.cause", "var lines = pairLines(cloud.pairs, now).concat(cloud.conflicts.map(function (c) { return c.path; }));\n    if (cloud.conflictCount > 0 && head.cause"],
    ["Sync now waits for a key or a connection", "return pair.state !== \"authorization-required\" ||", "return true ||"],
    ["Sync now retries a locked keyring", " || (pair.lastError !== null && pair.lastError.kind === \"credential-locked\");", ";"],
    ["Sync now waits for a running sync", "known && cloud.state !== \"running\" && cloud.pairs.some(pairCanSync)", "known && cloud.pairs.some(pairCanSync)"],
    ["Sync now waits for a paused pair", "if (pair.state === \"paused\") return false;", ""],
    ["the footer offers Add only beside a folder pair", "add: hasPairs }", "add: true }"],
    ["Resume is the primary while paused", ": hasPairs && cloud.paused ? Object.assign({ enabled: true }, resume)", ": false ? Object.assign({ enabled: true }, resume)"],
    ["the pause slot is empty beside a Resume primary", "!hasPairs || primary.action === \"resume\" ? null", "!hasPairs ? null"],
    ["the Settings page names its own fields", "return errorText(cloud.lastError, true);", "return errorText(cloud.lastError);"],
    ["Pause needs a folder pair", "var pause = !hasPairs ||", "var pause = !known ||"],
    ["Set up hourly sync while the units are not installed", "var primary = known && cloud.units !== \"installed\"", "var primary = false"],
    ["the window says a pause", "    if (cloud.paused)\n", "    if (false)\n"],
    ["the window names the first file to review", "if (cloud.conflicts.length > 0) lines.push({ text: \"First file to review: \"", "if (false) lines.push({ text: \"First file to review: \""],
    ["a file not copied carries its reason", " && (c.kind !== \"unreadable-on-drive\" || isText(c.reason))", ""],
    ["a file not copied with no copy here needs no local path", "(c.kind === \"unreadable-on-drive\" && !hasOwn(c, \"localPath\")) || ", ""],
    ["only a file not copied may lack its local path", "c.kind === \"unreadable-on-drive\" && !hasOwn(c, \"localPath\")", "!hasOwn(c, \"localPath\")"],
    ["a file not copied names its older copy's folder", "hasOwn(CONFLICT_FOLDER_TEXT, conflict.kind) ? conflict.dirs[0]", "conflict.kind === \"removed-on-drive\" ? conflict.dirs[0]"],
    ["a review row gives the reason", "if (conflict.kind === \"unreadable-on-drive\") what += ", "if (false) what += "],
    ["a known reason reads in its own words", "return row === undefined ? REASON_DEFAULT : row.text;", "return REASON_DEFAULT;"],
    ["an unknown reason reads in the default words", "return row === undefined ? REASON_DEFAULT : row.text;", "return row === undefined ? reason : row.text;"],
    ["a pair with files to review does not read up to date", "if (pair.state === \"idle\" && pair.review > 0) return {", "if (false) return {"],
    ["a pair counts its own files", "return c.pair === p.id;", "return true;"],
    ["a paused pair reads its pause", "if (pair.state === \"idle\" && pair.review > 0) return {", "if (pair.review > 0) return {"],
    ["the pair lines read the pair's view", "return p.label + \": \" + pairView(p, now).text;", "return p.label + \": \" + stateView(p.state, p.staleAfter, now).text;"],
    ["a review group holds each pair's files", "if (group === undefined) {", "if (true) {"],
    ["a change on both sides names the kept copy's folder", "conflict.kind === \"both-changed\" ? conflict.dirs[1] : ", ""],
    ["a connection notifies first", "if (reasons.indexOf(\"authorization-required\") !== -1)\n", "if (false)\n"],
    ["no file to review draws no count", "cloud.conflictCount > 0 ? String(cloud.conflictCount) : \"\"", "String(cloud.conflictCount)"],
    ["no folder pair hides the icon", "if (cloud === undefined || cloud === null || (cloud.pairs.length === 0 && pairListValid(cloud))) return", "if (cloud === undefined || cloud === null) return"],
    ["a Drive folder named as the pair reads Both ways", "return pair.remote === pair.label ? \"Both ways\" : pair.remote;", "return pair.remote;"],
    ["the account key list is published", "values.keys = keyItems(presence);", "values.account = signInValue(presence, record);"]
];

const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "test-google-drive-logic-"));
try {
    const source = fs.readFileSync(file, "utf8");
    for (const [label, needle, replacement] of controls) {
        const count = source.split(needle).length - 1;
        assert.equal(count, 1, "control pattern occurs once: " + label);
        const dir = fs.mkdtempSync(path.join(scratch, "control-"));
        const mutant = path.join(dir, "GoogleDriveLogic.js");
        fs.writeFileSync(mutant, source.replace(needle, replacement));
        assert.notEqual(fs.readFileSync(mutant, "utf8"), source);
        let red = false;
        try { verify(load(mutant)); } catch (e) { red = e instanceof assert.AssertionError; }
        assert.equal(red, true, "control fails without rule: " + label);
    }
} finally {
    fs.rmSync(scratch, { recursive: true, force: true });
}

console.log("test-google-drive-logic: ok");
