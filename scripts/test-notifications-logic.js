#!/usr/bin/env node
// The notifications' decisions, shell/plugins/vgs.notifications/
// NotificationLogic.js, under node: the body a card may render, Silence,
// lifetimes, entries and their image copies, the state file's judge, what a
// restart restores, the history's and the panel's limits, which toast a
// full stack lets go, the hover actions, what a choice on a card does,
// which notifications stay held and which go into the history, the
// sender's window, the paused and running clocks, the per-application
// rules that read a sender's workspace, people and workspace icons, and
// the VGS hints with what a click on a hinted card does, how a card's
// body text reads against its card, and which Slack message a card opens.
// Every expected value is written out by hand.
//
// The controls at the end edit a copy of the logic, one rule at a time, and
// require this suite to fail on each copy.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { load } = require("../bin/lib/qml-library.js");

// Slack stamps its log in local time, and the recorded stamp below was
// written in this zone.
process.env.TZ = "America/Los_Angeles";

const file = path.join(__dirname, "..", "shell", "plugins", "vgs.notifications", "NotificationLogic.js");
// The plugin's look, whose face tints the logic names.
const appearance = load(path.join(__dirname, "..", "shell", "plugins", "vgs.notifications", "Appearance.js"));
// The theme judge, which resolves the look and reads a contrast ratio.
const themeLogic = load(path.join(__dirname, "..", "shell", "Commons", "ThemeLogic.js"));
// The core's status judge, which the Slack token rows the service publishes
// must pass.
const pluginLogic = load(path.join(__dirname, "..", "shell", "Core", "PluginLogic.js"));
const IMAGES = "/state/vgshell/notifications/images";
// The logic runs in its own context, whose arrays and objects are not this
// one's; values are compared as JSON.
const same = (got, want, message) => assert.deepEqual(JSON.parse(JSON.stringify(got)), want, message === undefined ? JSON.stringify(want) : message);

// An entry as the state file stores it.
function stored(timestamp, id, extra) {
    return Object.assign({ key: timestamp + "-" + id, originalId: id, app: "app", appIcon: "", summary: "s" + id, body: "", image: "", desktopEntry: "", urgency: 1, expireTimeout: 0, timestamp: timestamp, hintIcon: "", hintTone: "", hintOpen: "", hintClick: "" }, extra || {});
}
const BOOT = "4b1c0e2a-6d55-4d2e-9a0f-3f1b2c4d5e6f";
function stateText(value) {
    return JSON.stringify(Object.assign({ version: 2, boot: BOOT, dnd: false, readBefore: 0, live: [], history: [] }, value));
}

// Bodies: [label, body, app, what the card renders].
const BODIES = [
    ["plain text", "hello", "app", "hello"],
    ["a remote image tag", 'a <img src="http://h/x.png"> b', "app", "a  b"],
    ["an image tag in capitals", 'a <IMG SRC="http://h/x.png"> b', "app", "a  b"],
    ["an image tag behind a NEL", "a <\u0085img src=\"http://h/x.png\"> b", "app", "a  b"],
    // One malformed tag named `im` to Qt as to the stripper: kept whole, and
    // nothing is spliced into a live image tag.
    ["a nested decoy", '<im<img src="http://a/decoy.png">g src="http://a/beacon.png">', "app", '<im<img src="http://a/decoy.png">g src="http://a/beacon.png">'],
    ["markup kept", "<b>bold</b> <i>it</i>", "app", "<b>bold</b> <i>it</i>"],
    ["newlines become breaks", "one\ntwo\r\nthree", "app", "one<br/>two<br/>three"],
    ["a break that would open an image", "<x\n<img src=\"http://h/x.png\">", "app", "<x<br/>"],
    ["an unterminated image tag", 'a <img src="http://h', "app", "a "],
    ["a Chromium site address", "<a href=\"https://chat.example.com\">chat.example.com</a> Hi there", "Google Chrome", "Hi there"],
    ["a bare Chromium site address", "chat.example.com Hi there", "chromium", "Hi there"],
    ["a site address from another sender", "chat.example.com Hi there", "app", "chat.example.com Hi there"],
    // Chromium as it runs here names no application: its site line, then a
    // blank line.
    ["an unnamed sender's site line", "app.slack.com\n\nfleet: Done", "", "fleet: Done"],
    ["an unnamed sender's calendar line", "calendar.google.com\n\n10:30am \u2013 11:30am", "", "10:30am \u2013 11:30am"],
    ["an unnamed sender's first word without a blank line", "app.slack.com fleet: Done", "", "app.slack.com fleet: Done"],
    ["an unnamed sender's first line without a blank line", "app.slack.com\nfleet: Done", "", "app.slack.com<br/>fleet: Done"]
];

// State files the judge refuses: [label, text, the error].
const STATE_REFUSED = [
    ["an empty file", "", "not-json"],
    ["not JSON", "{ nope", "not-json"],
    ["a list", "[]", "not-object"],
    ["an unknown key", stateText({ extra: 1 }), "extra unknown"],
    ["the first version, which named no boot", stateText({ version: 1, boot: undefined }), "version want=2"],
    ["no boot", stateText({ boot: undefined }), "boot want=string"],
    ["an empty boot", stateText({ boot: "" }), "boot want=string"],
    ["a boot that is no string", stateText({ boot: 7 }), "boot want=string"],
    ["a Silence that is no boolean", stateText({ dnd: "on" }), "dnd want=boolean"],
    ["a read cutoff that is no number", stateText({ readBefore: "0" }), "readBefore want=number"],
    ["a history that is no list", stateText({ history: {} }), "history want=list"],
    ["a history past its limit", stateText({ history: Array.from({ length: 101 }, (_, i) => stored(1000 + i, i)) }), "history length=101 want<=100"],
    ["a live list past its limit", stateText({ live: Array.from({ length: 21 }, (_, i) => stored(1000 + i, i)) }), "live length=21 want<=20"],
    ["an entry that is no object", stateText({ history: [3] }), "history.0 want=object"],
    ["an entry with an unknown key", stateText({ history: [stored(5, 1, { extra: 1 })] }), "history.0.extra unknown"],
    ["a summary that is no string", stateText({ history: [stored(5, 1, { summary: 3 })] }), "history.0.summary want=string"],
    ["a timestamp that is no number", stateText({ live: [stored(5, 1, { timestamp: "5" })] }), "live.0.timestamp want=number"],
    ["an unknown urgency", stateText({ history: [stored(5, 1, { urgency: 7 })] }), "history.0.urgency want=0|1|2"],
    ["a key that is not its identity", stateText({ history: [stored(5, 1, { key: "6-1" })] }), "history.0.key want=5-1"],
    ["a deadline that is no number", stateText({ live: [stored(5, 1, { deadline: "9" })] }), "live.0.deadline want=number"],
    ["a remaining time that is no number", stateText({ live: [stored(5, 1, { remaining: null })] }), "live.0.remaining want=number"],
    ["a clock both running and paused", stateText({ live: [stored(5, 1, { deadline: 9, remaining: 3 })] }), "live.0 deadline and remaining both set"],
    ["a key twice", stateText({ live: [stored(5, 1)], history: [stored(5, 1)] }), "history.0.key duplicate"],
    ["a stored hint role that is no string", stateText({ history: [stored(5, 1, { hintIcon: 3 })] }), "history.0.hintIcon want=string"],
    ["a stored hint tone outside the tones", stateText({ history: [stored(5, 1, { hintTone: "red" })] }), "history.0.hintTone refused"],
    ["a stored hint path that is relative", stateText({ history: [stored(5, 1, { hintOpen: "runs/a.log" })] }), "history.0.hintOpen refused"],
    ["a stored open click with nothing to open", stateText({ history: [stored(5, 1, { hintClick: "open" })] }), "history.0.hintClick open without hintOpen"]
];

// The VGS hints: [label, hints map, the roles an entry keeps, the names
// refused, what a click does]. shell/plugins/vgs.notifications/developer.md § Hints.
const NO_HINTS = { hintIcon: "", hintTone: "", hintOpen: "", hintClick: "" };
const HINT_ROWS = [
    ["no hints", {}, NO_HINTS, [], "default"],
    ["hints that are not a map", "x-vgs-icon", NO_HINTS, [], "default"],
    ["an automation's error", { "x-vgs-icon": "circle-x", "x-vgs-tone": "danger", "x-vgs-open": "/state/runs/a@1.log", "x-vgs-click": "open" },
        { hintIcon: "circle-x", hintTone: "danger", hintOpen: "/state/runs/a@1.log", hintClick: "open" }, [], "open"],
    ["an automation's start", { "x-vgs-icon": "play", "x-vgs-tone": "warning", "x-vgs-click": "none" },
        { hintIcon: "play", hintTone: "warning", hintOpen: "", hintClick: "none" }, [], "dismiss"],
    ["a file with no click hint keeps the default click", { "x-vgs-open": "/tmp/a.log" }, Object.assign({}, NO_HINTS, { hintOpen: "/tmp/a.log" }), [], "default"],
    ["an icon outside the grammar", { "x-vgs-icon": "Circle X" }, NO_HINTS, ["x-vgs-icon"], "default"],
    ["an icon past its length", { "x-vgs-icon": "a".repeat(65) }, NO_HINTS, ["x-vgs-icon"], "default"],
    ["a tone outside the status tones", { "x-vgs-tone": "red" }, NO_HINTS, ["x-vgs-tone"], "default"],
    ["a relative path", { "x-vgs-open": "a.log", "x-vgs-click": "open" }, NO_HINTS, ["x-vgs-open", "x-vgs-click"], "default"],
    ["a path with a line break", { "x-vgs-open": "/tmp/a\nb" }, NO_HINTS, ["x-vgs-open"], "default"],
    ["a path past the TUI argument limit", { "x-vgs-open": "/" + "a".repeat(256) }, NO_HINTS, ["x-vgs-open"], "default"],
    ["an open click with nothing to open", { "x-vgs-click": "open" }, NO_HINTS, ["x-vgs-click"], "default"],
    ["a click hint outside the clicks", { "x-vgs-click": "run" }, NO_HINTS, ["x-vgs-click"], "default"],
    ["a hint that is no string", { "x-vgs-icon": 5 }, NO_HINTS, ["x-vgs-icon"], "default"],
    ["an empty hint", { "x-vgs-tone": "" }, NO_HINTS, ["x-vgs-tone"], "default"],
    ["another sender's hint", { "x-other": "circle-x", "urgency": 2 }, NO_HINTS, [], "default"]
];

// Senders a rule reads, in the title forms Slack's web client builds:
// [label, app, desktop entry, summary, body, what the card draws].
const desktop = (workspace, title, faces, more) => ({ rule: "slack", source: "desktop", workspace, title, faces, more });
const browser = (title, faces) => ({ rule: "slack", source: "browser", workspace: "", title, faces, more: 0 });
const ENRICHED = [
    ["a direct message", "Slack", "slack", "[acme] from Ada Lovelace", "Lunch?", desktop("acme", "from Ada Lovelace", ["Ada Lovelace"], 0)],
    ["a channel message", "Slack", "slack", "[acme] in eng-core", "Grace Hopper (Navy): shipped", desktop("acme", "in eng-core", ["Grace Hopper (Navy)"], 0)],
    ["a channel message with no sender", "Slack", "slack", "[acme] in eng-core", "shipped", desktop("acme", "in eng-core", [], 0)],
    ["a group message, sender first and once", "Slack", "slack", "[acme] in ada, grace, alan, edsger, barbara", "Grace: hi all", desktop("acme", "in ada, grace, alan, edsger, barbara", ["Grace", "ada", "alan", "edsger"], 1)],
    ["a group message of four", "Slack", "slack", "[acme] in ada, grace, alan", "edsger: hi", desktop("acme", "in ada, grace, alan", ["edsger", "ada", "grace", "alan"], 0)],
    ["a group message of three", "Slack", "slack", "[acme] in ada, grace", "alan: hi", desktop("acme", "in ada, grace", ["alan", "ada", "grace"], 0)],
    ["one workspace, a direct message", "Slack", "slack", "New message from Ada", "hi", desktop("", "from Ada", ["Ada"], 0)],
    ["one workspace, a channel", "Slack", "slack", "New message in eng", "Ada: hi", desktop("", "in eng", ["Ada"], 0)],
    ["one workspace, a thread", "Slack", "slack", "New thread message in eng", "Ada: hi", desktop("", "in eng", ["Ada"], 0)],
    ["past Do Not Disturb", "Slack", "slack", "Ada is trying to reach you", "urgent", desktop("", "Ada is trying to reach you", ["Ada"], 0)],
    ["an unknown title under a workspace", "Slack", "slack", "[acme] Reminder: standup", "", desktop("acme", "Reminder: standup", [], 0)],
    ["an unknown title", "Slack", "slack", "Reminder: standup", "", null],
    ["matched by the desktop entry alone", "Electron", "slack", "[acme] from Ada", "", desktop("acme", "from Ada", ["Ada"], 0)],
    ["matched by the flatpak's name", "com.slack.Slack", "", "[acme] from Ada", "", desktop("acme", "from Ada", ["Ada"], 0)],
    ["another sender unchanged", "Chat", "chat", "[acme] from Ada", "", null],
    // Slack in a browser: Chromium here names no application.
    ["a browser channel message", "", "", "New message in master-operator", "app.slack.com\n\nfleet: Done: settings", browser("in master-operator", ["fleet"])],
    ["a browser direct message", "", "", "New message from Ada", "app.slack.com\n\nare you there?", browser("from Ada", ["Ada"])],
    ["a browser thread", "", "", "New thread message in eng", "app.slack.com\n\nAda: hi", browser("in eng", ["Ada"])],
    ["a named Chromium browser", "Google Chrome", "", "New message in eng", "<a href=\"https://app.slack.com\">app.slack.com</a> Grace: shipped", browser("in eng", ["Grace"])],
    ["another site in a browser", "", "", "New message in eng", "chat.example.com\n\nGrace: hi", null],
    ["a Slack address with no blank line from an unnamed sender", "", "", "New message in eng", "app.slack.com Grace: hi", null],
    ["a Slack address from a sender that is no browser", "Chat", "chat", "New message in eng", "app.slack.com\n\nGrace: hi", null]
];

// A toast's motion over the shipped durations (short2 100, short3 150,
// short4 200, medium1 250, medium2 300, medium3 350, medium4 400) and over
// a set where the fade outlasts the close, short3 400 and medium3 100.
// Glass: in, max(150, 250) + 100 + max(300, 400, 2 * 200) = 750; out,
// max(150, 350) + 150 = 500. Plain: in, max(150, 250) = 250; out, the fade
// then the close, 150 + 350 = 500, and 400 + 100 = 500 where glass takes
// max(400, 100) + 400 = 800 out and max(400, 250) + 100 + 400 = 900 in.
const SHIPPED_DURATIONS = { short2: 100, short3: 150, short4: 200, medium1: 250, medium2: 300, medium3: 350, medium4: 400 };
const LONG_FADE = Object.assign({}, SHIPPED_DURATIONS, { short3: 400, medium3: 100 });
const TOAST_MOTION = [
    [SHIPPED_DURATIONS, true, { enter: 750, exit: 500 }],
    [SHIPPED_DURATIONS, false, { fade: 150, drop: 250, close: 350, enter: 250, exit: 500 }],
    [LONG_FADE, true, { enter: 900, exit: 800 }],
    [LONG_FADE, false, { fade: 400, drop: 250, close: 100, enter: 400, exit: 500 }]
];

