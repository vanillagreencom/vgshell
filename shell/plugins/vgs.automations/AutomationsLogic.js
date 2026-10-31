.pragma library
.import qs.Commons 1.0 as Commons

// Pure decisions for vgs.automations: the store's schema, the recurrence
// model and its presets, the schedule compiler (systemd OnCalendar= and the
// cron fallback's fields), the occurrences the preview shows and the
// runner's guard reads, the summary line, the unit and crontab text, the
// run records and history rows, pruning, the notifications a run sends, the
// scheduled run's wait for the network, and the status the service
// publishes. bin/automations owns processes, files and systemctl;
// Service.qml owns timers and status writes. Both load this file, so the
// preview, the units and the guard cannot disagree.
//
// A schedule's optional zone selects the wall-clock zone for recurrence
// decisions. A time a daylight saving change skips does not occur that day,
// and a time it repeats occurs once, at its first instant.

var STORE_VERSION = 2;
var RECORD_VERSION = 1;

var ID_PATTERN = /^[a-z0-9](?:[a-z0-9-]{0,38}[a-z0-9])?$/;
var NAME_MAX = 80;
var COMMAND_MAX = 4096;
var PATH_MAX = 4096;
var AUTOMATIONS_MAX = 200;

var TIMEOUT_MIN = 1;
var TIMEOUT_MAX = 86400;
var TIMEOUT_DEFAULT = 3600;

var FREQUENCIES = ["minutely", "hourly", "daily", "weekly", "monthly", "yearly"];
// The steps an every-N-minutes or every-N-hours rule may take: those that
// divide an hour or a day, so its slots, counted from each local midnight,
// fall on the same wall-clock times every day. systemd's `*:00/N` and
// `00/N:00` and cron's `*/N` restart their step at each hour or day, so
// only such a step makes the two schedulers and the preview agree.
var INTERVAL_STEPS = { minutely: [1, 2, 3, 4, 5, 6, 10, 12, 15, 20, 30], hourly: [1, 2, 3, 4, 6, 8, 12] };
// Monday first: weeks are ISO weeks, so "every 2 weeks" counts from the
// Monday of the start date's week.
var WEEKDAYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"];
var WEEKDAY_NAMES = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];
var SYSTEMD_WEEKDAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
var MONTH_NAMES = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];
var ORDINALS = { "1": "first", "2": "second", "3": "third", "4": "fourth", "5": "fifth", "-1": "last" };
var INTERVAL_MAX = 99;
var TIMES_MAX = 24;
var COUNT_MAX = 999;
var END_TYPES = ["never", "date", "count"];
var PRESETS = ["daily", "weekdays", "weekly", "biweekly", "monthly-date", "monthly-weekday", "yearly"];

// How far the compiler looks for an occurrence: 400 years holds every
// leap-year cycle, so a rule with an occurrence finds it.
var SCAN_MONTHS_MAX = 400 * 12;
var PREVIEW_MAX = 50;
// A trigger this long after its occurrence is late, and an automation that
// does not catch up missed runs skips it. systemd starts a timer's service
// within AccuracySec=1s of its elapse and cron within its minute; the rest
// is room for a loaded or resuming machine.
var LATE_GRACE_MS = 10 * 60 * 1000;

var HISTORY_DAYS_MAX = 30;
// The ended runs an automation keeps beside the day cutoff: 30 days of a
// rule at TIMES_MAX runs a day, so an every-minute rule's history and its
// runs folder stay as large as a day-grained rule's could grow.
var HISTORY_RUNS_MAX = HISTORY_DAYS_MAX * TIMES_MAX;
var DAY_MS = 24 * 60 * 60 * 1000;
var TRANSCRIPT_MAX_BYTES = 1024 * 1024;
// The longest line the runner holds: a longer one, output with no line
// break included, reaches the transcript in pieces of this many characters.
var TRANSCRIPT_LINE_MAX = 8192;
var SNIPPET_LINES = 5;
var SNIPPET_CHARS = 400;
// The longest output line a failure notice carries before it ends in an
// ellipsis; Open log shows the whole line in the transcript.
var FAILURE_LINE_MAX = 120;
// SIGTERM to a timed-out command's process group, then SIGKILL this long
// after it.
var KILL_GRACE_MS = 10000;
// How long the runner waits for a timed-out group to go after SIGKILL
// before it records the run with the group named as surviving.
var KILL_WAIT_MS = 30000;

var UNIT_PREFIX = "vgs-automation-";
var CRON_BEGIN = "# BEGIN vgs.automations: sync writes the lines to END; an edit between them is replaced";
var CRON_END = "# END vgs.automations";

// A run's outcome, and the tone and Lucide icon each draws with. `running`
// and `vanished` are the two states of a run with no ended record: its
// runner holds the automation's lock, or no runner does.
var OUTCOMES = {
    succeeded: { tone: "success", icon: "circle-check", error: false },
    skipped: { tone: "neutral", icon: "circle-minus", error: false },
    failed: { tone: "danger", icon: "circle-x", error: true },
    timeout: { tone: "danger", icon: "circle-x", error: true },
    "failed-start": { tone: "danger", icon: "circle-x", error: true },
    running: { tone: "warning", icon: "loader", error: false },
    vanished: { tone: "danger", icon: "circle-x", error: true }
};
var ENDED_OUTCOMES = ["succeeded", "failed", "timeout", "failed-start", "skipped"];
var TRIGGERS = ["scheduled", "manual"];
var SCHEDULERS = ["systemd", "cron", "none"];
var LINGER_STATES = ["yes", "no", "unknown"];

// ------------------------------------------------------------- basics

function hasOwn(object, key) {
    return Object.prototype.hasOwnProperty.call(object, key);
}

function isPlainObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
}

function isWhole(value) {
    return typeof value === "number" && isFinite(value) && Math.floor(value) === value;
}

function pad2(n) {
    return (n < 10 ? "0" : "") + n;
}

// A line a person reads: no control character, not blank.
function isPrintableLine(value, max) {
    return typeof value === "string" && value.trim() !== "" && value.length <= max && !/[\u0000-\u001f\u007f]/.test(value);
}

function isCommandText(value, max) {
    return typeof value === "string" && value.trim() !== "" && value.length <= max && !/[\u0000-\u0008\u000b-\u001f\u007f]/.test(value);
}

function unknownKey(value, allowed, where) {
    var keys = Object.keys(value);
    for (var i = 0; i < keys.length; i++)
        if (allowed.indexOf(keys[i]) === -1) return where + "." + keys[i] + ": unknown";
    return "";
}

function withKeys(base, extra) {
    var out = {};
    var keys = Object.keys(base);
    for (var i = 0; i < keys.length; i++) out[keys[i]] = base[keys[i]];
    var more = Object.keys(extra);
    for (var j = 0; j < more.length; j++) out[more[j]] = extra[more[j]];
    return out;
}

// ------------------------------------------------------------- dates

// { y, m, d } for a real calendar date "YYYY-MM-DD", else null.
function parseDate(text) {
    var match = typeof text === "string" ? /^(\d{4})-(\d{2})-(\d{2})$/.exec(text) : null;
    if (match === null) return null;
    var y = Number(match[1]), m = Number(match[2]), d = Number(match[3]);
    if (y < 1970 || y > 9999 || m < 1 || m > 12 || d < 1 || d > daysInMonth(y, m)) return null;
    return { y: y, m: m, d: d };
}

// { h, mi } for "HH:MM" on a 24-hour clock, else null.
function parseTime(text) {
    var match = typeof text === "string" ? /^(\d{2}):(\d{2})$/.exec(text) : null;
    if (match === null) return null;
    var h = Number(match[1]), mi = Number(match[2]);
    if (h > 23 || mi > 59) return null;
    return { h: h, mi: mi };
}

function daysInMonth(y, m) {
    return new Date(Date.UTC(y, m, 0)).getUTCDate();
}

// Days since 1970-01-01 for a calendar date, whatever the zone.
function dayNumber(y, m, d) {
    return Math.round(Date.UTC(y, m - 1, d) / DAY_MS);
}

// 0 for Monday through 6 for Sunday.
function weekdayOf(y, m, d) {
    return (new Date(Date.UTC(y, m - 1, d)).getUTCDay() + 6) % 7;
}

function mondayNumber(y, m, d) {
    return dayNumber(y, m, d) - weekdayOf(y, m, d);
}

// The local date of an instant.
function localDate(ms) {
    var at = new Date(ms);
    return { y: at.getFullYear(), m: at.getMonth() + 1, d: at.getDate() };
}

function scheduleDate(ms, schedule) {
    if (schedule.zone !== "utc") return localDate(ms);
    var at = new Date(ms);
    return { y: at.getUTCFullYear(), m: at.getUTCMonth() + 1, d: at.getUTCDate() };
}

// The instant of a local wall-clock time, or null when the day's daylight
// saving change skips it. A repeated time takes its first instant, as the
// Date constructor answers.
function localInstant(y, m, d, time) {
    var at = new Date(y, m - 1, d, time.h, time.mi, 0, 0);
    if (at.getFullYear() !== y || at.getMonth() !== m - 1 || at.getDate() !== d || at.getHours() !== time.h || at.getMinutes() !== time.mi) return null;
    return at.getTime();
}

function scheduleInstant(y, m, d, time, schedule) {
    if (schedule.zone === "utc") return Date.UTC(y, m - 1, d, time.h, time.mi, 0, 0);
    return localInstant(y, m, d, time);
}

// ---------------------------------------------------------- schedules

