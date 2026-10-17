.pragma library

// One page judge owns placement and required readiness. The manifest judge
// validates every reference before these manager rows reach the page.
function requirementApplies(requirement) { return requirement.state !== "present"; }
function declaresStep(entry) { return entry.setup === true; }
// Whether ENTRY, a required step, waits on the user: unreported, or
// published as not done by a value that does not say the user cannot act
// on it (`available: false`, PluginLogic.statusDeclarationFits).
function stepOpen(entry) { return entry.report !== "reported" || (entry.tone !== "success" && entry.value.available !== false); }
// What required step ENTRY reads for PLUGIN, { enabled, failed }, `failed`
// true while it could not start (startFailed): "todo" while it waits on
// the user, "done", or "unavailable" while the user cannot act on it,
// because its value says so or because the plugin, on, could not start,
// which turning it off and on does not change: a failed build stays failed
// per source revision (Plugins.failedBuilds), and a refusal lasts while
// another plugin holds what it needs. PLUGIN is omitted where no start
// error applies.
function stepReading(entry, plugin) {
    if (entry.report === "reported" && entry.tone === "success") return "done";
    if (entry.report !== "reported" && plugin !== undefined && plugin.enabled && plugin.failed) return "unavailable";
    return stepOpen(entry) ? "todo" : "unavailable";
}
var STEP_RANKS = { todo: 0, unavailable: 1, done: 2 };
// The line that says why a plugin, on, does not run, of its manager row's
// ERRORS (Registry.managerRows): its first refusal or failed build, ""
// while neither applies.
function startError(errors) {
    return errors.find(function (line) { return line.startsWith("build failed: ") || line.startsWith("refused: "); }) || "";
}
// Whether a plugin of ERRORS could not start, the `failed` stepReading
// takes.
function startFailed(errors) { return startError(errors) !== ""; }
// The chip of each reading, its word and its tone. The words are declared
// here alone (docs/architecture/design-system.md § Settings pages).
var STEP_CHIPS = { todo: { text: "To do", tone: "warning" }, done: { text: "Done", tone: "success" }, unavailable: { text: "Not available", tone: "neutral" } };
// The line an unreported step draws while its plugin is on and starting.
var CHECKING_LINE = "Checking…";
// What a Setup step draws of ENTRY for PLUGIN, { enabled, name, error,
// failed }: its chip (stepReading), and under it the published state's own
// text, or, while the plugin is on and has published nothing for the step,
// why: ERROR, the plain line of why it was not built or could not start,
// else that it is checking. A step that reads Not available because its
// plugin could not start draws no hint: the declaration's hint, which
// PluginLogic.statusRows gives an unreported entry, names the action the
// step usually offers, and the row offers none.
function stepView(entry, timeText, plugin) {
    var view = statusView(entry, timeText);
    var reading = stepReading(entry, plugin);
    var chip = STEP_CHIPS[reading];
    view.text = chip.text;
    view.tone = chip.tone;
    // The published state explains the work beneath the chip.
    if (entry.report === "reported" && entry.type === "state" && entry.value.text !== "" && entry.value.text !== view.text)
        view.lines = [entry.value.text].concat(view.lines);
    if (entry.report !== "reported" && plugin.enabled)
        view.lines = [plugin.error !== "" ? plugin.error : CHECKING_LINE];
    if (entry.report !== "reported" && reading === "unavailable") {
        view.hint = "";
        view.link = null;
    }
    return view;
}
function detailEntries(status) {
    return status.filter(function (entry) { return !declaresStep(entry) && entry.setting === "" && entry.step === "" && entry.type !== "rows"; });
}
// The `rows` entries of STATUS a tab draws as sections of their own, in
// manifest order: those the manifest places on Settings while SETTINGS,
// else the Details ones.
function rowsEntries(status, settings) {
    return status.filter(function (entry) { return entry.type === "rows" && entry.settings === settings; });
}
function detailRequirements(requirements) { return requirements.filter(function (entry) { return entry.optional; }); }
// The action that opens the plugin's notice for every missing or outdated
// tool, the one install action of Setup's Tools step and of Details' Tools
// section.
var REVIEW_LABEL = "Review all missing or outdated tools";
function reviewButton() { return { kind: "tools", key: "tools", name: "", label: REVIEW_LABEL, tone: "", icon: "", enabled: true, reason: "" }; }
// The Review action Details' Tools section offers for REQUIREMENTS, its
// optional tools, while one is missing or outdated, else null.
function toolsReview(requirements) { return requirements.some(requirementApplies) ? reviewButton() : null; }
// REQUIREMENTS by title, each that is missing or outdated marked so.
function toolsText(requirements) {
    return requirements.map(function (row) { return row.title + (row.state === "outdated" ? " (outdated)" : row.state === "missing" ? " (missing)" : ""); }).join(", ");
}
// The required tools of REQUIREMENTS that are missing or outdated.
function requiredLacking(requirements) {
    return requirements.filter(function (row) { return !row.optional && requirementApplies(row); });
}
function requirementStep(requirements) {
    var required = requirements.filter(function (row) { return !row.optional; });
    if (required.length === 0) return null;
    var lacking = requiredLacking(required);
    var chip = STEP_CHIPS[lacking.length === 0 ? "done" : "todo"];
    return { done: lacking.length === 0, label: "Tools", text: chip.text, tone: chip.tone,
        hint: lacking.length === 0 ? "Every required tool is installed" : toolsText(lacking),
        button: lacking.length === 0 ? null : reviewButton() };
}
// The Setup section of a plugin's STATUS rows and REQUIREMENTS for
// PLUGIN, { enabled, failed }: its required steps, To do, then Not
// available, then Done (stepReading), each in manifest order with its key
// lists, and the one Tools step, To do before the first step that is not,
// else last. REQUIREMENTS and PLUGIN are omitted where neither applies.
function setupSections(tuis, status, requirements, plugin) {
    var required = requirements === undefined ? [] : requirements;
    var rank = function (entry) { return STEP_RANKS[stepReading(entry, plugin)]; };
    var ordered = status.filter(declaresStep).map(function (entry, index) { return { entry: entry, index: index }; })
        .sort(function (a, b) { return rank(a.entry) - rank(b.entry) || a.index - b.index; })
        .map(function (step) { return step.entry; });
    var items = [];
    ordered.forEach(function (entry) {
        items.push({ key: entry.key, slot: entry.key + ":" + rank(entry), keys: false, entry: entry,
            label: entry.label, step: true, button: stepButton(entry, required), aside: asideButton(entry) });
        status.filter(function (keyList) { return keyList.step === entry.key; }).forEach(function (keyList) {
            items.push({ key: keyList.key, slot: keyList.key, keys: true, entry: keyList, label: keyList.label, step: false, button: null, aside: null });
        });
    });
    var tools = requirementStep(required);
    if (tools !== null) {
        var toolEntry = { key: "required-tools", label: tools.label, type: "state", setup: true, report: "reported", tone: tools.tone,
            value: { text: "" }, hint: tools.hint, info: "", link: null, action: null, aside: null };
        var toolItem = { key: toolEntry.key, slot: toolEntry.key + ":" + tools.done, keys: false, tools: true, entry: toolEntry,
            label: tools.label, step: true, button: tools.button, aside: null };
        var firstDone = items.findIndex(function (item) { return !item.keys && rank(item.entry) !== STEP_RANKS.todo; });
        if (!tools.done && firstDone !== -1) items.splice(firstDone, 0, toolItem);
        else items.push(toolItem);
    }
    return items.length === 0 ? [] : [{ title: "Setup", items: items, buttons: [] }];
}
// Whether a plugin, on while ENABLED, needs setup, the one reading of the
// Plugins list's Setup needed and the Setup tab's mark: a required step of
// STATUS reads To do, or a required tool of REQUIREMENTS is missing or
// outdated. FAILED, startFailed of the plugin's errors, is true while it
// could not start. A step that reads Not available, by its value or while
// the plugin could not start, raises neither (stepReading).
function setupNeeds(status, requirements, enabled, failed) {
    var plugin = { enabled: enabled, failed: failed === true };
    return { open: enabled && (status.some(function (entry) { return declaresStep(entry) && stepReading(entry, plugin) === "todo"; })
        || requiredLacking(requirements).length > 0) };
}
function setupTab(sections, requirements) { return sections.length > 0 || requirements.some(function (row) { return !row.optional; }); }
// The action ENTRY's line offers while the plugin is on: { kind, key,
// name, label, tone, icon, enabled, reason }, `icon` the name of the mark a
// danger action leads with, "" for the trash mark (RowAction's
// `markName`). A primary status action always
// uses the status route, including when it opens a TUI, so its refusal
// and the successful retry belong to the same entry. A step whose value
// names `action: "tools"` (PluginLogic.STATUS_TOOLS_ACTION), which a
// missing or outdated required tool blocks, offers Review all missing or
// outdated tools, the one install action, while one of REQUIREMENTS, the
// plugin's, is, and none once every one is present. Only a Setup step
// carries that value, so a Details or rows line reads no REQUIREMENTS.
// Null while none is offered.
function stepButton(entry, requirements) {
    if (entry.type === "state" && entry.report === "reported" && entry.value.action === "tools")
        return requiredLacking(requirements).length > 0 ? reviewButton() : null;
    if (entry.action === null || !entry.action.offered) return null;
    return { kind: "status", key: entry.key + " " + entry.action.label, name: entry.action.tui,
        label: entry.action.label, tone: entry.action.tone, icon: entry.action.icon, enabled: true, reason: "" };
}
function asideButton(entry) {
    if (entry.aside === null || !entry.aside.offered) return null;
    return { kind: "tui", key: entry.key + " " + entry.aside.label, name: entry.aside.tui, label: entry.aside.label, tone: entry.aside.tone, icon: entry.aside.icon, enabled: true, reason: "" };
}
// The one action a page offers for a plugin that is off, which turns it on
// through the Enabled switch's route, and why its screens take no press.
function turnOn(name) { return { kind: "enable", key: "enable", name: "", label: "Turn on " + name, tone: "", icon: "", enabled: true, reason: "" }; }
function offReason(name) { return "Turn on " + name + " first"; }
// The action a line draws for PLUGIN, { enabled, name }: BUTTON, the one
// its entry offers, while the plugin is on; while it is off, Turn on for a
// line that holds work (OPEN), a To do step or a Details fact that
// declares an action, else none, since the page reads the plugin's
// settings alone while it is off.
function lineAction(button, open, plugin) {
    if (!plugin.enabled) return open ? turnOn(plugin.name) : null;
    return button;
}
// The listed screens TUIS that NAMES holds, as buttons: disabled while
// PLUGIN is off, with the reason.
function screenButtons(tuis, names, plugin) {
    return tuis.filter(function (tui) { return names.indexOf(tui.name) !== -1; }).map(function (tui) {
        return { kind: "tui", key: tui.name + " " + tui.label + " " + plugin.enabled, name: tui.name, label: tui.label, tone: "", icon: "", enabled: plugin.enabled, reason: plugin.enabled ? "" : offReason(plugin.name) };
    });
}
// The listed screens a page draws apart from its status entries: PLACE
// "Settings", a configuration screen's More settings link, or "Details", a
// task, each one no status entry declares.
function freeScreens(tuis, status, place, plugin) {
    var declared = [];
    status.forEach(function (entry) { declared = declared.concat(entry.declaredTuis); });
    return screenButtons(tuis, tuis.filter(function (tui) {
        return declared.indexOf(tui.name) === -1 && (place === "Settings" ? tui.settings : !tui.settings);
    }).map(function (tui) { return tui.name; }), plugin);
}
// Why BUTTONS take no press, "" while they do: they all take none while
// their plugin is off, for one reason (screenButtons).
function withheldHint(buttons) {
    var held = buttons.filter(function (button) { return !button.enabled; });
    return held.length === 0 ? "" : held[0].reason;
}

