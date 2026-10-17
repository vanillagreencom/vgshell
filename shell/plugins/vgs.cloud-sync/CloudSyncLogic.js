.pragma library

// vgs.cloud-sync's pure decisions, run under node by
// scripts/test-cloud-sync-logic.js: the one judge of the runner's status
// record and probe answer, the status values the service publishes from
// them, and what the bar widget, the window and the notification draw from
// those values. `headline` is the one statement of where the sync stands:
// the bar, its tooltip, the window and the Settings `sync` value all read
// it. The runner, bin/cloud-sync, owns every rule about the sync; this
// file only reads its answers.

// The runner's overall states and a pair's states (bin/cloud-sync,
// renderStatus).
var STATES = ["idle", "running", "paused", "offline", "authorization-required", "error", "not-set-up"];
var PAIR_STATES = ["idle", "running", "paused", "offline", "authorization-required", "error"];
var UNITS = ["installed", "absent", "stale"];
var CONFLICT_KINDS = ["both-changed", "removed-locally", "removed-on-drive", "renamed", "unreadable-on-drive", "duplicate-on-drive"];
var PRESENCES = ["present", "absent", "locked", "unavailable"];
// The credential accounts of the manifest's `secrets`, in the order the
// Setup section lists them (bin/cloud-sync probe prints the same set).
var ACCOUNTS = ["client-id", "client-secret", "token"];

// The conflicts the window lists: the published values share one 64 KiB
// ceiling (PluginLogic.STATUS_MAX_BYTES) with the rest, and a removed
// Drive folder can make thousands. The window states the rest as a count.
var CONFLICTS_MAX = 20;
var CLOUD_BYTES_MAX = 40000;
// A state's lines and hint, PluginLogic.STATUS_LIST_MAX and
// STATUS_HINT_MAX: a longer value is refused whole.
var LINES_MAX = 64;
var HINT_MAX = 200;
// A Google account address as the runner stores it on a token
// (bin/cloud-sync authorize): printable, at most 254 characters, one `@`.
var ADDRESS_MAX = 254;
var NOT_PRINTABLE = /[\u0000-\u001f\u007f-\u009f\u2028\u2029]/;

// What each state reads as and the tone it takes: `tone` is a status
// `state` tone (PluginLogic.STATUS_STATE_TONES). `idle` reads by the data's
// age (freshness). A pair reads by these; the whole sync by `headline`.
var STATE_VIEW = {
    running: { text: "Syncing", tone: "info", icon: "cloud-sync" },
    paused: { text: "Paused", tone: "info", icon: "cloud-off" },
    offline: { text: "Offline", tone: "warning", icon: "cloud-off" },
    "authorization-required": { text: "Connect needed", tone: "danger", icon: "cloud-alert" },
    error: { text: "Sync failed", tone: "danger", icon: "cloud-alert" },
    "not-set-up": { text: "Not set up", tone: "warning", icon: "cloud" }
};
var CURRENT = { text: "Up to date", tone: "ok", icon: "cloud-check" };
var OUT_OF_DATE = { text: "Out of date", tone: "warning", icon: "cloud-alert" };
var NOT_SYNCED = { text: "Not synced yet", tone: "info", icon: "cloud" };
var NO_PAIRS = { text: "No folder pairs", tone: "warning", icon: "cloud" };
// A status state tone as a Badge tone.
var BADGE_TONES = { ok: "success", info: "info", warning: "warning", danger: "danger" };

