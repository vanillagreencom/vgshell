// The Jarvis page's words for the account and key readers' typed outcomes
// (docs/architecture/design-system.md § Copy). A diagnostic key never
// reaches a value here; the readers log it. Shared by Accounts.qml,
// Keys.qml and their tests.

function counted(count, one, many) {
    return count === 1 ? "1 " + one : count + " " + many;
}

/**
 * The `accountSearch` state for an outcome: { kind: "found", found,
 * partial } with partial "", "entry-limit", "parent-unreadable" or
 * "account-limit", or { kind: "failed", reason }, reason the reader's safe
 * failure key (AccountProviders.probeFailure). A search, whole or partial,
 * offers Accounts; a failed check does not, since the folders or saved list
 * Accounts works on could not be read or Jarvis could not run the check.
 * Any other outcome reads as a failed check.
 */
function searchValue(outcome) {
    if (outcome.kind === "found") {
        var found = counted(outcome.found, "account found", "accounts found");
        if (outcome.partial === "entry-limit")
            return { tone: "warning", text: found + ". Your home folder is too large to search fully. Add an account by hand with Accounts.", action: true };
        if (outcome.partial === "parent-unreadable")
            return { tone: "warning", text: found + ". Some of your folders could not be read. Add an account by hand with Accounts.", action: true };
        if (outcome.partial === "account-limit")
            return { tone: "warning", text: found + ". Jarvis shows no more than these.", action: true };
        if (outcome.partial === "")
            return outcome.found > 0 ? { tone: "ok", text: found, action: true }
                : { tone: "info", text: "No account found yet", action: true };
    }
    var match = outcome.kind === "failed" ? /^jarvis-accounts: ([a-z-]+)=/.exec(outcome.reason) : null;
    var field = match === null ? "" : match[1];
    if (field === "directory")
        return { tone: "danger", text: "Could not read an account folder you named", action: false };
    if (field === "added")
        return { tone: "danger", text: "Could not read your saved accounts", action: false };
    return { tone: "danger", text: "Jarvis could not check for accounts", action: false };
}

/**
 * The `keyStore` state for { kind: "listed", rows }, rows the key presence
 * reader's, or { kind: "failed" }. Add key is offered in each: it opens the
 * keyring itself.
 */
function keysValue(outcome) {
    if (outcome.kind !== "listed") return { tone: "warning", text: "Could not check your keyring", action: true };
    var rows = outcome.rows;
    if (rows.length === 0) return { tone: "info", text: "No key stored yet", action: true };
    var stored = counted(rows.length, "key stored", "keys stored");
    for (var i = 0; i < rows.length; i++)
        if (rows[i].value !== "present") return { tone: "warning", text: stored + ". Some are not ready to use.", action: true };
    return { tone: "ok", text: stored, action: true };
}

/**
 * The hint of one key row, "" for none: a row that could not be checked
 * says so, in place of the reader's diagnostic key.
 */
function keyHint(row) {
    return row.value === "unavailable" ? "Could not check this key." : "";
}

/**
 * The words for an account's state, state its kind and source its source's
 * kind: the setup terminal's Status column, and the start of accountHint.
 * Any other state reads as one that could not be checked.
 */
function stateLabel(state, source) {
    switch (state) {
    case "signed-in": return "Signed in";
    case "found": return source === "cli" ? "Not signed in" : source === "local" ? "Running on this computer" : "Key found";
    case "verifying": return "Checking that it answers";
    case "verified": return "Answered a test request";
    case "locked": return "Keyring locked";
    default: return "Could not check";
    }
}

/**
 * The hint of one account item from Accounts.status(): its state, source,
 * plan, email and whether the email disagrees with the folder name.
 */
function accountHint(account) {
    var text = stateLabel(account.state, account.source);
    if (account.state === "signed-in")
        text += (account.plan !== "" ? ", " + account.plan + " plan" : "") + (account.email !== "" ? ", " + account.email : "");
    text += ".";
    if (account.mismatch === true) text += " The email does not match the folder name.";
    return text.slice(0, 200);
}

if (typeof module !== "undefined") module.exports = { searchValue: searchValue, keysValue: keysValue, keyHint: keyHint,
    stateLabel: stateLabel, accountHint: accountHint };
