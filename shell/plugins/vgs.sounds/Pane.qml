import QtQuick
import qs.Commons
import qs.Ui

// Sounds pane: every sound event the enabled plugins declare, under its
// plugin's name, each with a picker of the core's sounds, Off first, and
// Test, which plays the chosen sound. A choice is saved as it is made and
// plays once, so the user picks by ear. An event its plugin sounds itself
// offers Off and that plugin's own sound, with no Test: the core has no
// file to play for it. The events, the sounds and the one write are the
// `soundSettings` capability's; the pane holds the layout alone.
FocusScope {
    id: root

    property var shell: null
    property string problem: ""
    readonly property var sounds: shell === null ? null : shell.soundSettings
    readonly property var events: sounds === null ? [] : sounds.events
    readonly property var library: sounds === null ? [] : sounds.library
    // The plugins and their event names, as text: it changes only when an
    // event joins or leaves, so a choice, which replaces `events`, rebuilds
    // no row and the picker in use keeps the keyboard.
    readonly property string shape: JSON.stringify(groupsOf(events))
    readonly property var groups: JSON.parse(shape)
    property Item firstPicker: null
    readonly property Item initialFocus: firstPicker !== null ? firstPicker : root

    function open(payloadJson) {}
    function close() {}

    // [{ id, plugin, events: [name] }] in the order `events` lists them.
    function groupsOf(rows) {
        const out = [];
        for (const row of rows) {
            if (out.length === 0 || out[out.length - 1].id !== row.id) out.push({ id: row.id, plugin: row.plugin, events: [] });
            out[out.length - 1].events.push(row.event);
        }
        return out;
    }

    function rowOf(id, event) {
        return events.find(row => row.id === id && row.event === event) || null;
    }

    // What ROW's picker offers, { value, label }: Off, then the plugin's
    // own sound or the core's sounds.
    function offersOf(row) {
        const off = [{ value: "", label: "Off" }];
        if (row === null) return off;
        return off.concat(row.own !== "" ? [{ value: "own", label: row.own }] : library.map(sound => ({ value: sound.id, label: sound.label })));
    }

    function choose(row, value) {
        const reply = sounds.choose(row.id, row.event, value);
        problem = reply === "ok" ? "" : "VGS could not save this setting.";
        if (reply !== "ok") console.warn("sounds: choose " + reply);
        else if (value !== "" && row.own === "") test(value);
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

        Repeater {
            model: root.groups

            Column {
                id: group

                required property var modelData
                required property int index

                width: content.width
                spacing: Theme.stack.group

                SectionHeader {
                    width: parent.width
                    text: group.modelData.plugin
                }

                Column {
                    width: parent.width
                    spacing: Theme.stack.row

                    Repeater {
                        model: group.modelData.events

                        FormRow {
                            id: eventRow

                            required property string modelData
                            required property int index
                            readonly property var row: root.rowOf(group.modelData.id, modelData)
                            readonly property var offers: root.offersOf(row)
                            readonly property int chosen: row === null ? -1 : offers.findIndex(offer => offer.value === row.value)

                            width: parent.width
                            label: row === null ? "" : row.label
                            warning: row === null ? "" : row.description
                            warningTone: "muted"

                            Row {
                                spacing: Theme.stack.inline

                                Select {
                                    id: picker
                                    model: eventRow.offers
                                    textRole: "label"
                                    currentIndex: eventRow.chosen
                                    Accessible.name: eventRow.label
                                    // The binding comes back after a choice,
                                    // so the saved value is what shows.
                                    onActivated: index => {
                                        const value = eventRow.offers[index].value;
                                        currentIndex = Qt.binding(() => eventRow.chosen);
                                        root.choose(eventRow.row, value);
                                    }
                                    Component.onCompleted: if (group.index === 0 && eventRow.index === 0) root.firstPicker = picker
                                }

                                RowAction {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: eventRow.row !== null && eventRow.row.own === ""
                                    enabled: eventRow.row !== null && eventRow.row.value !== ""
                                    text: "Test"
                                    Accessible.name: "Test " + eventRow.label
                                    onClicked: root.test(eventRow.row.value)
                                }
                            }
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
