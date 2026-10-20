.pragma library

// vgs.google-drive's pure decisions, run under node by
// scripts/test-google-drive-logic.js: the one judge of the runner's status
// record and probe answer, the status values the service publishes from
// them, and what the bar widget, its popover and the notification draw
// from those values. `headline` is the one statement of where the sync
// stands: the bar, its tooltip, the popover and the Details `sync` value
// all read it. The runner, bin/google-drive, owns every rule about the sync; this
// file only reads its answers.

// The runner's overall states and a pair's states (bin/google-drive,
// renderStatus).
var STATES = ["idle", "running", "paused", "offline", "authorization-required", "error", "not-set-up"];
var PAIR_STATES = ["idle", "running", "paused", "offline", "authorization-required", "error"];
var UNITS = ["installed", "absent", "stale"];
var CONFLICT_KINDS = ["both-changed", "removed-locally", "removed-on-drive", "renamed", "unreadable-on-drive", "duplicate-identical", "duplicate-different"];
var DUPLICATE_KINDS = ["duplicate-identical", "duplicate-different"];
// Whether a review record needs the user or only says what the sync did
// (bin/google-drive needsOf decides it; this file only reads it).
var NEEDS = ["you", "nothing"];
// A review row's key, bin/google-drive conflictKey: a dismissal names it.
var CONFLICT_KEY = /^[0-9a-f]{16}$/;
// The kinds whose row has an action on this computer: each leaves the file
// here, where the user checks it or deletes it. A name Drive holds twice
// and a file the download could not copy are fixed in Google Drive, so
// their rows have none.
var LOCAL_ACTION_KINDS = ["both-changed", "removed-locally", "removed-on-drive", "renamed"];
var PRESENCES = ["present", "absent", "locked", "unavailable"];
// The credential accounts of the manifest's `secrets`, in the order the
// Setup section lists them (bin/google-drive probe prints the same set).
var ACCOUNTS = ["client-id", "client-secret", "token"];

// The conflicts the popover lists: the published values share one 64 KiB
// ceiling (PluginLogic.STATUS_MAX_BYTES) with the rest, and a removed
// Drive folder can make thousands. The popover states the rest as a count.
var CONFLICTS_MAX = 20;
var CLOUD_BYTES_MAX = 40000;
// A state's lines and hint, PluginLogic.STATUS_LIST_MAX and
// STATUS_HINT_MAX: a longer value is refused whole.
var LINES_MAX = 64;
var HINT_MAX = 200;
// A Google account address as the runner stores it on a token
// (bin/google-drive authorize): printable, at most 254 characters, one `@`.
var ADDRESS_MAX = 254;
var NOT_PRINTABLE = /[\u0000-\u001f\u007f-\u009f\u2028\u2029]/;

// What each state reads as and the tone it takes: `tone` is a status
// `state` tone (PluginLogic.STATUS_STATE_TONES). `idle` reads by the data's
// age (freshness). A pair reads by these; the whole sync by `headline`.
var STATE_VIEW = {
    running: { text: "Syncing", tone: "info", icon: "cloud-sync" },
    paused: { text: "Paused", tone: "info", icon: "cloud-off" },
    offline: { text: "Offline", tone: "warning", icon: "cloud-off" },
    "authorization-required": { text: "Sign-in needed", tone: "danger", icon: "cloud-alert" },
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
    offline: "Google Drive cannot be reached. VGS tries again at the next sync.",
    "authorization-refused": "Google did not accept the sign-in. [Sign in again on the Google Drive Setup tab](page:vgs.google-drive/Setup).",
    "credential-absent": "A Google Cloud key or the sign-in is missing. Add both keys, then [sign in on the Google Drive Setup tab](page:vgs.google-drive/Setup).",
    "credential-locked": "Your keyring is locked. Unlock it to sync.",
    "source-missing": "A Google Drive folder of a folder pair does not exist.",
    "rclone-missing": "rclone is not installed.",
    "secret-tool-missing": "VGS cannot read your keyring.",
    "secret-tool-failed": "VGS cannot read your keyring.",
    "secret-tool-timeout": "VGS cannot read your keyring.",
    interrupted: "The last sync stopped before it finished.",
    "pairs-invalid": "The folder pair list is not valid, so VGS copies nothing."
};
var ERROR_DEFAULT = "The sync stopped with an error. VGS tries again at the next sync.";
// A missing sign-in, the token's credential-absent.
var SIGNED_OUT_TEXT = "Google Drive is not signed in. [Sign in on the Google Drive Setup tab](page:vgs.google-drive/Setup).";
// Each review row's one line: what the sync did, then what the user does,
// or that nothing is lost and how to remove the row from the list. A
// variant key is the record's kind, or a kind and its case
// (conflictVariant). {to} is a Drive rename's new name, {owner} the address
// that owns a doubled name's copies. VGS keeps a displaced copy for 30 days
// (bin/google-drive KEEP_MS); Drive keeps an earlier revision of an upload
// under its own retention (developer.md).
var CONFLICT_TEXT = {
    "both-changed-kept": "Changed here and on Google Drive. The Google Drive version is here now. Compare it with the copy that was here, which VGS keeps for 30 days.",
    "both-changed": "Changed here and on Google Drive. The copy here was newer, so VGS copied it to Google Drive. If you need the other version, open the file's version history in Google Drive.",
    "removed-locally": "Removed here. VGS put it back from Google Drive, so nothing is lost. If you do not want it, delete it here and in Google Drive.",
    "removed-on-drive": "Removed from Google Drive. VGS put it back from this computer, so nothing is lost. If you do not want it, delete it here and in Google Drive.",
    renamed: "Renamed to {to} on Google Drive. VGS deletes no file, so both names are now here and on Google Drive. If you do not want this name, delete it here and in Google Drive.",
    "duplicate-identical": "Google Drive has identical copies of this file, so nothing is lost. To remove it from this list, keep one copy in Google Drive and delete the others.",
    "duplicate-identical-shared": "Google Drive has identical copies of this file, so nothing is lost. Only {owner}, who shared them with you, can remove a copy.",
    "duplicate-identical-unowned": "Google Drive has identical copies of this file, so nothing is lost. Only their owner can remove a copy.",
    "duplicate-different": "Google Drive has different files with this name, and VGS copied only one of them. In Google Drive, rename one so VGS copies both, or delete the one you do not need.",
    "duplicate-different-shared": "Google Drive has different files with this name, and VGS copied only one of them. Only {owner}, who shared them with you, can remove one.",
    "duplicate-different-unowned": "Google Drive has different files with this name, and VGS copied only one of them. Only their owner can remove one."
};
// Why a limit a row's line states holds, by the line's variant: a line
// that states a limit has an info that says why
// (docs/architecture/design-system.md § Copy).
var CONFLICT_INFO = {
    "both-changed-kept": "VGS deletes a kept copy after 30 days, so old copies do not fill your disk. To keep the copy for longer, move it out of its folder."
};
// A review row's mark: a file that needs the user, else a file that
// needs no action by its kind, a doubled name, a file not copied, or a
// file the sync kept.
var NEEDS_ICON = "file-exclamation-point";
var NOTE_ICONS = { "duplicate-identical": "copy", "duplicate-different": "copy", "unreadable-on-drive": "link-2-off" };
var NOTE_ICON = "file-check";
// What stands between a folder pair's name and each folder of a row's
// path, as "Documents › Taxes".
var PLACE_MARK = " \u203a ";
// rclone's reason for a file it could not copy, as the review row's line
// for it. The dangling shortcut row reads rclone v1.75.1's "failed to
// open source object: can't read dangling shortcut". The raw reason stays
// in the runner's record and log.
var REASON_TEXT = [
    { pattern: /dangling shortcut/, text: "This Google Drive shortcut points to a file VGS cannot open, so nothing was copied. If you do not need the shortcut, remove it in Google Drive." }
];
var REASON_DEFAULT = "VGS could not copy this file from Google Drive. It tries again at each sync. If the file still does not copy, check that it opens in Google Drive.";

