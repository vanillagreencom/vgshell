.pragma library
.import qs.Commons 1.0 as Commons

// What the service publishes and the widget, the panel and the Settings
// page draw from the helper's readings (backend/usage.js). Plain functions
// over plain values, which scripts/test-ai-usage.js runs under node.

// Used share: lots of room below MEDIUM_PERCENT, medium below
// WARNING_PERCENT, almost out from WARNING_PERCENT. The bar warns there.
var MEDIUM_PERCENT = 50;
var WARNING_PERCENT = 80;
// Simple Icons 16.17.0, CC0-1.0; sources and licence in README credits.
var MARKS = {"claude": "m4.7144 15.9555 4.7174-2.6471.079-.2307-.079-.1275h-.2307l-.7893-.0486-2.6956-.0729-2.3375-.0971-2.2646-.1214-.5707-.1215-.5343-.7042.0546-.3522.4797-.3218.686.0608 1.5179.1032 2.2767.1578 1.6514.0972 2.4468.255h.3886l.0546-.1579-.1336-.0971-.1032-.0972L6.973 9.8356l-2.55-1.6879-1.3356-.9714-.7225-.4918-.3643-.4614-.1578-1.0078.6557-.7225.8803.0607.2246.0607.8925.686 1.9064 1.4754 2.4893 1.8336.3643.3035.1457-.1032.0182-.0728-.164-.2733-1.3539-2.4467-1.445-2.4893-.6435-1.032-.17-.6194c-.0607-.255-.1032-.4674-.1032-.7285L6.287.1335 6.6997 0l.9957.1336.419.3642.6192 1.4147 1.0018 2.2282 1.5543 3.0296.4553.8985.2429.8318.091.255h.1579v-.1457l.1275-1.706.2368-2.0947.2307-2.6957.0789-.7589.3764-.9107.7468-.4918.5828.2793.4797.686-.0668.4433-.2853 1.8517-.5586 2.9021-.3643 1.9429h.2125l.2429-.2429.9835-1.3053 1.6514-2.0643.7286-.8196.85-.9046.5464-.4311h1.0321l.759 1.1293-.34 1.1657-1.0625 1.3478-.8804 1.1414-1.2628 1.7-.7893 1.36.0729.1093.1882-.0183 2.8535-.607 1.5421-.2794 1.8396-.3157.8318.3886.091.3946-.3278.8075-1.967.4857-2.3072.4614-3.4364.8136-.0425.0304.0486.0607 1.5482.1457.6618.0364h1.621l3.0175.2247.7892.522.4736.6376-.079.4857-1.2142.6193-1.6393-.3886-3.825-.9107-1.3113-.3279h-.1822v.1093l1.0929 1.0686 2.0035 1.8092 2.5075 2.3314.1275.5768-.3218.4554-.34-.0486-2.2039-1.6575-.85-.7468-1.9246-1.621h-.1275v.17l.4432.6496 2.3436 3.5214.1214 1.0807-.17.3521-.6071.2125-.6679-.1214-1.3721-1.9246L14.38 17.959l-1.1414-1.9428-.1397.079-.674 7.2552-.3156.3703-.7286.2793-.6071-.4614-.3218-.7468.3218-1.4753.3886-1.9246.3157-1.53.2853-1.9004.17-.6314-.0121-.0425-.1397.0182-1.4328 1.9672-2.1796 2.9446-1.7243 1.8456-.4128.164-.7164-.3704.0667-.6618.4008-.5889 2.386-3.0357 1.4389-1.882.929-1.0868-.0062-.1579h-.0546l-6.3385 4.1164-1.1293.1457-.4857-.4554.0608-.7467.2307-.2429 1.9064-1.3114Z", "copilot": "M23.922 16.997C23.061 18.492 18.063 22.02 12 22.02 5.937 22.02.939 18.492.078 16.997A.641.641 0 0 1 0 16.741v-2.869a.883.883 0 0 1 .053-.22c.372-.935 1.347-2.292 2.605-2.656.167-.429.414-1.055.644-1.517a10.098 10.098 0 0 1-.052-1.086c0-1.331.282-2.499 1.132-3.368.397-.406.89-.717 1.474-.952C7.255 2.937 9.248 1.98 11.978 1.98c2.731 0 4.767.957 6.166 2.093.584.235 1.077.546 1.474.952.85.869 1.132 2.037 1.132 3.368 0 .368-.014.733-.052 1.086.23.462.477 1.088.644 1.517 1.258.364 2.233 1.721 2.605 2.656a.841.841 0 0 1 .053.22v2.869a.641.641 0 0 1-.078.256Zm-11.75-5.992h-.344a4.359 4.359 0 0 1-.355.508c-.77.947-1.918 1.492-3.508 1.492-1.725 0-2.989-.359-3.782-1.259a2.137 2.137 0 0 1-.085-.104L4 11.746v6.585c1.435.779 4.514 2.179 8 2.179 3.486 0 6.565-1.4 8-2.179v-6.585l-.098-.104s-.033.045-.085.104c-.793.9-2.057 1.259-3.782 1.259-1.59 0-2.738-.545-3.508-1.492a4.359 4.359 0 0 1-.355-.508Zm2.328 3.25c.549 0 1 .451 1 1v2c0 .549-.451 1-1 1-.549 0-1-.451-1-1v-2c0-.549.451-1 1-1Zm-5 0c.549 0 1 .451 1 1v2c0 .549-.451 1-1 1-.549 0-1-.451-1-1v-2c0-.549.451-1 1-1Zm3.313-6.185c.136 1.057.403 1.913.878 2.497.442.544 1.134.938 2.344.938 1.573 0 2.292-.337 2.657-.751.384-.435.558-1.15.558-2.361 0-1.14-.243-1.847-.705-2.319-.477-.488-1.319-.862-2.824-1.025-1.487-.161-2.192.138-2.533.529-.269.307-.437.808-.438 1.578v.021c0 .265.021.562.063.893Zm-1.626 0c.042-.331.063-.628.063-.894v-.02c-.001-.77-.169-1.271-.438-1.578-.341-.391-1.046-.69-2.533-.529-1.505.163-2.347.537-2.824 1.025-.462.472-.705 1.179-.705 2.319 0 1.211.175 1.926.558 2.361.365.414 1.084.751 2.657.751 1.21 0 1.902-.394 2.344-.938.475-.584.742-1.44.878-2.497Z", "gateway": "m12 1.608 12 20.784H0Z"};