// "" for a recurrence the compiler accepts, else the first defect as
// `schedule.<path>: <reason>`.
//
// { frequency, interval, weekdays?, monthly?, yearly?, times?, start, end }
//   frequency  minutely, hourly, daily, weekly, monthly or yearly
//   interval   every N of them: 1 to INTERVAL_MAX for a day frequency, one
//              of INTERVAL_STEPS for minutely and hourly
//   weekdays   weekly only: the days it runs, a non-empty set of WEEKDAYS
//   monthly    monthly only: { by: "date", day } or
//              { by: "weekday", week: 1..5 or -1 (the last), weekday }
//   yearly     yearly only: { month, day }, a day the month can hold
//   zone       optional: "local" (the default) or "utc"
//   times      day frequencies only: "HH:MM" in zone, 1 to TIMES_MAX,
//              ascending and distinct. A minutely or hourly rule runs at
//              every step from each local midnight instead.
//   start      "YYYY-MM-DD": no occurrence before it, and the anchor every
//              day-frequency interval counts from
//   end        { type: "never" }, { type: "date", date } (the last day it
//              may run) or, for a day frequency, { type: "count", count }
//              (its first N occurrences). A minutely or hourly rule takes
//              no count: its slots start at midnight of the start date,
//              which a rule saved later that day has already passed.
function scheduleError(s) {
    if (!isPlainObject(s)) return "schedule: want=object";
    if (FREQUENCIES.indexOf(s.frequency) === -1) return "schedule.frequency: want=" + FREQUENCIES.join("|");
    var stepped = isStepFrequency(s.frequency);
    var allowed = ["frequency", "interval", "start", "end", "zone"];
    if (!stepped) allowed.push("times");
    if (s.frequency === "weekly") allowed.push("weekdays");
    if (s.frequency === "monthly") allowed.push("monthly");
    if (s.frequency === "yearly") allowed.push("yearly");
    var unknown = unknownKey(s, allowed, "schedule");
    if (unknown !== "") return unknown;
    if (hasOwn(s, "zone") && s.zone !== "local" && s.zone !== "utc") return "schedule.zone: want=local|utc";
    if (stepped) {
        if (INTERVAL_STEPS[s.frequency].indexOf(s.interval) === -1) return "schedule.interval: want=" + INTERVAL_STEPS[s.frequency].join("|");
    } else if (!isWhole(s.interval) || s.interval < 1 || s.interval > INTERVAL_MAX) {
        return "schedule.interval: want=1.." + INTERVAL_MAX;
    }
    var partError = s.frequency === "weekly" ? weekdaysError(s.weekdays)
        : s.frequency === "monthly" ? monthlyError(s.monthly)
        : s.frequency === "yearly" ? yearlyError(s.yearly)
        : "";
    if (partError !== "") return partError;
    if (!stepped) {
        if (!Array.isArray(s.times) || s.times.length === 0 || s.times.length > TIMES_MAX) return "schedule.times: want=1.." + TIMES_MAX + " times";
        for (var t = 0; t < s.times.length; t++) {
            if (parseTime(s.times[t]) === null) return "schedule.times." + t + ": want=HH:MM";
            if (t > 0 && s.times[t] <= s.times[t - 1]) return "schedule.times." + t + ": want=ascending and distinct";
        }
    }
    if (parseDate(s.start) === null) return "schedule.start: want=YYYY-MM-DD";
    var endDefect = endError(s.end, s.start, stepped ? ["never", "date"] : END_TYPES);
    if (endDefect !== "") return endDefect;
    if (occurrencesFrom(s, null, 1).length === 0) return "schedule: no occurrence";
    return "";
}

function weekdaysError(weekdays) {
    if (!Array.isArray(weekdays) || weekdays.length === 0) return "schedule.weekdays: want=non-empty list";
    for (var w = 0; w < weekdays.length; w++) {
        if (WEEKDAYS.indexOf(weekdays[w]) === -1) return "schedule.weekdays." + w + ": want=" + WEEKDAYS.join("|");
        if (weekdays.indexOf(weekdays[w]) !== w) return "schedule.weekdays." + w + ": duplicate";
    }
    return "";
}

function monthlyError(mo) {
    if (!isPlainObject(mo)) return "schedule.monthly: want=object";
    if (mo.by === "date") {
        var dateUnknown = unknownKey(mo, ["by", "day"], "schedule.monthly");
        if (dateUnknown !== "") return dateUnknown;
        if (!isWhole(mo.day) || mo.day < 1 || mo.day > 31) return "schedule.monthly.day: want=1..31";
        return "";
    }
    if (mo.by === "weekday") {
        var weekUnknown = unknownKey(mo, ["by", "week", "weekday"], "schedule.monthly");
        if (weekUnknown !== "") return weekUnknown;
        if (!isWhole(mo.week) || !hasOwn(ORDINALS, String(mo.week))) return "schedule.monthly.week: want=1..5|-1";
        if (WEEKDAYS.indexOf(mo.weekday) === -1) return "schedule.monthly.weekday: want=" + WEEKDAYS.join("|");
        return "";
    }
    return "schedule.monthly.by: want=date|weekday";
}

function yearlyError(yr) {
    if (!isPlainObject(yr)) return "schedule.yearly: want=object";
    var yearUnknown = unknownKey(yr, ["month", "day"], "schedule.yearly");
    if (yearUnknown !== "") return yearUnknown;
    if (!isWhole(yr.month) || yr.month < 1 || yr.month > 12) return "schedule.yearly.month: want=1..12";
    // 2000 is a leap year, so 29 February is a day the month can hold.
    var most = daysInMonth(2000, yr.month);
    if (!isWhole(yr.day) || yr.day < 1 || yr.day > most) return "schedule.yearly.day: want=1.." + most;
    return "";
}

// `types` is the END_TYPES the frequency takes.
function endError(end, start, types) {
    if (!isPlainObject(end)) return "schedule.end: want=object";
    if (types.indexOf(end.type) === -1) return "schedule.end.type: want=" + types.join("|");
    switch (end.type) {
    case "never":
        return unknownKey(end, ["type"], "schedule.end");
    case "date": {
        var dateUnknown = unknownKey(end, ["type", "date"], "schedule.end");
        if (dateUnknown !== "") return dateUnknown;
        if (parseDate(end.date) === null) return "schedule.end.date: want=YYYY-MM-DD";
        if (end.date < start) return "schedule.end.date: want>=start";
        return "";
    }
    case "count": {
        var countUnknown = unknownKey(end, ["type", "count"], "schedule.end");
        if (countUnknown !== "") return countUnknown;
        if (!isWhole(end.count) || end.count < 1 || end.count > COUNT_MAX) return "schedule.end.count: want=1.." + COUNT_MAX;
        return "";
    }
    default:
        throw new Error("automations: end type " + JSON.stringify(end.type) + " unjudged");
    }
}

// Whether a frequency is an every-N-minutes or every-N-hours rule, whose
// times of day are its steps rather than a `times` list.
function isStepFrequency(frequency) {
    return hasOwn(INTERVAL_STEPS, frequency);
}

// The parsed times of day a rule runs at, ascending: its `times`, or every
// step of a minutely or hourly rule from midnight. Every day of the rule
// holds the same ones.
function dayTimes(s) {
    var out = [];
    var h, mi;
    switch (s.frequency) {
    case "minutely":
        for (h = 0; h < 24; h++)
            for (mi = 0; mi < 60; mi += s.interval) out.push({ h: h, mi: mi });
        return out;
    case "hourly":
        for (h = 0; h < 24; h += s.interval) out.push({ h: h, mi: 0 });
        return out;
    default:
        return s.times.map(parseTime);
    }
}

// A schedule for one of PRESETS, from a start date and one time: the
// shortcuts a picker offers before Custom. monthly-weekday takes the start
// date's week of the month, the last one past the fourth.
function presetSchedule(preset, date, time) {
    var d = parseDate(date);
    if (d === null) throw new Error("automations: preset date " + JSON.stringify(date) + " is not YYYY-MM-DD");
    if (parseTime(time) === null) throw new Error("automations: preset time " + JSON.stringify(time) + " is not HH:MM");
    var weekday = WEEKDAYS[weekdayOf(d.y, d.m, d.d)];
    var base = { interval: 1, times: [time], start: date, end: { type: "never" } };
    switch (preset) {
    case "daily": return withKeys(base, { frequency: "daily" });
    case "weekdays": return withKeys(base, { frequency: "weekly", weekdays: WEEKDAYS.slice(0, 5) });
    case "weekly": return withKeys(base, { frequency: "weekly", weekdays: [weekday] });
    case "biweekly": return withKeys(base, { frequency: "weekly", interval: 2, weekdays: [weekday] });
    case "monthly-date": return withKeys(base, { frequency: "monthly", monthly: { by: "date", day: d.d } });
    case "monthly-weekday": {
        var week = Math.ceil(d.d / 7);
        return withKeys(base, { frequency: "monthly", monthly: { by: "weekday", week: week <= 4 ? week : -1, weekday: weekday } });
    }
    case "yearly": return withKeys(base, { frequency: "yearly", yearly: { month: d.m, day: d.d } });
    default: throw new Error("automations: preset " + JSON.stringify(preset) + " is not one of " + PRESETS.join(", "));
    }
}

// The days of month m of year y the calendar trigger fires on, ascending:
// the rule without its interval, start and end, which only the runner's
// guard can apply. It is exactly what `calendarExpressions` states.
function calendarDays(s, y, m) {
    var dim = daysInMonth(y, m);
    var out = [];
    var d;
    switch (s.frequency) {
    case "minutely":
    case "hourly":
    case "daily":
        for (d = 1; d <= dim; d++) out.push(d);
        return out;
    case "weekly":
        for (d = 1; d <= dim; d++)
            if (s.weekdays.indexOf(WEEKDAYS[weekdayOf(y, m, d)]) !== -1) out.push(d);
        return out;
    case "monthly":
        if (s.monthly.by === "date") return s.monthly.day <= dim ? [s.monthly.day] : [];
        for (d = 1; d <= dim; d++) {
            if (WEEKDAYS[weekdayOf(y, m, d)] !== s.monthly.weekday) continue;
            if (s.monthly.week === -1 ? d > dim - 7 : Math.ceil(d / 7) === s.monthly.week) out.push(d);
        }
        return out;
    case "yearly":
        return m === s.yearly.month && s.yearly.day <= dim ? [s.yearly.day] : [];
    default:
        throw new Error("automations: frequency " + JSON.stringify(s.frequency) + " unjudged");
    }
}

