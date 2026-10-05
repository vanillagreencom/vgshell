.pragma library

// What the service publishes and the widget, the panel and the Settings
// page draw from the helper's readings (backend/usage.js). Plain functions
// over plain values, which scripts/test-ai-usage.js runs under node.

// A used share at or above it takes the warning tone.
var WARNING_PERCENT = 80;
var NAMES = { claude: "Claude Code", codex: "Codex" };
// Only a Claude Code sign-in reads expired: its token is read, never refreshed.
var EXPIRED = "Open Claude Code to refresh the sign-in";
var NO_PLAN = "Signed in with an API key, which has no plan limits";

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

// The accounts with a plan sign-in: every one but a folder no tool signed
// in to and a sign-in, such as a Codex API key, that has no plan limits.
function signedIn(usage) {
    if (usage === null || usage === undefined) return [];
    return usage.accounts.filter(function (row) { return row.state !== "signed-out" && row.state !== "no-plan"; });
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
    var rows = (usage === null || usage === undefined ? [] : usage.accounts)
        .filter(function (row) { return row.provider === provider && row.state !== "signed-out"; });
    var plans = rows.filter(function (row) { return row.state !== "no-plan"; });
    if (plans.some(function (row) { return row.state === "ok" || row.state === "stale"; }))
        return { tone: "ok", text: plans.length === 1 ? "Signed in" : "Signed in to " + plans.length + " accounts" };
    if (plans.some(function (row) { return row.state === "expired"; }))
        return { tone: "warning", text: EXPIRED };
    if (plans.length > 0) return { tone: "danger", text: "Usage could not be read" };
    if (rows.length > 0) return { tone: "info", text: NO_PLAN };
    return { tone: "info", text: "Not signed in", action: true };
}

// What a window measures: its length in minutes, null when the tool names
// none, and the model it counts alone, "" for every model.
function limitOf(name) {
    if (name === "five_hour") return { minutes: 300, model: "" };
    if (name === "seven_day") return { minutes: 10080, model: "" };
    var model = /^seven_day_([a-z0-9_]+)$/.exec(name);
    if (model !== null) return { minutes: 10080, model: model[1].split("_").filter(Boolean).join(" ") };
    var minutes = /^minutes_([0-9]+)$/.exec(name);
    if (minutes !== null) return { minutes: Number(minutes[1]), model: "" };
    return { minutes: null, model: "" };
}

function windowLabel(name) {
    var limit = limitOf(name);
    var length = limit.minutes === null ? (name === "primary" ? "Short" : "Long")
        : limit.minutes === 10080 ? "Weekly"
        : limit.minutes % 1440 === 0 ? limit.minutes / 1440 + "-day"
        : limit.minutes % 60 === 0 ? limit.minutes / 60 + "-hour" : limit.minutes + "-minute";
    return length + (limit.model === "" ? "" : " " + limit.model.charAt(0).toUpperCase() + limit.model.slice(1)) + " limit";
}

// How long until a window resets, from now, both in milliseconds since the
// epoch: { kind: "none" } with no reset time, { kind: "now" } once it has
// passed, else { kind: "in", days, hours, minutes }, the whole minutes left
// rounded up and split.
function resetIn(resetsAt, now) {
    if (resetsAt === null || resetsAt === undefined) return { kind: "none" };
    var minutes = Math.ceil((resetsAt - now) / 60000);
    if (minutes <= 0) return { kind: "now" };
    return { kind: "in", days: Math.floor(minutes / 1440), hours: Math.floor(minutes / 60) % 24, minutes: minutes % 60 };
}

function resetText(resetsAt, now) {
    var left = resetIn(resetsAt, now);
    if (left.kind === "none") return "No reset time";
    if (left.kind === "now") return "Resets now";
    if (left.days > 0) return "Resets in " + left.days + " d " + left.hours + " h";
    if (left.hours > 0) return "Resets in " + left.hours + " h " + left.minutes + " min";
    return "Resets in " + left.minutes + " min";
}

// The only lines of the helper's stderr the service logs: its own keyed
// `ai-usage: <key>=<value>` pairs, never a line a tool or node printed.
function keyed(line) {
    return /^ai-usage: [a-z]+=[a-z0-9-]+( [a-z]+=[a-z0-9-]+)*$/.test(line);
}

// The panel's rows: one per signed-in account, with its fields, its title,
// its detail line and note, and each window's share, tone, reset time and
// the words for them.
function panel(usage, now) {
    return signedIn(usage).map(function (row) {
        var title = NAMES[row.provider] + (row.label === "default" ? "" : " \u00b7 " + row.label);
        var detail = [row.email, row.plan === "" ? "" : row.plan.charAt(0).toUpperCase() + row.plan.slice(1) + " plan"]
            .filter(Boolean).join(" \u00b7 ");
        var note = row.state === "expired" ? EXPIRED
            : row.state === "stale" ? "The last check failed. These figures may be old."
            : row.state === "failed" ? "Usage could not be read." : "";
        return { id: row.id, provider: row.provider, label: row.label, email: row.email, plan: row.plan, state: row.state,
            title: title, detail: detail, note: note, windows: row.windows.map(function (item) {
                return { name: item.name, percent: item.usedPercent, tone: item.usedPercent >= WARNING_PERCENT ? "warning" : "normal",
                    resetIn: resetIn(item.resetsAt, now), label: windowLabel(item.name), text: Math.round(item.usedPercent) + "%",
                    reset: resetText(item.resetsAt, now) };
            }) };
    });
}
