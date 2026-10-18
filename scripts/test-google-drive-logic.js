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
// Settings and Setup values (VGS-1744) are held by their tones, actions
// and structure, never their words. A
// review row is held by its structured fields alone (VGS-1727): its needs
// mark, its local-action flag, its folders, and which case of its kind
// its line takes, never its words. The
// tooltip and the Details lines never carry a file name, and the Google
// account a sign-in stored reaches the account value alone.
// Controls edit a copy of the logic, one rule each, and require this suite
// to fail on it.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { load } = require("../bin/lib/qml-library.js");

const file = path.join(__dirname, "..", "shell", "plugins", "vgs.google-drive", "GoogleDriveLogic.js");
const MANIFEST = path.join(__dirname, "..", "shell", "plugins", "vgs.google-drive", "manifest.json");
const Core = load(path.join(__dirname, "..", "shell", "Core", "PluginLogic.js"));
const Timestamp = load(path.join(__dirname, "..", "shell", "Commons", "Timestamp.js"));
const same = (got, want, message) => assert.deepEqual(JSON.parse(JSON.stringify(got)), JSON.parse(JSON.stringify(want)), message || "");

const NOW = Date.parse("2026-10-10T12:00:00Z");
const HOUR = 3600 * 1000;
const iso = ms => new Date(ms).toISOString();
const ADDRESS = "a.person@example.com";

