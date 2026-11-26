// The Jarvis page's words for the account and key readers' typed outcomes
// (docs/architecture/design-system.md § Copy). A diagnostic key never
// reaches a value here; the readers log it. Shared by Accounts.qml,
// Keys.qml, KeyEditor.qml and their tests.

/**
 * The search's own row on the Apps and local models list, or null for a
 * whole search: OUTCOME { kind: "found", partial } with partial "",
 * "entry-limit", "parent-unreadable" or "account-limit", or { kind:
 * "failed", reason }, reason the reader's safe failure key
 * (AccountProviders.probeFailure). A partial search says what it missed;
 * a failed one what Jarvis could not read. Any other outcome reads as a
 * failed check. No row counts what the search found.
 */
function searchRow(outcome) {
    var row = function (tone, text, secondary) { return { id: "search", label: text, secondary: secondary, state: { tone: tone, text: tone === "danger" ? "Not checked" : "Some may be missing" } }; };
    if (outcome.kind === "found") {
        if (outcome.partial === "") return null;
        if (outcome.partial === "entry-limit") return row("warning", "Search stopped at 10,000 folder entries",
            "Jarvis reads at most 10,000 entries in a folder, so large folders do not slow the search. Add a missed folder with Find apps and local models.");
        if (outcome.partial === "parent-unreadable") return row("warning", "Some of your folders could not be read", "Add a missed folder with Find apps and local models.");
        if (outcome.partial === "account-limit") return row("warning", "Jarvis shows up to 32 apps, keys and local models",
            "The limit keeps the lists easy to use. Remove one you do not use before you add another.");
    }
    var match = outcome.kind === "failed" ? /^jarvis-accounts: ([a-z-]+)=/.exec(outcome.reason) : null;
    var field = match === null ? "" : match[1];
    var again = "Jarvis searches again when it starts and after a sign-in or a key change.";
    if (field === "directory") return row("danger", "Could not read an account folder you named", again);
    if (field === "added") return row("danger", "Could not read your saved accounts", again);
    return row("danger", "Jarvis could not check for apps and local models", again);
}

/**
 * The Apps and local models list (the manifest's `apps`) for APPS, the
 * account reader's signed-in apps, local servers and environment keys,
 * each { id, label, value, state, source, plan, ... } as Accounts.status
 * gives them, then the search's own row (searchRow) for OUTCOME.
 */
function appRows(apps, outcome) {
    var rows = apps.map(function (app) {
        var tone = app.value === "present" ? "ok" : app.value === "signed-out" ? "warning" : app.value === "locked" ? "warning" : "danger";
        var text = app.value === "signed-out" ? "Signed out" : stateLabel(app.state, app.source);
        var secondary = app.update === true ? "Needs Pi 1.1.0 or later"
            : app.mismatch === true ? "The email does not match the folder name"
            : app.plan !== "" ? app.plan + " plan" : "";
        var row = { id: app.id, label: app.label, state: { tone: tone, text: text } };
        if (secondary !== "") row.secondary = secondary;
        return row;
    });
    var search = searchRow(outcome);
    return search === null ? rows : rows.concat([search]);
}

// The plain reason a failed Check reads with, by the cause Accounts.verify
// records, so the row says what failed and not the cause's key.
var CHECK_REASONS = [
    [/^http-(401|403)$/, "the provider refused the key"],
    [/^http-429$/, "the provider limits requests now"],
    [/^http-5[0-9][0-9]$/, "the provider had a problem"],
    [/^http-/, "the provider refused the request"],
    [/^network-/, "Jarvis could not reach the provider"],
    [/^key-/, "Jarvis could not read the key"],
    [/^keyring-locked$/, "the keyring is locked"],
    [/^no-inference$/, "the provider sent no answer"]
];
function checkReason(reason) {
    for (var i = 0; i < CHECK_REASONS.length; i++)
        if (CHECK_REASONS[i][0].test(reason)) return CHECK_REASONS[i][1];
    return "the check did not finish";
}

var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
// AT, milliseconds since the epoch, as the local date a person reads.
function checkDate(at) {
    var date = new Date(at);
    return date.getDate() + " " + MONTHS[date.getMonth()] + " " + date.getFullYear();
}

/**
 * The status of KEY, one of Accounts.status's `keys`, on its row of
 * Providers and keys: the keyring's state first, then CHECKING, true while
 * the user's Check of it runs, then its last Check. Presence is never
 * validity, so a stored key no Check answered reads Not checked yet.
 */
function keyStatus(key, checking) {
    if (key.presence === "locked") return { tone: "warning", text: "Keyring locked" };
    if (key.presence === "absent") return { tone: "danger", text: "Missing from the keyring" };
    if (key.presence === "unsupported") return { tone: "warning", text: "Jarvis cannot use this provider" };
    if (key.presence !== "present") return { tone: "warning", text: "Could not read the keyring" };
    if (checking) return { tone: "info", text: "Checking" };
    if (!key.checkable) return { tone: "info", text: "Check unavailable for this provider" };
    switch (key.check.kind) {
    case "working": return { tone: "ok", text: "Working (checked " + checkDate(key.check.at) + ")" };
    case "failed": return { tone: "danger", text: ("Check failed: " + checkReason(key.check.reason)).slice(0, 60) };
    case "unreadable": return { tone: "warning", text: "Could not read the last check" };
    default: return { tone: "info", text: "Not checked yet" };
    }
}

/**
 * The features that use the key whose account id is ID under SETTINGS,
 * the Jarvis settings: the AI model, each backup model by its place, and
 * the voice while a cloud voice (VOICE, AccountProviders.cloudVoice of the
 * Voice provider, null for Local) names it.
 */