// Slack's log record of one notification, as Slack 4.52.171 wrote it for a
// message in a second workspace on 2026-10-09 (browser.log, host cachy):
// the header line, then the object with these keys in this order. The ids
// are the synthetic Slack's and every other value a stand-in of the
// recorded value's kind. `stamp` is the header's time; `ids` holds teamId,
// channel, msg and, for a thread reply, thread_ts, and `store`, when set,
// another event's name for the line.
function slackLogged(stamp, ids) {
    const hidden = "[REDACTED]";
    const record = { title: hidden, subtitle: hidden, content: hidden, body: hidden, authorName: hidden, avatarImage: hidden,
        teamId: ids.teamId, userId: "U0GRACE", msg: ids.msg, channel: ids.channel, channelName: hidden };
    if (ids.thread_ts !== undefined) record.thread_ts = ids.thread_ts;
    Object.assign(record, { launchUri: hidden, silent: true, hasReply: true, groupWindowsNotifications: true, trace_id: "0f0e0d0c0b0a0908", id: "smoke-notification",
        sound: "none", win32: { workspaceName: "globex", useComActivation: false }, mac: { closeButtonOverride: false } });
    return "[" + stamp + "] info: Store: " + (ids.store || "NEW_NOTIFICATION") + " \n" + JSON.stringify(record, null, 2) + "\n";
}
// The recorded stamp, and the same time in milliseconds: the session bus
// carried that notification at 1791592528.584874 (dbus-monitor).
const SLACK_STAMP = "10/09/26, 17:35:28:584";
const SLACK_STAMP_MS = 1791592528584;
const GLOBEX_MESSAGE = { teamId: "T0GLOBEX", channel: "C0GLOBEXREVIEW", msg: "1791590000.000100" };
const GLOBEX_OTHER = { teamId: "T0GLOBEX", channel: "C0GLOBEXREVIEW", msg: "1791590000.000400" };
const ACME_MESSAGE = { teamId: "T0ACME", channel: "C0ACMEDESIGN", msg: "1791590000.000200" };
const GLOBEX_LINK = "slack://channel?id=C0GLOBEXREVIEW&message=1791590000.000100&team=T0GLOBEX";
const ACME_LINK = "slack://channel?id=C0ACMEDESIGN&message=1791590000.000200&team=T0ACME";
const SLACK_RECORDED = slackLogged(SLACK_STAMP, GLOBEX_MESSAGE);
const globexWith = change => slackLogged(SLACK_STAMP, Object.assign({}, GLOBEX_MESSAGE, change));
// A second record of the recorded message's team, 84 ms before it.
const GLOBEX_BEFORE = slackLogged("10/09/26, 17:35:28:500", GLOBEX_OTHER);
// A record line with no object under it, which names no team.
const SLACK_NO_OBJECT = "[" + SLACK_STAMP + "] info: Store: NEW_NOTIFICATION \n{\n  redacted\n}\n";
// A read by bytes that begins inside the line of a record of that team,
// written hours earlier: the line keeps no whole stamp.
const SLACK_CUT_LINE = slackLogged("10/09/26, 09:00:00:000", GLOBEX_OTHER).slice(10);
const one = link => ({ link: link, found: "one" });
const no = found => ({ link: "", found: found });
// The message a Slack card opens: [label, the log's text, the card's
// arrival in milliseconds after the recorded stamp, its team id, the
// reading].
const SLACK_LINKS = [
    ["the recorded notification of a second workspace", "[10/09/26, 17:35:24:519] info: window.focus\n" + SLACK_RECORDED, 1, "T0GLOBEX", one(GLOBEX_LINK)],
    ["a thread reply", globexWith({ thread_ts: "1791580000.000300" }), 1, "T0GLOBEX", one(GLOBEX_LINK + "&thread_ts=1791580000.000300")],
    ["the card's team, beside another team's record in its window", slackLogged("10/09/26, 17:35:28:500", ACME_MESSAGE) + SLACK_RECORDED, 1, "T0GLOBEX", one(GLOBEX_LINK)],
    ["the other team's card over the same log", slackLogged("10/09/26, 17:35:28:500", ACME_MESSAGE) + SLACK_RECORDED, 1, "T0ACME", one(ACME_LINK)],
    ["no record of the card's team", slackLogged(SLACK_STAMP, ACME_MESSAGE), 1, "T0GLOBEX", no("none")],
    ["a card whose team is not known", SLACK_RECORDED, 1, "", no("no-team")],
    ["two records of one team in one window", GLOBEX_BEFORE + SLACK_RECORDED, 1, "T0GLOBEX", no("several")],
    ["a stamp at the arrival", SLACK_RECORDED, 0, "T0GLOBEX", one(GLOBEX_LINK)],
    ["a stamp 500 ms before the arrival", SLACK_RECORDED, 500, "T0GLOBEX", one(GLOBEX_LINK)],
    ["a stamp 501 ms before the arrival", SLACK_RECORDED, 501, "T0GLOBEX", no("none")],
    ["a stamp 1 ms after the arrival", SLACK_RECORDED, -1, "T0GLOBEX", no("none")],
    // Slack 4.52.171 logs such a record for a notice of its own.
    ["a message that is a word", globexWith({ msg: "jit-notification" }), 1, "T0GLOBEX", no("refused")],
    ["a message time that is a number", globexWith({ msg: 1791590000.0001 }), 1, "T0GLOBEX", no("refused")],
    ["a channel that carries a second parameter", globexWith({ channel: "C0GLOBEX&team=T0ACME" }), 1, "T0GLOBEX", no("refused")],
    ["a thread time that is a word", globexWith({ thread_ts: "latest" }), 1, "T0GLOBEX", no("refused")],
    ["a team id in small letters", globexWith({ teamId: "t0globex" }), 1, "T0GLOBEX", no("refused")],
    ["a record line with no object under it", SLACK_NO_OBJECT, 1, "T0GLOBEX", no("refused")],
    // The read can end inside the newest record, which then has no closing
    // line.
    ["a record the read cut short", SLACK_RECORDED.slice(0, -3), 1, "T0GLOBEX", no("refused")],
    ["a refused record of the card's team beside its record", globexWith({ msg: "jit-notification" }) + SLACK_RECORDED, 1, "T0GLOBEX", no("several")],
    ["a refused record of another team beside the card's record", slackLogged(SLACK_STAMP, Object.assign({}, ACME_MESSAGE, { msg: "jit-notification" })) + SLACK_RECORDED, 1, "T0GLOBEX", one(GLOBEX_LINK)],
    ["a record of no team that reads beside the card's record", SLACK_NO_OBJECT + SLACK_RECORDED, 1, "T0GLOBEX", no("several")],
    ["a read that begins inside the line of the only record", SLACK_CUT_LINE, 1, "T0GLOBEX", no("refused")],
    ["a read that begins inside the line of a record of the card's team", SLACK_CUT_LINE + SLACK_RECORDED, 1, "T0GLOBEX", no("several")],
    ["a read that begins inside the line of another team's record", SLACK_CUT_LINE + slackLogged(SLACK_STAMP, ACME_MESSAGE), 1, "T0ACME", one(ACME_LINK)],
    ["a read that begins inside an older record's object", slackLogged("10/09/26, 09:00:00:000", GLOBEX_OTHER).slice(60) + SLACK_RECORDED, 1, "T0GLOBEX", one(GLOBEX_LINK)],
    ["another line of the store", globexWith({ store: "CLICK_NOTIFICATION" }), 1, "T0GLOBEX", no("none")],
    ["an empty log", "", 1, "T0GLOBEX", no("none")]
];
// What a choice on a card needs to open its message: [label, choice, the
// actions offered, the card, Slack's list, the request]. The cards are the
// recorded notification's, its names the synthetic Slack's.
const SLACK_LIST = [
    { id: "T0ACME", domain: "acme", name: "Acme Corp", names: ["acme", "Acme Corp"], urls: [] },
    { id: "T0GLOBEX", domain: "globex", name: "Globex", names: ["globex", "Globex"], urls: [] }
];
const SLACK_CARD = { app: "Slack", desktopEntry: "slack", appIcon: "", summary: "[globex] in launch-review", body: "Grace: the review notes are up", timestamp: 1791592528585 };
const SLACK_WEB_CARD = { app: "", desktopEntry: "", appIcon: "", summary: "New message in launch-review", body: "app.slack.com\n\nGrace: the review notes are up", timestamp: 1791592528585 };
const GLOBEX_REQUEST = { rule: "slack", arrival: 1791592528585, team: "T0GLOBEX" };
const MESSAGE_REQUESTS = [
    ["a click on a Slack card", "open", ["default", "View"], SLACK_CARD, SLACK_LIST, GLOBEX_REQUEST],
    ["a click on a Slack card with no live action", "open", [], SLACK_CARD, SLACK_LIST, GLOBEX_REQUEST],
    ["the View pill, the default action", "action:default", ["default", "View"], SLACK_CARD, SLACK_LIST, GLOBEX_REQUEST],
    ["the first action where no default is offered", "action:reply", ["reply"], SLACK_CARD, SLACK_LIST, GLOBEX_REQUEST],
    ["another action's pill", "action:reply", ["default", "reply"], SLACK_CARD, SLACK_LIST, null],
    ["a dismissal", "dismiss", ["default", "View"], SLACK_CARD, SLACK_LIST, null],
    ["a click on a Slack card from a browser", "open", [], SLACK_WEB_CARD, SLACK_LIST, null],
    ["a click on another sender's card", "open", ["default"], { app: "smoke-chat", desktopEntry: "", appIcon: "", summary: "Hello", body: "", timestamp: 1791592528585 }, SLACK_LIST, null],
    ["a card of the only workspace signed in, which its title does not name", "open", ["default", "View"], Object.assign({}, SLACK_CARD, { summary: "New message in launch-review" }), SLACK_LIST.slice(1), GLOBEX_REQUEST],
    ["a card of a workspace no list names", "open", ["default", "View"], Object.assign({}, SLACK_CARD, { summary: "[initech] in launch-review" }), SLACK_LIST, { rule: "slack", arrival: 1791592528585, team: "" }]
];