// A run's last error, as plain text a user reads. A kind not listed here is
// a sync error.
var ERROR_TEXT = {
    offline: "Google Drive cannot be reached. Cloud Sync tries again at the next sync.",
    "authorization-refused": "Google Drive did not accept Connect. [Select Connect again on the Cloud Sync page](page:vgs.cloud-sync/Setup).",
    "credential-absent": "A Google Drive key or connection is missing. Add the client ID and secret, then [select Connect on the Cloud Sync page](page:vgs.cloud-sync/Setup).",
    "credential-locked": "Your keyring is locked. Unlock it to sync.",
    "source-missing": "A Google Drive folder of a folder pair does not exist.",
    "rclone-missing": "rclone is not installed.",
    "secret-tool-missing": "VGS cannot read your keyring.",
    "secret-tool-failed": "VGS cannot read your keyring.",
    "secret-tool-timeout": "VGS cannot read your keyring.",
    interrupted: "The last sync stopped before it finished.",
    "pairs-invalid": "The folder pair list is not valid, so Cloud Sync copies nothing."
};
var ERROR_DEFAULT = "The sync stopped with an error. Cloud Sync tries again at the next sync.";
// The Settings page's own words where ERROR_TEXT sends the user to that
// page: its fields stand below the sync value.
var PAGE_ERROR_TEXT = {
    "authorization-refused": "Google Drive did not accept Connect. Select Connect again below.",
    "credential-absent": "A Google Drive key or connection is missing. Add the client ID and secret, then select Connect below."
};
var CONFLICT_TEXT = {
    "both-changed": "Changed here and on Google Drive. The older copy is kept for 30 days.",
    "removed-locally": "Removed here. Cloud Sync copied it back from Google Drive.",
    "removed-on-drive": "Removed from Google Drive. The copy here stays.",
    renamed: "Renamed on Google Drive. The old name was copied back to Google Drive.",
    "unreadable-on-drive": "Cloud Sync could not copy this file from Google Drive.",
    "duplicate-on-drive": "Google Drive holds two files with this name. Cloud Sync copied one of them."
};
// The line that names the folder of the copy CONFLICT_TEXT speaks of,
// before that folder's path: the kept older copy, or the copy here.
var CONFLICT_FOLDER_TEXT = {
    "both-changed": "The older copy is in this folder: ",
    "removed-on-drive": "The copy here is in this folder: ",
    "unreadable-on-drive": "The older copy here is in this folder: "
};
// rclone's reason for a file it could not copy, as the words the review
// row gives for it. The dangling shortcut row reads rclone v1.75.1's
// "failed to open source object: can't read dangling shortcut". The raw
// reason stays in the runner's record and log.
var REASON_TEXT = [
    { pattern: /dangling shortcut/, text: "It is a Google Drive shortcut to a file that no longer exists." }
];
var REASON_DEFAULT = "Google Drive did not let Cloud Sync read it.";

var PAIR_RULE_TEXT = {
    shape: "Folder pair {id} is not a valid folder pair.",
    id: "Folder pair {id} has an invalid ID.",
    label: "Folder pair {id} has an invalid name.",
    remote: "Folder pair {id} has an invalid Google Drive folder.",
    "drive-root": "Folder pair {id} uses the whole Drive.",
    local: "Folder pair {id} has an invalid folder on this computer.",
    "home-or-above": "Folder pair {id} uses your home folder or a folder above it.",
    "repository-root": "Folder pair {id} uses a Git repository.",
    "state-overlap": "Folder pair {id} overlaps the folder where Cloud Sync keeps its records.",
    "vgs-overlap": "Folder pair {id} overlaps a VGS folder.",
    "unit-overlap": "Folder pair {id} overlaps the folder for system services.",
    "repository-inside": "Folder pair {id} holds a Git repository.",
    "duplicate-id": "Folder pair {id} has the same ID as another folder pair.",
    "local-overlap": "Folder pair {id} overlaps another folder pair.",
    "remote-overlap": "Folder pair {id} overlaps another Google Drive folder pair."
};

var PAIRS_RESET_HINT = "Start again to keep the damaged file and make an empty list.";

// What a failed request to the runner reads as, by its operation.
var PROBLEM_TEXT = {
    start: "VGS could not start a sync.",
    pause: "VGS could not pause Cloud Sync.",
    resume: "VGS could not resume Cloud Sync.",
    status: "VGS could not read the Cloud Sync status.",
    probe: "VGS could not check the Google Drive keys."
};

var SCHEDULE_HINT = "Cloud Sync runs every hour while you are logged in.";
var NO_PAIRS_HINT = "Add a folder pair to choose what Cloud Sync keeps in step.";
var REVIEW_HINT = "Open Cloud Sync to review them.";
var UNUSED_KEY_HINT = "No folder pair uses this key now.";

function hasOwn(object, key) {
    return Object.prototype.hasOwnProperty.call(object, key);
}

function isObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
}

function isText(value) {
    return typeof value === "string";
}

function isTime(value) {
    return value === null || (isText(value) && !isNaN(Date.parse(value)));
}

function msOf(iso) {
    return iso === null ? null : Date.parse(iso);
}

function dirname(file) {
    var at = file.lastIndexOf("/");
    return at <= 0 ? "/" : file.slice(0, at);
}

function errorOk(value) {
    return value === null || (isObject(value) && isText(value.kind));
}