function usedBy(id, settings, voice) {
    var features = [];
    if (settings.brain === id) features.push("AI model");
    var backups = Array.isArray(settings.fallbacks) ? settings.fallbacks : [];
    backups.forEach(function (backup, index) {
        if (backup !== null && typeof backup === "object" && backup.brain === id)
            features.push(backups.length === 1 ? "Backup model" : "Backup model " + (index + 1));
    });
    if (voice !== null && settings.voiceAccount === id) features.push("Voice");
    return features;
}

// FEATURES as one phrase: "AI model and Voice", "AI model, Backup model 1
// and Voice".
function featureList(features) {
    if (features.length <= 1) return features.join("");
    return features.slice(0, -1).join(", ") + " and " + features[features.length - 1];
}

/**
 * The Providers and keys list (the manifest's `providerKeys`) for KEYS,
 * Accounts.status's stored keys, CHECKING the account id whose Check runs,
 * "" for none, SETTINGS the Jarvis settings and VOICE the cloud voice they
 * name (usedBy). A row reads its name, its provider where the name does
 * not already say it, the features that use it, and its status; a key
 * Jarvis stored offers Edit and Remove, one another app stored offers
 * Remove from Jarvis, and a present key whose provider takes a Check
 * offers Check; the row whose Check runs offers none of them. Each
 * question says what it cannot take back.
 */
function keyRows(keys, checking, settings, voice) {
    return keys.map(function (key) {
        var company = key.providerLabel;
        var features = usedBy(key.id, settings, voice);
        var uses = features.length === 0 ? "Not in use" : "Used by " + featureList(features);
        var named = key.label.toLowerCase().indexOf(company.toLowerCase()) !== -1;
        // One key operation runs at a time (KeyEditor.qml).
        var idle = checking !== key.id;
        var actions = key.own && idle ? ["edit"] : [];
        var confirm = {};
        if (key.presence === "present" && key.checkable && idle) {
            actions.push("check");
            confirm.check = "Jarvis sends one short request to " + company + " with " + key.model + ". It can cost a small amount.";
        }
        var after = features.length === 0 ? "" : " " + featureList(features) + " then need" + (features.length === 1 ? "s" : "") + " another key.";
        if (key.own && idle) {
            actions.push("remove");
            confirm.remove = "The key is deleted from your keyring." + after;
        } else if (idle) {
            actions.push("forget");
            confirm.forget = "The key stays in the keyring entry another app saved." + after;
        }
        var row = { id: key.id, label: key.label, secondary: (named ? "" : company + " · ") + uses,
            state: keyStatus(key, checking === key.id), actions: actions, confirm: confirm };
        if (key.own) row.choice = key.provider;
        return row;
    });
}

/**
 * What the key editor reads under its fields after a save that ended with
 * CODE, the exit status of keys.js add-key, other than 0. A store that
 * may have acted is never said to have kept the key before it.
 */
function saveFailure(code) {
    switch (code) {
    case 3: return "Paste the key first.";
    case 4: return "That text is longer than an API key. Copy the key again from the provider's page.";
    case 5: return "A key name takes at most 80 characters. Choose a shorter name.";
    case 6: return "The key list is full. Remove a key you no longer use, then try again.";
    case 8: return "A key with that name is already stored. Choose another name, or use Edit to replace it.";
    default: return "Jarvis could not confirm that the key was saved. If your keyring is locked, unlock it, then try again.";
    }
}

/**
 * The hint of one key row, "" for none: a row that could not be checked
 * says so, in place of the reader's diagnostic key.
 */
function keyHint(row) {
    return row.value === "unavailable" ? "Could not check this key" : "";
}

/**
 * The words for an account's state, state its kind and source its source's
 * kind: the setup terminal's Status column, and the start of accountHint
 * for a row that is not signed out.
 * Any other state reads as one that could not be checked.
 */
function stateLabel(state, source) {
    switch (state) {
    case "signed-in": return "Signed in";
    case "found": return source === "cli" ? "Not signed in" : source === "local" ? "Running on this computer" : "Key found";
    case "unchecked": return source === "cli" ? "Found; Verify checks sign-in" : "Could not check";
    case "verifying": return "Checking that it answers";
    case "verified": return "Answered a test request";
    case "locked": return "Keyring locked";
    default: return "Could not check";
    }
}

/**
 * The hint of one account item from Accounts.status(), "" for none: its
 * state, source, plan (the label names the email), whether its Pi needs an update and whether
 * the email disagrees with the folder name. A signed-out row's badge already says so, so its hint names only a
 * mismatch. A hint of one sentence ends with no full stop, and each
 * sentence of a longer one ends with one (docs/architecture/design-system.md § Copy).
 */
function accountHint(account) {
    var mismatch = account.mismatch === true ? "The email does not match the folder name" : "";
    if (account.value === "signed-out") return mismatch;
    if (account.update === true) return "Jarvis needs Pi 1.1.0 or later: choose [Review all missing or outdated tools under Optional tools on the Setup tab](page:vgs.jarvis/Setup) to use this setup";
    var text = stateLabel(account.state, account.source);
    if (account.state === "signed-in")
        text += account.plan !== "" ? ", " + account.plan + " plan" : "";
    if (mismatch !== "") text += ". " + mismatch + ".";
    return text.slice(0, 200);
}

if (typeof module !== "undefined") module.exports = { searchRow: searchRow, appRows: appRows, checkReason: checkReason,
    keyStatus: keyStatus, usedBy: usedBy, keyRows: keyRows, saveFailure: saveFailure, keyHint: keyHint, stateLabel: stateLabel, accountHint: accountHint };
