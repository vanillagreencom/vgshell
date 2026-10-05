.pragma library

// What the service publishes and the widget, the panel and the Settings
// page draw from the helper's readings (backend/usage.js). Plain functions
// over plain values, which scripts/test-ai-usage.js runs under node.

// A used share at or above it takes the warning tone.
var WARNING_PERCENT = 80;
var NAMES = { claude: "Claude Code", codex: "Codex" };
// Only a Claude Code sign-in reads expired: its token is read, never refreshed.
var EXPIRED = "Open Claude Code to refresh the sign-in";

function copyWindows(windows) {
    return windows.map(function (row) { return { name: row.name, usedPercent: row.usedPercent, resetsAt: row.resetsAt }; });
}

function previousOf(previous, id) {
    if (previous === null || previous === undefined) return null;
    for (var i = 0; i < previous.accounts.length; i++)
        if (previous.accounts[i].id === id) return previous.accounts[i];
    return null;
}

/**
 * The usage to publish after a read: { accounts, readAt }. READING is the
 * helper's output, or null for a run that failed as a whole; PREVIOUS is
 * the usage published before, or null. A failed read of an account, or a
 * failed run, keeps the last windows read for it marked stale; with none,
 * the account holds no windows. readAt is when a run last answered.
 */
function merge(previous, reading, now) {
    if (reading === null) {
        if (previous === null || previous === undefined) return { accounts: [], readAt: null };
        return { accounts: previous.accounts.map(function (row) {
            var copy = Object.assign({}, row, { windows: copyWindows(row.windows) });
            if (row.state === "ok") copy.state = "stale";
            return copy;
        }), readAt: previous.readAt };
    }
    return { accounts: reading.accounts.map(function (row) {
        var last = previousOf(previous, row.id);
        if (row.state === "failed" && last !== null && last.windows.length > 0)
            return { id: row.id, provider: row.provider, label: row.label, email: row.email || last.email,
                plan: row.plan || last.plan, state: "stale", windows: copyWindows(last.windows) };
        return { id: row.id, provider: row.provider, label: row.label, email: row.email, plan: row.plan,
            state: row.state, windows: copyWindows(row.windows) };
    }), readAt: now };
}

// The accounts with a sign-in: every one but a folder no tool signed in to.
function signedIn(usage) {
    if (usage === null || usage === undefined) return [];
    return usage.accounts.filter(function (row) { return row.state !== "signed-out"; });
}

/**
 * The bar widget: shown while an account is signed in; percent, the
 * highest used share of a window it shows, or null while no window holds
 * one; tone "warning" from WARNING_PERCENT, else "normal".
 */
function widget(usage) {
    var accounts = signedIn(usage);
    var percent = null;
    var expired = false;
    var stale = false;
    for (var i = 0; i < accounts.length; i++) {
        var row = accounts[i];
        if (row.state === "expired") expired = true;
        if (row.state === "stale") stale = true;
        for (var j = 0; j < row.windows.length; j++)
            if (percent === null || row.windows[j].usedPercent > percent) percent = row.windows[j].usedPercent;
    }
    var tooltip = percent === null ? "No usage figures yet" : "Highest plan limit used: " + Math.round(percent) + "%";
    if (expired) tooltip += ". " + EXPIRED;
    else if (stale) tooltip += ". The last check failed; figures may be old";
    return { shown: accounts.length > 0, percent: percent, tone: percent !== null && percent >= WARNING_PERCENT ? "warning" : "normal",
        text: percent === null ? "" : Math.round(percent) + "%", tooltip: tooltip };
}

// The Settings row of PROVIDER's sign-in: a state value, whose action, Sign
// in, applies while none of its accounts is signed in.
function signIn(usage, provider) {
    var rows = signedIn(usage).filter(function (row) { return row.provider === provider; });
    if (rows.some(function (row) { return row.state === "ok" || row.state === "stale"; }))
        return { tone: "ok", text: rows.length === 1 ? "Signed in" : "Signed in to " + rows.length + " accounts" };
    if (rows.some(function (row) { return row.state === "expired"; }))
        return { tone: "warning", text: EXPIRED };
    if (rows.length > 0) return { tone: "danger", text: "Usage could not be read" };
    return { tone: "info", text: "Not signed in", action: true };
}

function windowLabel(name) {
    if (name === "five_hour") return "5-hour limit";
    if (name === "seven_day") return "Weekly limit";
    var model = /^seven_day_([a-z0-9_]+)$/.exec(name);
    if (model !== null) {
        var words = model[1].split("_").filter(Boolean).join(" ");
        return "Weekly " + words.charAt(0).toUpperCase() + words.slice(1) + " limit";
    }
    var minutes = /^minutes_([0-9]+)$/.exec(name);
    if (minutes !== null) {
        var count = Number(minutes[1]);
        return count % 1440 === 0 ? count / 1440 + "-day limit" : count % 60 === 0 ? count / 60 + "-hour limit" : count + "-minute limit";
    }
    return name === "primary" ? "Short limit" : "Long limit";
}

// When a window resets, from now in milliseconds since the epoch.
function resetText(resetsAt, now) {
    if (resetsAt === null || resetsAt === undefined) return "No reset time";
    var minutes = Math.ceil((resetsAt - now) / 60000);
    if (minutes <= 0) return "Resets now";
    if (minutes < 60) return "Resets in " + minutes + " min";
    var hours = Math.floor(minutes / 60);
    if (hours < 24) return "Resets in " + hours + " h " + (minutes % 60) + " min";
    return "Resets in " + Math.floor(hours / 24) + " d " + (hours % 24) + " h";
}

// The panel's rows: one per signed-in account, its title, its detail line
// and each window's label, share, tone and reset line.
function panel(usage, now) {
    return signedIn(usage).map(function (row) {
        var title = NAMES[row.provider] + (row.label === "default" ? "" : " · " + row.label);
        var detail = [row.email, row.plan === "" ? "" : row.plan.charAt(0).toUpperCase() + row.plan.slice(1) + " plan"]
            .filter(Boolean).join(" · ");
        var note = row.state === "expired" ? EXPIRED
            : row.state === "stale" ? "The last check failed. These figures may be old."
            : row.state === "failed" ? "Usage could not be read." : "";
        return { id: row.id, title: title, detail: detail, note: note, windows: row.windows.map(function (item) {
            return { label: windowLabel(item.name), percent: item.usedPercent, text: Math.round(item.usedPercent) + "%",
                tone: item.usedPercent >= WARNING_PERCENT ? "warning" : "normal", reset: resetText(item.resetsAt, now) };
        }) };
    });
}
