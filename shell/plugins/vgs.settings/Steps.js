.pragma library

// One page judge owns placement and required readiness. The manifest judge
// validates every reference before these manager rows reach the page.
function requirementApplies(requirement) { return requirement.state !== "present"; }
function declaresStep(entry) { return entry.setup === true; }
function stepOpen(entry) { return entry.report !== "reported" || entry.tone !== "success"; }
function stepRank(entry) { return stepOpen(entry) ? 0 : 1; }
// What a Setup step draws of ENTRY for PLUGIN, { enabled, name, error }:
// To do or Done, and under the chip the published state's own text, or,
// while the plugin is on and has published nothing for the step, why:
// ERROR, why it was not built, or that it has not reported yet
// (waitingLine).
function stepView(entry, timeText, plugin) {
    var view = statusView(entry, timeText);
    view.text = stepOpen(entry) ? "To do" : "Done";
    view.tone = stepOpen(entry) ? "warning" : "success";
    // The published state explains the work beneath the two-state chip.
    if (entry.report === "reported" && entry.type === "state" && entry.value.text !== "" && entry.value.text !== view.text)
        view.lines = [entry.value.text].concat(view.lines);
    if (entry.report !== "reported" && plugin.enabled)
        view.lines = [plugin.error !== "" ? plugin.error : waitingLine(plugin.name)];
    return view;
}
function waitingLine(name) { return name + " has not reported this step yet"; }
function detailEntries(status) {
    return status.filter(function (entry) { return !declaresStep(entry) && entry.setting === "" && entry.step === ""; });
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
function requirementStep(requirements) {
    var required = requirements.filter(function (row) { return !row.optional; });
    if (required.length === 0) return null;
    var lacking = required.filter(requirementApplies);
    return { done: lacking.length === 0, label: "Tools", text: lacking.length === 0 ? "Done" : "To do",
        tone: lacking.length === 0 ? "success" : "warning",
        hint: lacking.length === 0 ? "Every required tool is installed" : toolsText(lacking),
        button: lacking.length === 0 ? null : reviewButton() };
}
function setupSections(tuis, status, requirements) {
    var steps = status.filter(declaresStep);
    var ordered = steps.filter(stepOpen).concat(steps.filter(function (entry) { return !stepOpen(entry); }));
    var items = [];
    ordered.forEach(function (entry) {
        items.push({ key: entry.key, slot: entry.key + ":" + stepRank(entry), keys: false, entry: entry,
            label: entry.label, step: true, button: stepButton(entry), aside: asideButton(entry) });
        status.filter(function (keyList) { return keyList.step === entry.key; }).forEach(function (keyList) {
            items.push({ key: keyList.key, slot: keyList.key, keys: true, entry: keyList, label: keyList.label, step: false, button: null, aside: null });
        });
    });
    var tools = requirementStep(requirements === undefined ? [] : requirements);
    if (tools !== null) {
        var toolEntry = { key: "required-tools", label: tools.label, type: "state", setup: true, report: "reported", tone: tools.tone,
            value: { text: "" }, hint: tools.hint, info: "", link: null, action: null, aside: null };
        var toolItem = { key: toolEntry.key, slot: toolEntry.key + ":" + tools.done, keys: false, tools: true, entry: toolEntry,
            label: tools.label, step: true, button: tools.button, aside: null };
        var firstDone = items.findIndex(function (item) { return !item.keys && !stepOpen(item.entry); });
        if (!tools.done && firstDone !== -1) items.splice(firstDone, 0, toolItem);
        else items.push(toolItem);
    }
    return items.length === 0 ? [] : [{ title: "Setup", items: items, buttons: [] }];
}
function setupNeeds(status, requirements, enabled) {
    return { open: enabled && (status.some(function (entry) { return declaresStep(entry) && stepOpen(entry); })
        || requirements.some(function (entry) { return !entry.optional && requirementApplies(entry); })) };
}
function setupTab(sections, requirements) { return sections.length > 0 || requirements.some(function (row) { return !row.optional; }); }
// The action ENTRY's line offers while the plugin is on: { kind, key,
// name, label, tone, icon, enabled, reason }, `icon` the name of the mark a
// danger action leads with, "" for the trash mark (RowAction's
// `markName`). A primary status action always
// uses the status route, including when it opens a TUI, so its refusal
// and the successful retry belong to the same entry. Null while none is
// offered.
function stepButton(entry) {
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
        return { tone: done ? "success" : "warning", text: done ? "Done" : "To do", reason: reason };
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