function verify(logic) {
    for (const [label, text, after, team, want] of SLACK_LINKS)
        same(logic.slackMessageLink(text, SLACK_STAMP_MS + after, team), want, "Slack message link: " + label);
    for (const [label, choice, offered, card, list, want] of MESSAGE_REQUESTS)
        same(logic.messageRequest(choice, offered, card, list, []), want, "message request: " + label);
    assert.equal(logic.enricherById("slack").messages.link, logic.slackMessageLink, "the Slack rule's reader is the link reader");
    for (const [durations, glass, want] of TOAST_MOTION)
        same(logic.toastMotion(durations, glass), want, "toast motion " + (glass ? "with" : "without") + " glass over " + JSON.stringify(durations));
    for (const [label, body, app, want] of BODIES)
        assert.equal(logic.styledBody(body, app, ""), want, "styled body: " + label);
    assert.equal(logic.sanitizeBody("", "app", ""), "", "an empty body stays empty");
    assert.equal(logic.summaryStartsWithGlyph("\u{f0e0}  Mail"), true, "a glyph and two spaces open the summary");
    assert.equal(logic.summaryStartsWithGlyph("M  ail"), true, "any first character counts, as the reference reads it");
    assert.equal(logic.summaryStartsWithGlyph("Mail today"), false, "one space is text");
    assert.equal(logic.summaryStartsWithGlyph(""), false, "an empty summary has no glyph");

    // Silence lets a critical notification from the bare command line or a
    // VGS plugin through: [label, appName, urgency, hints, bypasses].
    const U = logic.URGENCY;
    for (const [label, app, urgency, hints, want] of [
        ["a critical bare notify-send", "notify-send", U.critical, {}, true],
        ["a normal bare notify-send", "notify-send", U.normal, {}, false],
        ["a chat app marking everything critical stays silenced", "Slack", U.critical, {}, false],
        ["a critical plugin message", "Lock", U.critical, { "x-vgs-plugin": "vgs.lock" }, true],
        ["a normal plugin message", "Lock", U.normal, { "x-vgs-plugin": "vgs.lock" }, false],
        ["an empty plugin hint", "Lock", U.critical, { "x-vgs-plugin": "" }, false],
        ["a plugin hint that is no string", "Lock", U.critical, { "x-vgs-plugin": 1 }, false],
        ["no hints at all", "Lock", U.critical, undefined, false]
    ])
        assert.equal(logic.bypassesSilence(app, urgency, hints), want, "silence: " + label);

    // Lifetimes: [urgency, sender's timeout, the duration setting in
    // milliseconds, milliseconds shown].
    for (const [urgency, asked, normal, want] of [[U.low, 0, 8000, 5000], [U.low, 7000, 8000, 7000], [U.normal, 0, 8000, 8000], [U.normal, 3000, 8000, 8000], [U.normal, 12000, 8000, 12000], [U.normal, 90000, 8000, 30000], [U.critical, 5000, 8000, 0], [U.normal, -1, 8000, 8000], [U.normal, NaN, 8000, 8000],
        [U.normal, 0, 3000, 3000], [U.normal, 0, 20000, 20000], [U.normal, 12000, 20000, 20000], [U.low, 0, 3000, 3000], [U.low, 0, 20000, 5000], [U.critical, 0, 3000, 0]])
        assert.equal(logic.lifetimeFor(urgency, asked, normal), want, `lifetime of urgency ${urgency} asking ${asked} under ${normal}`);

    // Entries.
    const fields = { id: 7, appName: "Chat", appIcon: "chat", summary: "Hi", body: "b", image: "image://icon//tmp/a.png", desktopEntry: "chat", urgency: U.critical, expireTimeout: 4000 };
    same(logic.entryOf(fields, 1000, null), { key: "1000-7", originalId: 7, app: "Chat", appIcon: "chat", summary: "Hi", body: "b", image: "file:///tmp/a.png", desktopEntry: "chat", urgency: 2, expireTimeout: 4000, timestamp: 1000, hintIcon: "", hintTone: "", hintOpen: "", hintClick: "" });

    // Hints: an entry keeps the ones the judge accepts, and a click follows them.
    for (const [label, hints, roles, refused, route] of HINT_ROWS) {
        const read = logic.readHints(hints);
        same(read.roles, roles, "hint roles: " + label);
        same(read.refused, refused, "hints refused: " + label);
        const made = logic.entryOf(Object.assign({}, fields, { hints: hints }), 1000, null);
        same([made.hintIcon, made.hintTone, made.hintOpen, made.hintClick], [roles.hintIcon, roles.hintTone, roles.hintOpen, roles.hintClick], "entry hints: " + label);
        assert.equal(logic.clickRoute("open", made), route, "click: " + label);
        assert.equal(logic.clickRoute("action:reply", made), "default", "a pill ignores the click hints: " + label);
        assert.equal(logic.clickRoute("dismiss", made), "default", "dismiss ignores the click hints: " + label);
        same(logic.parseState(stateText({ history: [logic.persistable(made, IMAGES).entry] })).ok, true, "a stored hinted entry reads back: " + label);
    }
    // An open click's reply: ok lets the card leave; a refusal keeps it and
    // says why in a transient notification whose options the core's judge
    // accepts.
    same(logic.openOutcome("ok"), { leave: true, notice: null });
    const openManifest = pluginLogic.validateManifest(JSON.parse(fs.readFileSync(path.join(__dirname, "..", "shell", "plugins", "vgs.notifications", "manifest.json"), "utf8")), "/x").manifest;
    const runner = { launcher: "present", busy: [], run: "fixture" };
    const replies = [
        [pluginLogic.tuiRun(openManifest, true, "/x", { ...runner, busy: ["vgs.notifications/open"] }, "open", ["/file"]).answer, "Another file is open", "warning", "Close the open file window and try this notification again."],
        [pluginLogic.tuiRun(openManifest, true, "/x", { ...runner, launcher: "missing" }, "open", ["/file"]).answer, "The file did not open", "danger", "The setup window could not open. VGS is missing its terminal launcher, xdg-terminal-exec. Reinstall VGS to restore it."],
        [pluginLogic.tuiRun(openManifest, false, "/x", runner, "open", ["/file"]).answer, "The file did not open", "danger", "Enable Notifications in Plugins and try again."],
        [pluginLogic.tuiRun(openManifest, true, "/x", runner, "missing", []).answer, "The file did not open", "danger", "VGS cannot open notification files. Reinstall VGS to restore this feature."],
        [pluginLogic.tuiRun(openManifest, true, "/x", runner, "open", [null]).answer, "The file did not open", "danger", "VGS could not use the file path in this notification."],
        ["refused: tui=open reason=future-private-reason", "The file did not open", "danger", "Try this notification again."],
        ["error: private-path=/owner/file", "The file did not open", "danger", "Try this notification again."]
    ];
    for (const [reply, title, tone, message] of replies) {
        assert.equal(typeof reply, "string", "the actual core producer supplied a refusal");
        const outcome = logic.openOutcome(reply);
        same([outcome.leave, outcome.notice.title, outcome.notice.tone, outcome.notice.message, outcome.notice.transient], [false, title, tone, message, true], "open reply: " + reply);
        same(pluginLogic.notifyOptions(outcome.notice).ok, true, "the core accepts the published notice for " + reply);
        assert.doesNotMatch(JSON.stringify(outcome.notice), /reason=|tui=|private-path|future-private-reason/, "the published notice contains no diagnostic reply");
    }
    const hinted = logic.entryOf(Object.assign({}, fields, { hints: HINT_ROWS[2][1] }), 1000, null);
    assert.equal(logic.entryChanged(hinted, logic.updatedEntry(hinted, Object.assign({}, fields, { hints: HINT_ROWS[3][1] }))), true, "a replacement with other hints is a change");
    assert.equal(logic.entryOf(fields, 1000, k => k === "1000-7" || k === "1001-7").key, "1002-7", "a taken key moves the timestamp on");
    assert.equal(logic.entryOf({ id: 1, urgency: 9 }, 5, null).urgency, U.normal, "an unknown urgency is normal");
    assert.equal(logic.entryOf({ id: 1, summary: "x".repeat(600) }, 5, null).summary.length, 512, "a summary is cut at its limit");
    assert.equal(logic.entryOf({ id: 1, body: "x".repeat(5000) }, 5, null).body.length, 4096, "a body is cut at its limit");
    assert.equal(logic.entryOf({ id: 1, expireTimeout: -5 }, 5, null).expireTimeout, 0, "a negative timeout is none");
    const original = logic.entryOf(fields, 1000, null);
    const updated = logic.updatedEntry(original, Object.assign({}, fields, { id: 99, summary: "Hello" }));
    same([updated.key, updated.originalId, updated.timestamp, updated.summary], ["1000-7", 7, 1000, "Hello"], "an update keeps the identity");
    assert.equal(logic.entryChanged(original, updated), true);
    assert.equal(logic.entryChanged(original, logic.updatedEntry(original, fields)), false, "the same content is no change");

    // Image values: [value, local file].
    for (const [value, want] of [["/tmp/a.png", "/tmp/a.png"], ["file:///tmp/a%20b.png", "/tmp/a b.png"], ["image://icon//tmp/a.png", "/tmp/a.png"], ["image://icon/firefox", ""], ["image://qsimage/3", ""], ["firefox", ""], ["", ""], ["file://%E0%A4%A", ""]])
        assert.equal(logic.localImageFile(value), want, "local file of " + JSON.stringify(value));
    same(logic.drawnImage("image://icon//tmp/a.png"), "file:///tmp/a.png");
    same(logic.drawnImage("firefox"), "firefox");
    const entry = stored(1000, 7, { appIcon: "file:///usr/share/icons/chat.png", image: "image://qsimage/3" });
    same(logic.persistable(entry, IMAGES), {
        entry: stored(1000, 7, { appIcon: "file://" + IMAGES + "/1000-7-appIcon", image: "" }),
        copies: [{ from: "/usr/share/icons/chat.png", to: IMAGES + "/1000-7-appIcon" }]
    }, "a file is copied, an in-process image dropped");
    const again = logic.persistable(logic.persistable(entry, IMAGES).entry, IMAGES);
    same(again.copies, [], "an entry already pointing at its copies needs none");
    same(logic.persistable(stored(1, 2, { appIcon: "chat" }), IMAGES).entry.appIcon, "chat", "an icon name stays a name");
    same(logic.ownedImages([again.entry, stored(5, 1, { image: "file://" + IMAGES + "/5-1-image" }), stored(6, 1, { image: "file:///elsewhere/6-1-image.png" })]), ["1000-7-appIcon", "5-1-image"]);

    // The state file's judge.
    for (const [label, text, want] of STATE_REFUSED)
        same(logic.parseState(text), { ok: false, error: want }, "state: " + label);
    const good = { version: 2, boot: BOOT, dnd: true, readBefore: 50, live: [stored(9, 2, { deadline: 99 })], history: [stored(5, 1)] };
    same(logic.parseState(JSON.stringify(good)), { ok: true, state: { boot: BOOT, dnd: true, readBefore: 50, live: good.live, history: good.history } });
    // An entry stored before senders could add hints has no hint roles,
    // and reads back with each one empty.
    const unhinted = (timestamp, id) => (({ hintIcon, hintTone, hintOpen, hintClick, ...rest }) => rest)(stored(timestamp, id));
    same(logic.parseState(stateText({ live: [unhinted(8, 4)], history: [unhinted(7, 3)] })), { ok: true, state: { boot: BOOT, dnd: false, readBefore: 0, live: [stored(8, 4)], history: [stored(7, 3)] } }, "entries without hint roles read back with each empty");
    same(logic.parseState(logic.serializeState(logic.emptyState(BOOT))), { ok: true, state: { boot: BOOT, dnd: false, readBefore: 0, live: [], history: [] } }, "an empty state reads back");
    same(logic.parseState(logic.serializeState({ boot: BOOT, dnd: true, readBefore: 50, live: good.live, history: good.history })).state, { boot: BOOT, dnd: true, readBefore: 50, live: good.live, history: good.history }, "a state reads back as written");

    // A start after a reboot: the same boot keeps everything; another boot
    // clears the toasts and the history and keeps Silence and Mark read.
    const earlier = { boot: "other-boot", dnd: true, readBefore: 50, live: [stored(9, 2)], history: [stored(5, 1), stored(4, 3)] };
    same(logic.fromBoot(earlier, "other-boot"), { state: earlier, cleared: 0 }, "the same boot keeps the state");
    same(logic.fromBoot(earlier, BOOT), { state: { boot: BOOT, dnd: true, readBefore: 50, live: [], history: [] }, cleared: 3 }, "another boot clears the toasts and the history");
    same(logic.fromBoot(Object.assign({}, earlier, { dnd: false, readBefore: 0 }), BOOT).state, { boot: BOOT, dnd: false, readBefore: 0, live: [], history: [] }, "another boot keeps Silence off and no Mark read");

    // Restart: a toast whose time ran out goes into the history; one that
    // survives restarts with a whole lifetime as a deadline.
    const now = 100000;
    const plan = logic.restorePlan([
        stored(now - 9000, 1),
        stored(now - 3000, 2),
        stored(now - 60000, 3, { urgency: U.critical }),
        stored(now - 60000, 4, { deadline: now + 500 }),
        stored(now - 1000, 5, { deadline: now - 1 }),
        stored(now - 60000, 6, { urgency: U.low, remaining: 2000 })
    ], now, 8000);
    same(plan.expired.map(e => e.key), [(now - 9000) + "-1", (now - 1000) + "-5"]);
    same(plan.show.map(e => [e.key, e.deadline === undefined ? null : e.deadline]), [[(now - 3000) + "-2", now + 8000], [(now - 60000) + "-3", null], [(now - 60000) + "-4", now + 8000], [(now - 60000) + "-6", now + 5000]], "a paused clock has not run out");
    assert.equal("remaining" in plan.show[3], false, "a toast shown again keeps no paused time");
    same(logic.clockFields({ remaining: 400, since: null }), { remaining: 400 });
    same(logic.clockFields({ remaining: 400, since: 1000 }), { deadline: 1400 });
    assert.equal("deadline" in plan.expired[1], false, "an expired entry leaves its deadline behind");

    // History: newest first, each key once, a hundred at most, none 24
    // hours old.
    const AGE = 24 * 3600 * 1000;
    const pushed = logic.pushHistory([stored(10, 1), stored(5, 2)], [stored(10, 1, { summary: "again" }), stored(20, 3, { deadline: 5 })], 1000);
    same(pushed.history.map(e => [e.key, e.summary]), [["20-3", "s3"], ["10-1", "again"], ["5-2", "s2"]]);
    assert.equal("deadline" in pushed.history[0], false, "the history keeps no deadline");
    const full = Array.from({ length: 100 }, (_, i) => stored(10000 - i, i));
    const over = logic.pushHistory(full, [stored(20000, 5000)], 20000);
    same([over.history.length, over.history[0].key, over.history[99].key, over.dropped.map(e => e.key)], [100, "20000-5000", "9902-98", ["9901-99"]], "the oldest goes past the limit");
    same(logic.pushHistory(full.slice(0, 99), [stored(20000, 5000)], 20000).history.length, 100, "the history holds a hundred");
    // Age: an entry exactly 24 hours old at `now` is gone, one a
    // millisecond younger stays.
    const at = 5 * AGE;
    const ages = [stored(at - 1000, 1), stored(at - AGE + 1, 2), stored(at - AGE, 3), stored(at - AGE - 5000, 4)];
    same(logic.pruneHistory(ages, at).map(e => e.key), [(at - 1000) + "-1", (at - AGE + 1) + "-2"], "the age prune");
    const agedPush = logic.pushHistory(ages.slice(1), [stored(at, 9)], at);
    same([agedPush.history.map(e => e.originalId), agedPush.dropped.map(e => e.originalId)], [[9, 2], [3, 4]], "a push lets the aged entries go");
    assert.equal(logic.historyDue(ages), at - AGE - 5000 + AGE, "the next prune is due when the oldest entry comes of age");
    assert.equal(logic.historyDue([stored(7, 1), stored(9, 2), stored(8, 3)]), 7 + AGE, "the oldest entry wherever it stands");
    assert.equal(logic.historyDue([]), null, "an empty history is due no prune");

    // Panels: the inbox after the cutoff, the history whole, neither with an
    // entry 24 hours old.
    const kept = Array.from({ length: 60 }, (_, i) => stored(600 - i, i));
    same(logic.panelRows(kept, "inbox", 590, 1000).map(e => e.timestamp), [600, 599, 598, 597, 596, 595, 594, 593, 592, 591]);
    same(logic.panelRows(kept, "history", 590, 1000).length, 60);
    same(logic.panelRows(kept, "inbox", 0, 1000).length, 60);
    same(logic.panelRows([], "inbox", 0, 1000), []);
    same(logic.panelRows(kept, "history", 0, 590 + AGE).map(e => e.timestamp), [600, 599, 598, 597, 596, 595, 594, 593, 592, 591], "the history panel leaves out an entry 24 hours old");
    same(logic.panelRows(kept, "inbox", 595, 590 + AGE).map(e => e.timestamp), [600, 599, 598, 597, 596], "the inbox leaves out an entry 24 hours old");
    for (const [mode, count, state, want] of [["inbox", 0, "loaded", "No unread notifications"], ["history", 0, "absent", "No saved notifications"], ["inbox", 1, "loaded", "1 notification"], ["history", 3, "loaded", "3 notifications"], ["inbox", 2, "corrupt", "Saved history is damaged"], ["history", 2, "unreadable", "Saved history cannot be read"], ["inbox", 2, "pending", "Loading saved history"], ["history", 2, "future-private-reason", "Saved history is unavailable"]])
        assert.equal(logic.panelSubtitle(mode, count, state), want, `subtitle ${mode} ${count} ${state}`);

    // Eviction: the oldest that is not critical, or the oldest of all.
    assert.equal(logic.evictionKey([{ key: "new", urgency: U.normal }, { key: "mid", urgency: U.low }, { key: "old", urgency: U.critical }]), "mid");
    assert.equal(logic.evictionKey([{ key: "new", urgency: U.critical }, { key: "old", urgency: U.critical }]), "old");
    assert.equal(logic.evictionKey([]), "");

    // Actions: the sender's own, Show when it has none and a window is open,
    // and Dismiss.
    same(logic.actionsFor([{ identifier: "default", text: "" }, { identifier: "reply", text: "Reply" }, { identifier: "", text: "x" }], true), [{ id: "action:default", label: "Open" }, { id: "action:reply", label: "Reply" }, { id: "dismiss", label: "Dismiss" }]);
    same(logic.actionsFor([], true), [{ id: "open", label: "Show" }, { id: "dismiss", label: "Dismiss" }]);
    same(logic.actionsFor([], false), [{ id: "dismiss", label: "Dismiss" }]);

    // Choices: [label, choice, offered, plan]. Opening delivers default,
    // else the first action offered, and a pill its own action while it is
    // offered; both raise either way; dismissing does neither.
    for (const [label, choice, offered, want] of [
        ["open while held", "open", ["default", "reply"], { deliver: "default", raise: true, leave: "invoke" }],
        ["open with nothing held", "open", [], { deliver: "", raise: true, leave: "invoke" }],
        ["open when the sender offers no default runs its first action", "open", ["reply"], { deliver: "reply", raise: true, leave: "invoke" }],
        ["open prefers default over an earlier action", "open", ["reply", "default"], { deliver: "default", raise: true, leave: "invoke" }],
        ["open skips an action with no identifier", "open", ["", "reply"], { deliver: "reply", raise: true, leave: "invoke" }],
        ["the default action's pill opens", "action:default", ["default"], { deliver: "default", raise: true, leave: "invoke" }],
        ["another action raises too", "action:reply", ["default", "reply"], { deliver: "reply", raise: true, leave: "invoke" }],
        ["an action no longer offered still raises", "action:reply", [], { deliver: "", raise: true, leave: "invoke" }],
        ["dismiss", "dismiss", ["default"], { deliver: "", raise: false, leave: "dismiss" }],
        ["a choice no card offers", "focus", ["default"], null],
        ["an action with no identifier", "action:", ["default"], null]
    ])
        same(logic.choicePlan(choice, offered), want, "choice: " + label);

    // Holding: [reason, transient, fate].
    for (const [reason, transient, want] of [
        ["expire", false, "keep"], ["expire", true, "expire"], ["invoke", false, "dismiss"], ["invoke", true, "dismiss"],
        ["dismiss", false, "dismiss"], ["closed", false, "drop"], ["fade", false, null]
    ])
        assert.equal(logic.heldAfterLeave(reason, transient), want, `held after ${reason} transient=${transient}`);
    same(logic.heldPastHistory(["a", "b", "c", "d"], [stored(1, 1, { key: "a" })], [stored(2, 2, { key: "c" })]), ["b", "d"], "held past the history");
    same(logic.heldPastHistory([], [], []), [], "nothing held");

    // The sender's windows: [label, windows, entry, addresses]. Those of
    // its desktop entry, else of its name, case folded; for a browser's web
    // notification that names neither, the browser windows naming its site,
    // else every browser window.
    const named = [{ address: "abc", appClass: "Firefox" }, { address: "0xdef", appClass: "org.chat.App" }, { address: "", appClass: "chat" }, { address: "0x1", appClass: "Firefox" }];
    const slackDesk = { address: "0x5", appClass: "Slack" };
    const chromium = { address: "0x7", appClass: "chromium" };
    const brave = { address: "0x8", appClass: "brave-browser" };
    const webApp = { address: "0x9", appClass: "chrome-app.slack.com__client-Default" };
    const browserSlack = { desktopEntry: "", app: "", appIcon: "", body: "app.slack.com\n\nada: hi" };
    for (const [label, windows, entry, want] of [
        ["by desktop entry before the name", named, { desktopEntry: "org.chat.app", app: "Firefox" }, ["0xdef"]],
        ["every window of the name, the address prefixed", named, { desktopEntry: "", app: "firefox" }, ["0xabc", "0x1"]],
        ["a window with no address yet", named, { desktopEntry: "", app: "chat" }, []],
        ["the command line owns no window", named, { desktopEntry: "", app: "notify-send" }, []],
        ["no window", [], { desktopEntry: "x", app: "y" }, []],
        ["Slack's desktop copy raises Slack", [slackDesk, chromium], { desktopEntry: "slack", app: "Slack", body: "ada: hi" }, ["0x5"]],
        ["Slack's browser copy raises the browser, not Slack", [slackDesk, chromium], browserSlack, ["0x7"]],
        ["an installed web app naming the site wins", [slackDesk, chromium, webApp], browserSlack, ["0x9"]],
        ["every browser when none names the site", [chromium, brave], browserSlack, ["0x7", "0x8"]],
        ["no browser open", [slackDesk], browserSlack, []],
        ["a named browser by its desktop entry", [chromium, brave], { desktopEntry: "brave-browser", app: "Brave", body: "app.slack.com hi" }, ["0x8"]],
        ["a sender that is no browser keeps its body", [chromium], { desktopEntry: "", app: "Chat", body: "app.slack.com\n\nhi" }, []]
    ])
        same(logic.senderWindows(windows, entry), want, "sender windows: " + label);

    // Clocks: a paused clock keeps what is left; a running one is charged
    // for the time it ran.
    let clocks = { a: { remaining: 5000, since: null }, b: { remaining: 3000, since: null } };
    clocks = logic.settleClocks(clocks, key => key === "a", 1000);
    same(clocks, { a: { remaining: 5000, since: 1000 }, b: { remaining: 3000, since: null } });
    same(logic.nextExpiry(clocks, 2000), { key: "a", wait: 4000 });
    clocks = logic.settleClocks(clocks, () => false, 2500);
    same(clocks, { a: { remaining: 3500, since: null }, b: { remaining: 3000, since: null } }, "a clock that stops is charged");
    assert.equal(logic.nextExpiry(clocks, 3000), null, "no running clock runs out");
    clocks = logic.settleClocks(clocks, () => true, 3000);
    same(logic.nextExpiry(clocks, 6100), { key: "b", wait: 0 }, "an overdue clock waits no longer");
    same(logic.settleClocks(clocks, () => true, 9999), JSON.parse(JSON.stringify(clocks)), "a running clock that keeps running is left");

    // Silence over IPC.
    for (const [arg, current, want] of [["on", false, { ok: true, dnd: true }], ["OFF", true, { ok: true, dnd: false }], ["toggle", true, { ok: true, dnd: false }], ["", true, { ok: true, dnd: true }], ["loud", false, { ok: false }]])
        same(logic.silenceArgument(arg, current), want, "silence " + JSON.stringify(arg));

    // Enrichment: what a card draws for a sender a rule reads.
    for (const [label, app, entry, summary, body, want] of ENRICHED)
        same(logic.enrich(app, entry, "", summary, body), want, "enrich: " + label);
    for (const [app, icon, body, want] of [["", "", "app.slack.com\n\nhi", "app.slack.com"], ["Chromium", "", "Chat.Example.com hi", "chat.example.com"], ["", "chromium", "https://a.example.org/x hi", "a.example.org"], ["Chat", "", "app.slack.com\n\nhi", ""], ["", "", "hi", ""]])
        assert.equal(logic.webOrigin(app, icon, body), want, "web origin of " + JSON.stringify([app, icon, body]));
    for (const [name, want] of [["Ada Lovelace", "AL"], ["ada", "A"], ["Ada (she/her)", "A"], ["Grace B. Hopper (Navy)", "GH"], ["@ada", "A"], ["\u{1F600} Bot", "\u{1F600}B"], ["", "?"], ["(x)", "?"]])
        assert.equal(logic.initialsOf(name), want, "initials of " + JSON.stringify(name));
    // Face tints, as Python worked them out from the stated hash.
    for (const [name, want] of [["ada", "magenta"], ["Ada", "magenta"], [" ada ", "magenta"], ["grace", "rose"], ["alan", "blue"], ["edsger", "teal"], ["barbara", "green"], ["", "coral"]])
        assert.equal(logic.faceTint(name), want, "tint of " + JSON.stringify(name));
    same(Object.keys(appearance.TOKENS.face.tint), ["coral", "amber", "green", "blue", "indigo", "magenta", "teal", "rose"], "the look holds every tint");
    same(logic.FACE_TINTS, ["coral", "amber", "green", "blue", "indigo", "magenta", "teal", "rose"]);
    // The media slot's tier: one line is compact, anything more regular.
    for (const [lines, want] of [[0, "compact"], [1, "compact"], [2, "regular"], [5, "regular"]])
        assert.equal(logic.mediaTier(lines), want, "tier of " + lines + " lines");
    // A card's QML uses this step when it places rectangular text past a
    // rounded end.
    assert.equal(appearance.TOKENS.radius.clearance.type, "length");
    assert.equal(appearance.TOKENS.radius.clearance.value, 4);
    same(logic.workspaceRuleIds(), ["slack"]);
    assert.equal(logic.enricherById("slack").id, "slack");
    assert.equal(logic.enricherById("none"), null);

    // Slack's workspace list: team-id order, the larger icon first, unsafe
    // ids and nameless entries skipped and counted.
    const index = { workspaces: {
        T2: { domain: "globex", name: "Globex", icon: { image_68: "https://a/g68.png", image_88: "https://a/g88.png" } },
        T1: { domain: "acme", name: "Acme Corp", icon: { image_68: "https://a/a68.png" } },
        "../x": { domain: "evil", name: "Evil" },
        T3: { domain: "", name: "" },
        T4: { domain: "initech", icon: { image_88: "http://a/plain.png", image_68: "https://a/has space.png" } }
    } };
    same(logic.slackWorkspaces(JSON.stringify(index)), { ok: true, skipped: 2, workspaces: [
        { id: "T1", domain: "acme", name: "Acme Corp", names: ["acme", "Acme Corp"], urls: ["https://a/a68.png"] },
        { id: "T2", domain: "globex", name: "Globex", names: ["globex", "Globex"], urls: ["https://a/g88.png", "https://a/g68.png"] },
        { id: "T4", domain: "initech", name: "", names: ["initech"], urls: [] }
    ] });
    same(logic.slackWorkspaces("{"), { ok: false, error: "not-json" });
    same(logic.slackWorkspaces("{\"workspaces\": []}"), { ok: false, error: "workspaces want=object" });
    const many = { workspaces: {} };
    for (let i = 10; i < 30; i++) many.workspaces["T" + i] = { domain: "w" + i };
    same(logic.slackWorkspaces(JSON.stringify(many)).workspaces.map(w => w.id), Array.from({ length: 16 }, (_, i) => "T" + (10 + i)), "the list is cut at its limit");
    const listed = logic.slackWorkspaces(JSON.stringify(index)).workspaces;
    same(logic.workspaceCopies(listed, "/c"), [{ to: "/c/T1-0", url: "https://a/a68.png" }, { to: "/c/T2-0", url: "https://a/g88.png" }, { to: "/c/T2-1", url: "https://a/g68.png" }]);
    const icons = logic.workspaceIconMap(listed, "/c", ["/c/T2-1?v=0123456789abcdef", "/c/T9-0?v=abcdef0123456789"]);
    same(icons, { acme: "", "acme corp": "", globex: "file:///c/T2-1?v=0123456789abcdef", initech: "" }, "a workspace answers to its first copied icon, by domain and by name");
    same(logic.workspaceIconMap([{ id: "A", names: ["x"], urls: ["u"] }, { id: "B", names: ["X"], urls: ["u"] }], "/c", ["/c/B-0?v=0123456789abcdef"]), { x: "" }, "a shared name keeps the first workspace");
    // Reading the list again: [label, workspace, last read, now, want].
    for (const [label, workspace, loadedAt, now, want] of [
        ["one with an icon", "Globex", 0, 999999, false],
        ["one the list does not name", "hooli", 1000, 61000, true],
        ["one the list does not name, read a moment ago", "hooli", 1000, 60999, false],
        ["one with no icon", "acme", 0, 60000, true],
        ["no workspace", "", 0, 999999, false]
    ])
        assert.equal(logic.workspaceReload(icons, workspace, loadedAt, now), want, "reload for " + label);

    const photoCache = {
        status: "loaded",
        teams: [{
            id: "T1",
            names: ["acme", "Acme Corp"],
            icon: "file:///cache/T1/workspace.png?v=0123456789abcdef",
            users: [
                { id: "U1", names: ["Ada Lovelace", "ada"], photo: "file:///cache/T1/users/U1.png?v=abcdef0123456789" },
                { id: "U2", names: ["Grace Hopper"], photo: "file:///cache/T1/users/U2.png?v=1234567890abcdef" },
                { id: "U3", names: ["No Photo"], photo: "" }
            ],
            account: "slack:T1"
        }, {
            id: "T2",
            names: ["globex"],
            icon: "",
            users: [
                { id: "U7", names: ["Grace Hopper"], photo: "file:///cache/T2/users/U7.png?v=7777777777777777" },
                { id: "U8", names: ["Edsger"], photo: "file:///cache/T2/users/U8.png?v=8888888888888888" }
            ],
            account: "slack:T2"
        }]
    };
    same(logic.slackPhotos(JSON.stringify(photoCache)), { ok: true, status: "loaded", generatedAt: 0, downloadFailed: 0, stale: false, teams: photoCache.teams, emoji: null }, "a Slack photo cache is accepted");
    same(logic.slackPhotos(JSON.stringify({ status: "absent" })), { ok: true, status: "absent", generatedAt: 0, downloadFailed: 0, stale: false, teams: [], emoji: null }, "no token leaves no cache");
    same(logic.slackPhotos("{"), { ok: false, error: "not-json" });
    same(logic.slackPhotos(JSON.stringify({ status: "stale" })), { ok: false, error: "status want=loaded|absent|off" });
    same(logic.slackPhotos(JSON.stringify({ status: "loaded", teams: [{ id: "../x", names: ["x"], users: [], account: "slack:T2" }] })), { ok: false, error: "teams.0.id want=safe" });
    same(logic.slackPhotos(JSON.stringify({ status: "loaded", teams: [{ id: "T1", names: ["x"], users: [] }] })), { ok: false, error: "teams.0.account want=slack:<team id>" }, "a team names the account that served it");
    same(logic.slackPhotos(JSON.stringify({ status: "loaded", teams: [{ id: "T1", names: ["x"], users: [], account: "slack:../x" }] })), { ok: false, error: "teams.0.account want=slack:<team id>" });
    same(logic.slackPhotos(JSON.stringify({ status: "loaded", generatedAt: 123, downloadFailed: 2, stale: true, teams: [{ id: "T1", names: ["acme"], users: [{ id: "U1", names: ["Ada"], photo: "https://example.test/a.png" }], account: "slack:T1" }] })), { ok: true, status: "loaded", generatedAt: 123, downloadFailed: 2, stale: true, teams: [{ id: "T1", names: ["acme"], icon: "", users: [{ id: "U1", names: ["Ada"], photo: "" }], account: "slack:T1" }], emoji: null }, "a non-file photo is ignored");
    same(logic.slackPhotos(JSON.stringify({ status: "loaded", teams: [{ id: "T1", names: ["acme"], icon: "file:///cache/T1/workspace.png", users: [{ id: "U1", names: ["Ada"], photo: "file:///cache/T1/U1.png" }], account: "slack:T1" }] })).teams, [{ id: "T1", names: ["acme"], icon: "", users: [{ id: "U1", names: ["Ada"], photo: "" }], account: "slack:T1" }], "an unversioned file URL is ignored");
    const teams = photoCache.teams;
    const group = logic.enrich("Slack", "slack", "", "[acme] in Ada Lovelace, Grace Hopper, No Photo", "Ada Lovelace: hi");
    same(logic.slackFaceImages(group, teams, "file:///sender.png", "acme"), ["file:///cache/T1/users/U1.png?v=abcdef0123456789", "file:///cache/T1/users/U2.png?v=1234567890abcdef", ""], "each Slack face takes its own photo from its workspace");
    same(logic.slackFaceImages(group, teams, "file:///sender.png", "unknown"), ["file:///sender.png", "", ""], "an unknown workspace has no photos");
    same(logic.slackFaceImages(group, teams, "", ""), ["file:///cache/T1/users/U1.png?v=abcdef0123456789", "", ""], "with no workspace a face takes the photo of the one team holding the name, and none when two do");
    const direct = logic.enrich("Slack", "slack", "", "New message from Ada", "hi");
    same(logic.slackFaceImages(direct, [{ id: "T1", names: ["acme"], icon: "", users: [{ id: "U1", names: ["Ada"], photo: "file:///first.png?v=1111111111111111" }, { id: "U2", names: ["ADA"], photo: "file:///second.png?v=2222222222222222" }], account: "slack:T1" }], "", "acme"), ["file:///first.png?v=1111111111111111"], "the first duplicate name owns the photo");
    // Slack labels some of a bot's posts "<name> (bot)": a cached bot's
    // photo answers to both, and a person's photo to its own names alone.
    const flagshipPhoto = "file:///cache/T1/users/UF.png?v=f1a9f1a9f1a9f1a9";
    const flagshipCache = bot => ({ status: "loaded", teams: [{ id: "T1", names: ["acme"], icon: "", users: [Object.assign({ id: "UF", names: ["flagship"], photo: flagshipPhoto }, bot)], account: "slack:T1" }, { id: "T2", names: ["globex"], icon: "", users: [], account: "slack:T2" }] });
    const labelled = logic.enrich("Slack", "slack", "", "[acme] in bradm-master", "flagship (bot): VGS-1046: 1 group tabs");
    const plain = logic.enrich("Slack", "slack", "", "[acme] in bradm-master", "flagship: The VM move is ready");
    const unlabelled = name => logic.enrich("", "", "", "New message in bradm-master", "app.slack.com\n\n" + name + ": hi");
    for (const [label, bot, wantLabelled] of [
        ["a bot", { bot: true }, flagshipPhoto],
        ["a person", { bot: false }, "file:///sender.png"],
        ["a user with no bot field", {}, "file:///sender.png"]
    ]) {
        const read = logic.slackPhotos(JSON.stringify(flagshipCache(bot)));
        assert.equal(read.ok, true, "a cache holding " + label + " is accepted");
        same(read.teams[0].users.map(u => Object.keys(u).sort()), [["id", "names", "photo"]], "the reduced user of " + label + " keeps its shape");
        same(logic.slackFaceImages(labelled, read.teams, "file:///sender.png", "acme"), [wantLabelled], "the (bot) face of " + label);
        same(logic.slackFaceImages(plain, read.teams, "file:///sender.png", "acme"), [flagshipPhoto], "the plain face of " + label);
        assert.equal(logic.slackWorkspaceFor(unlabelled("flagship (bot)"), [], read.teams), wantLabelled === flagshipPhoto ? "acme" : "", "the workspace of the (bot) face of " + label);
        assert.equal(logic.slackWorkspaceFor(unlabelled("flagship"), [], read.teams), "acme", "the workspace of the plain face of " + label);
    }
    assert.equal(logic.slackWorkspaceIcon(teams, "acme"), "file:///cache/T1/workspace.png?v=0123456789abcdef");
    assert.equal(logic.slackWorkspaceIcon(teams, ""), "", "no workspace has no icon");

    // The workspace of a card: [label, enrichment, Slack's list, photo teams, want].
    const acmeOnly = [{ id: "T1", names: ["acme", "Acme Corp"] }];
    const bothListed = [{ id: "T1", names: ["acme"] }, { id: "T2", names: ["globex"] }];
    const browserFrom = name => logic.enrich("", "", "", "New message in eng", "app.slack.com\n\n" + name + ": hi");
    for (const [label, enrichment, list, cached, want] of [
        ["the workspace the summary names", group, bothListed, teams, "acme"],
        ["the only workspace Slack lists", browserFrom("Nobody"), acmeOnly, [], "acme"],
        ["the only workspace the photo cache holds", browserFrom("Nobody"), [], [teams[1]], "globex"],
        ["one workspace in both", browserFrom("Nobody"), acmeOnly, [teams[0]], "acme"],
        ["the one team holding the sender", browserFrom("Edsger"), bothListed, teams, "globex"],
        ["two teams holding the sender", browserFrom("Grace Hopper"), bothListed, teams, ""],
        ["no team holding the sender", browserFrom("Nobody"), bothListed, teams, ""],
        ["no sender", logic.enrich("", "", "", "New message in eng", "app.slack.com\n\nshipped"), bothListed, teams, ""],
        ["no rule", null, acmeOnly, teams, ""]
    ])
        assert.equal(logic.slackWorkspaceFor(enrichment, list, cached), want, "workspace for " + label);
    // The probe's stdout: one line per workspace account, and anything else refused.
    const TOKEN_OUTPUTS = [
        ["slack-token: account=slack:T1 present\n", { ok: true, states: { "slack:T1": "present" } }],
        ["slack-token: account=slack:T1 locked\nslack-token: account=slack:T2 absent\n", { ok: true, states: { "slack:T1": "locked", "slack:T2": "absent" } }],
        ["slack-token: account=slack:T1 unavailable reason=search-failed status=1", { ok: true, states: { "slack:T1": "unavailable" } }],
        ["slack-token: account=slack:T1 unsafe\n", { ok: false, error: "line.0.state unknown" }],
        ["slack-token: account=slack:T1 presently\n", { ok: false, error: "line.0.state unknown" }],
        ["slack-token: account=slack:../x present\n", { ok: false, error: "line.0.account unknown" }],
        ["slack-token: account=other present\n", { ok: false, error: "line.0.account unknown" }],
        ["slack-token: account=slack:T1 present\nslack-token: account=slack:T1 absent\n", { ok: false, error: "line.1.account duplicate" }],
        ["secret = xoxp-1\nslack-token: account=slack:T1 present\n", { ok: false, error: "line.0 unknown" }],
        ["slack-token: present\n", { ok: false, error: "line.0 unknown" }],
        ["slack-token: account=slack:T1 present!\n", { ok: false, error: "line.0 unknown" }],
        ["> slack-token: account=slack:T1 present\n", { ok: false, error: "line.0 unknown" }],
        ["", { ok: true, states: {} }]
    ];
    for (const [text, want] of TOKEN_OUTPUTS) same(logic.slackTokenStates(text), want, "slackTokenStates " + JSON.stringify(text));

    // The Settings rows: one per listed workspace.
    const listedTwo = [{ id: "T1", domain: "acme", name: "Acme Corp" }, { id: "T2", domain: "globex", name: "" }];
    same(logic.slackTokenRows(listedTwo, { "slack:T1": "present", "slack:T2": "locked" }), { ok: true, items: [
        { label: "Acme Corp (acme)", value: "present", secret: "slack:T1" },
        { label: "globex", value: "locked", secret: "slack:T2" }
    ] }, "each workspace carries its own account's state");
    same(logic.slackTokenRows([], {}), { ok: true, items: [] }, "no workspace lists no token row");
    same(logic.slackTokenRows(listedTwo, { "slack:T1": "present" }), { ok: false, missing: "slack:T2" }, "a workspace the probe has not answered for waits");
    for (const [label, workspace, want] of [
        ["a name equal to its domain", { id: "T1", domain: "acme", name: "ACME" }, "ACME"],
        ["a name with a control character", { id: "T1", domain: "acme", name: "Acme\nCorp" }, "Acme Corp (acme)"],
        ["neither printable", { id: "T1", domain: "\u0007", name: "" }, "T1"],
        ["a label past sixty characters", { id: "T1", domain: "d", name: "x".repeat(70) }, "x".repeat(59) + "\u2026"],
        // Sixty UTF-16 code units, as the core's judge counts: thirty emoji
        // are sixty units in thirty code points.
        ["a label of sixty code units in emoji", { id: "T1", domain: "", name: "\u{1F680}".repeat(30) }, "\u{1F680}".repeat(30)],
        ["a label past sixty code units in emoji", { id: "T1", domain: "", name: "\u{1F680}".repeat(31) }, "\u{1F680}".repeat(29) + "\u2026"],
        ["a cut that would split a surrogate pair", { id: "T1", domain: "", name: "x" + "\u{1F680}".repeat(40) }, "x" + "\u{1F680}".repeat(29) + "\u2026"]
    ])
        assert.equal(logic.slackWorkspaceLabel(workspace), want, "label of " + label);
    // A workspace with a long emoji name still yields token rows the core's
    // status judge takes.
    const emojiRows = logic.slackTokenRows([{ id: "T1", domain: "rocket", name: "\u{1F680} launch ".repeat(12) }, { id: "T2", domain: "", name: "\u{1F680}".repeat(45) }], { "slack:T1": "present", "slack:T2": "absent" });
    assert.equal(emojiRows.ok, true);
    assert.equal(emojiRows.items.every(item => item.label.length <= 60), true, "every label fits sixty code units");
    assert.equal(pluginLogic.statusValueFits("presenceList", JSON.parse(JSON.stringify(emojiRows.items))), true, "the core's judge takes the rows of long emoji names");
    // The rows fit the plugin's own declaration: its `secrets` let each item
    // name its account, so the core's write judge takes them.
    const manifest = pluginLogic.validateManifest(JSON.parse(fs.readFileSync(path.join(__dirname, "..", "shell", "plugins", "vgs.notifications", "manifest.json"), "utf8")), "/x");
    assert.equal(manifest.ok, true, "the notifications manifest is accepted");
    assert.equal(pluginLogic.statusWrite(manifest.manifest, {}, "slackTokens", JSON.parse(JSON.stringify(emojiRows.items))).ok, true, "the core's write judge takes the rows with their accounts");

    // The photo helper's next run: [label, read, listed, want].
    const DAY = 24 * 60 * 60 * 1000, RETRY = 15 * 60 * 1000, NOW = 10 * DAY;
    const loaded = extra => Object.assign({ ok: true, status: "loaded", generatedAt: NOW - 1000, downloadFailed: 0, stale: false, teams: [{ id: "T1" }, { id: "T2" }] }, extra);
    for (const [label, read, listed, want] of [
        ["every listed workspace loaded", loaded({}), listedTwo, DAY - 1000],
        ["a listed workspace without photos", loaded({ teams: [{ id: "T1" }] }), listedTwo, RETRY],
        ["a cached team without a listed workspace", loaded({ teams: [{ id: "T1" }] }), [], DAY - 1000],
        ["a stale answer", loaded({ stale: true }), listedTwo, RETRY],
        ["a failed download", loaded({ downloadFailed: 1 }), listedTwo, RETRY],
        ["no token", { ok: true, status: "absent", teams: [], generatedAt: 0, downloadFailed: 0, stale: false }, [], RETRY],
        ["a refused answer", { ok: false, error: "not-json" }, [], RETRY],
        ["a day already over", loaded({ generatedAt: NOW - 2 * DAY }), listedTwo, 1000]
    ])
        assert.equal(logic.slackPhotoDelay(read, listed, NOW, false, true), want, "next photo run with " + label);

    // With custom emoji on: pending emoji bring the run within a minute,
    // and the cache is read again within the hour.
    const MINUTE = 60 * 1000, HOUR = 60 * MINUTE;
    for (const [label, read, want] of [
        ["emoji waiting to be converted", loaded({ emoji: [{ team: "T1", map: {}, pending: 3 }] }), MINUTE],
        ["every emoji converted", loaded({ emoji: [{ team: "T1", map: {}, pending: 0 }] }), HOUR],
        ["a photo retry sooner than the rescan", loaded({ stale: true, emoji: [] }), RETRY],
        ["a refused answer", { ok: false, error: "not-json" }, RETRY]
    ])
        assert.equal(logic.slackPhotoDelay(read, listedTwo, NOW, true, true), want, "next run with emoji on and " + label);
    assert.equal(logic.slackPhotoDelay(loaded({ emoji: [{ team: "T1", map: {}, pending: 3 }] }), listedTwo, NOW, false, true), DAY - 1000, "emoji off leave the photos' day");

    // With the Slack photos setting off no photo schedule runs: the emoji keep
    // theirs, and with emoji off too the sweeping run is the last.
    const offRead = extra => Object.assign({ ok: true, status: "off", teams: [], generatedAt: 0, downloadFailed: 0, stale: false, emoji: null }, extra);
    for (const [label, read, emojiOn, want] of [
        ["emoji waiting to be converted", offRead({ emoji: [{ team: "T1", map: {}, pending: 3 }] }), true, MINUTE],
        ["every emoji converted", offRead({ emoji: [{ team: "T1", map: {}, pending: 0 }] }), true, HOUR],
        ["a refused answer with emoji on", { ok: false, error: "not-json" }, true, RETRY],
        ["emoji off", offRead({}), false, null],
        ["a refused answer with emoji off", { ok: false, error: "not-json" }, false, null],
        ["a workspace without photos", offRead({ emoji: [] }), true, HOUR]
    ])
        assert.equal(logic.slackPhotoDelay(read, listedTwo, NOW, emojiOn, false), want, "next run with the photos setting off and " + label);

    // The helper's argv: --photos only with the extra on, --emoji with its
    // cache only with emoji on, the team ids last.
    for (const [label, photos, emoji, want] of [
        ["both off", false, false, ["node", "/p/slack-photos.js", "refresh", "/c", "T1", "T2"]],
        ["the photos setting on", true, false, ["node", "/p/slack-photos.js", "refresh", "/c", "--photos", "T1", "T2"]],
        ["custom emoji on", false, true, ["node", "/p/slack-photos.js", "refresh", "/c", "--emoji", "/s/Cache_Data", "T1", "T2"]],
        ["both on", true, true, ["node", "/p/slack-photos.js", "refresh", "/c", "--photos", "--emoji", "/s/Cache_Data", "T1", "T2"]]
    ])
        same(logic.slackHelperCommand("/p/slack-photos.js", "/c", ["T1", "T2"], photos, emoji, "/s/Cache_Data"), want, "the helper's argv with " + label);
    same(logic.slackPhotos(JSON.stringify({ status: "off" })), { ok: true, status: "off", teams: [], generatedAt: 0, downloadFailed: 0, stale: false, emoji: null }, "a run with the photos setting off is read");

    // The helper's emoji list, and its refusals: [label, emoji, error].
    const HEX = "0123456789abcdef";
    const emojiOut = { status: "absent", emoji: [{ team: "T1", map: { party: HEX, __proto__x: HEX }, count: 2, pending: 0 }] };
    same(logic.slackPhotos(JSON.stringify(emojiOut)).emoji, [{ team: "T1", map: { party: HEX, __proto__x: HEX }, pending: 0 }], "a run's emoji are read");
    const objectNames = JSON.parse("{\"team\":\"T1\",\"pending\":0,\"map\":{\"__proto__\":\"" + HEX + "\",\"constructor\":\"" + HEX + "\",\"tostring\":\"" + HEX + "\"}}");
    const read = logic.slackEmojiTeams([objectNames]);
    assert.equal(read.ok, true);
    assert.deepEqual(Object.keys(read.teams[0].map).sort(), ["__proto__", "constructor", "tostring"], "names like Object's members are own names");
    assert.equal(Object.getPrototypeOf(read.teams[0].map), null);
    for (const [label, emoji, error] of [
        ["not a list", {}, "emoji want=list"],
        ["a team that is not safe", [{ team: "../x", map: {}, pending: 0 }], "emoji.0.team want=safe"],
        ["a name outside the rule", [{ team: "T1", map: { "Party": HEX }, pending: 0 }], "emoji.0.map name want=^[a-z0-9_+-]{1,100}$"],
        ["a name with markup", [{ team: "T1", map: { "<b>": HEX }, pending: 0 }], "emoji.0.map name want=^[a-z0-9_+-]{1,100}$"],
        ["a file that is not hex", [{ team: "T1", map: { party: "../../x" }, pending: 0 }], "emoji.0.map.party want=hex16"],
        ["no pending count", [{ team: "T1", map: {} }], "emoji.0.pending want=count"]
    ]) {
        same(logic.slackEmojiTeams(emoji), { ok: false, error }, "emoji refused: " + label);
        same(logic.slackPhotos(JSON.stringify({ status: "absent", emoji })), { ok: false, error }, "a run with refused emoji is refused: " + label);
    }
    // JSON.parse makes `__proto__` an own name, as the helper's output does.
    const lookups = logic.slackEmojiLookups(logic.slackEmojiTeams(JSON.parse(JSON.stringify([
        { team: "T1", map: { party: HEX, proto: HEX }, pending: 0 },
        { team: "T2", map: { globex: "fedcba9876543210" }, pending: 0 }
    ]).replace("\"proto\"", "\"__proto__\""))).teams, "/cache/slack-photos");
    assert.equal(lookups.T1.party, "file:///cache/slack-photos/T1/emoji/" + HEX + ".png?v=" + HEX, "a name's file URL");
    assert.equal(Object.isFrozen(lookups.T1) && Object.getPrototypeOf(lookups.T1) === null, true, "a lookup is frozen, with no prototype");
    const slackCard = { rule: "slack", faces: [] };
    const listedTeams = [{ id: "T1", names: ["acme", "Acme Corp"] }];
    for (const [label, enrichment, workspace, want] of [
        ["a workspace's domain", slackCard, "acme", "T1"],
        ["a workspace's name, case folded", slackCard, "ACME corp", "T1"],
        ["a photo team", slackCard, "globex", "T2"],
        ["a workspace nobody lists", slackCard, "initech", null],
        ["no workspace", slackCard, "", null],
        ["another rule's card", { rule: "other", faces: [] }, "acme", null]
    ]) {
        const got = logic.slackEmojiFor(lookups, enrichment, listedTeams, [{ id: "T2", names: ["globex"] }], workspace);
        assert.equal(got === null ? null : Object.keys(got).sort().join(","), want === null ? null : Object.keys(lookups[want]).sort().join(","), "emoji of " + label);
    }

    // A body as segments: [label, body, lookup, segments]. The body goes
    // through styledBody first, as the card's does.
    const T1 = lookups.T1;
    const PARTY = T1.party;
    const plainLookup = { party: PARTY };
    const flood = Array.from({ length: 70 }, () => ":party:").join("");
    for (const [label, body, lookup, want] of [
        ["a known custom emoji", "hi :party:!", T1, [{ markup: "hi " }, { image: PARTY, alt: ":party:" }, { markup: "!" }]],
        ["an unknown shortcode", "hi :nope:", T1, [{ markup: "hi :nope:" }]],
        ["another workspace's emoji", "hi :globex:", T1, [{ markup: "hi :globex:" }]],
        ["no lookup", "hi :party:", null, [{ markup: "hi :party:" }]],
        ["escaped markup stays escaped", "&lt;img src=x&gt; :party:", T1, [{ markup: "&lt;img src=x&gt; " }, { image: PARTY, alt: ":party:" }]],
        ["a sender's image tag is stripped", "<img src=\"http://h/x.png\">:party:", T1, [{ image: PARTY, alt: ":party:" }]],
        ["a shortcode inside a tag's attribute", "<a href=\":party:\">go</a>", T1, [{ markup: "<a href=\":party:\">go</a>" }]],
        ["a shortcode inside a link's text", "<a href=\"x\">:party:</a>", T1, [{ markup: "<a href=\"x\">" }, { image: PARTY, alt: ":party:" }, { markup: "</a>" }]],
        ["a shortcode across a tag", ":par<b>ty:</b>", T1, [{ markup: ":par<b>ty:</b>" }]],
        ["a time before a shortcode", "10:30:party:", T1, [{ markup: "10:30" }, { image: PARTY, alt: ":party:" }]],
        ["Object's members are not emoji", ":toString: :constructor: :hasOwnProperty:", plainLookup, [{ markup: ":toString: :constructor: :hasOwnProperty:" }]],
        ["a name like __proto__ the team holds", ":__proto__:", T1, [{ image: T1.__proto__, alt: ":__proto__:" }]],
        ["a line break", "a\n:party:", T1, [{ markup: "a<br/>" }, { image: PARTY, alt: ":party:" }]],
        ["past the cap", flood, T1, Array.from({ length: 64 }, () => ({ image: PARTY, alt: ":party:" })).concat([{ markup: ":party:".repeat(6) }])]
    ])
        same(logic.emojiSegments(logic.styledBody(body, "Slack", ""), lookup), want, "segments of " + label);

    // One message from Slack's own client and from its web client: [label,
    // the first copy, the second, whether they are one message].
    const note = (key, app, summary, body, at) => ({ key, app, appIcon: "", desktopEntry: app === "Slack" ? "slack" : "", summary, body, timestamp: at });
    const desk = note("d", "Slack", "[acme] in master-operator", "fleet: Done: your agent settings", 1000);
    const web = note("w", "", "New message in master-operator", "app.slack.com\n\nfleet: Done:  your agent <b>settings</b>", 4000);
    for (const [label, first, second, want] of [
        ["desktop then browser", desk, web, true],
        ["browser then desktop", web, desk, true],
        ["both from the desktop", desk, Object.assign({}, desk, { key: "d2", timestamp: 2000 }), false],
        ["both from a browser", web, Object.assign({}, web, { key: "w2", timestamp: 5000 }), false],
        ["outside the window", desk, Object.assign({}, web, { timestamp: 11001 }), false],
        ["at the window's edge", desk, Object.assign({}, web, { timestamp: 11000 }), true],
        ["another conversation", desk, Object.assign({}, web, { summary: "New message in eng" }), false],
        ["another sender", desk, Object.assign({}, web, { body: "app.slack.com\n\nada: Done: your agent settings" }), false],
        ["another text", desk, Object.assign({}, web, { body: "app.slack.com\n\nfleet: Done" }), false],
        ["two named workspaces", desk, Object.assign({}, web, { summary: "[globex] in master-operator" }), false],
        ["the same named workspace", desk, Object.assign({}, web, { summary: "[acme] in master-operator" }), true],
        ["no rule", note("a", "Chat", "hi", "x", 1000), note("b", "", "hi", "chat.example.com\n\nx", 2000), false]
    ]) {
        const a = logic.messageOf(first), b = logic.messageOf(second);
        assert.equal(a !== null && b !== null && logic.duplicateOf(logic.rememberMessage([], a), b) !== null, want, "one message: " + label);
    }
    same(logic.messageOf(web), { key: "w", rule: "slack", source: "browser", conversation: "in master-operator", sender: "fleet", text: "fleet: Done: your agent settings", workspace: "", at: 4000 });
    for (const [label, prior, message, onScreen, want] of [
        ["a desktop copy after a browser card still on screen", "browser", "desktop", true, "message"],
        ["a desktop copy after a browser card that left", "browser", "desktop", false, "prior"],
        ["a browser copy after a desktop card", "desktop", "browser", true, "prior"]
    ])
        assert.equal(logic.duplicateKept({ source: prior }, { source: message }, onScreen), want, "kept: " + label);
    const recent = Array.from({ length: 40 }, (_, i) => ({ key: "k" + i, at: 1000 + i }));
    same(logic.rememberMessage(recent.slice(0, 39), recent[39]).map(m => m.key), recent.slice(8).map(m => m.key), "the remembered messages are capped");
    same(logic.rememberMessage([{ key: "old", at: 0 }, { key: "kept", at: 6000 }], { key: "new", at: 10001 }).map(m => m.key), ["kept", "new"], "messages past the window are let go");
    same(logic.forgetMessage([{ key: "a", at: 0 }, { key: "b", at: 1 }], "a").map(m => m.key), ["b"]);
    // Messages in arrival order, as the service receives them: [label, the
    // notifications, each one's card still on screen for the one before it,
    // what each does: "shown" (no copy), "kept-prior" or "kept-message"].
    // A matched pair is settled, so a later message as alike as either
    // copy shows.
    const copyAt = (entry, key, at) => Object.assign({}, entry, { key, timestamp: at });
    for (const [label, entries, want] of [
        ["desktop, its browser copy, then another browser message", [desk, copyAt(web, "w", 2000), copyAt(web, "w2", 3000)], ["shown", "kept-prior", "shown"]],
        ["desktop, its browser copy, then another desktop message", [desk, copyAt(web, "w", 2000), copyAt(desk, "d2", 3000)], ["shown", "kept-prior", "shown"]],
        ["browser, its desktop copy, then another browser message", [copyAt(web, "w", 1000), copyAt(desk, "d", 2000), copyAt(web, "w2", 3000)], ["shown", "kept-message", "shown"]],
        ["browser, its desktop copy, then another desktop message", [copyAt(web, "w", 1000), copyAt(desk, "d", 2000), copyAt(desk, "d2", 3000)], ["shown", "kept-message", "shown"]],
        ["an unmatched message stays remembered", [desk, copyAt(desk, "d2", 2000), copyAt(web, "w", 3000)], ["shown", "shown", "kept-prior"]]
    ]) {
        let remembered = [];
        const got = entries.map(entry => {
            const read = logic.receiveMessage(remembered, logic.messageOf(entry), () => true);
            remembered = read.recent;
            return read.prior === null ? "shown" : "kept-" + read.kept;
        });
        same(got, want, "in sequence: " + label);
    }
}
verify(load(file));

