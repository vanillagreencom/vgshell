import QtQuick
import qs.Commons
import qs.Ui

// One read-only line of a Status row: `label` beside its value, the line's
// one-click setup step (D061) as a RowAction right after the value, or
// under it where the two do not fit one line, and `hint` under them, the
// words of it `hintLink` names drawn as a link that emits
// `hintLinkActivated`. The value is a
// Badge reading `text` in `tone`, with one more Badge of that tone under it for each of `lines`,
// each no wider than the value column, eliding a text too long for it; with
// `tone` "", `text` as one line in the value role, the label's pair,
// or the itemHint role while `muted`; with neither, the hint itself on the
// label's row, so a line that names a group never leaves its value column
// empty. Its lines sit `field.gap` apart: one group of the row's GroupList.
//
// The step is one of: `actionLabel` while `actionOffered`, an action that
// emits `act`; or, for a line that is the presence of a secret, by
// `access`: `connect`, a Connect action that opens a masked field under the
// line whose Save, or Enter, emits `storeSecret` with what was typed and
// closes it, and `disconnect`, a Disconnect action that emits
// `clearSecret`. `busy` disables the step while its write runs; `error`,
// when set, reads in the hint's place in the error colour.
Column {
    id: line

    property string label: ""
    property string hint: ""
    property string hintLink: ""
    property string info: ""
    property string tone: ""
    property string text: ""
    property var lines: []
    property bool muted: false
    property string actionLabel: ""
    property bool actionOffered: false
    property string access: ""
    property bool busy: false
    property string error: ""
    // What the masked field asks for: the plugin's `secrets` label.
    property string secretLabel: ""
    // Whether the masked field of a Connect is open.
    property bool connecting: false
    readonly property bool stepShown: (actionLabel !== "" && actionOffered) || access !== ""

    signal act()
    signal hintLinkActivated()
    signal storeSecret(string value)
    signal clearSecret()

    onAccessChanged: if (access !== "connect") cancelConnect()

    function cancelConnect() {
        connecting = false;
    }

    // Close the field, which destroys it and what it held, then hand VALUE
    // on.
    function saveSecret(value) {
        connecting = false;
        storeSecret(value);
    }

    spacing: Theme.field.gap

    readonly property bool valued: tone !== "" || text !== ""

    Field {
        id: field
        width: line.width
        label: line.label
        info: line.info
        inline: true
        hint: line.valued ? line.hint : ""
        hintLink: line.hintLink
        onHintLinkActivated: line.hintLinkActivated()
        error: line.error
        // The step stands right after the value, centred on the value's
        // first line, its chip or its text, while the two fit the value
        // column; past that, as for a long chip, the step goes under the
        // value, `field.gap` below it, from the value column, so the two
        // never overlap. The choice reads the value's natural width, the
        // chips' bounded to the value column or the whole text's in its own
        // font, never the width the value is then given beside a step, so
        // it does not depend on its own outcome. A long chip or text elides
        // and a hint wraps within the room it has, and the row grows with
        // it.
        Item {
            id: valueRow
            readonly property real naturalWidth: line.tone !== "" ? value.implicitWidth : Math.ceil(valueText.advanceWidth)
            readonly property bool stepBelow: step.visible && naturalWidth + Theme.stack.inline + step.implicitWidth > width
            // The height of the value's first line, a chip of the default
            // size or the whole text, and the centre that line shares with
            // a step beside it.
            readonly property real firstLine: line.tone !== "" ? Theme.badge.size.sm.height : value.height
            readonly property real centre: Math.max(firstLine, step.visible ? step.height : 0) / 2
            // The width a text value may take: the column, less a step
            // beside it.
            readonly property real room: width - (step.visible && !stepBelow ? step.width + Theme.stack.inline : 0)
            width: parent.width
            implicitHeight: stepBelow ? value.height + Theme.field.gap + step.height : Math.max(value.y + value.height, step.visible ? step.y + step.height : 0)
            TextMetrics {
                id: valueText
                // The text's own font once it is built; a chip value
                // measures no text.
                font: value.item !== null && value.item.font !== undefined ? value.item.font : Qt.font({ family: Theme.text.value.family, pixelSize: Theme.text.value.size })
                text: line.tone !== "" ? "" : line.text !== "" ? line.text : line.hint
            }
            Loader {
                id: value
                y: valueRow.stepBelow ? 0 : Math.round(valueRow.centre - valueRow.firstLine / 2)
                sourceComponent: line.tone !== "" ? badge : line.text !== "" ? plain : line.hint !== "" ? hintValue : null
            }
            RowActions {
                id: step
                x: valueRow.stepBelow ? 0 : value.width + Theme.stack.inline
                y: valueRow.stepBelow ? value.height + Theme.field.gap : Math.round(valueRow.centre - height / 2)
                visible: line.stepShown && !line.connecting
                RowAction {
                    visible: line.actionLabel !== "" && line.actionOffered
                    enabled: !line.busy
                    text: line.actionLabel
                    onClicked: line.act()
                }
                RowAction {
                    visible: line.access === "connect"
                    enabled: !line.busy
                    text: "Connect"
                    onClicked: line.connecting = true
                }
                RowAction {
                    visible: line.access === "disconnect"
                    enabled: !line.busy
                    text: "Disconnect"
                    onClicked: line.clearSecret()
                }
            }
        }
    }

    // The masked field of a Connect, built while it is open and destroyed
    // on Save or Cancel, so a line with no secret holds no input and a
    // typed secret outlives neither. What is typed stays in the field
    // alone until Save hands it to the core, which stores it through
    // libsecret.
    Loader {
        id: form
        x: field.valueX
        width: line.width - x - field.rightPadding
        active: line.connecting
        visible: active
        sourceComponent: Row {
            spacing: Theme.stack.inline
            Component.onCompleted: secret.forceActiveFocus()
            TextField {
                id: secret
                width: form.width - save.width - cancel.width - 2 * parent.spacing
                password: true
                leadingIcon: "key-round"
                placeholderText: line.secretLabel
                onAccepted: if (text !== "") line.saveSecret(text)
                Keys.onEscapePressed: event => {
                    line.cancelConnect();
                    event.accepted = true;
                }
            }
            Button {
                id: save
                enabled: secret.text !== "" && !line.busy
                text: "Save"
                variant: "primary"
                anchors.verticalCenter: parent.verticalCenter
                onClicked: line.saveSecret(secret.text)
            }
            Button {
                id: cancel
                text: "Cancel"
                variant: "ghost"
                anchors.verticalCenter: parent.verticalCenter
                onClicked: line.cancelConnect()
            }
        }
    }

    Component {
        id: badge
        Column {
            spacing: line.spacing
            // A chip wider than the value column elides rather than run
            // past the line's edge. It is bounded to the column, not to the
            // room a step beside it leaves, since a chip that does not fit
            // beside the step already puts the step under it.
            Badge { width: Math.min(implicitWidth, valueRow.width); text: line.text; tone: line.tone }
            Repeater {
                model: line.lines
                Badge {
                    required property string modelData
                    width: Math.min(implicitWidth, valueRow.width)
                    text: modelData
                    tone: line.tone
                }
            }
        }
    }

    Component {
        id: hintValue
        Label {
            role: "hint"
            text: line.hint
            width: Math.min(implicitWidth, valueRow.room)
            wrapMode: Text.Wrap
        }
    }

    Component {
        id: plain
        Label {
            role: line.muted ? "itemHint" : "value"
            text: line.text
            width: Math.min(implicitWidth, valueRow.room)
            elide: Text.ElideRight
        }
    }
}