// What a Settings page draws for FIELD, one row of the manager row's
// `fieldRows` (PluginLogic.fieldRows), from ROW, that manager row: the lines
// under the field's control, each { slot, kind, key }, a `keys` line for
// each stored key list beside the field whose entry ROW still holds. A
// Settings row holds only values the user changes, and a masked key field
// is one (docs/architecture/design-system.md § Settings pages).
function featureRow(field, row) {
    var lines = [];
    field.keyLists.forEach(function (key) {
        if (row.status.some(function (entry) { return entry.key === key; })) lines.push({ slot: "keys " + key, kind: "keys", key: key });
    });
    return lines;
}

// What a Details line of ENTRY offers for PLUGIN, an optional feature's
// own action beside its fact: { action, aside }, ACTION the action ENTRY
// offers while the plugin is on and Turn on while it is off, for an entry
// that declares one (lineAction), and ASIDE its aside while the plugin is
// on.
function detailButtons(entry, plugin) {
    return { action: lineAction(stepButton(entry), entry.action !== null, plugin), aside: plugin.enabled ? asideButton(entry) : null };
}

// The words a `presence` value reads as on the page.
var PRESENCE_WORDS = { present: "Present", absent: "Absent", locked: "Locked", unavailable: "Unavailable", unsafe: "Unsafe", "signed-out": "Signed out" };