// Each control removes one rule from a copy of the logic and keeps the text
// around it. The suite must fail on every copy.
const CONTROLS = [
    ["a plain exit is the fade then the close", "exit: d.short3 + d.medium3 };", "exit: Math.max(d.short3, d.medium3) + d.short3 };"],
    ["a plain entrance is the fade beside the drop", "enter: Math.max(d.short3, d.medium1), exit:", "enter: Math.max(d.short3, d.medium1) + d.short2, exit:"],
    ["the plain close is the medium3 duration", "close: d.medium3,", "close: d.medium4,"],
    ["a refused open's notice is transient", "notice: Object.assign(openNotice(match === null ? \"\" : match[1]), { transient: true })", "notice: openNotice(match === null ? \"\" : match[1])"],
    ["image tag", 'return !!name && name[1].toLowerCase() === "img";', "return false;"],
    ["strip after the newline rewrite", 'return stripImageTags(sanitizeBody(body, app, appIcon).replace(/\\r\\n|\\r|\\n/g, "<br/>"));', 'return sanitizeBody(body, app, appIcon).replace(/\\r\\n|\\r|\\n/g, "<br/>");'],
    ["Chromium address", "if (!chromium && String(app || \"\") !== \"\") return none;", "return none;"],
    ["a named sender that is no browser keeps its address", "if (!chromium && String(app || \"\") !== \"\") return none;", ""],
    ["an unnamed sender's address needs a blank line", "/^[ \\t]*\\r?\\n[ \\t]*\\r?\\n\\s*/", "/^\\s+/"],
    ["a rule by its web origin", "if ((ENRICHERS[o].origins || []).indexOf(origin.host) !== -1)", "if (false)"],
    ["a browser rule reads the text after the address", "source: \"browser\", body: origin.rest", "source: \"browser\", body: text"],
    ["a browser card says so", "source: \"browser\", body:", "source: \"desktop\", body:"],
    ["a direct title is normalised", "title: \"from \" + from[1]", "title: rest"],
    ["a conversation title is normalised", "title: \"in \" + within[1]", "title: rest"],
    ["Silence exception", 'if (urgency !== URGENCY.critical) return false;', ''],
    ["Silence lets the bare command line through", 'if (String(appName || "") === "notify-send") return true;', ''],
    ["Silence lets a plugin message through", 'return isPlainObject(hints) && typeof hints["x-vgs-plugin"] === "string" && hints["x-vgs-plugin"] !== "";', 'return false;'],
    ["a plugin hint is a string", 'typeof hints["x-vgs-plugin"] === "string" && hints', 'hints'],
    ["a plugin hint is not empty", ' && hints["x-vgs-plugin"] !== "";', ';'],
    ["critical stays", "if (urgency === URGENCY.critical) return 0;", ""],
    ["lifetime ceiling", "return Math.min(MAX_LIFETIME, Math.max(floor, Math.round(asked)));", "return Math.max(floor, Math.round(asked));"],
    ["the duration setting is the normal floor", "var floor = urgency === URGENCY.low ? Math.min(LOW_LIFETIME, normal) : normal;", "var floor = urgency === URGENCY.low ? Math.min(LOW_LIFETIME, normal) : 8000;"],
    ["a low toast stays no longer than the setting", "Math.min(LOW_LIFETIME, normal)", "LOW_LIFETIME"],
    ["key clash", "while (taken && taken(keyOf(at, id))) at += 1;", ""],
    ["summary limit", "summary: clip(f.summary, SUMMARY_MAX),", "summary: String(f.summary || \"\"),"],
    ["icon provider path", 'if (s.indexOf(ICON_PROVIDER) === 0 && s.charAt(ICON_PROVIDER.length) === "/") return s.slice(ICON_PROVIDER.length);', ""],
    ["in-process image dropped", '} else if (value.indexOf("image://") === 0) {\n            out[role] = "";', '} else if (false) {\n            out[role] = "";'],
    ["copy once", "if (source !== copy) copies.push({ from: source, to: copy });", "copies.push({ from: source, to: copy });"],
    ["history limit", "if (list.length > limits[lists[l]]) return", "if (false) return"],
    ["entry key identity", 'if (value.key !== keyOf(value.timestamp, value.originalId)) return where + ".key want="', 'if (false) return where + ".key want="'],
    ["duplicate key", 'if (seen[list[i].key]) return { ok: false, error: lists[l] + "." + i + ".key duplicate" };', ""],
    ["unknown state key", 'if (["version", "boot", "dnd", "readBefore", "live", "history"].indexOf(keys[k]) === -1) return', "if (false) return"],
    ["a state names its boot", 'if (typeof parsed.boot !== "string" || parsed.boot === "") return', "if (false) return"],
    ["a state's boot is not empty", 'if (typeof parsed.boot !== "string" || parsed.boot === "") return', 'if (typeof parsed.boot !== "string") return'],
    ["the state file keeps its boot", "        boot: state.boot,\n", ""],
    ["another boot clears the history", "if (state.boot === boot) return { state: state, cleared: 0 };", "return { state: state, cleared: 0 };"],
    ["another boot keeps Silence", "state: { boot: boot, dnd: state.dnd,", "state: { boot: boot, dnd: false,"],
    ["another boot keeps Mark read", "readBefore: state.readBefore, live: [], history: [] },", "readBefore: 0, live: [], history: [] },"],
    ["another boot counts what it cleared", "cleared: state.live.length + state.history.length", "cleared: state.history.length"],
    ["deadline outranks arrival", ": entry.deadline !== undefined ? now >= entry.deadline", ": false"],
    ["whole lifetime on restore", "if (lifetime > 0) kept.deadline = now + lifetime;", ""],
    ["a paused clock survives", "var over = entry.remaining !== undefined ? false", "var over = entry.remaining !== undefined ? true"],
    ["paused or running", 'if (value.deadline !== undefined && value.remaining !== undefined) return where + " deadline and remaining both set";', ""],
    ["clock fields", "return clock.since === null ? { remaining: clock.remaining } : { deadline: clock.since + clock.remaining };", "return { deadline: clock.since + clock.remaining };"],
    ["history newest first", "merged.sort(function (a, b) { return b.timestamp - a.timestamp; });", ""],
    ["history cut", "return { history: young.slice(0, HISTORY_MAX), dropped: young.slice(HISTORY_MAX).concat(aged) };", "return { history: young, dropped: aged };"],
    ["history cap", "var HISTORY_MAX = 100;", "var HISTORY_MAX = 720;"],
    ["age prune", "return entry.timestamp > now - HISTORY_AGE;", "return true;"],
    ["an entry exactly a day old goes", "return entry.timestamp > now - HISTORY_AGE;", "return entry.timestamp >= now - HISTORY_AGE;"],
    ["a push prunes by age", "var young = pruneHistory(merged, now);", "var young = merged;"],
    ["the next prune follows the oldest entry", "oldest = Math.min(oldest, history[i].timestamp);", ""],
    ["an empty history is due no prune", "if (history.length === 0) return null;", ""],
    ["inbox cutoff", '(mode !== "inbox" || e.timestamp > readBefore)', "true"],
    ["a panel leaves out an aged entry", 'return youngAt(e, now) && (mode', 'return (mode'],
    ["evict non-critical first", "if (rows[i].urgency !== URGENCY.critical) return rows[i].key;", ""],
    ["Show without actions", 'if (list.length === 0 && canRaise) list.push({ id: "open", label: "Show" });', ""],
    ["an open delivers its primary action", 'var id = c === "open" ? primaryAction(offered) :', 'var id = c === "open" ? "" :'],
    ["an open falls back to the first offered action", 'for (var i = 0; i < offered.length; i++) if (String(offered[i] || "") !== "") return String(offered[i]);', ""],
    ["default wins over the first action", 'if (offered.indexOf("default") !== -1) return "default";', ""],
    ["an open skips an action with no identifier", 'if (String(offered[i] || "") !== "") return', "if (true) return"],
    ["only an offered action is delivered", "deliver: offered.indexOf(id) !== -1 ? id : \"\"", "deliver: id"],
    ["an open raises", "raise: true, leave: \"invoke\"", "raise: id !== \"default\", leave: \"invoke\""],
    ["another action raises too", "raise: true, leave: \"invoke\"", "raise: id === \"default\", leave: \"invoke\""],
    ["dismiss delivers nothing", 'if (c === "dismiss") return { deliver: "", raise: false, leave: "dismiss" };', ""],
    ["an unknown choice is refused", 'if (id === "" && c !== "open") return null;', ""],
    ["an expired toast is held", 'if (reason === "expire") return transient ? "expire" : "keep";', 'if (reason === "expire") return "expire";'],
    ["a transient notification is never held", 'if (reason === "expire") return transient ? "expire" : "keep";', 'if (reason === "expire") return "keep";'],
    ["an invoked notification is closed on the server", 'if (reason === "invoke") return "dismiss";', 'if (reason === "invoke") return transient ? "dismiss" : "keep";'],
    ["a dismissal closes", 'if (reason === "dismiss") return "dismiss";', 'if (reason === "dismiss") return "keep";'],
    ["a held key past the history", "return keys.filter(function (k) { return !stored[k]; });", "return [];"],
    ["a held toast on screen stays", "for (var i = 0; i < live.length; i++) stored[live[i].key] = true;", ""],
    ["the sender's windows by name", "if (named.length > 0) return named.map(windowAddress);", ""],
    ["every window of the name", "if (named.length > 0) return named.map(windowAddress);", "if (named.length > 0) return [windowAddress(named[0])];"],
    ["a browser notification raises a browser", 'var host = webOrigin(entry.app, entry.appIcon, entry.body);\n    if (host === "") return [];', 'return [];'],
    ["the web app naming the site", "return (site.length > 0 ? site : browsers).map(windowAddress);", "return browsers.map(windowAddress);"],
    ["every browser when none names the site", "return (site.length > 0 ? site : browsers).map(windowAddress);", "return site.map(windowAddress);"],
    ["charge a stopping clock", "next[keys[i]] = { remaining: Math.max(0, c.remaining - (now - c.since)), since: null };", "next[keys[i]] = { remaining: c.remaining, since: null };"],
    ["paused clocks wait", "if (c.since === null) continue;", ""],
    ["rule by desktop entry", 'var wanted = [String(desktopEntry || "").toLowerCase(), String(app || "").toLowerCase()];\n    for (var r = 0;', 'var wanted = [String(app || "").toLowerCase()];\n    for (var r = 0;'],
    ["faces cap", "faces: read.people.slice(0, FACES_MAX),", "faces: read.people,"],
    ["one line is compact", 'return lines <= 1 ? "compact" : "regular";', 'return lines <= 2 ? "compact" : "regular";'],
    ["workspace prefix", "workspace = bracket[1];\n        rest = bracket[2];", "workspace = bracket[1];"],
    ["group members", 'var members = within[1].indexOf(",") === -1 ? [] :', "var members = true ? [] :"],
    ["sender once", "if (sender === \"\" || fold(members[i]) !== fold(sender)) people.push(members[i]);", "people.push(members[i]);"],
    ["initials skip a parenthesis", '.replace(/\\([^)]*\\)/g, " ")', ""],
    ["safe team id", "if (!/^[A-Za-z0-9]{1,32}$/.test(ids[i]) || names.length === 0) {", "if (names.length === 0) {"],
    ["larger icon first", "var urls = [icon.image_88, icon.image_68]", "var urls = [icon.image_68, icon.image_88]"],
    ["workspace limit", "for (var i = 0; i < ids.length && out.length < WORKSPACES_MAX; i++) {", "for (var i = 0; i < ids.length; i++) {"],
    ["first copied icon", "if (copiedUrl !== \"\") file = \"file://\" + copiedUrl;", "file = \"file://\" + to;"],
    ["reload gap", "return now - loadedAt >= WORKSPACE_RELOAD_GAP;", "return true;"],
    ["tint by the folded name", 'var key = fold(name || "");', 'var key = String(name || "");'],
    ["tint by the hash", "return FACE_TINTS[hash % FACE_TINTS.length];", "return FACE_TINTS[0];"],
    ["Slack photo cache status", 'if (parsed.status !== "loaded") return { ok: false, error: "status want=loaded|absent|off" };', 'if (false) return { ok: false, error: "status want=loaded|absent|off" };'],
    ["a run with the photos setting off is read", 'if (parsed.status === "absent" || parsed.status === "off")', 'if (parsed.status === "absent")'],
    ["the helper reads tokens only with the photos setting on", 'photos ? ["--photos"] : []', '["--photos"]'],
    ["the photos setting off runs no photo schedule", "var photos = photosOn ? slackPhotoOnlyDelay(read, workspaces, now) : Infinity;", "var photos = slackPhotoOnlyDelay(read, workspaces, now);"],
    ["with nothing on the sweeping run is the last", "return delay === Infinity ? null : delay;", "return delay === Infinity ? SLACK_PHOTO_RETRY : delay;"],
    ["Slack photo safe team id", 'if (typeof team.id !== "string" || !/^[A-Za-z0-9]{1,32}$/.test(team.id)) return { ok: false, error: "teams." + t + ".id want=safe" };', 'if (false) return { ok: false, error: "teams." + t + ".id want=safe" };'],
    ["Slack photo file URL only", 'return typeof value === "string" && /^file:\\/\\/\\/[^\\s?#]+\\.png\\?v=[0-9a-f]{16}$/.test(value) ? value : "";', 'return typeof value === "string" ? value : "";'],
    ["Slack photo workspace match", "if (fold(teams[t].names[n]) === wanted) return teams[t];", "if (false) return teams[t];"],
    ["Slack photo first name wins", "if (!hasOwn(map, key)) map[key] = photo;", "map[key] = photo;"],
    ["the Slack token state is one of the probe's", "if (SLACK_TOKEN_STATES.indexOf(match[2]) === -1) return", "if (false) return"],
    ["the Slack token account is one of the plugin's", "if (!SLACK_ACCOUNT.test(match[1])) return", "if (false) return"],
    ["a Slack token account answers once", "if (hasOwn(states, match[1])) return { ok: false, error: \"line.\" + i + \".account duplicate\" };", ""],
    ["the Slack token line is the whole line", "var match = /^slack-token: account=(\\S+) ([a-z]+)(?: [^\\n]*)?$/.exec(lines[i]);", "var match = /slack-token: account=(\\S+) ([a-z]+)/.exec(lines[i]);"],
    ["a Slack photo team names its account", "if (typeof team.account !== \"string\" || !SLACK_ACCOUNT.test(team.account)) return", "if (false) return"],
    ["a workspace's row waits for its state", "if (!hasOwn(states, account)) return { ok: false, missing: account };", ""],
    ["a workspace label is cut", "if (label.length <= SLACK_LABEL_MAX) return label;", "if (true) return label;"],
    ["a workspace label is cut by code units", "if (label.length <= SLACK_LABEL_MAX) return label;", "if (Array.from(label).length <= SLACK_LABEL_MAX) return label;"],
    ["a workspace label cut keeps a surrogate pair whole", "if (last >= 0xd800 && last <= 0xdbff) cut = cut.slice(0, -1);", ""],
    ["a matched pair forgets the prior copy", "return { recent: forgetMessage(recent, prior.key), prior: prior,", "return { recent: recent, prior: prior,"],
    ["a matched pair remembers neither copy", "return { recent: forgetMessage(recent, prior.key), prior: prior,", "return { recent: rememberMessage(forgetMessage(recent, prior.key), message), prior: prior,"],
    ["a listed workspace without photos retries", "if (!read.teams.some(function (t) { return t.id === workspaces[i].id; })) return SLACK_PHOTO_RETRY;", ""],
    ["the only known workspace", "if (ids.length === 1) return known[ids[0]];", ""],
    ["the one team holding the sender", "return holders.length === 1 ? holders[0].names[0] : \"\";", "return holders.length > 0 ? holders[0].names[0] : \"\";"],
    ["Slack photo per face", "if (fold(workspace) !== \"\") photo = hasOwn(map, key) ? map[key] : \"\";", "if (fold(workspace) !== \"\") photo = \"\";"],
    ["a named workspace the cache lacks has no photos", "if (fold(workspace) !== \"\") photo =", "if (team !== null) photo ="],
    ["a bot also goes by its (bot) name", 'names.concat(names.map(function (n) { return n + " (bot)"; }))', "names"],
    ["only a bot goes by a (bot) name", "slackUserNames(userNames, user.bot === true)", "slackUserNames(userNames, true)"],
    ["a face with no workspace takes the one holder's photo", "var only = holders.length === 1 ? slackUserPhotoMap(holders[0]) : {};", "var only = holders.length > 0 ? slackUserPhotoMap(holders[0]) : {};"],
    ["copies come from two clients", "r.rule === message.rule && r.source !== message.source &&", "r.rule === message.rule &&"],
    ["copies arrive within the window", "&& Math.abs(message.at - r.at) <= DUPLICATE_WINDOW) return r;", ") return r;"],
    ["copies share a workspace or name none", "(r.workspace === message.workspace || r.workspace === \"\" || message.workspace === \"\")", "true"],
    ["copies share their text", "&& r.sender === message.sender && r.text === message.text", "&& r.sender === message.sender"],
    ["copies share their markup-free text", ".replace(/<[^>]*>/g, \" \").replace(/\\s+/g, \" \").trim(),", ","],
    ["the desktop copy replaces a browser card on screen", "return message.source === \"desktop\" && priorOnScreen ? \"message\" : \"prior\";", "return \"prior\";"],
    ["the remembered messages are capped", ".concat([message]).slice(-DUPLICATES_MAX);", ".concat([message]);"],
    ["a shortcode is read only between tags", "var run = open === -1 ? text.slice(i) : text.slice(i, open);", "var run = text.slice(i);"],
    ["a shortcode resolves by an own name alone", "if (count >= EMOJI_PER_BODY || !hasOwn(lookup, found[1])) {", "if (count >= EMOJI_PER_BODY || !lookup[found[1]]) {"],
    ["a body's substitutions are capped", "if (count >= EMOJI_PER_BODY || !hasOwn", "if (!hasOwn"],
    ["a card takes its own workspace's emoji alone", "return id !== \"\" && hasOwn(lookups, id) ? lookups[id] : null;", "return id !== \"\" ? Object.assign.apply(null, [{}].concat(Object.keys(lookups).map(function (k) { return lookups[k]; }))) : null;"],
    ["pending emoji bring the run within a minute", "pending ? SLACK_EMOJI_PENDING : SLACK_EMOJI_RESCAN;", "SLACK_EMOJI_RESCAN;"],
    ["an emoji name is judged", "if (!EMOJI_NAME.test(names[n])) return", "if (false) return"],
    ["an emoji file is sixteen hex digits", "if (typeof hex !== \"string\" || !/^[0-9a-f]{16}$/.test(hex)) return", "if (false) return"],
    ["an emoji lookup has no prototype", "var lookup = Object.create(null);", "var lookup = {};"],
    ["the remembered messages keep the window", "return message.at - r.at <= DUPLICATE_WINDOW; }).concat(", "return true; }).concat("],
    ["a hint icon keeps the Lucide grammar", "return value === \"\" || (value.length <= HINT_ICON_MAX && HINT_ICON.test(value));", "return true;"],
    ["a hint tone is a status tone", "return value === \"\" || HINT_TONES.indexOf(value) !== -1;", "return true;"],
    ["a hint path is absolute and fits the TUI argument", "return value === \"\" || (value.charAt(0) === \"/\" && value.length <= HINT_OPEN_MAX && !/[\\u0000-\\u001f\\u007f]/.test(value));", "return true;"],
    ["a hint click is open or none", "return value === \"\" || HINT_CLICKS.indexOf(value) !== -1;", "return true;"],
    ["an open click needs a file", "if (roles.hintClick === \"open\" && roles.hintOpen === \"\") {", "if (false) {"],
    ["an entry keeps its hints", "hintIcon: hints.hintIcon,", "hintIcon: \"\","],
    ["a click opens the hinted file", "if (row.hintClick === \"open\" && row.hintOpen !== \"\") return \"open\";", "if (false) return \"open\";"],
    ["a none click only dismisses", "if (row.hintClick === \"none\") return \"dismiss\";", "if (false) return \"dismiss\";"],
    ["only an open reads the click hints", "if (choice !== \"open\") return \"default\";", ""],
    ["a refused open keeps the card", "if (text === \"ok\") return { leave: true, notice: null };", "if (true) return { leave: true, notice: null };"],
    ["a busy open names the open file", "    case \"busy\":\n", "    case \"busy-never\":\n"],
    ["a missing launcher names the terminal", "    case \"launcher-missing\":\n", "    case \"launcher-never\":\n"],
    ["unknown open replies do not leak", 'message: "Try this notification again.",', 'message: text.slice(0, 200),'],
    ["unknown history states do not leak", 'default: return "Saved history is unavailable";', 'default: return "History unavailable: " + storeState;'],
    ["damaged history differs from unreadable history", 'case "corrupt": return "Saved history is damaged";', 'case "corrupt": return "Saved history cannot be read";'],
    ["the state judge reads the hint values", "if (!hintValueFits(HINT_ROLES[h], hint)) return where + \".\" + HINT_ROLES[h] + \" refused\";", "if (false) return \"\";"],
    ["the state judge refuses a hint role that is no string", "if (typeof hint !== \"string\") return where + \".\" + HINT_ROLES[h] + \" want=string\";", "if (false) return \"\";"],
    ["the state judge refuses an open click with no file", "if (value.hintClick === \"open\" && !value.hintOpen) return where + \".hintClick open without hintOpen\";", "if (false) return \"\";"],
    ["a stored entry may leave its hint roles out", "if (hint === undefined) continue;", "if (hint === undefined) return where + \".\" + HINT_ROLES[h] + \" want=string\";"],
    ["a stored entry reads back with every hint role", "if (out[HINT_ROLES[h]] === undefined) out[HINT_ROLES[h]] = \"\";", ""],
    ["a card's message is its own team's", "record.teamId !== \"\" && record.teamId !== teamId", "false"],
    ["a record of no team that reads can be any team's", "record.teamId !== \"\" && record.teamId !== teamId", "record.teamId !== teamId"],
    ["a card of no known team has no link", "if (teamId === \"\") return { link: \"\", found: \"no-team\" };", ""],
    ["two records of one team in one window give no link", "if (matches !== 1) return", "if (matches === 0) return"],
    ["a refused record still counts", "matches++;", "if (record.link !== \"\") matches++;"],
    ["a stamp at the arrival is in the window", "at > arrival || ", "at >= arrival || "],
    ["a stamp after the arrival is no record of the card", "at > arrival || ", ""],
    ["a stamp at the window's far edge is in it", " || at < arrival - SLACK_STAMP_WINDOW", " || at <= arrival - SLACK_STAMP_WINDOW"],
    ["a stamp before the window is no record of the card", " || at < arrival - SLACK_STAMP_WINDOW", ""],
    ["a stamp is local time", "new Date(2000 + n[2], n[0] - 1, n[1], n[3], n[4], n[5], n[6]).getTime()", "Date.UTC(2000 + n[2], n[0] - 1, n[1], n[3], n[4], n[5], n[6])"],
    ["a record line with no stamp can be of any time", "at !== null && (at > arrival", "at === null || (at > arrival"],
    ["a record line with no stamp gives no link", "link = at === null ? \"\" : record.link;", "link = record.link;"],
    ["a record is a NEW_NOTIFICATION line", "info: Store: NEW_NOTIFICATION *$/gm", "info: Store: [A-Z_]+ *$/gm"],
    ["a team id is a Slack id", "!slackIdFits(read.teamId, SLACK_ID)", "false"],
    ["a channel is a Slack id", "!slackIdFits(read.channel, SLACK_ID)", "false"],
    ["a message is a time", "!slackIdFits(read.msg, SLACK_MESSAGE_TIME)", "false"],
    ["a thread is a time", "!slackIdFits(read.thread_ts, SLACK_MESSAGE_TIME)", "false"],
    ["an id is text", "return typeof value === \"string\" && shape.test(value);", "return shape.test(value);"],
    ["a thread reply's link names its thread", "(threaded ? \"&thread_ts=\" + read.thread_ts : \"\")", "\"\""],
    ["text that is no object is a refused record", "    } catch (e) {\n        return unread;\n    }\n    if (!slackIdFits(read.teamId", "    } catch (e) {\n        throw e;\n    }\n    if (!slackIdFits(read.teamId"],
    ["only a card's way in opens its message", "if (c !== \"open\" && c !== \"action:\" + primaryAction(offered)) return null;", ""],
    ["the primary action's pill is a way in", "c !== \"open\" && c !== \"action:\" + primaryAction(offered)", "c !== \"open\""],
    ["a browser's copy opens no message", " || read.source !== \"desktop\"", ""],
    ["a card no rule reads opens no message", "if (read === null || read.source !== \"desktop\") return null;", "if (read === null) return { rule: \"\", arrival: 0, team: \"\" }; if (read.source !== \"desktop\") return null;"]
];

