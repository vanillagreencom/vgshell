import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "DisplaysLogic.js" as Logic

// System → Displays: one row per display with its brightness or what keeps
// it from being ready; under a display the helper could not place, or one
// placed by the user's choice, the screen it shows on, picked from the
// outputs Hyprland reads, and Identify, which shows each screen's name and
// flashes that display; Link displays; Dimming; the saved
// choices whose display or screen is gone, each with Forget; and, while a
// step is needed, the access entries that need one (`accessNeeded`), each
// as one line with its action while offered. The holder draws the title,
// the inset and the scrolling. It draws the status the service publishes
// and asks the service, or the core through `status.act`, for every
// change; it runs nothing itself. Each access entry's tone and offered
// action come from the core's status rows (`status.rows`). Tab starts on
// the arrangement canvas and then moves through the controls in reading
// order; the arrows move the canvas selection, a slider and a closed
// Select.
FocusScope {
    id: root

    property var shell: null
    readonly property var values: shell === null ? ({}) : shell.status.values
    readonly property var list: values.displays === undefined ? ({ state: "pending", items: [] }) : values.displays
    readonly property var assignments: values.assignments === undefined ? ({ entries: [], error: null }) : values.assignments
    readonly property var stale: assignments.entries.filter(e => e.state === "stale")
    readonly property var outputs: shell === null || shell.monitors.outputs === null ? [] : shell.monitors.outputs
    readonly property var outputRules: shell === null ? ({}) : (shell.settings.outputs || ({}))
    property var outputDraft: ({})
    property string selectedOutput: outputs.length > 0 ? outputs[0].identifier : ""
    readonly property var selected: Logic.outputByIdentifier(outputs, selectedOutput)
    readonly property var selectedRule: selected === null ? null : Logic.effectiveRule(selected, outputRules[selected.name] || outputRules[selectedOutput], outputDraft[selected.name] || outputDraft[selectedOutput])
    readonly property bool selectedOn: selectedRule !== null && selectedRule.disabled !== true
    readonly property bool selectedMirrors: selectedRule !== null && selectedRule.mirror !== undefined
    // Why the selected display may not be turned off, Logic.offBlock's key.
    readonly property string offBlock: selected === null ? "" : Logic.offBlock(outputs, outputRules, outputDraft, selectedOutput)
    readonly property var mirrorChoices: selected === null ? [] : Logic.mirrorChoices(outputs, outputRules, outputDraft, selectedOutput)
    readonly property var displayChoices: Logic.outputChoices(outputs)
    readonly property bool outputDirty: Object.keys(Logic.dirtyRules(outputDraft, outputRules)).length > 0
    readonly property var trialState: shell === null ? ({ phase: "idle", token: "", deadline: 0, failure: "" }) : shell.monitors.trialState
    readonly property bool trialHolding: trialState.phase === "holding" || trialState.phase === "keeping"
    property int nowSeconds: Math.floor(Date.now() / 1000)
    readonly property var screenChoices: Logic.screenChoices(list.items, outputs)
    // The access entries that need a step, as the core's status rows give
    // them.
    readonly property var accessRows: shell === null ? [] : shell.status.rows.filter(r => r.group === "Access" && r.report === "reported" && Logic.accessNeeded(r.value))
    // The refusal the last step was answered with, "" for none.
    property string problem: ""
    // The refusal the last Dimming write was answered with, "" for none.
    property string dimProblem: ""
    readonly property Item initialFocus: arrangement

    function open(payloadJson) {
        problem = "";
        dimProblem = "";
    }
    function close() {}

    function answered(reply) {
        problem = Logic.replyText(reply);
        if (reply !== "ok") console.warn("displays pane: " + reply);
        return reply;
    }

    // Put DEVICE on the output OUTPUT names, "" to forget its choice;
    // answers the service's reply.
    function assign(device, output) { return answered(shell.ipc.call("assign", JSON.stringify({ device: device, output: output }))); }
    function identify(id) { return answered(shell.ipc.call("identify", id)); }
    function identifyAll() { return answered(shell.ipc.call("identify", "")); }
    function runAction(key) { return answered(shell.status.act(key)); }
    // Write the plugin's setting KEY; answers the core's reply.
    function configure(key, value) {
        const reply = shell.configure.set(key, value);
        dimProblem = Logic.replyText(reply);
        if (reply !== "ok") console.warn("displays pane: " + key + " " + reply);
        return reply;
    }

    // The Select index of the choice that names IDENTIFIER, 0 for none.
    function choiceIndex(identifier) {
        for (let i = 0; i < screenChoices.length; i++) if (screenChoices[i].value === identifier) return i;
        return 0;
    }

    // The output identifier the applied choice of DEVICE names, "" for none.
    function chosenOutput(device) {
        const entry = assignments.entries.find(e => e.device === device && e.state === "applied");
        return entry === undefined ? "" : entry.output;
    }

    function setOutputDraft(patch) {
        outputDraft = Logic.withOutputDraft(outputs, outputRules, outputDraft, selectedOutput, patch);
    }

    function offBlockText(key) {
        if (key === "only-on") return "This is the only display that is on.";
        if (key === "mirrored") return "Another display mirrors this one.";
        return "";
    }

    function applyOutputDraft() {
        const rules = Logic.dirtyRules(outputDraft, outputRules);
        const reply = shell.monitors.trial(rules);
        problem = Logic.replyText(reply);
        if (reply !== "ok") console.warn("displays pane: monitors trial " + reply);
    }

    function keepTrial() {
        const reply = shell.monitors.keep(trialState.token, result => {
            if (!result.ok) {
                problem = Logic.replyText(result.error);
                console.warn("displays pane: monitors keep " + result.error);
                return;
            }
            const next = Object.assign({}, outputRules, result.rules);
            const write = shell.configure.set("outputs", next);
            problem = Logic.replyText(write);
            if (write === "ok") outputDraft = ({});
            else console.warn("displays pane: outputs " + write);
        });
        if (reply !== "pending") {
            problem = Logic.replyText(reply);
            console.warn("displays pane: monitors keep " + reply);
        }
    }

    function revertTrial() {
        const reply = shell.monitors.revert(trialState.token);
        problem = Logic.replyText(reply);
        if (reply === "ok") outputDraft = ({});
        else console.warn("displays pane: monitors revert " + reply);
    }

    Keys.onReturnPressed: event => {
        if (trialState.phase === "holding") {
            keepTrial();
            event.accepted = true;
        }
    }
    Keys.onEnterPressed: event => {
        if (trialState.phase === "holding") {
            keepTrial();
            event.accepted = true;
        }
    }
    Keys.onEscapePressed: event => {
        if (trialState.phase === "holding") {
            revertTrial();
            event.accepted = true;
        }
    }

    implicitWidth: Theme.size.window.width
    implicitHeight: content.implicitHeight
    focus: true

    Column {
        id: content
        width: root.width
        spacing: Theme.stack.section

        Column {
            width: parent.width
            spacing: Theme.stack.group

            SectionHeader {
                width: parent.width
                text: "Display"
                description: "Set the mode, scale and orientation of one screen."
            }

            Dialog {
                id: trialDialog
                width: parent.width
                visible: root.trialState.phase === "holding"
                modal: false
                title: "Keep these display settings?"
                message: Logic.countdownDetail(root.trialState.deadline - root.nowSeconds)
                actions: [{ label: "Keep", role: "accept" }, { label: "Revert", role: "cancel" }]
                onAccepted: root.keepTrial()
                onRejected: root.revertTrial()
            }

            Arrangement {
                id: arrangement
                width: parent.width
                outputs: root.outputs
                savedRules: root.outputRules
                draftRules: root.outputDraft
                selected: root.selectedOutput
                locked: root.trialHolding
                onSelectedChangedByUser: identifier => root.selectedOutput = identifier
                onMoved: rules => root.outputDraft = rules
                onIdentify: identifier => root.identifyAll()
            }

            Button {
                variant: "secondary"
                size: "sm"
                text: "Identify"
                iconName: "scan-eye"
                enabled: root.outputs.length > 0
                onClicked: root.identifyAll()
            }

            // The canvas leaves out a display that mirrors, so this picks it.
            FormRow {
                width: parent.width
                visible: arrangement.items.length < root.displayChoices.length
                label: "Display"

                Select {
                    width: parent.width
                    enabled: !root.trialHolding
                    model: root.displayChoices
                    textRole: "label"
                    currentIndex: Logic.indexByValue(root.displayChoices, root.selectedOutput)
                    Accessible.name: "Display"
                    onActivated: index => {
                        root.selectedOutput = root.displayChoices[index].value;
                        currentIndex = Qt.binding(() => Logic.indexByValue(root.displayChoices, root.selectedOutput));
                    }
                }
            }

            Label {
                width: parent.width
                visible: root.selected !== null
                role: "hint"
                text: root.selected === null ? "" : Logic.outputSummary(root.selected)
                wrapMode: Text.Wrap
            }

            FormRow {
                width: parent.width
                visible: root.selected !== null
                label: "Use this display"
                warning: root.selectedOn ? root.offBlockText(root.offBlock) : ""
                warningTone: "muted"

                Switch {
                    size: "sm"
                    enabled: !root.trialHolding && (!root.selectedOn || root.offBlock === "")
                    checked: root.selectedOn
                    Accessible.name: "Use this display"
                    // The binding comes back after a toggle, so the draft
                    // is what shows.
                    onToggled: {
                        const wanted = checked;
                        checked = Qt.binding(() => root.selectedOn);
                        root.setOutputDraft(wanted ? { disabled: false } : { disabled: true, mirror: "" });
                    }
                }
            }

            FormRow {
                width: parent.width
                visible: root.selected !== null && root.selectedOn
                label: "Mirror"

                Select {
                    width: parent.width
                    enabled: !root.trialHolding
                    model: root.mirrorChoices
                    textRole: "label"
                    currentIndex: root.selectedRule === null ? 0 : Logic.mirrorIndex(root.mirrorChoices, root.selectedRule.mirror)
                    Accessible.name: "Mirror"
                    onActivated: index => {
                        root.setOutputDraft({ mirror: root.mirrorChoices[index].value });
                        currentIndex = Qt.binding(() => root.selectedRule === null ? 0 : Logic.mirrorIndex(root.mirrorChoices, root.selectedRule.mirror));
                    }
                }
            }

            FormRow {
                width: parent.width
                enabled: !root.trialHolding
                visible: root.selected !== null && root.selectedOn
                label: "Resolution"

                Select {
                    id: modeSelect
                    readonly property var choices: root.selected === null ? [] : Logic.modeChoices(root.selected)
                    width: parent.width
                    enabled: !root.trialHolding
                    model: choices
                    textRole: "label"
                    currentIndex: root.selectedRule === null ? 0 : Logic.indexByValue(choices, Logic.modeKey(root.selectedRule.mode))
                    Accessible.name: "Resolution"
                    onActivated: index => {
                        root.setOutputDraft({ mode: choices[index].mode });
                        currentIndex = Qt.binding(() => root.selectedRule === null ? 0 : Logic.indexByValue(choices, Logic.modeKey(root.selectedRule.mode)));
                    }
                }
            }

            FormRow {
                width: parent.width
                enabled: !root.trialHolding
                visible: root.selected !== null && root.selectedOn
                label: "Refresh rate"

                Select {
                    id: refreshSelect
                    readonly property var choices: root.selectedRule === null ? [] : Logic.refreshChoices(root.selected, root.selectedRule.mode)
                    width: parent.width
                    enabled: !root.trialHolding
                    model: choices
                    textRole: "label"
                    currentIndex: root.selectedRule === null ? 0 : Logic.indexByValue(choices, root.selectedRule.mode.refresh)
                    Accessible.name: "Refresh rate"
                    onActivated: index => {
                        root.setOutputDraft({ mode: choices[index].mode });
                        currentIndex = Qt.binding(() => root.selectedRule === null ? 0 : Logic.indexByValue(choices, root.selectedRule.mode.refresh));
                    }
                }
            }

            FormRow {
                width: parent.width
                visible: root.selected !== null && root.selectedOn && !root.selectedMirrors
                label: "Scale"

                Select {
                    id: scaleSelect
                    readonly property var choices: root.selectedRule === null ? [] : Logic.scaleChoices(root.selectedRule.mode, root.selectedRule.scale)
                    width: parent.width
                    model: choices
                    textRole: "label"
                    currentIndex: root.selectedRule === null ? 0 : Logic.indexByValue(choices, root.selectedRule.scale)
                    Accessible.name: "Scale"
                    onActivated: index => {
                        root.setOutputDraft({ scale: choices[index].value });
                        currentIndex = Qt.binding(() => root.selectedRule === null ? 0 : Logic.indexByValue(choices, root.selectedRule.scale));
                    }
                }
            }

            FormRow {
                width: parent.width
                visible: root.selected !== null && root.selectedOn && !root.selectedMirrors
                label: "Orientation"

                Select {
                    width: parent.width
                    model: Logic.TRANSFORMS
                    textRole: "label"
                    currentIndex: root.selectedRule === null ? 0 : Logic.indexByValue(model, root.selectedRule.transform)
                    Accessible.name: "Orientation"
                    onActivated: index => {
                        root.setOutputDraft({ transform: model[index].value });
                        currentIndex = Qt.binding(() => root.selectedRule === null ? 0 : Logic.indexByValue(model, root.selectedRule.transform));
                    }
                }
            }

            Label {
                width: parent.width
                visible: root.trialState.phase === "idle" && root.selected !== null && root.shell !== null && (root.shell.monitors.overridden(root.outputRules)[root.selected.name] === true || root.shell.monitors.overridden(root.outputRules)[root.selectedOutput] === true)
                role: "hint"
                color: Theme.color.warning
                text: "Your Hyprland file now sets this display differently."
                wrapMode: Text.Wrap
            }

            SaveBar {
                width: parent.width
                dirty: root.outputDirty && root.trialState.phase !== "holding"
                onSave: root.applyOutputDraft()
                onDiscard: root.outputDraft = ({})
            }

            Timer {
                interval: 250
                running: root.trialState.phase === "holding"
                repeat: true
                onTriggered: root.nowSeconds = Math.floor(Date.now() / 1000)
            }
        }

        Column {
            width: parent.width
            spacing: Theme.stack.group

            SectionHeader {
                width: parent.width
                text: "Brightness"
                description: "Each display keeps its own level."
            }

            Column {
                id: displaysColumn
                width: parent.width
                spacing: Theme.stack.row

                Repeater {
                    model: ScriptModel {
                        values: root.list.items
                        objectProp: "id"
                    }

                    Column {
                        id: entry
                        required property var modelData
                        required property int index
                        readonly property bool placeable: Logic.placeable(modelData)
                        width: displaysColumn.width
                        spacing: Theme.stack.row

                        DisplayRow {
                            id: row
                            width: entry.width
                            shell: root.shell
                            display: entry.modelData
                        }

                        FormRow {
                            width: entry.width
                            visible: entry.placeable
                            label: "Screen"
                            warning: entry.modelData.outputs.length === 0 ? "Not placed" : ""

                            Row {
                                width: parent.width
                                spacing: Theme.stack.inline

                                Select {
                                    id: screenSelect
                                    readonly property string chosen: root.chosenOutput(entry.modelData.device)
                                    width: parent.width - identifyButton.width - parent.spacing
                                    model: root.screenChoices
                                    textRole: "label"
                                    currentIndex: root.choiceIndex(chosen)
                                    Accessible.name: "Screen for " + entry.modelData.label
                                    // A new choice assigns currentIndex; the
                                    // binding comes back, so the choice the
                                    // service applies is the one shown.
                                    onActivated: index => {
                                        const output = root.screenChoices[index].value;
                                        if (output !== screenSelect.chosen) root.assign(entry.modelData.device, output);
                                        currentIndex = Qt.binding(() => root.choiceIndex(screenSelect.chosen));
                                    }
                                }
                                Button {
                                    id: identifyButton
                                    variant: "secondary"
                                    size: "sm"
                                    text: "Identify"
                                    iconName: "scan-eye"
                                    anchors.verticalCenter: parent.verticalCenter
                                    onClicked: root.identify(entry.modelData.id)
                                }
                            }
                        }
                    }
                }
            }

            Label {
                width: parent.width
                visible: text !== ""
                role: "hint"
                text: Logic.listText(root.list.state, root.list.items.length)
                wrapMode: Text.Wrap
            }

            LinkRow {
                id: linkRow
                width: parent.width
                shell: root.shell
                onReplied: reply => root.answered(reply)
            }

            Label {
                width: parent.width
                visible: text !== ""
                role: "hint"
                color: Theme.color.danger
                text: root.problem
                wrapMode: Text.Wrap
            }
        }

        // Dimming: how long without input before the displays dim, and the
        // level they dim to, each a Select over its schema entry's presets,
        // written through `configure`; a custom value, set on the plugin's
        // settings page, shows as one more choice.
        Column {
            id: dimColumn
            readonly property var schema: root.shell === null ? ({}) : root.shell.manifest.schema
            readonly property int after: root.shell === null ? 0 : root.shell.settings.dimAfterSeconds
            readonly property int percent: root.shell === null ? 0 : root.shell.settings.dimPercent
            readonly property var afterChoices: root.shell === null ? [] : Logic.presetChoices(schema.dimAfterSeconds, after, SettingValues.presetText)
            readonly property var percentChoices: root.shell === null ? [] : Logic.presetChoices(schema.dimPercent, percent, SettingValues.presetText)
            width: parent.width
            spacing: Theme.stack.group

            function indexOf(choices, value) {
                for (let i = 0; i < choices.length; i++) if (choices[i].value === value) return i;
                return 0;
            }

            SectionHeader {
                width: parent.width
                text: "Dimming"
                description: "Any input brings each display back to its level."
            }

            FormRow {
                width: parent.width
                label: dimColumn.schema.dimAfterSeconds === undefined ? "" : dimColumn.schema.dimAfterSeconds.label

                Select {
                    width: parent.width
                    model: dimColumn.afterChoices
                    textRole: "label"
                    currentIndex: dimColumn.indexOf(dimColumn.afterChoices, dimColumn.after)
                    Accessible.name: dimColumn.schema.dimAfterSeconds === undefined ? "" : dimColumn.schema.dimAfterSeconds.label
                    // The binding comes back after a choice, so the value
                    // the configuration holds is the one shown.
                    onActivated: index => {
                        const value = dimColumn.afterChoices[index].value;
                        if (value !== dimColumn.after) root.configure("dimAfterSeconds", value);
                        currentIndex = Qt.binding(() => dimColumn.indexOf(dimColumn.afterChoices, dimColumn.after));
                    }
                }
            }

            FormRow {
                width: parent.width
                label: dimColumn.schema.dimPercent === undefined ? "" : dimColumn.schema.dimPercent.label

                Select {
                    width: parent.width
                    enabled: dimColumn.after > 0
                    model: dimColumn.percentChoices
                    textRole: "label"
                    currentIndex: dimColumn.indexOf(dimColumn.percentChoices, dimColumn.percent)
                    Accessible.name: dimColumn.schema.dimPercent === undefined ? "" : dimColumn.schema.dimPercent.label
                    onActivated: index => {
                        const value = dimColumn.percentChoices[index].value;
                        if (value !== dimColumn.percent) root.configure("dimPercent", value);
                        currentIndex = Qt.binding(() => dimColumn.indexOf(dimColumn.percentChoices, dimColumn.percent));
                    }
                }
            }

            Label {
                width: parent.width
                visible: text !== ""
                role: "hint"
                color: Theme.color.danger
                text: root.dimProblem
                wrapMode: Text.Wrap
            }
        }

        Column {
            id: staleColumn
            width: parent.width
            spacing: Theme.stack.group
            visible: root.stale.length > 0 || root.assignments.error !== null

            SectionHeader {
                width: parent.width
                text: "Saved choices"
                description: Logic.savedChoicesText(root.assignments.error)
            }

            Repeater {
                model: ScriptModel {
                    values: root.stale
                    objectProp: "device"
                }

                FormRow {
                    required property var modelData
                    width: staleColumn.width
                    label: modelData.label

                    Row {
                        width: parent.width
                        spacing: Theme.stack.inline

                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - forgetButton.width - parent.spacing
                            role: "body"
                            text: modelData.output
                            elide: Text.ElideRight
                        }
                        Button {
                            id: forgetButton
                            variant: "secondary"
                            size: "sm"
                            text: "Forget"
                            onClicked: root.assign(modelData.device, "")
                        }
                    }
                }
            }
        }

        Column {
            id: accessColumn
            width: parent.width
            spacing: Theme.stack.group
            visible: root.accessRows.length > 0

            SectionHeader {
                width: parent.width
                text: "Access"
            }

            Repeater {
                model: ScriptModel {
                    values: root.accessRows
                    objectProp: "key"
                }

                FormRow {
                    id: accessRow
                    required property var modelData
                    width: accessColumn.width
                    label: modelData.label
                    warning: modelData.value.text
                    warningTone: Logic.formWarningTone(modelData.tone)

                    Button {
                        visible: accessRow.modelData.action !== null && accessRow.modelData.action.offered
                        variant: "secondary"
                        size: "sm"
                        text: accessRow.modelData.action === null ? "" : accessRow.modelData.action.label
                        onClicked: root.runAction(accessRow.modelData.key)
                    }
                }
            }
        }
    }
}