var PAIR_RULE_TEXT = {
    shape: "Folder pair {id} is not a valid folder pair.",
    id: "Folder pair {id} has an invalid ID.",
    label: "Folder pair {id} has an invalid name.",
    remote: "Folder pair {id} has an invalid Google Drive folder.",
    "drive-root": "Folder pair {id} uses the whole Drive.",
    local: "Folder pair {id} has an invalid folder on this computer.",
    "home-or-above": "Folder pair {id} uses your home folder or a folder above it.",
    "repository-root": "Folder pair {id} uses a Git repository.",
    "state-overlap": "Folder pair {id} overlaps the folder where VGS keeps its Google Drive records.",
    "vgs-overlap": "Folder pair {id} overlaps a VGS folder.",
    "unit-overlap": "Folder pair {id} overlaps the folder for system services.",
    "repository-inside": "Folder pair {id} holds a Git repository.",
    "duplicate-id": "Folder pair {id} has the same ID as another folder pair.",
    "local-overlap": "Folder pair {id} overlaps another folder pair.",
    "remote-overlap": "Folder pair {id} overlaps another Google Drive folder pair."
};

var PAIRS_RESET_HINT = "Start again to keep the damaged file and make an empty list.";

// The runner's exit while its rename from the plugin's previous name is
// held (bin/google-drive, the rename): a sync of that name's service runs,
// its timer could not be disabled, or systemctl gave no state. Nothing
// tells the shell when the hold ends, so the service asks again after
// HELD_RETRY_MS while the runner answers this.
var RUNNER_HELD = 75;
var HELD_RETRY_MS = 15000;

// Why the runner held the rename, read from its refusal line,
// `google-drive: refused: migration=held <reason>` (holdRename). First
// match wins; a held answer no row matches is `other`.
var HELD_REASONS = [
    { pattern: /migration=held reason=old-service-(active|activating|deactivating|reloading|refreshing)\b/, reason: "old-sync" },
    { pattern: /migration=held reason=old-service-unknown\b/, reason: "old-sync-unknown" },
    { pattern: /migration=held systemctl=missing\b/, reason: "systemd-missing" },
    { pattern: /migration=held systemctl=failed\b/, reason: "old-timer" }
];

// The Settings sync value while the runner holds the rename, by reason.
// It stands with or without a status record, since a held runner writes
// none.
var HELD_VIEW = {
    "old-sync": { tone: "info", text: "Waiting", hint: "Google Drive is finishing a sync under its earlier name, Cloud Sync. VGS shows the sync status when it ends." },
    "old-sync-unknown": { tone: "warning", text: "Waiting", hint: "VGS could not tell whether a sync under the earlier name, Cloud Sync, still runs. VGS tries again soon." },
    "systemd-missing": { tone: "warning", text: "Waiting", hint: "VGS could not find systemd, which runs the hourly sync under the earlier name, Cloud Sync. VGS tries again soon." },
    "old-timer": { tone: "warning", text: "Waiting", hint: "VGS could not stop the hourly sync under the earlier name, Cloud Sync. VGS tries again soon." },
    other: { tone: "warning", text: "Waiting", hint: "VGS could not finish the move from the earlier name, Cloud Sync. VGS tries again soon." }
};

function heldReason(line) {
    var row = HELD_REASONS.find(function (r) { return r.pattern.test(line); });
    return row === undefined ? "other" : row.reason;
}

// What a failed request to the runner reads as, by its operation.
var PROBLEM_TEXT = {
    start: "VGS could not start a sync.",
    pause: "VGS could not pause the Google Drive sync.",
    resume: "VGS could not resume the Google Drive sync.",
    status: "VGS could not read the Google Drive status.",
    probe: "VGS could not check the Google Drive keys.",
    dismiss: "VGS could not remove the file from the list."
};

// Where a file that needs the user is shown: the bar icon's popover.
var NEEDS_HINT = "Select the Google Drive icon in the bar to see what to do.";