const source = fs.readFileSync(file, "utf8");
const temp = path.join(__dirname, "..", "tmp", "notifications-logic-control-" + process.pid);
fs.rmSync(temp, { recursive: true, force: true });
fs.mkdirSync(temp, { recursive: true });
try {
    for (const [label, needle, replacement] of CONTROLS) {
        assert.equal(source.split(needle).length, 2, `control "${label}": the text to replace must occur once`);
        const mutant = path.join(temp, "NotificationLogic.js");
        fs.writeFileSync(mutant, source.replace(needle, () => replacement));
        let failed = false;
        try {
            verify(load(mutant));
        } catch (e) {
            failed = true;
        }
        assert.ok(failed, `control "${label}": the suite passed on logic without that rule`);
    }
} finally {
    fs.rmSync(temp, { recursive: true, force: true });
}
// The libsecret service the manifest's `secrets` declares, the one the
// core stores and clears under, is the one the photo helper, the token
// probe name: each names it as a literal, so each literal is read back
// against the manifest. The controls: a manifest naming another service,
// and a helper naming another one.
const pluginDir = path.dirname(file);
const SERVICE_SOURCES = [
    ["slack-photos.js", /const SERVICE = \["service", "([^"]+)", "account"\];/g],
    ["token-status.sh", /secret-tool search service (\S+) account/g],
];
function serviceMismatches(manifestText, read) {
    const declared = JSON.parse(manifestText).secrets.service;
    const out = [];
    for (const [name, pattern] of SERVICE_SOURCES) {
        const found = [...read(name).matchAll(pattern)].map(m => m[1]);
        if (found.length === 0) out.push(name + " names no service");
        for (const service of found) if (service !== declared) out.push(name + " names " + service + ", the manifest " + declared);
    }
    return out;
}
const manifestText = fs.readFileSync(path.join(pluginDir, "manifest.json"), "utf8");
const readSource = name => fs.readFileSync(path.join(pluginDir, name), "utf8");
assert.deepEqual(serviceMismatches(manifestText, readSource), [], "every script names the manifest's secrets service");
const otherManifest = JSON.stringify(Object.assign({}, JSON.parse(manifestText), { secrets: { service: "vgs-other", label: "x" } }));
assert.deepEqual([...new Set(serviceMismatches(otherManifest, readSource).map(line => line.split(" ")[0]))], SERVICE_SOURCES.map(([name]) => name), "control: a manifest naming another service fails every script");
assert.deepEqual(serviceMismatches(manifestText, name => name === "slack-photos.js" ? readSource(name).replace('"service", "vgs-notifications"', '"service", "vgs-other"') : readSource(name)), ["slack-photos.js names vgs-other, the manifest vgs-notifications"], "control: a helper naming another service fails");

