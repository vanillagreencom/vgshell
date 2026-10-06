.pragma library

// The one rule for when a plugin page shows a setup step (D061), pure so
// scripts/test-settings-steps.js runs it under node: a step, its button and
// the command behind Show command, shows only while its value offers it: a
// `presence` while `absent` and a `state` while it carries `action: true`
// or names one of its entry's actions, so a failing state its writer gives
// no action shows neither (see docs/architecture/status.md
// § Actions and secrets). The core decides when a step applies
// (PluginLogic.statusActionOffered, SECRET_ACCESS, requirementRows); this
// file decides what the page then draws, so a command never sits on a line
// without the button that runs it.

// What the line of ENTRY, one row of PluginLogic.statusRows, draws of its
// step: { offered, command }, `offered` whether the action's button shows
// and `command` the entry's command while it does, else "".
function statusStep(entry) {
    var offered = entry.action !== null && entry.action.offered;
    return { offered: offered, command: offered ? entry.command : "" };
}

// The command the line of ITEM, one item of a `presenceList` row, draws:
// its own while the item's step is Connect, the step the command stands
// for, else "". Disconnect is a button alone.
function itemCommand(item) {
    return item.access === "connect" ? item.command : "";
}

// Whether the Requirements section's install step applies to REQUIREMENT,
// one row of PluginLogic.requirementRows: while its requirement is missing.
function requirementApplies(requirement) {
    return requirement.state === "missing";
}