function pairOk(p) {
    return isObject(p) && !hasOwn(p, "direction") && isText(p.id) && isText(p.label) && isText(p.remote)
        && PAIR_STATES.indexOf(p.state) !== -1 && isTime(p.lastSuccess) && isTime(p.staleAfter) && errorOk(p.lastError);
}

function conflictOk(c) {
    return isObject(c) && CONFLICT_KINDS.indexOf(c.kind) !== -1 && isText(c.pair) && isText(c.pairLabel) && isText(c.path)
        && ((c.kind === "unreadable-on-drive" && !hasOwn(c, "localPath")) || (isText(c.localPath) && c.localPath.charAt(0) === "/"))
        && (c.kind !== "both-changed" || !hasOwn(c, "storedPath") || (isText(c.storedPath) && c.storedPath.charAt(0) === "/"))
        && (c.kind !== "renamed" || isText(c.to)) && (c.kind !== "unreadable-on-drive" || isText(c.reason)) && isTime(c.since);
}

// The one judge of the runner's status record, status.json or `status`'s
// line (bin/cloud-sync renderStatus): { ok: true, record } or
// { ok: false, error } naming the first field that does not fit.
function parseStatus(text) {
    var doc;
    try {
        doc = JSON.parse(text);
    } catch (e) {
        return { ok: false, error: "status=not-json" };
    }
    if (!isObject(doc)) return { ok: false, error: "status=shape" };
    if (STATES.indexOf(doc.state) === -1) return { ok: false, error: "status=state" };
    if (typeof doc.paused !== "boolean") return { ok: false, error: "status=paused" };
    if (UNITS.indexOf(doc.units) === -1) return { ok: false, error: "status=units" };
    if (!isTime(doc.lastSuccess) || !isTime(doc.staleAfter)) return { ok: false, error: "status=time" };
    if (!errorOk(doc.lastError)) return { ok: false, error: "status=lastError" };
    if (!Array.isArray(doc.pairs) || !doc.pairs.every(pairOk)) return { ok: false, error: "status=pairs" };
    if (!Array.isArray(doc.conflicts) || !doc.conflicts.every(conflictOk)) return { ok: false, error: "status=conflicts" };
    if (doc.attention !== null && !(isObject(doc.attention) && Array.isArray(doc.attention.reasons) && isText(doc.attention.key)
        && typeof doc.attention.notified === "boolean"))
        return { ok: false, error: "status=attention" };
    return { ok: true, record: doc };
}

// A Google account address a token carries, as the runner judges it.
function isAddress(value) {
    return isText(value) && value.length > 0 && value.length <= ADDRESS_MAX && !NOT_PRINTABLE.test(value) && value.split("@").length === 2;
}

// The one judge of `probe`'s line: { ok: true, presence: { account:
// { presence, needed, user? } } } or { ok: false, error }. Only a token's
// row carries `user`, the account it signed in as, and only when the
// runner read it.
function parseProbe(text) {
    var doc;
    try {
        doc = JSON.parse(text);
    } catch (e) {
        return { ok: false, error: "probe=not-json" };
    }
    if (!isObject(doc) || !Array.isArray(doc.credentials)) return { ok: false, error: "probe=shape" };
    var presence = {};
    for (var i = 0; i < doc.credentials.length; i++) {
        var c = doc.credentials[i];
        if (!isObject(c) || ACCOUNTS.indexOf(c.account) === -1 || PRESENCES.indexOf(c.presence) === -1 || typeof c.needed !== "boolean")
            return { ok: false, error: "probe=credential" };
        if (hasOwn(c, "user") && (c.account !== "token" || !isAddress(c.user)))
            return { ok: false, error: "probe=user account=" + c.account };
        presence[c.account] = { presence: c.presence, needed: c.needed };
        if (hasOwn(c, "user")) presence[c.account].user = c.user;
    }
    for (var a = 0; a < ACCOUNTS.length; a++)
        if (!hasOwn(presence, ACCOUNTS[a])) return { ok: false, error: "probe=missing account=" + ACCOUNTS[a] };
    return { ok: true, presence: presence };
}