// Body and inbox count text on their glass fill, judged over black and
// white, the darkest and lightest wallpaper pixels. Each role's control
// restores its old alpha and must fail the normal-size text floor.
const TEXT_FLOOR = 4.5;
const WALLPAPERS = ["#000000", "#ffffff"];
function lookIn(tokens, light, mode) {
    const judged = themeLogic.acceptAppearance(tokens, light, { scheme: { mode: mode }, palette: { accent: "#ff5a36" }, motion: { scale: 1 }, font: { family: { sans: "Inter" } } });
    assert.equal(judged.ok, true, "the look resolves in " + mode + " mode: " + JSON.stringify(judged));
    return judged.values;
}
function over(top, under) {
    const channel = name => top[name] * top.a + under[name] * (1 - top.a);
    return { r: channel("r"), g: channel("g"), b: channel("b"), a: 1 };
}
function textShortfalls(look, role) {
    return WALLPAPERS.filter(wallpaper => {
        const card = over(themeLogic.parseColor(look.card.fill), themeLogic.parseColor(wallpaper));
        return themeLogic.contrastRatio(over(themeLogic.parseColor(look.text[role].color), card), card) < TEXT_FLOOR;
    });
}
for (const mode of ["dark", "light"]) {
    for (const role of ["body", "subtitle"]) {
        same(textShortfalls(lookIn(appearance.TOKENS, appearance.LIGHT, mode), role), [], mode + " " + role + " meets 4.5:1 over both wallpapers");
        const faintTokens = JSON.parse(JSON.stringify(appearance.TOKENS));
        faintTokens.text[role].color.value = "alpha({text.foreground}, 0.5)";
        const faintLight = JSON.parse(JSON.stringify(appearance.LIGHT));
        faintLight.text[role] = { color: "alpha({text.foreground}, 0.5)" };
        same(textShortfalls(lookIn(faintTokens, faintLight, mode), role), mode === "dark" ? ["#ffffff"] : WALLPAPERS, "control: " + mode + " " + role + " at 0.5 fails the text floor");
    }
}

