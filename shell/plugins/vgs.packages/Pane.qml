import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// The shared package choices live with Config; Updates keeps its own
// update settings. Both views draw that same manifest through SettingField
// and write through the manager, including choice handlers such as restart
// notices. Mounting this pane starts no check, review or package operation;
// it reads only the account folders the package owner offers and how the
// review reads the saved one.
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
    // The account folders the package owner offers for the agent the review
    // would start, as { value, label }; null until a read answers. They
    // depend on the agent and command alone.
    property var accountOffers: null
    readonly property string offersQuery: JSON.stringify({ agent: review.agent || "", command: review.command || "" })
    // The saved account as the review reads it (PackageReview.reviewAccount):
    // { state: "chosen" or "missing", shown } or { state: "automatic" }, also
    // for a folder another agent's discovery lists; null until a read answers.
    property var savedAccount: null
    readonly property string savedQuery: JSON.stringify({ agent: review.agent || "", command: review.command || "", account: review.account || "" })
    readonly property string accountValue: savedAccount !== null && savedAccount.state === "automatic" ? "" : review.account || ""
    readonly property var accountChoices: {
        const choices = [{ value: "", label: "Automatic" }].concat(accountOffers || []);
        const saved = accountValue;
        // A saved folder discovery no longer lists stays shown; it is named
        // not found only once the review's reading says so.
        if (!choices.some(choice => choice.value === saved))
            choices.push({ value: saved, label: savedAccount === null ? saved : savedAccount.shown + (savedAccount.state === "missing" ? " (not found)" : "") });
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

    // One read per reader at a time. A choice that changed during a read
    // drops its answer and reads again when it ends.
    function readOwner(reader, verb, query) {
        if (reader.running) return;
        reader.asked = query;
        reader.command = [Quickshell.shellDir + "/../bin/vgshell-pkg", verb, query];
        reader.running = true;
    }
    function readOffers() { readOwner(offersReader, "review-settings-accounts", offersQuery); }
    function readSaved() {
        if ((review.account || "") !== "") readOwner(savedReader, "review-settings-account", savedQuery);
        else if (!savedReader.running) savedAccount = { state: "automatic" };
    }
    function unread(name, done, lines) {
        console.warn("packages: " + name + "=unread " + (done === null ? "start=failed" : "exit=" + done.code + " lines=" + lines.length));
        return null;
    }

    // `review-settings-accounts` prints one `folder<TAB>shown folder` line
    // per offer; any other line leaves the offers unread.
    function takeOffers(done, text) {
        const lines = text.split("\n").filter(line => line !== "");
        const offers = lines.map(line => line.split("\t")).filter(fields => fields.length === 2 && fields[0] !== "")
            .map(fields => ({ value: fields[0], label: fields[1] }));
        accountOffers = done !== null && done.code === 0 && offers.length === lines.length ? offers : unread("accounts", done, lines);
    }

    // `review-settings-account` prints one line: `automatic`, or `chosen` or
    // `missing`, a tab and the folder as shown.
    function takeSaved(done, text) {
        const lines = text.split("\n").filter(line => line !== "");
        const fields = lines.length === 1 ? lines[0].split("\t") : [];
        const known = done !== null && done.code === 0
            && ((fields.length === 1 && fields[0] === "automatic") || (fields.length === 2 && ["chosen", "missing"].indexOf(fields[0]) >= 0 && fields[1] !== ""));
        savedAccount = known ? (fields.length === 1 ? { state: "automatic" } : { state: fields[0], shown: fields[1] }) : unread("account", done, lines);
    }

    // A new query's answer is unknown until its read ends.
    onOffersQueryChanged: { accountOffers = null; readOffers(); }
    onSavedQueryChanged: { savedAccount = null; readSaved(); }
    Component.onCompleted: { readOffers(); readSaved(); }

    implicitWidth: Theme.size.window.width
    implicitHeight: content.implicitHeight
    focus: true

    // Collectors finish before exited, then running turns false; a failed
    // start has no exited signal. The process inherits the shell's
    // environment, the account variables discovery reads included.
    // https://quickshell.org/docs/v0.3.1/types/Quickshell.Io/Process/
    Process {
        id: offersReader
        property string asked: ""
        property var completion: null
        stdout: StdioCollector { id: offersText }
        stderr: StdioCollector {}
        onExited: (code, status) => { completion = { code: status === 0 ? code : -1 }; }
        onRunningChanged: {
            if (running) return;
            const done = completion;
            completion = null;
            if (asked === root.offersQuery) root.takeOffers(done, offersText.text);
            else Qt.callLater(root.readOffers);
        }
    }
    Process {
        id: savedReader
        property string asked: ""
        property var completion: null
        stdout: StdioCollector { id: savedText }
        stderr: StdioCollector {}
        onExited: (code, status) => { completion = { code: status === 0 ? code : -1 }; }
        onRunningChanged: {
            if (running) return;
            const done = completion;
            completion = null;
            if (asked === root.savedQuery) root.takeSaved(done, savedText.text);
            else Qt.callLater(root.readSaved);
        }
    }

    Column {
        id: content
        width: root.width
        spacing: Theme.stack.group

        Callout {
            objectName: "packages-problem"
            level: "raised"
            width: parent.width
            text: root.problem
            tone: "danger"
            visible: text !== ""
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
            description: "The review runs only with paru. Yay keeps its own review menus."
            rowSpacing: Theme.stack.row

            Field {
                width: parent.width
                inline: true
                label: "Before installing"
                hint: beforeInstalling.currentIndex === 2 ? "Ask each time, with no review selected if no AI agent is found"
                    : "Asks first with a custom AUR command"
                Select {
                    id: beforeInstalling
                    objectName: "packageReviewChoice"
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
                    model: root.agentChoices
                    textRole: "label"
                    currentIndex: root.agentChoices.findIndex(choice => choice.value === (root.review.agent || ""))
                    onActivated: index => {
                        currentIndex = Qt.binding(() => root.agentChoices.findIndex(choice => choice.value === (root.review.agent || "")));
                        root.changeReview("agent", root.agentChoices[index].value);
                    }
                }
            }

            Field {
                width: parent.width
                inline: true
                label: "Account"
                hint: "Automatic uses the agent's own account"
                Select {
                    id: account
                    objectName: "packageReviewAccount"
                    model: root.accountChoices
                    textRole: "label"
                    currentIndex: root.accountChoices.findIndex(choice => choice.value === root.accountValue)
                    onActivated: index => {
                        currentIndex = Qt.binding(() => root.accountChoices.findIndex(choice => choice.value === root.accountValue));
                        root.changeReview("account", root.accountChoices[index].value);
                    }
                }
            }

            SettingField {
                id: commandField
                width: parent.width
                key: "command"
                spec: ({ type: "string", label: "Review command", description: "Optional command to use instead of the selected AI agent", info: "The command starts in its own review folder, or one fixed folder when it starts with claude.\nNeither folder holds updates or other reviews, so an agent with its own sandbox cannot change them.\nA claude or codex command uses the account above.\nWithout -p, claude asks before it reads review files or saves a verdict, unless your options decide.\nVGS does not restrict commands that have no sandbox.", presets: [{ value: "", label: "Use the selected AI agent" }], allowCustom: true })
                value: root.review.command || ""
                onApply: value => root.changeReview("command", value)
            }
        }
    }
}