// What STATE reads as, the data's age deciding an idle one: { text, tone,
// icon }. STALE_AFTER and NOW are epoch milliseconds, STALE_AFTER null
// before the first success.
function stateView(state, staleAfter, now) {
    if (state !== "idle") {
        if (!hasOwn(STATE_VIEW, state)) throw new Error("cloud-sync: state " + JSON.stringify(state) + " is not one of " + STATES.join(", "));
        return STATE_VIEW[state];
    }
    if (staleAfter === null) return NOT_SYNCED;
    return now < staleAfter ? CURRENT : OUT_OF_DATE;
}

function badgeTone(tone) {
    return BADGE_TONES[tone];
}

// ERROR as a sentence; ON_PAGE true for the Settings page, which names
// its own fields below instead of sending the user to itself.
function errorText(error, onPage) {
    if (error === null) return "";
    if (error.kind === "credential-absent" && error.account === "token")
        return "Google Drive is not connected. " + (onPage === true ? "Select Connect below." : "[Select Connect on the Cloud Sync page](page:vgs.cloud-sync/Setup).");
    if (onPage === true && hasOwn(PAGE_ERROR_TEXT, error.kind)) return PAGE_ERROR_TEXT[error.kind];
    return hasOwn(ERROR_TEXT, error.kind) ? ERROR_TEXT[error.kind] : ERROR_DEFAULT;
}

// The pair list reader's detail as one sentence a user reads. The keyed
// detail stays in the log and status record for support.
function pairListProblem(error) {
    if (error === null || error.kind !== "pairs-invalid" || !isText(error.detail)) return ERROR_TEXT["pairs-invalid"];
    if (error.detail === "pairs-file=not-json") return "The folder pair list file is damaged.";
    if (/^pairs-file=unreadable-/.test(error.detail)) return "VGS cannot read the folder pair list file.";
    if (error.detail === "pairs-file=shape") return "The folder pair list file does not hold a list of folder pairs.";
    var match = /^pair=([^ ]+) rule=([^ ]+)$/.exec(error.detail);
    if (match !== null && hasOwn(PAIR_RULE_TEXT, match[2])) {
        var id = match[1] === "?" ? "entry" : match[1];
        return PAIR_RULE_TEXT[match[2]].replace("{id}", id);
    }
    return ERROR_TEXT["pairs-invalid"];
}

function pairListResetHint(error) {
    return pairListProblem(error) + " " + PAIRS_RESET_HINT;
}

function conflictText(kind) {
    return CONFLICT_TEXT[kind];
}

function reasonText(reason) {
    var row = REASON_TEXT.find(function (r) { return r.pattern.test(reason); });
    return row === undefined ? REASON_DEFAULT : row.text;
}

function problemText(operation, firstLine) {
    if (operation === "") return "";
    if (operation === "start" && firstLine.indexOf("units=absent") !== -1) return "Set up hourly sync first.";
    return hasOwn(PROBLEM_TEXT, operation) ? PROBLEM_TEXT[operation] : "VGS could not reach Cloud Sync.";
}


// The folders Open folders opens for CONFLICT: the mirror's folder, and
// for a local edit also the folder that keeps the local version. A file
// the runner names no local path for has no copy here, so no folder.
function reviewDirs(conflict) {
    if (conflict.localPath === undefined) return [];
    var dirs = [dirname(conflict.localPath)];
    if (conflict.kind === "both-changed" && conflict.storedPath !== undefined) dirs.push(dirname(conflict.storedPath));
    return dirs;
}

// An error as the published data carries it: its kind, and the account
// it names, which errorText reads.
function publishedError(error) {
    if (error === null) return null;
    if (error.kind === "pairs-invalid" && isText(error.detail)) return { kind: error.kind, detail: error.detail };
    return isText(error.account) ? { kind: error.kind, account: error.account } : { kind: error.kind };
}

// Whether the runner could read the pair list; while it cannot, it
// refuses every pair change too.
function pairListValid(cloud) {
    return cloud.lastError === null || cloud.lastError.kind !== "pairs-invalid";
}