// A record as bin/google-drive renderStatus writes it: a account pair that
// synced an hour ago, an account pair whose connection Google refused, and one
// conflict of each kind.
const HOME = "/home/me";
const DOCS = { id: "docs", label: "Documents", remote: "Docs", local: "/home/me/gdrive", state: "idle", lastSuccess: iso(NOW - HOUR), staleAfter: iso(NOW + HOUR), lastError: null, changes: { added: 1, updated: 0 } };
const INBOX = { id: "inbox", label: "Agent uploads", remote: "Inbox", local: "/home/me/outbox", state: "authorization-required", lastSuccess: iso(NOW - 2 * HOUR), staleAfter: iso(NOW), lastError: { kind: "authorization-refused", at: iso(NOW - 60000), exit: 1 }, changes: null };
// A new name longer than a window row, with no space to break at.
const RENAMED_TO = "Quarterly-planning-notes-for-the-agent-uploads-review-with-every-attachment-from-the-October-meeting.txt";
// Each carries `needs` as bin/google-drive needsOf decides it.
const CONFLICTS = [
    { kind: "both-changed", pair: "docs", pairLabel: "Documents", path: "taxes/2025.xlsx", localPath: "/home/me/gdrive/taxes/2025.xlsx", storedPath: "/home/me/.local/state/vgshell/google-drive/pairs/docs/conflicts/20261010T110000Z-7/taxes/2025.xlsx", since: iso(NOW - HOUR), needs: "you" },
    { kind: "removed-on-drive", pair: "docs", pairLabel: "Documents", path: "old.txt", localPath: "/home/me/gdrive/old.txt", since: iso(NOW - HOUR), needs: "nothing" },
    { kind: "renamed", pair: "inbox", pairLabel: "Agent uploads", path: "a.txt", to: RENAMED_TO, localPath: "/home/me/outbox/a.txt", since: iso(NOW - HOUR), needs: "nothing" },
    { kind: "removed-locally", pair: "docs", pairLabel: "Documents", path: "taxes/receipts.pdf", localPath: "/home/me/gdrive/taxes/receipts.pdf", since: iso(NOW - HOUR), needs: "nothing" }
];
// The kinds a download leg records: a dangling shortcut with no copy
// here and so no local path, then one with an older copy here, with
// rclone's reason, and a name Drive holds twice in two different files,
// one of them the user's.
const DANGLING = "failed to open source object: can't read dangling shortcut";
const DRIVE_CONFLICTS = [
    { kind: "unreadable-on-drive", pair: "docs", pairLabel: "Documents", path: "reports/Plan \u2013 first draft.pdf", reason: DANGLING, since: iso(NOW - HOUR), needs: "nothing" },
    { kind: "unreadable-on-drive", pair: "docs", pairLabel: "Documents", path: "reports/Second gone.pdf", localPath: "/home/me/gdrive/reports/Second gone.pdf", reason: DANGLING, since: iso(NOW - HOUR), needs: "nothing" },
    { kind: "duplicate-different", pair: "docs", pairLabel: "Documents", path: "reports/Twice listed.txt", localPath: "/home/me/gdrive/reports/Twice listed.txt", since: iso(NOW - HOUR), mine: true, needs: "you" }
];
// A doubled name as the runner's status record carries it (bin/google-drive
// conflictsOf): IDENTICAL or not, MINE, and OWNER when given.
const OWNER = "colleague@example.com";
const doubled = (name, identical, mine, owner) => Object.assign({ kind: identical ? "duplicate-identical" : "duplicate-different", pair: "docs", pairLabel: "Documents", path: "legal/" + name, localPath: "/home/me/gdrive/legal/" + name, since: iso(NOW - HOUR), mine: mine, needs: !identical && mine ? "you" : "nothing" }, owner === undefined ? {} : { owner: owner });
// A record's `needsYou` is its count of rows that need the user, unless
// OVER names it.
function record(over) {
    const r = recordOf(over);
    if (!Object.prototype.hasOwnProperty.call(over || {}, "needsYou")) r.needsYou = r.conflicts.filter(c => c.needs === "you").length;
    return r;
}
function recordOf(over) {
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

// The sentences that send the user to the Setup tab's sign-in step, read
// from the logic: their words are not this suite's to pin.
const SETUP_LINK = "](page:vgs.google-drive/Setup)";
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

// The Details sync hint of a row that sends the user to the Setup tab's
// sign-in step, and of one whose folder pair waits for the hourly sync,
// which says what the schedule value says. A row may instead name the
// error whose sentence its hint is, so the published error keeps the
// account it names.
const LINKED = { linksSetup: true };
const SETUP_AGAIN = { schedule: "failed" };

// One row per state of the sync: the record, then the headline's text,
// tone and icon every surface must show, the window footer's primary, the
// Details hint, and whether the bar hides its icon.
const STATES = [
    ["first run", { state: "not-set-up", units: "absent", lastSuccess: null, staleAfter: null, lastError: null, pairs: [], conflicts: [], attention: null }, "No folder pairs", "warning", "cloud", NO_SYNC, undefined, true],
    ["a folder pair whose hourly sync did not install", well({ state: "not-set-up", units: "absent" }), "Not set up", "warning", "cloud", SETUP, SETUP_AGAIN],
    ["no keys", well({ state: "authorization-required", pairs: [Object.assign({}, DOCS, { state: "authorization-required", lastError: { kind: "credential-absent", account: "client-id" } })], lastError: { kind: "credential-absent", account: "client-id", pair: "docs" } }), "Sign-in needed", "danger", "cloud-alert", NO_SYNC, LINKED],
    ["no folder pair", { state: "not-set-up", units: "installed", lastSuccess: null, staleAfter: null, lastError: null, pairs: [], conflicts: [], attention: null }, "No folder pairs", "warning", "cloud", NO_SYNC, undefined, true],
    ["pair list not readable", invalid(), "Sync failed", "danger", "cloud-alert", NO_SYNC, INVALID, false],
    ["signed out", well({ state: "authorization-required", pairs: [Object.assign({}, DOCS, { state: "authorization-required", lastError: signedOut })], lastError: Object.assign({ pair: "docs" }, signedOut) }), "Sign-in needed", "danger", "cloud-alert", NO_SYNC, { error: signedOut }],
    ["syncing while another pair needs a sign-in", record({ state: "running", pairs: [Object.assign({}, DOCS, { state: "running" }), INBOX], conflicts: [] }), "Sign-in needed", "danger", "cloud-alert", NO_SYNC, LINKED],
    ["syncing while another pair failed", well({ state: "running", pairs: [Object.assign({}, DOCS, { state: "running" }), Object.assign({}, INBOX, { state: "error", lastError: { kind: "source-missing" } })], lastError: { kind: "source-missing", pair: "inbox" }, conflicts: CONFLICTS.slice(0, 1) }), "Sync failed", "danger", "cloud-alert", NO_SYNC, "A Google Drive folder of a folder pair does not exist."],
    ["empty review", well(), "Up to date", "ok", "cloud-check", SYNC, undefined],
    ["data old", well({ staleAfter: iso(NOW) }), "Out of date", "warning", "cloud-alert", SYNC, undefined],
    ["never synced", well({ lastSuccess: null, staleAfter: null }), "Not synced yet", "info", "cloud", SYNC, undefined],
    ["syncing", well({ state: "running", pairs: [Object.assign({}, DOCS, { state: "running" })] }), "Syncing", "info", "cloud-sync", NO_SYNC, undefined],
    ["paused", well({ state: "paused", paused: true, pairs: [PAUSED_DOCS] }), "Paused", "info", "cloud-off", RESUME, undefined],
    ["every pair paused on its own", well({ state: "paused", pairs: [PAUSED_DOCS] }), "Paused", "info", "cloud-off", NO_SYNC, undefined],
    ["error", well({ state: "error", lastError: { kind: "source-missing", pair: "docs" } }), "Sync failed", "danger", "cloud-alert", SYNC, "A Google Drive folder of a folder pair does not exist."],
    ["offline", well({ state: "offline", lastError: { kind: "offline", pair: "docs" } }), "Offline", "warning", "cloud-off", SYNC, "Google Drive cannot be reached. VGS tries again at the next sync."],
    ["keyring locked", well({ state: "authorization-required", pairs: [Object.assign({}, DOCS, { state: "authorization-required", lastError: { kind: "credential-locked", account: "client-id" } })], lastError: { kind: "credential-locked", account: "client-id", pair: "docs" } }), "Sign-in needed", "danger", "cloud-alert", SYNC, "Your keyring is locked. Unlock it to sync."],
    ["sign-in needed", record({ conflicts: [] }), "Sign-in needed", "danger", "cloud-alert", SYNC, LINKED],
    ["set up with files to review", well({ conflicts: CONFLICTS.slice(0, 2) }), "2 files to review", "warning", "cloud-alert", SYNC, "Open the Google Drive window to review them."],
    ["one file to review", well({ conflicts: CONFLICTS.slice(1, 2) }), "1 file to review", "warning", "cloud-alert", SYNC, "Open the Google Drive window to review them."],
    ["files to review while paused", well({ state: "paused", paused: true, pairs: [PAUSED_DOCS], conflicts: CONFLICTS.slice(0, 2) }), "2 files to review", "warning", "cloud-alert", RESUME, "Open the Google Drive window to review them."],
    ["sign-in needed with files to review", record(), "Sign-in needed", "danger", "cloud-alert", SYNC, LINKED]
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
        ["attention with no notified", JSON.stringify(record({ attention: { reasons: [], key: "k" } })), "status=attention"],
        ["a row with no needs mark", JSON.stringify(record({ conflicts: [Object.assign({}, CONFLICTS[1], { needs: undefined })] })), "status=conflicts"],
        ["a needs mark the runner never writes", JSON.stringify(record({ conflicts: [Object.assign({}, CONFLICTS[1], { needs: "maybe" })] })), "status=conflicts"],
        ["the earlier doubled-name kind", JSON.stringify(record({ conflicts: [{ kind: "duplicate-on-drive", pair: "docs", pairLabel: "Documents", path: "reports/Twice listed.txt", localPath: "/home/me/gdrive/reports/Twice listed.txt", since: iso(NOW - HOUR), needs: "nothing" }] })), "status=conflicts"],
        ["a doubled name with no mine", JSON.stringify(record({ conflicts: [Object.assign({}, doubled("a.pdf", true, true), { mine: undefined })] })), "status=conflicts"],
        ["mine as text", JSON.stringify(record({ conflicts: [doubled("a.pdf", true, "yes")] })), "status=conflicts"],
        ["mine on a row that is no doubled name", JSON.stringify(record({ conflicts: [Object.assign({}, CONFLICTS[1], { mine: true })] })), "status=conflicts"],
        ["an owner on the user's own copies", JSON.stringify(record({ conflicts: [doubled("a.pdf", true, true, OWNER)] })), "status=conflicts"],
        ["an owner that is no address", JSON.stringify(record({ conflicts: [doubled("a.pdf", true, false, "a colleague")] })), "status=conflicts"],
        ["an owner with a line break", JSON.stringify(record({ conflicts: [doubled("a.pdf", true, false, "colleague@example.com\nx")] })), "status=conflicts"],
        ["an owner on a row that is no doubled name", JSON.stringify(record({ conflicts: [Object.assign({}, CONFLICTS[1], { owner: OWNER })] })), "status=conflicts"],
        ["no needs-you count", JSON.stringify(record({ needsYou: undefined })), "status=needsYou"],
        ["a needs-you count as text", JSON.stringify(record({ needsYou: "1" })), "status=needsYou"],
        ["a needs-you count that counts the notes", JSON.stringify(record({ needsYou: CONFLICTS.length })), "status=needsYou"]
    ];
    for (const [label, text, error] of bad) same(L.parseStatus(text), { ok: false, error }, label);
    // The runner's doubled-name records (bin/google-drive duplicateRecord,
    // conflictsOf), each judged whole.
    const RUNNER_DOUBLED = [
        ["identical, the user's", doubled("a.pdf", true, true)],
        ["different, the user's", doubled("b.pdf", false, true)],
        ["identical, shared by an owner", doubled("c.pdf", true, false, OWNER)],
        ["different, shared by an owner", doubled("d.pdf", false, false, OWNER)],
        ["identical, no owner named", doubled("e.pdf", true, false)],
        ["different, no owner named", doubled("f.pdf", false, false)]
    ];
    for (const [label, c] of RUNNER_DOUBLED) {
        const judgedDoubled = L.parseStatus(JSON.stringify(well({ conflicts: [c] })));
        assert.equal(judgedDoubled.ok, true, label + ": " + judgedDoubled.error);
    }

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
        ["sign-in", "authorization-required", null, "Sign-in needed", "danger"],
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
        const sync = L.statusValues(rec, null, "", "", NOW, HOME).sync;
        same([sync.text, sync.tone], [text, tone], label + ": the Details sync value");
        if (hint === LINKED) assert.ok(typeof sync.hint === "string" && sync.hint.includes(SETUP_LINK), label + ": the Details hint links the Setup tab: " + sync.hint);
        else if (hint !== undefined && hint.error !== undefined) same(sync.hint, L.errorText(hint.error), label + ": the Details hint is the sentence of the record's own error");
        else if (hint === SETUP_AGAIN) same(sync.hint, L.scheduleValue(rec.units, true).hint, label + ": the Details hint says what Hourly sync says");
        else assert.equal(sync.hint, hint, label + ": the Details hint");
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
    const values = L.statusValues(good.record, presence, "", "", NOW, HOME);
    same(Object.keys(values).sort(), ["account", "cloud", "cloudKeys", "connection", "firstPair", "keys", "lastSync", "pairList", "pairs", "schedule", "sync"]);
    same(values.sync.lines, ["Documents: 3 files to review", "Agent uploads: Sign-in needed"], "a line per pair, each by its own state and files");
    assert.equal(values.lastSync, NOW - HOUR);
    same(Object.keys(L.statusValues(null, null, "", "", NOW, HOME)), [], "nothing is published before the first answers");
    same(Object.keys(L.statusValues(null, presence, "", "", NOW, HOME)).sort(), ["account", "cloudKeys", "connection", "keys"]);

    // A state value as a page reads it: its tone, the action it names, null
    // for none, and whether it says the user cannot act on it.
    const step = v => [v.tone, v.action === undefined || v.action === false ? null : v.action, v.available === false];

    // firstPair: To do with Add while no pair, done with one, and not
    // available while the list cannot be read, linking its repair, or
    // while no sign-in is stored, so it follows the sign-in step.
    const signedOutProbe = L.parseProbe(JSON.stringify(probe({ token: { presence: "absent" } }))).presence;
    for (const [label, rec, p, want] of [
        ["no folder pair, signed in", well({ state: "not-set-up", pairs: [] }), presence, ["warning", true, false]],
        ["no folder pair before the probe answers", well({ state: "not-set-up", pairs: [] }), null, ["warning", true, false]],
        ["no folder pair, no sign-in", well({ state: "not-set-up", pairs: [] }), signedOutProbe, ["info", null, true]],
        ["a folder pair, no sign-in", good.record, signedOutProbe, ["ok", null, false]],
        ["a folder pair", good.record, presence, ["ok", null, false]],
        ["an unreadable list", invalid(), presence, ["warning", null, true]]
    ]) same(step(L.statusValues(rec, p, "", "", NOW, HOME).firstPair), want, "first pair: " + label);
    assert.ok(L.statusValues(invalid(), null, "", "", NOW, HOME).firstPair.hint.includes("](page:vgs.google-drive/Details)"), "an unreadable list's step links its repair");

    // schedule: Set up again only while the units are out of date, or
    // absent beside a folder pair, whose add could not install them; with
    // no pair nothing asks for setup (VGS-1744).
    const SCHEDULES = [
        ["installed", "installed", true, ["ok", null, false]],
        ["installed, no pair", "installed", false, ["ok", null, false]],
        ["out of date", "stale", true, ["warning", true, false]],
        ["out of date, no pair", "stale", false, ["warning", true, false]],
        ["absent beside a pair", "absent", true, ["warning", true, false]],
        ["absent, no pair", "absent", false, ["info", null, false]]
    ];
    for (const [label, units, hasPairs, want] of SCHEDULES) same(step(L.scheduleValue(units, hasPairs)), want, "schedule: " + label);
    assert.throws(() => L.scheduleValue("maybe", true), /units "maybe"/);
    same(values.schedule, L.scheduleValue("installed", true));
    same(L.statusValues(well({ state: "not-set-up", units: "absent", pairs: [] }), null, "", "", NOW, HOME).schedule, L.scheduleValue("absent", false), "the schedule reads the record's pairs");

    // pairs: one Settings row per pair, by its id, with Remove, its two
    // folders, the local one from `~` under the home folder, and its state:
    // a warning, which the page draws as a chip, only while its files need
    // the user, else its own state's tone.
    same(values.pairs.map(r => [r.id, r.label, r.actions]), [["docs", "Documents", ["remove"]], ["inbox", "Agent uploads", ["remove"]]]);
    same(values.pairs.map(r => r.secondary), ["Drive/Docs ⇄ ~/gdrive", "Drive/Inbox ⇄ ~/outbox"]);
    same(values.pairs.map(r => r.state.tone), ["warning", "danger"], "a file that needs the user, and a sign-in");
    const rowState = rec => L.statusValues(rec, null, "", "", NOW, HOME).pairs[0].state;
    for (const [label, rec, tone] of [
        ["nothing to review", well(), "ok"],
        ["notes alone", well({ conflicts: CONFLICTS.slice(1, 2) }), "ok"],
        ["a file that needs the user", well({ conflicts: CONFLICTS.slice(0, 1) }), "warning"],
        ["paused", well({ state: "paused", paused: true, pairs: [PAUSED_DOCS] }), "info"],
        ["paused with a file that needs the user", well({ state: "paused", paused: true, pairs: [PAUSED_DOCS], conflicts: CONFLICTS.slice(0, 1) }), "warning"],
        ["never synced", well({ pairs: [Object.assign({}, DOCS, { lastSuccess: null, staleAfter: null })] }), "info"]
    ]) assert.equal(rowState(rec).tone, tone, "pair row state: " + label);
    assert.ok(rowState(well({ conflicts: CONFLICTS.slice(0, 1) })).text.startsWith("1 "), "the chip counts the files that need the user");
    assert.ok(rowState(well({ conflicts: [CONFLICTS[0], DRIVE_CONFLICTS[2], CONFLICTS[1]] })).text.startsWith("2 "), "notes add nothing to the count");
    const folders = [
        ["under the home folder", "/home/me/Drive/Docs", HOME, "Drive/Docs ⇄ ~/Drive/Docs"],
        ["outside the home folder", "/srv/share/Docs", HOME, "Drive/Docs ⇄ /srv/share/Docs"],
        ["a sibling that shares the home folder's name", "/home/meow/Docs", HOME, "Drive/Docs ⇄ /home/meow/Docs"],
        ["no home folder known", "/home/me/Drive/Docs", "", "Drive/Docs ⇄ /home/me/Drive/Docs"]
    ];
    for (const [label, local, home, line] of folders) {
        const rec = well({ pairs: [Object.assign({}, DOCS, { local })] });
        same(L.statusValues(rec, null, "", "", NOW, home).pairs[0].secondary, line, label + ": the Settings row");
        assert.equal(L.pairRow(L.cloudValue(rec, "").pairs[0], NOW, home).secondary, line, label + ": the window row");
    }
    same(L.statusValues(well({ state: "not-set-up", pairs: [] }), null, "", "", NOW, HOME).pairs, [], "no pair, no row");
    const unreadable = L.statusValues(invalid(), null, "", "", NOW, HOME).pairs;
    same(unreadable.map(r => [r.state.tone, r.actions]), [["danger", []]], "an unreadable list holds one row that says so, which offers no Remove");

    // pairList: hidden while the runner reads the list, else its repair.
    same(values.pairList, { hidden: true });
    const genericPairListProblem = L.errorText({ kind: "pairs-invalid" });
    const pairProblems = [
        ["a pair rule", "pair=docs rule=repository-inside", "docs"],
        ["not JSON", "pairs-file=not-json", "file is damaged"],
        ["unreadable", "pairs-file=unreadable-EACCES", "read"],
        ["wrong shape", "pairs-file=shape", "list"],
        ["pair rule", "pair=docs rule=local-overlap", "docs"],
        ["unknown pair", "pair=? rule=shape", "entry"]
    ];
    const seenPairProblemText = new Set();
    for (const [label, detail, word] of pairProblems) {
        const value = L.statusValues(invalid(detail), null, "", "", NOW, HOME).pairList;
        same(step(value), ["danger", true, false], label + ": the repair is offered");
        assert.ok(value.hint.length <= L.HINT_MAX, label + ": hint ceiling");
        assert.ok(value.hint.includes(word), label + ": sentence category");
        assert.ok(value.hint !== genericPairListProblem, label + ": known detail is not generic");
        assert.ok(!value.hint.includes("rule=") && !value.hint.includes("pairs-file=") && !value.hint.includes("pair="), label + ": keyed detail hidden");
        seenPairProblemText.add(value.hint.split(". ")[0]);
    }
    assert.equal(seenPairProblemText.size, pairProblems.length, "each pair-list problem class has its own sentence");
    const unknownPairProblem = L.statusValues(invalid("not-a-runner-detail"), null, "", "", NOW, HOME).pairList;
    assert.equal(unknownPairProblem.action, true, "an unknown detail still offers the repair");
    assert.ok(unknownPairProblem.hint.includes(genericPairListProblem), "an unknown detail falls back to the generic sentence");
    assert.equal(L.pairListValid(L.cloudValue(invalid(), "")), false);
    assert.equal(L.pairListValid(L.cloudValue(well(), "")), true);

    // keys: the client ID and secret, each with its own hint and info.
    same(values.keys.map(k => [k.secret, k.value]), [["client-id", "present"], ["client-secret", "present"]]);
    for (const key of values.keys) assert.ok(key.hint !== "" && key.info !== "" && key.hint !== key.info, key.secret + ": its own hint and info");
    assert.notEqual(values.keys[0].info, values.keys[1].info, "each key explains itself");

    // The Setup steps and the Details account from the probe: the keys,
    // then the sign-in, which waits for both keys, then the account.
    const withUser = (user, extra) => L.parseProbe(JSON.stringify(probe(Object.assign({ "token": user === undefined ? {} : { user } }, extra || {})))).presence;
    const SIGN_INS = [
        // label, presence, record, keys step, sign-in step, account
        ["sign-in locked", withUser(undefined, { "token": { presence: "locked" } }), null, ["ok", null, false], ["warning", null, true], ["warning", null, false]],
        ["keys locked", withUser(ADDRESS, { "client-id": { presence: "locked" } }), null, ["warning", null, true], ["warning", null, true], ["warning", null, false]],
        ["keyring unreadable", withUser(undefined, { "client-id": { presence: "unavailable" } }), null, ["warning", null, true], ["warning", null, true], ["warning", null, false]],
        ["no keys", withUser(undefined, { "client-id": { presence: "absent" }, "client-secret": { presence: "absent" }, "token": { presence: "absent" } }), null, ["warning", null, false], ["info", null, true], ["info", null, false]],
        ["one key", withUser(undefined, { "client-secret": { presence: "absent" }, "token": { presence: "absent" } }), null, ["warning", null, false], ["info", null, true], ["info", null, false]],
        ["no sign-in", withUser(undefined, { "token": { presence: "absent" } }), null, ["ok", null, false], ["warning", "signIn", false], ["info", null, false]],
        ["sign-in refused", withUser(ADDRESS), good.record, ["ok", null, false], ["danger", "again", false], ["danger", true, false]],
        ["signed in", withUser(ADDRESS), well(), ["ok", null, false], ["ok", null, false], ["ok", true, false]]
    ];
    for (const [label, p, rec, keys, signIn, account] of SIGN_INS) {
        const v = L.statusValues(rec, p, "", "", NOW, HOME);
        same(step(v.cloudKeys), keys, label + ": the keys step");
        same(step(v.connection), signIn, label + ": the sign-in step");
        same(step(v.account), account, label + ": the account");
    }
    // The account names the address its token carries, as its value; one
    // too long for a value names none.
    assert.equal(L.statusValues(well(), withUser(ADDRESS), "", "", NOW, HOME).account.text, ADDRESS);
    const long = "a".repeat(200) + "@example.com";
    assert.ok(!JSON.stringify(L.statusValues(well(), withUser(long), "", "", NOW, HOME).account).includes(long), "an address past the value's ceiling is left out");
    // A step that is not done and that the user cannot act on says why.
    for (const [label, p, rec] of SIGN_INS) {
        const v = L.statusValues(rec, p, "", "", NOW, HOME);
        for (const key of ["cloudKeys", "connection"])
            if (v[key].available === false) assert.ok(typeof v[key].hint === "string" && v[key].hint !== "", label + ": " + key + " says why it waits");
    }
    // The account reaches the account value alone.
    const signedInValues = L.statusValues(well(), withUser(ADDRESS), "", "", NOW, HOME);
    for (const key of Object.keys(signedInValues).filter(k => k !== "account"))
        assert.ok(!JSON.stringify(signedInValues[key]).includes(ADDRESS), "the account shows in " + key);

    // Every value the service publishes is one the core takes for the
    // plugin's own manifest (PluginLogic.statusWrite), in every world.
    const manifest = Core.validateManifest(JSON.parse(fs.readFileSync(MANIFEST, "utf8")), path.dirname(MANIFEST));
    assert.equal(manifest.ok, true, manifest.error);
    const longLabel = Object.assign({}, DOCS, { label: "L".repeat(64), remote: "R/".repeat(90) + "R", local: "/srv/" + "x".repeat(300) });
    const worlds = [good.record, well(), invalid(), well({ state: "not-set-up", units: "absent", pairs: [] }), well({ state: "not-set-up", units: "absent" }), well({ units: "stale" }),
        well({ pairs: [longLabel] }), well({ conflicts: CONFLICTS.concat(DRIVE_CONFLICTS) })];
    for (const rec of worlds) for (const [, p] of SIGN_INS.map(r => [r[0], r[1]]).concat([["long address", withUser(long)]])) {
        const v = L.statusValues(rec, p, "", "", NOW, HOME);
        for (const key of Object.keys(v)) {
            const written = Core.statusWrite(manifest.manifest, {}, key, v[key]);
            assert.equal(written.ok, true, key + ": " + written.error + " " + JSON.stringify(v[key]));
        }
    }

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
    same(tip.details.split("\n"), ["Documents: 3 files to review", "Agent uploads: Sign-in needed", "4 files to review", "Last sync " + Timestamp.text(NOW - HOUR, NOW)]);
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
        [L.errorText({ kind: "authorization-refused" }), "danger"]
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
    same(L.pairRow(cloud.pairs[0], NOW, HOME), { id: "docs", label: "Documents", secondary: "Drive/Docs \u21c4 ~/gdrive", icon: "folder-sync", text: "3 files to review", tone: "warning" });
    same(L.cloudValue(good.record, "").pairs.map(p => p.review), [3, 1]);
    const badge = rec => { const p = L.pairRow(L.cloudValue(rec, "").pairs[0], NOW, HOME); return [p.text, p.tone]; };
    same(badge(well()), ["Up to date", "success"]);
    same(badge(well({ conflicts: DRIVE_CONFLICTS.slice(0, 1) })), ["1 file to review", "warning"]);
    same(badge(well({ conflicts: CONFLICTS.slice(2, 3) })), ["Up to date", "success"], "another pair's file");
    same(badge(well({ state: "paused", paused: true, pairs: [PAUSED_DOCS], conflicts: CONFLICTS.slice(0, 1) })), ["Paused", "info"]);
    same(L.pairRow(cloud.pairs[1], NOW, HOME), { id: "inbox", label: "Agent uploads", secondary: "Drive/Inbox \u21c4 ~/outbox", icon: "folder-sync", text: "Sign-in needed", tone: "danger" });
    // The footer: one primary, Set up hourly sync again while the schedule
    // offers it, Resume while paused; Pause or Resume and Add a folder pair
    // only while a folder pair exists, since the empty pair list offers Add.
    const SETUP_FOOT = { text: "Set up hourly sync again", icon: "cloud-cog", action: "setup", enabled: true };
    const footer = rec => L.footerView(rec === undefined ? undefined : L.cloudValue(rec, ""));
    const footers = [
        ["before the first value", undefined, { primary: { text: "Sync now", icon: "refresh-cw", action: "sync", enabled: false }, pause: null, add: false }],
        ["first run", well({ state: "not-set-up", units: "absent", pairs: [] }), { primary: { text: "Sync now", icon: "refresh-cw", action: "sync", enabled: false }, pause: null, add: false }],
        ["a folder pair whose units did not install", well({ state: "not-set-up", units: "absent" }), { primary: SETUP_FOOT, pause: { text: "Pause", icon: "pause", action: "pause" }, add: true }],
        ["no folder pair", well({ state: "not-set-up", pairs: [] }), { primary: { text: "Sync now", icon: "refresh-cw", action: "sync", enabled: false }, pause: null, add: false }],
        ["units stale with a pair", well({ units: "stale" }), { primary: SETUP_FOOT, pause: { text: "Pause", icon: "pause", action: "pause" }, add: true }],
        ["set up", well(), { primary: { text: "Sync now", icon: "refresh-cw", action: "sync", enabled: true }, pause: { text: "Pause", icon: "pause", action: "pause" }, add: true }],
        ["paused", well({ state: "paused", paused: true, pairs: [PAUSED_DOCS] }), { primary: { text: "Resume", icon: "play", action: "resume", enabled: true }, pause: null, add: true }],
        ["units stale while paused", well({ units: "stale", state: "paused", paused: true, pairs: [PAUSED_DOCS] }), { primary: SETUP_FOOT, pause: { text: "Resume", icon: "play", action: "resume" }, add: true }]
    ];
    for (const [label, rec, want] of footers) same(footer(rec), want, "footer: " + label);
    // Each review row by its fields: its needs mark and local-action flag
    // as the record and its kind give them, the folders Open folders opens,
    // and whether a folder line names the copy its line speaks of.
    const KEPT = "/home/me/.local/state/vgshell/google-drive/pairs/docs/conflicts/20261010T110000Z-7/taxes";
    const UNKNOWN_REASON = Object.assign({}, DRIVE_CONFLICTS[0], { path: "reports/Held.pdf", reason: "failed to open source object: stand-in cause", needs: "you" });
    const ROWS = [
        // label, record row, needs, local action, dirs, folder line
        ["a change on both sides with the copy that was here kept", CONFLICTS[0], "you", true, ["/home/me/gdrive/taxes", KEPT], true],
        ["a change on both sides uploaded from here", Object.assign({}, CONFLICTS[0], { storedPath: undefined }), "you", true, ["/home/me/gdrive/taxes"], false],
        ["a Drive deletion put back", CONFLICTS[1], "nothing", true, ["/home/me/gdrive"], false],
        ["a Drive rename", CONFLICTS[2], "nothing", true, ["/home/me/outbox"], false],
        ["a local deletion put back", CONFLICTS[3], "nothing", true, ["/home/me/gdrive/taxes"], false],
        ["a dangling shortcut never copied", DRIVE_CONFLICTS[0], "nothing", false, [], false],
        ["a dangling shortcut with an earlier copy here", DRIVE_CONFLICTS[1], "nothing", false, [], true],
        ["a file not copied for another reason", UNKNOWN_REASON, "you", false, [], false],
        ["identical copies, the user's", doubled("a.pdf", true, true), "nothing", false, [], false],
        ["different copies, the user's", doubled("b.pdf", false, true), "you", false, [], false],
        ["identical copies shared by an owner", doubled("c.pdf", true, false, OWNER), "nothing", false, [], false],
        ["different copies shared by an owner", doubled("d.pdf", false, false, OWNER), "nothing", false, [], false],
        ["identical copies, no owner named", doubled("e.pdf", true, false), "nothing", false, [], false],
        ["different copies, no owner named", doubled("f.pdf", false, false), "nothing", false, [], false]
    ];
    const rowOf = c => {
        const judgedRow = L.parseStatus(JSON.stringify(well({ conflicts: [c] })));
        assert.equal(judgedRow.ok, true, c.path + ": " + judgedRow.error);
        const published = L.cloudValue(judgedRow.record, "").conflicts[0];
        return [published, L.conflictGroups([published])[0].rows[0]];
    };
    const details = {};
    for (const [label, c, needs, local, dirs, folder] of ROWS) {
        const [published, row] = rowOf(c);
        same([published.needs, published.localAction, published.dirs], [needs, local, dirs], label + ": the published row");
        same([row.needs, row.localAction, row.dirs, row.folder !== ""], [needs, local, dirs, folder], label + ": the window row");
        // Only the line that states how long VGS keeps a copy has the info
        // that says why.
        assert.equal(row.info !== "", label === "a change on both sides with the copy that was here kept", label + ": the limit's info");
        assert.equal(row.label, c.path, label + ": the row names its file");
        assert.ok(typeof row.detail === "string" && row.detail !== "", label + ": the row has its line");
        details[label] = row.detail;
    }
    // Each case of a kind takes its own line: who can act on a doubled
    // name, a kept copy or an upload, a dangling shortcut or another cause.
    const cases = ["identical copies, the user's", "identical copies shared by an owner", "identical copies, no owner named",
        "different copies, the user's", "different copies shared by an owner", "different copies, no owner named"];
    assert.equal(new Set(cases.map(c => details[c])).size, cases.length, "each doubled-name case has its own line");
    assert.notEqual(details["a change on both sides with the copy that was here kept"], details["a change on both sides uploaded from here"]);
    assert.notEqual(details["a dangling shortcut never copied"], details["a file not copied for another reason"]);
    assert.ok(details["identical copies shared by an owner"].includes(OWNER) && details["different copies shared by an owner"].includes(OWNER), "a shared doubled name names its owner");
    for (const c of cases.filter(c => !c.includes("shared"))) assert.ok(!details[c].includes("@"), c + ": names no one");
    assert.ok(details["a Drive rename"].includes(RENAMED_TO), "a rename names its new name");
    // The folder line names the folder of the copy it speaks of.
    assert.ok(rowOf(CONFLICTS[0])[1].folder.endsWith(KEPT), "the kept copy's folder");
    assert.ok(rowOf(DRIVE_CONFLICTS[1])[1].folder.endsWith("/home/me/gdrive/reports"), "the earlier copy's folder");
    // The needs-you count the record publishes reaches the window's data.
    const drivenRecord = L.parseStatus(JSON.stringify(well({ conflicts: CONFLICTS.concat(DRIVE_CONFLICTS) })));
    assert.equal(drivenRecord.ok, true, drivenRecord.error);
    assert.equal(L.cloudValue(drivenRecord.record, "").needsYou, 2, "one change on both sides and one doubled name of the user's");
    // A file not copied reads by rclone's reason, never in rclone's words.
    const driveSide = L.parseStatus(JSON.stringify(well({ conflicts: DRIVE_CONFLICTS })));
    assert.equal(driveSide.ok, true, driveSide.error);
    const driveCloud = L.cloudValue(driveSide.record, "");
    same(L.headline(driveCloud, NOW).text, "3 files to review");
    const unknown = L.cloudValue(well({ conflicts: [UNKNOWN_REASON] }), "");
    for (const value of [driveCloud, unknown]) assert.ok(!JSON.stringify(value).includes("failed to open source object"), "rclone's text is published");
    // Rows that need the user come first, in the list, in each pair's
    // group and in the pair order, and the cap cuts notes before them.
    same(driveCloud.conflicts.map(c => c.needs), ["you", "nothing", "nothing"], "the user's doubled name comes first");
    same(subtitle(L.windowStatus(driveCloud, NOW, Timestamp.text))[1], ["First file to review: " + DRIVE_CONFLICTS[2].path, ""]);
    const INBOX_NOTE = Object.assign({}, CONFLICTS[2], { path: "note.txt" });
    const mixed = L.cloudValue(well({ conflicts: [INBOX_NOTE, CONFLICTS[1], DRIVE_CONFLICTS[0], CONFLICTS[0], CONFLICTS[3], DRIVE_CONFLICTS[2]] }), "");
    same(mixed.conflicts.map(c => c.path), [CONFLICTS[0].path, DRIVE_CONFLICTS[2].path, INBOX_NOTE.path, CONFLICTS[1].path, DRIVE_CONFLICTS[0].path, CONFLICTS[3].path], "needs-you first, each part in the record's order");
    same(L.conflictGroups(mixed.conflicts).map(g => [g.label, g.rows.map(r => r.needs)]), [["Documents", ["you", "you", "nothing", "nothing", "nothing"]], ["Agent uploads", ["nothing"]]], "the group of the first row that needs the user leads");
    const notes = Array.from({ length: L.CONFLICTS_MAX + 5 }, (_, i) => Object.assign({}, CONFLICTS[1], { path: "n" + i + ".txt" }));
    const overCap = L.cloudValue(well({ conflicts: notes.concat([CONFLICTS[0]]) }), "");
    assert.equal(overCap.conflicts.length, L.CONFLICTS_MAX);
    same([overCap.conflicts[0].path, overCap.conflicts[0].needs], [CONFLICTS[0].path, "you"], "the cap keeps the row that needs the user");
    const heavy = record({ conflicts: Array.from({ length: 500 }, (_, i) => Object.assign({}, CONFLICTS[1], { path: "f" + i + ".txt", localPath: "/home/me/gdrive/" + "x".repeat(3000) + "/f" + i + ".txt" })).concat([CONFLICTS[0]]) });
    const heavyCloud = L.cloudValue(heavy, "");
    assert.ok(heavyCloud.conflicts.length < L.CONFLICTS_MAX, "the byte ceiling cuts the list");
    assert.equal(heavyCloud.conflicts[0].needs, "you", "the byte ceiling keeps the row that needs the user");
    // The notification: one per reason in order of need.
    same(L.notification(good.record), { title: "Google Drive needs a sign-in", message: L.errorText({ kind: "authorization-refused" }), tone: "danger" });
    // The conflicts reason counts the rows that need the user: four rows,
    // one of which needs the user, notify as that one row alone does, and
    // two that need the user do not.
    const asked = conflicts => L.notification(record({ conflicts, attention: { reasons: ["conflicts"], key: "k", notified: false } }));
    assert.equal(asked(CONFLICTS).tone, "warning");
    same(asked(CONFLICTS), asked(CONFLICTS.slice(0, 1)), "the notes raise no count");
    assert.notEqual(asked(CONFLICTS).message, asked([CONFLICTS[0], DRIVE_CONFLICTS[2]]).message, "the count is the rows that need the user");
    same(L.notification(record({ lastError: { kind: "offline" }, attention: { reasons: ["error"], key: "k", notified: false } })).tone, "danger");
    const stale = L.notification(record({ attention: { reasons: ["units-stale"], key: "k", notified: false } }));
    assert.equal(stale.tone, "warning");
    assert.ok(stale.message.includes("](page:vgs.google-drive/Details)"), "out-of-date units link the Details tab, which holds Set up again");
    assert.equal(L.notification(record({ attention: null })), null);
    same(L.notification(record({ lastError: Object.assign({ pair: "docs" }, signedOut) })).message, L.errorText(signedOut), "a missing token is a sign-in");
    // Each sentence that asks for a key or a sign-in links the Setup tab,
    // where those steps are, the Details sync value's included.
    for (const error of [signedOut, { kind: "credential-absent", account: "client-id" }, { kind: "authorization-refused" }])
        assert.ok(L.errorText(error).includes(SETUP_LINK), JSON.stringify(error) + ": links the Setup tab");
    assert.notEqual(L.errorText(signedOut), L.errorText({ kind: "credential-absent", account: "client-id" }), "a missing sign-in is no missing key");

    // A failed request reads as a sentence.
    assert.notEqual(L.problemText("start", "start exit=1 google-drive: refused: units=absent"), L.problemText("start", "start exit=1 google-drive: refused: busy"), "absent units name their own fix");
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
    ["the first pair waits for a sign-in", 'if (presence !== null && presence.token.presence !== "present")\n        return', 'if (false)\n        return'],
    ["first pair cannot finish empty", 'if (cloud.pairs.length > 0) return { tone: "ok", text: "A folder pair is ready" };', 'return { tone: "ok", text: "A folder pair is ready" };'],
    ["the sign-in step offers Sign in while none is stored", 'text: "Not signed in", action: "signIn" };', 'text: "Not signed in" };'],
    ["the sign-in step waits for both keys", 'if (states[0] !== "present" || states[1] !== "present")\n        return { tone: "info", text: "Keys needed"', 'if (false)\n        return { tone: "info", text: "Keys needed"'],
    ["a sign-in that waits for the keys says the user cannot act there", 'text: "Keys needed", available: false,', 'text: "Keys needed",'],
    ["the keys step needs both keys", 'if (states[0] === "present" && states[1] === "present") return { tone: "ok"', 'if (states[0] === "present") return { tone: "ok"'],
    ["the account is the token's address", 'text: user !== undefined && user.length <= ROW_TEXT_MAX ? user : "Signed in"', 'text: "Signed in"'],
    ["an address past the value's ceiling is left out", 'user !== undefined && user.length <= ROW_TEXT_MAX ? user', 'user !== undefined ? user'],

    ["the missing-key text links to Setup", "then [sign in on the Google Drive Setup tab](page:vgs.google-drive/Setup).", "then sign in on the Google Drive Setup tab."],
    ["the judge refuses an unknown state", "if (STATES.indexOf(doc.state) === -1) return", "if (false) return"],
    ["the judge needs attention.notified", "\n        && typeof doc.attention.notified === \"boolean\")", ")"],
    ["a both-changed stored path is absolute", "&& (c.kind !== \"both-changed\" || !hasOwn(c, \"storedPath\") || (isText(c.storedPath) && c.storedPath.charAt(0) === \"/\"))", ""],
    ["an address holds one @", " && value.split(\"@\").length === 2", ""],
    ["only a token's row carries a user", '(c.account !== "token" || !isAddress(c.user))', "!isAddress(c.user)"],
    ["idle data reads by its age", "return now < staleAfter ? CURRENT : OUT_OF_DATE;", "return CURRENT;"],
    ["a pair whose units are absent reads not set up", "return cloud.pairs.length > 0 ? withCause(", "return false ? withCause("],
    ["a connection needed or a failure wins over files to review", "if (danger.length > 0) return", "if (false) return"],
    ["another pair's failure wins over a running sync", "return cloud.state === state || cloud.pairs.some(function (p) { return p.state === state; });", "return cloud.state === state;"],
    ["a missing token reads as a connection", "if (error.kind === \"credential-absent\" && error.account === \"token\")", "if (false)"],
    ["the published error keeps its account", "return isText(error.account) ? { kind: error.kind, account: error.account } : { kind: error.kind };", "return { kind: error.kind };"],
    ["the published pair-list error keeps its detail", "if (error.kind === \"pairs-invalid\" && isText(error.detail)) return { kind: error.kind, detail: error.detail };\n    ", ""],
    ["an unreadable pair list offers its repair", "hint: pairListResetHint(cloud.lastError), action: true };", "hint: pairListResetHint(cloud.lastError) };"],
    ["an unreadable pair list shows its repair", "if (pairListValid(cloud)) return { hidden: true };", "return { hidden: true };"],
    ["an unreadable pair list says so on Settings", "if (!pairListValid(cloud)) return [UNREADABLE_ROW];", ""],
    ["an unreadable pair list keeps the bar", "(cloud.pairs.length === 0 && pairListValid(cloud))", "cloud.pairs.length === 0"],
    ["files to review win over the state", "if (cloud.conflictCount > 0) return {", "if (false) return {"],
    ["the bar reads the headline", "var head = headline(cloud, now);\n    return { hidden: false", "var head = stateView(cloud.state, cloud.staleAfter, now);\n    return { hidden: false"],
    ["the tooltip reads the headline", "var head = headline(cloud, now);\n    var lines = pairLines(cloud.pairs, now);", "var head = stateView(cloud.state, cloud.staleAfter, now);\n    var lines = pairLines(cloud.pairs, now);"],
    ["the window reads the headline", "var head = headline(cloud, now);\n    var lines = [{", "var head = stateView(cloud.state, cloud.staleAfter, now);\n    var lines = [{"],
    ["the Settings sync value reads the headline", "var head = headline(cloud, now);\n    var value = {", "var head = stateView(cloud.state, cloud.staleAfter, now);\n    var value = {"],
    ["Set up again for units absent beside a pair", "return units === \"stale\" || (units === \"absent\" && hasPairs);", "return units === \"stale\";"],
    ["no Set up again for units absent with no pair", "return units === \"stale\" || (units === \"absent\" && hasPairs);", "return units !== \"installed\";"],
    ["Sign in again for a refused sign-in", "if (signInRefused(record)) return { tone: \"danger\", text: \"Google did not accept", "if (false) return { tone: \"danger\", text: \"Google did not accept"],
    ["a locked keyring comes first", "if (states.indexOf(\"locked\") !== -1) return", "if (false) return"],
    ["a row's chip counts the files that need the user", "if (pair.needsYou > 0) return", "if (pair.review > 0) return"],
    ["a pair counts the files that need the user", "needsYou: own.filter(function (c) { return c.needs === \"you\"; }).length", "needsYou: own.length"],
    ["a row's label is cut to its ceiling", "label: cut(p.label, ROW_LABEL_MAX)", "label: p.label"],
    ["a row's folders are cut to their ceiling", "secondary: cut(pairFolders(p, home), ROW_TEXT_MAX)", "secondary: pairFolders(p, home)"],
    ["a folder under the home folder reads from ~", "pair.local.indexOf(home + \"/\") === 0", "pair.local.indexOf(home) === 0"],
    ["no home folder writes the whole path", "var local = home !== \"\" && (", "var local = ("],
    ["a line that states a limit has its info", "info: hasOwn(CONFLICT_INFO, variant) ? CONFLICT_INFO[variant] : \"\"", "info: \"\""],
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
    ["Pause needs a folder pair", "var pause = !hasPairs ||", "var pause = !known ||"],
    ["the footer offers Set up again as the schedule does", "var primary = known && setupOffered(cloud.units, hasPairs)", "var primary = false"],
    ["the window says a pause", "    if (cloud.paused)\n", "    if (false)\n"],
    ["the window names the first file to review", "if (cloud.conflicts.length > 0) lines.push({ text: \"First file to review: \"", "if (false) lines.push({ text: \"First file to review: \""],
    ["a file not copied carries its reason", " && (c.kind !== \"unreadable-on-drive\" || isText(c.reason))", ""],
    ["a file not copied with no copy here needs no local path", "(c.kind === \"unreadable-on-drive\" && !hasOwn(c, \"localPath\")) || ", ""],
    ["only a file not copied may lack its local path", "c.kind === \"unreadable-on-drive\" && !hasOwn(c, \"localPath\")", "!hasOwn(c, \"localPath\")"],
    ["a file not copied names its earlier copy's folder", "if (conflict.kind === \"unreadable-on-drive\" && conflict.localPath !== undefined) return dirname(conflict.localPath);", ""],
    ["a known reason reads in its own words", "return row === undefined ? REASON_DEFAULT : row.text;", "return REASON_DEFAULT;"],
    ["an unknown reason reads in the default words", "return row === undefined ? REASON_DEFAULT : row.text;", "return row === undefined ? reason : row.text;"],
    ["a pair with files to review does not read up to date", "if (pair.state === \"idle\" && pair.review > 0) return {", "if (false) return {"],
    ["a pair counts its own files", "return c.pair === p.id;", "return true;"],
    ["a paused pair reads its pause", "if (pair.state === \"idle\" && pair.review > 0) return {", "if (pair.review > 0) return {"],
    ["the pair lines read the pair's view", "return p.label + \": \" + pairView(p, now).text;", "return p.label + \": \" + stateView(p.state, p.staleAfter, now).text;"],
    ["a review group holds each pair's files", "if (group === undefined) {", "if (true) {"],
    ["a change on both sides names the kept copy's folder", "if (conflict.kind === \"both-changed\" && conflict.storedPath !== undefined) return dirname(conflict.storedPath);", ""],
    ["a row needs its needs mark", "\n        && NEEDS.indexOf(c.needs) !== -1", ""],
    ["only a doubled name carries mine", "(duplicate ? typeof c.mine === \"boolean\" : !hasOwn(c, \"mine\"))", "true"],
    ["an owner is a not-mine doubled name's address", "(!hasOwn(c, \"owner\") || (duplicate && c.mine === false && isAddress(c.owner)))", "true"],
    ["the earlier doubled-name kind is refused", "\"duplicate-different\"];\nvar DUPLICATE_KINDS", "\"duplicate-different\", \"duplicate-on-drive\"];\nvar DUPLICATE_KINDS"],
    ["the needs-you count is judged", "if (doc.needsYou !== doc.conflicts.filter(function (c) { return c.needs === \"you\"; }).length) return", "if (false) return"],
    ["the window's data carries the needs-you count", "needsYou: record.needsYou,", ""],
    ["rows that need the user come first", "needsFirst(record.conflicts).slice(0, CONFLICTS_MAX)", "record.conflicts.slice(0, CONFLICTS_MAX)"],
    ["the cap cuts after the sort", "needsFirst(record.conflicts).slice(0, CONFLICTS_MAX)", "needsFirst(record.conflicts.slice(0, CONFLICTS_MAX))"],
    ["a row carries the record's needs", "needs: c.needs, localAction:", "needs: \"you\", localAction:"],
    ["a fix in Google Drive has no local action", "if (LOCAL_ACTION_KINDS.indexOf(conflict.kind) === -1 || conflict.localPath === undefined) return [];", "if (conflict.localPath === undefined) return [];"],
    ["the local-action flag reads the folders", "localAction: dirs.length > 0", "localAction: true"],
    ["the window row carries the mark and the flag", "needs: conflict.needs, localAction: conflict.localAction }", "needs: \"you\", localAction: true }"],
    ["a doubled name the user owns says what they do", "if (DUPLICATE_KINDS.indexOf(conflict.kind) === -1 || conflict.mine) return conflict.kind;", "if (DUPLICATE_KINDS.indexOf(conflict.kind) === -1) return conflict.kind;"],
    ["a shared doubled name names who can fix it", "conflict.kind + (conflict.owner !== undefined ? \"-shared\" : \"-unowned\")", "conflict.kind + \"-unowned\""],
    ["a change on both sides says which copy is here", "return conflict.copyFolder !== undefined ? \"both-changed-kept\" : \"both-changed\";", "return \"both-changed-kept\";"],
    ["a rename names its new name", ".replace(\"{to}\", function () { return conflict.to; })", ""],
    ["the notification counts the rows that need the user", "needsLine(record.needsYou)", "needsLine(record.conflicts.length)"],
    ["a connection notifies first", "if (reasons.indexOf(\"authorization-required\") !== -1)\n", "if (false)\n"],
    ["no file to review draws no count", "cloud.conflictCount > 0 ? String(cloud.conflictCount) : \"\"", "String(cloud.conflictCount)"],
    ["no folder pair hides the icon", "if (cloud === undefined || cloud === null || (cloud.pairs.length === 0 && pairListValid(cloud))) return", "if (cloud === undefined || cloud === null) return"],
    ["the account key list is published", "values.keys = keyItems(presence);", "values.keys = [];"]
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
