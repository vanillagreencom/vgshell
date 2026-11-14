import QtQuick
import qs.Commons
import qs.Ui

// The editor of one idle stage's time, from `field`, what the core lends
// for it (PluginLogic.idleSettingFields): the owner's schema entry and the
// value its configuration holds, drawn by NumberSettingField, so each page
// that draws the stage edits the one stored value. While the stage it
// starts with runs, Immediately (<time>) holds that stage's time
// (SettingValues.idleTimeSpec); the hint then says what it means and the
// info dialog that it is a snapshot. A choice asks the page to write it,
// `apply`, which writes it to the owner's setting, and a refusal the page
// shows as `problem`.
//
// `reference` marks a page other than the owner's own: there an owner
// that is off, or no owner, locks the field with the reason, and its hint
// says so, with a page reference to the owner's Settings to turn it on,
// which asks for the page through `pageActivated`. The owner's own page
// draws its own Turn on line instead.
NumberSettingField {
    id: root

    required property var field
    property bool reference: true
    readonly property var stageText: SettingValues.IDLE_STAGE_TEXT[field.stage]
    readonly property bool immediately: field.immediately > 0 && value === field.immediately
    readonly property string ownerHint: !reference || field.reason === "" ? ""
        : field.reason === "none" ? "No plugin that " + stageText.owner + " is installed"
        : "[Turn on " + field.name + "](page:" + field.plugin + "/Settings) to change this time"

    // With no owner there is no schema entry: an empty list under the
    // stage's own label, locked with the reason.
    spec: field.spec === null ? ({ type: "number", label: stageText.label, presets: [] }) : SettingValues.idleTimeSpec(field)
    value: field.value === null ? undefined : field.value
    hint: ownerHint !== "" ? ownerHint
        : immediately ? stageText.immediately
        : field.spec !== null && field.spec.description !== undefined ? String(field.spec.description) : ""
    info: field.immediately > 0 ? stageText.snapshot
        : field.spec !== null && field.spec.info !== undefined ? String(field.spec.info) : ""
    disabledReason: !reference || field.reason === "" ? ""
        : field.reason === "none" ? "No plugin that " + stageText.owner + " is installed."
        : "Turn on " + field.name + " to change this time."
}