// The published `cloud` data the widget and the window draw: the record
// with times as epoch milliseconds, each pair with `review`, the count of
// its own files to review, the review list capped, each conflict with the
// folders Open folders opens, a file not copied with `why`, its reason in
// plain words, and the last failed request.
function cloudValue(record, problem) {
    var conflicts = record.conflicts.slice(0, CONFLICTS_MAX).map(function (c) {
        var out = { kind: c.kind, pairLabel: c.pairLabel, path: c.path, since: msOf(c.since), dirs: reviewDirs(c) };
        if (c.kind === "renamed") out.to = c.to;
        if (c.kind === "unreadable-on-drive") out.why = reasonText(c.reason);
        return out;
    });
    var value = {
        state: record.state,
        paused: record.paused,
        units: record.units,
        lastSuccess: msOf(record.lastSuccess),
        staleAfter: msOf(record.staleAfter),
        lastError: publishedError(record.lastError),
        pairs: record.pairs.map(function (p) {
            var review = record.conflicts.filter(function (c) { return c.pair === p.id; }).length;
            return { id: p.id, label: p.label, remote: p.remote, state: p.state, lastSuccess: msOf(p.lastSuccess), staleAfter: msOf(p.staleAfter), lastError: publishedError(p.lastError), review: review };
        }),
        conflicts: conflicts,
        conflictCount: record.conflicts.length,
        problem: problem
    };
    while (value.conflicts.length > 0 && JSON.stringify(value).length > CLOUD_BYTES_MAX) value.conflicts.pop();
    return value;
}

function reviewLine(count) {
    return count === 1 ? "1 file to review" : count + " files to review";
}

// Where the whole sync stands: { text, tone, icon, cause }, or null before
// the first record. CLOUD is the published `cloud` value. Hourly sync not
// set up comes first, then no folder pair, then Connect needed or a
// failed sync, of the whole sync or of any pair, since the runner ranks a
// running pair above another pair's failure; then files to review, then
// the state, an idle one by the data's age. `cause` is the state,
// `no-pairs` or `review`.
function headline(cloud, now) {
    if (cloud === undefined || cloud === null) return null;
    if (cloud.state === "not-set-up")
        return cloud.units === "absent" ? withCause(STATE_VIEW["not-set-up"], "not-set-up") : withCause(NO_PAIRS, "no-pairs");
    var danger = DANGER_STATES.filter(function (state) {
        return cloud.state === state || cloud.pairs.some(function (p) { return p.state === state; });
    });
    if (danger.length > 0) return withCause(STATE_VIEW[danger[0]], danger[0]);
    if (cloud.conflictCount > 0) return { text: reviewLine(cloud.conflictCount), tone: "warning", icon: "cloud-alert", cause: "review" };
    return withCause(stateView(cloud.state, cloud.staleAfter, now), cloud.state);
}

// The states that need the user, in the runner's order (PAIR_PRECEDENCE).
var DANGER_STATES = ["authorization-required", "error"];

function withCause(view, cause) {
    return { text: view.text, tone: view.tone, icon: view.icon, cause: cause };
}

// The Settings page's sentence that gives HEAD's cause, or "": what to do
// with files to review, or the last error behind a failure or an offline
// sync.
function headlineHint(cloud, head) {
    if (head.cause === "review") return REVIEW_HINT;
    if (head.tone === "danger" || head.cause === "offline") return errorText(cloud.lastError, true);
    return "";
}

// What PAIR reads as wherever a pair shows, the window's badge, the
// tooltip and the Settings status: its state, and an idle pair by its own
// files to review before the data's age, in the headline's review tone.
function pairView(pair, now) {
    if (pair.state === "idle" && pair.review > 0) return { text: reviewLine(pair.review), tone: "warning", icon: "cloud-alert" };
    return stateView(pair.state, pair.staleAfter, now);
}

// Each pair's line as the Settings status and the tooltip show it: its
// label and pairView, never a file name.
function pairLines(pairs, now) {
    return pairs.map(function (p) {
        return p.label + ": " + pairView(p, now).text;
    });
}

// The `sync` value: the headline, a line per pair and the headline's cause.
function syncValue(cloud, now) {
    var head = headline(cloud, now);
    var value = { tone: head.tone, text: head.text };
    if (cloud.pairs.length > 0) value.lines = pairLines(cloud.pairs, now).slice(0, LINES_MAX);
    var hint = headlineHint(cloud, head);
    if (hint !== "") value.hint = hint;
    return value;
}

// The `schedule` value: whether the hourly units are what install writes
// now, with Set up hourly sync while they are not.
function scheduleValue(units) {
    if (units === "installed") return { tone: "ok", text: "On", hint: SCHEDULE_HINT };
    if (units === "absent") return { tone: "warning", text: "Not set up", action: true, hint: SCHEDULE_HINT };
    if (units === "stale") return { tone: "warning", text: "Needs setup", action: true, hint: SCHEDULE_HINT };
    throw new Error("cloud-sync: units " + JSON.stringify(units) + " is not one of " + UNITS.join(", "));
}

