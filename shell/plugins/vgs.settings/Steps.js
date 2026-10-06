.pragma library

// The one rule for when a plugin page shows a setup step (D061), pure so
// scripts/test-settings-steps.js runs it under node: a step's button shows
// only while its value offers it: a `presence` while `absent` and a `state`
// while it carries `action: true` or names one of its entry's actions, so a
// failing state its writer gives no action shows none (see
// docs/architecture/status.md § Actions and secrets). The core decides when
// a step applies (PluginLogic.statusActionOffered, SECRET_ACCESS,
// requirementRows); this file decides what the page then draws.

// What the line of ENTRY, one row of PluginLogic.statusRows, draws of its
// step: { offered }, whether the action's button shows.
function statusStep(entry) {
    var offered = entry.action !== null && entry.action.offered;
    return { offered: offered };
}

// Whether the Requirements section's install step applies to REQUIREMENT,
// one row of PluginLogic.requirementRows: while its requirement is missing.
function requirementApplies(requirement) {
    return requirement.state === "missing";
}