// Whether a calendar day holds occurrences: the interval counted from the
// start date, not before the start and not after an end date. An end after
// N occurrences is applied on instants, by `lastOccurrence`. A minutely or
// hourly rule's interval is its step within each day, so every day in
// range holds its slots.
function ruleDay(s, start, y, m, d) {
    var day = dayNumber(y, m, d);
    var first = dayNumber(start.y, start.m, start.d);
    if (day < first) return false;
    if (s.end.type === "date") {
        var end = parseDate(s.end.date);
        if (day > dayNumber(end.y, end.m, end.d)) return false;
    }
    var n = s.interval;
    switch (s.frequency) {
    case "minutely":
    case "hourly": return true;
    case "daily": return (day - first) % n === 0;
    case "weekly": return ((mondayNumber(y, m, d) - mondayNumber(start.y, start.m, start.d)) / 7) % n === 0;
    case "monthly": return ((y * 12 + m) - (start.y * 12 + start.m)) % n === 0;
    case "yearly": return (y - start.y) % n === 0;
    default: throw new Error("automations: frequency " + JSON.stringify(s.frequency) + " unjudged");
    }
}

// The instant of the schedule's last occurrence under an end after N
// occurrences, else null.
function lastOccurrence(s) {
    if (s.end.type !== "count") return null;
    var found = occurrencesFrom(withKeys(s, { end: { type: "never" } }), null, s.end.count);
    return found.length === s.end.count ? found[found.length - 1] : null;
}

// Up to `count` occurrence instants after `afterMs` (every one from the
// start when null), ascending. The end after N occurrences is the one rule
// applied here rather than per day.
function occurrencesFrom(s, afterMs, count) {
    var start = parseDate(s.start);
    var last = lastOccurrence(s);
    var endMonth = s.end.type === "date" ? Number(s.end.date.slice(0, 4)) * 12 + Number(s.end.date.slice(5, 7)) : null;
    var times = dayTimes(s);
    var from = start;
    if (afterMs !== null) {
        var at = scheduleDate(afterMs, s);
        if (dayNumber(at.y, at.m, at.d) > dayNumber(start.y, start.m, start.d)) from = at;
    }
    // A day before `from` holds no instant after `afterMs`: skipping it
    // before its times keeps an every-minute rule to the days it needs.
    var fromDay = dayNumber(from.y, from.m, from.d);
    var out = [];
    var y = from.y, m = from.m;
    for (var scanned = 0; scanned < SCAN_MONTHS_MAX && out.length < count; scanned++) {
        if (endMonth !== null && y * 12 + m > endMonth) break;
        var days = calendarDays(s, y, m);
        for (var i = 0; i < days.length && out.length < count; i++) {
            if (dayNumber(y, m, days[i]) < fromDay || !ruleDay(s, start, y, m, days[i])) continue;
            for (var t = 0; t < times.length && out.length < count; t++) {
                var instant = scheduleInstant(y, m, days[i], times[t], s);
                if (instant === null || (afterMs !== null && instant <= afterMs)) continue;
                if (last !== null && instant > last) return out;
                out.push(instant);
            }
        }
        m += 1;
        if (m > 12) { m = 1; y += 1; }
    }
    return out;
}

// The next `count` occurrences after `afterMs`, at most PREVIEW_MAX: what
// the editor previews and `automations preview` prints.
function nextOccurrences(s, afterMs, count) {
    if (!isWhole(count) || count < 1 || count > PREVIEW_MAX) throw new Error("automations: preview count " + count + " is not 1.." + PREVIEW_MAX);
    return occurrencesFrom(s, afterMs, count);
}

// The latest occurrence at or before `atMs`, or null when none came yet.
function latestOccurrence(s, atMs) {
    var start = parseDate(s.start);
    var last = lastOccurrence(s);
    var times = dayTimes(s);
    var at = scheduleDate(atMs, s);
    // A day after the date of `atMs` holds no instant at or before it.
    var atDay = dayNumber(at.y, at.m, at.d);
    var y = at.y, m = at.m;
    for (var scanned = 0; scanned < SCAN_MONTHS_MAX; scanned++) {
        if (y * 12 + m < start.y * 12 + start.m) return null;
        var days = calendarDays(s, y, m);
        for (var i = days.length - 1; i >= 0; i--) {
            if (dayNumber(y, m, days[i]) > atDay || !ruleDay(s, start, y, m, days[i])) continue;
            for (var t = times.length - 1; t >= 0; t--) {
                var instant = scheduleInstant(y, m, days[i], times[t], s);
                if (instant === null || instant > atMs) continue;
                if (last !== null && instant > last) continue;
                return instant;
            }
        }
        m -= 1;
        if (m < 1) { m = 12; y -= 1; }
    }
    return null;
}

// What the runner does with a scheduled trigger at `nowMs`: run the latest
// occurrence it has not handled, unless that occurrence is late and the
// automation does not catch up. The timer fires on the tightest calendar
// systemd can state, and cron on a coarser one, so a trigger on a day the
// rule skips (an off week, a Tuesday outside its week, a day after the end)
// finds an occurrence it already handled and runs nothing. `handledThrough`
// is the last occurrence the guard decided on, or the time the automation
// was last enabled, so nothing before that runs; null when neither exists.
// { run, slot, reason }: reason ran, handled, late or none.
function guard(s, nowMs, handledThrough, catchUp) {
    var slot = latestOccurrence(s, nowMs);
    if (slot === null) return { run: false, slot: null, reason: "none" };
    if (handledThrough !== null && slot <= handledThrough) return { run: false, slot: slot, reason: "handled" };
    if (catchUp !== true && nowMs - slot > LATE_GRACE_MS) return { run: false, slot: slot, reason: "late" };
    return { run: true, slot: slot, reason: "ran" };
}

// ------------------------------------------------------------ compiler

function orderedWeekdays(days) {
    return WEEKDAYS.filter(function (w) { return days.indexOf(w) !== -1; });
}

// One systemd OnCalendar= expression per time of day, the tightest
// calendar systemd can state for the rule: every day, the named weekdays,
// a day of the month, a weekday within a week of the month, or a day of
// the year. The interval, start and end are the guard's.
function calendarExpressions(s) {
    var date;
    var weekdays = "";
    switch (s.frequency) {
    // A step from each hour's minute 0, or from each day's hour 0: the
    // slots dayTimes generates, as `systemd-analyze calendar` reads them.
    case "minutely":
        return ["*-*-* *:00/" + s.interval + ":00" + calendarZoneSuffix(s)];
    case "hourly":
        return ["*-*-* 00/" + s.interval + ":00:00" + calendarZoneSuffix(s)];
    case "daily":
        date = "*-*-*";
        break;
    case "weekly":
        weekdays = orderedWeekdays(s.weekdays).map(function (w) { return SYSTEMD_WEEKDAYS[WEEKDAYS.indexOf(w)]; }).join(",") + " ";
        date = "*-*-*";
        break;
    case "monthly":
        if (s.monthly.by === "date") {
            date = "*-*-" + pad2(s.monthly.day);
        } else {
            weekdays = SYSTEMD_WEEKDAYS[WEEKDAYS.indexOf(s.monthly.weekday)] + " ";
            // The last week is the seven days ending the month: `~07/1`
            // counts from the seventh-last day to the last.
            date = s.monthly.week === -1 ? "*-*~07/1" : "*-*-" + pad2((s.monthly.week - 1) * 7 + 1) + ".." + pad2(Math.min(31, s.monthly.week * 7));
        }
        break;
    case "yearly":
        date = "*-" + pad2(s.yearly.month) + "-" + pad2(s.yearly.day);
        break;
    default:
        throw new Error("automations: frequency " + JSON.stringify(s.frequency) + " unjudged");
    }
    return s.times.map(function (time) { return weekdays + date + " " + time + ":00" + calendarZoneSuffix(s); });
}

function calendarZoneSuffix(s) {
    return s.zone === "utc" ? " UTC" : "";
}

// The cron fallback's fields per time of day, "minute hour day month
// weekday". cron ORs a day and a weekday, so a weekday within a week of the
// month is its weekday alone, the tighter of the two, and the guard keeps
// the week. A minutely or hourly rule is one line whose `*/N` steps from
// minute 0 or hour 0, the same slots as its OnCalendar= expression.
function cronFields(s) {
    var tail;
    switch (s.frequency) {
    case "minutely":
        return ["*/" + s.interval + " * * * *"];
    case "hourly":
        return ["0 */" + s.interval + " * * *"];
    case "daily":
        tail = "* * *";
        break;
    case "weekly":
        tail = "* * " + orderedWeekdays(s.weekdays).map(function (w) { return String((WEEKDAYS.indexOf(w) + 1) % 7); }).join(",");
        break;
    case "monthly":
        tail = s.monthly.by === "date" ? s.monthly.day + " * *" : "* * " + String((WEEKDAYS.indexOf(s.monthly.weekday) + 1) % 7);
        break;
    case "yearly":
        tail = s.yearly.day + " " + s.yearly.month + " *";
        break;
    default:
        throw new Error("automations: frequency " + JSON.stringify(s.frequency) + " unjudged");
    }
    return s.times.map(function (time) {
        var t = parseTime(time);
        return t.mi + " " + t.h + " " + tail;
    });
}

// ------------------------------------------------------------- summary

function listText(items) {
    if (items.length <= 1) return items.join("");
    return items.slice(0, -1).join(", ") + " and " + items[items.length - 1];
}

function every(n, one, many) {
    return n === 1 ? one : "Every " + n + " " + many;
}

function longDate(text) {
    var d = parseDate(text);
    return d.d + " " + MONTH_NAMES[d.m - 1] + " " + d.y;
}

function longDateFromScheduleInstant(ms, schedule) {
    var at = scheduleDate(ms, schedule);
    return at.d + " " + MONTH_NAMES[at.m - 1] + " " + at.y;
}

function weekdayNameFromScheduleInstant(ms, schedule) {
    var at = scheduleDate(ms, schedule);
    return WEEKDAY_NAMES[weekdayOf(at.y, at.m, at.d)];
}