// A pair's second line, in the window row and the Settings Folder pairs
// line: its Google Drive folder, or Both ways when that folder carries
// the pair's own name, where repeating it would say nothing.
function pairDrive(pair) {
    return pair.remote === pair.label ? "Both ways" : pair.remote;
}

// The `pairs` value of CLOUD: each pair's label and pairDrive line, with Add a
// folder pair while there is none and Remove a folder pair once one
// exists; while the runner cannot read the list it offers Reset, the one
// change the runner accepts in that state.
function pairsValue(cloud) {
    if (!pairListValid(cloud)) return { tone: "danger", text: "Not readable", hint: pairListResetHint(cloud.lastError), action: "reset" };
    var pairs = cloud.pairs;
    if (pairs.length === 0) return { tone: "warning", text: "None", action: "add", hint: NO_PAIRS_HINT };
    return {
        tone: "ok",
        text: pairs.length === 1 ? "1 folder pair" : pairs.length + " folder pairs",
        lines: pairs.map(function (p) { return p.label + ": " + pairDrive(p); }).slice(0, LINES_MAX),
        action: "remove"
    };
}

// The `keys` presence list: the client ID and secret, each with the
// account the masked field stores.
function keyItems(presence) {
    return [["Client ID", "client-id"], ["Client secret", "client-secret"]].map(function (pair) {
        var account = pair[1];
        return { label: pair[0], value: presence[account].presence, secret: account };
    });
}

// The `account` connection value from the probe's PRESENCE and RECORD.
function signInValue(presence, record) {
    var states = ["client-id", "client-secret", "token"].map(function (a) { return presence[a].presence; });
    if (states.indexOf("locked") !== -1) return { tone: "warning", text: "Keyring locked", hint: "Unlock your keyring to sync." };
    if (states.indexOf("unavailable") !== -1) return { tone: "warning", text: "Unknown", hint: "VGS cannot read your keyring." };
    if (states[0] !== "present" || states[1] !== "present") return { tone: "info", text: "Not connected", hint: "Add the client ID and secret first." };
    if (states[2] !== "present") return { tone: "warning", text: "Not connected", action: "signIn" };
    var refused = record !== null && record.pairs.some(function (p) {
        return p.state === "authorization-required" && p.lastError !== null && p.lastError.kind === "authorization-refused";
    });
    if (refused) return { tone: "danger", text: "Connect refused", action: "reconnect", hint: "Google Drive did not accept Connect." };
    var user = presence.token.user;
    var named = user === undefined ? "" : "Connected as " + user + ".";
    return { tone: "ok", text: "Connected", hint: named !== "" && named.length <= HINT_MAX ? named : "Connected.", action: "signOut" };
}

// The values the service publishes (the manifest's `status`): from the
// record, `sync`, the headline; `schedule`, the hourly units; `pairs`;
// `cloud`, the data the widget and the window draw; and `lastSync`, the
// time of the last complete sync, or null to clear it. From the probe,
// the key list and connection. RECORD and PRESENCE are null
// until their first answer, which leaves their values out.
function statusValues(record, presence, problem, now) {
    var values = {};
    if (record !== null) {
        var cloud = cloudValue(record, problem);
        values.sync = syncValue(cloud, now);
        values.schedule = scheduleValue(record.units);
        values.pairs = pairsValue(cloud);
        values.firstPair = pairListValid(cloud) && cloud.pairs.length > 0
            ? { tone: "ok", text: "A folder pair is ready", action: false }
            : { tone: "warning", text: "Add your first folder pair", action: pairListValid(cloud) };
        if (!pairListValid(cloud)) values.firstPair.hint = "Choose Start the folder pair list again under [Folder pairs](page:vgs.cloud-sync/Details)";
        values.cloud = cloud;
        values.lastSync = cloud.lastSuccess;
    }
    if (presence !== null) {
        values.keys = keyItems(presence);
        values.account = signInValue(presence, record);
        values.connection = Object.assign({}, values.account, { action: values.account.action === "signIn" || values.account.action === "reconnect" });
        // Connecting belongs to the required step. This row keeps account
        // maintenance beside its fact on Details.
        if (values.account.action === "signIn") delete values.account.action;
    }
    return values;
}

