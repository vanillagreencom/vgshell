#!/usr/bin/env node
// vgs.google-drive's pure decisions, shell/plugins/vgs.google-drive/
// GoogleDriveLogic.js: the judge of the runner's status record and probe
// answer, the headline, the status values the service publishes, what the
// bar widget, its tooltip and its popover draw, the notification, and when
// idle data turns old. One table holds a row per state of the sync and
// pins the headline's words and tone; every surface (the bar's tone, icon
// and count, the tooltip's title, the popover's header and the Settings
// `sync` value) must read that one headline. The words are pinned because
// the issues (VGS-1314, VGS-1729) make them the contract of the four
// surfaces. The Settings and Setup values (VGS-1744) are held by their
// tones, actions and structure, never their words. A review row is held by
// its structured fields alone (VGS-1727): its needs mark, its local-action
// flag, its action, and which case of its kind its line takes, never its
// words. The popover (VGS-1745) is held by its structure: its header's
// parts, which problem callout shows and where its fix goes, whether its
// body speaks, the rows in Needs you and in the folded notes with the
// counts, and when its footer shows and lets Sync now start. The tooltip,
// the Details lines and the popover's header never carry a file name, and
// the Google account a sign-in stored reaches the account value alone.
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

// The bar's tone and the popover header's Badge tone for each headline
// tone, stated here apart from the logic.
const BAR = { ok: "calm", info: "calm", warning: "warning", danger: "danger" };
const BADGE = { ok: "success", info: "info", warning: "warning", danger: "danger" };

// The sentences that send the user to the Setup tab's sign-in step, read
// from the logic: their words are not this suite's to pin.
const SETUP_LINK = "](page:vgs.google-drive/Setup)";
const INVALID = "The folder pair list is not valid, so VGS copies nothing.";
const signedOut = { kind: "credential-absent", account: "token" };
// The pair list the runner could not read: it reads no pair and refuses
// every pair change (bin/google-drive readPairs).
const invalid = detail => record({ state: "error", lastError: { kind: "pairs-invalid", detail: detail || "pair=docs rule=repository-inside" }, pairs: [], conflicts: [], attention: { reasons: ["error"], key: "k", notified: false } });

// The popover's footer: shown, and whether Sync now can start.
const SYNC = { shown: true, sync: true };
const HELD = { shown: true, sync: false };
const NO_FOOT = { shown: false };
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

// The Details hint of a headline that counts the files that need the
// user: it says where to see them.
const NEEDS_SEEN = { needs: true };