// CardSlot.qml plays the plain exit as toastMotion's fade, then its close,
// one after the other, and the service's timers read toastMotion under the
// state the slot reads: a source check of the two files, since the
// lengths themselves are pinned above. The controls swap the close for a
// literal duration and the service's state for the setting.
const notesDir = path.join(__dirname, "..", "shell", "plugins", "vgs.notifications");
function plainExitPlays(slotSource) {
    const block = slotSource.match(/id: plainExit\n([\s\S]*?)\n    \}/);
    return block === null ? [] : [...block[1].matchAll(/duration: slot\.plain\.(\w+);/g)].map(m => m[1]);
}
function serviceTimesFollowGlass(serviceSource) {
    return /Logic\.toastMotion\(look\.motion\.duration, glassOn\)/.test(serviceSource) && /readonly property bool glassOn: glassState\.on/.test(serviceSource);
}
const slotSource = fs.readFileSync(path.join(notesDir, "CardSlot.qml"), "utf8");
const serviceSource = fs.readFileSync(path.join(notesDir, "Service.qml"), "utf8");
same(plainExitPlays(slotSource), ["fade", "close"], "the plain exit plays the fade, then the close");
assert.ok(/readonly property bool glassOn: service !== null && service\.glassOn/.test(slotSource), "a toast moves as the service's glass state says");
assert.equal(serviceTimesFollowGlass(serviceSource), true, "the service's timers follow its glass state");
assert.equal(slotSource.split("duration: slot.plain.close;").length, 2, "control text occurs once");
same(plainExitPlays(slotSource.replace("duration: slot.plain.close;", "duration: slot.look.motion.duration.medium3;")), ["fade"], "control: a plain close of its own length is caught");
assert.equal(serviceTimesFollowGlass(serviceSource.replace("readonly property bool glassOn: glassState.on", "readonly property bool glassOn: glassChoice")), false, "control: service timers on the setting alone are caught");