// What a page draws of ENTRY, a `rows` entry of PluginLogic.statusRows, for
// PLUGIN, { enabled, name }: { rows, add, text }. ROWS are its published
// rows, each with the `key` its line keeps across writes, its id, and its
// `buttons`, one per row action it offers, as a line action { kind, key,
// name, row, label, text, tone, icon, removesItem }: KIND `row`, ROW the
// row's id, TEXT the words a RowAction draws, its label, and
// REMOVES_ITEM for a danger action with no mark of its own, which removes
// the row it stands on and so draws the trash mark alone, its TEXT its
// label and the row's, as its tooltip and accessible name name the row.
// ADD is the line action under the list (lineAction): while the plugin is
// on, the entry's action on the whole list, such as Add, once the list is
// reported; while it is off, Turn on for a Details list the user changes
// through an action, since the core keeps no list of a plugin that is off.
// A Settings list offers none: the tab's Enabled switch and its hint are
// the one Turn on there, as every other Settings row of a plugin that is
// off adds none of its own. TEXT is
// "<name> is off" while the plugin is off, "Not reported" while the list
// is not reported, "None yet" while it is empty, else "".
function rowsView(entry, plugin) {
    var add = lineAction(stepButton(entry), !entry.settings && (entry.action !== null || entry.declaredTuis.length > 0), plugin);
    if (!plugin.enabled) return { rows: [], add: add, text: plugin.name + " is off" };
    if (entry.report !== "reported") return { rows: [], add: add, text: "Not reported" };
    return {
        rows: entry.value.map(function (row) {
            return Object.assign({ key: row.id, buttons: row.actions.map(function (action) {
                var removes = action.tone === "danger" && action.icon === "";
                return { kind: "row", key: entry.key + " " + row.id + " " + action.name, name: action.name, row: row.id, label: action.label,
                    text: removes ? action.label + " " + row.label : action.label, tone: action.tone, icon: action.icon, removesItem: removes };
            }) }, row);
        }),
        add: add,
        text: entry.value.length === 0 ? "None yet" : ""
    };
}

