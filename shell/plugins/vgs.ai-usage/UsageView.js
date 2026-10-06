.pragma library
.import qs.Commons 1.0 as Commons

// What the service publishes and the widget, the panel and the Settings
// page draw from the helper's readings (backend/usage.js). Plain functions
// over plain values, which scripts/test-ai-usage.js runs under node.

// A used share at or above it takes the warning tone.
var WARNING_PERCENT = 80;
var NAMES = { claude: "Claude Code", codex: "Codex", copilot: "Copilot", gateway: "AI Gateway" };
var EXPIRED = { claude: "Open Claude Code to refresh the sign-in", copilot: "Open Copilot to sign in again" };
var NO_PLAN = "Signed in with an API key, which has no plan limits";
var GATEWAY_ACCOUNT = "ai-gateway";
var LABEL_MAX = 60;
// What the bar's number is under each Bar number setting, for its tooltip.
var BAR_MEANING = { average: "Average of each account's highest limit", "most-left": "Account with the most left",
    "most-used": "Highest plan limit" };

function copyWindows(windows) {
    return windows.map(function (row) { return { name: row.name, usedPercent: row.usedPercent, resetsAt: row.resetsAt }; });
}

function copyCredits(credits) {
    return credits === null || credits === undefined ? null : Object.assign({}, credits);
}

function copyDetails(details) {
    return details === null || details === undefined ? {} : JSON.parse(JSON.stringify(details));
}

function hasDetails(details) {
    return details !== null && details !== undefined && Object.keys(details).length > 0;
}

function previousOf(previous, id) {
    if (previous === null || previous === undefined) return null;
    for (var i = 0; i < previous.accounts.length; i++)
        if (previous.accounts[i].id === id) return previous.accounts[i];
    return null;
}

function accountCopy(row, extra) {
    return Object.assign({ id: row.id, provider: row.provider, label: row.label, email: row.email || "",
        state: row.state, windows: copyWindows(row.windows || []), credits: copyCredits(row.credits), details: copyDetails(row.details) }, extra || {});
}

/**
 * The usage to publish after a read: { accounts, readAt, gatewayKey }. READING is the
 * helper's output, or null for a run that failed as a whole; PREVIOUS is
 * the usage published before, or null. A failed read of an account, or a
 * failed run, keeps the last windows and details read for it marked stale;
 * with none, the account holds no windows. readAt is when a run last answered.
 */
function merge(previous, reading, now) {
    if (reading === null) {
        if (previous === null || previous === undefined) return { accounts: [], readAt: null, gatewayKey: null };
        return { accounts: previous.accounts.map(function (row) {
            var copy = accountCopy(row);
            if (row.state === "ok") copy.state = "stale";
            return copy;
        }), readAt: previous.readAt, gatewayKey: previous.gatewayKey || null };
    }
    return { accounts: reading.accounts.map(function (row) {
        var last = previousOf(previous, row.id);
        if (row.state === "failed" && last !== null && (last.windows.length > 0 || last.credits !== null || hasDetails(last.details)))
            return accountCopy(row, { email: row.email || last.email, state: "stale",
                windows: copyWindows(last.windows), credits: copyCredits(last.credits), details: copyDetails(last.details) });
        return accountCopy(row);
    }), readAt: now, gatewayKey: reading.gatewayKey || null };
}

// The accounts with a plan sign-in: every one but a folder no tool signed
// in to and a sign-in, such as a Codex API key, that has no plan limits.
function signedIn(usage) {
    if (usage === null || usage === undefined) return [];
    return usage.accounts.filter(function (row) { return row.state !== "signed-out" && row.state !== "no-plan"; });
}

function shownProvider(provider, settings) {
    if (settings === null || settings === undefined) return true;
    if (provider === "claude") return settings.showClaude !== false;
    if (provider === "codex") return settings.showCodex !== false;
    if (provider === "copilot") return settings.showCopilot !== false;
    return true;
}

