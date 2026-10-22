import QtQuick
import qs.Commons
import qs.Ui

// One read-only line of a Status row: `label` beside its value, the line's
// one-click setup step (D061) as a RowAction right after the value, or
// under it where the two do not fit one line, and `hint` under them, the
// words of it `hintLink` names drawn as a link that emits
// `hintLinkActivated`, or a page reference in it (LinkText) as a link
// that emits `hintPageActivated`; a page reference in the label's `info`
// emits `infoPageActivated`. The value is a
// Badge reading `text` in `tone`, with one more Badge of that tone under it for each of `lines`,
// each no wider than the value column, eliding a text too long for it; with
// `tone` "", `text` as one line in the value role, the label's pair,
// or the itemHint role while `muted`; with neither, the hint itself on the
// label's row, its `hintLink` words still a link, so a line that names a
// group never leaves its value column empty. Its lines sit `field.gap` apart: one group of the row's GroupList.
//
// The step is one of: `actionLabel` while `actionOffered`, an action in
// `actionTone`, a danger one led by the mark `actionIcon` names or by the
// trash mark, that emits `act`, with `asideLabel` while `asideOffered`
// after it, in `asideTone` with `asideIcon`, which emits `aside`; or, for
// a line that is the presence of a secret, by `access`: `connect`, an Add key action, and `disconnect`, a
// Replace action before a Remove action in the danger tone that emits
// `clearSecret`. Add key and Replace open a masked field in the value slot
// whose Save, or Enter, emits `storeSecret` with what was typed and closes
// it. A line with no
// value, such as a secret nothing is stored for, starts its step on the
// value column. `busy` disables the step while its write runs; `error`,
// when set, reads in the hint's place in the error colour. A line that ends
// in a hint, lines or an error takes the room under it a Field takes
// (Theme.subTextRoom), `subText`.
Column {
    id: line

    property string label: ""
    property string hint: ""
    property string hintLink: ""
    property string info: ""
    property string tone: ""
    property string text: ""
    property var lines: []
    property bool plainLines: false
    property bool muted: false
    property string actionLabel: ""
    property bool actionOffered: false
    // "" or "danger", the declared action's tone (PluginLogic.statusRowAction).
    property string actionTone: ""
    // The mark a danger action leads with, "" for the trash mark
    // (PluginLogic.statusActionIcon).
    property string actionIcon: ""
    property string access: ""
    property string asideLabel: ""
    property bool asideOffered: false
    property string asideTone: ""
    property string asideIcon: ""
    property bool busy: false
    property string error: ""
    // What the masked field asks for: the plugin's `secrets` label.
    property string secretLabel: ""
    // Whether the masked field is open.
    property bool entering: false
    // What the line offers for its secret: Add key, or Replace and Remove.
    readonly property bool adds: access === "connect"
    readonly property bool stored: access === "disconnect"
    readonly property bool stepShown: (actionLabel !== "" && actionOffered) || asideOffered || adds || stored
    readonly property bool subText: field.subText

    signal act()
    signal aside()
    signal hintLinkActivated()
    signal hintPageActivated(string page, string tab)
    signal infoPageActivated(string page, string tab)
    signal storeSecret(string value)
    signal clearSecret()

    // The secret's presence changed under an open field, so what the
    // field was opened for no longer holds.
    onAccessChanged: {
        // The writer ends before the plugin's presence probe publishes. If
        // Add key still owns focus, hand it to Replace as presence changes;
        // a publish after focus moved elsewhere must not take it back.
        const actionFocused = addKey.activeFocus || replaceKey.activeFocus;
        entering = false;
        if (actionFocused) restoreActionFocus();
    }
    onVisibleChanged: if (!visible) {
        entering = false;
        // Invisible Qt Quick items can retain keyboard focus. Reopening a
        // retained page must not revive its earlier save interaction.
        // https://doc.qt.io/qt-6/qml-qtquick-item.html#visible-prop
        if (activeFocus) focus = false;
    }
    onBusyChanged: if (!busy && activeFocus) restoreActionFocus()

    function restoreActionFocus() {
        if (visible && !busy && (access === "connect" || access === "disconnect"))
            (access === "connect" ? addKey : replaceKey).forceActiveFocus(Qt.TabFocusReason);
    }

    function canSave(value) {
        return entering && !busy && value !== "" && !/[\r\n]/.test(value);
    }

    function cancelEntry() {
        entering = false;
        restoreActionFocus();
    }

    // Close the field, which destroys it and what it held, then hand VALUE
    // on.
    function saveSecret(value) {
        if (!canSave(value)) return;
        entering = false;
        // While the action is disabled, this row holds the save interaction's
        // focus. Moving to another control ends that ownership naturally;
        // completion restores an action only if the user stayed here.
        forceActiveFocus(Qt.TabFocusReason);
        storeSecret(value);
        if (!busy && activeFocus) restoreActionFocus();
    }

    spacing: Theme.field.gap
    bottomPadding: Theme.subTextRoom(subText, Positioner.index, Positioner.isLastItem, parent)

    readonly property bool valued: tone !== "" || text !== ""

    Field {
        id: field
        width: line.width
        label: line.label
        info: line.info
        onInfoPageActivated: (page, tab) => line.infoPageActivated(page, tab)
        inline: true
        hint: line.valued || line.entering ? line.hint : ""
        hintLink: line.hintLink
        onHintLinkActivated: line.hintLinkActivated()
        onHintPageActivated: (page, tab) => line.hintPageActivated(page, tab)
        error: line.error
        lines: line.plainLines ? line.lines : []
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
            width: parent.width
            implicitHeight: line.entering ? form.height : valueRow.height
            function inkAbove() { return line.entering ? Theme.inkAbove(form) : valueRow.inkAbove(); }
            function inkBelow() { return line.entering ? Theme.inkBelow(form) : valueRow.inkBelow(); }
            Item {
                id: valueRow
                visible: !line.entering
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
                // Where the value or the step beside it starts and ends to
                // draw, so a GroupList centres its hairline on what the line
                // shows.
                function inkAbove() {
                    const top = value.y + Theme.inkAbove(value);
                    return step.visible ? Math.min(top, step.y + Theme.inkAbove(step)) : top;
                }
                function inkBelow() {
                    const bottom = value.y + value.height - Theme.inkBelow(value);
                    return height - (step.visible ? Math.max(bottom, step.y + step.height - Theme.inkBelow(step)) : bottom);
                }
                width: parent.width
                implicitHeight: stepBelow ? value.height + Theme.field.gap + step.height : Math.max(value.y + value.height, step.visible ? step.y + step.height : 0)
                // The hint role's face, which a hint drawn as the value takes;
                // its LinkText reports the control's font, not its text's.
                Label {
                    id: hintFace
                    role: "hint"
                    visible: false
                }
                TextMetrics {
                    id: valueText
                    // The text's own font once it is built, the hint role's for
                    // a hint; a chip value measures no text.
                    font: line.tone === "" && line.text === "" ? hintFace.font
                        : value.item !== null && value.item.font !== undefined ? value.item.font : Qt.font({ family: Theme.text.value.family, pixelSize: Theme.text.value.size })
                    text: line.tone !== "" ? "" : line.text !== "" ? line.text : line.hint
                }
                Loader {
                    id: value
                    y: valueRow.stepBelow ? 0 : Math.round(valueRow.centre - valueRow.firstLine / 2)
                    sourceComponent: line.tone !== "" ? badge : line.text !== "" ? plain : line.hint !== "" ? hintValue : null
                }
                // RowActions places only its visible actions, so a line draws
                // the steps that apply to it alone.
                Row {
                    id: step
                    x: valueRow.stepBelow ? 0 : value.width > 0 ? value.width + Theme.stack.inline : 0
                    y: valueRow.stepBelow ? value.height + Theme.field.gap : Math.round(valueRow.centre - height / 2)
                    spacing: Theme.stack.inline
                    visible: line.stepShown && !line.entering
                    RowActions {
                        anchors.verticalCenter: parent.verticalCenter
                        RowAction {
                            visible: line.actionLabel !== "" && line.actionOffered
                            enabled: !line.busy
                            text: line.actionLabel
                            tone: line.actionTone === "danger" ? "danger" : "accent"
                            markName: line.actionIcon
                            onClicked: line.act()
                        }
                        RowAction {
                            visible: line.asideOffered
                            enabled: !line.busy
                            text: line.asideLabel
                            tone: line.asideTone === "danger" ? "danger" : "accent"
                            markName: line.asideIcon
                            onClicked: line.aside()
                        }
                        RowAction {
                            id: addKey
                            visible: line.adds
                            enabled: !line.busy
                            text: "Add key"
                            onClicked: line.entering = true
                        }
                        RowAction {
                            id: replaceKey
                            visible: line.stored
                            enabled: !line.busy
                            text: "Replace"
                            onClicked: line.entering = true
                        }
                        RowAction {
                            visible: line.stored
                            enabled: !line.busy
                            text: "Remove"
                            tone: "danger"
                            onClicked: line.clearSecret()
                        }
                    }
                }
            }
            // The masked field of Add key and Replace, built while it is open
            // and destroyed on Save or Cancel, so a closed line holds no input and a
            // typed secret outlives neither. What is typed stays in the field
            // alone until Save hands it to the core, which stores it through
            // libsecret.
            Loader {
                id: form
                width: parent.width
                active: line.entering
                visible: active
                // Qt Loader releases its item when inactive; the store signal's
                // unit test reads item === null synchronously before the writer.
                // https://doc.qt.io/qt-6/qml-qtquick-loader.html#active-prop
                sourceComponent: Item {
                    readonly property bool below: secret.minimumWidth + Theme.stack.inline + editorActions.implicitWidth > width
                    implicitHeight: below ? secret.height + Theme.stack.row + editorActions.height : secret.height
                    Component.onCompleted: secret.forceActiveFocus()
                    TextField {
                        id: secret
                        width: parent.below ? form.width : form.width - editorActions.implicitWidth - Theme.stack.inline
                        password: true
                        leadingIcon: "key-round"
                        placeholderText: line.secretLabel
                        onAccepted: line.saveSecret(text)
                        Keys.onEscapePressed: event => {
                            line.cancelEntry();
                            event.accepted = true;
                        }
                    }
                    RowActions {
                        id: editorActions
                        width: parent.below ? form.width : implicitWidth
                        x: parent.below ? 0 : secret.width + Theme.stack.inline
                        y: parent.below ? secret.height + Theme.stack.row : Math.round((secret.height - height) / 2)
                        RowAction {
                            id: save
                            enabled: line.canSave(secret.text)
                            text: "Save"
                            onClicked: line.saveSecret(secret.text)
                        }
                        RowAction {
                            id: cancel
                            text: "Cancel"
                            onClicked: line.cancelEntry()
                        }
                    }
                }
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
                model: line.plainLines ? [] : line.lines
                Badge {
                    required property string modelData
                    width: Math.min(implicitWidth, valueRow.width)
                    text: modelData
                    tone: line.tone
                }
            }
        }
    }

    // The hint as the value, its `hintLink` words a link as a field's
    // hint draws them.
    Component {
        id: hintValue
        LinkText {
            role: "hint"
            text: line.hint
            link: line.hintLink
            color: Theme.text.hint.color
            width: Math.min(implicitWidth, valueRow.room)
            wrapMode: Text.Wrap
            onActivated: line.hintLinkActivated()
            onPageActivated: (page, tab) => line.hintPageActivated(page, tab)
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
