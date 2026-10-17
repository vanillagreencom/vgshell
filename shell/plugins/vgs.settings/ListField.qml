import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// The editor of one `list` schema entry (Pads.js): one group per item, each
// of its fields drawn by SettingField as the page draws a flat entry, with
// its Remove, the trash mark alone (RowAction's `removesItem`), right after
// the first field's value, and an Add action, which appends an item of the
// entry's `defaults` under the lowest whole number no item names. That
// number is the item's storage key and names nothing the user chose, so no
// row draws it.
// Every edit sends the whole list through `apply`, which the page writes
// through the manager's set-setting path, so the configuration's judge
// sees each change and a refused one leaves the drawn list as it was.
// `edits` is the page's set of unsaved edits, which each item field joins
// while its text editor holds one. A field's description link reaches
// the page through `openLink`, and its page reference through `openPage`.
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
    signal openLink(var link)
    signal openPage(string page, string tab)

    readonly property var items: Array.isArray(value) ? value : []
    readonly property var fields: spec.items === undefined ? [] : Object.keys(spec.items)
    // How far right of an item's left edge a field's value ends at most:
    // FormRow's value column, from the label column's end, bounded by
    // `control.maxWidth`, inside the field's `field.paddingX`.
    readonly property real valueEnd: Theme.field.paddingX + Theme.field.labelWidth + Theme.field.labelGap + Theme.control.maxWidth

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
            // One item: its fields in a column, and Remove beside it on the
            // first field's row, so the column keeps its rows and the ink
            // spacing between them. GroupList reads the column's ink.
            Item {
                id: itemGroup
                required property var modelData
                required property int index
                // Every field leaves room for Remove on its right, so the
                // item's values end on one edge.
                readonly property real fieldWidth: Math.max(0, width - remove.width - Theme.stack.inline)
                width: groups.width
                implicitHeight: itemFields.height

                function inkAbove() { return Theme.inkAbove(itemFields); }
                function inkBelow() { return Theme.inkBelow(itemFields); }

                Column {
                    id: itemFields
                    width: itemGroup.width
                    spacing: Theme.stack.row

                    Repeater {
                        model: root.fields
                        SettingField {
                            required property string modelData
                            width: itemGroup.fieldWidth
                            key: modelData
                            spec: root.spec.items[modelData]
                            value: itemGroup.modelData[modelData]
                            choices: root.choices[itemGroup.index] === undefined || root.choices[itemGroup.index][modelData] === undefined ? [] : root.choices[itemGroup.index][modelData]
                            editable: root.editable
                            edits: root.edits
                            onApply: v => root.setField(itemGroup.modelData.name, modelData, v)
                            onOpenLink: link => root.openLink(link)
                            onOpenPage: (page, tab) => root.openPage(page, tab)
                        }
                    }
                }

                // It centres in the first field's row box, `row.height` for
                // a label of one line, as FormRow centres a control, and
                // starts `stack.inline` after where that field's value ends.
                RowAction {
                    id: remove
                    x: Math.min(itemGroup.fieldWidth - Theme.field.paddingX, root.valueEnd) + Theme.stack.inline
                    y: Math.round((Theme.row.height - height) / 2)
                    text: "Remove"
                    removesItem: true
                    enabled: root.editable
                    onClicked: root.remove(itemGroup.modelData.name)
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