// One row per state of the sync: the record, then the headline's text,
// tone and icon every surface must show, the popover's footer, the
// Details hint, and whether the bar hides its icon.
const STATES = [
    ["first run", { state: "not-set-up", units: "absent", lastSuccess: null, staleAfter: null, lastError: null, pairs: [], conflicts: [], attention: null }, "No folder pairs", "warning", "cloud", NO_FOOT, undefined, true],
    ["a folder pair whose hourly sync did not install", well({ state: "not-set-up", units: "absent" }), "Not set up", "warning", "cloud", NO_FOOT, SETUP_AGAIN],
    ["no keys", well({ state: "authorization-required", pairs: [Object.assign({}, DOCS, { state: "authorization-required", lastError: { kind: "credential-absent", account: "client-id" } })], lastError: { kind: "credential-absent", account: "client-id", pair: "docs" } }), "Sign-in needed", "danger", "cloud-alert", NO_FOOT, LINKED],
    ["no folder pair", { state: "not-set-up", units: "installed", lastSuccess: null, staleAfter: null, lastError: null, pairs: [], conflicts: [], attention: null }, "No folder pairs", "warning", "cloud", NO_FOOT, undefined, true],
    ["pair list not readable", invalid(), "Sync failed", "danger", "cloud-alert", NO_FOOT, INVALID, false],
    ["signed out", well({ state: "authorization-required", pairs: [Object.assign({}, DOCS, { state: "authorization-required", lastError: signedOut })], lastError: Object.assign({ pair: "docs" }, signedOut) }), "Sign-in needed", "danger", "cloud-alert", NO_FOOT, { error: signedOut }],
    ["syncing while another pair needs a sign-in", record({ state: "running", pairs: [Object.assign({}, DOCS, { state: "running" }), INBOX], conflicts: [] }), "Sign-in needed", "danger", "cloud-alert", HELD, LINKED],
    ["syncing while another pair failed", well({ state: "running", pairs: [Object.assign({}, DOCS, { state: "running" }), Object.assign({}, INBOX, { state: "error", lastError: { kind: "source-missing" } })], lastError: { kind: "source-missing", pair: "inbox" }, conflicts: CONFLICTS.slice(0, 1) }), "Sync failed", "danger", "cloud-alert", HELD, "A Google Drive folder of a folder pair does not exist."],
    ["empty review", well(), "Up to date", "ok", "cloud-check", SYNC, undefined],
    ["data old", well({ staleAfter: iso(NOW) }), "Out of date", "warning", "cloud-alert", SYNC, undefined],
    ["never synced", well({ lastSuccess: null, staleAfter: null }), "Not synced yet", "info", "cloud", SYNC, undefined],
    ["syncing", well({ state: "running", pairs: [Object.assign({}, DOCS, { state: "running" })] }), "Syncing", "info", "cloud-sync", HELD, undefined],
    ["paused", well({ state: "paused", paused: true, pairs: [PAUSED_DOCS] }), "Paused", "info", "cloud-off", HELD, undefined],
    ["every pair paused on its own", well({ state: "paused", pairs: [PAUSED_DOCS] }), "Paused", "info", "cloud-off", NO_FOOT, undefined],
    ["error", well({ state: "error", lastError: { kind: "source-missing", pair: "docs" } }), "Sync failed", "danger", "cloud-alert", SYNC, "A Google Drive folder of a folder pair does not exist."],
    ["offline", well({ state: "offline", lastError: { kind: "offline", pair: "docs" } }), "Offline", "warning", "cloud-off", SYNC, "Google Drive cannot be reached. VGS tries again at the next sync."],
    ["keyring locked", well({ state: "authorization-required", pairs: [Object.assign({}, DOCS, { state: "authorization-required", lastError: { kind: "credential-locked", account: "client-id" } })], lastError: { kind: "credential-locked", account: "client-id", pair: "docs" } }), "Sign-in needed", "danger", "cloud-alert", SYNC, "Your keyring is locked. Unlock it to sync."],
    ["sign-in needed", record({ conflicts: [] }), "Sign-in needed", "danger", "cloud-alert", SYNC, LINKED],
    ["a file that needs you and a note", well({ conflicts: CONFLICTS.slice(0, 2) }), "1 file needs you", "warning", "cloud-alert", SYNC, NEEDS_SEEN],
    ["two files that need you", well({ conflicts: [CONFLICTS[0], DRIVE_CONFLICTS[2]] }), "2 files need you", "warning", "cloud-alert", SYNC, NEEDS_SEEN],
    ["a note alone", well({ conflicts: CONFLICTS.slice(1, 2) }), "Up to date", "ok", "cloud-check", SYNC, undefined],
    ["a file that needs you while paused", well({ state: "paused", paused: true, pairs: [PAUSED_DOCS], conflicts: CONFLICTS.slice(0, 2) }), "1 file needs you", "warning", "cloud-alert", HELD, NEEDS_SEEN],
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
    for (const [label, rec, text, tone, icon, footer, hint, hidden] of STATES) {
        const cloud = L.cloudValue(rec, "");
        const head = L.headline(cloud, NOW);
        same([head.text, head.tone, head.icon], [text, tone, icon], label + ": headline");
        const sync = L.statusValues(rec, null, "", "", NOW, HOME).sync;
        same([sync.text, sync.tone], [text, tone], label + ": the Details sync value");
        if (hint === LINKED) assert.ok(typeof sync.hint === "string" && sync.hint.includes(SETUP_LINK), label + ": the Details hint links the Setup tab: " + sync.hint);
        else if (hint !== undefined && hint.error !== undefined) same(sync.hint, L.errorText(hint.error), label + ": the Details hint is the sentence of the record's own error");
        else if (hint === SETUP_AGAIN) same(sync.hint, L.scheduleValue(rec.units, true).hint, label + ": the Details hint says what Hourly sync says");
        else if (hint === NEEDS_SEEN) assert.ok(typeof sync.hint === "string" && sync.hint !== "" && !sync.hint.includes("](page:"), label + ": the Details hint says where to see the files");
        else assert.equal(sync.hint, hint, label + ": the Details hint");
        const header = L.panelHeader(cloud, NOW, Timestamp.text);
        same([header.headline, header.tone, header.icon], [text, BADGE[tone], icon], label + ": the popover header");
        const foot = L.footerView(cloud);
        same(foot.shown ? { shown: true, sync: foot.sync.reason === "" } : { shown: false }, footer, label + ": the popover footer");
        const tip = L.widgetTooltip(cloud, NOW, Timestamp.text);
        assert.equal(tip.title, "Google Drive: " + text, label + ": the tooltip title");
        const bar = L.widgetView(cloud, NOW);
        if (hidden === true) {
            assert.equal(bar.hidden, true, label + ": no folder pair hides the icon");
            continue;
        }
        const needing = rec.conflicts.filter(c => c.needs === "you").length;
        same([bar.hidden, bar.tone, bar.icon, bar.badge], [false, BAR[tone], icon, needing > 0 ? String(needing) : ""], label + ": the bar counts only the files that need the user");
        assert.equal(bar.spinning, rec.state === "running", label + ": the spinner");
    }

    // One pair with one file that needs the user and two notes: every
    // surface counts the one file in the same words, and no surface
    // counts the notes (VGS-1745, the overseer's reading of VGS-1744).
    const oneTwo = well({ conflicts: [CONFLICTS[0], CONFLICTS[1], CONFLICTS[3]] });
    const oneTwoCloud = L.cloudValue(oneTwo, "");
    const oneTwoValues = L.statusValues(oneTwo, null, "", "", NOW, HOME);
    const chip = oneTwoValues.pairs[0].state, head = L.headline(oneTwoCloud, NOW);
    const detailsLine = oneTwoValues.sync.lines[0].slice("Documents: ".length);
    const tipLine = L.widgetTooltip(oneTwoCloud, NOW, Timestamp.text).details.split("\n")[0].slice("Documents: ".length);
    same([chip.tone, L.widgetView(oneTwoCloud, NOW).badge, L.reviewView(oneTwoCloud).needs.length], ["warning", "1", 1], "the chip warns and the bar and Needs you count one");
    assert.ok(head.text.startsWith("1 "), "the headline counts one: " + head.text);
    same([chip.text, detailsLine, tipLine], [head.text, head.text, head.text], "Settings, Details and the tooltip read the headline's words");
    assert.ok(L.reviewView(oneTwoCloud).notesLine.startsWith("2 "), "the two notes fold apart");
    // No surface calls a row "to review": a row needs the user or is a
    // note. The record of every state in the table, and the two-note one.
    for (const rec of STATES.map(row => row[1]).concat([oneTwo])) {
        const c = L.cloudValue(rec, "");
        const shown = JSON.stringify([L.statusValues(rec, null, "", "", NOW, HOME), L.widgetTooltip(c, NOW, Timestamp.text), L.panelHeader(c, NOW, Timestamp.text),
            L.problemCallout(c, NOW), L.panelBody(c, NOW), L.reviewView(c), L.notification(rec)]);
        assert.ok(!/to review/i.test(shown), "a surface says to review: " + shown);
    }

    // The published values of the record and the probe.
    const presence = L.parseProbe(JSON.stringify(probe())).presence;
    const values = L.statusValues(good.record, presence, "", "", NOW, HOME);
    same(Object.keys(values).sort(), ["account", "cloud", "cloudKeys", "connection", "firstPair", "keys", "lastSync", "pairList", "pairs", "schedule", "sync"]);
    same(values.sync.lines, ["Documents: 1 file needs you", "Agent uploads: Sign-in needed"], "a line per pair, each by its own state and the files that need the user");
    const lines = rec => L.statusValues(rec, null, "", "", NOW, HOME).sync.lines;
    same(lines(well({ conflicts: CONFLICTS.slice(1, 2) })), ["Documents: Up to date"], "a note leaves its pair up to date");
    same(lines(well({ state: "paused", paused: true, pairs: [PAUSED_DOCS], conflicts: CONFLICTS.slice(0, 1) })), ["Documents: Paused"], "a paused pair reads its pause before its files");
    same(lines(well({ conflicts: [Object.assign({}, CONFLICTS[0], { pair: "inbox", pairLabel: "Agent uploads" })] })), ["Documents: Up to date"], "another pair's file is not this pair's");
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

    // The popover's data: times as milliseconds, each conflict with its
    // local-action flag and the folder of a kept copy, the list capped
    // under the ceiling.
    const cloud = values.cloud;
    same(cloud.conflicts.map(c => [c.localAction, c.copyFolder === undefined ? null : c.copyFolder]), [
        [true, "/home/me/.local/state/vgshell/google-drive/pairs/docs/conflicts/20261010T110000Z-7/taxes"],
        [true, null],
        [true, null],
        [true, null]
    ]);
    assert.equal(cloud.conflicts[2].to, RENAMED_TO);
    const many = record({ conflicts: Array.from({ length: 500 }, (_, i) => Object.assign({}, CONFLICTS[1], { path: "f" + i + ".txt", localPath: "/home/me/gdrive/" + "x".repeat(3000) + "/f" + i + ".txt" })) });
    const capped = L.cloudValue(many, "");
    assert.equal(capped.conflictCount, 500);
    assert.ok(capped.conflicts.length > 0 && capped.conflicts.length <= L.CONFLICTS_MAX);
    assert.ok(JSON.stringify(capped).length <= L.CLOUD_BYTES_MAX, "the data stays under its ceiling");

    // Writes: a key the next values lack is cleared with null.
    same(L.changedKeys({ sync: 1, lastSync: 5 }, { sync: 1 }), ["lastSync"]);
    same(L.changedKeys({ lastSync: null }, { lastSync: null }), []);

    // The tooltip: pairs and states, never a file name; the count of files
    // to review when the headline does not say it.
    const tip = L.widgetTooltip(cloud, NOW, Timestamp.text);
    same(tip.details.split("\n"), ["Documents: 1 file needs you", "Agent uploads: Sign-in needed", "1 file needs you", "Last sync " + Timestamp.text(NOW - HOUR, NOW)]);
    same(L.widgetTooltip(L.cloudValue(well({ conflicts: CONFLICTS.slice(0, 2) }), ""), NOW, Timestamp.text).details.split("\n"), ["Documents: 1 file needs you", "Last sync " + Timestamp.text(NOW - HOUR, NOW)], "the headline says the count once");
    same(L.widgetTooltip(L.cloudValue(well({ conflicts: CONFLICTS.slice(1, 2) }), ""), NOW, Timestamp.text).details.split("\n"), ["Documents: Up to date", "Last sync " + Timestamp.text(NOW - HOUR, NOW)], "a note adds no count");
    same(L.widgetTooltip(undefined, NOW, Timestamp.text), { title: "Google Drive", details: "" });
    for (const text of [tip.title, tip.details].concat(values.sync.lines))
        for (const c of CONFLICTS) assert.ok(!text.includes(c.path) && !text.includes(c.localPath), "a file name shows: " + text);

    // The popover's header: the headline, then the last complete sync in
    // the shell's wording and, unless the sync stopped, the count of folder
    // pairs, as one line of parts. It names no file.
    const metaParts = rec => L.panelHeader(L.cloudValue(rec, ""), NOW, Timestamp.text).meta.split(" · ");
    const SYNCED = Timestamp.text(NOW - HOUR, NOW);
    for (const [label, rec, count] of [
        ["up to date, one pair", well(), 1],
        ["a file that needs you, two pairs", well({ pairs: [DOCS, Object.assign({}, INBOX, { state: "idle", lastError: null })], conflicts: CONFLICTS.slice(0, 1) }), 2],
        ["sign-in needed", record(), null],
        ["sync failed", well({ state: "error", lastError: { kind: "source-missing", pair: "docs" } }), null]
    ]) {
        const parts = metaParts(rec);
        assert.ok(parts[0].endsWith(SYNCED), label + ": the header says when the sync last ran: " + parts[0]);
        same(parts.length, count === null ? 1 : 2, label + ": the header counts the folder pairs unless the sync stopped");
        if (count !== null) assert.ok(parts[1].startsWith(count + " "), label + ": the pair count: " + parts[1]);
    }
    same(metaParts(well({ lastSuccess: null, staleAfter: null })).length, 2, "a pair never synced still counts");
    assert.notEqual(metaParts(well({ lastSuccess: null, staleAfter: null }))[0], metaParts(well())[0], "no complete sync says so");
    for (const rec of [record(), well({ conflicts: CONFLICTS.concat(DRIVE_CONFLICTS) })]) {
        const header = JSON.stringify(L.panelHeader(L.cloudValue(rec, ""), NOW, Timestamp.text));
        for (const c of rec.conflicts) assert.ok(!header.includes(c.path) && !header.includes(c.localPath), "the header names a file: " + header);
    }

    // The problem callout: which shows, its tone, and where its one fix
    // goes, a TUI the manifest declares or a tab of the plugin's page.
    const driveManifest = JSON.parse(fs.readFileSync(MANIFEST, "utf8"));
    const callout = rec => {
        const c = L.problemCallout(L.cloudValue(rec, ""), NOW);
        if (c === null) return null;
        assert.ok(c.title !== "" && c.text !== "" && !c.text.includes("](") && !c.title.includes("]("), "a callout's words are plain text: " + JSON.stringify(c));
        if (c.action !== null && c.action.tui !== undefined) assert.ok(Object.prototype.hasOwnProperty.call(driveManifest.tui, c.action.tui), "the manifest declares " + c.action.tui);
        if (c.action !== null && c.action.tab !== undefined) assert.ok(["Settings", "Setup", "Details"].includes(c.action.tab), "a tab of the page: " + c.action.tab);
        return [c.tone, c.action === null ? null : c.action.tui !== undefined ? "tui:" + c.action.tui : "tab:" + c.action.tab];
    };
    const STATE_OF = (state, error) => well({ state, pairs: [Object.assign({}, DOCS, { state, lastError: error })], lastError: Object.assign({ pair: "docs" }, error) });
    const SIGNED_OUT = STATE_OF("authorization-required", signedOut);
    const REFUSED = STATE_OF("authorization-required", { kind: "authorization-refused" });
    const CALLOUT_ROWS = [
        ["up to date", well(), null],
        ["a file that needs you", well({ conflicts: CONFLICTS.slice(0, 1) }), null],
        ["paused", well({ state: "paused", paused: true, pairs: [PAUSED_DOCS] }), null],
        ["signed out", SIGNED_OUT, ["danger", "tui:connect"]],
        ["a sign-in Google refused", REFUSED, ["danger", "tui:connect"]],
        ["no keys", STATE_OF("authorization-required", { kind: "credential-absent", account: "client-id" }), ["danger", "tab:Setup"]],
        ["keyring locked", STATE_OF("authorization-required", { kind: "credential-locked", account: "client-id" }), ["danger", null]],
        ["a running pair beside a pair with no keys", well({ state: "running", pairs: [Object.assign({}, DOCS, { state: "running" }), Object.assign({}, INBOX, { lastError: { kind: "credential-absent", account: "client-id" } })], lastError: null }), ["danger", "tab:Setup"]],
        ["a Drive folder gone", STATE_OF("error", { kind: "source-missing" }), ["danger", "tab:Settings"]],
        ["rclone missing", STATE_OF("error", { kind: "rclone-missing" }), ["danger", "tab:Setup"]],
        ["an interrupted sync", STATE_OF("error", { kind: "interrupted" }), ["danger", null]],
        ["a pair list that cannot be read", invalid(), ["danger", "tui:reset-pairs"]],
        ["offline", STATE_OF("offline", { kind: "offline" }), ["warning", null]],
        ["offline with a file that needs you", Object.assign(STATE_OF("offline", { kind: "offline" }), { conflicts: CONFLICTS.slice(0, 1), needsYou: 1 }), ["warning", null]],
        ["a folder pair whose hourly sync did not install", well({ state: "not-set-up", units: "absent" }), ["warning", "tab:Details"]],
        ["an hourly sync out of date", well({ units: "stale" }), ["warning", "tab:Details"]]
    ];
    for (const [label, rec, want] of CALLOUT_ROWS) same(callout(rec), want, "callout: " + label);
    const titleOf = rec => L.problemCallout(L.cloudValue(rec, ""), NOW).title;
    assert.notEqual(titleOf(SIGNED_OUT), titleOf(REFUSED), "a sign-in never made reads apart from one Google refused");

    // The body: a pause always, else what the state means while nothing is
    // to review and nothing is wrong.
    const body = rec => L.panelBody(L.cloudValue(rec, ""), NOW);
    for (const [label, rec, speaks] of [
        ["up to date", well(), true],
        ["out of date", well({ staleAfter: iso(NOW) }), true],
        ["never synced", well({ lastSuccess: null, staleAfter: null }), true],
        ["paused", well({ state: "paused", paused: true, pairs: [PAUSED_DOCS] }), true],
        ["a file that needs you while paused", well({ state: "paused", paused: true, pairs: [PAUSED_DOCS], conflicts: CONFLICTS.slice(0, 1) }), true],
        ["a note alone", well({ conflicts: CONFLICTS.slice(1, 2) }), false],
        ["a file that needs you", well({ conflicts: CONFLICTS.slice(0, 1) }), false],
        ["syncing", well({ state: "running", pairs: [Object.assign({}, DOCS, { state: "running" })] }), false],
        ["sync failed", STATE_OF("error", { kind: "source-missing" }), false],
        ["an hourly sync out of date", well({ units: "stale" }), false]
    ]) assert.equal(body(rec) !== "", speaks, "body: " + label + ": " + JSON.stringify(body(rec)));
    assert.notEqual(body(well()), body(well({ pairs: [DOCS, Object.assign({}, INBOX, { state: "idle", lastError: null })] })), "up to date counts the folder pairs");
    assert.notEqual(body(well({ state: "paused", paused: true, pairs: [PAUSED_DOCS] })), body(well({ state: "paused", paused: true, pairs: [PAUSED_DOCS], conflicts: CONFLICTS.slice(0, 1) })), "a pause under another headline names itself");

    // The footer: shown only while a sync can run, Pause or Resume, and
    // Sync now with the reason it cannot start now.
    const footer = rec => {
        const f = L.footerView(rec === undefined ? undefined : L.cloudValue(rec, ""));
        return f.shown ? [f.pause.action, f.sync.action, f.sync.reason !== ""] : null;
    };
    const FOOTERS = [
        ["before the first value", undefined, null],
        ["first run", well({ state: "not-set-up", units: "absent", pairs: [] }), null],
        ["a folder pair whose units did not install", well({ state: "not-set-up", units: "absent" }), null],
        ["no folder pair", well({ state: "not-set-up", pairs: [] }), null],
        ["a pair list that cannot be read", invalid(), null],
        ["signed out", SIGNED_OUT, null],
        ["set up", well(), ["pause", "sync", false]],
        ["units out of date", well({ units: "stale" }), ["pause", "sync", false]],
        ["syncing", well({ state: "running", pairs: [Object.assign({}, DOCS, { state: "running" })] }), ["pause", "sync", true]],
        ["paused", well({ state: "paused", paused: true, pairs: [PAUSED_DOCS] }), ["resume", "sync", true]],
        ["every pair paused on its own", well({ state: "paused", pairs: [PAUSED_DOCS] }), null],
        ["keyring locked", STATE_OF("authorization-required", { kind: "credential-locked", account: "client-id" }), ["pause", "sync", false]]
    ];
    for (const [label, rec, want] of FOOTERS) same(footer(rec), want, "footer: " + label);
    assert.notEqual(L.footerView(L.cloudValue(well({ state: "paused", paused: true, pairs: [PAUSED_DOCS] }), "")).sync.reason,
        L.footerView(L.cloudValue(well({ state: "running", pairs: [Object.assign({}, DOCS, { state: "running" })] }), "")).sync.reason, "a pause and a running sync each give their own reason");

    // Each review row by its fields: its needs mark and local-action flag
    // as the record and its kind give them, its name and place, and its
    // action: Show older copy only on a row that needs the user and whose
    // copy VGS kept here.
    const KEPT = "/home/me/.local/state/vgshell/google-drive/pairs/docs/conflicts/20261010T110000Z-7/taxes";
    const UNKNOWN_REASON = Object.assign({}, DRIVE_CONFLICTS[0], { path: "reports/Held.pdf", reason: "failed to open source object: stand-in cause", needs: "you" });
    const ROWS = [
        // label, record row, needs, local action, the action's folder or null
        ["a change on both sides with the copy that was here kept", CONFLICTS[0], "you", true, KEPT],
        ["a change on both sides uploaded from here", Object.assign({}, CONFLICTS[0], { storedPath: undefined }), "you", true, null],
        ["a kept copy on a row that needs nothing", Object.assign({}, CONFLICTS[0], { needs: "nothing" }), "nothing", true, null],
        ["a Drive deletion put back", CONFLICTS[1], "nothing", true, null],
        ["a Drive rename", CONFLICTS[2], "nothing", true, null],
        ["a local deletion put back", CONFLICTS[3], "nothing", true, null],
        ["a dangling shortcut never copied", DRIVE_CONFLICTS[0], "nothing", false, null],
        ["a dangling shortcut with an earlier copy here", DRIVE_CONFLICTS[1], "nothing", false, null],
        ["a file not copied for another reason", UNKNOWN_REASON, "you", false, null],
        ["identical copies, the user's", doubled("a.pdf", true, true), "nothing", false, null],
        ["different copies, the user's", doubled("b.pdf", false, true), "you", false, null],
        ["identical copies shared by an owner", doubled("c.pdf", true, false, OWNER), "nothing", false, null],
        ["different copies shared by an owner", doubled("d.pdf", false, false, OWNER), "nothing", false, null],
        ["identical copies, no owner named", doubled("e.pdf", true, false), "nothing", false, null],
        ["different copies, no owner named", doubled("f.pdf", false, false), "nothing", false, null]
    ];
    const rowOf = c => {
        const judgedRow = L.parseStatus(JSON.stringify(well({ conflicts: [c] })));
        assert.equal(judgedRow.ok, true, c.path + ": " + judgedRow.error);
        const published = L.cloudValue(judgedRow.record, "").conflicts[0];
        return [published, L.conflictRow(published)];
    };
    const details = {}, needsMarks = new Set(), noteMarks = new Set();
    for (const [label, c, needs, local, folder] of ROWS) {
        const [published, row] = rowOf(c);
        same([published.needs, published.localAction], [needs, local], label + ": the published row");
        same([row.needs, row.action === null ? null : row.action.folder], [needs, folder], label + ": the popover row");
        (needs === "you" ? needsMarks : noteMarks).add(row.icon);
        // Only the line that states how long VGS keeps a copy has the info
        // that says why.
        assert.equal(row.info !== "", c.kind === "both-changed" && c.storedPath !== undefined, label + ": the limit's info");
        const at = c.path.lastIndexOf("/");
        assert.equal(row.name, c.path.slice(at + 1), label + ": the row names its file");
        assert.ok(row.place.startsWith(c.pairLabel) && (at <= 0 || c.path.slice(0, at).split("/").every(part => row.place.includes(part))), label + ": the row names its pair and folders: " + row.place);
        assert.ok(typeof row.detail === "string" && row.detail !== "", label + ": the row has its line");
        details[label] = row.detail;
    }
    assert.equal(needsMarks.size, 1, "every row that needs the user takes one mark");
    assert.ok(![...noteMarks].some(m => needsMarks.has(m)), "no note takes the mark of a row that needs the user");
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
    // The needs-you count the record publishes reaches the popover's data.
    const drivenRecord = L.parseStatus(JSON.stringify(well({ conflicts: CONFLICTS.concat(DRIVE_CONFLICTS) })));
    assert.equal(drivenRecord.ok, true, drivenRecord.error);
    assert.equal(L.cloudValue(drivenRecord.record, "").needsYou, 2, "one change on both sides and one doubled name of the user's");
    // A file not copied reads by rclone's reason, never in rclone's words.
    const driveSide = L.parseStatus(JSON.stringify(well({ conflicts: DRIVE_CONFLICTS })));
    assert.equal(driveSide.ok, true, driveSide.error);
    const driveCloud = L.cloudValue(driveSide.record, "");
    same(L.headline(driveCloud, NOW).text, "1 file needs you");
    const unknown = L.cloudValue(well({ conflicts: [UNKNOWN_REASON] }), "");
    for (const value of [driveCloud, unknown]) assert.ok(!JSON.stringify(value).includes("failed to open source object"), "rclone's text is published");
    // Rows that need the user come first, in the list and in Needs you,
    // and the cap cuts notes before them.
    same(driveCloud.conflicts.map(c => c.needs), ["you", "nothing", "nothing"], "the user's doubled name comes first");
    const INBOX_NOTE = Object.assign({}, CONFLICTS[2], { path: "note.txt" });
    const mixed = L.cloudValue(well({ conflicts: [INBOX_NOTE, CONFLICTS[1], DRIVE_CONFLICTS[0], CONFLICTS[0], CONFLICTS[3], DRIVE_CONFLICTS[2]] }), "");
    same(mixed.conflicts.map(c => c.path), [CONFLICTS[0].path, DRIVE_CONFLICTS[2].path, INBOX_NOTE.path, CONFLICTS[1].path, DRIVE_CONFLICTS[0].path, CONFLICTS[3].path], "needs-you first, each part in the record's order");
    const mixedView = L.reviewView(mixed);
    same([mixedView.needs.map(r => r.name), mixedView.notes.map(r => r.name)], [["2025.xlsx", "Twice listed.txt"], ["note.txt", "old.txt", "Plan – first draft.pdf", "receipts.pdf"]], "Needs you holds the rows that need the user, the notes the rest");
    assert.ok(mixedView.notesLine.startsWith("4 "), "the fold line counts the notes: " + mixedView.notesLine);
    same([mixedView.moreNeeds, mixedView.moreNotes], ["", ""], "a whole list counts no rest");
    // One file that needs the user and eight notes: Needs you lists it,
    // the eight fold into one line, and the bar counts one.
    const eight = Array.from({ length: 8 }, (_, i) => Object.assign({}, CONFLICTS[1], { path: "kept/n" + i + ".txt" }));
    const oneAndEight = L.cloudValue(well({ conflicts: eight.concat([CONFLICTS[0]]) }), "");
    const oneAndEightView = L.reviewView(oneAndEight);
    same([oneAndEightView.needs.length, oneAndEightView.notes.length, L.widgetView(oneAndEight, NOW).badge], [1, 8, "1"]);
    assert.ok(oneAndEightView.notesLine.startsWith("8 "), "the fold line counts eight notes: " + oneAndEightView.notesLine);
    same(L.reviewView(L.cloudValue(well({ conflicts: CONFLICTS.slice(0, 1) }), "")).notesLine, "", "no note, no fold line");
    const notes = Array.from({ length: L.CONFLICTS_MAX + 5 }, (_, i) => Object.assign({}, CONFLICTS[1], { path: "n" + i + ".txt" }));
    const overCap = L.cloudValue(well({ conflicts: notes.concat([CONFLICTS[0]]) }), "");
    assert.equal(overCap.conflicts.length, L.CONFLICTS_MAX);
    same([overCap.conflicts[0].path, overCap.conflicts[0].needs], [CONFLICTS[0].path, "you"], "the cap keeps the row that needs the user");
    const overCapView = L.reviewView(overCap);
    assert.ok(overCapView.notesLine.startsWith((L.CONFLICTS_MAX + 5) + " "), "the fold line counts every note the record holds: " + overCapView.notesLine);
    assert.ok(overCapView.moreNotes.startsWith((L.CONFLICTS_MAX + 5 - (L.CONFLICTS_MAX - 1)) + " "), "the notes the list leaves out are counted: " + overCapView.moreNotes);
    same(overCapView.moreNeeds, "");
    const manyNeeds = L.cloudValue(well({ conflicts: Array.from({ length: L.CONFLICTS_MAX + 2 }, (_, i) => Object.assign({}, CONFLICTS[0], { path: "y" + i + ".txt" })) }), "");
    assert.ok(L.reviewView(manyNeeds).moreNeeds.startsWith("2 "), "the files that need the user the list leaves out are counted");
    // A row carries its path, so long paths fill the ceiling first.
    const heavy = record({ conflicts: Array.from({ length: 500 }, (_, i) => Object.assign({}, CONFLICTS[1], { path: "x".repeat(3000) + "/f" + i + ".txt", localPath: "/home/me/gdrive/" + "x".repeat(3000) + "/f" + i + ".txt" })).concat([CONFLICTS[0]]) });
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
    ["files that need the user win over the state", "if (cloud.needsYou > 0) return {", "if (false) return {"],
    ["a note never raises the headline", "if (cloud.needsYou > 0) return {", "if (cloud.conflictCount > 0) return {"],
    ["the bar reads the headline", "var head = headline(cloud, now);\n    return { hidden: false", "var head = stateView(cloud.state, cloud.staleAfter, now);\n    return { hidden: false"],
    ["the tooltip reads the headline", "var head = headline(cloud, now);\n    var lines = pairLines(cloud.pairs, now);", "var head = stateView(cloud.state, cloud.staleAfter, now);\n    var lines = pairLines(cloud.pairs, now);"],
    ["the popover header reads the headline", "var head = headline(cloud, now);\n    var stopped", "var head = withCause(stateView(cloud.state, cloud.staleAfter, now), cloud.state);\n    var stopped"],
    ["the header says when the sync stopped", "if (!stopped && cloud.pairs.length > 0) meta +=", "if (cloud.pairs.length > 0) meta +="],
    ["a refused sign-in offers Sign in again", "    return CALLOUTS[\"sign-in-refused\"];\n}", "    return null;\n}"],
    ["a missing token is no missing key", "CALLOUTS[error.account === \"token\" ? \"signed-out\" : \"keys-missing\"]", "CALLOUTS[\"keys-missing\"]"],
    ["a locked keyring offers no sign-in", "if (error !== null && error.kind === \"credential-locked\") return CALLOUTS[\"keyring-locked\"];", ""],
    ["a callout reads the pair in the headline's state", "return pair === undefined ? cloud.lastError : pair.lastError;", "return cloud.lastError;"],
    ["an offline sync says so", "if (cloud.state === \"offline\") return CALLOUTS.offline;", ""],
    ["a failed sync names its fix", "action: hasOwn(FAILED_ACTIONS, kind) ? FAILED_ACTIONS[kind] : null };", "action: null };"],
    ["out-of-date units offer their fix", "if (cloud.units === \"stale\") return CALLOUTS.stale;", ""],
    ["absent units offer their fix", "if (head.cause === \"not-set-up\") return CALLOUTS[\"not-set-up\"];", ""],
    ["an unreadable pair list offers its repair in the popover", "action: { label: \"Start the list again\", tui: \"reset-pairs\" } };", "action: null };"],
    ["the popover says a pause", "if (cloud.paused) return (head.cause", "if (false) return (head.cause"],
    ["a note hides the up-to-date sentence", "if (cloud.conflictCount > 0 || problemCallout(", "if (problemCallout("],
    ["up to date counts the folder pairs", "return (n === 1 ? \"Your folder pair matches Google Drive.\" : \"Your \" + n + \" folder pairs match Google Drive.\")", "return \"Your folder pairs match Google Drive.\""],
    ["no surface calls a note to review", "notes\") + \" · nothing was lost\"", "notes\") + \" to review\""],
    ["the fold line counts the record's notes", "var noteCount = cloud.conflictCount - cloud.needsYou;", "var noteCount = notes.length;"],
    ["the notes the list leaves out are counted", "notesRest = noteCount - notes.length;", "notesRest = 0;"],
    ["Needs you holds only the rows that need the user", "var needs = rows.filter(function (r) { return r.needs === \"you\"; });", "var needs = rows;"],
    ["Show older copy only on a row that needs the user", "var action = needs && conflict.localAction && conflict.copyFolder !== undefined", "var action = conflict.copyFolder !== undefined"],
    ["a row names its pair and folders", "return [conflict.pairLabel].concat(at <= 0 ? [] : conflict.path.slice(0, at).split(\"/\")).join(PLACE_MARK);", "return conflict.pairLabel;"],
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
    ["the tooltip names pairs, not files", "var lines = pairLines(cloud.pairs, now);\n    if (cloud.needsYou > 0 && head.cause", "var lines = pairLines(cloud.pairs, now).concat(cloud.conflicts.map(function (c) { return c.path; }));\n    if (cloud.needsYou > 0 && head.cause"],
    ["Sync now waits for a key or a connection", "return pair.state !== \"authorization-required\" ||", "return true ||"],
    ["Sync now retries a locked keyring", " || (pair.lastError !== null && pair.lastError.kind === \"credential-locked\");", ";"],
    ["Sync now waits for a running sync", "cloud.state === \"running\" ? SYNC_REASONS.running", "false ? SYNC_REASONS.running"],
    ["Sync now waits for a pause", "reason: cloud.paused ? SYNC_REASONS.paused", "reason: false ? SYNC_REASONS.paused"],
    ["the footer offers Resume while paused", "pause: cloud.paused ? { text: \"Resume\"", "pause: false ? { text: \"Resume\""],
    ["a paused sync keeps its footer", "(cloud.paused || cloud.pairs.some(pairCanSync))", "(cloud.pairs.some(pairCanSync))"],
    ["the footer hides while the hourly units are absent", " && cloud.units !== \"absent\"", ""],
    ["Sync now waits for a paused pair", "if (pair.state === \"paused\") return false;", ""],
    ["a file not copied carries its reason", " && (c.kind !== \"unreadable-on-drive\" || isText(c.reason))", ""],
    ["a file not copied with no copy here needs no local path", "(c.kind === \"unreadable-on-drive\" && !hasOwn(c, \"localPath\")) || ", ""],
    ["only a file not copied may lack its local path", "c.kind === \"unreadable-on-drive\" && !hasOwn(c, \"localPath\")", "!hasOwn(c, \"localPath\")"],
    ["a known reason reads in its own words", "return row === undefined ? REASON_DEFAULT : row.text;", "return REASON_DEFAULT;"],
    ["an unknown reason reads in the default words", "return row === undefined ? REASON_DEFAULT : row.text;", "return row === undefined ? reason : row.text;"],
    ["a pair with files that need the user does not read up to date", "if (pair.state === \"idle\" && pair.needsYou > 0) return {", "if (false) return {"],
    ["a paused pair reads its pause", "if (pair.state === \"idle\" && pair.needsYou > 0) return {", "if (pair.needsYou > 0) return {"],
    ["a pair counts its own files", "return c.pair === p.id;", "return true;"],
    ["the pair lines read the pair's view", "return p.label + \": \" + pairView(p, now).text;", "return p.label + \": \" + stateView(p.state, p.staleAfter, now).text;"],
    ["a change on both sides names the kept copy's folder", "if (conflict.kind === \"both-changed\" && conflict.storedPath !== undefined) return dirname(conflict.storedPath);", ""],
    ["a row needs its needs mark", "\n        && NEEDS.indexOf(c.needs) !== -1", ""],
    ["only a doubled name carries mine", "(duplicate ? typeof c.mine === \"boolean\" : !hasOwn(c, \"mine\"))", "true"],
    ["an owner is a not-mine doubled name's address", "(!hasOwn(c, \"owner\") || (duplicate && c.mine === false && isAddress(c.owner)))", "true"],
    ["the earlier doubled-name kind is refused", "\"duplicate-different\"];\nvar DUPLICATE_KINDS", "\"duplicate-different\", \"duplicate-on-drive\"];\nvar DUPLICATE_KINDS"],
    ["the needs-you count is judged", "if (doc.needsYou !== doc.conflicts.filter(function (c) { return c.needs === \"you\"; }).length) return", "if (false) return"],
    ["the popover's data carries the needs-you count", "needsYou: record.needsYou,", ""],
    ["rows that need the user come first", "needsFirst(record.conflicts).slice(0, CONFLICTS_MAX)", "record.conflicts.slice(0, CONFLICTS_MAX)"],
    ["the cap cuts after the sort", "needsFirst(record.conflicts).slice(0, CONFLICTS_MAX)", "needsFirst(record.conflicts.slice(0, CONFLICTS_MAX))"],
    ["a row carries the record's needs", "needs: c.needs, localAction:", "needs: \"you\", localAction:"],
    ["a fix in Google Drive has no local action", "return LOCAL_ACTION_KINDS.indexOf(conflict.kind) !== -1 && conflict.localPath !== undefined;", "return conflict.localPath !== undefined;"],
    ["the local-action flag is published", "localAction: hasLocalAction(c) };", "localAction: true };"],
    ["the popover row carries the needs mark", "needs: conflict.needs, action: action };", "needs: \"you\", action: action };"],
    ["a doubled name the user owns says what they do", "if (DUPLICATE_KINDS.indexOf(conflict.kind) === -1 || conflict.mine) return conflict.kind;", "if (DUPLICATE_KINDS.indexOf(conflict.kind) === -1) return conflict.kind;"],
    ["a shared doubled name names who can fix it", "conflict.kind + (conflict.owner !== undefined ? \"-shared\" : \"-unowned\")", "conflict.kind + \"-unowned\""],
    ["a change on both sides says which copy is here", "return conflict.copyFolder !== undefined ? \"both-changed-kept\" : \"both-changed\";", "return \"both-changed-kept\";"],
    ["a rename names its new name", ".replace(\"{to}\", function () { return conflict.to; })", ""],
    ["the notification counts the rows that need the user", "needsLine(record.needsYou)", "needsLine(record.conflicts.length)"],
    ["a connection notifies first", "if (reasons.indexOf(\"authorization-required\") !== -1)\n", "if (false)\n"],
    ["no file that needs the user draws no count", "cloud.needsYou > 0 ? String(cloud.needsYou) : \"\"", "String(cloud.needsYou)"],
    ["the bar counts only the files that need the user", "cloud.needsYou > 0 ? String(cloud.needsYou) : \"\"", "cloud.conflictCount > 0 ? String(cloud.conflictCount) : \"\""],
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