function timeFromScheduleInstant(ms, schedule) {
    var at = new Date(ms);
    var hours = schedule.zone === "utc" ? at.getUTCHours() : at.getHours();
    var minutes = schedule.zone === "utc" ? at.getUTCMinutes() : at.getMinutes();
    return pad2(hours) + ":" + pad2(minutes);
}

function weekdayNameOfDate(text) {
    var d = parseDate(text);
    return WEEKDAY_NAMES[weekdayOf(d.y, d.m, d.d)];
}

// The rule in one line: "Every weekday at 09:00", "Every 2 weeks on Monday
// and Thursday at 08:30 and 17:00, 10 times", "Every 10 minutes".
function summaryText(s) {
    if (s.end.type === "count" && s.end.count === 1) {
        var first = occurrencesFrom(s, null, 1)[0];
        return first === undefined ? "Once" : "Once on " + weekdayNameFromScheduleInstant(first, s) + " " + longDateFromScheduleInstant(first, s) + " at " + timeFromScheduleInstant(first, s);
    }
    var head;
    var at = isStepFrequency(s.frequency) ? "" : " at " + listText(s.times);
    switch (s.frequency) {
    case "minutely":
        head = every(s.interval, "Every minute", "minutes");
        break;
    case "hourly":
        head = every(s.interval, "Every hour", "hours");
        break;
    case "daily":
        head = every(s.interval, "Every day", "days");
        break;
    case "weekly": {
        var days = orderedWeekdays(s.weekdays);
        if (s.interval === 1 && days.length === 7) head = "Every day";
        else if (s.interval === 1 && days.join() === WEEKDAYS.slice(0, 5).join()) head = "Every weekday";
        else head = every(s.interval, "Weekly", "weeks") + " on " + listText(days.map(function (w) { return WEEKDAY_NAMES[WEEKDAYS.indexOf(w)]; }));
        break;
    }
    case "monthly":
        head = every(s.interval, "Monthly", "months") + " on " + (s.monthly.by === "date"
            ? "day " + s.monthly.day
            : "the " + ORDINALS[String(s.monthly.week)] + " " + WEEKDAY_NAMES[WEEKDAYS.indexOf(s.monthly.weekday)]);
        break;
    case "yearly":
        head = every(s.interval, "Annually", "years") + " on " + s.yearly.day + " " + MONTH_NAMES[s.yearly.month - 1];
        break;
    default:
        throw new Error("automations: frequency " + JSON.stringify(s.frequency) + " unjudged");
    }
    var tail = s.end.type === "date" ? ", until " + longDate(s.end.date)
        : s.end.type === "count" ? (s.end.count === 1 ? ", once" : ", " + s.end.count + " times")
        : "";
    return head + at + tail;
}

// --------------------------------------------------------------- store

var AUTOMATION_KEYS = ["id", "name", "command", "enabled", "schedule", "timeoutSeconds", "catchUp", "requiresNetwork", "workingDirectory", "notifyEveryRun"];
// What `add` fills in when a definition leaves it out.
var AUTOMATION_DEFAULTS = { enabled: true, timeoutSeconds: TIMEOUT_DEFAULT, catchUp: false, requiresNetwork: false, workingDirectory: "", notifyEveryRun: false };

// An absolute path with no control character: a working directory, or one
// a unit or crontab line names.
function isAbsolutePath(value) {
    return typeof value === "string" && value.charAt(0) === "/" && value.length <= PATH_MAX && !/[\u0000-\u001f\u007f]/.test(value);
}

// "" or the first defect of one stored automation, under `where`.
//   id                ID_PATTERN; names the units and the records
//   name              a printable line of at most NAME_MAX
//   command           shell text of at most COMMAND_MAX, run as
//                     `<login shell> -l -c <command>`; newline and tab are
//                     allowed and other control characters are refused
//   enabled           whether its timer runs; a paused one keeps its history
//   schedule          scheduleError's model
//   timeoutSeconds    TIMEOUT_MIN..TIMEOUT_MAX
//   catchUp           run a missed occurrence at the next boot or trigger
//   requiresNetwork   admit a command only after full internet connectivity
//   workingDirectory  "" for the home directory, else an absolute path
//   notifyEveryRun    notify each start and success, not only errors
function automationError(a, where) {
    if (!isPlainObject(a)) return where + ": want=object";
    var unknown = unknownKey(a, AUTOMATION_KEYS, where);
    if (unknown !== "") return unknown;
    for (var k = 0; k < AUTOMATION_KEYS.length; k++)
        if (!hasOwn(a, AUTOMATION_KEYS[k])) return where + "." + AUTOMATION_KEYS[k] + ": missing";
    if (typeof a.id !== "string" || !ID_PATTERN.test(a.id)) return where + ".id: want=lower-case letters, digits and inner dashes, 1..40";
    if (!isPrintableLine(a.name, NAME_MAX)) return where + ".name: want=printable line of 1.." + NAME_MAX;
    if (!isCommandText(a.command, COMMAND_MAX))
        return where + ".command: want=command of 1.." + COMMAND_MAX + " without control characters except newline and tab";
    if (typeof a.enabled !== "boolean") return where + ".enabled: want=boolean";
    var scheduleDefect = scheduleError(a.schedule);
    if (scheduleDefect !== "") return where + "." + scheduleDefect;
    if (!isWhole(a.timeoutSeconds) || a.timeoutSeconds < TIMEOUT_MIN || a.timeoutSeconds > TIMEOUT_MAX) return where + ".timeoutSeconds: want=" + TIMEOUT_MIN + ".." + TIMEOUT_MAX;
    if (typeof a.catchUp !== "boolean") return where + ".catchUp: want=boolean";
    if (typeof a.requiresNetwork !== "boolean") return where + ".requiresNetwork: want=boolean";
    if (a.workingDirectory !== "" && !isAbsolutePath(a.workingDirectory)) return where + ".workingDirectory: want=\"\" or an absolute path";
    if (typeof a.notifyEveryRun !== "boolean") return where + ".notifyEveryRun: want=boolean";
    return "";
}

// The store's text judged: { ok: true, store } or { ok: false, error }.
// { version, automations }: every automation whole, ids distinct.
function parseStore(text) {
    var doc;
    try {
        doc = JSON.parse(String(text));
    } catch (e) {
        return { ok: false, error: "store: not-json" };
    }
    if (!isPlainObject(doc)) return { ok: false, error: "store: want=object" };
    var unknown = unknownKey(doc, ["version", "automations"], "store");
    if (unknown !== "") return { ok: false, error: unknown };
    if (doc.version !== STORE_VERSION) return { ok: false, error: "store.version: want=" + STORE_VERSION };
    if (!Array.isArray(doc.automations)) return { ok: false, error: "store.automations: want=list" };
    if (doc.automations.length > AUTOMATIONS_MAX) return { ok: false, error: "store.automations: length=" + doc.automations.length + " want<=" + AUTOMATIONS_MAX };
    var seen = {};
    for (var i = 0; i < doc.automations.length; i++) {
        var error = automationError(doc.automations[i], "store.automations." + i);
        if (error !== "") return { ok: false, error: error };
        if (hasOwn(seen, doc.automations[i].id)) return { ok: false, error: "store.automations." + i + ".id: duplicate" };
        seen[doc.automations[i].id] = true;
    }
    return { ok: true, store: doc };
}

function emptyStore() {
    return { version: STORE_VERSION, automations: [] };
}

// D107: migration alone reads the previous format. Current readers accept
// only v2, and the engine commits this conversion under its store lock.
function convertStoreV1(text) {
    var doc;
    try { doc = JSON.parse(String(text)); }
    catch (e) { return { ok: false, error: "store: not-json" }; }
    if (!isPlainObject(doc) || doc.version !== 1 || !Array.isArray(doc.automations))
        return { ok: false, error: "store.migration: want=version-1" };
    var unknown = unknownKey(doc, ["version", "automations"], "store");
    if (unknown !== "") return { ok: false, error: unknown };
    var converted = [];
    for (var i = 0; i < doc.automations.length; i++) {
        var old = doc.automations[i];
        if (!isPlainObject(old) || hasOwn(old, "requiresNetwork"))
            return { ok: false, error: "store.migration: invalid-version-1-automation" };
        converted.push(withKeys(old, { requiresNetwork: false }));
    }
    return parseStore(serializeStore({ version: STORE_VERSION, automations: converted }));
}

function serializeStore(store) {
    return JSON.stringify(store, null, 2) + "\n";
}

function indexOfAutomation(store, id) {
    for (var i = 0; i < store.automations.length; i++)
        if (store.automations[i].id === id) return i;
    return -1;
}

// An id from a name, distinct from `taken`: its letters and digits in
// lower case, runs of anything else as one dash, and "-2", "-3" on a clash.
function deriveId(name, taken) {
    var base = String(name).toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 32).replace(/-+$/, "");
    if (base === "") base = "automation";
    var id = base;
    for (var n = 2; taken.indexOf(id) !== -1; n++) id = base + "-" + n;
    return id;
}

// The store with one automation added from a definition, `add`'s answer:
// { ok, store, automation } or { ok: false, error }. The definition's
// missing keys take AUTOMATION_DEFAULTS, and a missing id is derived from
// the name.
function addAutomation(store, definition) {
    if (!isPlainObject(definition)) return { ok: false, error: "definition: want=object" };
    var unknown = unknownKey(definition, AUTOMATION_KEYS, "definition");
    if (unknown !== "") return { ok: false, error: unknown };
    if (store.automations.length >= AUTOMATIONS_MAX) return { ok: false, error: "store.automations: full limit=" + AUTOMATIONS_MAX };
    var taken = store.automations.map(function (a) { return a.id; });
    var made = {};
    for (var k = 0; k < AUTOMATION_KEYS.length; k++) {
        var key = AUTOMATION_KEYS[k];
        if (hasOwn(definition, key)) made[key] = definition[key];
        else if (hasOwn(AUTOMATION_DEFAULTS, key)) made[key] = AUTOMATION_DEFAULTS[key];
    }
    if (!hasOwn(made, "id")) made.id = deriveId(typeof made.name === "string" ? made.name : "", taken);
    else if (taken.indexOf(made.id) !== -1) return { ok: false, error: "definition.id: taken=" + made.id };
    var error = automationError(made, "definition");
    if (error !== "") return { ok: false, error: error };
    return { ok: true, store: { version: STORE_VERSION, automations: store.automations.concat([made]) }, automation: made };
}