// The Google Drive folder and the folder on this computer a pair joins,
// as a pair's second line shows them.
var PAIR_ARROW = " ⇄ ";
// A row's printable label and secondary line, PluginLogic.STATUS_LABEL_MAX
// and STATUS_TEXT_MAX: the runner admits a 64-character label and paths of
// any length, and a longer value is refused whole, so each is cut with an
// ellipsis.
var ROW_LABEL_MAX = 60;
var ROW_TEXT_MAX = 200;

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
    return isObject(p) && !hasOwn(p, "direction") && isText(p.id) && isText(p.label) && isText(p.remote) && isText(p.local) && p.local.charAt(0) === "/"
        && PAIR_STATES.indexOf(p.state) !== -1 && isTime(p.lastSuccess) && isTime(p.staleAfter) && errorOk(p.lastError);
}

// A doubled name carries `mine` and, only when it is not the user's,
// may carry `owner`, an address; no other kind carries either.
function conflictOk(c) {
    if (!isObject(c)) return false;
    var duplicate = DUPLICATE_KINDS.indexOf(c.kind) !== -1;
    return CONFLICT_KINDS.indexOf(c.kind) !== -1 && isText(c.pair) && isText(c.pairLabel) && isText(c.path)
        && ((c.kind === "unreadable-on-drive" && !hasOwn(c, "localPath")) || (isText(c.localPath) && c.localPath.charAt(0) === "/"))
        && (c.kind !== "both-changed" || !hasOwn(c, "storedPath") || (isText(c.storedPath) && c.storedPath.charAt(0) === "/"))
        && (c.kind !== "renamed" || isText(c.to)) && (c.kind !== "unreadable-on-drive" || isText(c.reason)) && isTime(c.since)
        && NEEDS.indexOf(c.needs) !== -1 && isText(c.key) && CONFLICT_KEY.test(c.key)
        && (duplicate ? typeof c.mine === "boolean" : !hasOwn(c, "mine"))
        && (!hasOwn(c, "owner") || (duplicate && c.mine === false && isAddress(c.owner)));
}

// The one judge of the runner's status record, status.json or `status`'s
// line (bin/google-drive renderStatus): { ok: true, record } or
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
    if (doc.needsYou !== doc.conflicts.filter(function (c) { return c.needs === "you"; }).length) return { ok: false, error: "status=needsYou" };
    if (!Array.isArray(doc.dismissed) || !doc.dismissed.every(function (k) { return isText(k) && CONFLICT_KEY.test(k); })) return { ok: false, error: "status=dismissed" };
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
        if (!hasOwn(STATE_VIEW, state)) throw new Error("google-drive: state " + JSON.stringify(state) + " is not one of " + STATES.join(", "));
        return STATE_VIEW[state];
    }
    if (staleAfter === null) return NOT_SYNCED;
    return now < staleAfter ? CURRENT : OUT_OF_DATE;
}

function badgeTone(tone) {
    return BADGE_TONES[tone];
}

