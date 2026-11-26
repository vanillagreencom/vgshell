import QtQuick
import qs.Commons
import qs.Ui

// The in-page form of a `rows` entry that declares `editor`
// (PluginLogic.statusRowsEditorError), open for `form`, the plugin's
// judged open (PluginLogic.editorOpenRequest): a heading, the choice field,
// a Select of `choices`, or the chosen one as plain text while `fixed`,
// the name field, which starts as the plugin's name or the chosen
// choice's label and follows the choice until the user types, plain text
// for an edit, and the masked secret field, always empty when the form
// opens, with Save and Cancel. A choice that carries `link` offers it
// under the fields as "Open <link text>", which opens it through
// `openLink`; nothing else here opens a page. Save, or Enter in the
// secret field, emits `save` with the form and the typed secret; the
// field is cleared as the save starts, so no typed secret stays in the
// form past it, and the form is destroyed when its owner closes it.
// `error` reads under the fields while the owner keeps the form after a
// failed save; `saving` disables both buttons while a save runs.
Column {
    id: root

    required property var editor
    required property var choices
    required property var form
    property string error: ""
    property bool saving: false

    signal save(var form, string secret)
    signal cancel(var form)
    signal openLink(var link)

    spacing: Theme.stack.row

    property string chosen: form.choice
    readonly property int chosenIndex: choices.findIndex(item => item.value === chosen)
    readonly property var chosenItem: chosenIndex === -1 ? null : choices[chosenIndex]
    // Whether the user typed a name, which a later choice keeps.
    property bool named: form.name !== ""
    readonly property string editing: form.row
    readonly property string name: nameField.text.trim()
    readonly property bool canSave: !saving && chosenItem !== null && name !== "" && secretField.text !== "" && !/[\r\n]/.test(secretField.text)

    function submit() {
        if (!canSave) return;
        const secret = secretField.text;
        secretField.clear();
        root.save({ row: form.row, choice: chosen, name: name, target: form.target }, secret);
    }

    // A new open, the first or one that replaces the shown form, starts
    // the fields again, the secret empty, and puts the keyboard on the
    // first field the user fills.
    function start() {
        chosen = form.choice;
        named = form.name !== "";
        secretField.clear();
        nameField.text = form.name !== "" ? form.name : chosenItem === null ? "" : chosenItem.label;
        if (form.fixed && form.row !== "") secretField.forceActiveFocus(Qt.TabFocusReason);
        else if (form.fixed) nameField.forceActiveFocus(Qt.TabFocusReason);
        else picker.forceActiveFocus(Qt.TabFocusReason);
    }
    Component.onCompleted: start()
    onFormChanged: if (nameField !== null) start()
    Component.onDestruction: secretField.clear()

    Label {
        width: root.width
        role: "bodyStrong"
        text: root.form.title !== "" ? root.form.title : root.editing !== "" ? "Replace the key of " + root.form.name : "Add API key"
        wrapMode: Text.Wrap
    }

    FormRow {
        width: root.width
        visible: !root.form.fixed
        label: root.editor.choice
        Select {
            id: picker
            model: root.choices
            textRole: "label"
            currentIndex: root.chosenIndex
            placeholderText: "Choose a provider"
            onActivated: index => {
                root.chosen = root.choices[index].value;
                if (!root.named) nameField.text = root.choices[index].label;
            }
        }
    }
    FormRow {
        width: root.width
        visible: root.form.fixed
        label: root.editor.choice
        Label {
            role: "value"
            text: root.chosenItem === null ? "" : root.chosenItem.label
        }
    }

    // An edit keeps the row's name: it reads as text in place of the field.
    FormRow {
        width: root.width
        visible: root.editing === ""
        label: root.editor.name
        TextField {
            id: nameField
            maximumLength: 80
            onTextEdited: root.named = true
            onAccepted: secretField.forceActiveFocus(Qt.TabFocusReason)
        }
    }
    FormRow {
        width: root.width
        visible: root.editing !== ""
        label: root.editor.name
        Label {
            role: "value"
            text: root.form.name
        }
    }

    FormRow {
        width: root.width
        label: root.editor.secret
        warning: root.editing !== "" ? "The saved key stays until you save a replacement" : ""
        warningTone: "muted"
        TextField {
            id: secretField
            password: true
            leadingIcon: "key-round"
            placeholderText: root.editor.secret
            onAccepted: root.submit()
            Keys.onEscapePressed: event => {
                root.cancel(root.form);
                event.accepted = true;
            }
        }
    }

    LinkText {
        width: root.width
        visible: root.chosenItem !== null && root.chosenItem.link !== undefined
        role: "body"
        text: root.chosenItem === null || root.chosenItem.link === undefined ? "" : "Open " + root.chosenItem.link.text
        link: text
        wrapMode: Text.Wrap
        onActivated: root.openLink(root.chosenItem.link)
    }

    Label {
        width: root.width
        visible: text !== ""
        role: "hint"
        color: Theme.color.danger
        text: root.error
        wrapMode: Text.Wrap
    }

    Row {
        spacing: Theme.stack.inline
        Button {
            variant: "primary"
            text: root.form.target !== "" ? "Save and use" : "Save"
            disabledReason: root.saving ? "The key is being saved" : root.canSave ? "" : root.chosenItem === null ? "Choose a provider first"
                : root.name === "" ? "Enter a name first" : "Paste the key first"
            onClicked: root.submit()
        }
        Button {
            variant: "secondary"
            text: "Cancel"
            disabledReason: root.saving ? "Wait for the save to end" : ""
            onClicked: root.cancel(root.form)
        }
    }
}
