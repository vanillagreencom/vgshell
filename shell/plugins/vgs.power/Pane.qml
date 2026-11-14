import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// System → Power: the section the panes holder mounts, a body alone from
// x 0, its height its implicitHeight; the holder draws its title, inset and
// scrolling. It takes no payload keys.
//
// From the top: Stay awake's control (StayAwake.qml), the one the flyout
// draws; the idle timeline, one row per stage of the core's record
// (`shell.idle.stages`, D109) in its order, each with its time and a page
// reference to the field that sets it, built from the record's `plugin` and
// `setting`, and the record's `before` verdict as the row's warning. A
// stage of the manifest's `idleSettingRows`, the lock, draws its owner's
// editor instead (`shell.idleSettings`, IdleTimeField), in its place in
// the order whether its owner is on, off or absent, and writes through
// it; then
// this plugin's own settings, one section per schema group in manifest
// order, each field drawn while its `shownWhen` presence reads present, as
// the Settings page draws it, with its info, and written through
// `configure`. A field whose setting the service applies elsewhere also
// shows the service's last failure through the schema's `problem`, as
// the Settings page does. Under Turn displays off, a row per input that
// can turn the displays on shows whether Hyprland lets it
// (`hyprland.displayWake`). While the last scan misses the optional power profiles service,
// the section offers its install, which raises the core's requirement
// notice.
FocusScope {
    id: root

    property var shell: null
    property string problem: ""
    readonly property var stages: shell === null ? [] : shell.idle.stages
    readonly property var editors: shell === null ? [] : shell.idleSettings.fields
    // The timeline's stages in order: each one the record holds or the pane
    // edits. Each row reads its record entry and editor by stage, so a
    // change of a time keeps every row and its control in place.
    readonly property var timelineStages: Object.keys(stageText).filter(stage => stageRowOf(stage) !== null || editorOf(stage) !== null)
    // The last refusal of a timeline editor's write, by stage.
    property var editorProblems: ({})
    readonly property var schema: shell === null ? ({}) : shell.manifest.schema
    readonly property var presence: shell === null ? ({}) : shell.status.values
    readonly property var settingChoices: shell === null ? ({}) : (shell.manager.plugins.find(plugin => plugin.id === shell.manifest.id)?.settingChoices ?? ({}))
    readonly property var wakeRow: shell === null ? null : shell.status.rows.find(row => row.key === "wakeSources") || null
    readonly property var displayWake: shell === null ? { keyPress: "unreadable", pointerMovement: "unreadable" } : shell.hyprland.displayWake
    readonly property var displayWakeRows: [
        { label: "Key press wake", state: displayWake.keyPress, path: "misc.key_press_enables_dpms" },
        { label: "Pointer movement wake", state: displayWake.pointerMovement, path: "misc.mouse_move_enables_dpms" }
    ]
    readonly property var wakeStates: ({
        enabled: { label: "Enabled", tone: "success" },
        disabled: { label: "Disabled", tone: "warning" },
        unreadable: { label: "Unreadable", tone: "neutral" }
    })
    readonly property string profilesService: "org.freedesktop.UPower.PowerProfiles"
    readonly property bool profilesMissing: shell !== null && shell.requirements.missing.indexOf(profilesService) !== -1
    readonly property var diskSleep: shell === null ? null : shell.status.rows.find(row => row.key === "diskSleep" && row.report === "reported") || null
    // The schema's groups in the order their first entry appears, each with
    // its keys in key order.
    readonly property var groups: {
        const out = [];
        for (const key of Object.keys(schema)) {
            const name = schema[key].group;
            let group = out.find(g => g.name === name);
            if (group === undefined) out.push(group = { name: name, keys: [] });
            group.keys.push(key);
        }
        return out;
    }
    readonly property Item initialFocus: content

    // Each stage's row label, what it does as a verb for its own row, and
    // as a clause for a row it fires before, in the record's order. The
    // record holds no other stage (PluginLogic.IDLE_STAGES).
    readonly property var stageText: ({
        dim: { label: "Dim", verb: "Dims", clause: "the displays dim" },
        screensaver: { label: "Screensaver", verb: "Starts", clause: "the screensaver starts" },
        lock: { label: "Lock", verb: "Locks", clause: "the screen locks" },
        displayOff: { label: "Display off", verb: "Turns off", clause: "the displays turn off" },
        sleep: { label: "Sleep", verb: "Sleeps", clause: "the computer sleeps" }
    })

    function open(payloadJson) {}
    function close() {}

    function openHyprlandConfig() {
        const reply = shell.tui.edit("hypr/hyprland.lua");
        if (reply !== "ok") console.warn("power pane: edit " + reply);
    }

    // INFO with each reference to this section reduced to its words: the
    // help names this section for the Settings page, which opens it, and
    // `surfaces.openPage` here would open the Settings page instead
    // (Plugins.openSettingsPage). Other references keep their links.
    function infoHere(info) {
        let out = info;
        for (const link of PageReference.references(info).links)
            if (link.page === shell.manifest.id) out = out.replace(link.reference, () => link.words);
        return out;
    }

    // STAGE's entry of the core's record, or null.
    function stageRowOf(stage) {
        return stages.find(entry => entry.stage === stage) || null;
    }
    // STAGE's editor (`shell.idleSettings.fields`), or null.
    function editorOf(stage) {
        return editors.find(entry => entry.stage === stage) || null;
    }

    function timeReference(stage) {
        const words = stage.seconds === 0 ? "Never" : "After " + SettingValues.quantityText(stage.seconds, "seconds");
        return "[" + words + "](page:" + stage.plugin + "/Settings/" + stage.setting + ")";
    }

    function beforeText(stage) {
        if (stage.before.length === 0) return "";
        const clauses = stage.before.map(name => stageText[name].clause);
        const list = clauses.length === 1 ? clauses[0] : clauses.slice(0, -1).join(", ") + " and " + clauses[clauses.length - 1];
        return stageText[stage.stage].verb + " before " + list;
    }

    function shown(key) {
        const when = schema[key].shownWhen;
        return when === undefined || presence[when] === "present";
    }

    // A number's presets, with the stored value as one more choice when no
    // preset holds it, as the Settings page offers a custom value. A
    // boolean has none: its switch reads the value.
    function choicesOf(key) {
        const entry = schema[key];
        if (entry.type === "boolean") return [];
        if (entry.type === "enum") return entry.options.map(option => ({ label: option.label, value: option.value }));
        if (entry.optionsFrom !== undefined) return settingChoices[key] ?? [];
        const value = shell.settings[key];
        const choices = entry.presets.map(preset => ({ label: SettingValues.presetText(entry, preset), value: preset.value }));
        if (!choices.some(choice => choice.value === value)) choices.push({ label: SettingValues.presetText(entry, { value: value }), value: value });
        return choices;
    }

    function installProfiles() {
        const reply = shell.requirements.offer([profilesService]);
        problem = reply === "ok" || reply === "satisfied" ? "" : "VGS could not open the install for the power profiles service.";
        if (problem !== "") console.warn("power pane: requirements " + reply);
    }

    function allowDiskSleep() {
        const reply = shell.ipc.call("disk-sleep", "");
        problem = reply === "ok" || reply === "satisfied" ? "" : "VGS could not open the disk sleep setup.";
        if (problem !== "") console.warn("power pane: disk sleep " + reply);
    }

    function configure(key, value) {
        if (value === shell.settings[key]) return "ok";
        const reply = shell.configure.set(key, value);
        problem = reply === "ok" ? "" : "VGS could not save this setting.";
        if (reply !== "ok") console.warn("power pane: configure " + key + " " + reply);
        return reply;
    }

    // Writes SECONDS as FIELD's stage time through the stage's owner,
    // keeping a refusal for the row.
    function writeStage(field, seconds) {
        const reply = shell.idleSettings.set(field.stage, seconds, field.identity);
        const next = Object.assign({}, editorProblems);
        if (reply === "ok") delete next[field.stage];
        else {
            next[field.stage] = Reply.line(reply, shell.manager.plugins);
            console.warn("power pane: idle setting " + field.stage + " " + reply);
        }
        editorProblems = next;
        return reply;
    }

    function allowWake() {
        const reply = shell.status.act("wakeSources");
        problem = reply === "ok" ? "" : "VGS could not open wake source setup.";
        if (reply !== "ok") console.warn("power pane: wake sources " + reply);
    }

    implicitWidth: Theme.size.window.width
    implicitHeight: content.implicitHeight
    focus: true

    // Each Repeater delegate sizes from an id, not its parent: the
    // holder's teardown unparents a delegate while its bindings still run,
    // and a parent read there is a TypeError the log keeps (the
    // system-window row's log check). Each Section measures its own
    // `stack.heading` above it, less this column's spacing, which is the
    // problem line's space.
    Column {
        id: content
        width: root.width
        spacing: Theme.stack.group

        Section {
            id: stayAwakeSection
            width: content.width
            title: "Stay awake"

            Field {
                width: stayAwakeSection.width
                inline: true
                label: stayAwake.awake.active ? "Time left" : "Duration"
                hint: stayAwake.hint
                error: stayAwake.problem

                StayAwake {
                    id: stayAwake
                    shell: root.shell
                }
            }
        }

        Section {
            id: timeline
            width: content.width
            title: "Idle timeline"
            description: stayAwake.awake.active ? "Paused while Stay awake is on. Each time counts from your last input." : "Each time counts from your last input. Select a time to change it."

            // A ScriptModel of stage names keeps each row while the record
            // and the editors are replaced whole on every change.
            Repeater {
                model: ScriptModel { values: root.timelineStages }

                Loader {
                    id: stageRow
                    required property string modelData
                    readonly property var row: root.stageRowOf(modelData)
                    readonly property var field: root.editorOf(modelData)
                    // The row stands by ink as the row it holds does: a
                    // key/value row under another one reads this Loader as
                    // its row above (FormRow `rowAbove`).
                    readonly property bool keyValueRow: item !== null && item.keyValueRow === true
                    width: timeline.width
                    sourceComponent: field === null ? timeRow : editorRow

                    Component {
                        id: timeRow
                        FormRow {
                            width: stageRow.width
                            label: root.stageText[stageRow.modelData].label
                            warning: stageRow.row === null ? "" : root.beforeText(stageRow.row)

                            LinkText {
                                role: "value"
                                text: stageRow.row === null ? "" : root.timeReference(stageRow.row)
                                onPageActivated: (page, tab) => root.shell.surfaces.openPage(page, tab)
                            }
                        }
                    }

                    Component {
                        id: editorRow
                        IdleTimeField {
                            width: stageRow.width
                            field: stageRow.field
                            warning: stageRow.row === null ? "" : root.beforeText(stageRow.row)
                            problem: root.editorProblems[stageRow.modelData] ?? ""
                            onApply: value => root.writeStage(field, value)
                            onPageActivated: (page, tab) => root.shell.surfaces.openPage(page, tab)
                        }
                    }
                }
            }

            Label {
                visible: root.timelineStages.length === 0
                width: timeline.width
                role: "hint"
                text: "Nothing happens when you stop using the computer."
                wrapMode: Text.Wrap
            }
        }

        Repeater {
            model: root.groups

            Section {
                id: group
                required property var modelData
                readonly property var keys: modelData.keys.filter(key => root.shown(key))
                visible: keys.length > 0
                width: content.width
                title: modelData.name

                Repeater {
                    model: group.keys

                    Field {
                        id: field
                        required property string modelData
                        readonly property var entry: root.schema[modelData]
                        readonly property var choices: root.shell === null ? [] : root.choicesOf(modelData)
                        readonly property int current: root.shell === null ? -1 : choices.findIndex(choice => choice.value === root.shell.settings[modelData])
                        width: content.width
                        inline: true
                        label: entry.label
                        hint: entry.description ?? ""
                        info: root.shell === null ? "" : root.infoHere(entry.info ?? "")
                        error: entry.problem === undefined ? "" : root.presence[entry.problem] ?? ""
                        onInfoPageActivated: (page, tab) => root.shell.surfaces.openPage(page, tab)

                        // The binding comes back after a choice, so the
                        // control shows the value the configuration holds.
                        // The row's slot is as tall as all its children,
                        // shown or not (FormRow `slot`), so a hidden
                        // control takes no height.
                        SegmentedControl {
                            visible: field.entry.type === "enum"
                            height: visible ? implicitHeight : 0
                            model: field.choices.map(choice => choice.label)
                            currentIndex: field.current
                            Accessible.name: field.entry.label
                            onActivated: index => {
                                root.configure(field.modelData, field.choices[index].value);
                                currentIndex = Qt.binding(() => field.current);
                            }
                        }

                        Switch {
                            visible: field.entry.type === "boolean"
                            height: visible ? implicitHeight : 0
                            size: "sm"
                            checked: root.shell !== null && root.shell.settings[field.modelData] === true
                            Accessible.name: field.entry.label
                            onToggled: {
                                root.configure(field.modelData, checked);
                                checked = Qt.binding(() => root.shell !== null && root.shell.settings[field.modelData] === true);
                            }
                        }

                        Select {
                            visible: field.entry.type === "number" || field.entry.type === "string"
                            height: visible ? implicitHeight : 0
                            width: parent.width
                            model: field.choices
                            textRole: "label"
                            currentIndex: field.current
                            Accessible.name: field.entry.label
                            onOpened: {
                                if (field.entry.optionsFrom !== undefined)
                                    root.shell.manager.refreshChoices(root.shell.manifest.id, field.entry.optionsFrom);
                            }
                            onActivated: index => {
                                root.configure(field.modelData, field.choices[index].value);
                                currentIndex = Qt.binding(() => field.current);
                            }
                        }
                    }
                }

                Repeater {
                    model: group.keys.includes("displayOffSeconds") ? root.displayWakeRows : []

                    // The core layer writes both options true
                    // (HyprlandLayer.js sessionLockLines), so a disabled
                    // reading is a later line of the user's own Hyprland
                    // config: the row's override message and its link to
                    // that file, as Hyprland reading back another value
                    // than VGS wrote reads in every ValueSourceRow.
                    ValueSourceRow {
                        id: wakeInput
                        required property var modelData
                        width: content.width
                        label: modelData.label
                        path: modelData.path
                        hyprland: ({ values: {}, userValues: [], overridden: modelData.state === "disabled" ? [modelData.path] : [] })
                        warning: modelData.state === "unreadable" ? "Could not check if this turns displays on" : wakeInput.messageText(wakeInput.messageKind)
                        onOpenHyprlandConfig: root.openHyprlandConfig()

                        Badge {
                            text: root.wakeStates[modelData.state].label
                            tone: root.wakeStates[modelData.state].tone
                        }
                    }
                }
            }
        }

        Section {
            visible: root.diskSleep !== null
            width: content.width
            title: "Hard disks"

            Field {
                width: content.width
                inline: true
                label: root.diskSleep === null ? "" : root.diskSleep.label
                hint: root.diskSleep === null ? "" : root.diskSleep.hint
                info: root.diskSleep === null ? "" : root.diskSleep.info

                Row {
                    spacing: Theme.stack.inline

                    Badge {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.diskSleep === null ? "" : root.diskSleep.value.text
                        tone: root.diskSleep === null ? "info" : root.diskSleep.tone
                    }

                    RowAction {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.diskSleep !== null && (root.presence.diskSleepInstall === "present" || (root.diskSleep.action !== null && root.diskSleep.action.offered))
                        text: root.diskSleep === null || root.diskSleep.action === null ? "" : root.diskSleep.action.label
                        onClicked: root.allowDiskSleep()
                    }
                }
            }
        }

        Section {
            visible: root.profilesMissing
            width: content.width
            title: "Power profiles"
            description: "Install the power profiles service to switch between power saver, balanced and performance."

            RowAction {
                text: "Install power profiles"
                onClicked: root.installProfiles()
            }
        }

        Section {
            width: content.width
            title: "Wake"

            Field {
                width: content.width
                inline: true
                label: "Wake sources"
                hint: root.wakeRow === null ? "" : root.wakeRow.hint

                Row {
                    spacing: Theme.stack.inline
                    Badge {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.wakeRow === null || root.wakeRow.value === null ? "Checking" : root.wakeRow.value.text
                        tone: root.wakeRow === null || root.wakeRow.tone === "" ? "info" : root.wakeRow.tone
                    }
                    RowAction {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.wakeRow !== null && root.wakeRow.action !== null && root.wakeRow.action.offered
                        text: root.wakeRow === null || root.wakeRow.action === null ? "Allow" : root.wakeRow.action.label
                        onClicked: root.allowWake()
                    }
                }
            }
        }

        Label {
            visible: root.problem !== ""
            width: parent.width
            role: "hint"
            color: Theme.color.danger
            text: root.problem
            wrapMode: Text.Wrap
        }
    }
}
