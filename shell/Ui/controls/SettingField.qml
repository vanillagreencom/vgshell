import QtQuick
import QtQuick.Templates as T
import qs.Commons
import qs.Ui

// Draw the least-effort editor for one schema entry. Booleans use Switch.
// Enums of at most three options use SegmentedControl because each choice
// fits in one row. Larger enums and status-fed strings use Select. Both
// draw an enum option's label and write its value. String
// and number presets use Select. A string's separator makes its presets
// independently checked menu entries that keep their joined string value.
// When custom values are allowed, Custom…
// follows the presets or the published choices, and a configured value no
// row holds shows under it; for a status-fed string "" is the unset value,
// never a custom one. A custom datetime string validates before it writes.
// A bounded number uses Slider, and a unit makes its value read as a
// quantity. A status-fed select whose entry declares `addChoice` ends its
// list with that entry, led by the plus mark, which asks the page to open
// the plugin's screen that adds an offer and stores nothing; one that
// declares `preview` draws a speaker button beside each offer, which asks
// the plugin to play it. An enum whose options form groups (PluginLogic.groupsOf, the
// manager row's `groups`) draws one segment per group; a group of one
// option stores it when pressed, and under the group of several a second
// row, labelled by the entry's `groupLabel`, chooses among them with a
// Select. Pressing that group's segment while another group's option is
// stored opens its list and stores nothing until a choice; the list
// closed with none puts the segments back.
//
// Every editor but a text one writes at once. A text editor keeps what is
// typed until it is saved: Enter in it writes it, a loss of focus writes
// nothing, and Escape puts back what the configuration holds. `edited` says
// a text editor holds a text the configuration does not, `save()` writes it
// and `discard()` puts the configuration's back. A text the manager
// refuses, or the custom editor's own check does, stays in its editor, so
// the field stays edited. `edits` is the page's set of unsaved edits
// (EditSet), which the field joins while edited and tells of each write
// of its text the manager accepted. A field that ends in a description or
// an error line takes the room a Field takes under it, as its own last row
// is last in this column and takes none. A description's `link`, which
// the manager judged (PluginLogic.linkError), draws as a link in it and
// asks the page to open it through `openLink`, and a page reference in
// the description (LinkText) asks for its page through `openPage`. A
// `tooltip` shows on hover and keyboard focus of the label.
Column {
    id: root

    property string pluginId: ""
    property string key: ""
    property var spec: ({})
    property var value
    property var choices: []
    // An enum's option groups, each { name, values } (PluginLogic.fieldRows).
    property var groups: []
    // The group whose segment was pressed while its list waits for a
    // choice, "" for none: the stored value's group draws otherwise.
    property string pendingGroup: ""
    readonly property int valueGroup: groups.findIndex(group => group.values.indexOf(value) !== -1)
    readonly property int shownGroup: pendingGroup !== "" ? groups.findIndex(group => group.name === pendingGroup) : valueGroup
    // The options of the shown group when it holds several, which the
    // group row's Select offers; none otherwise.
    readonly property var groupOptions: shownGroup < 0 || groups[shownGroup].values.length < 2 ? []
        : spec.options.filter(option => groups[shownGroup].values.indexOf(option.value) !== -1)
    // The manager row resolves the schema's problem from plugin status.
    property string problem: ""
    property bool editable: true
    property var edits: null
    property bool customChosen: false
    property var presetModel: []
    // The custom editor appeared and waits to be brought into view.
    property bool revealPending: false
    readonly property int segmentedLimit: 3 // More choices read better in a vertical Select list.
    readonly property bool bounded: spec.type === "number" && spec.min !== undefined && spec.max !== undefined
    readonly property bool hasPresets: spec.presets !== undefined && Array.isArray(spec.presets)
    readonly property bool multiple: spec.separator !== undefined
    readonly property var selectedTokens: multiple && heldText !== "" ? heldText.split(spec.separator) : []
    readonly property bool knownSelection: multiple && selectedTokens.every(token => offerIndex(token) >= 0)
    readonly property bool statusFed: spec.optionsFrom !== undefined
    // The row of an enum's options that holds the value, or -1.
    readonly property int optionIndex: spec.type === "enum" ? spec.options.findIndex(option => option.value === value) : -1
    readonly property bool allowCustom: (hasPresets || statusFed) && spec.allowCustom === true
    readonly property int selectedOfferIndex: offerIndex(value)
    readonly property bool customVisible: allowCustom && (customChosen || (multiple ? !knownSelection : selectedOfferIndex < 0 && !(statusFed && value === "")))
    readonly property string labelText: spec.label !== undefined ? String(spec.label) : key
    readonly property string hintText: spec.description !== undefined ? String(spec.description) : ""
    readonly property string infoText: spec.info !== undefined ? String(spec.info) : ""
    readonly property string tooltipText: spec.tooltip !== undefined ? String(spec.tooltip) : ""
    readonly property string linkText: spec.link !== undefined ? spec.link.text : ""
    // What the configuration holds, as a text editor shows it.
    readonly property string heldText: value === undefined ? "" : String(value)
    readonly property bool edited: editing(loader.item) || editing(customLoader.item)
    // Whether the field ends in a description or an error line, which
    // takes the room under it a Field takes (Theme.subTextRoom).
    readonly property bool subText: (customVisible ? customField : groupOptions.length > 0 && groupRow.item !== null ? groupRow.item : primary).subText
    // A key/value row: the row under it stands by ink (Field).
    readonly property bool keyValueRow: true
    signal apply(var value)
    signal openLink(var link)
    signal openPage(string page, string tab)
    // The select of a status-fed string opened: the page asks the plugin
    // to read its choices again.
    signal choicesWanted()
    // The entry's `addChoice` was chosen: the page opens its screen, which
    // adds an offer; the field stores nothing.
    signal addWanted()
    // The speaker beside the offer VALUE, its own id, was pressed
    // (`preview`): the page asks the plugin to play it; the field stores
    // nothing.
    signal previewWanted(var value)

    width: parent === null ? implicitWidth : parent.width
    spacing: Theme.field.gap
    bottomPadding: Theme.subTextRoom(subText, Positioner.index, Positioner.isLastItem, parent)

    Component.onCompleted: {
        rebuildPresetModel();
        revealPending = customVisible;
    }
    Component.onDestruction: if (edits !== null) edits.forget(root)
    onEditedChanged: if (edits !== null) edits.track(root)
    // A read-only field and a hidden custom row hold no edit.
    onEditableChanged: if (!editable) discard()
    onCustomVisibleChanged: {
        if (customVisible) {
            revealPending = true;
        }
        else if (editing(customLoader.item)) customLoader.item.revert();
    }
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
    onSpecChanged: rebuildPresetModel()
    onChoicesChanged: rebuildPresetModel()
    onValueChanged: {
        if (multiple ? knownSelection : offerIndex(value) >= 0) customChosen = false;
        if (loader.item === null || loader.item.listOpen !== true) rebuildPresetModel();
    }

    Connections {
        target: Time
        function onNowChanged() {
            if (root.spec.format === "datetime" && (loader.item === null || loader.item.listOpen !== true))
                root.rebuildPresetModel();
        }
    }

    function rebuildPresetModel() {
        if (!root.hasPresets) {
            presetModel = [];
            return;
        }
        const out = [];
        for (const preset of root.spec.presets) {
            out.push({ label: SettingValues.presetText(root.spec, preset, v => Qt.formatDateTime(Time.now, v)), value: preset.value, custom: false });
        }
        if (root.allowCustom) out.push({ label: "Custom…", value: root.value, custom: true });
        presetModel = out;
    }

    function sameValue(a, b) { return a === b; }
    // The row of the presets or the published choices that holds `v`, or -1.
    function offerIndex(v) {
        if (statusFed) return choices.findIndex(option => sameValue(option.value, v));
        if (!hasPresets) return -1;
        for (let i = 0; i < spec.presets.length; i++)
            if (sameValue(spec.presets[i].value, v)) return i;
        return -1;
    }
    function displayNumber(v) { return spec.unit === undefined ? String(v) : SettingValues.quantityText(v, spec.unit); }

    // Only the clicked token changes. Unknown tokens and their order survive.
    function togglePreset(token) {
        if (!editable) return;
        const next = selectedTokens.indexOf(token) >= 0 ? selectedTokens.filter(held => held !== token) : selectedTokens.concat([token]);
        root.apply(next.join(spec.separator));
    }

    // Lost status choices can expose a stored value without an edit.
    // Only an intentional Custom choice starts a draft.
    function chooseCustom() {
        if (!editable || customChosen) return;
        customChosen = true;
        if (!bounded && customLoader.item !== null && !editing(customLoader.item)) customLoader.item.prefill();
    }

    function openDescriptionLink() { openLink(spec.link); }
    function openDescriptionPage(page, tab) { openPage(page, tab); }
    // The nearest enclosing ScrollArea scrolls the least distance that
    // shows the custom editor; a field outside one has nothing to scroll.
    // Stopping a plugin removes its runtime choices. The exposed read-only
    // editor must leave the page at the Enabled switch the user pressed.
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
    // Write the text of `input`. The manager's rows come back before
    // `apply` returns, so the value is the typed one exactly when the write
    // was accepted; the editor then shows what the configuration holds, and
    // the set hears of the write.
    function commit(input) {
        const typed = spec.type === "number" ? (input.text.trim() === "" ? NaN : Number(input.text)) : input.text;
        apply(typed);
        if (!sameValue(typed, value)) return;
        input.text = heldText;
        if (edits !== null) edits.wrote();
    }

    Field {
        id: primary
        width: root.width
        label: root.labelText
        info: root.infoText
        labelTooltip: root.tooltipText
        hint: root.customVisible ? "" : root.hintText
        hintLink: root.customVisible ? "" : root.linkText
        error: root.problem
        inline: true
        onHintLinkActivated: root.openDescriptionLink()
        onHintPageActivated: (page, tab) => root.openDescriptionPage(page, tab)
        onInfoPageActivated: (page, tab) => root.openDescriptionPage(page, tab)

        Loader {
            id: loader
            width: parent.width
            sourceComponent: root.spec.type === "boolean" ? toggle
                : root.groups.length > 0 ? groupedSegments
                : root.spec.type === "enum" && root.spec.options.length <= root.segmentedLimit ? segmented
                : root.spec.type === "enum" || root.spec.optionsFrom !== undefined ? choice
                : root.multiple ? multipleChoice
                : root.hasPresets ? presetChoice
                : root.bounded ? slider
                : text
        }
    }

    // Open the group row's list, once the row shows the pressed group.
    function openGroupList() {
        if (groupRow.item !== null) groupRow.item.select.openList();
    }

    // The second row of a grouped enum: the shown group's options, while
    // that group holds several. Only a grouped enum builds it.
    Loader {
        id: groupRow
        width: root.width
        active: root.groups.length > 0
        visible: root.groupOptions.length > 0
        sourceComponent: groupFieldComponent
    }
    Component {
        id: groupFieldComponent
        Field {
            id: groupField
            readonly property alias select: groupSelect
            width: root.width
            label: root.spec.groupLabel === undefined ? "" : String(root.spec.groupLabel)
            inline: true

            Select {
                id: groupSelect
                width: parent.width
                readonly property int chosen: root.groupOptions.findIndex(option => option.value === root.value)
                model: root.groupOptions
                textRole: "label"
                placeholderText: root.spec.groupLabel === undefined ? "" : "Choose a " + String(root.spec.groupLabel).toLowerCase()
                currentIndex: chosen
                enabled: root.editable
                onActivated: index => {
                    const option = root.groupOptions[index];
                    currentIndex = Qt.binding(() => chosen);
                    root.pendingGroup = "";
                    if (option.value !== root.value) root.apply(option.value);
                }
                // A list closed with no choice stores nothing and puts the
                // stored value's segment back. Select emits `activated` before
                // it closes its list (Select.choose), so a choice has already
                // cleared the pending group here.
                onListOpenChanged: if (!listOpen && root.pendingGroup !== "") root.pendingGroup = ""
            }
        }
    }

    Field {
        id: customField
        width: root.width
        visible: root.customVisible
        label: ""
        hint: root.hintText
        hintLink: root.linkText
        onHintLinkActivated: root.openDescriptionLink()
        onHintPageActivated: (page, tab) => root.openDescriptionPage(page, tab)
        error: customLoader.item === null || customLoader.item.problemText === undefined ? "" : customLoader.item.problemText
        inline: true

        Loader {
            id: customLoader
            width: parent.width
            active: root.allowCustom
            sourceComponent: root.spec.type === "number" && root.bounded ? slider : customText
        }
    }

    // The text field of both text editors of `field`, a SettingField: it
    // keeps what is typed until it is saved. It shows the field's
    // `heldText` at first and again whenever that changes, and no binding
    // holds the text, so a draft outlives every other change. `edited`
    // says the text is not the held one, `revert()` and Escape put the
    // held one back, and Enter saves the field.
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

    Component {
        id: customText
        Item {
            id: custom
            width: parent.width
            implicitHeight: Math.max(input.implicitHeight, preview.implicitHeight)
            readonly property string problemCode: root.spec.format === "datetime" ? SettingValues.datetimeFormatProblem(input.text) : ""
            readonly property string problemText: problemCode === "" ? "" : SettingValues.PROBLEM_TEXT[problemCode]
            readonly property bool edited: input.edited
            function save() { if (problemText === "") root.commit(input); }
            function revert() { input.revert(); }
            // Empty defaults have no editable example. Keep the seed in
            // the draft, so Enter saves it and Escape restores heldText.
            function prefill() {
                if (root.heldText !== "" || !root.hasPresets) return;
                const preset = root.spec.presets.find(preset => preset.value !== "");
                if (preset !== undefined) input.text = String(preset.value);
            }

            DraftField {
                id: input
                field: root
                error: custom.problemText !== ""
                width: preview.visible ? Math.max(Theme.size.panel.sm / 3, parent.width - preview.width - Theme.stack.inline) : parent.width
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
            }

            Label {
                id: preview
                role: "hint"
                visible: root.spec.format === "datetime"
                text: custom.problemText === "" && input.text !== "" ? Qt.formatDateTime(Time.now, input.text) : ""
                width: Math.min(implicitWidth, Theme.size.panel.sm / 2)
                elide: Text.ElideRight
                anchors.left: input.right
                anchors.leftMargin: Theme.stack.inline
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    Component {
        id: toggle
        Switch {
            size: "sm"
            checked: root.value === true
            enabled: root.editable
            onToggled: {
                const wanted = checked;
                checked = Qt.binding(() => root.value === true);
                root.apply(wanted);
            }
        }
    }

    Component {
        id: choice
        Select {
            width: parent.width
            readonly property bool dynamic: root.statusFed
            // It reads no value, so the Custom… row adds no rebuild on a
            // write.
            // A speaker beside each offer (PluginLogic.settingChoices
            // `offer`), none beside an unavailable stored value.
            readonly property var offers: !dynamic || root.spec.preview !== true ? root.choices
                : root.choices.map(choice => ({ label: choice.label, value: choice.value, offer: choice.offer, preview: choice.offer !== undefined }))
            readonly property var rows: !dynamic ? root.spec.options
                : offers.concat(root.allowCustom ? [{ label: "Custom…", custom: true }] : [],
                    root.spec.addChoice === undefined ? [] : [{ label: root.spec.addChoice.label, add: true, icon: "plus" }])
            readonly property int configuredIndex: dynamic ? root.selectedOfferIndex : root.optionIndex
            readonly property int shownIndex: configuredIndex >= 0 ? configuredIndex : root.customVisible ? root.choices.length : -1
            model: rows
            textRole: "label"
            iconRole: "icon"
            actionRole: "preview"
            entryAction: root.spec.preview === true ? { iconName: "volume-2", label: "Play" } : null
            onEntryActionActivated: index => root.previewWanted(rows[index].offer)
            // A plugin that is off publishes no choices, so nothing was
            // looked for.
            emptyText: !dynamic ? "" : root.editable ? "None found yet" : "Not reported"
            placeholderText: dynamic && root.spec.placeholder !== undefined ? root.spec.placeholder : ""
            currentIndex: shownIndex
            enabled: root.editable
            onOpened: if (dynamic) root.choicesWanted()
            onActivated: index => {
                const row = rows[index];
                currentIndex = Qt.binding(() => shownIndex);
                if (dynamic && row.custom === true) {
                    root.chooseCustom();
                    return;
                }
                if (dynamic && row.add === true) {
                    root.addWanted();
                    return;
                }
                root.customChosen = false;
                if (row.value === root.value) return;
                root.apply(row.value);
            }
        }
    }

    Component {
        id: groupedSegments
        Item {
            width: parent.width
            implicitHeight: groupSeg.implicitHeight
            function inkEnd() { return groupSeg.x + groupSeg.width; }

            SegmentedControl {
                id: groupSeg
                width: implicitWidth
                model: root.groups.map(group => group.name)
                currentIndex: root.shownGroup
                enabled: root.editable
                onActivated: index => {
                    currentIndex = Qt.binding(() => root.shownGroup);
                    const group = root.groups[index];
                    if (index === root.valueGroup) {
                        root.pendingGroup = "";
                        return;
                    }
                    if (group.values.length === 1) {
                        root.pendingGroup = "";
                        root.apply(group.values[0]);
                        return;
                    }
                    root.pendingGroup = group.name;
                    // The group row shows once the binding above settles.
                    Qt.callLater(root.openGroupList);
                }
            }
        }
    }

    Component {
        id: segmented
        Item {
            width: parent.width
            implicitHeight: seg.implicitHeight
            function inkEnd() { return seg.x + seg.width; }

            SegmentedControl {
                id: seg
                width: implicitWidth
                model: root.spec.options.map(option => option.label)
                currentIndex: root.optionIndex
                enabled: root.editable
                onActivated: index => {
                    currentIndex = Qt.binding(() => root.optionIndex);
                    root.apply(root.spec.options[index].value);
                }
            }
        }
    }

    Component {
        id: multipleChoice
        Button {
            id: selection
            width: parent.width
            variant: "secondary"
            iconName: "chevron-down"
            readonly property bool listOpen: menu.opened
            text: !root.knownSelection ? "Custom…" : root.selectedTokens.length === 0 ? "Choose…"
                : root.selectedTokens.length > 2 ? root.selectedTokens.length + " selected"
                : root.selectedTokens.map(token => {
                    const preset = root.spec.presets[root.offerIndex(token)];
                    return preset.label === undefined ? token : preset.label;
                }).join(", ")
            disabledReason: root.editable ? "" : "Turn on this plugin to change its settings."
            onClicked: menu.toggle(KeyNavLogic.opener(selection))

            Menu {
                id: menu
                Repeater {
                    model: root.spec.presets
                    MenuItem {
                        required property var modelData
                        text: modelData.label === undefined ? modelData.value : modelData.label
                        checked: root.selectedTokens.indexOf(modelData.value) >= 0
                        keepsOpen: true
                        onTriggered: root.togglePreset(modelData.value)
                    }
                }
                MenuItem {
                    text: "Custom…"
                    visible: root.allowCustom
                    onTriggered: root.chooseCustom()
                }
            }
        }
    }

    Component {
        id: presetChoice
        Select {
            width: parent.width
            model: root.presetModel
            textRole: "label"
            currentIndex: root.selectedOfferIndex >= 0 ? root.selectedOfferIndex : root.allowCustom ? root.presetModel.length - 1 : -1
            enabled: root.editable
            onActivated: index => {
                const chosen = root.presetModel[index];
                currentIndex = Qt.binding(() => root.selectedOfferIndex >= 0 ? root.selectedOfferIndex : root.allowCustom ? root.presetModel.length - 1 : -1);
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
            function inkBelow() { return height - Math.max(bar.y + bar.height - bar.inkBelow(), shown.y + shown.height - shown.inkBelow()); }
            function inkAbove() { return Math.min(bar.y + bar.inkAbove(), shown.y + shown.inkAbove()); }

            function commit() {
                const wanted = bar.value;
                bar.value = Qt.binding(() => root.value);
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
                value: root.value
                enabled: root.editable
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