// The status keys whose value differs between PREVIOUS and NEXT, the
// values last published and those to publish: a key NEXT lacks and
// PREVIOUS holds is written as null, which clears it.
function changedKeys(previous, next) {
    var keys = Object.keys(next).filter(function (k) { return JSON.stringify(previous[k]) !== JSON.stringify(next[k]); });
    Object.keys(previous).forEach(function (k) {
        if (!hasOwn(next, k) && previous[k] !== null) keys.push(k);
    });
    return keys;
}

// A headline tone as the bar draws it.
var BAR_TONES = { ok: "calm", info: "calm", warning: "warning", danger: "danger" };

// The bar widget: { hidden, icon, tone, spinning, badge }, the headline's
// icon and tone (calm, warning or danger), and badge the count of files to
// review as BarItem's `count` text, "" for none. The icon is hidden until
// a folder pair exists, so a bar that places it before setup shows nothing
// to act on, but not while the pair list cannot be read. CLOUD is the
// published value, undefined before the first.
function widgetView(cloud, now) {
    if (cloud === undefined || cloud === null || (cloud.pairs.length === 0 && pairListValid(cloud))) return { hidden: true, icon: "cloud", tone: "calm", spinning: false, badge: "" };
    var head = headline(cloud, now);
    return { hidden: false, icon: head.icon, tone: BAR_TONES[head.tone], spinning: cloud.state === "running", badge: cloud.conflictCount > 0 ? String(cloud.conflictCount) : "" };
}

// The widget's tooltip: the headline as its title, then one line per pair,
// its label and state, the files to review when the headline does not say
// so, and the last sync's time in the shell's wording (TIME_TEXT).
function widgetTooltip(cloud, now, timeText) {
    if (cloud === undefined || cloud === null) return { title: "Cloud Sync", details: "" };
    var head = headline(cloud, now);
    var lines = pairLines(cloud.pairs, now);
    if (cloud.conflictCount > 0 && head.cause !== "review") lines.push(reviewLine(cloud.conflictCount));
    if (cloud.lastSuccess !== null) lines.push("Last sync " + timeText(cloud.lastSuccess, now));
    return { title: "Cloud Sync: " + head.text, details: lines.join("\n") };
}

// The window's subtitle: { text, tone, lines }, the headline, then
// [{ text, tone }] lines, tone "" or "danger": the last complete sync,
// the first file to review, the pause, the last error and the last failed
// request.
function windowStatus(cloud, now, timeText) {
    var head = headline(cloud, now);
    var lines = [{ text: cloud.lastSuccess === null ? "No complete sync yet" : "Last complete sync " + timeText(cloud.lastSuccess, now), tone: "" }];
    if (cloud.conflicts.length > 0) lines.push({ text: "First file to review: " + cloud.conflicts[0].path, tone: "" });
    if (cloud.paused)
        lines.push({ text: (head.cause === "paused" ? "" : "Paused. ") + "The hourly sync copies nothing until you resume it.", tone: "" });
    if (cloud.lastError !== null) lines.push({ text: errorText(cloud.lastError), tone: head.tone === "danger" ? "danger" : "" });
    if (cloud.problem !== "") lines.push({ text: cloud.problem, tone: "danger" });
    return { text: head.text, tone: head.tone, lines: lines };
}

// One folder pair's row in the window: { id, label, secondary, icon, text,
// tone }, its pairDrive line, since a ListItem's secondary line elides and
// the long form does not fit beside the state and Remove, and its pairView
// as a Badge tone.
function pairRow(pair, now) {
    var view = pairView(pair, now);
    return { id: pair.id, label: pair.label, secondary: pairDrive(pair), icon: "folder-sync", text: view.text, tone: badgeTone(view.tone) };
}

// One conflict's row in the window: { label, detail, folder, dirs }, its
// path, what happened, with the reason in plain words for a file it could
// not copy, the line that names the folder of the copy the detail speaks of
// ("" for none), and the folders Open folders opens. The window wraps
// each line, so none is cut.
function conflictRow(conflict) {
    var what = conflictText(conflict.kind);
    if (conflict.kind === "renamed") what += " New name: " + conflict.to + ".";
    if (conflict.kind === "unreadable-on-drive") what += " " + conflict.why;
    return { label: conflict.path, detail: what, folder: conflictFolder(conflict), dirs: conflict.dirs };
}

