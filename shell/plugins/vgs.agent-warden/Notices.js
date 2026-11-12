.pragma library
.import "ViewLogic.js" as ViewLogic

// The Agent Warden plugin's notices, pure so
// scripts/test-agent-warden-notices.js runs them under node: which episodes
// a status holds, which of them are new, what each new one says, and the
// core notify options that send it.
//
// An episode is a condition that opens and later clears, one notice per
// episode. Each item of the warden's status is one, keyed by the item's
// `key`, which vsys keeps the same from one check to the next while its
// state holds
// (https://github.com/vanillagreencom/vsys/blob/main/docs/architecture/warden.md#rules).
// The plugin's own stale status is one more, keyed NOT_CHECKING.
// The service remembers the keys of the open episodes; an episode is sent
// once when it opens and again only after it has cleared and opened again.
// A key clears only on evidence: a fresh status that no longer holds it. A
// status that cannot tell, an unreadable or stale one, keeps the keys it
// cannot judge.
//
// The words of an item's notice are vsys's own: its title and detail.
// The observation boundary is
// shell/plugins/vgs.agent-warden/README.md § How it works.

// The `notify` setting's values, least first: each sends what the one
// before it sends and more.
var MODES = ["off", "problems", "everything"];
// The least MODES value that sends an item of each level: `problems`
// sends what asks the reader for a step, `everything` adds what the warden
// handles itself.
var LEAST = { "danger": "problems", "warn": "problems", "info": "everything" };
// The most episode keys the service remembers. A new episode that finds
// them all in use is neither sent nor remembered, so it is tried again on
// the next status and never sent twice.
var MAX_EPISODES = 64;
// How often the service touches the warden's heartbeat file. The warden
// leaves every notice to the plugin while the file is less than 120 s old.
var HEARTBEAT_MS = 60000;
// The key of the plugin's own episode: the warden stopped writing.
var NOT_CHECKING = "not-checking:agent-warden";

// Whether the service owns the notices: while it reads a status document
// (STATUS, WardenLogic.readStatus's answer or the service's absent and
// pending reads). Only then does it touch the heartbeat, so a warden this
// plugin cannot read gets the warden's own notices back within 120 s.
// The `notify` setting plays no part: `off` keeps the heartbeat, so the
// warden stays silent as the user asked.
function owns(status) {
    return status.kind === "read";
}

// The episodes DETAIL, WardenLogic.derive's answer, holds: { open, keep }.
// `open` lists each open episode as { key, item } for an item of a fresh
// status, or { key: NOT_CHECKING, checkedAt } for a stale one; `keep` is
// whether a remembered key not open stays remembered, because the status
// cannot tell whether its condition cleared.
function conditionsOf(detail) {
    switch (detail.state) {
    case "not-set-up":
        return { open: [], keep: true };
    case "not-checking":
        if (detail.reason !== "stale") return { open: [], keep: true };
        return { open: [{ key: NOT_CHECKING, checkedAt: detail.checkedAt }], keep: true };
    case "calm":
    case "info":
    case "warn":
    case "danger":
        return { open: detail.items.map(function (item) { return { key: item.key, item: item }; }), keep: false };
    }
    throw new Error("agent-warden: state=" + JSON.stringify(detail.state) + " unknown");
}

// One status's step through MEMORY, the keys the service remembers, with
// CONDITIONS, conditionsOf's answer: { memory, opened, dropped }. `memory`
// keeps each remembered key that is still open, or every remembered key
// when CONDITIONS keep them, and adds each new open one, up to
// MAX_EPISODES; `opened` lists the new episodes, which are the ones to
// send; `dropped` counts the new ones past the ceiling. A fresh status
// that holds one key twice opens it once.
function step(memory, conditions) {
    var openKeys = conditions.open.map(function (e) { return e.key; });
    var next = memory.filter(function (k) { return conditions.keep || openKeys.indexOf(k) !== -1; });
    var opened = [];
    var dropped = 0;
    conditions.open.forEach(function (e) {
        if (next.indexOf(e.key) !== -1) return;
        if (next.length >= MAX_EPISODES) {
            dropped += 1;
            return;
        }
        next.push(e.key);
        opened.push(e);
    });
    return { memory: next, opened: opened, dropped: dropped };
}

// MEMORY without KEYS: the episodes of a notice that failed to go out, so
// the next status opens them again, as the warden retries a failed send.
function forget(memory, keys) {
    return memory.filter(function (k) { return keys.indexOf(k) === -1; });
}

function sends(least, mode) {
    var rank = MODES.indexOf(mode);
    if (rank === -1) throw new Error("agent-warden: notify=" + JSON.stringify(mode) + " unknown");
    return rank >= MODES.indexOf(least);
}

// The notices for OPENED, step's new episodes, under MODE, one of MODES,
// at NOW; VSYS is whether the last scan found vsys, whose TUI every action
// opens. Each notice is { keys, title, body, tone, icon, urgency,
// transient, actions }: `keys` the episodes it tells of, `tone` the
// level's notify tone, "" for a calm one, `actions` the item's actions
// the vsys TUI takes, each { label, args }, none without vsys.
function notices(opened, mode, vsys, now) {
    var out = [];
    opened.forEach(function (e) {
        if (e.key === NOT_CHECKING) {
            if (sends("problems", mode)) out.push(stopped(e, now));
            return;
        }
        if (!sends(LEAST[e.item.level], mode)) return;
        var look = ViewLogic.LEVEL_LOOKS[e.item.level];
        out.push({
            keys: [e.key],
            title: e.item.title,
            body: e.item.detail === null ? "" : e.item.detail,
            tone: look.notice,
            icon: look.icon,
            urgency: look.urgency,
            transient: look.transient,
            actions: vsys ? ViewLogic.actionsOf(e.item) : []
        });
    });
    return out;
}

// The notice for the plugin's own stale episode E: the crossed shield in
// the card's own ink, as the bar draws not checking in grey. It offers no
// action: a notice's actions open the vsys TUI, and Start checks is the
// panel's own setup step.
function stopped(e, now) {
    return {
        keys: [e.key],
        title: "Agent Warden has stopped checking",
        body: "The last check was " + ViewLogic.ago(e.checkedAt, now) + ", so agent limits are not applied.",
        tone: "",
        icon: "shield-off",
        urgency: "normal",
        transient: false,
        actions: []
    };
}

// The options shell.notify.send takes for NOTICE. A notice with no tone
// leaves `tone` out, which the core reads as none. Each action's id is
// its index in NOTICE.actions, which the service's press reads back. A
// notice with no action observes delivery without waiting for dismissal.
function shellOptions(notice) {
    var options = {
        title: notice.title, message: notice.body, icon: notice.icon,
        urgency: notice.urgency, transient: notice.transient, wait: false,
        actions: notice.actions.map(function (a, i) { return { id: String(i), label: a.label }; })
    };
    if (notice.tone !== "") options.tone = notice.tone;
    return options;
}