// What a page draws of ENTRY, one row of PluginLogic.statusRows, or null
// for a row whose entry left the manager row: { label, hint, info, link,
// tone, text, lines, muted, items }, `link` the words of the hint that
// open an address, { text, url } or null, `tone` "" for a value drawn as
// text, `lines` a state's
// further lines and `items` a presence list's items with the `key` each
// keeps across writes (itemsKeyed). TIME_TEXT spells a `time` value for
// people. An entry the plugin has not published reads "Not reported".
function statusView(entry, timeText) {
    if (entry === null) return { label: "", hint: "", info: "", link: null, tone: "", text: "", lines: [], muted: true, items: [] };
    var out = { label: entry.label, hint: entry.hint, info: entry.info, link: entry.link, tone: "", text: "Not reported", lines: [], muted: true, items: [] };
    if (entry.report !== "reported") return out;
    out.muted = false;
    out.tone = entry.tone;
    switch (entry.type) {
    case "presence": out.text = PRESENCE_WORDS[entry.value]; return out;
    case "presenceList":
        out.items = itemsKeyed(entry.value);
        out.text = entry.value.length === 0 ? "None detected" : "";
        out.muted = true;
        return out;
    case "state":
        out.text = entry.value.text;
        if (entry.value.lines !== undefined) out.lines = entry.value.lines;
        return out;
    case "text": out.text = entry.value; return out;
    case "count": out.text = String(entry.value); return out;
    case "time": out.text = timeText(entry.value); return out;
    }
    console.error("Steps: no rule for status type " + JSON.stringify(entry.type));
    out.text = "";
    return out;
}

// What a line draws of ITEM's presence, one item of a presence list:
// { tone, text }, its chip, or neither for a secret nothing is stored for,
// whose line offers Add key in the chip's place.
function itemView(item, setup) {
    if (setup) {
        var done = item.value === "present";
        var reason = done ? "" : PRESENCE_WORDS[item.value];
        var chip = STEP_CHIPS[done ? "done" : "todo"];
        return { tone: chip.tone, text: chip.text, reason: reason };
    }
    if (item.access === "connect" && item.value === "absent") return { tone: "", text: "" };
    return { tone: item.tone, text: PRESENCE_WORDS[item.value] };
}

// ITEMS, a presence list's, each with the `key` a line keeps across
// writes, so a status write elsewhere, which hands the page new objects,
// keeps each line's delegate, an open masked field and what it holds with
// it: its secret's account, else its label, with its count among earlier
// equal names after a second one.
function itemsKeyed(items) {
    var seen = Object.create(null);
    return items.map(function (item) {
        var name = item.secret !== "" ? "secret " + item.secret : "label " + item.label;
        seen[name] = (seen[name] || 0) + 1;
        return Object.assign({ key: seen[name] === 1 ? name : name + " " + seen[name] }, item);
    });
}