// The folder line of CONFLICT: a change on both sides names the folder
// that keeps the older copy, reviewDirs' second, when the runner kept
// one; a Drive deletion and a file not copied name the local folder,
// reviewDirs' first, the latter only while an older copy is here.
function conflictFolder(conflict) {
    var dir = conflict.kind === "both-changed" ? conflict.dirs[1] : hasOwn(CONFLICT_FOLDER_TEXT, conflict.kind) ? conflict.dirs[0] : undefined;
    return dir === undefined ? "" : CONFLICT_FOLDER_TEXT[conflict.kind] + dir;
}

// The review list by folder pair, in the order the list first names each:
// [{ label, rows }], so a pair's label stands on its own line.
function conflictGroups(conflicts) {
    var groups = [];
    conflicts.forEach(function (c) {
        var group = groups.find(function (g) { return g.label === c.pairLabel; });
        if (group === undefined) {
            group = { label: c.pairLabel, rows: [] };
            groups.push(group);
        }
        group.rows.push(conflictRow(c));
    });
    return groups;
}

// Whether a run would copy PAIR: not paused, and not waiting for a key or
// Connect only the user can add. A locked keyring is not one: the run
// reads the keyring again, so Sync now stays the way to retry after an
// unlock.
function pairCanSync(pair) {
    if (pair.state === "paused") return false;
    return pair.state !== "authorization-required" || (pair.lastError !== null && pair.lastError.kind === "credential-locked");
}

// The window's footer for CLOUD, undefined before the first value:
// { primary, pause, add }. Once the hourly units are installed the primary
// is Resume while the sync is paused with a folder pair, since a run then
// copies nothing, else Sync now, enabled only when a sync can start: no
// sync runs and a folder pair can sync (pairCanSync); the headline already
// says why it cannot. Else it is Set up hourly sync. `pause` is Pause or
// Resume while a folder pair exists and the primary is not Resume, else
// null; `add`, the footer's Add a folder pair, shows only beside a folder
// pair, since the empty pair list offers its own.
function footerView(cloud) {
    var known = cloud !== undefined && cloud !== null;
    var hasPairs = known && cloud.pairs.length > 0;
    var canSync = known && cloud.state !== "running" && cloud.pairs.some(pairCanSync);
    var resume = { text: "Resume", icon: "play", action: "resume" };
    var primary = known && cloud.units !== "installed"
        ? { text: "Set up hourly sync", icon: "cloud-cog", action: "setup", enabled: true }
        : hasPairs && cloud.paused ? Object.assign({ enabled: true }, resume)
        : { text: "Sync now", icon: "refresh-cw", action: "sync", enabled: canSync };
    var pause = !hasPairs || primary.action === "resume" ? null : cloud.paused ? resume : { text: "Pause", icon: "pause", action: "pause" };
    return { primary: primary, pause: pause, add: hasPairs };
}

// The line under the review list when it shows only part of the list.
function moreConflicts(cloud) {
    var rest = cloud.conflictCount - cloud.conflicts.length;
    return rest <= 0 ? "" : rest === 1 ? "1 more file to review" : rest + " more files to review";
}

// The notification RECORD asks for while it needs the user, or null:
// { title, message, tone }.
function notification(record) {
    if (record.attention === null) return null;
    var reasons = record.attention.reasons;
    if (reasons.indexOf("authorization-required") !== -1)
        return { title: "Cloud Sync needs Connect", message: errorText(record.lastError === null ? { kind: "authorization-refused" } : record.lastError), tone: "danger" };
    if (reasons.indexOf("error") !== -1)
        return { title: "Cloud Sync failed", message: errorText(record.lastError), tone: "danger" };
    if (reasons.indexOf("conflicts") !== -1)
        return { title: "Cloud Sync kept files for review", message: reviewLine(record.conflicts.length) + ". Open Cloud Sync to see them.", tone: "warning" };
    if (reasons.indexOf("units-stale") !== -1)
        return { title: "Cloud Sync needs setup", message: "[Select Set up hourly sync in Cloud Sync Details](page:vgs.cloud-sync/Details).", tone: "warning" };
    return null;
}

// The epoch milliseconds at which RECORD's idle data turns old, after NOW,
// or null: the service republishes then, since nothing else changes.
function nextStale(record, now) {
    var times = [record.staleAfter].concat(record.pairs.map(function (p) { return p.staleAfter; }))
        .map(msOf).filter(function (t) { return t !== null && t > now; });
    return times.length === 0 ? null : Math.min.apply(null, times);
}
