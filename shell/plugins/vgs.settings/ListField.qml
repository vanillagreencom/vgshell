import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// The editor of one `list` schema entry (Pads.js): one group per item, its
// name beside a Remove action and each of its fields drawn by SettingField
// as the page draws a flat entry, and an Add action, which appends an item
// of the entry's `defaults` under the lowest whole number no item names.
// Every edit sends the whole list through `apply`, which the page writes
// through the manager's set-setting path, so the configuration's judge
// sees each change and a refused one leaves the drawn list as it was.
// `edits` is the page's set of unsaved edits, which each item field joins
// while its text editor holds one.
Column {
    id: root

    property string pluginId: ""
    property string key: ""
    property var spec: ({})
    property var value: []
    // One { field: Select model } per item, in order: the manager row's
    // `settingChoices` for this key.
    property var choices: []
    property bool editable: true
    property var edits: null
    signal apply(var value)

    readonly property var items: Array.isArray(value) ? value : []
    readonly property var fields: spec.items === undefined ? [] : Object.keys(spec.items)

    width: parent === null ? implicitWidth : parent.width
    spacing: Theme.stack.row

    // The lowest whole number, as text, that no item names.
    function freshName() {
        let n = 1;
        while (items.some(item => item.name === String(n))) n += 1;
        return String(n);
    }
    function add() {
        apply(items.concat([Object.assign({ name: freshName() }, JSON.parse(JSON.stringify(spec.defaults)))]));
    }
    function remove(name) {
        apply(items.filter(item => item.name !== name));
    }
    function setField(name, field, fieldValue) {
        apply(items.map(item => {
            if (item.name !== name) return item;
            const next = Object.assign({}, item);
            next[field] = fieldValue;
            return next;
        }));
    }

    GroupList {
        id: groups
        width: root.width
        visible: root.items.length > 0

        Repeater {
            model: ScriptModel {
                values: root.items
                objectProp: "name"
            }
            Column {
                id: itemGroup
                required property var modelData
                required property int index
                width: groups.width
                spacing: Theme.stack.row

                Field {
                    width: itemGroup.width
                    label: "Name"
                    inline: true
                    Row {
                        spacing: Theme.stack.inline
                        Label {
                            role: "value"
                            text: itemGroup.modelData.name
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        RowAction {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Remove"
                            tone: "danger"
                            enabled: root.editable
                            onClicked: root.remove(itemGroup.modelData.name)
                        }
                    }
                }

                Repeater {
                    model: root.fields
                    SettingField {
                        required property string modelData
                        width: itemGroup.width
                        key: modelData
                        spec: root.spec.items[modelData]
                        value: itemGroup.modelData[modelData]
                        choices: root.choices[itemGroup.index] === undefined || root.choices[itemGroup.index][modelData] === undefined ? [] : root.choices[itemGroup.index][modelData]
                        editable: root.editable
                        edits: root.edits
                        onApply: v => root.setField(itemGroup.modelData.name, modelData, v)
                    }
                }
            }
        }
    }

    Field {
        width: root.width
        label: root.items.length === 0 ? "None yet" : ""
        inline: true
        RowAction {
            text: "Add"
            enabled: root.editable
            onClicked: root.add()
        }
    }
}
