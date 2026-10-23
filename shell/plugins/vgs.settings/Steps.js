.pragma library

// PluginLogic.statusPlacement places each status entry, which the manager
// row carries as `placement`; this page judge orders and draws the entries
// and owns required readiness. The manifest judge validates every
// reference before these manager rows reach the page.
function requirementApplies(requirement) { return requirement.state !== "present"; }
// Whether ENTRY, a manager status row, is a Setup step, required or
// optional.
function declaresStep(entry) { return entry.placement === "setup"; }
// Whether ENTRY, a step, waits on the user: unreported, or published as
// not done by a value that does not say the user cannot act on it
// (`available: false`, PluginLogic.statusDeclarationFits).
function stepOpen(entry) { return entry.report !== "reported" || (entry.tone !== "success" && entry.value.available !== false); }
// What step ENTRY reads for PLUGIN, { enabled, failed }, `failed` true
// while it could not start (startFailed): "done"; "unavailable" while the
// user cannot act on it, because its value says so or because the plugin,
// on, could not start, which turning it off and on does not change: a
// failed build stays failed per source revision (Plugins.failedBuilds),
// and a refusal lasts while another plugin holds what it needs; else
// "optional" for an optional step, which never waits on the user, and
// "todo" for a required one. PLUGIN is omitted where no start error
// applies.
function stepReading(entry, plugin) {
    if (entry.report === "reported" && entry.tone === "success") return "done";
    if (entry.report !== "reported" && plugin !== undefined && plugin.enabled && plugin.failed) return "unavailable";
    if (!stepOpen(entry)) return "unavailable";
    return entry.setup === "optional" ? "optional" : "todo";
}
// Where step ENTRY stands on Setup for PLUGIN (stepReading): the required
// steps the user can act on, then the required ones they cannot, then
// every optional step that is not done, whether it reads Optional or Not
// available, then every Done step (docs/architecture/design-system.md §
// Settings pages).
var STEP_RANKS = { todo: 0, unavailable: 1, optional: 2, done: 3 };
function stepRank(entry, plugin) {
    var reading = stepReading(entry, plugin);
    return reading !== "done" && entry.setup === "optional" ? STEP_RANKS.optional : STEP_RANKS[reading];
}
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
var STEP_CHIPS = { todo: { text: "To do", tone: "warning" }, done: { text: "Done", tone: "success" }, unavailable: { text: "Not available", tone: "neutral" },
    optional: { text: "Optional", tone: "neutral" } };
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
// The status rows Details draws as readings, by the one placement
// PluginLogic.statusPlacement gives each row.
function detailEntries(status) {
    return status.filter(function (entry) { return entry.placement === "details"; });
}
// The `rows` entries of STATUS a tab draws as sections of their own, in
// manifest order: those the manifest places on Settings while SETTINGS,
// else the Details ones.
function rowsEntries(status, settings) {
    return status.filter(function (entry) { return entry.placement === "rows" && entry.settings === settings; });
}
function detailRequirements(requirements) { return requirements.filter(function (entry) { return entry.optional; }); }
// The action that opens the plugin's notice for every missing or outdated
// tool, the one install action of Setup's Tools and Optional tools steps.
var REVIEW_LABEL = "Review all missing or outdated tools";
function reviewButton() { return { kind: "tools", key: "tools", name: "", label: REVIEW_LABEL, tone: "", icon: "", enabled: true, reason: "" }; }
// REQUIREMENTS by title, each that is missing or outdated marked so.
function toolsText(requirements) {
    return requirements.map(function (row) { return row.title + (row.state === "outdated" ? " (outdated)" : row.state === "missing" ? " (missing)" : ""); }).join(", ");
}
// The required tools of REQUIREMENTS that are missing or outdated.
function requiredLacking(requirements) {
    return requirements.filter(function (row) { return !row.optional && requirementApplies(row); });
}
// The one step of REQUIREMENTS' required tools, Tools, while OPTIONAL is
// false, else of their optional tools, Optional tools: { done, optional,
// label, text, tone, hint, button }, Done while every one is present and
// current, else To do, or Optional for the optional tools, naming the
// missing or outdated ones and offering Review. Null while the plugin
// declares no such tool.
function toolsStep(requirements, optional) {
    var rows = requirements.filter(function (row) { return row.optional === optional; });
    if (rows.length === 0) return null;
    var lacking = rows.filter(requirementApplies);
    var chip = STEP_CHIPS[lacking.length === 0 ? "done" : optional ? "optional" : "todo"];
    return { done: lacking.length === 0, optional: optional, label: toolsLabel(optional), text: chip.text, tone: chip.tone,
        hint: lacking.length === 0 ? (optional ? "Every optional tool is installed" : "Every required tool is installed") : toolsText(lacking),
        button: lacking.length === 0 ? null : reviewButton() };
}
function toolsLabel(optional) { return optional ? "Optional tools" : "Tools"; }
// The command the core reads and stores a plugin's keys with
// (PluginLogic.secretRequest).
var KEY_TOOL = "secret-tool";
// The label of the Setup step that installs KEY_TOOL while REQUIREMENTS,
// the plugin's, read it missing (toolsStep), else "" while it is present
// or the plugin declares none.
function keyToolStep(requirements) {
    var tool = requirements.find(function (row) { return row.name === KEY_TOOL && row.state === "missing"; });
    return tool === undefined ? "" : toolsLabel(tool.optional);
}
// The Setup section of a plugin's STATUS rows and REQUIREMENTS for
// PLUGIN, { enabled, failed }: its steps by stepRank, each in manifest
// order with its key lists, and the Tools and Optional tools steps, each
// before the first step that ranks after it, else last. REQUIREMENTS and PLUGIN are
// omitted where neither applies.
function setupSections(tuis, status, requirements, plugin) {
    var required = requirements === undefined ? [] : requirements;
    var rank = function (entry) { return stepRank(entry, plugin); };
    var ordered = status.filter(declaresStep).map(function (entry, index) { return { entry: entry, index: index }; })
        .sort(function (a, b) { return rank(a.entry) - rank(b.entry) || a.index - b.index; })
        .map(function (step) { return step.entry; });
    var items = [];
    ordered.forEach(function (entry) {
        items.push({ key: entry.key, slot: entry.key + ":" + rank(entry), keys: false, entry: entry,
            label: entry.label, step: true, button: stepButton(entry, required), aside: asideButton(entry) });
        status.filter(function (keyList) { return keyList.placement === "step" && keyList.step === entry.key; }).forEach(function (keyList) {
            items.push({ key: keyList.key, slot: keyList.key, keys: true, entry: keyList, label: keyList.label, step: false, button: null, aside: null });
        });
    });
    [toolsStep(required, false), toolsStep(required, true)].forEach(function (tools) {
        if (tools === null) return;
        var toolEntry = { key: tools.optional ? "optional-tools" : "required-tools", label: tools.label, type: "state", setup: tools.optional ? "optional" : "required",
            report: "reported", tone: tools.tone, value: { text: "" }, hint: tools.hint, info: "", link: null, action: null, aside: null };
        var toolItem = { key: toolEntry.key, slot: toolEntry.key + ":" + tools.done, keys: false, tools: true, entry: toolEntry,
            label: tools.label, step: true, button: tools.button, aside: null };
        var after = items.findIndex(function (item) { return !item.keys && rank(item.entry) > rank(toolEntry); });
        if (after !== -1) items.splice(after, 0, toolItem);
        else items.push(toolItem);
    });
    return items.length === 0 ? [] : [{ title: "Setup", items: items, buttons: [] }];
}
// Whether a plugin, on while ENABLED, needs setup, the one reading of the
// Plugins list's Setup needed and the Setup tab's mark: a required step of
// STATUS reads To do, or a required tool of REQUIREMENTS is missing or
// outdated. FAILED, startFailed of the plugin's errors, is true while it
// could not start. A step that reads Not available, by its value or while
// the plugin could not start, and an optional step raise neither
// (stepReading).
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
// missing or outdated tool blocks, required or optional, offers Review all
// missing or outdated tools, the one install action, while one of
// REQUIREMENTS, the plugin's, is, and none once every one is present: the
// value names no tool, and its writer names `tools` only while a tool the
// step waits on is lacking. Only a Setup step carries that value, so a
// Details or rows line reads no REQUIREMENTS. Null while none is offered.
function stepButton(entry, requirements) {
    if (entry.type === "state" && entry.report === "reported" && entry.value.action === "tools")
        return requirements.some(requirementApplies) ? reviewButton() : null;
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
// The action a Details or rows line draws for PLUGIN, { enabled, name }:
// BUTTON, the one its entry offers, while the plugin is on; while it is
// off, Turn on for a line that holds work (OPEN), a Details fact or a list
// that declares an action, else none, since the page reads the plugin's
// settings alone while it is off.
function lineAction(button, open, plugin) {
    if (!plugin.enabled) return open ? turnOn(plugin.name) : null;
    return button;
}
// The action Setup step ENTRY draws for PLUGIN, { enabled }, with
// REQUIREMENTS, the plugin's: its own (stepButton) while the plugin is on,
// else none, since the tab's one Turn on notice stands for every step
// (docs/architecture/design-system.md § Settings pages).
function stepAction(entry, requirements, plugin) {
    return plugin.enabled ? stepButton(entry, requirements) : null;
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
// people. An entry the plugin has not published reads "Not reported", save
// one that offers a core system step (`systemStep`) while PLUGIN, { enabled,
// failed }, is on and started: the plugin publishes it once the core's
// first probe ends, so it reads that it is checking. Any other
// unpublished entry, or any without PLUGIN, reads "Not reported": a plugin
// may leave such an entry unpublished for good, so the page cannot tell
// its first publish apart from none.
function statusView(entry, timeText, plugin) {
    if (entry === null) return { label: "", hint: "", info: "", link: null, tone: "", text: "", lines: [], muted: true, items: [] };
    var checking = entry.report !== "reported" && entry.systemStep && plugin !== undefined && plugin.enabled && !plugin.failed;
    var out = { label: entry.label, hint: entry.hint, info: entry.info, link: entry.link, tone: "", text: checking ? CHECKING_LINE : "Not reported", lines: [], muted: true, items: [] };
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

// What a stored key reads as beside its masked field on Settings, plain
// text that says what the key store holds and never that the key works,
// and the sentence under it, after the key's hint (hintOf), for a
// presence that has one, of what the user can do, for PLUGIN,
// { id, name, keyTool }, `keyTool` its
// keyToolStep. An unavailable key names the missing KEY_TOOL and links the
// step that installs it, since turning the plugin off and on reads the
// keys no better while it is missing. An absent key reads nothing: its Add
// key says it.
var KEY_WORDS = { present: "Saved", absent: "", locked: "Keyring locked", unavailable: "Keyring unavailable", unsafe: "Saved key is not private", "signed-out": "Signed out" };
function keyNote(value, plugin) {
    if (value === "locked") return "Saving may ask you to unlock your keyring";
    if (value === "unavailable" && plugin.keyTool !== "") return "Install " + KEY_TOOL + " from [" + plugin.keyTool + "](page:" + plugin.id + "/Setup) to read this key";
    if (value === "unavailable") return "Restore the keyring, then turn " + plugin.name + " off and on to read its keys again";
    return "";
}
// One hint of PARTS, what a line reads under its value, by the copy rule
// (docs/architecture/design-system.md § Copy): a part alone reads as
// written, a declared hint the manifest judge holds to that rule or one
// sentence of the page's own, which ends with no full stop; of two or
// more, each part that ends with no mark of its own ends with a full stop.
function hintOf(parts) {
    var shown = parts.filter(function (part) { return part !== ""; });
    return shown.length === 1 ? shown[0] : shown.map(function (part) { return /[.?!]$/.test(part) ? part : part + "."; }).join(" ");
}
// What a line draws of ITEM's presence, one item of a presence list:
// { tone, text }, its chip, or neither for a secret nothing is stored for,
// whose line offers Add key in the chip's place. On Setup, a key that is
// not done reads To do with its presence as the reason before its hint,
// save an absent one, whose To do and Add key already say it.
function itemView(item, setup) {
    if (setup) {
        var done = item.value === "present";
        var reason = done || item.value === "absent" ? "" : PRESENCE_WORDS[item.value];
        var chip = STEP_CHIPS[done ? "done" : "todo"];
        return { tone: chip.tone, text: chip.text, reason: reason };
    }
    if (item.access === "connect" && item.value === "absent") return { tone: "", text: "" };
    return { tone: item.tone, text: PRESENCE_WORDS[item.value] };
}

// What a stored key beside its Settings field draws of ITEM's presence,
// with no chip (docs/architecture/design-system.md § Settings pages):
// { tone, text, reason, danger, note }, KEY_WORDS as plain text, `danger`
// for a key another user can read, and `note`, keyNote's sentence for
// PLUGIN; `tone` and `reason` are "" as itemView's shape has them.
function keyView(item, plugin) {
    return { tone: "", text: KEY_WORDS[item.value], reason: "", danger: item.value === "unsafe", note: keyNote(item.value, plugin) };
}

// What a key's line reads in its value's place while its own write runs,
// by the write's verb.
var WRITE_WORDS = { store: "Saving\u2026", clear: "Removing\u2026" };

// What a stored key list beside its Settings field draws of ENTRY, a
// `presenceList` row of PluginLogic.statusRows, for PLUGIN, { enabled,
// name, error, failed }: { items, note }. The list draws no head of its
// own there, since its field's label names what the keys are for: ITEMS,
// its published items keyed (itemsKeyed), each line with its own label,
// and NOTE, the one sentence the list reads in their place while it has
// none, attached under the field: while the plugin is off, that turning it
// on lists them; while it could not start, why; while it is starting, that
// it is finding them; and once it lists none, the entry's hint, which says
// how keys come to be listed, or "None detected" for an entry without one.
// An item without a hint or an info of its own reads the entry's, which
// explain each key of a list whose head is not drawn. No published item is
// drawn while the plugin is off.
function keyListView(entry, plugin) {
    if (!plugin.enabled) return { items: [], note: "Turn on " + plugin.name + " to load " + entry.label };
    if (entry.report !== "reported") return { items: [], note: plugin.failed ? plugin.error : "Finding " + entry.label + "\u2026" };
    if (entry.value.length === 0) return { items: [], note: entry.hint !== "" ? entry.hint : "None detected" };
    return { items: itemsKeyed(entry.value).map(function (item) {
        return Object.assign({}, item, { hint: item.hint !== "" ? item.hint : entry.hint, info: item.info !== "" ? item.info : entry.info });
    }), note: "" };
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