function cleanLine(value, fallback) {
    var text = String(value || "").replace(/[\u0000-\u001f\u007f-\u009f\u2028\u2029]/g, " ").replace(/\s+/g, " ").trim();
    return text === "" ? fallback : text;
}

function accountChoices(usage) {
    if (usage === null || usage === undefined) return [];
    return usage.accounts.map(function (row) {
        var name = NAMES[row.provider] || row.provider;
        var label = cleanLine(row.email, cleanLine(row.label, row.id));
        var text = name + " · " + label;
        return { label: text.length <= LABEL_MAX ? text : text.slice(0, LABEL_MAX - 1) + "…", value: row.id };
    });
}

function hiddenIds(settings, usage) {
    var list = settings !== null && settings !== undefined && Array.isArray(settings.hidden) ? settings.hidden : [];
    var offers = accountChoices(usage);
    var first = offers.length === 0 ? "" : offers[0].value;
    var ids = [];
    for (var i = 0; i < list.length; i++) {
        var id = list[i] !== null && typeof list[i] === "object" && typeof list[i].account === "string" ? list[i].account : "";
        if (id === "") id = first;
        if (id !== "" && ids.indexOf(id) === -1) ids.push(id);
    }
    return ids;
}

function visibleAccounts(usage, settings) {
    var hidden = hiddenIds(settings, usage);
    return signedIn(usage).filter(function (row) { return shownProvider(row.provider, settings) && hidden.indexOf(row.id) === -1; });
}

// The used share the bar figures from PEAKS, each account's highest used
// share, under the Bar number setting MODE: their mean rounded, the least
// ("most-left") or the most ("most-used"); null with no peak.
function barNumber(peaks, mode) {
    if (peaks.length === 0) return null;
    if (mode === "most-left") return Math.min.apply(null, peaks);
    if (mode === "average") return Math.round(peaks.reduce(function (sum, peak) { return sum + peak; }, 0) / peaks.length);
    return Math.max.apply(null, peaks);
}

/**
 * The bar widget: shown while an account is signed in and not hidden by
 * settings. used is the used share barNumber figures from each shown
 * account's peak, the highest used share of its windows; an account with
 * no window is left out, never counted as 0. percent is what the bar
 * draws: used, or what is left of it under Bar shows "left"; null while no
 * window holds a share. tone is "warning" from WARNING_PERCENT of used
 * while Colour by usage is on, else "normal".
 */
function widget(usage, settings) {
    var given = settings === null || settings === undefined ? {} : settings;
    var mode = BAR_MEANING[given.barNumber] === undefined ? "most-used" : given.barNumber;
    var left = given.barShows === "left";
    var accounts = visibleAccounts(usage, settings);
    var peaks = [];
    var expired = "";
    var stale = false;
    for (var i = 0; i < accounts.length; i++) {
        var row = accounts[i];
        if (row.state === "expired" && expired === "") expired = EXPIRED[row.provider];
        if (row.state === "stale") stale = true;
        if (row.windows.length > 0)
            peaks.push(Math.max.apply(null, row.windows.map(function (item) { return item.usedPercent; })));
    }
    var used = barNumber(peaks, mode);
    var percent = used === null ? null : left ? Math.max(0, 100 - used) : used;
    var text = percent === null ? "" : Math.round(percent) + "%";
    var tooltip = percent === null ? "No usage figures yet" : BAR_MEANING[mode] + ": " + text + (left ? " left" : " used");
    if (expired !== "") tooltip += ". " + expired;
    else if (stale) tooltip += ". The last check failed; figures may be old";
    return { shown: accounts.length > 0, used: used, percent: percent,
        tone: used !== null && given.colourByUsage !== false && used >= WARNING_PERCENT ? "warning" : "normal", text: text, tooltip: tooltip };
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
        return { tone: "warning", text: EXPIRED[provider] };
    if (plans.length > 0) return { tone: "danger", text: "Usage could not be read" };
    if (rows.length > 0) return { tone: "info", text: NO_PLAN };
    return { tone: "info", text: "Not signed in", action: true };
}