// The store with one automation's keys replaced by `changes`, `edit`'s
// answer. A schedule is replaced whole; the id never changes.
function editAutomation(store, id, changes) {
    var at = indexOfAutomation(store, id);
    if (at === -1) return { ok: false, error: "id: unknown=" + id };
    if (!isPlainObject(changes)) return { ok: false, error: "definition: want=object" };
    var unknown = unknownKey(changes, AUTOMATION_KEYS, "definition");
    if (unknown !== "") return { ok: false, error: unknown };
    if (hasOwn(changes, "id") && changes.id !== id) return { ok: false, error: "definition.id: fixed=" + id };
    var made = withKeys(store.automations[at], changes);
    var error = automationError(made, "definition");
    if (error !== "") return { ok: false, error: error };
    var list = store.automations.slice();
    list[at] = made;
    return { ok: true, store: { version: STORE_VERSION, automations: list }, automation: made };
}

function removeAutomation(store, id) {
    var at = indexOfAutomation(store, id);
    if (at === -1) return { ok: false, error: "id: unknown=" + id };
    var list = store.automations.slice();
    list.splice(at, 1);
    return { ok: true, store: { version: STORE_VERSION, automations: list } };
}

// The guard's per-automation state, `{ handledThrough }` in ms: the file
// `add`, `enable` and every guarded trigger write.
function parseGuardState(text) {
    var doc;
    try {
        doc = JSON.parse(String(text));
    } catch (e) {
        return { ok: false, error: "guard: not-json" };
    }
    if (!isPlainObject(doc)) return { ok: false, error: "guard: want=object" };
    var unknown = unknownKey(doc, ["handledThrough"], "guard");
    if (unknown !== "") return { ok: false, error: unknown };
    if (!isWhole(doc.handledThrough) || doc.handledThrough < 0) return { ok: false, error: "guard.handledThrough: want=ms" };
    return { ok: true, handledThrough: doc.handledThrough };
}

// ------------------------------------------------------ units and cron

function unitName(id, suffix) {
    return UNIT_PREFIX + id + "." + suffix;
}

// Whether a file name is one sync owns in the systemd user unit directory.
function isOwnedUnit(name) {
    var match = /^vgs-automation-(.+)\.(timer|service)$/.exec(name);
    return match !== null && ID_PATTERN.test(match[1]);
}

// One word of DIRECTIVE's line, quoted as systemd reads it back: a
// backslash and a quote escaped, and `%` doubled so no specifier expands,
// which every line does. A command line, ExecStart=, also expands `$`, so
// its words double it (systemd.service(5), Command lines); Environment=
// gives `$` no special meaning, so it stays single there (systemd.exec(5),
// Environment=).
function systemdQuote(directive, arg) {
    var s = String(arg);
    if (/[\u0000-\u001f\u007f]/.test(s)) throw new Error("automations: unit argument " + JSON.stringify(s) + " holds a control character");
    var quoted = s.replace(/\\/g, "\\\\").replace(/"/g, "\\\"").replace(/%/g, "%%");
    return "\"" + (directive === "Environment" ? quoted : quoted.replace(/\$/g, "$$$$")) + "\"";
}

function timerUnit(automation) {
    var lines = [
        "# Written by vgs.automations sync from automations.json; sync replaces it.",
        "[Unit]",
        "Description=VGS automation " + automation.id,
        "",
        "[Timer]"
    ];
    var expressions = calendarExpressions(automation.schedule);
    for (var i = 0; i < expressions.length; i++) lines.push("OnCalendar=" + expressions[i]);
    lines.push("AccuracySec=1s");
    lines.push("Persistent=" + (automation.catchUp ? "true" : "false"));
    lines.push("", "[Install]", "WantedBy=timers.target", "");
    return lines.join("\n");
}

// `argv` runs the runner under its lock; `environment` is the directories
// the runner reads, as NAME=value, since a user manager's environment need
// not hold the ones the CLI resolved. A oneshot service has no start
// timeout: the runner's own timeout ends the command. A trigger while a run
// holds the lock exits 75 and is not a failure.
function serviceUnit(automation, argv, environment) {
    return [
        "# Written by vgs.automations sync from automations.json; sync replaces it.",
        "[Unit]",
        "Description=VGS automation " + automation.id,
        "",
        "[Service]",
        "Type=oneshot",
        "Environment=" + environment.map(function (word) { return systemdQuote("Environment", word); }).join(" "),
        "ExecStart=" + argv.map(function (word) { return systemdQuote("ExecStart", word); }).join(" "),
        "SuccessExitStatus=75",
        ""
    ].join("\n");
}

