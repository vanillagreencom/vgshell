import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Steps.js" as Steps

// Settings holds only values the user changes, Setup the required steps,
// kept visible through completion, and Details facts, each optional
// feature's action beside its fact, optional tools and task screens
// (docs/architecture/design-system.md § Settings pages).
FocusScope {
    id: page

    // The Settings panel: its rows, its replies and its navigation.
    required property Item panel
    // The manager row this page draws, or null.
    property var row: null

    readonly property bool editable: row !== null && row.enabled
    readonly property bool isSelf: row !== null && panel.shell !== null && row.id === panel.shell.manifest.id
    readonly property alias scrollArea: layout.scrollArea
    // The page's height unscrolled, with the tab it shows now; the window
    // follows it on each tab change, `tab`.
    readonly property real fitHeight: layout.uncappedHeight
    // The tab shown, by its text on the strip.
    readonly property string tab: tabs.model[tabs.currentIndex] || "Settings"
    readonly property alias titleMenu: menu
    readonly property alias title: titleHeader.titleButton
    readonly property alias initialFocus: back
    // The manager row of the panes holder that shows this plugin's page,
    // or null.
    readonly property var paneHolder: row === null || row.paneHolder === "" ? null : panel.plugins.find(p => p.id === row.paneHolder) || null
    // Whether the Settings page holds nothing below its switches.
    readonly property bool bare: row !== null && row.builtins.length === 0 && fields.length === 0 && sections.length === 0 && lists.length === 0 && row.binds.length === 0 && paneHolder === null
    // Whether a field of the page holds an unsaved edit.
    readonly property bool dirty: unsaved.edited

    // What the page's lines act on: whether the plugin is on, its name and,
    // while it is on, why it was not built, its first failed build or the
    // capability another plugin holds, in the shell's words, which a step it
    // never reported reads in place of the wait (Steps.stepView).
    readonly property var plugin: row === null ? { enabled: false, name: "", error: "" }
        : { enabled: row.enabled, name: row.name, error: Reply.line(row.errors.find(error => error.startsWith("build failed: ") || error.startsWith("refused: ")) || "ok") }

    // The rows of the manager row's `fieldRows` (PluginLogic.fieldRows)
    // decide each field's section. Fields of no group are rows under the
    // switches, `fields`, before every section. Built-in placement and
    // same-named schema fields share one section; the built-ins come first,
    // then each group in the order its first field appears. A `list` field
    // whose group exists on the page follows that group; one whose group is
    // absent stays with ungrouped lists at the end. A `hideEmpty` field has
    // no place while its select model is empty and it draws no key list
    // beside it (Steps.featureRow): nothing is offered for it.
    function drawsLines(field) {
        return Steps.featureRow(field, row).length > 0;
    }
    function placed(field) {
        return !field.list && !(row.schema[field.key].hideEmpty === true && (row.settingChoices[field.key] || []).length === 0 && !drawsLines(field));
    }
    function fieldRow(key) {
        return row === null ? null : row.fieldRows.find(field => field.key === key) || null;
    }
    readonly property var fields: row === null ? [] : row.fieldRows.filter(field => field.section === "" && placed(field)).map(field => field.key)
    readonly property var sections: {
        if (row === null) return [];
        const out = row.builtins.map(builtin => ({ group: builtin.name, keys: [], builtin: builtin }));
        for (const field of row.fieldRows.filter(field => field.section !== "" && placed(field))) {
            let section = out.find(s => s.group === field.section);
            if (section === undefined) {
                section = { group: field.section, keys: [], builtin: null };
                out.push(section);
            }
            section.keys.push(field.key);
        }
        for (const field of row.fieldRows.filter(field => field.list && field.section !== "")) {
            const section = out.find(s => s.group === field.section);
            if (section !== undefined) {
                if (section.lists === undefined) section.lists = [];
                section.lists.push(field.key);
            }
        }
        return out;
    }

    readonly property var lists: {
        if (row === null) return [];
        const groups = page.sections.map(section => section.group);
        return row.fieldRows.filter(field => field.list && (field.section === "" || groups.indexOf(field.section) === -1)).map(field => field.key);
    }
    // The Setup tab's status sections in drawn order, with their rows,
    // keys and setup actions.
    readonly property var setupSections: row === null ? [] : Steps.setupSections(row.tuis, row.status, row.requirements)
    // Required declarations keep their tab after completion.
    readonly property bool hasSetup: row !== null && Steps.setupTab(setupSections, row.requirements)
    readonly property bool setupNeeded: row !== null && Steps.setupNeeds(row.status, row.requirements, row.enabled).open
    readonly property var moreSettings: row === null ? [] : Steps.freeScreens(row.tuis, row.status, "Settings", plugin)
    // The listed screens Details draws in its Actions row: those that are
    // no setup screens and that no status entry declares.
    readonly property var detailScreens: row === null ? [] : Steps.freeScreens(row.tuis, row.status, "Details", plugin)
    // Keep the selected tab by name when a new plugin changes the strip.
    // If that plugin has no Setup tab, an open Setup moves to Details.
    onHasSetupChanged: {
        const names = hasSetup ? ["Settings", "Setup", "Details"] : ["Settings", "Details"];
        const shown = names.indexOf(tab) !== -1 ? tab : "Details";
        tabs.returning = true;
        tabs.model = names;
        tabs.currentIndex = names.indexOf(shown);
        tabs.returning = false;
    }

    // The keys of the status entries Details draws, by section, as
    // `sections` holds the schema's: [{ group, keys }], ungrouped first,
    // then each group in the order its first entry appears. The row's
    // `status` is in manifest order and holds no `data`, `choices` or
    // hidden entry.
    readonly property var statusSections: {
        if (row === null) return [];
        const out = [{ group: "", keys: [] }];
        for (const entry of Steps.detailEntries(row.status)) {
            let section = out.find(s => s.group === entry.group);
            if (section === undefined) {
                section = { group: entry.group, keys: [] };
                out.push(section);
            }
            section.keys.push(entry.key);
        }
        return out.filter(s => s.keys.length > 0);
    }

    function statusEntry(key) {
        return row === null ? null : row.status.find(entry => entry.key === key) || null;
    }

    // Run BUTTON, one action a line draws (Steps.js), for ENTRY, the status
    // entry of its line, or null: Turn on through the Enabled switch's
    // route, the requirement notice, a listed screen or the entry's own
    // action; answers the manager's reply.
    function press(button, entry) {
        switch (button.kind) {
        case "enable": return panel.setEnabled(row.id, true);
        case "tools": return panel.installRequirements(row.id);
        case "tui": return panel.openTui(row.id, button.name);
        case "status": return panel.act(row.id, entry.key);
        }
        throw new Error("settings: action kind " + JSON.stringify(button.kind) + " has no route");
    }
    // The last refusal of BUTTON's press for ENTRY's line, "" for none: a
    // screen's and an entry's own are kept by their step key; a Turn on's
    // and the notice's under the plugin's id, which the page head reads
    // too, so the pressed line reads it beside its button.
    function replyFor(button, entry) {
        if (row === null || panel === null) return "";
        if (button === null) return entry === null ? "" : panel.replyOf(row.id, entry.key);
        if (button.kind === "tui") return panel.replyOf(row.id, panel.tuiKey(button.name));
        if (button.kind === "enable" || button.kind === "tools") return panel.replyOf(row.id);
        return button.kind === "status" && entry !== null ? panel.replyOf(row.id, entry.key) : "";
    }

    // One Setup step drawn from a status entry, or from none, the Tools
    // step. ACTION and ASIDE_ACTION are the line's actions, which its owner
    // reads from Steps.js.
    component EntryRow: StatusLine {
        id: stateRow
        required property var entry
        property bool setup: false
        property var action: null
        property var asideAction: null
        // A step whose entry left the row draws as no entry (statusView),
        // and its delegate is hidden.
        readonly property var view: setup && entry !== null ? Steps.stepView(entry, ms => Timestamp.text(ms, Time.now.getTime()), page.plugin) : Steps.statusView(entry, ms => Timestamp.text(ms, Time.now.getTime()))
        width: parent.width
        label: view.label
        info: view.info
        tone: view.tone
        text: view.text
        muted: view.muted
        lines: view.lines
        plainLines: setup
        hint: view.hint
        hintLink: view.link === null ? "" : view.link.text
        onHintLinkActivated: page.panel.openLink(page.row.id, view.link)
        onHintPageActivated: (id, tab) => page.panel.openPage(id, tab)
        error: [action, asideAction].map(button => page.replyFor(button, entry)).find(reply => reply !== "") || ""
        actionOffered: action !== null
        actionLabel: action === null ? "" : action.label
        actionTone: action === null ? "" : action.tone
        onAct: page.press(action, entry)
        asideOffered: asideAction !== null
        asideLabel: asideAction === null ? "" : asideAction.label
        asideTone: asideAction === null ? "" : asideAction.tone
        onAside: page.press(asideAction, entry)
    }

    component ChoiceField: Column {
        id: choiceField
        property alias pluginId: editor.pluginId
        property alias key: editor.key
        // The key a page reference names the row by (revealField).
        readonly property string fieldKey: key
        property alias spec: editor.spec
        property alias value: editor.value
        property alias choices: editor.choices
        property alias editable: editor.editable
        property alias edits: editor.edits
        // Whether the row's last shown line ends in sub-text, which takes
        // the room under the row a Field takes (Theme.subTextRoom).
        readonly property bool subText: {
            const shown = children.filter(child => child.visible && child.height > 0);
            return shown.length > 0 && shown[shown.length - 1].subText === true;
        }
        signal apply(var value)
        signal openLink(var link)
        signal openPage(string id, string tab)
        signal choicesWanted()
        spacing: Theme.stack.row
        bottomPadding: Theme.subTextRoom(choiceField.subText, Positioner.index, Positioner.isLastItem, parent)
        SettingField {
            id: editor
            width: parent.width
            onApply: value => choiceField.apply(value)
            onOpenLink: link => choiceField.openLink(link)
            onOpenPage: (id, tab) => choiceField.openPage(id, tab)
            onChoicesWanted: choiceField.choicesWanted()
        }
        ChoiceExtras {
            width: parent.width
            key: choiceField.key
        }
    }

    // The lines a field draws under its control, one feature row
    // (Steps.featureRow): its stored key lists. Each delegate reads its
    // entry again by key, so a status write, which hands the page new
    // objects, keeps a key list's open masked field.
    component ChoiceExtras: Column {
        id: choiceExtras
        required property string key
        // One evaluation reads the field and the row it belongs to, so a
        // row replaced or cleared under the field never meets the field of
        // the row before.
        readonly property var lines: {
            const field = page.fieldRow(key);
            return field === null ? [] : Steps.featureRow(field, page.row);
        }
        readonly property bool subText: {
            const shown = children.filter(child => child.visible && child.height > 0);
            return shown.length > 0 && shown[shown.length - 1].subText === true;
        }
        spacing: Theme.stack.row
        bottomPadding: Theme.subTextRoom(choiceExtras.subText, Positioner.index, Positioner.isLastItem, parent)
        Repeater {
            model: ScriptModel { values: choiceExtras.lines; objectProp: "slot" }
            Column {
                id: keyLine
                required property var modelData
                readonly property bool subText: keys.subText
                width: choiceExtras.width
                bottomPadding: Theme.subTextRoom(keyLine.subText, Positioner.index, Positioner.isLastItem, parent)
                StatusRow {
                    id: keys
                    width: keyLine.width
                    entry: page.statusEntry(keyLine.modelData.key)
                    panel: page.panel
                    pluginId: page.row === null ? "" : page.row.id
                    secretLabel: page.row === null ? "" : page.row.secretLabel
                    onOpenLink: link => page.panel.openLink(page.row.id, link)
                    onOpenPage: (id, tab) => page.panel.openPage(id, tab)
                }
            }
        }
    }

    // Show the page as it opens: on TAB, a tab's text, or on Settings when
    // the page has no such tab, the back button focused. A `Settings/<field
    // key>` tab (PageReference.place) also brings that field into view.
    function open(reason, tab) {
        const place = PageReference.place(tab);
        tabs.currentIndex = Math.max(0, tabs.model.indexOf(place.tab));
        back.forceActiveFocus(reason);
        if (place.field === "") {
            revealing = "";
            return;
        }
        revealMoving = true;
        layout.scrollArea.contentY = 0;
        revealMoving = false;
        revealing = place.field;
        Qt.callLater(page.revealField);
    }

    // The key of the field an open asked to show, "" for none. A newly
    // shown plugin's rows lay out after the open, so each layout of the
    // Settings tab that completes shows it again (Column.positioningComplete),
    // the call waiting for the next turn, as SettingField's reveal does,
    // until the next open, a change of tab or a scroll the reveal did not
    // make, so the page never moves under the user later.
    property string revealing: ""
    property bool revealMoving: false
    Connections {
        target: layout.scrollArea
        function onContentYChanged() { if (!page.revealMoving) page.revealing = ""; }
    }
    // Scroll the Settings tab to the row of the field `revealing` names, a
    // field's or a list's. A key the page draws no row for is refused once,
    // at the page head and in the log.
    function revealField() {
        if (revealing === "" || row === null) return;
        const field = fieldRow(revealing);
        if (field === null || (!field.list && !placed(field))) {
            panel.keep(row.id, "refused: page-field=" + revealing + " reason=" + (field === null ? "unknown" : "undrawn"));
            revealing = "";
            return;
        }
        const found = [settingsPage];
        for (let i = 0; i < found.length; i++) {
            if (found[i].fieldKey === revealing && found[i].visible) {
                revealMoving = true;
                layout.scrollArea.reveal(found[i]);
                revealMoving = false;
                return;
            }
            for (const child of found[i].children) found.push(child);
        }
    }

    // Write every unsaved edit; answers whether none is left.
    function save() {
        return unsaved.save();
    }

    function discard() {
        unsaved.discard();
    }

    EditSet {
        id: unsaved
        onSaved: saveBar.confirm()
        // The bar's actions leave with the last edit, so the keyboard one
        // of them holds goes to the strip, as a page that hides hands it on.
        onEditedChanged: if (!edited && saveBar.activeFocus) tabs.tabs.forceActiveFocus(Qt.TabFocusReason)
    }

    // The back button and the title sit outside the tab pages, so the keys
    // they leave go to the pages, which step on the tab keys.
    Keys.forwardTo: [tabs]
    Keys.onPressed: event => {
        if (event.key !== Qt.Key_S || event.modifiers !== Qt.ControlModifier) return;
        save();
        event.accepted = true;
    }

    Pane {
        id: layout
        anchors.fill: parent
        container: "window"
        bodySpacing: 0

        titleContent: [
            PageHeader {
                id: titleHeader
                width: parent.width
                text: page.row === null ? "" : page.row.name
                menu: menu

                leading: [
                    IconButton {
                        id: back
                        iconName: "chevron-left"
                        label: "Back to the plugin list"
                        anchors.verticalCenter: parent.verticalCenter
                        onClicked: page.panel.back()
                    }
                ]

                trailing: [
                    Button {
                        id: openButton
                        text: "Open"
                        iconName: "app-window"
                        variant: "secondary"
                        anchors.verticalCenter: parent.verticalCenter
                        visible: page.row !== null && page.row.opens !== "" && !page.isSelf
                        enabled: page.editable
                        onClicked: page.panel.openSurface(page.row.id)
                    }
                ]

                Menu {
                    id: menu
                    Repeater {
                        model: ScriptModel {
                            values: page.panel.plugins
                            objectProp: "id"
                        }
                        MenuItem {
                            required property var modelData
                            text: modelData.name
                            iconName: modelData.icon
                            checked: page.row !== null && modelData.id === page.row.id
                            onTriggered: page.panel.openPlugin(modelData.id, Qt.TabFocusReason)
                        }
                    }
                }
            }
        ]

        Column {
            id: body
            width: parent.width
            spacing: Theme.stack.page
            visible: page.row !== null

            Repeater {
                model: page.row === null ? [] : page.row.errors
                Label {
                    required property string modelData
                    role: "hint"
                    text: Reply.line(modelData)
                    color: Theme.color.danger
                    width: body.width
                    wrapMode: Text.Wrap
                }
            }

            Label {
                role: "hint"
                text: page.row === null ? "" : page.panel.replyOf(page.row.id)
                visible: text !== ""
                color: Theme.color.danger
                width: parent.width
                wrapMode: Text.Wrap
            }

            TabPages {
                id: tabs
                width: parent.width
                model: ["Settings", "Details"]
                warningTabs: page.setupNeeded ? ["Setup"] : []
                // True while the handler puts Settings back, and while
                // the page sets the strip's tabs.
                property bool returning: false
                onCurrentIndexChanged: {
                    if (returning) return;
                    page.revealing = "";
                    if (currentIndex === 0 || !page.dirty) {
                        layout.scrollArea.contentY = 0;
                        return;
                    }
                    const wanted = currentIndex;
                    returning = true;
                    currentIndex = 0;
                    returning = false;
                    page.panel.leave(() => { tabs.currentIndex = wanted; });
                }

                Column {
                    id: settingsPage
                    spacing: Theme.stack.page
                    onPositioningComplete: if (page.revealing !== "") Qt.callLater(page.revealField)

                    // The switches, then the fields of no group, rows of
                    // one list, so a row with a hint leaves `stack.group`
                    // before the next (Theme.subTextRoom).
                    Column {
                        id: switches
                        width: parent.width
                        spacing: Theme.stack.row

                        Field {
                            width: parent.width
                            label: SettingValues.PAGE_LABELS.enabled
                            inline: true
                            visible: page.row !== null && !page.row.alwaysOn
                            hint: page.row !== null && !page.row.enabled && !page.bare ? "Turn on " + page.row.name + " to change its settings and shortcuts" : ""
                            Switch {
                                size: "sm"
                                checked: page.row !== null && page.row.enabled
                                onToggled: {
                                    checked = Qt.binding(() => page.row !== null && page.row.enabled);
                                    if (page.row !== null) page.panel.setEnabled(page.row.id, !page.row.enabled);
                                }
                            }
                        }

                        Field {
                            width: parent.width
                            label: SettingValues.PAGE_LABELS.showInBar
                            inline: true
                            visible: page.row !== null && page.row.kinds.indexOf("bar-widget") !== -1 && page.row.kinds.some(kind => kind !== "bar" && kind !== "bar-widget")
                            hint: page.row !== null && !page.row.enabled ? "Turn on " + page.row.name + " to show it in the bar" : ""
                            Switch {
                                size: "sm"
                                checked: page.row !== null && page.row.placed
                                enabled: page.editable
                                onToggled: {
                                    checked = Qt.binding(() => page.row !== null && page.row.placed);
                                    if (page.row !== null) page.panel.togglePlaced(page.row.id);
                                }
                            }
                        }

                        Repeater {
                            model: ScriptModel {
                                values: page.fields
                            }
                            ChoiceField {
                                required property string modelData
                                width: switches.width
                                pluginId: page.row.id
                                key: modelData
                                spec: page.row.schema[modelData]
                                value: page.row.settings[modelData]
                                choices: page.row.settingChoices[modelData] || []
                                editable: page.editable
                                edits: unsaved
                                onApply: v => { if (page !== null && page.row !== null) page.panel.writeSetting(pluginId, key, v); }
                                onOpenLink: link => { if (page !== null && page.row !== null) page.panel.openLink(pluginId, link); }
                                onOpenPage: (id, tab) => { if (page !== null && page.panel !== null) page.panel.openPage(id, tab); }
                                onChoicesWanted: if (page !== null && page.row !== null) page.panel.refreshChoices(pluginId, spec.optionsFrom)
                            }
                        }
                    }

                    Label {
                        role: "hint"
                        color: Theme.color.textMuted
                        text: "This plugin has no other settings."
                        visible: page.bare
                        width: parent.width
                        wrapMode: Text.Wrap
                    }

                    // Keyed models keep each section, field and key row
                    // while the manager's rows are replaced, so an edit in
                    // progress survives an unrelated change.
                    Repeater {
                        model: ScriptModel {
                            values: page.sections
                            objectProp: "group"
                        }
                        Section {
                            id: section
                            required property var modelData
                            width: body.width
                            title: section.modelData.group

                            Repeater {
                                model: ScriptModel {
                                    values: section.modelData.builtin === null ? [] : [section.modelData.builtin]
                                    objectProp: "id"
                                }
                                SettingField {
                                    required property var modelData
                                    pluginId: modelData.id
                                    spec: ({ type: "boolean", label: SettingValues.PAGE_LABELS.showOnBar })
                                    value: modelData.placed
                                    editable: page.editable
                                    onApply: v => { if (page !== null && page.row !== null) page.panel.writePlacement(pluginId, v, page.row.id); }
                                }
                            }

                            Repeater {
                                model: ScriptModel {
                                    values: section.modelData.keys
                                }
                                ChoiceField {
                                    required property string modelData
                                    width: section.width
                                    pluginId: page.row.id
                                    key: modelData
                                    spec: page.row.schema[modelData]
                                    value: page.row.settings[modelData]
                                    choices: page.row.settingChoices[modelData] || []
                                    editable: page.editable
                                    edits: unsaved
                                    onApply: v => { if (page !== null && page.row !== null) page.panel.writeSetting(pluginId, key, v); }
                                    onOpenLink: link => { if (page !== null && page.row !== null) page.panel.openLink(pluginId, link); }
                                    onOpenPage: (id, tab) => { if (page !== null && page.panel !== null) page.panel.openPage(id, tab); }
                                    onChoicesWanted: if (page !== null && page.row !== null) page.panel.refreshChoices(pluginId, spec.optionsFrom)
                                }
                            }

                            Repeater {
                                model: ScriptModel {
                                    values: section.modelData.lists || []
                                }
                                Section {
                                    id: groupedListSection
                                    required property string modelData
                                    // The key a page reference names the list by (revealField).
                                    readonly property string fieldKey: modelData
                                    width: section.width
                                    title: page.row.schema[modelData].label
                                    description: page.row.schema[modelData].description === undefined ? "" : page.row.schema[modelData].description
                                    onPageActivated: (id, tab) => { if (page !== null && page.panel !== null) page.panel.openPage(id, tab); }
                                    info: page.row.schema[modelData].info === undefined ? "" : page.row.schema[modelData].info

                                    ListField {
                                        width: groupedListSection.width
                                        pluginId: page.row.id
                                        key: groupedListSection.modelData
                                        spec: page.row.schema[groupedListSection.modelData]
                                        value: page.row.settings[groupedListSection.modelData]
                                        choices: page.row.settingChoices[groupedListSection.modelData] || []
                                        editable: page.editable
                                        edits: unsaved
                                        onApply: v => { if (page !== null && page.row !== null) page.panel.writeSetting(pluginId, key, v); }
                                        onOpenLink: link => { if (page !== null && page.row !== null) page.panel.openLink(pluginId, link); }
                                        onOpenPage: (id, tab) => { if (page !== null && page.panel !== null) page.panel.openPage(id, tab); }
                                    }
                                    ChoiceExtras {
                                        width: groupedListSection.width
                                        key: groupedListSection.modelData
                                    }
                                }
                            }
                        }
                    }

                    Repeater {
                        model: ScriptModel {
                            values: page.lists
                        }
                        Section {
                            id: listSection
                            required property string modelData
                            // The key a page reference names the list by (revealField).
                            readonly property string fieldKey: modelData
                            width: body.width
                            title: page.row.schema[modelData].label
                            description: page.row.schema[modelData].description === undefined ? "" : page.row.schema[modelData].description
                            onPageActivated: (id, tab) => { if (page !== null && page.panel !== null) page.panel.openPage(id, tab); }
                            info: page.row.schema[modelData].info === undefined ? "" : page.row.schema[modelData].info

                            ListField {
                                width: listSection.width
                                pluginId: page.row.id
                                key: listSection.modelData
                                spec: page.row.schema[listSection.modelData]
                                value: page.row.settings[listSection.modelData]
                                choices: page.row.settingChoices[listSection.modelData] || []
                                editable: page.editable
                                edits: unsaved
                                onApply: v => { if (page !== null && page.row !== null) page.panel.writeSetting(pluginId, key, v); }
                                onOpenLink: link => { if (page !== null && page.row !== null) page.panel.openLink(pluginId, link); }
                                onOpenPage: (id, tab) => { if (page !== null && page.panel !== null) page.panel.openPage(id, tab); }
                            }
                            ChoiceExtras {
                                width: listSection.width
                                key: listSection.modelData
                            }
                        }
                    }

                    Section {
                        width: parent.width
                        visible: page.row !== null && page.row.binds.length > 0
                        title: "Keys"
                        description: "Select a shortcut and press its new keys"

                        Repeater {
                            model: ScriptModel {
                                values: page.row === null ? [] : page.row.binds
                                objectProp: "shortcut"
                            }
                            KeyField {
                                id: keyField
                                required property var modelData
                                width: body.width
                                pluginId: page.row.id
                                bind: modelData
                                editable: page.editable
                                capture: page.panel.capture
                                edits: unsaved
                                onRemovalAsked: row => page.panel.confirmRemoval(keyField, row)
                                onLineAsked: row => page.panel.openUserLine(row)
                                onApplyKey: key => {
                                    if (page === null || page.row === null) return;
                                    settle(key, Reply.isOk(page.panel.writeKey(pluginId, modelData.shortcut, key)));
                                }
                            }
                        }
                    }

                    Repeater {
                        model: page.moreSettings
                        Field {
                            id: moreSettingsRow
                            required property var modelData
                            width: settingsPage.width
                            label: SettingValues.PAGE_LABELS.moreSettings
                            inline: true
                            hint: modelData.reason
                            error: page.row === null ? "" : page.panel.replyOf(page.row.id, page.panel.tuiKey(modelData.name))
                            RowAction {
                                text: moreSettingsRow.modelData.label
                                enabled: moreSettingsRow.modelData.enabled
                                onClicked: page.panel.openTui(page.row.id, moreSettingsRow.modelData.name)
                            }
                        }
                    }

                    Button {
                        text: page.paneHolder === null ? "" : "More settings in " + page.paneHolder.name
                        iconName: page.paneHolder === null ? "" : page.paneHolder.icon
                        variant: "secondary"
                        visible: page.paneHolder !== null
                        enabled: page.editable
                        onClicked: page.panel.openPane(page.row.id)
                    }
                }

                // The strip's second page. Setup stands between Settings and
                // Details when the plugin has it, so the second page is
                // Setup for such a plugin and Details for any other, which
                // then draws here, under sections that are none: an Item's
                // `parent` is writable, and a Column lays out the children
                // it has that are shown and sized
                // (https://doc.qt.io/qt-6/qml-qtquick-item.html#parent-prop,
                // https://doc.qt.io/qt-6/qml-qtquick-column.html).
                Column {
                    id: setupPage
                    spacing: Theme.stack.page

                    Section {
                        width: body.width
                        title: "Setup"
                        visible: page.hasSetup
                        GroupList {
                            id: requiredSteps
                            width: setupPage.width
                            Repeater {
                                model: ScriptModel {
                                    values: page.setupSections.length === 0 ? [] : page.setupSections[0].items
                                    objectProp: "slot"
                                }
                                Loader {
                                    id: requiredEntry
                                    required property var modelData
                                    width: requiredSteps.width
                                    // A step whose entry left the row draws no line.
                                    visible: modelData.keys || modelData.tools === true || page.statusEntry(modelData.key) !== null
                                    sourceComponent: modelData.keys ? requiredKeys : requiredState
                                    Component {
                                        id: requiredKeys
                                        StatusRow {
                                            // ScriptModel can keep modelData when the same update
                                            // changes and moves a row. Read current key presence
                                            // without replacing an unchanged masked editor.
                                            entry: page.statusEntry(requiredEntry.modelData.key)
                                            setup: true
                                            panel: page.panel
                                            pluginId: page.row === null ? "" : page.row.id
                                            secretLabel: page.row === null ? "" : page.row.secretLabel
                                            onOpenLink: link => page.panel.openLink(page.row.id, link)
                                            onOpenPage: (id, tab) => page.panel.openPage(id, tab)
                                        }
                                    }
                                    Component {
                                        id: requiredState
                                        // The step's entry and its actions read the manager
                                        // row again, as its key list does, since ScriptModel
                                        // can keep a moved row's modelData.
                                        EntryRow {
                                            readonly property bool tools: requiredEntry.modelData.tools === true
                                            entry: tools ? requiredEntry.modelData.entry : page.statusEntry(requiredEntry.modelData.key)
                                            setup: true
                                            action: page.row === null ? null : tools ? Steps.requirementStep(page.row.requirements).button
                                                : entry === null ? null : Steps.lineAction(Steps.stepButton(entry), Steps.stepOpen(entry), page.plugin)
                                            asideAction: entry === null || tools || !page.plugin.enabled ? null : Steps.asideButton(entry)
                                        }
                                    }
                                }
                            }

                        }
                    }
                }

                Column {
                    id: detailsPage
                    // The strip's last page beside a Setup tab, as declared.
                    parent: page.hasSetup ? settingsPage.parent : setupPage
                    // The strip shows and hides its own pages alone, and hid
                    // this one as its third.
                    onParentChanged: if (parent === setupPage) visible = true
                    spacing: Theme.stack.page

                    Label {
                        role: "hint"
                        color: Theme.color.textMuted
                        text: page.row === null ? "" : page.row.description
                        width: parent.width
                        wrapMode: Text.Wrap
                    }

                    Flow {
                        width: parent.width
                        spacing: Theme.space.xs
                        visible: page.row !== null && page.row.capabilities.length > 0
                        Repeater {
                            model: page.row === null ? [] : page.row.capabilities
                            Badge { required property string modelData; text: modelData; iconName: "shield" }
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: Theme.stack.row

                        Repeater {
                            model: page.row === null ? [] : [["Author", page.row.author], ["Version", page.row.version], ["License", page.row.license], ["Source", page.row.source === "bundled" ? "Included with VGS" : "Installed"]].filter(pair => pair[1] !== "")
                            Field {
                                id: detail
                                required property var modelData
                                width: body.width
                                label: modelData[0]
                                inline: true
                                Label { role: "value"; text: detail.modelData[1]; width: parent.width; elide: Text.ElideRight }
                            }
                        }

                        Field {
                            width: parent.width
                            label: "Readme"
                            inline: true
                            visible: page.row !== null && page.row.readme !== ""
                            RowAction {
                                text: "Open on GitHub"
                                onClicked: page.panel.openLink(page.row.id, { url: page.row.readme })
                            }
                        }

                        // A bundled plugin is disabled, never updated or removed.
                        Field {
                            width: parent.width
                            label: "Manage"
                            inline: true
                            visible: page.row !== null && page.row.source === "installed"
                            hint: "You can review changes before you apply them"
                            RowActions {
                                RowAction {
                                    text: "Update"
                                    onClicked: page.panel.updatePlugin(page.row.id)
                                }
                                RowAction {
                                    text: "Remove"
                                    tone: "danger"
                                    onClicked: page.panel.removePlugin(page.row.id)
                                }
                            }
                        }

                        // Each screen opens through the manager, and the
                        // last refusal of each reads under the row in its
                        // own line, so it never takes the hint's place. A
                        // screen of a plugin that is off takes no press and
                        // no Tab stop; its reason reads in the row's hint
                        // and opens on hover.
                        Column {
                            id: detailActions
                            width: parent.width
                            spacing: Theme.field.gap
                            visible: page.detailScreens.length > 0
                            Field {
                                width: parent.width
                                label: "Actions"
                                inline: true
                                hint: Steps.withheldHint(page.detailScreens)
                                RowActions {
                                    width: parent.width
                                    Repeater {
                                        model: ScriptModel {
                                            values: page.detailScreens
                                            objectProp: "key"
                                        }
                                        RowAction {
                                            id: detailScreen
                                            required property var modelData
                                            text: modelData.label
                                            enabled: modelData.enabled
                                            onClicked: page.panel.openTui(page.row.id, modelData.name)
                                            Tooltip { text: detailScreen.modelData.reason }
                                        }
                                    }
                                }
                            }
                            Repeater {
                                model: page.panel === null ? [] : page.detailScreens.map(screen => page.panel.tuiKey(screen.name))
                                Label {
                                    required property string modelData
                                    role: "hint"
                                    color: Theme.color.danger
                                    text: page.row === null || page.panel === null ? "" : page.panel.replyOf(page.row.id, modelData)
                                    visible: text !== ""
                                    width: detailActions.width
                                    wrapMode: Text.Wrap
                                }
                            }
                        }
                    }

                    // What the plugin published, read-only.
                    Repeater {
                        model: ScriptModel {
                            values: page.statusSections
                            objectProp: "group"
                        }
                        Section {
                            id: statusSection
                            required property var modelData
                            width: body.width
                            title: statusSection.modelData.group === "" ? "Status" : statusSection.modelData.group

                            // Each entry is one group, divided from the next.
                            GroupList {
                                id: statusRows
                                width: statusSection.width

                                Repeater {
                                    model: ScriptModel {
                                        values: statusSection.modelData.keys
                                    }
                                    StatusRow {
                                        id: detailRow
                                        required property string modelData
                                        // An optional feature's own action beside its fact.
                                        readonly property var buttons: entry === null ? ({ action: null, aside: null }) : Steps.detailButtons(entry, page.plugin)
                                        width: statusRows.width
                                        entry: page.statusEntry(modelData)
                                        action: detailRow.buttons.action
                                        asideAction: detailRow.buttons.aside
                                        actionReply: [detailRow.action, detailRow.asideAction].map(button => page.replyFor(button, detailRow.entry)).find(reply => reply !== "") || ""
                                        onActionPressed: button => page.press(button, detailRow.entry)
                                        panel: page.panel
                                        onOpenLink: link => { if (page !== null && page.row !== null) page.panel.openLink(page.row.id, link); }
                                        onOpenPage: (id, tab) => { if (page !== null && page.panel !== null) page.panel.openPage(id, tab); }
                                        pluginId: page.row === null ? "" : page.row.id
                                        secretLabel: page.row === null ? "" : page.row.secretLabel
                                    }
                                }
                            }
                        }
                    }

                    Section {
                        id: toolsSection
                        // The optional tools and the action that installs
                        // the missing or outdated ones (Steps.toolsReview).
                        readonly property var tools: page.row === null ? [] : Steps.detailRequirements(page.row.requirements)
                        readonly property var review: Steps.toolsReview(tools)
                        width: parent.width
                        title: "Tools"
                        visible: tools.length > 0
                        Repeater {
                            model: toolsSection.tools
                            RequirementRow { required property var modelData; width: toolsSection.width; requirement: modelData }
                        }
                        RowAction {
                            visible: toolsSection.review !== null
                            text: toolsSection.review === null ? "" : toolsSection.review.label
                            onClicked: page.press(toolsSection.review, null)
                        }
                    }
                }
            }
        }

        footer: [
            SaveBar {
                id: saveBar
                width: parent.width
                dirty: page.dirty
                onSave: page.save()
                onDiscard: page.discard()
            }
        ]
    }
}