function gatewayKey(presence) {
    var value = ["present", "absent", "locked", "unavailable", "unsafe"].indexOf(presence) === -1 ? "unavailable" : presence;
    return [{ label: "AI Gateway", value: value, secret: GATEWAY_ACCOUNT }];
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
    if (name === "credits") return { minutes: null, model: "credits" };
    return { minutes: null, model: "" };
}

function windowLabel(name) {
    if (name === "credits") return "Credits";
    var limit = limitOf(name);
    var length = limit.minutes === null ? (name === "primary" ? "Short" : "Long")
        : limit.minutes === 10080 ? "Weekly"
        : limit.minutes % 1440 === 0 ? limit.minutes / 1440 + "-day"
        : limit.minutes % 60 === 0 ? limit.minutes / 60 + "-hour" : limit.minutes + "-minute";
    return length + (limit.model === "" ? "" : " " + limit.model.charAt(0).toUpperCase() + limit.model.slice(1)) + " limit";
}

function compact(value) {
    if (typeof value !== "number" || !Number.isFinite(value)) return "";
    var sign = value < 0 ? "-" : "";
    var n = Math.abs(value);
    var units = [[1000000000, "B"], [1000000, "M"], [1000, "k"]];
    for (var i = 0; i < units.length; i++) {
        if (n >= units[i][0]) return sign + trimNumber(n / units[i][0]) + units[i][1];
    }
    return sign + trimNumber(n);
}

function trimNumber(value) {
    var decimals = value >= 100 ? 0 : value >= 10 ? 1 : value >= 1 ? 2 : 3;
    var text = value.toFixed(decimals);
    return text.indexOf(".") < 0 ? text : text.replace(/\.?0+$/, "");
}

// NUMBER, a numeral, with a comma between each group of three digits of
// its whole part.
function grouped(number) {
    return number.replace(/\B(?=(\d{3})+(?!\d))/g, ",");
}

function money(value, currency) {
    if (typeof value !== "number" || !Number.isFinite(value)) return "";
    return (currency === "USD" || currency === "" || currency === undefined ? "$" : currency + " ") + grouped(value.toFixed(2));
}

// VALUE, a number or a numeral string such as Codex's credit balance,
// rounded to a whole number and grouped; "" for no finite number.
function wholeNumber(value) {
    var n = typeof value === "number" ? value : typeof value === "string" && value.trim() !== "" ? Number(value) : NaN;
    if (!Number.isFinite(n)) return "";
    var whole = Math.round(n);
    return (whole < 0 ? "-" : "") + grouped(String(Math.abs(whole)));
}

function dateText(value) {
    if (typeof value !== "number" || !Number.isFinite(value)) return "";
    return new Date(value).toISOString().slice(0, 10);
}

function creditNoun(credits, singular) {
    if (credits === null || credits === undefined) return "";
    if (credits.unit === "credits") return singular ? "AI credit" : "AI credits";
    return singular ? "premium request" : "premium requests";
}