// ERROR as a sentence. A sentence that sends the user to a step links
// the Setup tab, which the Details tab's sync value opens as well.
function errorText(error) {
    if (error === null) return "";
    if (error.kind === "credential-absent" && error.account === "token") return SIGNED_OUT_TEXT;
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

function reasonText(reason) {
    var row = REASON_TEXT.find(function (r) { return r.pattern.test(reason); });
    return row === undefined ? REASON_DEFAULT : row.text;
}

function problemText(operation, firstLine) {
    if (operation === "") return "";
    if (operation === "start" && firstLine.indexOf("units=absent") !== -1) return "Set up the hourly sync again first.";
    return hasOwn(PROBLEM_TEXT, operation) ? PROBLEM_TEXT[operation] : "VGS could not reach the Google Drive sync.";
}


// Whether CONFLICT has an action on this computer: a kind whose file
// stays here (LOCAL_ACTION_KINDS) and that the runner names a local path
// for. A kind whose fix is in Google Drive has none.
function hasLocalAction(conflict) {
    return LOCAL_ACTION_KINDS.indexOf(conflict.kind) !== -1 && conflict.localPath !== undefined;
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

// The folder of the copy a download displaced, kept beside the pair's
// records, or undefined: Show older copy opens it.
function copyFolder(conflict) {
    if (conflict.kind === "both-changed" && conflict.storedPath !== undefined) return dirname(conflict.storedPath);
    return undefined;
}

// CONFLICTS with the rows that need the user first, each part in the
// record's order, so neither the review list's cap nor its byte ceiling
// cuts a row that needs the user while a row that needs nothing stands.
function needsFirst(conflicts) {
    return conflicts.filter(function (c) { return c.needs === "you"; }).concat(conflicts.filter(function (c) { return c.needs !== "you"; }));
}

// The published `cloud` data the widget and the popover draw: the record
// with times as epoch milliseconds, each pair with its folder on this
// computer, `local`, and `needsYou`, the count of its own files that need
// the user, `needsYou`, the record's count of rows that need the user,
// the review list needs-first and capped, `conflictCount`, the count of
// its rows, and the last failed request. The review list and its count
// leave out each row that needs nothing whose key the record's `dismissed`
// names; a row that needs the user is never left out. Each conflict
// carries its `key`, the record's `needs`, `localAction`, whether it
// has an action on this computer, `localPath`, the file on this computer
// while the runner names one, `copyFolder`, the folder of a kept copy, a
// file not copied `why`, its line from rclone's reason, and a doubled
// name `mine` and, when the record names one, `owner`.
function cloudValue(record, problem) {
    var shown = record.conflicts.filter(function (c) { return c.needs === "you" || record.dismissed.indexOf(c.key) === -1; });
    var conflicts = needsFirst(shown).slice(0, CONFLICTS_MAX).map(function (c) {
        var out = { kind: c.kind, pairLabel: c.pairLabel, path: c.path, since: msOf(c.since), needs: c.needs, localAction: hasLocalAction(c) };
        out.key = c.key;
        if (c.localPath !== undefined) out.localPath = c.localPath;
        var copy = copyFolder(c);
        if (copy !== undefined) out.copyFolder = copy;
        if (c.kind === "renamed") out.to = c.to;
        if (c.kind === "unreadable-on-drive") out.why = reasonText(c.reason);
        if (DUPLICATE_KINDS.indexOf(c.kind) !== -1) {
            out.mine = c.mine;
            if (c.owner !== undefined) out.owner = c.owner;
        }
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
            var own = record.conflicts.filter(function (c) { return c.pair === p.id; });
            return { id: p.id, label: p.label, remote: p.remote, local: p.local, state: p.state, lastSuccess: msOf(p.lastSuccess), staleAfter: msOf(p.staleAfter), lastError: publishedError(p.lastError),
                needsYou: own.filter(function (c) { return c.needs === "you"; }).length };
        }),
        conflicts: conflicts,
        conflictCount: shown.length,
        needsYou: record.needsYou,
        problem: problem
    };
    while (value.conflicts.length > 0 && JSON.stringify(value).length > CLOUD_BYTES_MAX) value.conflicts.pop();
    return value;
}

// COUNT files that need the user, the record's `needsYou`.
function needsLine(count) {
    return count === 1 ? "1 file needs you" : count + " files need you";
}

// Where the whole sync stands: { text, tone, icon, cause }, or null before
// the first record. CLOUD is the published `cloud` value. No folder pair
// comes first, then a folder pair whose hourly units are absent, which an
// install at its add could not finish, then Sign-in needed or a failed
// sync, of the whole sync or of any pair, since the runner ranks a running
// pair above another pair's failure; then the files that need the user,
// then the state, an idle one by the data's age. A row that needs
// nothing never raises the headline. `cause` is the state, `no-pairs` or
// `needs-you`. With no folder pair nothing asks for the hourly sync: the
// first pair installs it (bin/google-drive pairAddVerb).
function headline(cloud, now) {
    if (cloud === undefined || cloud === null) return null;
    if (cloud.state === "not-set-up")
        return cloud.pairs.length > 0 ? withCause(STATE_VIEW["not-set-up"], "not-set-up") : withCause(NO_PAIRS, "no-pairs");
    var danger = DANGER_STATES.filter(function (state) {
        return cloud.state === state || cloud.pairs.some(function (p) { return p.state === state; });
    });
    if (danger.length > 0) return withCause(STATE_VIEW[danger[0]], danger[0]);
    if (cloud.needsYou > 0) return { text: needsLine(cloud.needsYou), tone: "warning", icon: "cloud-alert", cause: "needs-you" };
    return withCause(stateView(cloud.state, cloud.staleAfter, now), cloud.state);
}

// The states that need the user, in the runner's order (PAIR_PRECEDENCE).
var DANGER_STATES = ["authorization-required", "error"];

function withCause(view, cause) {
    return { text: view.text, tone: view.tone, icon: view.icon, cause: cause };
}

// The sentence the Details `sync` value gives for HEAD's cause, or "":
// where to see the files that need the user, the hourly sync a folder pair
// waits for, or the last error behind a failure or an offline sync.
function headlineHint(cloud, head) {
    if (head.cause === "needs-you") return NEEDS_HINT;
    if (head.cause === "not-set-up") return SCHEDULE_HINTS.failed;
    if (head.tone === "danger" || head.cause === "offline") return errorText(cloud.lastError);
    return "";
}

// What PAIR reads as wherever a pair shows, the tooltip and the Details
// sync lines: its state, and an idle pair by its own files that need the
// user before the data's age, in the headline's tone for them.
function pairView(pair, now) {
    if (pair.state === "idle" && pair.needsYou > 0) return { text: needsLine(pair.needsYou), tone: "warning", icon: "cloud-alert" };
    return stateView(pair.state, pair.staleAfter, now);
}

// Each pair's line as the Details sync value and the tooltip show it: its
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

// The `schedule` value's hint by what it reads.
var SCHEDULE_HINTS = {
    on: "Google Drive syncs every hour while you are logged in, also while VGS is closed. It turned on with your first folder pair.",
    off: "Google Drive syncs every hour while you are logged in. The hourly sync turns on with your first folder pair.",
    stale: "The hourly sync is from an earlier version of VGS. Select Set up again to update it.",
    failed: "VGS could not turn on the hourly sync. Select Set up again beside Hourly sync."
};

// Whether the hourly units UNITS want Set up again: while they are out of
// date, or absent beside a folder pair, whose add could not install them.
// With no folder pair they are absent until the first add installs them
// (bin/google-drive pairAddVerb), so nothing asks for a step there.
function setupOffered(units, hasPairs) {
    if (UNITS.indexOf(units) === -1) throw new Error("google-drive: units " + JSON.stringify(units) + " is not one of " + UNITS.join(", "));
    return units === "stale" || (units === "absent" && hasPairs);
}

// The `schedule` Setup step: whether the hourly units are what install
// writes now, with Set up again while setupOffered. Before the first
// folder pair, which installs them, the user has nothing to do here, so
// the step reads Not available, its hint saying what turns it on.
function scheduleValue(units, hasPairs) {
    if (!setupOffered(units, hasPairs)) return units === "installed" ? { tone: "ok", text: "On", hint: SCHEDULE_HINTS.on } : { tone: "info", text: "Off", hint: SCHEDULE_HINTS.off, available: false };
    return units === "stale" ? { tone: "warning", text: "Out of date", action: true, hint: SCHEDULE_HINTS.stale } : { tone: "warning", text: "Not on", action: true, hint: SCHEDULE_HINTS.failed };
}

// TEXT cut to MAX characters with an ellipsis.
function cut(text, max) {
    return text.length <= max ? text : text.slice(0, max - 1) + "\u2026";
}

// A pair's second line in the Settings row: its Google
// Drive folder and its folder on this computer, the second under HOME
// written from `~`.
function pairFolders(pair, home) {
    var local = home !== "" && (pair.local === home || pair.local.indexOf(home + "/") === 0) ? "~" + pair.local.slice(home.length) : pair.local;
    return "Drive/" + pair.remote + PAIR_ARROW + local;
}

// What a pair's Settings row says of it: its files that need the user as
// a warning, which the page draws as a chip, else its state.
function pairState(pair, now) {
    if (pair.needsYou > 0) return { tone: "warning", text: needsLine(pair.needsYou) };
    var view = stateView(pair.state, pair.staleAfter, now);
    return { tone: view.tone, text: view.text };
}

// The row the Settings list holds while the runner cannot read the pair
// list: it holds no pair then, and the repair is the Setup tab's.
var UNREADABLE_ROW = { id: "unreadable", label: "The folder pair list cannot be read", secondary: "VGS copies nothing until you start the list again",
    state: { tone: "danger", text: "Not readable" }, actions: [] };

// The `pairs` rows value of CLOUD (PluginLogic, a `rows` entry): one row
// per pair, its label, its folders and its state, each with Remove, whose
// TUI takes the pair's id. While the runner cannot read the pair list it
// holds no pair and refuses every change but the repair, so the list holds
// UNREADABLE_ROW alone, with no Remove. HOME is the user's home folder.
function pairsValue(cloud, now, home) {
    if (!pairListValid(cloud)) return [UNREADABLE_ROW];
    return cloud.pairs.slice(0, LINES_MAX).map(function (p) {
        return { id: p.id, label: cut(p.label, ROW_LABEL_MAX), secondary: cut(pairFolders(p, home), ROW_TEXT_MAX), state: pairState(p, now), actions: ["remove"] };
    });
}

// The `pairList` Setup step: done while the runner reads the pair list,
// else why it cannot, with Start the list again, the one change it accepts
// then. A required step stays on Setup once done, so it is never hidden.
function pairListValue(cloud) {
    if (pairListValid(cloud)) return { tone: "ok", text: "Readable" };
    return { tone: "danger", text: "Not readable", hint: pairListResetHint(cloud.lastError), action: true };
}

// The `firstPair` step: done once a pair exists; while the runner cannot
// read the list, no add can finish it, so it names the repair, the
// `pairList` step.
// Until the probe's PRESENCE, null before its first answer, has a sign-in
// it waits for one, so the steps read in the order a new user takes them:
// the keys, the sign-in, then the first pair, whose sync needs both. The
// Settings tab's Add a folder pair stays open throughout.
function firstPairValue(cloud, presence) {
    if (!pairListValid(cloud))
        return { tone: "warning", text: "The folder pair list cannot be read", available: false, hint: "Select Start the folder pair list again, then add a folder pair" };
    if (cloud.pairs.length > 0) return { tone: "ok", text: "A folder pair is ready" };
    if (presence !== null && presence.token.presence !== "present")
        return { tone: "info", text: "Sign-in needed", available: false, hint: "Sign in to Google first" };
    return { tone: "warning", text: "No folder pair yet", action: true };
}

// Each key's hint and explanation on the Setup tab, by account.
var KEY_ITEMS = [
    { label: "Client ID", account: "client-id", hint: "Ends in .apps.googleusercontent.com",
        info: "The first key of your Google Cloud client. In Google Cloud, open Clients and select your client. Copy the Client ID there and paste it here." },
    { label: "Client secret", account: "client-secret", hint: "Starts with GOCSPX-. Google shows it only once.",
        info: "The second key of your Google Cloud client. Google shows it once, in the window that opens when you create the client. Copy it from there. Lost it? In Google Cloud, open your client, select Add secret and paste the new secret here." }
];

// The `keys` presence list: the client ID and secret, each with the
// account the masked field stores.
function keyItems(presence) {
    return KEY_ITEMS.map(function (item) {
        return { label: item.label, value: presence[item.account].presence, hint: item.hint, info: item.info, secret: item.account };
    });
}

// The presences of the client ID and secret and the token, in that order.
function presences(presence) {
    return ACCOUNTS.map(function (a) { return presence[a].presence; });
}

// The keyring's state when it cannot answer for STATES, or null: locked
// first, since an unlock answers it.
function keyringView(states) {
    if (states.indexOf("locked") !== -1) return { tone: "warning", text: "Keyring locked", hint: "Unlock your keyring so VGS can read the keys" };
    if (states.indexOf("unavailable") !== -1) return { tone: "warning", text: "Keyring not readable", hint: "VGS cannot read your keyring" };
    return null;
}

// The `cloudKeys` step: done while both keys are stored. A key is added
// on its own line under the step, so the step names no action of its own.
function cloudKeysValue(presence) {
    var states = presences(presence).slice(0, 2);
    var keyring = keyringView(states);
    if (keyring !== null) return Object.assign({ available: false }, keyring);
    if (states[0] === "present" && states[1] === "present") return { tone: "ok", text: "Both keys are in your keyring" };
    return { tone: "warning", text: "Add the Client ID and the Client secret" };
}

// Whether Google refused the stored sign-in of a pair of RECORD.
function signInRefused(record) {
    return record !== null && record.pairs.some(function (p) {
        return p.state === "authorization-required" && p.lastError !== null && p.lastError.kind === "authorization-refused";
    });
}

// The `connection` step, Sign in to Google, from the probe's PRESENCE and
// RECORD: not available until both keys are stored, Sign in while no
// sign-in is, Sign in again once Google refused it, else done, with Sign
// out.
function connectionValue(presence, record) {
    var states = presences(presence);
    var keyring = keyringView(states);
    if (keyring !== null) return Object.assign({ available: false }, keyring);
    if (states[0] !== "present" || states[1] !== "present")
        return { tone: "info", text: "Keys needed", available: false, hint: "Add the Client ID and the Client secret first" };
    if (states[2] !== "present") return { tone: "warning", text: "Not signed in", action: "signIn" };
    if (signInRefused(record)) return { tone: "danger", text: "Google did not accept the sign-in", action: "again" };
    return { tone: "ok", text: "Signed in", action: "signOut", hint: SIGN_OUT_HINT };
}
var SIGN_OUT_HINT = "Sign out stops the sync. Your files stay here and in Google Drive.";

// The `account` Details reading: the Google account signed in, by its
// address as the token names it, which the manifest draws as plain text
// while it needs nothing; a sign-in Google refused, or none, says where to
// sign in. Sign out is the `connection` step's.
function accountValue(presence, record) {
    var states = presences(presence);
    var keyring = keyringView(states);
    if (keyring !== null) return keyring;
    if (states[2] !== "present") return { tone: "info", text: "Not signed in", hint: "[Sign in on the Setup tab](page:vgs.google-drive/Setup)" };
    if (signInRefused(record)) return { tone: "danger", text: "Sign-in refused", hint: "[Sign in again on the Setup tab](page:vgs.google-drive/Setup)" };
    var user = presence.token.user;
    return { tone: "ok", text: user !== undefined && user.length <= ROW_TEXT_MAX ? user : "Signed in" };
}

// The values the service publishes (the manifest's `status`): from the
// record, `sync`, the headline; `schedule`, the hourly units; `pairs`,
// the Settings rows; `pairList`, the repair of a list the runner cannot
// read; `firstPair`; `cloud`, the data the widget and the popover draw; and
// `lastSync`, the time of the last complete sync, or null to clear it.
// From the probe, the key list, its step, the sign-in step and the
// account. RECORD and PRESENCE are null until their first answer, which
// leaves their values out. HELD is the heldReason the runner last held the
// rename for, "" for none: while it holds, `sync` says why, with or
// without a record. HOME is the user's home folder, which a pair's
// folders are written from.
function statusValues(record, presence, problem, held, now, home) {
    var values = {};
    if (record !== null) {
        var cloud = cloudValue(record, problem);
        values.sync = syncValue(cloud, now);
        values.schedule = scheduleValue(record.units, cloud.pairs.length > 0);
        values.pairs = pairsValue(cloud, now, home);
        values.pairList = pairListValue(cloud);
        values.firstPair = firstPairValue(cloud, presence);
        values.cloud = cloud;
        values.lastSync = cloud.lastSuccess;
    }
    if (presence !== null) {
        values.keys = keyItems(presence);
        values.cloudKeys = cloudKeysValue(presence);
        values.connection = connectionValue(presence, record);
        values.account = accountValue(presence, record);
    }
    if (held !== "") {
        if (!hasOwn(HELD_VIEW, held)) throw new Error("google-drive: held reason " + JSON.stringify(held) + " is not one of " + Object.keys(HELD_VIEW).join(", "));
        values.sync = Object.assign({}, HELD_VIEW[held]);
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
// icon and tone (calm, warning or danger), and badge the count of files
// that need the user as BarItem's `count` text, "" for none: a row that
// needs nothing never counts. The icon is hidden until a folder pair
// exists, so a bar that places it before setup shows nothing to act on, but
// not while the pair list cannot be read. CLOUD is the published value,
// undefined before the first.
function widgetView(cloud, now) {
    if (cloud === undefined || cloud === null || (cloud.pairs.length === 0 && pairListValid(cloud))) return { hidden: true, icon: "cloud", tone: "calm", spinning: false, badge: "" };
    var head = headline(cloud, now);
    return { hidden: false, icon: head.icon, tone: BAR_TONES[head.tone], spinning: cloud.state === "running", badge: cloud.needsYou > 0 ? String(cloud.needsYou) : "" };
}

// The widget's tooltip: the headline as its title, then one line per pair,
// its label and state, the files that need the user when the headline
// does not say so, and the last sync's time in the shell's wording
// (TIME_TEXT).
function widgetTooltip(cloud, now, timeText) {
    if (cloud === undefined || cloud === null) return { title: "Google Drive", details: "" };
    var head = headline(cloud, now);
    var lines = pairLines(cloud.pairs, now);
    if (cloud.needsYou > 0 && head.cause !== "needs-you") lines.push(needsLine(cloud.needsYou));
    if (cloud.lastSuccess !== null) lines.push("Last sync " + timeText(cloud.lastSuccess, now));
    return { title: "Google Drive: " + head.text, details: lines.join("\n") };
}

// The popover's header: { icon, tone, headline, meta }, the headline's
// icon, its tone as a Badge tone and its text, and the line under it: the
// last complete sync in the shell's wording (TIME_TEXT) and the count of
// folder pairs, or, while the sync stops, when it last synced. It names
// no file.
function panelHeader(cloud, now, timeText) {
    var head = headline(cloud, now);
    var stopped = head.tone === "danger";
    var meta = cloud.lastSuccess === null ? "No complete sync yet" : (stopped ? "Last synced " : "Synced ") + timeText(cloud.lastSuccess, now);
    if (!stopped && cloud.pairs.length > 0) meta += " · " + (cloud.pairs.length === 1 ? "1 folder pair" : cloud.pairs.length + " folder pairs");
    return { icon: head.icon, tone: badgeTone(head.tone), headline: head.text, meta: meta };
}

// What a problem reads as in the popover: a callout that says what
// happened and offers its one fix, an `action` { label, tui } that opens
// the plugin's own TUI or { label, tab } that opens that tab of the
// plugin's page, or null where the fix is the user's alone or the
// footer's Sync now. Its words are plain text: a callout draws no link.
var CALLOUTS = {
    "signed-out": { tone: "danger", title: "Google Drive is not signed in", text: "Your files are safe here and in Google Drive. Sign in to start the sync.", action: { label: "Sign in", tui: "connect" } },
    "sign-in-refused": { tone: "danger", title: "Google signed this computer out", text: "Your files are safe here and in Google Drive. Sign in again to resume the sync.", action: { label: "Sign in again", tui: "connect" } },
    "keys-missing": { tone: "danger", title: "Google Drive needs its keys", text: "Add the Client ID and the Client secret, then sign in. Your files are safe here and in Google Drive.", action: { label: "Add the keys", tab: "Setup" } },
    "keyring-locked": { tone: "danger", title: "Your keyring is locked", text: "VGS cannot read the Google Drive keys. Unlock your keyring, then select Sync now.", action: null },
    offline: { tone: "warning", title: "Google Drive cannot be reached", text: "Your files stay as the last complete sync left them. VGS tries again at the next sync.", action: null },
    "not-set-up": { tone: "warning", title: "The hourly sync is not on", text: "VGS could not turn on the hourly sync, so Google Drive does not sync. Select Set up again beside Hourly sync.", action: { label: "Open Setup", tab: "Setup" } },
    stale: { tone: "warning", title: "The hourly sync is out of date", text: SCHEDULE_HINTS.stale, action: { label: "Open Setup", tab: "Setup" } }
};
var PAIRS_STOPPED = "VGS copies nothing until you start the list again.";
// A failed sync's fix by its error kind, where one place holds it.
var FAILED_ACTIONS = {
    "source-missing": { label: "Check the folder pairs", tab: "Settings" },
    "rclone-missing": { label: "Review the tools", tab: "Setup" }
};
// The error kinds a sign-in or a key answers.
var SIGN_IN_KINDS = ["authorization-refused", "credential-absent", "credential-locked"];

// The error behind the headline's CAUSE, a state: the whole sync's while
// it is in that state, else the first pair's in it, else the whole
// sync's last error.
function causeError(cloud, cause) {
    if (cloud.state === cause && cloud.lastError !== null) return cloud.lastError;
    var pair = cloud.pairs.find(function (p) { return p.state === cause && p.lastError !== null; });
    return pair === undefined ? cloud.lastError : pair.lastError;
}

function signInCallout(error) {
    if (error !== null && error.kind === "credential-locked") return CALLOUTS["keyring-locked"];
    if (error !== null && error.kind === "credential-absent") return CALLOUTS[error.account === "token" ? "signed-out" : "keys-missing"];
    return CALLOUTS["sign-in-refused"];
}

// How the core file route's end REPLY, the answer a review row's open
// receives, reads in the popover: `opened`, `gone` for the route's
// `reason=missing`, else `failed`.
function openFileEnd(reply) {
    if (reply === "ok") return "opened";
    return / reason=missing$/.test(reply) ? "gone" : "failed";
}

// The popover's problem callout for CLOUD, or null: a sign-in, a key or
// the keyring, a failed sync, an offline sync, or hourly units absent
// beside a folder pair or out of date. It takes the place of the error
// lines under the headline.
function problemCallout(cloud, now) {
    var head = headline(cloud, now);
    if (head.cause === "authorization-required" || head.cause === "error") {
        var error = causeError(cloud, head.cause);
        var kind = error === null ? "" : error.kind;
        if (head.cause === "authorization-required" || SIGN_IN_KINDS.indexOf(kind) !== -1) return signInCallout(error);
        if (kind === "pairs-invalid")
            return { tone: "danger", title: "The folder pair list cannot be read", text: pairListProblem(error) + " " + PAIRS_STOPPED, action: { label: "Start the list again", tui: "reset-pairs" } };
        return { tone: "danger", title: "Google Drive could not sync", text: hasOwn(ERROR_TEXT, kind) ? ERROR_TEXT[kind] : ERROR_DEFAULT, action: hasOwn(FAILED_ACTIONS, kind) ? FAILED_ACTIONS[kind] : null };
    }
    if (head.cause === "not-set-up") return CALLOUTS["not-set-up"];
    if (cloud.state === "offline") return CALLOUTS.offline;
    if (cloud.units === "stale") return CALLOUTS.stale;
    return null;
}

// The popover's sentence under its header, or "": a pause, which holds
// every copy; else, with nothing to review and no problem, what the
// state means: up to date, out of date or never synced.
var PAUSED_BODY = "The hourly sync copies nothing until you resume it.";
var STATE_BODY = {
    "out-of-date": "Google Drive missed its hourly sync. Select Sync now to sync again.",
    "not-synced": "No sync has finished yet. Select Sync now to start one."
};
function panelBody(cloud, now) {
    var head = headline(cloud, now);
    if (cloud.paused) return (head.cause === "paused" ? "" : "Paused. ") + PAUSED_BODY;
    if (cloud.conflictCount > 0 || problemCallout(cloud, now) !== null || cloud.state !== "idle") return "";
    var view = stateView(cloud.state, cloud.staleAfter, now);
    if (view === OUT_OF_DATE) return STATE_BODY["out-of-date"];
    if (view === NOT_SYNCED) return STATE_BODY["not-synced"];
    var n = cloud.pairs.length;
    return (n === 1 ? "Your folder pair matches Google Drive." : "Your " + n + " folder pairs match Google Drive.") + " Google Drive syncs every hour, also while VGS is closed.";
}

// The CONFLICT_TEXT key of a published CONFLICT other than a file not
// copied: a change on both sides by whether VGS kept the copy that was
// here, a doubled name by whether the user owns a copy and else whether
// the record names the owner.
function conflictVariant(conflict) {
    if (conflict.kind === "both-changed") return conflict.copyFolder !== undefined ? "both-changed-kept" : "both-changed";
    if (DUPLICATE_KINDS.indexOf(conflict.kind) === -1 || conflict.mine) return conflict.kind;
    return conflict.kind + (conflict.owner !== undefined ? "-shared" : "-unowned");
}

// A row's place: its folder pair's name, then each folder of its path.
function placeOf(conflict) {
    var at = conflict.path.lastIndexOf("/");
    return [conflict.pairLabel].concat(at <= 0 ? [] : conflict.path.slice(0, at).split("/")).join(PLACE_MARK);
}

// One conflict's row in the popover: { name, file, place, detail, info,
// icon, needs, action }, its file's name, the file its name opens, the
// published `localPath`, or null while the file is not on this computer,
// its place (placeOf), its one line (conflictVariant, or for a file not
// copied the line of its reason), why a limit that line states holds
// (CONFLICT_INFO, "" for none), its mark, the published `needs`, and its
// action, or null: { kind: "folder", label, folder }, Show older copy,
// which opens the folder of the copy VGS kept, on a row that needs the
// user and has a local action; { kind: "dismiss", label, key }, Dismiss,
// on every row that needs nothing, which hides it until its record
// changes. A row that needs the user has no Dismiss, since its fix is
// still the user's. The popover wraps each line, so none is cut.
function conflictRow(conflict) {
    var variant = conflict.kind === "unreadable-on-drive" ? "" : conflictVariant(conflict);
    var what = variant === "" ? conflict.why : CONFLICT_TEXT[variant]
        .replace("{to}", function () { return conflict.to; })
        .replace("{owner}", function () { return conflict.owner; });
    var needs = conflict.needs === "you";
    var action = !needs ? { kind: "dismiss", label: "Dismiss", key: conflict.key }
        : conflict.localAction && conflict.copyFolder !== undefined ? { kind: "folder", label: "Show older copy", folder: conflict.copyFolder } : null;
    return { name: conflict.path.slice(conflict.path.lastIndexOf("/") + 1), file: conflict.localPath !== undefined ? conflict.localPath : null, place: placeOf(conflict), detail: what, info: hasOwn(CONFLICT_INFO, variant) ? CONFLICT_INFO[variant] : "",
        icon: needs ? NEEDS_ICON : hasOwn(NOTE_ICONS, conflict.kind) ? NOTE_ICONS[conflict.kind] : NOTE_ICON, needs: conflict.needs, action: action };
}

// The popover's review: { needs, notes, notesLine, moreNeeds, moreNotes },
// the rows that need the user and the rows that need no action, each in
// the published order; the line the rows that need no action fold into,
// "" with none; and the line that counts each part's rows the published
// list leaves out (cloudValue's cap), "" when it holds them all. The
// counts are the record's less its dismissed rows, not the list's.
function reviewView(cloud) {
    var rows = cloud.conflicts.map(conflictRow);
    var needs = rows.filter(function (r) { return r.needs === "you"; });
    var notes = rows.filter(function (r) { return r.needs !== "you"; });
    var noteCount = cloud.conflictCount - cloud.needsYou;
    var needsRest = cloud.needsYou - needs.length, notesRest = noteCount - notes.length;
    return {
        needs: needs,
        notes: notes,
        notesLine: noteCount === 0 ? "" : (noteCount === 1 ? "1 file needs no action" : noteCount + " files need no action") + " · nothing was lost",
        moreNeeds: needsRest <= 0 ? "" : needsRest === 1 ? "1 more file needs you" : needsRest + " more files need you",
        moreNotes: notesRest <= 0 ? "" : notesRest === 1 ? "1 more file needs no action" : notesRest + " more files need no action"
    };
}

// Whether a run would copy PAIR: not paused, and not waiting for a key or
// a sign-in only the user can add. A locked keyring is not one: the run
// reads the keyring again, so Sync now stays the way to retry after an
// unlock.
function pairCanSync(pair) {
    if (pair.state === "paused") return false;
    return pair.state !== "authorization-required" || (pair.lastError !== null && pair.lastError.kind === "credential-locked");
}

// Why Sync now cannot start while the footer shows.
var SYNC_REASONS = {
    paused: "Select Resume first, because the sync is paused",
    running: "Wait until the sync that runs now ends"
};

// The popover's footer for CLOUD, undefined before the first value:
// { shown, pause, sync }. It shows only while a sync can run: a folder
// pair exists, its hourly units are there to start the sync, and the sync
// is paused, which Resume ends, or a folder pair can sync (pairCanSync).
// `pause` is Pause, or Resume while paused; `sync` is Sync now, with the
// reason it cannot start now, "" when it can: a pause or a running sync.
function footerView(cloud) {
    var shown = cloud !== undefined && cloud !== null && cloud.pairs.length > 0 && cloud.units !== "absent" && (cloud.paused || cloud.pairs.some(pairCanSync));
    if (!shown) return { shown: false, pause: null, sync: null };
    return {
        shown: true,
        pause: cloud.paused ? { text: "Resume", icon: "play", action: "resume" } : { text: "Pause", icon: "pause", action: "pause" },
        sync: { text: "Sync now", icon: "refresh-cw", action: "sync", reason: cloud.paused ? SYNC_REASONS.paused : cloud.state === "running" ? SYNC_REASONS.running : "" }
    };
}

// The notification RECORD asks for while it needs the user, or null:
// { title, message, tone }.
function notification(record) {
    if (record.attention === null) return null;
    var reasons = record.attention.reasons;
    if (reasons.indexOf("authorization-required") !== -1)
        return { title: "Google Drive needs a sign-in", message: errorText(record.lastError === null ? { kind: "authorization-refused" } : record.lastError), tone: "danger" };
    if (reasons.indexOf("error") !== -1)
        return { title: "Google Drive sync failed", message: errorText(record.lastError), tone: "danger" };
    if (reasons.indexOf("conflicts") !== -1)
        return { title: "Google Drive needs you", message: needsLine(record.needsYou) + ". " + NEEDS_HINT, tone: "warning" };
    if (reasons.indexOf("units-stale") !== -1)
        return { title: "Google Drive needs setup", message: "The hourly sync is out of date. [Set it up again on the Google Drive Setup tab](page:vgs.google-drive/Setup).", tone: "warning" };
    return null;
}

// The epoch milliseconds at which RECORD's idle data turns old, after NOW,
// or null: the service republishes then, since nothing else changes.
function nextStale(record, now) {
    var times = [record.staleAfter].concat(record.pairs.map(function (p) { return p.staleAfter; }))
        .map(msOf).filter(function (t) { return t !== null && t > now; });
    return times.length === 0 ? null : Math.min.apply(null, times);
}
