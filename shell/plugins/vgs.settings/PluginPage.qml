import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Steps.js" as Steps

// One plugin's page, drawn from its manager row alone. The header holds a
// back button, which returns to the list, and the plugin's name as a title
// whose menu lists every plugin, the current one checked, and opens the
// chosen one's page. The body holds every error and the last refusal, then
// two pages under one tab strip (TabPages), Settings first.
//
// Settings holds what a user changes: the enabled switch, the Show in bar
// switch of a plugin with a bar widget and another kind besides bar and
// bar-widget, which stays enabled once unplaced, the switch turning only
// while the plugin is enabled (for a widget-only plugin Enabled is the
// placement), a Setup section with one button per setup screen the
// manifest lists, which opens it through the manager, one settings section
// per schema group (entries without a group first, under `Settings`), one
// section per `list` entry, titled with its label, and the Keys section. A
// plugin with none of those below its switches says so in one line. A
// disabled plugin's fields are read-only, its Enabled switch says to turn
// it on while it has something to change, and its setup buttons take no
// press.
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
    // Whether the Settings page holds nothing below its switches.
    readonly property bool bare: row !== null && row.tuis.length === 0 && sections.length === 0 && lists.length === 0 && row.binds.length === 0

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
            spacing: Theme.stack.group
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
                onCurrentIndexChanged: layout.scrollArea.contentY = 0

                Column {
                    id: settingsPage
                    spacing: Theme.stack.group

                    Column {
                        width: parent.width
                        spacing: Theme.stack.row

                        Field {
                            id: enabledField
                            width: parent.width
                            label: "Enabled"
                            inline: true
                            hint: page.isSelf ? "Turning off Settings closes this window." : page.row !== null && !page.row.enabled && !page.bare ? "Turn on " + page.row.name + " to change its settings and shortcuts." : ""
                            Switch {
                                size: "sm"
                                checked: page.row !== null && page.row.enabled
                                onToggled: {
                                    checked = Qt.binding(() => page.row !== null && page.row.enabled);
                                    if (page.row !== null) page.panel.toggle(page.row.id);
                                }
                            }
                        }

                        // Once Settings is off no window is left to hold a
                        // button that turns it on, so its own page keeps the
                        // command that does, behind Show command (D061).
                        CommandDisclosure {
                            x: enabledField.valueX
                            width: parent.width - x - enabledField.rightPadding
                            visible: page.isSelf
                            command: page.row === null ? "" : "vgshell plugin enable " + page.row.id
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
                                    // An editor loses focus while the page is torn
                                    // down and emits apply into a page that is
                                    // gone; that edit was never committed.
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

                            ListField {
                                width: listSection.width
                                pluginId: page.row.id
                                key: listSection.modelData
                                spec: page.row.schema[listSection.modelData]
                                value: page.row.settings[listSection.modelData]
                                choices: page.row.settingChoices[listSection.modelData] || []
                                editable: page.editable
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
                            KeyField {
                                required property var modelData
                                width: body.width
                                pluginId: page.row.id
                                bind: modelData
                                editable: page.editable
                                capture: page.panel.capture
                                onApplyKey: key => { if (page !== null && page.row !== null) page.panel.writeKey(pluginId, modelData.shortcut, key); }
                            }
                        }
                    }
                }

                Column {
                    id: detailsPage
                    spacing: Theme.stack.group

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
    }
}
