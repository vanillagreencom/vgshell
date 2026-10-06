import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Steps.js" as Steps

// One plugin's page, drawn from its manager row alone. The header holds a
// back button, which returns to the list, and the plugin's name as a title
// whose menu lists every plugin, the current one checked, and opens the
// chosen one's page. Open summons the plugin's window or panel. The body
// holds every error and the last refusal, then two pages under one tab
// strip (TabPages), Settings first.
//
// Settings holds what a user changes: the enabled switch, the Show in bar
// switch of a plugin with a bar widget and another kind besides bar and
// bar-widget, which stays enabled once unplaced, the switch turning only
// while the plugin is enabled (for a widget-only plugin Enabled is the
// placement), a Setup section with one button per setup screen the
// manifest lists, which opens it through the manager, one settings section
// per schema group (entries without a group first, under `Settings`), one
// section per `list` entry, titled with its label, and the Keys section,
// then, for a plugin of kind `pane` while a panes holder is enabled, a
// button named for the holder that opens the plugin's page there. A
// plugin with none of those below its switches says so in one line. A
// disabled plugin's fields are read-only, its Enabled switch says to turn
// it on while it has something to change, and its setup and holder
// buttons take no press.
//
// Details holds what a user reads: the description, in the hint role in
// the muted colour, the capabilities, the listing metadata, the Update and
// Remove buttons of an installed plugin, one status section per status
// group (entries without a group first, under `Status`), whose values are
// read-only and whose setup steps run through the manager (D061), and the
// Requirements section with an Install all missing button while one is
// missing. A disabled plugin's status rows say it has not reported.
//
// `open` shows Settings, so every opened page starts there; a change of
// the manager's rows moves neither the page nor an edit. A page change
// returns the body to its top, where the strip is. The header and body
// share one content edge, the scroll bar sits in the window's right inset,
// and each inline value draws at line height 1, centred on its label. The
// switches, and the listing metadata with Manage, are each one key/value
// group `stack.row` apart, with one key/value row height.
//
// A text field and a key typed as text wait for a save (EditSet): while one
// holds an unsaved edit the footer shows the save bar, whose Save, and
// Ctrl+S anywhere on the page, write every such edit, and whose Discard
// puts the configuration's values back. The bar reads Saved once the last
// edit is written, and a refused one keeps its field edited and the bar
// shown. A change to Details with an unsaved edit returns to Settings and
// asks the panel first.
FocusScope {
    id: page

    // The Settings panel: its rows, its replies and its navigation.
    required property Item panel
    // The manager row this page draws, or null.
    property var row: null

    readonly property bool editable: row !== null && row.enabled
    // Whether a requirement of the plugin was missing at the last scan.
    readonly property bool requirementMissing: row !== null && row.requirements.some(Steps.requirementApplies)
    readonly property bool isSelf: row !== null && panel.shell !== null && row.id === panel.shell.manifest.id
    readonly property alias scrollArea: layout.scrollArea
    readonly property alias titleMenu: menu
    readonly property alias title: titleHeader.titleButton
    readonly property alias initialFocus: back
    // The manager row of the panes holder that shows this plugin's page,
    // or null.
    readonly property var paneHolder: row === null || row.paneHolder === "" ? null : panel.plugins.find(p => p.id === row.paneHolder) || null
    // Whether the Settings page holds nothing below its switches.
    readonly property bool bare: row !== null && row.tuis.length === 0 && sections.length === 0 && lists.length === 0 && row.binds.length === 0 && paneHolder === null
    // Whether a field of the page holds an unsaved edit.
    readonly property bool dirty: unsaved.edited
    property var extraKeySlots: ({})
    property string captureKeySlot: ""
    onRowChanged: {
        extraKeySlots = ({});
        captureKeySlot = "";
    }

    // The schema's keys by section: [{ group, keys }], entries without a
    // group first under "", then each group in the order its first entry
    // appears. The manifest's key order is the schema's. A `list` entry
    // has its own section, `lists`.
    readonly property var sections: {
        if (row === null) return [];
        const out = [{ group: "", keys: [] }];
        for (const key of Object.keys(row.schema).filter(key => row.schema[key].type !== "list")) {
            const group = row.schema[key].group === undefined ? "" : row.schema[key].group;
            let section = out.find(s => s.group === group);
            if (section === undefined) {
                section = { group: group, keys: [] };
                out.push(section);
            }
            section.keys.push(key);
        }
        return out.filter(s => s.keys.length > 0);
    }

    readonly property var lists: row === null ? [] : Object.keys(row.schema).filter(key => row.schema[key].type === "list")

    // The displayable status entries' keys by section, as `sections` holds
    // the schema's: [{ group, keys }], ungrouped first, then each group in
    // the order its first entry appears. The row's `status` is in manifest
    // order and holds no `data`, `choices` or hidden entry.
    readonly property var statusSections: {
        if (row === null) return [];
        const out = [{ group: "", keys: [] }];
        for (const entry of row.status) {
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

    // Show the page as it opens: on Settings, the back button focused.
    function open(reason) {
        tabs.currentIndex = 0;
        back.forceActiveFocus(reason);
    }

    // Write every unsaved edit; answers whether none is left.
    function save() {
        return unsaved.save();
    }

    function discard() {
        unsaved.discard();
    }

    function bindKeys(bind) {
        if (bind === null) return [];
        // `keys` can arrive as a list-like rather than an Array, as from a ListModel.
        if (bind.keys !== undefined && bind.keys !== null) return Array.from(bind.keys);
        return bind.key === null || bind.key === undefined ? [] : [bind.key];
    }

    function keySlotRows(bind) {
        const keys = bindKeys(bind);
        const extra = extraKeySlots[bind.shortcut] || 0;
        const total = Math.max(1, keys.length + extra);
        const out = [];
        for (let i = 0; i < total; i++)
            out.push({ shortcut: bind.shortcut, index: i, last: i === total - 1, bind: Object.assign({}, bind, { key: i < keys.length ? keys[i] : null, description: i === 0 ? bind.description : "", keys: keys }) });
        return out;
    }

    function addKeySlot(shortcut, index) {
        const next = Object.assign({}, extraKeySlots);
        next[shortcut] = (next[shortcut] || 0) + 1;
        captureKeySlot = shortcut + ":" + index;
        extraKeySlots = next;
    }

    function removeKeySlot(shortcut) {
        const next = Object.assign({}, extraKeySlots);
        if (next[shortcut] > 1) next[shortcut] -= 1;
        else delete next[shortcut];
        extraKeySlots = next;
    }

    function keySlotAccepted(bind, index, key) {
        if (key === undefined) {
            const next = Object.assign({}, extraKeySlots);
            delete next[bind.shortcut];
            extraKeySlots = next;
            return;
        }
        if (index >= bindKeys(bind).length) removeKeySlot(bind.shortcut);
    }

    function keyValueAfter(bind, index, key) {
        if (key === undefined) return undefined;
        const keys = bindKeys(bind);
        if (key === null) {
            if (index < keys.length) keys.splice(index, 1);
        } else if (index < keys.length) {
            keys[index] = key;
        } else {
            keys.push(key);
        }
        if (keys.length === 0) return null;
        return keys.length === 1 ? keys[0] : keys;
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

        header: [
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
                // True while the handler puts Settings back.
                property bool returning: false
                onCurrentIndexChanged: {
                    if (returning) return;
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

                    Column {
                        width: parent.width
                        spacing: Theme.stack.row

                        Field {
                            width: parent.width
                            label: "Enabled"
                            inline: true
                            visible: page.row !== null && !page.row.alwaysOn
                            hint: page.row !== null && !page.row.enabled && !page.bare ? "Turn on " + page.row.name + " to change its settings and shortcuts." : ""
                            Switch {
                                size: "sm"
                                checked: page.row !== null && page.row.enabled
                                onToggled: {
                                    checked = Qt.binding(() => page.row !== null && page.row.enabled);
                                    if (page.row !== null) page.panel.toggle(page.row.id);
                                }
                            }
                        }

                        Field {
                            width: parent.width
                            label: "Show in bar"
                            inline: true
                            visible: page.row !== null && page.row.kinds.indexOf("bar-widget") !== -1 && page.row.kinds.some(kind => kind !== "bar" && kind !== "bar-widget")
                            hint: page.row !== null && !page.row.enabled ? "Turn on " + page.row.name + " to show it in the bar." : ""
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
                    }

                    Label {
                        role: "hint"
                        color: Theme.color.textMuted
                        text: "This plugin has no other settings."
                        visible: page.bare
                        width: parent.width
                        wrapMode: Text.Wrap
                    }

                    // The plugin's own setup screens, each a TUI its
                    // manifest lists, opened through the manager as a status
                    // step is. A keyed model keeps each button while the
                    // rows are replaced, and a refusal reads under them.
                    Section {
                        id: setup
                        width: parent.width
                        visible: page.row !== null && page.row.tuis.length > 0
                        title: "Setup"
                        description: "Each button opens a setup window."

                        Column {
                            width: setup.width
                            spacing: Theme.field.gap

                            Flow {
                                width: parent.width
                                spacing: Theme.stack.inline
                                Repeater {
                                    model: ScriptModel {
                                        values: page.row === null ? [] : page.row.tuis
                                        objectProp: "name"
                                    }
                                    Button {
                                        required property var modelData
                                        text: modelData.label
                                        iconName: modelData.icon
                                        variant: "secondary"
                                        enabled: page.editable
                                        onClicked: page.panel.openTui(page.row.id, modelData.name)
                                    }
                                }
                            }

                            Repeater {
                                model: ScriptModel {
                                    values: page.row === null ? [] : page.row.tuis
                                    objectProp: "name"
                                }
                                Label {
                                    required property var modelData
                                    role: "hint"
                                    color: Theme.color.danger
                                    text: page.row === null ? "" : page.panel.replyOf(page.row.id, page.panel.tuiKey(modelData.name))
                                    visible: text !== ""
                                    width: setup.width
                                    wrapMode: Text.Wrap
                                }
                            }
                        }
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
                            title: section.modelData.group === "" ? "Settings" : section.modelData.group

                            Repeater {
                                model: ScriptModel {
                                    values: section.modelData.keys
                                }
                                SettingField {
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
                            width: body.width
                            title: page.row.schema[modelData].label
                            description: page.row.schema[modelData].description === undefined ? "" : page.row.schema[modelData].description
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
                            }
                        }
                    }

                    Section {
                        width: parent.width
                        visible: page.row !== null && page.row.binds.length > 0
                        title: "Keys"
                        description: "Select a shortcut and press its new keys."

                        Repeater {
                            model: ScriptModel {
                                values: page.row === null ? [] : page.row.binds
                                objectProp: "shortcut"
                            }
                            Column {
                                required property var modelData
                                width: body.width
                                spacing: Theme.stack.row

                                Repeater {
                                    model: ScriptModel {
                                        values: page.keySlotRows(modelData)
                                        objectProp: "index"
                                    }
                                    KeyField {
                                        id: keyField
                                        required property var modelData
                                        width: parent.width
                                        pluginId: page.row.id
                                        bind: modelData.bind
                                        editable: page.editable
                                        capture: page.panel.capture
                                        edits: unsaved
                                        addVisible: modelData.last
                                        resetVisible: modelData.index === 0
                                        onAddKey: page.addKeySlot(modelData.shortcut, modelData.index + 1)
                                        onRemovalAsked: row => page.panel.confirmRemoval(keyField, row)
                                        onLineAsked: row => page.panel.openUserLine(row)
                                        onApplyKey: key => {
                                            if (page === null || page.row === null) return;
                                            const value = page.keyValueAfter(bind, modelData.index, key);
                                            const accepted = Reply.isOk(page.panel.writeKey(pluginId, modelData.shortcut, value));
                                            const slot = modelData.index;
                                            const slotBind = bind;
                                            // Settle first: closing the added slot can rebuild the
                                            // slots and take this field with them.
                                            settle(key, accepted);
                                            if (accepted) page.keySlotAccepted(slotBind, slot, key);
                                        }
                                        Component.onCompleted: {
                                            const slot = modelData.shortcut + ":" + modelData.index;
                                            if (page.captureKeySlot === slot) {
                                                shortcutField.start();
                                                page.captureKeySlot = "";
                                            }
                                        }
                                    }
                                }
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

                Column {
                    id: detailsPage
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

                        // A bundled plugin is disabled, never updated or removed.
                        Field {
                            width: parent.width
                            label: "Manage"
                            inline: true
                            visible: page.row !== null && page.row.source === "installed"
                            hint: "You can review changes before you apply them."
                            Row {
                                spacing: Theme.stack.inline
                                Button {
                                    text: "Update"
                                    iconName: "refresh-cw"
                                    variant: "secondary"
                                    onClicked: page.panel.updatePlugin(page.row.id)
                                }
                                Button {
                                    text: "Remove"
                                    iconName: "trash"
                                    variant: "danger"
                                    onClicked: page.panel.removePlugin(page.row.id)
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
                                        required property string modelData
                                        width: statusRows.width
                                        entry: page.statusEntry(modelData)
                                        panel: page.panel
                                        pluginId: page.row === null ? "" : page.row.id
                                        secretLabel: page.row === null ? "" : page.row.secretLabel
                                    }
                                }
                            }
                        }
                    }

                    Section {
                        width: parent.width
                        visible: page.row !== null && page.row.requirements.length > 0
                        title: "Requirements"
                        description: "Tools this plugin needs"

                        // Each command is one group, and the Install row after them.
                        GroupList {
                            id: requirementRows
                            width: parent.width

                            Repeater {
                                model: ScriptModel {
                                    values: page.row === null ? [] : page.row.requirements
                                    objectProp: "command"
                                }
                                RequirementRow {
                                    required property var modelData
                                    width: requirementRows.width
                                    requirement: modelData
                                }
                            }

                            Field {
                                width: requirementRows.width
                                label: "Missing"
                                inline: true
                                visible: page.requirementMissing
                                hint: "Review the missing tools before you install them."
                                Button {
                                    text: "Install all missing"
                                    iconName: "download"
                                    variant: "primary"
                                    onClicked: page.panel.installRequirements(page.row.id)
                                }
                            }
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
