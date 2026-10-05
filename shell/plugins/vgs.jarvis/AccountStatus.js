// The Jarvis page's words for the account and key readers' typed outcomes
// (docs/architecture/copy.md). A diagnostic key never reaches a value here;
// the readers log it. Shared by Accounts.qml, Keys.qml and their tests.

// Accounts.js MAX_ROWS: the most accounts one search shows.
var SHOWN_ACCOUNTS = 32;

function counted(count, one, many) {
    return count === 1 ? "1 " + one : count + " " + many;
}

/**
 * The `accountSearch` state for an outcome: { kind: "found", found,
 * partial } with partial "", "entry-limit" or "account-limit", or
 * { kind: "failed", reason }, reason the reader's safe failure key
 * (AccountProviders.probeFailure). Accounts is offered unless the saved
 * list it edits is unreadable or Jarvis could not run the check. Any other
 * outcome reads as a failed check.
 */
function searchValue(outcome) {
    if (outcome.kind === "found") {
        var found = counted(outcome.found, "account found", "accounts found");
        if (outcome.partial === "entry-limit")
            return { tone: "warning", text: found + ". Your home folder is too large to search fully. Add an account by hand with Accounts.", action: true };
        if (outcome.partial === "account-limit")
            return { tone: "warning", text: "Showing the first " + SHOWN_ACCOUNTS + " accounts found", action: true };
        if (outcome.partial === "")
            return outcome.found > 0 ? { tone: "ok", text: found, action: true }
                : { tone: "info", text: "No account found yet", action: true };
    }
    var match = outcome.kind === "failed" ? /^jarvis-accounts: ([a-z-]+)=([a-z0-9-]+)$/.exec(outcome.reason) : null;
    var field = match === null ? "" : match[1];
    if (field === "directory" || (field === "discovery" && match[2] === "directory-unreadable"))
        return { tone: "warning", text: "Could not read your home folder. Add an account by hand with Accounts.", action: true };
    if (field === "added")
        return { tone: "danger", text: "Could not read your saved accounts", action: false };
    return { tone: "danger", text: "Jarvis could not check for accounts", action: false };
}

/**
 * The `keyStore` state for { kind: "listed", count } or { kind: "failed" }.
 * Add key is offered in both: it opens the keyring itself.
 */
function keysValue(outcome) {
    if (outcome.kind === "listed")
        return outcome.count > 0 ? { tone: "ok", text: counted(outcome.count, "key stored", "keys stored"), action: true }
            : { tone: "info", text: "No key stored yet", action: true };
    return { tone: "warning", text: "Could not check your keyring", action: true };
}

/**
 * The hint of one account item from Accounts.status(): its state, source,
 * plan, email and whether the email disagrees with the folder name.
 */
function accountHint(account) {
    var text;
    switch (account.state) {
    case "signed-in":
        text = "Signed in" + (account.plan !== "" ? ", " + account.plan + " plan" : "")
            + (account.email !== "" ? ", " + account.email : "") + ".";
        break;
    case "found":
        text = account.source === "cli" ? "Found, not signed in."
            : account.source === "local" ? "Running on this computer."
            : "Key found.";
        break;
    case "verifying": text = "Checking that it answers."; break;
    case "verified": text = "Answered a test request."; break;
    case "locked": text = "Your keyring is locked."; break;
    default: text = "Could not check this account.";
    }
    if (account.mismatch === true) text += " The email does not match the folder name.";
    return text.slice(0, 200);
}

if (typeof module !== "undefined") module.exports = { searchValue: searchValue, keysValue: keysValue, accountHint: accountHint };
