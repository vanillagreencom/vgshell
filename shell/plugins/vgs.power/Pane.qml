import QtQuick
import qs.Commons
import qs.Ui

// System → Power: the section the panes holder mounts, a body alone from
// x 0, its height its implicitHeight; the holder draws its title, inset and
// scrolling. It takes no payload keys.
//
// From the top: the idle timeline, one row per stage of the core's record
// (`shell.idle.stages`, D109) in its order, each with its time and a page
// reference to the field that sets it, built from the record's `plugin` and
// `setting`, and the record's `before` verdict as the row's warning; then
// this plugin's own settings, one section per schema group in manifest
// order, each field drawn while its `shownWhen` presence reads present, as
// the Settings page draws it, and written through `configure`. While the
// last scan misses the optional power profiles service, the section offers
// its install, which raises the core's requirement notice.
FocusScope {
    id: root

    property var shell: null
    property string problem: ""
    readonly property var stages: shell === null ? [] : shell.idle.stages
    readonly property var schema: shell === null ? ({}) : shell.manifest.schema
    readonly property var presence: shell === null ? ({}) : shell.status.values
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
    // as a clause for a row it fires before. The record holds no other
    // stage (PluginLogic.IDLE_STAGES).
    readonly property var stageText: ({
        dim: { label: "Dim", verb: "Dims", clause: "the displays dim" },
        screensaver: { label: "Screensaver", verb: "Starts", clause: "the screensaver starts" },
        lock: { label: "Lock", verb: "Locks", clause: "the screen locks" },
        displayOff: { label: "Display off", verb: "Turns off", clause: "the displays turn off" },
        sleep: { label: "Sleep", verb: "Sleeps", clause: "the computer sleeps" }
    })

    function open(payloadJson) {}
    function close() {}

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
    // preset holds it, as the Settings page offers a custom value.
    function choicesOf(key) {
        const entry = schema[key];
        if (entry.type === "enum") return entry.options.map(option => ({ label: option.label, value: option.value }));
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
            id: timeline
            width: content.width
            title: "Idle timeline"
            description: "Each time counts from your last input. Select a time to change it."

            Repeater {
                model: root.stages

                FormRow {
                    required property var modelData
                    width: timeline.width
                    label: root.stageText[modelData.stage].label
                    warning: root.beforeText(modelData)

                    LinkText {
                        role: "value"
                        text: root.timeReference(modelData)
                        onPageActivated: (page, tab) => root.shell.surfaces.openPage(page, tab)
                    }
                }
            }

            Label {
                visible: root.stages.length === 0
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
                        hint: entry.description

                        // The binding comes back after a choice, so the
                        // control shows the value the configuration holds.
                        SegmentedControl {
                            visible: field.entry.type === "enum"
                            model: field.choices.map(choice => choice.label)
                            currentIndex: field.current
                            Accessible.name: field.entry.label
                            onActivated: index => {
                                root.configure(field.modelData, field.choices[index].value);
                                currentIndex = Qt.binding(() => field.current);
                            }
                        }

                        Select {
                            visible: field.entry.type === "number"
                            width: parent.width
                            model: field.choices
                            textRole: "label"
                            currentIndex: field.current
                            Accessible.name: field.entry.label
                            onActivated: index => {
                                root.configure(field.modelData, field.choices[index].value);
                                currentIndex = Qt.binding(() => field.current);
                            }
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

                Badge {
                    text: root.diskSleep === null ? "" : root.diskSleep.value.text
                    tone: root.diskSleep === null ? "info" : root.diskSleep.tone
                }

                RowAction {
                    visible: root.diskSleep !== null && root.diskSleep.action !== null && root.diskSleep.action.offered
                    text: root.diskSleep === null || root.diskSleep.action === null ? "" : root.diskSleep.action.label
                    onClicked: root.allowDiskSleep()
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