function logo(provider, color) {
    var mark = MARKS[provider];
    return mark === undefined ? "" : "data:image/svg+xml," + encodeURIComponent(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="' + color + '" d="' + mark + '"/></svg>');
}

function usageTone(percent) {
    return percent >= WARNING_PERCENT ? "danger" : percent >= MEDIUM_PERCENT ? "warning" : "success";
}

var NAMES = { claude: "Claude Code", codex: "Codex", copilot: "Copilot", gateway: "AI Gateway" };
var EXPIRED = { claude: "Open Claude Code to refresh the sign-in", copilot: "Open Copilot to sign in again" };
var NO_PLAN = "Signed in with an API key, which has no plan limits";
var STALE_NOTE = "The last check failed. These figures may be old.";
var LIMITED_NOTE = "Claude limits how often usage can be read. The next check tries again.";
// What the bar's tooltip adds for old figures: a failed check's, or a
// limited read's kept figures once a window has reset since; and a limited
// read's kept figures before that.
var STALE_TIP = "The last check failed; figures may be old";
var LIMITED_TIP = "These figures are from the last check";
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

function hasFigures(row) {
    return row.windows.length > 0 || row.credits !== null || hasDetails(row.details);
}

// Whether a window of ROW's figures has reset at or before NOW, so the
// figures no longer tell its use.
function pastReset(row, now) {
    return row.windows.some(function (item) { return item.resetsAt !== null && item.resetsAt !== undefined && item.resetsAt <= now; });
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
 * the usage published before, or null; NOW is the time in epoch ms. Each
 * account's readAt is when its figures were read, null while it holds none.
 * A limited read, the endpoint turning away a frequent read, reads limited
 * and keeps the last figures read for the account with their readAt; with
 * none, it holds no windows and readAt is null. A failed read of an
 * account keeps the last figures marked stale with their readAt; with
 * none, the account holds no windows. A failed run turns each ok account
 * stale and leaves every other as it was, readAt included. The top-level
 * readAt is when a run last answered.
 */
function merge(previous, reading, now) {
    if (reading === null) {
        if (previous === null || previous === undefined) return { accounts: [], readAt: null, gatewayKey: null };
        return { accounts: previous.accounts.map(function (row) {
            var copy = accountCopy(row, { readAt: row.readAt });
            if (row.state === "ok") copy.state = "stale";
            return copy;
        }), readAt: previous.readAt, gatewayKey: previous.gatewayKey || null };
    }
    return { accounts: reading.accounts.map(function (row) {
        var last = previousOf(previous, row.id);
        if ((row.state === "failed" || row.state === "limited") && last !== null && hasFigures(last))
            return accountCopy(row, { email: row.email || last.email, state: row.state === "limited" ? "limited" : "stale",
                windows: copyWindows(last.windows), credits: copyCredits(last.credits), details: copyDetails(last.details),
                readAt: last.readAt });
        return accountCopy(row, { readAt: row.state === "ok" ? now : null });
    }), readAt: now, gatewayKey: reading.gatewayKey || null };
}

// Every signed-in account, including an API key with no plan limits.
function signedIn(usage) {
    if (usage === null || usage === undefined) return [];
    return usage.accounts.filter(function (row) { return row.state !== "signed-out"; });
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
 * while Colour by usage is on, else "normal". A limited account's kept
 * figures count; the tooltip says they are from the last check, or that
 * they may be old once a window has reset since NOW, in epoch ms, as it
 * does for a failed check.
 */
function widget(usage, settings, now) {
    var given = settings === null || settings === undefined ? {} : settings;
    var mode = BAR_MEANING[given.barNumber] === undefined ? "most-used" : given.barNumber;
    var left = given.barShows === "left";
    var accounts = visibleAccounts(usage, settings);
    var peaks = [];
    var expired = "";
    var stale = false;
    var limited = false;
    for (var i = 0; i < accounts.length; i++) {
        var row = accounts[i];
        if (row.state === "expired" && expired === "") expired = EXPIRED[row.provider];
        if (row.state === "stale" || (row.state === "limited" && pastReset(row, now))) stale = true;
        else if (row.state === "limited" && row.windows.length > 0) limited = true;
        if (row.windows.length > 0)
            peaks.push(Math.max.apply(null, row.windows.map(function (item) { return item.usedPercent; })));
    }
    var used = barNumber(peaks, mode);
    var percent = used === null ? null : left ? Math.max(0, 100 - used) : used;
    var text = percent === null ? "" : Math.round(percent) + "%";
    var tooltip = percent === null ? "No usage figures yet" : BAR_MEANING[mode] + ": " + text + (left ? " left" : " used");
    if (expired !== "") tooltip += ". " + expired;
    else if (stale) tooltip += ". " + STALE_TIP;
    else if (limited) tooltip += ". " + LIMITED_TIP;
    return { shown: accounts.length > 0, used: used, percent: percent,
        tone: used !== null && given.colourByUsage !== false && used >= WARNING_PERCENT ? "warning" : "normal", text: text, tooltip: tooltip };
}

// The Settings row of PROVIDER's sign-in: a state value, whose action, Sign
// in, applies while none of its accounts is signed in.
function signIn(usage, provider) {
    var rows = (usage === null || usage === undefined ? [] : usage.accounts)
        .filter(function (row) { return row.provider === provider && row.state !== "signed-out"; });
    var plans = rows.filter(function (row) { return row.state !== "no-plan"; });
    if (plans.some(function (row) { return row.state === "ok" || row.state === "stale" || row.state === "limited"; }))
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

// The time left until a window resets, drawn dim beside its share: "" with
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
    return { name: item.name, percent: item.usedPercent, tone: usageTone(item.usedPercent),
        started: begun, resetIn: resetIn(item.resetsAt, now),
        label: creditWindow ? (row.credits.unit === "credits" ? "AI credits" : "Premium requests") : gatewayWindow ? "AI Gateway credits" : windowLabel(item.name),
        text: creditWindow ? compact(row.credits.used) + " of " + compact(row.credits.granted) : begun ? Math.round(item.usedPercent) + "%" : "Not started",
        reset: resetText(item.resetsAt, now) };
}

// An account read, or kept through a limited read, whose every window is
// a time window at 0 %: it has had no use yet. A credit pool at 0 used
// still shows its allowance.
function unused(row) {
    return (row.state === "ok" || row.state === "limited") && row.windows.length > 0
        && row.windows.every(function (item) { return item.name !== "credits" && item.usedPercent === 0; });
}

// The account line: the email or login the helper read, else the folder's
// label, so two cards of one provider stay apart. The default folder and
// the AI Gateway key, which is no folder, have no label to show.
function accountLine(row) {
    if (row.email !== "") return row.email;
    return row.label === "default" || row.provider === "gateway" ? "" : row.label;
}

// How long ago an account's figures were read, from READAT and NOW in
// epoch ms: "Checked just now" under a minute, "Checked 4m ago" after, ""
// with no figures read. KEPT, for figures a later check kept without new
// ones, names the figures' age rather than a check's: "Figures from 4m ago".
function checkedText(readAt, now, kept) {
    if (readAt === null || readAt === undefined) return "";
    var seconds = Math.max(0, Math.floor((now - readAt) / 1000));
    if (kept) return seconds < 60 ? "Figures from under a minute ago" : "Figures from " + Commons.Duration.format(seconds, 1) + " ago";
    return seconds < 60 ? "Checked just now" : "Checked " + Commons.Duration.format(seconds, 1) + " ago";
}

// The panel's rows: one per signed-in account after settings filters, with
// title, the provider's name; email, the account's email or the login its
// provider gives; account, the line drawn under the title; checked, the
// age of its figures, named as kept figures' age for a limited or stale
// account; detail line; note, in tone "warning" for a failed or
// old read, a limited read's kept figures past a window's reset among them,
// else "normal"; every limit, none while unused; and full-view detail rows.
// Most room compares each account's highest used limit. An account with
// no reported limit comes last because its remaining share is unknown.
function peak(row) {
    return row.windows.length === 0 ? Infinity : Math.max.apply(null, row.windows.map(function (item) { return item.usedPercent; }));
}

function sortedAccounts(accounts, mode) {
    return accounts.slice().sort(function (a, b) {
        if (mode === "most-left") {
            var left = peak(a), right = peak(b);
            if (left !== right) return left < right ? -1 : 1;
        }
        if (mode === "email") {
            var email = a.email.toLowerCase().localeCompare(b.email.toLowerCase());
            if (email !== 0) return email;
        }
        return a.provider.localeCompare(b.provider);
    });
}

function panel(usage, now, settings) {
    return sortedAccounts(visibleAccounts(usage, settings), settings === null || settings === undefined ? "provider" : settings.sort).map(function (row) {
        var idle = unused(row);
        var warning = row.state === "expired" ? EXPIRED[row.provider]
            : row.state === "stale" || (row.state === "limited" && pastReset(row, now)) ? STALE_NOTE
            : row.state === "failed" ? "Usage could not be read." : "";
        var note = warning !== "" ? warning
            : row.state === "limited" ? LIMITED_NOTE
            : idle ? "No usage yet."
            : row.state === "no-plan" ? NO_PLAN
            : row.state === "ok" && !hasFigures(row) ? "This plan reports no usage limits." : "";
        return { id: row.id, provider: row.provider, label: row.label, email: row.email, account: accountLine(row), state: row.state,
            title: NAMES[row.provider] || row.provider, api: row.state === "no-plan" || row.provider === "gateway", detail: row.provider === "copilot" ? creditLine(row.credits) : "",
            checked: checkedText(row.readAt, now, row.state === "limited" || row.state === "stale"),
            note: note, noteTone: warning !== "" ? "warning" : "normal", details: detailRows(row),
            windows: idle ? [] : row.windows.map(function (item) { return windowRow(row, item, now); }) };
    });
}
