import QtQuick
import QtQuick.Templates as T
import qs.Commons
import qs.Ui

// The editor of one number setting, from its schema entry `spec`, and the
// value the configuration holds, `value`. Presets use Select; when custom
// values are allowed, Custom… follows them, and a value no preset holds
// shows under it in the custom row, a Slider for a bounded number, else a
// text field. A bounded number with no presets uses Slider, and one with
// neither presets nor bounds a text field. A unit makes the value read as
// a quantity (SettingValues.quantityText).
//
// A Select or a Slider writes at once, through `apply`, and writes nothing
// for the value held. A text field keeps what is typed until it is saved:
// Enter in it writes it, a loss of focus writes nothing, and Escape puts
// back what the configuration holds. `edited` says a text field holds a
// text the configuration does not, `save()` writes it and `discard()` puts
// the configuration's back; a read-only field and a hidden custom row
// hold none. A text the setting's owner refuses stays in its field, so the
// field stays edited; one it accepts reads `wrote()`. The custom row that
// Custom… opens is brought into view by the nearest enclosing ScrollArea.
//
// `label`, `hint`, `info`, `tooltip` and `hintLink` default to the entry's
// `label`, `description`, `info`, `tooltip` and `link` words; `problem` is
// the error line. A set `disabledReason` locks the Select with it
// (DisabledReason) and disables the Slider, which takes no reason. A
// description's link activates `hintLinkActivated`, and a page reference
// in the description or the info dialog `pageActivated`. The column ends
// in its last shown row's description or error line, which takes the room
// a Field takes under it (`subText`).
//
// DraftField, the text field of a draft, is the one a string setting's
// editor composes too (NumberSettingField.DraftField): `field` gives it
// `heldText`, `editable` and `save()`.
Column {
    id: root

    property var spec: ({})
    property var value
    property bool editable: true
    property string problem: ""
    property string label: spec.label !== undefined ? String(spec.label) : ""
    property string hint: spec.description !== undefined ? String(spec.description) : ""
    property string info: spec.info !== undefined ? String(spec.info) : ""
    property string tooltip: spec.tooltip !== undefined ? String(spec.tooltip) : ""
    property string hintLink: spec.link !== undefined ? spec.link.text : ""
    property string disabledReason: ""
    // A reading the user should act on, drawn in place of the hint in the
    // warning colour (Field `hintTone`).
    property string warning: ""
    property bool customChosen: false
    // The custom editor appeared and waits to be brought into view.
    property bool revealPending: false
    readonly property bool bounded: spec.min !== undefined && spec.max !== undefined
    // A list-like `presets`, as a spec read through a view's modelData
    // holds it (SettingValues.presetRows).
    readonly property bool hasPresets: spec.presets !== undefined && spec.presets !== null && typeof spec.presets.length === "number"
    readonly property bool allowCustom: hasPresets && spec.allowCustom === true
    // The Select's rows: the presets, then Custom…. No row reads the value,
    // so a write rebuilds none.
    readonly property var presetModel: hasPresets ? SettingValues.presetRows(spec, allowCustom, null) : []
    readonly property int selectedOfferIndex: SettingValues.presetIndex(spec, value)
    readonly property bool customVisible: allowCustom && (customChosen || selectedOfferIndex < 0)
    // What the configuration holds, as a text field shows it.
    readonly property string heldText: value === undefined ? "" : String(value)
    readonly property bool edited: editing(loader.item) || editing(customLoader.item)
    readonly property bool subText: (customVisible ? customField : primary).subText
    // A key/value row: the row under it stands by ink (Field).
    readonly property bool keyValueRow: true
    signal apply(var value)
    // A typed value the owner accepted: the draft now reads it.
    signal wrote()
    signal hintLinkActivated()
    signal pageActivated(string page, string tab)

    width: parent === null ? implicitWidth : parent.width
    spacing: Theme.field.gap
    bottomPadding: Theme.subTextRoom(subText, Positioner.index, Positioner.isLastItem, parent)

    onEditableChanged: if (!editable) discard()
    onValueChanged: if (selectedOfferIndex >= 0) customChosen = false
    onCustomVisibleChanged: if (!customVisible && editing(customLoader.item)) customLoader.item.revert()
    // The custom editor shows once this column has placed it
    // (Column.positioningComplete). The columns around it and the scroll
    // area's content height settle in the same polish pass, so the reveal
    // waits for the next turn (Qt.callLater) and reads them settled.
    // callLater guards a method by its object and keys it by object and
    // method (Qt 6.9 qqmldelayedcallqueue.cpp), so a destroyed field is
    // never called and each field keeps its own call.
    onPositioningComplete: {
        if (!revealPending) return;
        revealPending = false;
        Qt.callLater(root.revealCustom);
    }

    function displayNumber(v) { return spec.unit === undefined ? String(v) : SettingValues.quantityText(v, spec.unit); }
    // Only the user's Custom… choice brings the row into view: a custom
    // value the field loads with, or another page writes, moves no page,
    // as Power's section, which a reveal would scroll from the row the
    // user works on.
    function chooseCustom() {
        if (!editable || disabledReason !== "") return;
        revealPending = !customVisible;
        customChosen = true;
    }
    // The nearest enclosing ScrollArea scrolls the least distance that
    // shows the custom editor; a field outside one has nothing to scroll.
    function revealCustom() {
        if (!customVisible || !editable) return;
        for (let at = parent; at !== null; at = at.parent) {
            if (typeof at.reveal === "function") {
                at.reveal(customField);
                return;
            }
        }
    }
    function editing(editor) { return editor !== null && editor.edited === true; }
    function save() {
        for (const editor of [loader.item, customLoader.item]) if (editing(editor)) editor.save();
    }
    function discard() {
        for (const editor of [loader.item, customLoader.item]) if (editing(editor)) editor.revert();
    }
    // Write the text of `input`. The owner's reply comes back before
    // `apply` returns, so the value is the typed one exactly when the write
    // was accepted; the field then shows what the configuration holds.
    function commit(input) {
        const typed = SettingValues.typedNumber(input.text);
        apply(typed);
        if (typed !== value) return;
        input.text = heldText;
        wrote();
    }

    Field {
        id: primary
        width: root.width
        label: root.label
        info: root.info
        labelTooltip: root.tooltip
        hint: root.customVisible ? "" : root.warning !== "" ? root.warning : root.hint
        hintLink: root.customVisible || root.warning !== "" ? "" : root.hintLink
        hintTone: root.warning !== "" ? "warning" : ""
        error: root.problem
        inline: true
        onHintLinkActivated: root.hintLinkActivated()
        onHintPageActivated: (page, tab) => root.pageActivated(page, tab)
        onInfoPageActivated: (page, tab) => root.pageActivated(page, tab)

        Loader {
            id: loader
            width: parent.width
            sourceComponent: root.hasPresets ? presetChoice : root.bounded ? slider : text
        }
    }

    Field {
        id: customField
        width: root.width
        visible: root.customVisible
        label: ""
        hint: root.warning !== "" ? root.warning : root.hint
        hintLink: root.warning !== "" ? "" : root.hintLink
        hintTone: root.warning !== "" ? "warning" : ""
        onHintLinkActivated: root.hintLinkActivated()
        onHintPageActivated: (page, tab) => root.pageActivated(page, tab)
        inline: true

        Loader {
            id: customLoader
            width: parent.width
            active: root.allowCustom
            sourceComponent: root.bounded ? slider : customText
        }
    }

    // The text field of a draft: it keeps what is typed until it is saved.
    // It shows the field's `heldText` at first and again whenever that
    // changes, and no binding holds the text, so a draft outlives every
    // other change. `edited` says the text is not the held one, `revert()`
    // and Escape put the held one back, and Enter saves the field.
    component DraftField: TextField {
        id: draft
        required property Item field
        readonly property bool edited: text !== field.heldText
        function revert() { text = field.heldText; }
        readOnly: !field.editable
        escapeReverts: true
        committedText: field.heldText
        onAccepted: field.save()
        Component.onCompleted: text = field.heldText
        Connections {
            target: draft.field
            function onHeldTextChanged() { draft.text = draft.field.heldText; }
        }
    }

    Component {
        id: text
        DraftField {
            id: input
            function save() { root.commit(input); }
            field: root
            width: parent.width
            focusPolicy: root.editable ? Qt.StrongFocus : Qt.NoFocus
        }
    }

    // The custom row's text keeps its focus while the field turns
    // read-only: Qt refuses a focus policy change of the active focus item.
    Component {
        id: customText
        DraftField {
            id: input
            function save() { root.commit(input); }
            field: root
            width: parent.width
        }
    }

    Component {
        id: presetChoice
        Select {
            readonly property int shownIndex: root.selectedOfferIndex >= 0 ? root.selectedOfferIndex : root.allowCustom ? root.presetModel.length - 1 : -1
            width: parent.width
            model: root.presetModel
            textRole: "label"
            currentIndex: shownIndex
            enabled: root.editable
            disabledReason: root.disabledReason
            onActivated: index => {
                const chosen = root.presetModel[index];
                currentIndex = Qt.binding(() => shownIndex);
                if (chosen.custom === true) {
                    root.chooseCustom();
                    return;
                }
                root.customChosen = false;
                if (chosen.value !== root.value) root.apply(chosen.value);
            }
        }
    }

    Component {
        id: slider
        Item {
            id: sliderRow
            width: parent.width
            implicitHeight: Math.max(bar.implicitHeight, shown.implicitHeight)

            // The slider and its value centre in the row: the lower of
            // their drawn bottoms ends it (Theme.inkBelow), the higher of
            // their drawn tops starts it (Theme.inkAbove).
            readonly property real inkBelow: height - Math.max(bar.y + bar.height - bar.inkBelow, shown.y + shown.height - shown.inkBelow)
            readonly property real inkAbove: Math.min(bar.y + bar.inkAbove, shown.y + shown.inkAbove)

            function commit() {
                const wanted = bar.value;
                bar.value = Qt.binding(() => typeof root.value === "number" ? root.value : bar.from);
                if (wanted !== root.value) root.apply(wanted);
            }

            Slider {
                id: bar
                width: parent.width - shown.width - Theme.field.labelGap
                anchors.verticalCenter: parent.verticalCenter
                from: root.spec.min
                to: root.spec.max
                stepSize: root.spec.step === undefined ? 0 : root.spec.step
                snapMode: root.spec.step === undefined ? T.Slider.NoSnap : T.Slider.SnapAlways
                // A value that is no number, as a field that loses its
                // owner holds a moment before its row goes, stands at the
                // start instead of failing to assign.
                value: typeof root.value === "number" ? root.value : from
                enabled: root.editable && root.disabledReason === ""
                onPressedChanged: if (!pressed) sliderRow.commit()
                onMoved: if (!pressed) sliderRow.commit()
            }
            Label { id: minProbe; visible: false; role: "label"; text: root.displayNumber(root.spec.min) }
            Label { id: maxProbe; visible: false; role: "label"; text: root.displayNumber(root.spec.max) }
            Label {
                id: shown
                role: "label"
                text: root.displayNumber(bar.value)
                width: Math.max(implicitWidth, minProbe.implicitWidth, maxProbe.implicitWidth, Theme.size.control.lg)
                horizontalAlignment: Text.AlignRight
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
}
