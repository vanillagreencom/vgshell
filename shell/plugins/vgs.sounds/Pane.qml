import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Sounds pane: every sound event the enabled plugins declare, under its
// plugin's name, each with a picker of the values the event takes, Off
// first, and Test on the row's line while the choice is a sound of the
// core's. A choice is saved as it is made and plays once, so the user picks
// by ear. An event
// its plugin sounds itself offers Off and that plugin's own sound. An event
// whose value another program holds shows what its plugin read there, and
// that plugin's line when the value is unread or a choice did not take
// effect. The events, the values each takes and the one write are the
// `soundSettings` capability's; the pane holds the layout alone.
FocusScope {
    id: root

    property var shell: null
    property string problem: ""
    readonly property var sounds: shell === null ? null : shell.soundSettings
    readonly property var groups: sounds === null ? [] : groupsOf(sounds.events)
    property Item firstPicker: null
    readonly property Item initialFocus: firstPicker !== null ? firstPicker : root

    // The page shows what each held value is now, so its holder reads it
    // again.
    function open(payloadJson) {
        sounds.refresh();
    }
    function close() {}

    // [{ id, plugin, rows }] in the order ROWS lists them.
    function groupsOf(rows) {
        const out = [];
        for (const row of rows) {
            if (out.length === 0 || out[out.length - 1].id !== row.id) out.push({ id: row.id, plugin: row.plugin, rows: [] });
            out[out.length - 1].rows.push(row);
        }
        return out;
    }

    function choose(row, offer) {
        const reply = sounds.choose(row.id, row.event, offer.value);
        problem = reply === "ok" ? "" : "VGS could not save this setting.";
        if (reply !== "ok") console.warn("sounds: choose " + reply);
        else if (offer.playable) test(offer.value);
    }

    // `busy` is a sound still playing, which the user hears.
    function test(sound) {
        const reply = sounds.test(sound);
        if (reply !== "ok" && reply !== "busy") console.warn("sounds: test " + reply);
    }

    implicitWidth: Theme.size.window.width
    implicitHeight: content.implicitHeight
    focus: true

    Column {
        id: content
        width: root.width
        spacing: Theme.stack.group

        EmptyState {
            visible: root.groups.length === 0
            width: parent.width
            iconName: "volume-x"
            text: "No enabled plugin has a sound."
        }

        // Keyed by plugin and by event, so a choice, which replaces every
        // row, changes each row in place and the picker in use keeps the
        // keyboard. https://quickshell.org/docs/v0.3.1/types/Quickshell/ScriptModel
        Repeater {
            model: ScriptModel {
                values: root.groups
                objectProp: "id"
            }

            Section {
                id: section

                required property var modelData
                required property int index

                width: content.width
                title: modelData.plugin

                Repeater {
                    model: ScriptModel {
                        values: section.modelData.rows
                        objectProp: "event"
                    }

                    FormRow {
                        id: eventRow

                        required property var modelData
                        required property int index
                        readonly property int chosen: modelData.offers.findIndex(offer => offer.value === modelData.value)

                        width: section.width
                        label: modelData.label
                        warning: modelData.problem !== "" ? modelData.problem : modelData.description
                        warningTone: modelData.problem !== "" ? "warning" : "muted"

                        // A value its plugin could not read is no offer:
                        // the picker says so and takes no choice, and the
                        // row's line gives the reason.
                        Select {
                            id: picker
                            width: parent.width
                            model: eventRow.modelData.offers
                            textRole: "label"
                            currentIndex: eventRow.chosen
                            placeholderText: "Not available"
                            enabled: eventRow.chosen !== -1
                            Accessible.name: eventRow.label
                            // The binding comes back after a choice, so
                            // the saved value is what shows.
                            onActivated: index => {
                                const offer = eventRow.modelData.offers[index];
                                currentIndex = Qt.binding(() => eventRow.chosen);
                                root.choose(eventRow.modelData, offer);
                            }
                            Component.onCompleted: if (section.index === 0 && eventRow.index === 0) root.firstPicker = picker
                        }

                        // Test draws on the row's line, so every picker
                        // fills the value column, and only while the
                        // choice plays a sound.
                        action: RowAction {
                            visible: eventRow.modelData.testable && eventRow.chosen !== -1 && eventRow.modelData.offers[eventRow.chosen].playable
                            text: "Test"
                            Accessible.name: "Test " + eventRow.label
                            onClicked: root.test(eventRow.modelData.value)
                        }
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
