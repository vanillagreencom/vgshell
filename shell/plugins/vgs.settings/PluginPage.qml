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
    // The cap on this page's Pane, which the window host maps the window
    // at for a long page: Window.maxHeight, or 0 for none.
    property alias maximumHeight: layout.maximumHeight
    // The manager row this page draws, or null.
    property var row: null
    onRowChanged: Qt.callLater(page.syncTabNavigation)

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
    readonly property alias stickyTabs: tabs.tabs
    // The manager row of the panes holder that shows this plugin's page,
    // or null.
    readonly property var paneHolder: row === null || row.paneHolder === "" ? null : panel.plugins.find(p => p.id === row.paneHolder) || null
    // Whether the plugin declares nothing for the Settings page below its
    // switches. It reads the schema's rows before placed(), so a plugin
    // whose fields only wait, on a `shownWhen` entry or a `hideEmpty`
    // offer, keeps the Turn on hint while it is off and never reads as
    // having no settings.
    readonly property bool bare: row !== null && row.builtins.length === 0 && row.fieldRows.length === 0 && row.binds.length === 0 && paneHolder === null && settingsRows.length === 0
    // Whether a field of the page holds an unsaved edit.
    readonly property bool dirty: unsaved.edited

    // What the page's lines act on: whether the plugin is on, its name,
    // while it is on, why it was not built, its first failed build or the
    // capability another plugin holds, in the shell's words (Reply.line),
    // which a step it never reported reads in place of Checking, and
    // `failed`, whether such a line applies, which reads such a step Not
    // available (Steps.stepView). A binding that reads it with the row
    // calls pluginOf(row), so a new row reaches it in one evaluation and
    // never beside the plugin of the row before.
    function pluginOf(row) {
        if (row === null) return { enabled: false, name: "", error: "", failed: false };
        const line = Steps.startError(row.errors);
        return { enabled: row.enabled, name: row.name, error: Reply.line(line || "ok"), failed: line !== "" };
    }
    readonly property var plugin: pluginOf(row)

    // The rows of the manager row's `fieldRows` (PluginLogic.fieldRows)
    // decide each field's section. Fields of no group are rows under the
    // switches, `fields`, before every section. Built-in placement and
    // same-named schema fields share one section; the built-ins come first,
    // then each group in the order its first field appears. A `list` field
    // whose group exists on the page follows that group; one whose group is
    // absent stays with ungrouped lists at the end. A `hideEmpty` field has
    // no place while its select model is empty and it draws no key list
    // beside it (Steps.featureRow): nothing is offered for it. A
    // `shownWhen` field has no place while the manager row withholds it,
    // its presence entry not reading present or the setting it follows
    // holding another value (PluginLogic.withheldFields).
    function drawsLines(field) {
        return Steps.featureRow(field, row).length > 0;
    }
    function placed(field) {
        return !field.list && !(row.schema[field.key].shownWhen !== undefined && row.withheldFields.indexOf(field.key) !== -1)
            && !(row.schema[field.key].hideEmpty === true && (row.settingChoices[field.key] || []).length === 0 && !drawsLines(field));
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
    readonly property var setupSections: row === null ? [] : Steps.setupSections(row.tuis, row.status, row.requirements, pluginOf(row))
    // Required declarations keep their tab after completion.
    readonly property bool hasSetup: row !== null && Steps.setupTab(setupSections, row.requirements)
    readonly property bool setupNeeded: row !== null && Steps.setupNeeds(row.status, row.requirements, row.enabled, Steps.startFailed(row.errors)).open
    readonly property var moreSettings: row === null ? [] : Steps.freeScreens(row.tuis, row.status, "Settings", plugin)
    // The listed screens Details draws in its Actions row: those that are
    // no setup screens and that no status entry declares.
    readonly property var detailScreens: row === null ? [] : Steps.freeScreens(row.tuis, row.status, "Details", plugin)
    // The keys of the `rows` entries each tab draws as a section of its
    // own: those the manifest places on Settings, and the Details ones.
    readonly property var settingsRows: row === null ? [] : Steps.rowsEntries(row.status, true).map(entry => entry.key)
    readonly property var detailRows: row === null ? [] : Steps.rowsEntries(row.status, false).map(entry => entry.key)
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
    // route, the requirement notice, a listed screen, the entry's own
    // action or one row action of a `rows` entry; answers the manager's reply.
    function press(button, entry) {
        switch (button.kind) {
        case "enable": return panel.setEnabled(row.id, true);
        case "tools": return panel.installRequirements(row.id);
        case "tui": return panel.openTui(row.id, button.name);
        case "status": return panel.act(row.id, entry.key);
        case "row": return panel.act(row.id, entry.key, button.row, button.name);
        }
        throw new Error("settings: action kind " + JSON.stringify(button.kind) + " has no route");
    }
    // The last refusal of BUTTON's press for ENTRY's line, "" for none,
    // each read under its action's own step key: a screen's, an entry's,
    // a row action's, under its row's id, Turn on's and the notice's. Every Turn on asks the one thing, to turn
    // the plugin on, so each line offering it reads its refusal, as each
    // Review reads the notice's; the page head reads those two as well.
    function replyFor(button, entry) {
        if (row === null || panel === null) return "";
        if (button === null) return entry === null ? "" : panel.replyOf(row.id, entry.key);
        if (button.kind === "tui") return panel.replyOf(row.id, panel.tuiKey(button.name));
        if (button.kind === "enable" || button.kind === "tools") return panel.replyOf(row.id, panel.actionKey(button.kind));
        if (button.kind === "row") return entry === null ? "" : panel.replyOf(row.id, entry.key, button.row);
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
        onInfoPageActivated: (id, tab) => page.panel.openPage(id, tab)
        error: [action, asideAction].map(button => page.replyFor(button, entry)).find(reply => reply !== "") || ""
        actionOffered: action !== null
        actionLabel: action === null ? "" : action.label
        actionTone: action === null ? "" : action.tone
        actionIcon: action === null ? "" : action.icon
        onAct: page.press(action, entry)
        asideOffered: asideAction !== null
        asideLabel: asideAction === null ? "" : asideAction.label
        asideTone: asideAction === null ? "" : asideAction.tone
        asideIcon: asideAction === null ? "" : asideAction.icon
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
        property alias groups: editor.groups
        property alias problem: editor.problem
        property alias editable: editor.editable
        property alias edits: editor.edits
        // A key/value row: the row under it stands by ink (Field).
        readonly property bool keyValueRow: true
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
        signal addWanted()
        signal previewWanted(var value)
        spacing: Theme.stack.row
        bottomPadding: Theme.subTextRoom(choiceField.subText, Positioner.index, Positioner.isLastItem, parent)
        SettingField {
            id: editor
            width: parent.width
            onApply: value => choiceField.apply(value)
            onOpenLink: link => choiceField.openLink(link)
            onOpenPage: (id, tab) => choiceField.openPage(id, tab)
            onChoicesWanted: choiceField.choicesWanted()
            onAddWanted: choiceField.addWanted()
            onPreviewWanted: value => choiceField.previewWanted(value)
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
    // the page has no such tab, the back button focused. A `<tab>/<key>` tab
    // (PageReference.place) also brings that row into view, a Settings
    // field's or a Setup or Details status row's, and marks it.
    function open(reason, tab) {
        const place = PageReference.place(tab);
        tabs.currentIndex = Math.max(0, tabs.model.indexOf(place.tab));
        back.forceActiveFocus(reason);
        if (place.key === "") {
            revealing = "";
            return;
        }
        revealMoving = true;
        layout.scrollArea.contentY = 0;
        revealMoving = false;
        revealTab = tabs.model.indexOf(place.tab) === -1 ? "Settings" : place.tab;
        revealing = place.key;
        Qt.callLater(page.revealField);
    }

    // The key of the row an open asked to show, "" for none, on the tab
    // `revealTab` names. A newly shown plugin's rows lay out after the open,
    // so each layout of the tab that completes shows it again
    // (Column.positioningComplete), the call waiting for the next turn, as
    // SettingField's reveal does, until the next open, a change of tab or a
    // scroll the reveal did not make, so the page never moves under the user
    // later. The row it shows draws the page's one mark (`revealMark`) while
    // `revealing` holds.
    property string revealing: ""
    property string revealTab: "Settings"
    property bool revealMoving: false
    // The row the last reveal found, null while none is shown.
    property Item revealedRow: null
    onRevealingChanged: if (revealing === "") revealedRow = null
    // The scroll position the last move left. A move that starts past the
    // area's end is the area settling back inside it, as the window takes
    // the page's height after a reveal near the end, not the user's scroll.
    property real lastContentY: 0
    Connections {
        target: layout.scrollArea
        function onContentYChanged() {
            const area = layout.scrollArea;
            const settling = page.lastContentY > Math.max(0, area.contentHeight - area.height);
            page.lastContentY = area.contentY;
            if (!page.revealMoving && !settling) page.revealing = "";
        }
    }
    // Whether the tab TAB draws a row for KEY: a Settings field or list
    // the page places, a Setup step, or a Details status row.
    function revealDrawn(tab, key) {
        if (tab === "Settings") {
            const field = fieldRow(key);
            return field === null ? "unknown" : field.list || placed(field) ? "" : "undrawn";
        }
        const entry = statusEntry(key);
        if (entry === null) return "unknown";
        if (tab === "Setup") return setupSections.length > 0 && setupSections[0].items.some(item => !item.keys && item.key === key) ? "" : "undrawn";
        return Steps.detailEntries(row.status).some(shown => shown.key === key) ? "" : "undrawn";
    }
    // Scroll the tab `revealTab` names to the row `revealing` names, which
    // carries it as `fieldKey`, a field's or a list's, or `statusKey`, a
    // status row's. A key the tab draws no row for is refused once, at the
    // page head and in the log.
    function revealField() {
        if (revealing === "" || row === null) return;
        const refusal = revealDrawn(revealTab, revealing);
        if (refusal !== "") {
            panel.keep(row.id, "refused: page-target=" + revealTab + "/" + revealing + " reason=" + refusal);
            revealing = "";
            return;
        }
        const found = [revealTab === "Settings" ? settingsPage : revealTab === "Setup" ? setupPage : detailsPage];
        for (let i = 0; i < found.length; i++) {
            const item = found[i];
            if ((item.fieldKey === revealing || item.statusKey === revealing) && item.visible) {
                revealMoving = true;
                layout.scrollArea.reveal(item);
                revealMoving = false;
                revealedRow = item;
                revealMark.place();
                return;
            }
            for (const child of item.children) found.push(child);
        }
    }

    // Write every unsaved edit; answers whether none is left.
    function save() {
        return unsaved.save();
    }

    function discard() {
        unsaved.discard();
    }

    function firstFocusable(item) {
        if (item === null || item === undefined) return null;
        const pending = [item];
        while (pending.length > 0) {
            const current = pending.shift();
            if (current !== item && current.visible && current.enabled && current.forceActiveFocus !== undefined && (current.activeFocusOnTab === true || current.focusPolicy === Qt.StrongFocus || current.focusPolicy === Qt.TabFocus))
                return current;
            for (let i = 0; i < current.children.length; i++) pending.push(current.children[i]);
        }
        return null;
    }

    function syncTabNavigation() {
        const first = firstFocusable(tabs.currentPage);
        const open = openButton.visible && openButton.enabled;
        titleHeader.titleButton.KeyNavigation.tab = open ? openButton : tabs.tabs;
        if (open) openButton.KeyNavigation.tab = tabs.tabs;
        tabs.tabs.KeyNavigation.backtab = open ? openButton : titleHeader.titleButton;
        tabs.tabs.KeyNavigation.tab = first;
        if (first !== null) first.KeyNavigation.backtab = tabs.tabs;
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
                        KeyNavigation.tab: titleHeader.titleButton
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
                        KeyNavigation.backtab: titleHeader.titleButton
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
                text: page.row === null ? "" : page.panel.headReplies(page.row.id).join("\n")
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
                tabs.x: layout.scrollArea.focusInset + layout.ringRoom
                // Keep the real tab bar inside TabPages so its focus scope
                // continues to own keyboard navigation. Offset it by the
                // scroll position so its viewport position stays fixed.
                tabs.tabs.y: layout.scrollArea.contentY + layout.scrollArea.focusInset + layout.ringRoom - tabs.y
                tabs.width: Math.max(0, layout.scrollArea.contentWidth - layout.ringRoom)
                tabs.z: 2
                tabs.objectName: "stickyTabs"
                Component.onCompleted: Qt.callLater(page.syncTabNavigation)
                // True while the handler puts Settings back, and while
                // the page sets the strip's tabs.
                property bool returning: false
                onCurrentIndexChanged: {
                    Qt.callLater(page.syncTabNavigation);
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
                    onPositioningComplete: if (page.revealing !== "" && page.revealTab === "Settings") Qt.callLater(page.revealField)

                    // The switches, then the fields of no group, rows of
                    // one list, each `stack.page` under the drawn ink of
                    // the row above (Field).
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
                                groups: page.fieldRow(modelData).groups
                                problem: spec.problem === undefined ? "" : page.row.fieldProblems[modelData]
                                editable: page.editable
                                edits: unsaved
                                onApply: v => { if (page !== null && page.row !== null) page.panel.writeSetting(pluginId, key, v); }
                                onOpenLink: link => { if (page !== null && page.row !== null) page.panel.openLink(pluginId, link); }
                                onOpenPage: (id, tab) => { if (page !== null && page.panel !== null) page.panel.openPage(id, tab); }
                                onChoicesWanted: if (page !== null && page.row !== null) page.panel.refreshChoices(pluginId, spec.optionsFrom)
                                onAddWanted: if (page !== null && page.row !== null) page.panel.addChoice(pluginId, key)
                                onPreviewWanted: value => { if (page !== null && page.row !== null) page.panel.previewChoice(pluginId, key, value); }
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
                                    groups: page.fieldRow(modelData).groups
                                    problem: spec.problem === undefined ? "" : page.row.fieldProblems[modelData]
                                    editable: page.editable
                                    edits: unsaved
                                    onApply: v => { if (page !== null && page.row !== null) page.panel.writeSetting(pluginId, key, v); }
                                    onOpenLink: link => { if (page !== null && page.row !== null) page.panel.openLink(pluginId, link); }
                                    onOpenPage: (id, tab) => { if (page !== null && page.panel !== null) page.panel.openPage(id, tab); }
                                    onChoicesWanted: if (page !== null && page.row !== null) page.panel.refreshChoices(pluginId, spec.optionsFrom)
                                    onAddWanted: if (page !== null && page.row !== null) page.panel.addChoice(pluginId, key)
                                    onPreviewWanted: value => { if (page !== null && page.row !== null) page.panel.previewChoice(pluginId, key, value); }
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

                    // A list of rows the user changes, each a section of
                    // its own after the schema's.
                    Repeater {
                        model: ScriptModel {
                            values: page.settingsRows
                        }
                        RowsList {
                            required property string modelData
                            width: body.width
                            entry: page.statusEntry(modelData)
                            plugin: page.plugin
                            reply: lastPress === null ? "" : page.replyFor(lastPress, entry)
                            onPressed: button => page.press(button, entry)
                            onOpenLink: link => { if (page !== null && page.row !== null) page.panel.openLink(page.row.id, link); }
                            onPageActivated: (id, tab) => { if (page !== null && page.panel !== null) page.panel.openPage(id, tab); }
                        }
                    }

                    Section {
                        width: parent.width
                        visible: page.row !== null && page.row.binds.length > 0
                        title: "Keys"
                        description: "Select a shortcut and press its new keys"
                        // design-system.md § Copy: a line that states a time
                        // says why the limit exists.
                        info: page.panel === null || !page.panel.capture ? ""
                            : "While a shortcut field listens, your other shortcuts do not work. The field stops listening after " + Math.round(page.panel.capture.timeoutMs / 1000) + " seconds, so your shortcuts always start to work again."

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
                    onPositioningComplete: if (page.revealing !== "" && page.revealTab !== "Settings") Qt.callLater(page.revealField)

                    // The manifest's guide to the steps, which opens its
                    // README section in the default browser
                    // (PluginLogic.setupGuideRow); a plugin with no README
                    // to open draws it with no link.
                    Callout {
                        readonly property var guide: page.hasSetup && page.row !== null ? page.row.guide : null
                        width: body.width
                        visible: guide !== null
                        iconName: "book-open"
                        title: guide === null ? "" : guide.title
                        text: guide === null ? "" : guide.text
                        linkText: guide === null || guide.url === "" ? "" : guide.link
                        onActivated: page.panel.openLink(page.row.id, { url: guide.url })
                    }

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
                                    // The key a page reference names the step by (revealField).
                                    readonly property string statusKey: modelData.keys ? "" : modelData.key
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
                                            action: page.row === null ? null : tools ? requiredEntry.modelData.button
                                                : entry === null ? null : Steps.lineAction(Steps.stepButton(entry, page.row.requirements), Steps.stepOpen(entry), page.plugin)
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
                    onPositioningComplete: if (page.revealing !== "" && page.revealTab === "Details") Qt.callLater(page.revealField)

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
                                        // The key a page reference names the row by (revealField).
                                        readonly property string statusKey: modelData
                                        // An optional feature's own action beside its fact.
                                        readonly property var buttons: entry === null ? ({ action: null, aside: null }) : Steps.detailButtons(entry, page.plugin)
                                        width: statusRows.width
                                        entry: page.statusEntry(modelData)
                                        plugin: page.plugin
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

                    // A list of rows that are facts, each a section of its
                    // own after the status sections.
                    Repeater {
                        model: ScriptModel {
                            values: page.detailRows
                        }
                        RowsList {
                            required property string modelData
                            width: body.width
                            entry: page.statusEntry(modelData)
                            plugin: page.plugin
                            reply: lastPress === null ? "" : page.replyFor(lastPress, entry)
                            onPressed: button => page.press(button, entry)
                            onOpenLink: link => { if (page !== null && page.row !== null) page.panel.openLink(page.row.id, link); }
                            onPageActivated: (id, tab) => { if (page !== null && page.panel !== null) page.panel.openPage(id, tab); }
                        }
                    }

                    Section {
                        id: toolsSection
                        // The optional tools, as readings: Setup's Optional
                        // tools step installs the missing or outdated ones.
                        readonly property var tools: page.row === null ? [] : Steps.detailRequirements(page.row.requirements)
                        width: parent.width
                        title: "Tools"
                        visible: tools.length > 0
                        Repeater {
                            model: toolsSection.tools
                            RequirementRow { required property var modelData; width: toolsSection.width; requirement: modelData }
                        }
                    }
                }
            }
        }

        // The mark on the row a page reference opened (revealField): one
        // plate of the list selection's fill under the row, in the scroll
        // area's content beside the page's columns, so no column lays it out
        // as a row of its own, and it scrolls with the row. It fades in, and
        // out once `revealing` clears: at the next scroll, tab or open.
        Rectangle {
            id: revealMark
            objectName: "revealMark"
            parent: layout.scrollArea.contentItem
            z: -1
            radius: Theme.listItem.radius
            color: Theme.listItem.selected
            opacity: page.revealedRow !== null ? 1 : 0
            visible: opacity > 0
            Behavior on opacity {
                enabled: Theme.motion.list.fade.duration > 0
                NumberAnimation { duration: Theme.motion.list.fade.duration; easing.type: Theme.motion.list.fade.easing }
            }
            // The row's box in the content, `space.xs` taller on each side.
            // A page row spans the body to the content's right edge, which
            // leaves no room beside it inside the container inset, so the
            // plate keeps the row's own width.
            function place() {
                const shown = page.revealedRow;
                if (shown === null || parent === null) return;
                const at = shown.mapToItem(parent, 0, 0);
                x = at.x;
                y = at.y - Theme.space.xs;
                width = shown.width;
                height = shown.height + 2 * Theme.space.xs;
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

    // Keep the fade behind the pinned tabs out of view. This sibling of the
    // scroll area covers only the viewport band behind its tab strip.
    Rectangle {
        id: stickySurface
        objectName: "stickyTabsSurface"
        parent: layout.scrollArea
        x: 0
        y: 0
        width: layout.scrollArea.width - layout.scrollArea.rightInset
        height: layout.scrollArea.focusInset + layout.ringRoom + tabs.tabs.height
        color: Theme.color.surface
        z: 1
    }
}