// One argument of a crontab line, single-quoted for the /bin/sh cron runs.
// cron turns an unescaped `%` into a newline, so an argument holding one is
// refused rather than escaped.
function cronQuote(arg) {
    var s = String(arg);
    if (/[\u0000-\u001f\u007f%]/.test(s)) throw new Error("automations: crontab argument " + JSON.stringify(s) + " holds a control character or %");
    return "'" + s.replace(/'/g, "'\\''") + "'";
}

// The crontab lines of every enabled automation: its fields, then `env`
// with the directories the runner reads and the runner argv
// `argvFor(automation)` answers. An automation that catches up also runs
// the same scheduled trigger at `@reboot`, cron's Persistent=true: the
// guard then runs the latest occurrence the machine was off for, since
// catch-up lets a late one run, and nothing when that one was handled.
function cronLines(automations, argvFor, environment) {
    var local = [];
    var utc = [];
    var env = environment.map(cronQuote).join(" ");
    for (var i = 0; i < automations.length; i++) {
        if (!automations[i].enabled) continue;
        var command = "env " + env + " " + argvFor(automations[i]).map(cronQuote).join(" ");
        var fields = cronFields(automations[i].schedule);
        var out = automations[i].schedule.zone === "utc" ? utc : local;
        for (var f = 0; f < fields.length; f++) out.push(fields[f] + " " + command);
        if (automations[i].catchUp) out.push("@reboot " + command);
    }
    return local.concat(utc.length === 0 ? [] : ["CRON_TZ=UTC"], utc, utc.length === 0 ? [] : ["CRON_TZ="]);
}

// The user's crontab with the managed block replaced by `lines`, or
// dropped when there are none: { ok, text } or { ok: false, error }. Lines
// outside the block stay as they were. A crontab holding BEGIN without END,
// or either twice, is refused.
function crontabWith(text, lines) {
    var rows = String(text).split("\n");
    if (rows.length > 0 && rows[rows.length - 1] === "") rows.pop();
    var begin = rows.indexOf(CRON_BEGIN);
    var end = rows.indexOf(CRON_END);
    if ((begin === -1) !== (end === -1) || end < begin || (begin !== -1 && (rows.indexOf(CRON_BEGIN, begin + 1) !== -1 || rows.indexOf(CRON_END, end + 1) !== -1)))
        return { ok: false, error: "crontab: block=malformed" };
    var kept = begin === -1 ? rows : rows.slice(0, begin).concat(rows.slice(end + 1));
    var all = lines.length === 0 ? kept : kept.concat([CRON_BEGIN], lines, [CRON_END]);
    return { ok: true, text: all.length === 0 ? "" : all.join("\n") + "\n" };
}

// ----------------------------------------------------------- run records

// The files of one run, flat in the runs directory so one listing notices
// every new record: <id>@<run>.started.json, <id>@<run>.ended.json and the
// transcript <id>@<run>.log. <run> is `<start ms>-<runner pid>`.
var RUN_FILE = /^([a-z0-9](?:[a-z0-9-]{0,38}[a-z0-9])?)@(\d{13}-\d+)\.(started\.json|ended\.json|log)$/;

function runFile(id, run, kind) {
    return id + "@" + run + (kind === "log" ? ".log" : "." + kind + ".json");
}

// { id, run, kind } for a run file's name, kind started, ended or log;
// null for any other name, such as a record's temporary file.
function parseRunFile(name) {
    var match = RUN_FILE.exec(String(name));
    if (match === null) return null;
    return { id: match[1], run: match[2], kind: match[3] === "log" ? "log" : match[3].slice(0, match[3].indexOf(".")) };
}

var STARTED_KEYS = ["version", "automation", "run", "name", "command", "directory", "trigger", "slot", "startedAt", "transcript"];
var ENDED_KEYS = STARTED_KEYS.concat(["endedAt", "durationMs", "outcome", "exitCode", "signal", "reason", "transcriptBytes", "truncated", "snippet"]);

// "" or the first defect of a started or ended record.
function recordError(rec, kind) {
    if (!isPlainObject(rec)) return "record: want=object";
    var keys = kind === "ended" ? ENDED_KEYS : STARTED_KEYS;
    var unknown = unknownKey(rec, keys, "record");
    if (unknown !== "") return unknown;
    for (var i = 0; i < keys.length; i++)
        if (!hasOwn(rec, keys[i])) return "record." + keys[i] + ": missing";
    if (rec.version !== RECORD_VERSION) return "record.version: want=" + RECORD_VERSION;
    if (typeof rec.automation !== "string" || !ID_PATTERN.test(rec.automation)) return "record.automation: want=id";
    if (typeof rec.run !== "string" || !/^\d{13}-\d+$/.test(rec.run)) return "record.run: want=<ms>-<pid>";
    var strings = ["name", "command", "directory", "transcript"];
    for (var s = 0; s < strings.length; s++)
        if (typeof rec[strings[s]] !== "string") return "record." + strings[s] + ": want=string";
    if (TRIGGERS.indexOf(rec.trigger) === -1) return "record.trigger: want=" + TRIGGERS.join("|");
    if (rec.slot !== null && !isWhole(rec.slot)) return "record.slot: want=ms|null";
    if (!isWhole(rec.startedAt)) return "record.startedAt: want=ms";
    if (kind !== "ended") return "";
    if (!isWhole(rec.endedAt) || rec.endedAt < rec.startedAt) return "record.endedAt: want=ms>=startedAt";
    if (!isWhole(rec.durationMs) || rec.durationMs < 0) return "record.durationMs: want=ms";
    if (ENDED_OUTCOMES.indexOf(rec.outcome) === -1) return "record.outcome: want=" + ENDED_OUTCOMES.join("|");
    if (rec.exitCode !== null && !isWhole(rec.exitCode)) return "record.exitCode: want=integer|null";
    if (rec.signal !== null && typeof rec.signal !== "string") return "record.signal: want=string|null";
    if (typeof rec.reason !== "string") return "record.reason: want=string";
    if (!isWhole(rec.transcriptBytes) || rec.transcriptBytes < 0) return "record.transcriptBytes: want=bytes";
    if (typeof rec.truncated !== "boolean") return "record.truncated: want=boolean";
    if (typeof rec.snippet !== "string") return "record.snippet: want=string";
    return "";
}

// How long after its start a command's name-resolution failure counts as
// the network not being ready yet. A requiresNetwork command starts as soon
// as the runner's wait reads Connectivity FULL, so this is the window after
// FULL as the runner saw it; NetworkManager's FULL can be stale just after
// a resume, before the resolver answers (px13, 2026-10-30).
var NETWORK_DNS_WINDOW_MS = 60000;
// The resolver failures a command reports: curl's, which git prints as
// "fatal: unable to access '<url>': Could not resolve host: github.com"
// (px13's run, 2026-10-30); OpenSSH's resolve_host() in ssh.c; and glibc's
// gai_strerror(EAI_AGAIN).
var NETWORK_DNS_PHRASES = ["Could not resolve host: ", "Could not resolve hostname ", "Temporary failure in name resolution"];

// A run's outcome and reason from how its command ended: `failed-start`
// when it never ran, `timeout` when the runner's timer killed it,
// `succeeded` on exit 0, else `failed`, each with the ending's reason.
// `context` is { trigger, requiresNetwork, snippet, durationMs, previous },
// `previous` the automation's newest ended run before this one, or null.
// A failure is `skipped` with reason `network-dns` only when the
// automation needs the network, the trigger is scheduled (a person at Run
// now or Test run keeps the failure to act on), the command exited
// non-zero by itself within NETWORK_DNS_WINDOW_MS of its start, a line of
// its snippet names one of NETWORK_DNS_PHRASES, and the automation's
// newest ended run succeeded. A name that never resolves therefore fails
// from its second run on, every run after; a first run, a run whose
// history was cleared or pruned, and a run after any skip or failure keep
// the failure.
function outcomeOf(ending, context) {
    if (ending.started !== true) return { outcome: "failed-start", reason: ending.reason };
    if (ending.timedOut === true) return { outcome: "timeout", reason: ending.reason };
    if (ending.exitCode === 0 && ending.signal === null) return { outcome: "succeeded", reason: ending.reason };
    var previous = context.previous;
    var dns = context.requiresNetwork === true && context.trigger === "scheduled"
        && ending.signal === null && ending.exitCode !== null && context.durationMs <= NETWORK_DNS_WINDOW_MS
        && String(context.snippet).split("\n").some(function (line) {
            return NETWORK_DNS_PHRASES.some(function (phrase) { return line.indexOf(phrase) !== -1; });
        })
        && previous !== null && previous.outcome === "succeeded";
    return dns ? { outcome: "skipped", reason: "network-dns" } : { outcome: "failed", reason: ending.reason };
}

// The error notification's snippet: the last stderr lines, or the last
// stdout lines when the command wrote nothing to stderr, at most
// SNIPPET_LINES non-blank lines and SNIPPET_CHARS characters, the newest
// kept, each as plain text (plainOutput).
function snippetOf(stderrLines, stdoutLines) {
    var fromErr = lastLines(stderrLines);
    var text = fromErr.length > 0 ? fromErr.join("\n") : lastLines(stdoutLines).join("\n");
    return text.length > SNIPPET_CHARS ? text.slice(text.length - SNIPPET_CHARS) : text;
}

function lastLines(lines) {
    var kept = [];
    for (var i = lines.length - 1; i >= 0 && kept.length < SNIPPET_LINES; i--) {
        var line = plainOutput(lines[i]).replace(/\s+$/, "");
        if (line.trim() !== "") kept.unshift(line);
    }
    return kept;
}

// A terminal escape sequence a command writes for colour, a window title or
// a link, whole, so none of its text is left behind: an OSC string to its
// BEL or ST, or to the line's end; a CSI sequence to its final byte; and any
// other ESC sequence (ECMA-48 5th edition § 5.3 and § 5.4 for the ESC and
// CSI forms and their 8-bit introducers, § 5.6 for the OSC control string;
// BEL as an OSC terminator is xterm's, ctlseqs § Operating System
// Commands).
var TERMINAL_ESCAPE = /(?:\u001b\]|\u009d)[^\u0007\u001b\u009c]*(?:\u0007|\u001b\\|\u009c|$)|(?:\u001b\[|\u009b)[0-?]*[ -\/]*[@-~]|\u001b[ -\/]*[0-~]/g;

// A line of a command's output as plain text: its escape sequences whole,
// then every other control character but a tab.
function plainOutput(line) {
    return String(line).replace(TERMINAL_ESCAPE, "").replace(/[\u0000-\u0008\u000a-\u001f\u007f-\u009f]/g, "");
}

// History rows, newest first, from the run files one listing found.
// `records` maps "<id>@<run>" to { started, ended }, each a parsed record or
// null; `liveIds` holds each automation whose lock a runner holds, which
// keeps its newest open run `running`; every other open run is `vanished`.
// A record the judge refuses is left out and named in `refused`.
function historyRows(records, liveIds) {
    var rows = [];
    var refused = [];
    var newestOpen = {};
    var keys = Object.keys(records).sort();
    for (var i = 0; i < keys.length; i++) {
        var pair = records[keys[i]];
        var kind = pair.ended !== null ? "ended" : "started";
        var rec = pair.ended !== null ? pair.ended : pair.started;
        if (rec === null) continue;
        var error = recordError(rec, kind);
        if (error === "" && keys[i] !== rec.automation + "@" + rec.run) error = "record.run: want=" + keys[i];
        if (error !== "") {
            refused.push({ key: keys[i], error: error });
            continue;
        }
        var ended = kind === "ended";
        if (!ended) newestOpen[rec.automation] = rec.run;
        rows.push({
            automation: rec.automation,
            run: rec.run,
            name: rec.name,
            command: rec.command,
            trigger: rec.trigger,
            slot: rec.slot,
            startedAt: rec.startedAt,
            endedAt: ended ? rec.endedAt : null,
            durationMs: ended ? rec.durationMs : null,
            outcome: ended ? rec.outcome : "open",
            exitCode: ended ? rec.exitCode : null,
            signal: ended ? rec.signal : null,
            reason: ended ? rec.reason : "",
            transcript: rec.transcript,
            truncated: ended ? rec.truncated : false,
            snippet: ended ? rec.snippet : ""
        });
    }
    for (var r = 0; r < rows.length; r++) {
        if (rows[r].outcome !== "open") continue;
        var live = liveIds.indexOf(rows[r].automation) !== -1 && newestOpen[rows[r].automation] === rows[r].run;
        rows[r].outcome = live ? "running" : "vanished";
    }
    rows.sort(function (a, b) { return b.startedAt - a.startedAt || (a.run < b.run ? 1 : -1); });
    for (var t = 0; t < rows.length; t++) {
        rows[t].tone = OUTCOMES[rows[t].outcome].tone;
        rows[t].icon = OUTCOMES[rows[t].outcome].icon;
    }
    return { rows: rows, refused: refused };
}

// The retention setting as a whole number of days, 1 to HISTORY_DAYS_MAX;
// anything else throws, since the manifest's schema bounds the setting.
function retentionDays(value) {
    if (!isWhole(value) || value < 1 || value > HISTORY_DAYS_MAX) throw new Error("automations: history days " + JSON.stringify(value) + " is not 1.." + HISTORY_DAYS_MAX);
    return value;
}

// The runs, as "<id>@<run>", a prune removes: every one that is not
// running and started before the retention window or past its
// automation's newest HISTORY_RUNS_MAX.
function prunable(rows, nowMs, days) {
    var cutoff = nowMs - retentionDays(days) * DAY_MS;
    var newest = rows.filter(function (r) { return r.outcome !== "running"; });
    newest.sort(function (a, b) { return b.startedAt - a.startedAt || (a.run < b.run ? 1 : -1); });
    var kept = {};
    var beyondCap = {};
    for (var n = 0; n < newest.length; n++) {
        var id = newest[n].automation;
        kept[id] = (hasOwn(kept, id) ? kept[id] : 0) + 1;
        if (kept[id] > HISTORY_RUNS_MAX) beyondCap[id + "@" + newest[n].run] = true;
    }
    var out = [];
    for (var i = 0; i < rows.length; i++) {
        var key = rows[i].automation + "@" + rows[i].run;
        if (rows[i].outcome === "running") continue;
        if (rows[i].startedAt < cutoff || hasOwn(beyondCap, key)) out.push(key);
    }
    return out;
}

// -------------------------------------------------------- notifications

// bin/automations supplies the keyed reasons. UI callers keep the raw
// failure in the log and use this table for notices and status.
var FAILURE_TEXT = [
    [/run=busy/, "This automation is running or waiting. Let it finish, or cancel its waiting run."],
    [/id=unknown|id: unknown/, "This automation no longer exists. Choose another automation."],
    [/store=|store:/, "The saved automations could not be read. Open Automations to check them."],
    [/directory=/, "The work folder is unavailable. Choose another folder in Automations."],
    [/shell=|spawn=|start=failed/, "The automation could not start. Check its command in Automations."],
    [/definition=|definition:/, "The automation could not be saved. Check its fields in Automations."],
    [/scheduler=none|systemctl=|systemd-run=|crontab=/, "The scheduler is unavailable. Open Automations to check its status."],
    [/schedule|calendar=/, "The schedule is invalid. Check its dates and times in Automations."],
    [/answer=not-json|file=unreadable/, "The automation result could not be read. Open Automations to try again."]
];

function failureText(reason) {
    for (var i = 0; i < FAILURE_TEXT.length; i++)
        if (FAILURE_TEXT[i][0].test(String(reason))) return FAILURE_TEXT[i][1];
    return "The automation request failed. Open Automations to try again.";
}

// Why a run was skipped, for its history row, its list row and its notice;
// "" for a reason with nothing to add to Skipped.
var SKIP_TEXT = {
    "network-offline-late": "No internet connection",
    "network-dns": "Network not ready yet",
    "cancelled-before-start": "Cancelled before start"
};

function skipText(reason) {
    return hasOwn(SKIP_TEXT, reason) ? SKIP_TEXT[reason] : "";
}

// Why a run failed, in one line. A run that exited with an error says why
// in its own words: the last line it wrote to stderr, else to stdout, the
// stream a refusal or an error goes to (snippetOf's rule, read back by
// lastOutputLine). A run that printed nothing, and one a signal stopped,
// whose reason is the signal, keep a sentence of their own.
function failureLine(rec) {
    switch (rec.outcome) {
    case "failed":
        if (rec.signal !== null) return "The automation was stopped. Open Automations to read its output.";
        var line = lastOutputLine(rec.snippet);
        return line !== "" ? line : "The automation failed. Open Automations to read its output.";
    case "timeout": return "Timed out after " + Commons.Duration.format(Math.round(rec.durationMs / 1000));
    case "failed-start": return failureText(rec.reason);
    default: throw new Error("automations: outcome " + JSON.stringify(rec.outcome) + " is not a failure");
    }
}

// The last non-blank line of an ended record's snippet, "" for none. The
// line is the command's own text, which no rule trusts: it is read as plain
// text (plainOutput) whatever the record holds, a tab reads as a space, and
// a line past FAILURE_LINE_MAX ends in an ellipsis, never between the two
// halves of a surrogate pair. notifySendArgs escapes it as markup.
function lastOutputLine(snippet) {
    var lines = String(snippet).split("\n");
    for (var i = lines.length - 1; i >= 0; i--) {
        var line = plainOutput(lines[i]).replace(/\t/g, " ").trim();
        if (line === "") continue;
        if (line.length <= FAILURE_LINE_MAX) return line;
        var cut = FAILURE_LINE_MAX - 1;
        if (/[\ud800-\udbff]/.test(line.charAt(cut - 1))) cut--;
        return line.slice(0, cut).replace(/\s+$/, "") + "…";
    }
    return "";
}

// The notification a run event sends, or null when it sends none: an error
// always, the start and a success only under notifyEveryRun, and the first
// success after a failure always, as recovered. Each carries the VGS hints
// vgs.notifications reads (shell/plugins/vgs.notifications/developer.md § Hints): a Lucide
// icon, a design-system status tone, the transcript to open and what a
// click does. `event` is start (with the started record) or end
// (with the ended one and the automation's failure streak before it, null
// for none); a failure after the first of a streak counts the failures since
// the first one. A skip sends no alert; under notifyEveryRun the end of a
// skipped command replaces its start notice, as a finish does.
function notificationFor(event, automation, rec, streak) {
    if (rec !== null && rec.outcome === "skipped") {
        if (event !== "end" || automation.notifyEveryRun !== true) return null;
        return { summary: automation.name + " skipped", body: skipText(rec.reason), urgency: "low", icon: "circle-minus", tone: "info", click: "open", open: rec.transcript };
    }
    if (event === "start") {
        if (automation.notifyEveryRun !== true) return null;
        return { summary: automation.name + " started", body: "The automation is running.", urgency: "low", icon: "play", tone: "warning", click: "none", open: "" };
    }
    if (event !== "end") throw new Error("automations: notification event " + JSON.stringify(event) + " is not start or end");
    var finished = "Finished in " + Commons.Duration.format(Math.round(rec.durationMs / 1000));
    if (rec.outcome === "succeeded") {
        if (streak !== null)
            return { summary: automation.name + " recovered", body: finished + " after " + streak.failures + (streak.failures === 1 ? " failed run" : " failed runs"), urgency: "low", icon: "circle-check", tone: "success", click: "open", open: rec.transcript };
        if (automation.notifyEveryRun !== true) return null;
        return { summary: automation.name + " finished", body: finished, urgency: "low", icon: "circle-check", tone: "success", click: "open", open: rec.transcript };
    }
    var body = streak === null ? failureLine(rec) : "Failed " + (streak.failures + 1) + " times since " + sinceText(streak.since, rec.startedAt) + "\n" + failureLine(rec);
    return { summary: automation.name + " failed", body: body, urgency: "critical", icon: "circle-x", tone: "danger", click: "open", open: rec.transcript };
}

// When a streak began, as its notice reads it: the time alone on the day
// of `nowMs`, else the day too.
function sinceText(sinceMs, nowMs) {
    var since = new Date(sinceMs);
    var now = new Date(nowMs);
    var sameDay = since.getFullYear() === now.getFullYear() && since.getMonth() === now.getMonth() && since.getDate() === now.getDate();
    return sameDay ? pad2(since.getHours()) + ":" + pad2(since.getMinutes()) : formatWhen(sinceMs);
}

// The failure streak an automation's run leaves: none after a success,
// else one failure more than `streak`, whose notice is now `notice`.
function streakAfter(rec, streak, notice) {
    if (rec.outcome === "skipped") return streak;
    if (rec.outcome === "succeeded") return null;
    return {
        notice: isNotice(notice) ? notice : null,
        failures: streak === null ? 1 : streak.failures + 1,
        since: streak === null ? rec.startedAt : streak.since
    };
}

// A notice the runner can replace: `{ id, server }`, the id notify-send
// printed and the server that handed it out, as notificationServer names it.
function isNotice(value) {
    return isPlainObject(value) && unknownKey(value, ["id", "server"], "notice") === ""
        && isWhole(value.id) && value.id > 0 && typeof value.server === "string" && value.server !== "";
}

// The runner's per-automation streak file, `{ notice, failures, since }`:
// the open failure notice (null when there is none to replace), the
// failed runs in a row and when the first of them started, in ms. The
// runner writes it after a failed run and removes it after a success, so
// no file is no streak.
function parseStreak(text) {
    var doc;
    try {
        doc = JSON.parse(String(text));
    } catch (e) {
        return { ok: false, error: "streak: not-json" };
    }
    if (!isPlainObject(doc)) return { ok: false, error: "streak: want=object" };
    var unknown = unknownKey(doc, ["notice", "failures", "since"], "streak");
    if (unknown !== "") return { ok: false, error: unknown };
    if (doc.notice !== null && !isNotice(doc.notice)) return { ok: false, error: "streak.notice: want={id,server}|null" };
    if (!isWhole(doc.failures) || doc.failures < 1) return { ok: false, error: "streak.failures: want=count" };
    if (!isWhole(doc.since) || doc.since < 0) return { ok: false, error: "streak.since: want=ms" };
    return { ok: true, streak: { notice: doc.notice, failures: doc.failures, since: doc.since } };
}

// The notification server notify-send reaches, from busctl --json=short's
// replies to org.freedesktop.DBus GetId and to GetNameOwner of
// org.freedesktop.Notifications: "<bus id> <unique name>", or null when a
// reply is missing or not one string. A notice id names a notification of
// one server process alone (Quickshell's NotificationServer counts ids from
// 1 in each). A unique name is never reused on one bus, and the bus id is
// new for each bus daemon (the D-Bus specification, § Message Bus Names and
// § org.freedesktop.DBus.GetId), so the pair changes on a shell restart, a
// new session bus at login and a reboot, where the unique name alone can
// recur on a fresh bus.
function notificationServer(busReply, ownerReply) {
    var bus = busctlString(busReply);
    var owner = busctlString(ownerReply);
    return bus === null || owner === null ? null : bus + " " + owner;
}

// The one string a busctl --json=short call reply carries,
// `{"type":"s","data":["..."]}`, or null.
function busctlString(reply) {
    if (reply === null) return null;
    var doc;
    try {
        doc = JSON.parse(String(reply));
    } catch (e) {
        return null;
    }
    if (!isPlainObject(doc) || doc.type !== "s" || !Array.isArray(doc.data) || doc.data.length !== 1) return null;
    var value = doc.data[0];
    return typeof value === "string" && value !== "" && !/\s/.test(value) ? value : null;
}

// The id a notification replaces: the notice's, when the server that
// handed it out still owns the name, else null, since another server's
// same id names a notification another application may have open.
function replaceIdFor(notice, server) {
    return notice !== null && server !== null && notice.server === server ? notice.id : null;
}

// notify-send's argv for a notification, replacing `replaceId` when it is
// a positive number; the summary and body follow `--`, so neither is read
// as an option. It prints the id a later notification replaces. The
// notification server reads a body as markup, so the body's `&`, `<` and
// `>` are escaped, as the core escapes a plugin message
// (PluginLogic.notifyArgv), and a run's output line shows as it printed it.
function notifySendArgs(n, replaceId) {
    var args = ["--app-name=Automations", "--urgency=" + n.urgency, "--print-id",
        "--hint=string:x-vgs-avatar:calendar-clock", "--hint=string:x-vgs-icon:" + n.icon, "--hint=string:x-vgs-tone:" + n.tone, "--hint=string:x-vgs-click:" + n.click];
    if (n.open !== "") args.push("--hint=string:x-vgs-open:" + n.open);
    if (isWhole(replaceId) && replaceId > 0) args.push("--replace-id=" + replaceId);
    return args.concat(["--", n.summary, n.body.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")]);
}

// ------------------------------------------------------------- network

// Only NetworkManager's latest Connectivity result FULL admits a command.
// UNKNOWN may mean connectivity checks are disabled; it proves no outage.
// https://networkmanager.dev/docs/api/latest/nm-dbus-types.html
var NM_CONNECTIVITY_FULL = 4;
// Preserve the previous network wait's active-time grace. Expiry classifies
// the wait; it never grants permission or extends the schedule's late bound.
var NETWORK_GRACE_MS = 60000;
var NETWORK_POLL_SECONDS = 5;

function nmConnectivity(reply) {
    var doc;
    try { doc = JSON.parse(String(reply)); }
    catch (e) { return null; }
    return isPlainObject(doc) && doc.type === "u" && isWhole(doc.data)
        && doc.data >= 0 && doc.data <= NM_CONNECTIVITY_FULL ? doc.data : null;
}

function networkAdmission(requiresNetwork, connectivity, waitedMs) {
    if (!requiresNetwork || connectivity === NM_CONNECTIVITY_FULL)
        return { admit: true, diagnostic: null };
    return { admit: false, diagnostic: connectivity === null || connectivity === 0 ? "unavailable"
        : waitedMs < NETWORK_GRACE_MS ? "grace" : "offline" };
}

// Polls remain bounded after grace, so missing signals cannot lose a
// reconnect or cancellation. The runner owns one child at a time.
function networkWaitSeconds(waitedMs) {
    var remaining = NETWORK_GRACE_MS - waitedMs;
    return remaining <= 0 ? NETWORK_POLL_SECONDS : Math.min(NETWORK_POLL_SECONDS, Math.max(1, Math.ceil(remaining / 1000)));
}

// The engine validates process identity and phase before publishing this
// marker. A saved definition lets a cancellation record what never started.
function parsePending(text) {
    var doc;
    try { doc = JSON.parse(String(text)); }
    catch (e) { return { ok: false, error: "pending: not-json" }; }
    if (!isPlainObject(doc)) return { ok: false, error: "pending: want=object" };
    var keys = ["version", "kind", "phase", "token", "owner", "dueAt", "trigger", "diagnostic", "definition", "engine"];
    var unknown = unknownKey(doc, keys, "pending");
    if (unknown !== "") return { ok: false, error: unknown };
    for (var i = 0; i < keys.length; i++)
        if (!hasOwn(doc, keys[i])) return { ok: false, error: "pending." + keys[i] + ": missing" };
    if (doc.version !== 1 || doc.kind !== "network" || ["waiting", "admitted"].indexOf(doc.phase) === -1
        || typeof doc.token !== "string" || doc.token === ""
        || !isWhole(doc.dueAt) || doc.dueAt < 0 || TRIGGERS.indexOf(doc.trigger) === -1
        || ["grace", "offline", "unavailable"].indexOf(doc.diagnostic) === -1 || !isAbsolutePath(doc.engine))
        return { ok: false, error: "pending: invalid-state" };
    var owner = doc.owner;
    if (!isPlainObject(owner) || unknownKey(owner, ["pid", "startTime", "bootId"], "pending.owner") !== ""
        || !isWhole(owner.pid) || owner.pid <= 0 || typeof owner.startTime !== "string"
        || !/^\d+$/.test(owner.startTime) || typeof owner.bootId !== "string" || owner.bootId === "")
        return { ok: false, error: "pending.owner: invalid-identity" };
    var error = automationError(doc.definition, "pending.definition");
    return error === "" ? { ok: true, pending: doc } : { ok: false, error: error };
}

// --------------------------------------------------------------- status

// The rows `list --json` prints, one per automation, from the store, the
// history rows newest first and the time: its settings, its summary, its
// state, its next occurrence (null when paused or ended), its last run and
// the engine's live waiting marker, if any. A manual wait can be paused;
// scheduled pauses and an actual running command take precedence.
function listRows(store, rows, nowMs, pendingById) {
    pendingById = pendingById || {};
    var latest = {};
    for (var i = 0; i < rows.length; i++)
        if (!hasOwn(latest, rows[i].automation)) latest[rows[i].automation] = rows[i];
    return store.automations.map(function (a) {
        var next = occurrencesFrom(a.schedule, nowMs, 1);
        var last = hasOwn(latest, a.id) ? latest[a.id] : null;
        var pending = hasOwn(pendingById, a.id) ? pendingById[a.id] : null;
        if (last !== null && last.outcome === "running") pending = null;
        if (!a.enabled && (pending === null || pending.trigger !== "manual")) pending = null;
        return {
            id: a.id,
            name: a.name,
            command: a.command,
            enabled: a.enabled,
            schedule: a.schedule,
            timeoutSeconds: a.timeoutSeconds,
            catchUp: a.catchUp,
            requiresNetwork: a.requiresNetwork,
            pending: pending,
            workingDirectory: a.workingDirectory,
            notifyEveryRun: a.notifyEveryRun,
            summary: summaryText(a.schedule),
            state: pending !== null ? "waiting" : !a.enabled ? "paused" : last !== null && last.outcome === "running" ? "running" : next.length === 0 ? "ended" : "scheduled",
            nextRun: a.enabled && next.length > 0 ? next[0] : null,
            lastRun: last === null ? null : { run: last.run, outcome: last.outcome, reason: last.reason, tone: last.tone, startedAt: last.startedAt, endedAt: last.endedAt, transcript: last.transcript }
        };
    });
}

// A local time as the status line reads it: "Tue 30 Sep 2026 09:00".
function formatWhen(ms) {
    var at = new Date(ms);
    return WEEKDAY_NAMES[(at.getDay() + 6) % 7].slice(0, 3) + " " + at.getDate() + " " + MONTH_NAMES[at.getMonth()].slice(0, 3) + " " + at.getFullYear() + " " + pad2(at.getHours()) + ":" + pad2(at.getMinutes());
}

// The values the service publishes from `list --json`'s document,
// { scheduler, linger, automations }: which scheduler runs the timers,
// whether they run while logged out, how many are scheduled, the next run
// and the automations whose last run failed. Lingering off offers the
// manifest's Enable while logged out action, the `linger` TUI, in the info
// tone of an optional step.
function statusValues(listed) {
    var rows = listed.automations;
    var next = null;
    var failing = [];
    for (var i = 0; i < rows.length; i++) {
        if (rows[i].nextRun !== null && (next === null || rows[i].nextRun < next)) next = rows[i].nextRun;
        if (rows[i].lastRun !== null && OUTCOMES[rows[i].lastRun.outcome].error) failing.push(rows[i].name);
    }
    var scheduler;
    switch (listed.scheduler) {
    case "systemd": scheduler = { tone: "ok", text: "Ready" }; break;
    case "cron": scheduler = { tone: "warning", text: "Using the backup scheduler" }; break;
    case "none": scheduler = { tone: "danger", text: "No scheduler is available" }; break;
    default: throw new Error("automations: scheduler " + JSON.stringify(listed.scheduler) + " is not one of " + SCHEDULERS.join(", "));
    }
    var linger;
    switch (listed.linger) {
    case "yes": linger = { tone: "ok", text: "Automations run while you are logged out" }; break;
    case "no": linger = { tone: "info", text: "Automations run only while you are logged in", action: true }; break;
    // An unanswered check offers no action, so its Setup step reads Not
    // available, its hint saying what changes that.
    case "unknown": linger = { tone: "info", text: "Could not check whether automations run while logged out", available: false, hint: "VGS checks again when an automation runs or changes" }; break;
    default: throw new Error("automations: linger " + JSON.stringify(listed.linger) + " is not one of " + LINGER_STATES.join(", "));
    }
    return {
        scheduler: scheduler,
        linger: linger,
        active: rows.filter(function (r) { return r.enabled && (r.state === "scheduled" || r.state === "waiting" || r.state === "running"); }).length,
        nextRun: next === null ? "None scheduled" : formatWhen(next),
        lastRuns: failing.length === 0 ? { tone: "ok", text: rows.length === 0 ? "No automations" : "No failures" }
            : { tone: "danger", text: ("Failing: " + failing.join(", ")).slice(0, 200) }
    };
}

// How long the service waits before it lists again with no run file to
// wake it: until a second after the earliest next run, since a trigger the
// guard skips writes no record, and at most a day. `listed` is `list
// --json`'s document.
var REFRESH_MAX_MS = DAY_MS;
var PENDING_REFRESH_MS = NETWORK_POLL_SECONDS * 1000;
function refreshDelay(listed, nowMs) {
    var next = null;
    for (var i = 0; i < listed.automations.length; i++) {
        if (listed.automations[i].pending !== null && listed.automations[i].pending !== undefined)
            return PENDING_REFRESH_MS;
        var at = listed.automations[i].nextRun;
        if (at !== null && (next === null || at < next)) next = at;
    }
    if (next === null) return REFRESH_MAX_MS;
    return Math.max(1000, Math.min(REFRESH_MAX_MS, next - nowMs + 1000));
}

// The engine operations the service runs, in the order the Engine status
// names a failure.
var ENGINE_OPERATIONS = ["sync", "list", "prune"];

// `failures` with OPERATION's last outcome: its failure line, or "" for a
// success, which clears that operation's failure alone. A list that
// succeeds after a failed sync therefore leaves the sync failure shown.
function withOutcome(failures, operation, failure) {
    if (ENGINE_OPERATIONS.indexOf(operation) === -1) throw new Error("automations: operation " + JSON.stringify(operation) + " is not one of " + ENGINE_OPERATIONS.join(", "));
    var next = withKeys(failures, {});
    if (failure === "") delete next[operation];
    else next[operation] = String(failure).slice(0, 200);
    return next;
}

// The Engine status value: the first operation's failure, else ok.
function engineProblem(failures) {
    for (var i = 0; i < ENGINE_OPERATIONS.length; i++)
        if (hasOwn(failures, ENGINE_OPERATIONS[i])) return { tone: "danger", text: failureText(failures[ENGINE_OPERATIONS[i]]) };
    return { tone: "ok", text: "None" };
}

// The keys of `values` whose value differs from `reported`, the status
// writes a publish makes.
function changedKeys(reported, values) {
    var out = [];
    var keys = Object.keys(values);
    for (var i = 0; i < keys.length; i++)
        if (!hasOwn(reported, keys[i]) || JSON.stringify(reported[keys[i]]) !== JSON.stringify(values[keys[i]])) out.push(keys[i]);
    return out;
}