function creditLine(credits) {
    if (credits === null || credits === undefined) return "";
    var noun = creditNoun(credits, false);
    if (credits.unlimited === true) return "Unlimited " + noun;
    if (credits.granted === 0) return "No " + creditNoun(credits, true) + " pool";
    return "";
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

// The time left until a window resets, drawn after the reset icon: "" with
// no reset time, "now" once it has passed.
function resetText(resetsAt, now) {
    var left = resetIn(resetsAt, now);
    if (left.kind === "none") return "";
    if (left.kind === "now") return "now";
    var seconds = (left.days * 1440 + left.hours * 60 + left.minutes) * 60;
    return Commons.Duration.format(seconds, seconds < 3600 ? 1 : 2);
}

// The only lines of the helper's stderr the service logs: its own keyed
// `ai-usage: <key>=<value>` pairs, never a line a tool or node printed.
function keyed(line) {
    return /^ai-usage: [a-z]+=[a-z0-9-]+( [a-z]+=[a-z0-9-]+)*$/.test(line);
}

function detailRows(row) {
    var d = row.details || {};
    var rows = [];
    if (d.claudeExtra !== undefined) {
        var extra = d.claudeExtra;
        rows.push({ label: "Extra usage", value: money(extra.used, extra.currency) + " of " + money(extra.limit, extra.currency) });
    }
    if (d.codexCredits !== undefined) {
        var codex = d.codexCredits;
        var balance = wholeNumber(codex.balance);
        rows.push({ label: "Codex credits", value: codex.unlimited === true ? "Unlimited" : balance !== "" ? balance + " available" : "Available" });
    }
    if (d.copilotMonthUsed !== undefined) rows.push({ label: "Month credits used", value: compact(d.copilotMonthUsed) });
    if (d.copilotRenewsAt !== undefined) rows.push({ label: "Renews", value: dateText(d.copilotRenewsAt) });
    if (d.gateway !== undefined) {
        rows.push({ label: "Balance left", value: money(d.gateway.balance, "USD") });
        rows.push({ label: "Total used", value: money(d.gateway.totalUsed, "USD") });
    }
    return rows;
}

// A time window not yet started: none used and no reset time, as Claude
// Code's 5-hour window reads before its first message. A credit pool has no
// start, so it never reads so.
function started(item) {
    return item.name === "credits" || item.usedPercent > 0 || (item.resetsAt !== null && item.resetsAt !== undefined);
}

function windowRow(row, item, now) {
    var creditWindow = row.provider === "copilot" && item.name === "credits" && row.credits !== null;
    var gatewayWindow = row.provider === "gateway" && item.name === "credits";
    var begun = started(item);
    return { name: item.name, percent: item.usedPercent, tone: item.usedPercent >= WARNING_PERCENT ? "warning" : "normal",
        started: begun, resetIn: resetIn(item.resetsAt, now),
        label: creditWindow ? (row.credits.unit === "credits" ? "AI credits" : "Premium requests") : gatewayWindow ? "AI Gateway credits" : windowLabel(item.name),
        text: creditWindow ? compact(row.credits.used) + " of " + compact(row.credits.granted) : begun ? Math.round(item.usedPercent) + "%" : "Not started",
        reset: resetText(item.resetsAt, now) };
}

// An account read whose every window reads 0 %: it has had no use yet.
function unused(row) {
    return row.state === "ok" && row.windows.length > 0 && row.windows.every(function (item) { return item.usedPercent === 0; });
}

// The panel's rows: one per signed-in account after settings filters, with
// title, the provider's name; email, the account's email or the login its
// provider gives; detail line; note, in tone "warning" for a failed or old
// read, else "normal"; every limit, none while unused; and full-view detail
// rows.
function panel(usage, now, settings) {
    return visibleAccounts(usage, settings).map(function (row) {
        var idle = unused(row);
        var warning = row.state === "expired" ? EXPIRED[row.provider]
            : row.state === "stale" ? "The last check failed. These figures may be old."
            : row.state === "failed" ? "Usage could not be read." : "";
        var note = warning !== "" ? warning
            : idle ? "No usage yet."
            : row.state === "ok" && row.windows.length === 0 && row.credits === null && !hasDetails(row.details) ? "This plan reports no usage limits." : "";
        return { id: row.id, provider: row.provider, label: row.label, email: row.email, state: row.state,
            title: NAMES[row.provider] || row.provider, detail: row.provider === "copilot" ? creditLine(row.credits) : "",
            note: note, noteTone: warning !== "" ? "warning" : "normal", details: detailRows(row),
            windows: idle ? [] : row.windows.map(function (item) { return windowRow(row, item, now); }) };
    });
}
