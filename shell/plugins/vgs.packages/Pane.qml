import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// The shared package choices live with Config; Updates keeps its own
// update settings. Both views draw that same manifest through SettingField
// and write through the manager, including choice handlers such as restart
// notices. Mounting this pane starts no check, review or package operation.
FocusScope {
    id: root
    objectName: "packagesPage"

    property var shell: null
    readonly property var updateRow: shell === null ? null : shell.manager.plugins.find(row => row.id === "vgs.updates") || null
    readonly property var review: shell === null ? ({}) : shell.manager.packageReview
    readonly property var agentChoices: {
        const choices = [{ value: "", label: "Automatic" }].concat(shell === null ? [] : shell.manager.packageReviewAgents);
        const saved = review.agent || "";
        if (!choices.some(choice => choice.value === saved)) choices.push({ value: saved, label: saved + " (unavailable)" });
        return choices;
    }
    readonly property var updateFields: updateRow === null ? [] : updateRow.fieldRows.filter(field => !field.list
        && updateRow.withheldFields.indexOf(field.key) === -1
        && !(updateRow.schema[field.key].hideEmpty === true && (updateRow.settingChoices[field.key] || []).length === 0))
    readonly property var editors: [commandField].concat(updates.parent === null ? []
        : updates.parent.children.filter(child => child instanceof SettingField))
    readonly property bool dirty: editors.some(field => field.edited)
    property string problem: ""
    readonly property Item initialFocus: updateToggle.visible ? updateToggle : beforeInstalling
    readonly property Item footer: SaveBar {
        id: saveBar
        width: parent === null ? root.width : parent.width
        dirty: root.dirty
        onSave: {
            for (const field of root.editors) field.save();
            if (!root.dirty) confirm();
        }
        onDiscard: {
            for (const field of root.editors) field.discard();
        }
    }

    function open(payloadJson) {}
    function close() {}

    function answered(reply) {
        problem = reply === "ok" ? "" : "Could not save this change. Try again.";
        if (reply !== "ok") console.warn("packages: save " + reply);
        return reply;
    }
    function changeUpdate(key, value) { return answered(shell.manager.setSetting("vgs.updates", key, value)); }
    function changeReview(key, value) { return answered(shell.manager.setPackageReview(key, value)); }

    implicitWidth: Theme.size.window.width
    implicitHeight: content.implicitHeight
    focus: true

    Column {
        id: content
        width: root.width
        spacing: Theme.stack.group

        Label {
            width: parent.width
            role: "hint"
            text: root.problem
            color: Theme.color.danger
            visible: text !== ""
            wrapMode: Text.Wrap
        }

        Section {
            width: parent.width
            title: "Updates"
            rowSpacing: Theme.stack.row

            Field {
                width: parent.width
                visible: root.updateRow !== null
                inline: true
                label: "Check for updates"
                hint: root.updateRow !== null && !root.updateRow.enabled ? "Turn this on to change the update options" : ""
                Switch {
                    id: updateToggle
                    size: "sm"
                    checked: root.updateRow !== null && root.updateRow.enabled
                    onToggled: {
                        const wanted = checked;
                        checked = Qt.binding(() => root.updateRow !== null && root.updateRow.enabled);
                        root.answered(root.shell.manager.setEnabled("vgs.updates", wanted));
                    }
                }
            }

            Label {
                width: parent.width
                role: "hint"
                visible: root.updateRow === null
                text: "Update options are available when the Updates plugin is installed."
                wrapMode: Text.Wrap
            }

            Repeater {
                id: updates
                // Keyed ScriptModel keeps an editor's draft while another
                // setting changes: https://quickshell.org/docs/v0.3.1/types/Quickshell/ScriptModel
                model: ScriptModel { values: root.updateFields; objectProp: "key" }
                SettingField {
                    required property var modelData
                    width: root.width
                    pluginId: "vgs.updates"
                    key: modelData.key
                    spec: root.updateRow.schema[key]
                    value: root.updateRow.settings[key]
                    groups: modelData.groups
                    choices: root.updateRow.settingChoices[key] || []
                    problem: spec.problem === undefined ? "" : root.updateRow.fieldProblems[key]
                    editable: root.updateRow.enabled
                    onApply: value => root.changeUpdate(key, value)
                    onChoicesWanted: root.answered(root.shell.manager.refreshChoices(pluginId, spec.optionsFrom))
                }
            }
        }

        Section {
            width: parent.width
            title: "Agent review"
            description: "Choose the first option VGS offers before a package installs or updates."
            rowSpacing: Theme.stack.row

            Field {
                width: parent.width
                inline: true
                label: "Before installing"
                hint: beforeInstalling.currentIndex === 0 ? "Ask an AI agent to check the package before you decide"
                    : beforeInstalling.currentIndex === 1 ? "Skip the AI check and ask you to confirm installation"
                    : "Offer a review when an AI agent is available"
                Select {
                    id: beforeInstalling
                    objectName: "packageReviewChoice"
                    width: parent.width
                    model: ["Review with an agent", "Install without review", "Automatic (review when an agent is available)"]
                    currentIndex: root.review.enabled === true ? 0 : root.review.enabled === false ? 1 : 2
                    onActivated: index => {
                        currentIndex = Qt.binding(() => root.review.enabled === true ? 0 : root.review.enabled === false ? 1 : 2);
                        root.changeReview("enabled", index === 2 ? null : index === 0);
                    }
                }
            }

            Field {
                width: parent.width
                inline: true
                label: "AI agent"
                hint: "Automatic uses the first supported agent available on this computer"
                Select {
                    id: agent
                    width: parent.width
                    model: root.agentChoices
                    textRole: "label"
                    currentIndex: root.agentChoices.findIndex(choice => choice.value === (root.review.agent || ""))
                    onActivated: index => {
                        currentIndex = Qt.binding(() => root.agentChoices.findIndex(choice => choice.value === (root.review.agent || "")));
                        root.changeReview("agent", root.agentChoices[index].value);
                    }
                }
            }

            SettingField {
                id: commandField
                width: parent.width
                key: "command"
                spec: ({ type: "string", label: "Review command", description: "Optional command to use instead of the selected AI agent", presets: [{ value: "", label: "Use the selected AI agent" }], allowCustom: true })
                value: root.review.command || ""
                onApply: value => root.changeReview("command", value)
            }
        }
    }
}