// VGlass at its defaults draws what the launcher's and the notifications'
// own glass tables drew before the shared style, in both modes: each value
// below is the resolved literal those tables held, with the look and the
// shared table each value now comes from. `drawn` reads every value the
// two glass surfaces, the launcher's dividers and the toast's bead draw.
const launcherAppearance = load(path.join(__dirname, "..", "shell", "plugins", "vgs.launcher", "Appearance.js"));
const glassAppearance = load(path.join(__dirname, "..", "shell", "Commons", "Glass.js"));
const DRAWN_BEFORE = {
    dark: {
        launcher: { fill: "#151515c7", sheen: "#e8e8e80b", sheenEnd: "#e8e8e800", sheenHeight: 48, hairline: "#e8e8e817", hairlineWidth: 1, divider: "#e8e8e812", dividerWidth: 1,
            wide: { color: "#0000008c", blur: 90, offsetY: 28, spread: -4 }, tight: { color: "#00000073", blur: 30, offsetY: 10, spread: -4 } },
        notifications: { base: "#101010ff", fill: "#101010cc", sheen: "#e8e8e80b", sheenEnd: "#e8e8e800", sheenHeight: 48, hairline: "#e8e8e817", hairlineWidth: 1,
            shadow: { color: "#00000073", blur: 30, offsetY: 10, spread: -4 },
            orb: { shadeStop: 0.45, shade: "#00000059", clear: "#00000000", spot: "#ffffff6b", spotEnd: "#ffffff00", spotX: 0.3, spotY: 0.42, spotWidth: 0.46, spotHeight: 0.3, spotAngle: -18 },
            ring: "#101010ff", chip: "#484848ff", coral: "#924a3cff" }
    },
    light: {
        launcher: { fill: "#efefefcc", sheen: "#2a2a2a59", sheenEnd: "#2a2a2a00", sheenHeight: 48, hairline: "#2a2a2a1a", hairlineWidth: 1, divider: "#2a2a2a14", dividerWidth: 1,
            wide: { color: "#00000033", blur: 90, offsetY: 28, spread: -4 }, tight: { color: "#00000029", blur: 30, offsetY: 10, spread: -4 } },
        notifications: { base: "#f2f2f2ff", fill: "#f2f2f2d9", sheen: "#2a2a2a59", sheenEnd: "#2a2a2a00", sheenHeight: 48, hairline: "#2a2a2a1a", hairlineWidth: 1,
            shadow: { color: "#00000029", blur: 30, offsetY: 10, spread: -4 },
            orb: { shadeStop: 0.45, shade: "#00000059", clear: "#00000000", spot: "#ffffff6b", spotEnd: "#ffffff00", spotX: 0.3, spotY: 0.42, spotWidth: 0.46, spotHeight: 0.3, spotAngle: -18 },
            ring: "#f2f2f2ff", chip: "#bebebeff", coral: "#eca597ff" }
    }
};
function drawn(launcherTable, notesTable, glassTable, mode) {
    const launcher = lookIn(launcherTable.TOKENS, launcherTable.LIGHT, mode);
    const notes = lookIn(notesTable.TOKENS, notesTable.LIGHT, mode);
    const glass = lookIn(glassTable.TOKENS, glassTable.LIGHT, mode);
    const shared = { sheen: glass.glass.sheen, sheenEnd: glass.glass.sheenEnd, sheenHeight: glass.glass.sheenHeight, hairline: glass.glass.hairline, hairlineWidth: glass.glass.hairlineWidth };
    return {
        // Launcher.qml hands card.fill and the wide elevation, ContextMenu.qml
        // the tight one; the dividers read row.
        launcher: Object.assign({ fill: launcher.card.fill }, shared, { divider: launcher.row.divider, dividerWidth: launcher.row.dividerWidth, wide: glass.shadow.wide, tight: glass.shadow.tight }),
        // CardFace.qml and InboxHeader.qml hand card.fill and the tight
        // elevation; Orb.qml reads orb; the faces mix card.base.
        notifications: Object.assign({ base: notes.card.base, fill: notes.card.fill }, shared, { shadow: glass.shadow.tight, orb: notes.orb, ring: notes.face.ring, chip: notes.face.chip, coral: notes.face.tint.coral })
    };
}
for (const mode of ["dark", "light"])
    same(drawn(launcherAppearance, appearance, glassAppearance, mode), DRAWN_BEFORE[mode], "VGlass at its defaults draws today's " + mode + " glass");
// Controls: a shared hairline, a launcher fill and a notifications base
// each moved by one step must fail the comparison.
const moved = (table, edit) => { const copy = { TOKENS: JSON.parse(JSON.stringify(table.TOKENS)), LIGHT: JSON.parse(JSON.stringify(table.LIGHT)) }; edit(copy); return copy; };
for (const [label, launcherTable, notesTable, glassTable] of [
    ["the shared hairline", launcherAppearance, appearance, moved(glassAppearance, t => { t.TOKENS.glass.hairline.value = "alpha({text.foreground}, 0.1)"; })],
    ["the launcher fill", moved(launcherAppearance, t => { t.TOKENS.card.fill.value = "alpha(#151515, 0.8)"; }), appearance, glassAppearance],
    ["the notifications base", launcherAppearance, moved(appearance, t => { t.TOKENS.card.base.value = "#111111"; }), glassAppearance]
])
    assert.throws(() => same(drawn(launcherTable, notesTable, glassTable, "dark"), DRAWN_BEFORE.dark), { code: "ERR_ASSERTION" }, "control: " + label + " moved fails today's glass");

// ContextMenu.qml draws the flyout with flyout.fill over the card's rows: a
// key hint at the full foreground under it shows through by no visible
// step, over black and white wallpapers. The control hands it card.fill.
const contextMenuSource = fs.readFileSync(path.join(__dirname, "..", "shell", "plugins", "vgs.launcher", "ContextMenu.qml"), "utf8");
assert.ok(/fill: menu\.look\.flyout\.fill\n/.test(contextMenuSource), "the flyout draws its own fill");
function hintShowsThrough(table, mode, fillOf) {
    const look = lookIn(table.TOKENS, table.LIGHT, mode), fill = themeLogic.parseColor(fillOf(look));
    return WALLPAPERS.filter(wallpaper => {
        const card = over(themeLogic.parseColor(look.card.fill), themeLogic.parseColor(wallpaper));
        return themeLogic.contrastRatio(over(fill, over(themeLogic.parseColor(look.text.foreground), card)), over(fill, card)) >= 1.01;
    });
}
for (const mode of ["dark", "light"]) {
    same(hintShowsThrough(launcherAppearance, mode, look => look.flyout.fill), [], mode + ": no key hint shows through the flyout");
    same(hintShowsThrough(launcherAppearance, mode, look => look.card.fill), WALLPAPERS, "control: " + mode + " card.fill on the flyout shows the hint");
}

console.log(`test-notifications-logic: ok bodies=${BODIES.length} states=${STATE_REFUSED.length} hints=${HINT_ROWS.length} enriched=${ENRICHED.length} controls=${CONTROLS.length}`);
