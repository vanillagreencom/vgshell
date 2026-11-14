import QtQuick
import qs.Commons
import qs.Ui

// The gallery: every component in every variant and state, in a scrolling
// window, so a theme author sees a whole theme at once. It is built only
// while summoned. It composes Pane as every window does: the title in
// windowTitle with its line under it, then one Section per group, each a
// SectionHeader followed by blocks `stack.group` apart. Controls side by
// side sit `stack.inline` apart, and controls of different heights centre
// on one line inside the group that wraps; the validation row reads every
// component of the module back from `examples`.
Item {
    id: root

    property var shell: null
    property var payload: ({})
    // The root of every example, for the row that checks each component of
    // the module is drawn here.
    readonly property Item examples: root
    property Item initialFocus: layout.scrollArea.focusProxy

    KeyNav {}

    function open(payloadJson) { payload = payloadJson ? JSON.parse(payloadJson) : {}; }
    function close() {}
    // A sample of the one way a plugin tells the user something.
    function notify() {
        const reply = shell.notify.send({ title: "Saved", message: "The theme was saved", tone: "success", icon: "check" });
        if (reply !== "ok") console.error("gallery: notice " + reply);
        return reply;
    }

    implicitWidth: Theme.size.panel.lg
    implicitHeight: Theme.size.panel.maxHeight

    Pane {
        id: layout
        anchors.fill: parent
        container: "window"
        Component.onCompleted: scrollArea.keyboardScroll = true

        title: "VGS Components"
        subtitle: [
            Column {
                width: layout.contentWidth
                spacing: Theme.row.lineGap
                Label { role: "hint"; color: Theme.color.textMuted; text: "Preview controls with the " + Theme.name + " theme."; width: parent.width; wrapMode: Text.Wrap }
            }
        ]

            Column {

                id: sections
                width: layout.contentWidth
                spacing: Theme.stack.group


                Section {
                    title: "Surfaces"
                    description: "Panel background levels"
                Flow {
                    width: parent.width
                    spacing: Theme.stack.inline
                    Repeater {
                        model: ["base", "raised", "sunken"]
                        Surface {
                            id: sample
                            required property string modelData
                            level: modelData
                            width: Theme.size.panel.sm / 2
                            height: Theme.size.panel.sm / 4
                            Label { role: "label"; text: sample.modelData; anchors.centerIn: parent }
                        }
                    }
                }
                }
                Section {
                    title: "Typography"
                    rowSpacing: Theme.stack.group
                    description: "Text roles, sizes and label-value pairs"
                Column {
                    spacing: Theme.space.xxs
                    Repeater {
                        model: Object.keys(Theme.text)
                        Label { required property string modelData; role: modelData; text: modelData + " " + Theme.text[modelData].size }
                    }
                }
                Column {
                    width: parent.width
                    spacing: Theme.stack.row
                    Field { label: "Agents running"; inline: true; info: "How many AI agents run now."; width: parent.width; Label { role: "value"; text: "3"; width: parent.width; elide: Text.ElideRight } }
                    Field { label: "Last check"; inline: true; info: "When Agent Warden last checked your agents. If it stops changing, open the Agent Warden panel and choose Start checks."; width: parent.width; Label { role: "value"; text: "9/30/26 3:57 PM"; width: parent.width; elide: Text.ElideRight } }
                    Field { label: "Warden"; inline: true; info: "Shows whether Agent Warden is watching your AI agents and whether any of them needs your attention."; width: parent.width; Badge { text: "Within limits"; tone: "success" } }
                }
                ImageText {
                    width: parent.width
                    maximumLineCount: 2
                    segments: [
                        { markup: "An image sits in the line at the text's height " },
                        { image: Qt.resolvedUrl("sample-emoji.png"), alt: ":sample:" },
                        { markup: " and a text too long for its lines ends at a whole word or image." }
                    ]
                }
                }
                Section {
                    title: "Buttons"
                    rowSpacing: Theme.stack.group
                    description: "Five variants, three sizes, checked and disabled, and a row's action"
                Flow {
                    width: parent.width
                    spacing: Theme.stack.inline
                    Repeater {
                        model: ["primary", "secondary", "tertiary", "ghost", "danger"]
                        Button { required property string modelData; variant: modelData; text: modelData; iconName: "arrow-right" }
                    }
                }
                // The sizes, centred on one line inside a group that wraps.
                Flow {
                    width: parent.width
                    spacing: Theme.stack.inline
                    Row {
                        spacing: Theme.stack.inline
                        Button { text: "Small"; size: "sm"; variant: "secondary"; anchors.verticalCenter: parent.verticalCenter }
                        Button { text: "Medium"; variant: "secondary"; anchors.verticalCenter: parent.verticalCenter }
                        Button { text: "Large"; size: "lg"; variant: "secondary"; anchors.verticalCenter: parent.verticalCenter }
                    }
                    Row {
                        spacing: Theme.stack.inline
                        ToggleButton { text: "Pinned"; checked: true }
                        Button { text: "Disabled"; enabled: false }
                    }
                    // A surface's own form: bare words, and a soft fill.
                    Row {
                        spacing: Theme.stack.inline
                        Button {
                            text: "Bare"
                            variant: "ghost"
                            size: "sm"
                            radius: Theme.radius.full
                            hoverFill: Theme.button.variant.ghost.background
                            textColor: Theme.color.textMuted
                            ringColor: Theme.color.warning
                        }
                        Button {
                            text: "Soft fill"
                            variant: "ghost"
                            size: "sm"
                            radius: Theme.radius.full
                            restFill: Theme.color.surfaceRaised
                            hoverFill: Theme.color.surfaceHover
                            ringColor: Theme.color.warning
                        }
                    }
                }
                // The bar's items: workspace pills, the first focused; an
                // icon alone; the corner count at 1 and above 9 (9+) and at
                // its warning and danger levels; a spinner; and readings
                // with a detail beside them.
                Rectangle {
                    width: parent.width
                    height: Theme.bar.height
                    color: Theme.bar.background
                    Row {
                        x: Theme.bar.padding
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.bar.item.gap
                        BarItem { text: "1"; active: true }
                        BarItem { text: "2" }
                        BarItem { iconName: "settings"; label: "Settings" }
                        BarItem { iconName: "route"; count: "1"; label: "Tailscale, 1 device connected to this one" }
                        BarItem { iconName: "refresh-cw"; count: "12"; tone: Theme.color.accent; label: "Updates, 12 updates" }
                        BarItem { iconName: "shield-alert"; count: "2"; countLevel: "warning"; label: "Agent Warden, 2 warnings" }
                        BarItem { iconName: "shield-x"; count: "1"; countLevel: "danger"; label: "Agent Warden, 1 problem" }
                        BarItem { iconName: "refresh-cw"; spinning: true; label: "Updates" }
                        BarItem { iconName: "cpu"; text: "5%"; detail: "74°"; separator: "/"; detailLevel: "warning"; label: "CPU reading" }
                        BarItem { caption: "GPU"; text: "92%"; detail: "88°"; separator: "/"; textLevel: "danger"; detailLevel: "warning"; label: "GPU reading" }
                    }
                }
                Column {
                    width: parent.width
                    spacing: Theme.stack.row
                    Field { label: "Rest"; inline: true; width: parent.width; IconButton { iconName: "settings"; label: "Settings" } }
                    Field { label: "Pressed"; inline: true; width: parent.width; IconButton { iconName: "mouse-pointer-click"; label: "Pressed"; down: true } }
                    Field { label: "Checked"; inline: true; width: parent.width; IconButton { iconName: "check"; label: "Checked"; checkable: true; checked: true } }
                    Field { label: "Disabled"; inline: true; width: parent.width; IconButton { iconName: "ban"; label: "Disabled"; enabled: false } }
                    Field { label: "Danger"; inline: true; width: parent.width; IconButton { iconName: "x"; label: "Close"; variant: "danger" } }
                    // A surface's own look hands the glyph and ring colours.
                    Field { label: "Look colours"; inline: true; width: parent.width; IconButton { iconName: "mic"; label: "Look colours"; restColor: Theme.color.info; activeColor: Theme.color.text; onColor: Theme.color.success; ringColor: Theme.color.warning } }
                    Field { label: "Look colours, on"; inline: true; width: parent.width; IconButton { iconName: "mic-off"; label: "Look colours, on"; checkable: true; checked: true; restColor: Theme.color.info; activeColor: Theme.color.text; onColor: Theme.color.success; ringColor: Theme.color.warning } }
                }
                // A key/value row's action after the row's value, then
                // pressed, disabled, in the danger tone, which leads with
                // its mark, and two actions side by side; the Focus
                // section draws its ring.
                Column {
                    width: parent.width
                    spacing: Theme.stack.row
                    Field {
                        label: "Row action"
                        inline: true
                        width: parent.width
                        Row {
                            spacing: Theme.stack.inline
                            Badge { text: "To do"; tone: "warning"; anchors.verticalCenter: parent.verticalCenter }
                            RowAction { text: "Set up voice"; anchors.verticalCenter: parent.verticalCenter }
                        }
                    }
                    Field { label: "Pressed"; inline: true; width: parent.width; RowAction { text: "Pressed"; down: true } }
                    Field { label: "Disabled"; inline: true; width: parent.width; RowAction { text: "Disabled"; enabled: false } }
                    Field { label: "Danger"; inline: true; width: parent.width; RowAction { text: "Remove"; tone: "danger" } }
                    // A word that acts, as the pointer finds it.
                    Field {
                        label: "Word under the pointer"
                        inline: true
                        width: parent.width
                        Label {
                            id: hoveredWord
                            text: "Show all"
                            TextUnderline { label: hoveredWord; visible: true }
                        }
                    }
                    Field {
                        label: "Side by side"
                        inline: true
                        width: parent.width
                        RowActions {
                            RowAction { text: "Update" }
                            RowAction { text: "Remove"; tone: "danger" }
                        }
                    }
                }

                }
                Section {
                    title: "Choices"
                    rowSpacing: Theme.stack.group
                    description: "Switch, checkbox, radio, segments, tiles and select"
                Column {
                    width: parent.width
                    spacing: Theme.stack.row
                    Field { label: "Small off"; inline: true; width: parent.width; Switch { size: "sm"; text: "Off" } }
                    Field { label: "Small on"; inline: true; width: parent.width; Switch { size: "sm"; text: "On"; checked: true } }
                    Field { label: "Small disabled"; inline: true; width: parent.width; Switch { size: "sm"; text: "Disabled"; checked: true; enabled: false } }
                    Field { label: "Medium off"; inline: true; width: parent.width; Switch { size: "md"; text: "Off" } }
                    Field { label: "Medium on"; inline: true; width: parent.width; Switch { size: "md"; text: "On"; checked: true } }
                    Field { label: "Medium disabled"; inline: true; width: parent.width; Switch { size: "md"; text: "Disabled"; checked: true; enabled: false } }
                    // A locked switch says why and carries the step that
                    // unlocks it; a preview runs no step.
                    Field { label: "Small locked"; inline: true; width: parent.width; Switch { size: "sm"; text: "Locked"; disabledReason: "Sign in to your VPN account to turn on this switch"; unlock: ({ label: "Sign in", run: () => {} }) } }
                    Field { label: "Medium locked"; inline: true; width: parent.width; Switch { size: "md"; text: "Locked"; disabledReason: "Sign in to your VPN account to turn on this switch"; unlock: ({ label: "Sign in", run: () => {} }) } }
                }
                Flow {
                    width: parent.width
                    spacing: Theme.stack.inline
                    Checkbox { text: "Unchecked" }
                    Checkbox { text: "Checked"; checked: true }
                    Checkbox { text: "Disabled"; checked: true; enabled: false }
                    Column {
                        Radio { text: "One"; checked: true }
                        Radio { text: "Two" }
                        Radio { text: "Disabled"; enabled: false }
                    }
                }
                Flow {
                    width: parent.width
                    spacing: Theme.stack.inline
                    SegmentedControl { model: ["Day", "Week", "Month"]; currentIndex: 1 }
                    Select { model: ["Default", "Ocean", "Forest"] }
                    Select { model: ["Disabled"]; enabled: false }
                    // Offers that each play on request, ended by an Add
                    // entry, as a voice field draws them. Play does nothing
                    // here.
                    Select {
                        objectName: "gallerySelectActions"
                        property string focusExample: "Select entry action"
                        textRole: "label"
                        iconRole: "icon"
                        actionRole: "preview"
                        entryAction: ({ iconName: "volume-2", label: "Play" })
                        model: [{ label: "Puck", preview: true }, { label: "Kore", preview: true }, { label: "Add a voice", icon: "plus" }]
                    }
                }
                Column {
                    width: parent.width
                    spacing: Theme.stack.row
                    Field { label: "Tiles"; inline: true; width: parent.width; TileGroup { width: parent.width; model: [{ text: "Area", icon: "scan" }, { text: "Window", icon: "app-window" }, { text: "Display", icon: "monitor" }]; currentIndex: 1 } }
                    Field { label: "Tiles unavailable"; inline: true; width: parent.width; TileGroup { width: parent.width; model: [{ text: "Area", icon: "scan" }, { text: "Picker", icon: "screen-share", available: false }]; currentIndex: 0 } }
                    Field { label: "Tiles disabled"; inline: true; width: parent.width; TileGroup { width: parent.width; enabled: false; model: [{ text: "Area", icon: "scan" }, { text: "Window", icon: "app-window" }]; currentIndex: 0 } }
                }

                }
                Section {
                    title: "Inputs"
                    rowSpacing: Theme.stack.group
                    description: "Text fields, actions, errors and hints"
                TextField { variant: "search"; searchUnderline: false; width: parent.width; placeholderText: "Search plugins"; leadingIcon: "search" }
                TextField { variant: "search"; width: parent.width; placeholderText: "Search"; leadingIcon: "search" }
                TextField { variant: "search"; width: parent.width; text: "Search error"; error: true }
                TextField { variant: "search"; width: parent.width; text: "Read-only search"; readOnly: true }
                Flow {
                    width: parent.width
                    spacing: Theme.stack.inline
                    TextField { placeholderText: "Text field" }
                    TextField { id: named; text: "acme.weather"; trailingIcon: "package"; actions: [ IconButton { iconName: "x"; label: "Clear"; size: "sm"; onClicked: named.clear() } ] }
                    TextField { text: "taken"; error: true }
                    TextField { text: "read only"; readOnly: true; enabled: false }
                }
                Field { label: "Display name"; hint: "Shown in the bar"; width: parent.width; TextField { width: parent.width; placeholderText: "Weather" } }
                Field { label: "Format"; error: "Not a Qt date format"; inline: true; width: parent.width; TextField { width: parent.width; text: "HH:mm:" } }
                SettingField {
                    id: schemaSwitch
                    width: parent.width
                    key: "enabled"
                    spec: ({ type: "boolean", label: "Schema switch" })
                    value: true
                    onApply: value => schemaSwitch.value = value
                }
                SettingField {
                    id: schemaChoice
                    width: parent.width
                    key: "choice"
                    spec: ({ type: "enum", label: "Schema choice", options: [{ value: "first", label: "First" }, { value: "second", label: "Second" }] })
                    value: "first"
                    onApply: value => schemaChoice.value = value
                }
                SettingField {
                    id: schemaText
                    width: parent.width
                    key: "text"
                    spec: ({ type: "string", label: "Schema text", presets: [{ value: "Default" }], allowCustom: true })
                    value: "Custom text"
                    onApply: value => schemaText.value = value
                }
                Column {
                    width: parent.width
                    spacing: Theme.stack.row
                    Field { label: "Switch"; inline: true; width: parent.width; Switch { size: "sm"; checked: true } }
                    Field { label: "Text"; inline: true; width: parent.width; Label { role: "value"; text: "Inline value"; width: parent.width; elide: Text.ElideRight } }
                    Field { label: "Badge"; inline: true; width: parent.width; Badge { text: "synced"; tone: "success" } }
                    Field { label: "Action"; inline: true; width: parent.width; RowAction { text: "Open" } }
                    Field { label: "Select"; inline: true; hint: "Hints start under the value column."; width: parent.width; Select { width: parent.width; model: ["Default", "Ocean", "Forest"] } }
                }
                Column {
                    width: parent.width
                    spacing: Theme.stack.row
                    FormRow { label: "Natural scroll"; width: parent.width; Switch { size: "sm"; checked: true } }
                    FormRow { label: "Pointer speed"; warning: "Overridden"; width: parent.width; Slider { from: 0; to: 100; value: 40; width: parent.width } }
                }
                // ValueSourceRow in each state, a value the theme can set
                // and one mapped to a Hyprland option. Its actions are
                // RowActions, whose focus example stands above.
                Column {
                    width: parent.width
                    spacing: Theme.stack.row
                    ValueSourceRow { id: themeSource; label: "Set by theme"; width: parent.width; themeOffered: true; source: "theme"; themeValue: 8; formatValue: value => value + " px"; Slider { from: 0; to: 32; value: themeSource.shownValue; width: parent.width } }
                    ValueSourceRow { id: userSource; label: "User value"; width: parent.width; themeOffered: true; source: "user"; themeValue: 8; userValue: 12; formatValue: value => value + " px"; Slider { from: 0; to: 32; value: userSource.shownValue; width: parent.width } }
                    ValueSourceRow { id: hyprlandSource; label: "Hyprland value"; width: parent.width; themeOffered: true; source: "hyprland"; themeValue: 8; path: "decoration.rounding"; hyprland: ({ values: { "decoration.rounding": 10 }, userValues: [], overridden: [] }); Slider { from: 0; to: 32; value: hyprlandSource.shownValue; width: parent.width } }
                    ValueSourceRow { id: configSource; label: "Hyprland line"; width: parent.width; themeOffered: true; source: "user"; themeValue: 8; userValue: 12; path: "decoration.rounding"; formatValue: value => value + " px"; hyprland: ({ values: {}, userValues: [{ path: "decoration.rounding", value: 10 }], overridden: [] }); Slider { from: 0; to: 32; value: configSource.shownValue; width: parent.width } }
                    ValueSourceRow { label: "Overridden"; width: parent.width; source: "user"; userValue: true; path: "input.natural_scroll"; hyprland: ({ values: {}, userValues: [], overridden: ["input.natural_scroll"] }); Switch { size: "sm"; checked: true } }
                }
                Field { label: "Command"; hint: "Multi-line command text"; width: parent.width; TextArea { width: parent.width; text: "echo hello\nprintf '%s\\n' done" } }
                Field { label: "Date"; hint: "A keyboard picker"; width: parent.width; DateField { date: "2026-01-05" } }
                Field { label: "Time"; hint: "Use Up and Down to change the minutes"; width: parent.width; TimeField { text: "09:00" } }
                Field { label: "Folder"; hint: "A directory picker"; width: parent.width; PathField { width: parent.width; path: ""; placeholderText: "Choose a folder" } }
                Field { label: "Shortcut"; hint: "Key caps and a typed combo; the Settings Keys rows also capture pressed keys"; width: parent.width; ShortcutField { id: shortcutSample; width: parent.width; keys: ["SUPER+SPACE"]; onTyped: text => shortcutSample.keys = text === "" ? [] : [text.toUpperCase()]; onCleared: shortcutSample.keys = [] } }
                BindField { id: bindSample; width: parent.width; hint: "A plugin bind: what it does beside its key"; bind: ({ shortcut: "toggle", key: "SUPER+SPACE", default: "SUPER+SPACE", description: "Open or close the launcher" }); onApplyKey: key => bindSample.bind = Object.assign({}, bindSample.bind, { key: key === null ? null : key.toUpperCase() }) }
                Field { label: "Weekdays"; hint: "Choose the days for a schedule"; width: parent.width; WeekdayChipGroup { selected: ["mon", "wed", "fri"] } }
                Field { label: "Times"; hint: "Sorted time chips"; width: parent.width; TimeChipList { width: parent.width; times: ["09:00", "17:30"] } }
                Slider { from: 0; to: 100; value: 40; width: parent.width }
                Slider { from: 0; to: 100; value: 70; width: parent.width; enabled: false }
                // SavedSlider beside its reading; a release keeps the value.
                // Its slider is the Slider whose focus example stands below.
                SavedSlider { id: savedSample; property real kept: 12; width: parent.width; from: 0; to: 32; shown: kept; formatValue: value => Math.round(value) + " px"; onSaved: value => savedSample.kept = value }
                // NumberSettingField: presets with Custom… and its slider
                // row, a bounded number's slider, and a read-only field.
                // A choice writes the sample's value.
                Column {
                    width: parent.width
                    spacing: Theme.stack.row
                    NumberSettingField { id: presetNumber; width: parent.width; spec: ({ type: "number", label: "Refresh", description: "How often it checks", min: 1, max: 600, step: 1, unit: "seconds", allowCustom: true, presets: [{ value: 60 }, { value: 300 }] }); value: 90; onApply: value => presetNumber.value = value }
                    NumberSettingField { id: sliderNumber; width: parent.width; spec: ({ type: "number", label: "Frame rate", min: 1, max: 120, step: 1 }); value: 30; onApply: value => sliderNumber.value = value }
                    NumberSettingField { width: parent.width; editable: false; spec: ({ type: "number", label: "Read-only", unit: "%", presets: [{ value: 20 }, { value: 50 }] }); value: 20 }
                }
                // IdleTimeField: Immediately held, a time with the warning
                // of a stage that fires early, an owner that is off and no
                // owner, each from a field as the core lends it.
                Column {
                    width: parent.width
                    spacing: Theme.stack.row
                    readonly property var lockSpec: ({ type: "number", label: "Lock after", min: 0, max: 86400, step: 30, unit: "seconds", allowCustom: true, presets: [{ value: 0, label: "Never" }, { value: 60 }, { value: 300 }, { value: 600 }] })
                    IdleTimeField { id: idleSample; width: parent.width; field: ({ stage: "lock", plugin: "acme.lock", name: "Lock", setting: "after", spec: parent.lockSpec, value: 150, reason: "", immediately: 150, identity: "" }); onApply: value => idleSample.field = Object.assign({}, idleSample.field, { value: value }) }
                    IdleTimeField { width: parent.width; warning: "Locks before the screensaver starts"; field: ({ stage: "lock", plugin: "acme.lock", name: "Lock", setting: "after", spec: parent.lockSpec, value: 60, reason: "", immediately: 150, identity: "" }) }
                    IdleTimeField { width: parent.width; field: ({ stage: "lock", plugin: "acme.lock", name: "Lock", setting: "after", spec: parent.lockSpec, value: 300, reason: "off", immediately: 0, identity: "" }) }
                    IdleTimeField { width: parent.width; field: ({ stage: "lock", plugin: "", name: "", setting: "", spec: null, value: null, reason: "none", immediately: 0, identity: "" }) }
                }

                }
                Section {
                    title: "Groups"
                    description: "Status rows with hints and setup actions"
                GroupList {
                    id: groups
                    width: parent.width
                    Column {
                        width: groups.width
                        spacing: Theme.field.gap
                        Field { id: wardenRow; label: "Warden"; inline: true; hint: "Checks whether AI agents stay within their memory and process limits"; width: parent.width; Badge { text: "Within limits"; tone: "success" } }
                    }
                    Field { label: "Agents running"; inline: true; width: groups.width; Label { role: "value"; text: "3"; width: parent.width; elide: Text.ElideRight } }
                    Field { label: "Last check"; inline: true; width: groups.width; Label { role: "value"; text: "9/30/26 3:57 PM"; width: parent.width; elide: Text.ElideRight } }
                    Field {
                        label: "Agent dashboard"
                        inline: true
                        hint: "vsys shows your agents and provides Agent Warden"
                        width: groups.width
                        Row {
                            spacing: Theme.stack.inline
                            Badge { text: "Not installed"; tone: "warning"; anchors.verticalCenter: parent.verticalCenter }
                            RowAction { text: "Install vsys"; anchors.verticalCenter: parent.verticalCenter }
                        }
                    }
                }

                }
                Section {
                    title: "Message rows"
                    description: "Fixed avatars, source links and separate response buttons"
                    rowSpacing: Theme.stack.group
                    MessageRow {
                        width: parent.width
                        sender: "You"
                        timeText: "10:41 am"
                        initials: "Y"
                        bodyText: "Keep the current settings."
                    }
                    MessageRow {
                        width: parent.width
                        sender: "Assistant"
                        timeText: "since 10:10 am"
                        avatarIcon: "bot"
                        title: "Review the proposed change"
                        bodyText: "The original request stays with its source."
                        linkText: "Open source request"
                        stateText: "Needs reply"
                        stateTone: "warning"
                        actions: [{ id: "reply", label: "Reply" }, { id: "done", label: "Done" },
                            { id: "later", label: "Later", disabledReason: "Choose a return date before postponing this request." }]
                        onActionTriggered: id => bodyText = "Selected " + id + "."
                        onSourceActivated: bodyText = "The source request was selected."
                        Component.onCompleted: Qt.callLater(() => actionAt(0).focusPreview = true)
                    }
                    MessageRow {
                        width: parent.width
                        sender: "Reviewer"
                        timeText: "since yesterday"
                        initials: "R"
                        title: "Check the completed work"
                        stateText: "Checking"
                        stateTone: "info"
                        bodyText: "The request stays open while the result is checked."
                    }
                    MessageRow {
                        width: parent.width
                        sender: "Reviewer"
                        timeText: "since yesterday"
                        initials: "R"
                        above: "Snoozed"
                        title: "Read the update plan"
                        stateText: "Snoozed"
                        bodyText: "Returns tomorrow at 9:00 am."
                    }
                    MessageRow {
                        width: parent.width
                        sender: "Jarvis"
                        timeText: "just now"
                        avatarIcon: "vgs-letter-j"
                        bodyText: "Three things changed this week. The bar shows a Jarvis icon that tells you when Jarvis listens, works or has a problem, and you can hide the orb from its menu. The console has a History tab for past conversations, tasks and problems."
                        bodyLines: 2
                        cutHint: "Click to read the full answer"
                        marked: true
                    }
                    MessageRow {
                        width: parent.width
                        sender: "Jarvis"
                        avatarIcon: "vgs-letter-j"
                        stateText: "Speaking"
                        bodyComponent: Component {
                            Label { width: parent ? parent.width : 0; role: "body"; text: "The words as Jarvis speaks them"; wrapMode: Text.Wrap }
                        }
                    }
                    ResultsFilter {
                        property string focusExample: "Results filter"
                        property bool focusPreview: true
                        accessibleLabel: "Filter example results"
                        model: ["All types", "Conversations", "Tasks", "Problems"]
                        currentIndex: 0
                    }
                    Tabs {
                        width: parent.width
                        model: ["Now", "Needs you", "History"]
                        unreadCounts: ({ "Needs you": "3" })
                        currentIndex: 1
                    }
                }
                Section {
                    title: "Feedback"
                    rowSpacing: Theme.stack.group
                    description: "Progress, badges, keys, copyable text and empty results"
                Column {
                    width: parent.width
                    spacing: Theme.stack.group
                    // Each state with a title, text and a link; with a row
                    // of links under the text; with wrapped text and no
                    // title beside a button; and as the one-line banner
                    // with a button and no icon.
                    Repeater {
                        model: [
                            { tone: "danger", mark: "circle-alert", line: "VPN dropped: traffic blocked", action: "Turn VPN off" },
                            { tone: "warning", mark: "triangle-alert", line: "Jarvis cannot forward requests", action: "Open Settings" },
                            { tone: "info", mark: "info", line: "A new version of VGS is ready", action: "Update" }
                        ]
                        Column {
                            id: example
                            required property var modelData
                            width: parent ? parent.width : 0
                            spacing: Theme.stack.inline
                            Callout {
                                tone: example.modelData.tone
                                iconName: example.modelData.mark
                                title: "Callout: " + example.modelData.tone
                                text: "Read the [setup guide](page:vgs.gallery) before you start. The text wraps to fit the available width."
                                linkText: "Read the guide"
                                onActivated: linkText = "The guide action was selected"
                                onPageActivated: (page, tab) => text = "The page link was selected."
                            }
                            Callout {
                                tone: example.modelData.tone
                                iconName: example.modelData.mark
                                title: "Callout with links"
                                text: "Each action is a link in one row under the text."
                                links: ["Show details", "Stop"]
                                onActionActivated: index => text = "The link " + links[index] + " was selected."
                            }
                            Callout {
                                tone: example.modelData.tone
                                iconName: example.modelData.mark
                                text: "Text without a title wraps under its first line, which the icon stays level with, and centres on the button beside it."
                                buttonText: "Try again"
                                onButtonActivated: buttonText = "Selected"
                            }
                            Callout {
                                tone: example.modelData.tone
                                text: example.modelData.line
                                buttonText: example.modelData.action
                                onButtonActivated: text = "The button was selected"
                            }
                        }
                    }
                    Callout { title: "Title only" }
                    Callout { text: "Text only, in the default info state" }
                }
                Flow {
                    width: parent.width
                    spacing: Theme.stack.inline
                    Spinner {}
                    Repeater {
                        model: ["accent", "neutral", "info", "success", "warning", "danger"]
                        Column {
                            required property string modelData
                            spacing: Theme.row.lineGap
                            Label { role: "label"; text: modelData }
                            ProgressBar { value: 0.6; tone: modelData }
                        }
                    }
                    ProgressBar { indeterminate: true }
                    Column {
                        spacing: Theme.row.lineGap
                        Label { role: "label"; text: "Gradient" }
                        ProgressBar {
                            value: 0.8
                            trackColor: Theme.inputMeter.track
                            fillGradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0; color: Theme.inputMeter.low }
                                GradientStop { position: 0.5; color: Theme.inputMeter.good }
                                GradientStop { position: 1; color: Theme.inputMeter.high }
                            }
                        }
                    }
                }
                Flow {
                    width: parent.width
                    spacing: Theme.stack.inline
                    LevelOsd { iconName: "volume-2"; level: 0.45 }
                    LevelOsd { iconName: "volume-x"; level: 0; text: "Muted" }
                    LevelOsd { iconName: "sun"; level: 0.8; text: "Studio Display" }
                }
                Column {
                    width: Math.min(parent.width, Theme.size.panel.md)
                    spacing: Theme.stack.inline
                    LevelSlider { width: parent.width; iconName: "volume-2"; buttonLabel: "Mute output"; value: 0.6; stepSize: 0.05 }
                    LevelSlider { width: parent.width; iconName: "volume-x"; buttonLabel: "Unmute output"; value: 0.6; stepSize: 0.05; text: "Muted" }
                }
                Flow {
                    width: parent.width
                    spacing: Theme.stack.inline
                    Repeater {
                        model: [1, 2, 3, 4, 7]
                        AvatarGroup {
                            required property int modelData
                            readonly property var everyone: [
                                { image: "", initials: "AL", tint: Theme.color.accent },
                                { image: "", initials: "GH", tint: Theme.color.info },
                                { image: "", initials: "AT", tint: Theme.color.success },
                                { image: "", initials: "ED", tint: Theme.color.warning }
                            ]
                            people: everyone.slice(0, Math.min(modelData, everyone.length))
                            more: Math.max(0, modelData - everyone.length)
                        }
                    }
                }
                Column {
                    width: parent.width
                    spacing: Theme.stack.row
                    Field { label: "Badge sm"; inline: true; width: parent.width; Flow { width: parent.width; spacing: Theme.stack.inline; Repeater { model: ["neutral", "accent", "success", "warning", "danger", "info"]; Badge { required property string modelData; tone: modelData; text: modelData; size: "sm" } } } }
                    Field { label: "Badge sm icon"; inline: true; width: parent.width; Flow { width: parent.width; spacing: Theme.stack.inline; Repeater { model: ["neutral", "accent", "success", "warning", "danger", "info"]; Badge { required property string modelData; tone: modelData; text: modelData; size: "sm"; iconName: "circle" } } } }
                    Field { label: "Badge md"; inline: true; width: parent.width; Flow { width: parent.width; spacing: Theme.stack.inline; Repeater { model: ["neutral", "accent", "success", "warning", "danger", "info"]; Badge { required property string modelData; tone: modelData; text: modelData; size: "md" } } } }
                    Field { label: "Badge md icon"; inline: true; width: parent.width; Flow { width: parent.width; spacing: Theme.stack.inline; Repeater { model: ["neutral", "accent", "success", "warning", "danger", "info"]; Badge { required property string modelData; tone: modelData; text: modelData; size: "md"; iconName: "circle" } } } }
                    Field { label: "Badge verbatim"; inline: true; width: parent.width; Flow { width: parent.width; spacing: Theme.stack.inline; Repeater { model: [["voxtype-bin", "sm"], ["wl-clipboard", "md"]]; Badge { required property var modelData; text: modelData[0]; size: modelData[1]; verbatim: true } } } }
                    Field {
                        label: "Unread counts"
                        inline: true
                        width: parent.width
                        Row {
                            spacing: Theme.stack.inline
                            Badge { variant: "unread"; text: "3" }
                            Badge { variant: "unread"; text: "99" }
                            Badge { variant: "unread"; text: "120" }
                            Badge { variant: "unread"; text: "3"; level: "warning" }
                            Badge { variant: "unread"; text: "3"; level: "danger" }
                        }
                    }
                    // The bar corner's size, on the bar's background its ring
                    // parts from: 1, 9+ and each level.
                    Field {
                        label: "Unread corner"
                        inline: true
                        width: parent.width
                        Rectangle {
                            width: cornerCounts.width + 2 * Theme.space.xs
                            height: Theme.bar.height
                            color: Theme.bar.background
                            Row {
                                id: cornerCounts
                                anchors.centerIn: parent
                                spacing: Theme.stack.inline
                                Badge { variant: "unread"; size: "corner"; text: "1"; anchors.verticalCenter: parent.verticalCenter }
                                Badge { variant: "unread"; size: "corner"; text: "12"; anchors.verticalCenter: parent.verticalCenter }
                                Badge { variant: "unread"; size: "corner"; text: "2"; level: "warning"; anchors.verticalCenter: parent.verticalCenter }
                                Badge { variant: "unread"; size: "corner"; text: "1"; level: "danger"; anchors.verticalCenter: parent.verticalCenter }
                            }
                        }
                    }
                    Field {
                        label: "Keycap"
                        inline: true
                        width: parent.width
                        Flow {
                            width: parent.width
                            spacing: Theme.stack.inline
                            Kbd { text: "S" }
                            Kbd { text: "Enter" }
                            Row {
                                spacing: Theme.space.xs
                                Kbd { text: "Ctrl" }
                                Kbd { text: "K" }
                            }
                            KeyCaps { shortcut: "SUPER+SHIFT+T" }
                        }
                    }
                }
                CodeLine { width: parent.width; text: "~/.config/vgshell/shell.json"; copyLabel: "Copy the path" }
                // CopyText draws nothing: its RowAction reads Copied while it confirms.
                Field {
                    label: "Copy text"
                    inline: true
                    width: parent.width
                    RowAction {
                        text: galleryCopy.confirming ? "Copied" : "Copy"
                        onClicked: galleryCopy.copy("100.64.0.1")
                        CopyText { id: galleryCopy }
                    }
                }
                LinkText { width: parent.width; role: "body"; text: "Open hyprland.lua to inspect the line VGS adds."; link: "hyprland.lua" }
                EmptyState { width: parent.width; iconName: "search-x"; text: "No plugin matches \"zzqx\""; actionText: "Clear search" }
                SaveBar { width: parent.width; dirty: true }
                Flow {
                    width: parent.width
                    spacing: Theme.stack.inline
                    Button { text: "Send a notification"; variant: "tertiary"; iconName: "bell"; onClicked: root.notify() }
                    Button {
                        text: "Open a popover"
                        variant: "tertiary"
                        iconName: "panel-top"
                        onClicked: popover.toggle()
                        Popover {
                            id: popover
                            width: Theme.size.panel.sm
                            title: "A popover"
                            subtitle: Label { role: "hint"; width: parent.width; text: "This opens below the button." }
                        }
                        Tooltip { text: "Opens a popover under this button" }
                    }
                    Button { id: menuButton; text: "Open a menu"; variant: "tertiary"; iconName: "menu"; onClicked: menu.toggle(KeyNavLogic.opener(menuButton))
                        Menu { id: menu
                            MenuItem { text: "Rescan plugins"; iconName: "refresh-cw"; shortcut: "R" }
                            MenuItem { text: "Open settings"; iconName: "settings" }
                            MenuItem { text: "Quit"; iconName: "power"; enabled: false }
                        }
                    }
                    ToggleButton {
                        id: passiveButton
                        text: "Show a passive popup"
                        iconName: "message-square"
                        PassivePopup {
                            shown: passiveButton.checked
                            width: Theme.size.panel.sm
                            Card {
                                floating: true
                                width: parent.width
                                Label { width: parent.width; role: "body"; wrapMode: Text.Wrap; text: "This shows below the button and takes no keyboard." }
                            }
                        }
                    }
                }
                Label { role: "hint"; color: Theme.color.textMuted; text: "A plugin tells you something through a system notification, which Notifications draws."; width: parent.width; wrapMode: Text.Wrap }
                Label { role: "hint"; color: Theme.color.textMuted; text: "VGS has no toast of its own."; width: parent.width; wrapMode: Text.Wrap }

                }
                Section {
                    title: "Voice levels"
                    description: "Animated rings with sample audio levels"
                    headerInset: 0
                    Flow {
                        width: parent.width
                        spacing: Theme.space.sm
                        Repeater {
                            model: ["accent", "info", "success", "warning", "danger", "muted"]
                            Column {
                                required property string modelData
                                spacing: Theme.space.xs
                                VoiceOrb { tone: parent.modelData; active: true; level: 0.6; secondaryLevel: 0.3 }
                                Label { role: "label"; text: parent.modelData }
                            }
                        }
                    }
                    Flow {
                        width: parent.width
                        spacing: Theme.space.sm
                        Column {
                            spacing: Theme.space.xs
                            VoiceOrb { active: false }
                            Label { role: "label"; text: "Inactive" }
                        }
                        Column {
                            spacing: Theme.space.xs
                            VoiceOrb { active: true; level: 1; secondaryLevel: 1 }
                            Label { role: "label"; text: "Full levels" }
                        }
                        Column {
                            spacing: Theme.space.xs
                            VoiceOrb { active: true; level: orbLevel.value; secondaryLevel: 1 - orbLevel.value }
                            Label { role: "label"; text: "Adjust levels" }
                        }
                    }
                    Slider { id: orbLevel; from: 0; to: 1; value: 0.4; width: parent.width }
                    Label { role: "hint"; text: "These samples use no microphone input."; width: parent.width; wrapMode: Text.Wrap }
                }
                Section {
                    title: "Backdrop fields"
                    description: "One dark field behind a passive layer's content, over a bright ground"
                    headerInset: 0
                    Flow {
                        width: parent.width
                        spacing: Theme.space.sm
                        Repeater {
                            // An eased field over a disc and a line of text, with
                            // the disc's halo, and a Gaussian disc alone.
                            model: [{ name: "Eased, two boxes and a halo", falloff: "eased", halo: true },
                                    { name: "Gaussian, one disc", falloff: "gaussian", halo: false }]
                            Column {
                                id: backdropSample
                                required property var modelData
                                readonly property real unit: Theme.space.xxxl
                                spacing: Theme.space.xs
                                Rectangle {
                                    width: 6 * backdropSample.unit
                                    height: 5 * backdropSample.unit
                                    color: Theme.color.accent
                                    RadialBackdrop {
                                        anchors.fill: parent
                                        readonly property real u: backdropSample.unit
                                        boxes: [{ x: 2 * u, y: u, w: 2 * u, h: 2 * u, corner: u, peak: 0.6, fade: 1.5 * u, inset: 0.5 * u, ink: Theme.screensaver.background }]
                                            .concat(backdropSample.modelData.halo ? [{ x: 1.5 * u, y: 3.5 * u, w: 3 * u, h: 0.5 * u, corner: 0.25 * u, peak: 0.8, fade: 1.5 * u, inset: 0.25 * u, ink: Theme.screensaver.background }] : [])
                                        join: 0.1
                                        blend: 0.15
                                        falloff: backdropSample.modelData.falloff
                                        halo: backdropSample.modelData.halo ? { strength: 0.4, width: 0.5 * u, ring: u, stops: [Theme.color.info, Theme.color.accent, Theme.color.warning, Theme.color.success] } : null
                                    }
                                }
                                Label { role: "label"; text: backdropSample.modelData.name }
                            }
                        }
                    }
                }
                Section {
                    title: "Dialogs"
                    rowSpacing: Theme.stack.group
                    description: "Confirmations, progress and disabled actions"
                Button {
                    id: modalExample
                    property string focusExample: "Modal dialog launcher"
                    text: "Open modal dialog"
                    variant: "secondary"
                    onClicked: modalSample.shown = true
                }
                ModalDialog {
                    id: modalSample
                    title: "Keep these settings?"
                    message: "This confirmation stays at the center of the screen."
                    actions: [{ label: "Keep", role: "accept" }, { label: "Revert", role: "cancel" }]
                    onAccepted: shown = false
                    onRejected: shown = false
                }
                Dialog {
                    modal: false
                    title: "Warden"
                    message: "Shows whether Agent Warden is watching your AI agents and whether any of them needs your attention."
                    actions: [{ label: "Close", role: "cancel", focused: true }]
                }
                Dialog {
                    modal: false
                    title: "Download wallpapers for Nord?"
                    message: "12 wallpapers, 42 MB, from vanillagreencom/vgs-themes."
                    actions: [{ label: "Not now", role: "cancel" }, { label: "Download", role: "accept" }]
                }
                Dialog {
                    modal: false
                    title: "Remove acme.weather?"
                    message: "Your settings are kept."
                    actions: [{ label: "Cancel", role: "cancel" }, { label: "Remove", role: "accept", variant: "danger" }]
                }
                Dialog {
                    modal: false
                    title: "Downloading wallpapers for Nord"
                    message: "The theme applies again when the download ends."
                    busy: true
                    actions: [{ label: "Not now", role: "cancel" }, { label: "Download", role: "accept" }]
                }
                Dialog {
                    modal: false
                    title: "Install what acme.weather needs?"
                    message: "VGS cannot install these tools on this system."
                    actions: [{ label: "Not now", role: "cancel" }, { label: "Install", role: "accept", enabled: false }]
                    Label { role: "itemCode"; text: "gum" }
                    Label { role: "itemCode"; text: "xdg-terminal-exec" }
                }

                }
                Section {
                    title: "Cards"
                    rowSpacing: Theme.stack.group
                    description: "Grouped, selected and unselected cards"
                Item {
                    width: parent.width
                    height: Theme.size.panel.sm / 2

                    Scrim {}
                    Row {
                        anchors.centerIn: parent
                        spacing: Theme.stack.inline
                        Repeater {
                            model: ["info", "success", "warning"]
                            AngledCard {
                                id: card
                                required property string modelData
                                required property int index
                                width: Theme.size.panel.sm / 2
                                height: Theme.size.panel.sm / 2 - 2 * Theme.space.md
                                selected: index === 1
                                Rectangle { anchors.fill: parent; color: Theme.color[card.modelData] }
                            }
                        }
                    }
                }
                Card {
                    width: parent.width
                    Label { role: "label"; text: "Work account" }
                    Label { role: "hint"; text: "ana@example.com · Pro" }
                    ProgressBar { width: parent.width; value: 0.42 }
                    Label { role: "hint"; text: "Resets in 2 h 10 min" }
                }
                Card {
                    width: parent.width
                    floating: true
                    Label { role: "label"; text: "Floating card" }
                    Label { role: "hint"; text: "Stands alone over the desktop, on the popover's ground" }
                }

                }
                Section {
                    title: "QR matrix"
                    description: "A public sample matrix drawn with integer modules."
                    QrMatrix { matrixData: "11111\n10001\n10101\n10001\n11111\n" }
                }
                Section {
                    title: "Carousel"
                    rowSpacing: Theme.stack.group
                    description: "Click a card or scroll to change the selection."
                CardCarousel {
                    width: parent.width
                    height: Theme.carousel.expandedHeight * Theme.carousel.minScale
                    model: ["info", "success", "warning", "danger", "info", "success", "warning", "danger", "info"]
                    currentIndex: 4
                    tabSteps: false
                    delegate: Rectangle {
                        required property var modelData
                        required property size decodeSize
                        anchors.fill: parent
                        color: Theme.color[modelData]
                    }
                }

                }
                Section {
                    title: "Focus"
                    rowSpacing: Theme.stack.group
                    description: "Focusable controls drawn with their keyboard focus state"
                Column {
                    width: parent.width
                    spacing: Theme.stack.row
                    Field {
                        label: "Buttons"
                        inline: true
                        width: parent.width
                        Flow {
                            width: parent.width
                            spacing: Theme.stack.inline
                            Repeater {
                                model: ["primary", "secondary", "tertiary", "ghost", "danger"]
                                Button {
                                    required property string modelData
                                    property string focusExample: "Button " + modelData
                                    focusPreview: true
                                    variant: modelData
                                    text: modelData
                                }
                            }
                            ToggleButton {
                                property string focusExample: "ToggleButton"
                                focusPreview: true
                                text: "Pinned"
                                checked: true
                            }
                            IconButton {
                                property string focusExample: "IconButton"
                                focusPreview: true
                                iconName: "settings"
                                label: "Settings"
                            }
                            RowAction {
                                property string focusExample: "RowAction"
                                focusPreview: true
                                text: "Set up voice"
                            }
                        }
                    }
                    Field {
                        label: "Bar item"
                        inline: true
                        width: parent.width
                        Rectangle {
                            width: Math.min(parent.width, Theme.size.panel.sm)
                            height: Theme.bar.height
                            color: Theme.bar.background
                            BarItem {
                                property string focusExample: "BarItem"
                                focusPreview: true
                                anchors.verticalCenter: parent.verticalCenter
                                iconName: "settings"
                                label: "Settings"
                            }
                        }
                    }
                    Field {
                        label: "Choices"
                        inline: true
                        width: parent.width
                        Flow {
                            width: parent.width
                            spacing: Theme.stack.inline
                            Switch {
                                property string focusExample: "Switch"
                                focusPreview: true
                                text: "Switch"
                                checked: true
                            }
                            Checkbox {
                                property string focusExample: "Checkbox"
                                focusPreview: true
                                text: "Checkbox"
                                checked: true
                            }
                            Radio {
                                property string focusExample: "Radio"
                                focusPreview: true
                                text: "Radio"
                                checked: true
                            }
                            SegmentedControl {
                                property string focusExample: "SegmentedControl"
                                focusPreview: true
                                model: ["One", "Two", "Three"]
                                currentIndex: 1
                            }
                            TileGroup {
                                property string focusExample: "TileGroup"
                                focusPreview: true
                                model: [{ text: "Area", icon: "scan" }, { text: "Window", icon: "app-window" }]
                                currentIndex: 0
                            }
                        }
                    }
                    Field {
                        label: "Inputs"
                        inline: true
                        width: parent.width
                        Flow {
                            width: parent.width
                            spacing: Theme.stack.inline
                            TextField { variant: "search"; width: parent.width; text: "Focused search"; leadingIcon: "search"; property bool focusPreview: true }
                            TextField { variant: "search"; searchUnderline: false; width: parent.width; text: "Focused Plugins search"; leadingIcon: "search"; property bool focusPreview: true }
                            Select {
                                property string focusExample: "Select"
                                property bool focusPreview: true
                                model: ["Default", "Ocean", "Forest"]
                            }
                            SettingField {
                                id: focusedSetting
                                property string focusExample: "SettingField"
                                property bool focusPreview: true
                                width: parent.width
                                key: "focused"
                                spec: ({ type: "boolean", label: "Schema focus" })
                                value: true
                                onApply: value => focusedSetting.value = value
                            }
                            TextField {
                                property string focusExample: "TextField"
                                property bool focusPreview: true
                                text: "Focused text"
                            }
                            ShortcutField {
                                property string focusExample: "ShortcutField"
                                focusPreview: true
                                keys: ["SUPER+SPACE"]
                            }
                            Slider {
                                property string focusExample: "Slider"
                                focusPreview: true
                                from: 0
                                to: 100
                                value: 55
                                width: Theme.size.panel.sm / 2
                            }
                            TitleButton {
                                property string focusExample: "TitleButton"
                                property bool focusPreview: true
                                text: "Focused title"
                                menu: Menu { MenuItem { text: "Focused title" } }
                            }
                        }
                    }
                    Field {
                        label: "Tabs and rows"
                        inline: true
                        width: parent.width
                        Column {
                            width: parent.width
                            spacing: Theme.stack.row
                            Tabs {
                                property string focusExample: "Tabs"
                                property bool focusPreview: true
                                width: parent.width
                                model: ["Installed", "Available", "Updates"]
                                currentIndex: 1
                            }
                            // The rows and their cursor, beside the rows' column.
                            Item {
                                width: parent.width
                                height: focusRows.height
                                ListCursor { id: focusRowsCursor }
                                Column {
                                    id: focusRows
                                    width: parent.width
                                    spacing: Theme.stack.row
                                    Disclosure {
                                        property string focusExample: "Disclosure"
                                        width: parent.width
                                        cursor: focusRowsCursor
                                        text: "Focused disclosure"
                                        secondary: "Expanded"
                                        iconName: "package"
                                        expanded: true
                                        Label { role: "hint"; text: "The disclosure row is the focusable control." }
                                    }
                                    DeviceRow {
                                        property string focusExample: "DeviceRow"
                                        width: parent.width
                                        cursor: focusRowsCursor
                                        text: "Focused device"
                                        secondary: "Connected"
                                        iconName: "bluetooth"
                                        battery: 0.5
                                        menuEntries: [ MenuItem { text: "Forget" } ]
                                    }
                                }
                            }
                        }
                    }
                    Field {
                        label: "Carousel"
                        inline: true
                        width: parent.width
                        CardCarousel {
                            property string focusExample: "CardCarousel"
                            width: parent.width
                            height: Theme.carousel.expandedHeight * Theme.carousel.minScale
                            model: ["accent", "info", "success", "warning", "danger"]
                            currentIndex: 2
                            tabSteps: false
                            delegate: Rectangle {
                                required property var modelData
                                required property size decodeSize
                                anchors.fill: parent
                                color: Theme.color[modelData]
                            }
                        }
                    }
                    Field {
                        label: "Key navigation"
                        inline: true
                        width: parent.width
                        Column {
                            width: parent.width
                            spacing: Theme.stack.row
                            KeyCaps {
                                property string focusExample: "KeyCaps"
                                shortcut: "SUPER+SHIFT+T"
                            }
                            KeyHints {
                                hints: [
                                    { key: "Left/Right", text: "Move" },
                                    { key: "Enter", text: "Open" }
                                ]
                            }
                            // focus-indicator: ListCursor shows the current row
                            Item {
                                id: focusList
                                property string focusExample: "KeyNav list"
                                property int current: 0
                                width: parent.width
                                height: focusListColumn.height
                                activeFocusOnTab: true
                                Keys.onPressed: event => { event.accepted = focusListNav.handle(event); }

                                ListCursor { id: focusListCursor }
                                KeyNav {
                                    id: focusListNav
                                    count: focusListRows.count
                                    currentIndex: focusList.current
                                    cursor: focusListCursor
                                    itemAt: index => focusListRows.itemAt(index)
                                    onMoved: index => focusList.current = index
                                }
                                Column {
                                    id: focusListColumn
                                    width: parent.width
                                    Repeater {
                                        id: focusListRows
                                        model: ["First", "Second", "Third"]
                                        NavigationRow {
                                            required property string modelData
                                            required property int index
                                            width: focusListColumn.width
                                            text: modelData
                                            iconName: "list"
                                            cursor: focusListCursor
                                            highlighted: index === focusList.current
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Field {
                        label: "Dialog"
                        inline: false
                        width: parent.width
                        Dialog {
                            property string focusExample: "Dialog accept action"
                            width: parent.width
                            modal: false
                            title: "Save this theme?"
                    message: "Save has keyboard focus."
                            actions: [{ label: "Cancel", role: "cancel" }, { label: "Save", role: "accept" }]
                        }
                    }
                }

                }
                Section {
                    title: "Titles and scrolling"
                    rowSpacing: Theme.stack.group
                    description: "Title menus and scroll bars"
                Flow {
                    width: parent.width
                    spacing: Theme.stack.inline
                    TitleButton {
                        id: title
                        property string chosen: "Notifications"
                        text: chosen
                        menu: titleMenu
                        Menu {
                            id: titleMenu
                            Repeater {
                                model: ["Bar", "VGS Components", "Launcher", "Notifications", "Settings", "Themes", "Clock", "Weather", "Workspaces", "Battery", "Network", "Volume"]
                                MenuItem {
                                    required property string modelData
                                    text: modelData
                                    iconName: "package"
                                    checked: modelData === title.chosen
                                    onTriggered: title.chosen = modelData
                                }
                            }
                        }
                    }
                    TitleButton { text: "Disabled"; enabled: false }
                }
                ScrollArea {
                    width: parent.width
                    height: Theme.size.panel.sm / 2
                    Column {
                        id: scrolledRows
                        width: parent.width
                        Repeater {
                            model: 12
                            // The column, not `parent`, which is null while
                            // the repeater tears the row down.
                            ListItem { required property int index; text: "Row " + (index + 1); iconName: "list"; clickable: false; width: scrolledRows.width }
                        }
                    }
                }
                // The slim bar a plugin that owns its look draws beside its
                // own list, here with the shell's scroll bar values.
                Item {
                    width: parent.width
                    height: Theme.size.panel.sm / 2
                    Flickable {
                        id: slimList
                        width: parent.width - Theme.scrollArea.gutter
                        height: parent.height
                        contentHeight: slimRows.height
                        clip: true
                        acceptedButtons: Qt.NoButton
                        TouchpadScroll { view: slimList }
                        Column {
                            id: slimRows
                            width: slimList.width
                            Repeater {
                                model: 12
                                ListItem { required property int index; text: "Slim " + (index + 1); iconName: "list"; clickable: false; width: slimRows.width }
                            }
                        }
                    }
                    SlimScrollBar {
                        flickable: slimList
                        x: parent.width - width
                        width: Theme.scrollArea.gutter
                        thin: Theme.scrollArea.barWidth / 2
                        wide: Theme.scrollArea.barWidth
                        minLength: Theme.scrollArea.minThumb
                        color: Theme.scrollArea.bar
                        radius: Theme.scrollArea.barRadius
                        idleOpacity: 1
                        movingOpacity: 1
                        activeOpacity: 1
                        widthStep: Theme.motion.list.fade
                        opacityStep: Theme.motion.list.fade
                    }
                }

                }
                Section {
                    title: "Lists"
                    rowSpacing: Theme.stack.group
                    description: "Tabs, tab pages, rows, expanded details and dividers"
                Tabs { model: ["Installed", "Available", "Updates"] }
                TabPages {
                    width: parent.width
                    model: ["Settings", "Details"]
                    Column {
                        spacing: Theme.stack.row
                        Field { label: "Enabled"; inline: true; width: parent.width; Switch { size: "sm"; checked: true } }
                        Field { label: "Show in bar"; inline: true; width: parent.width; Switch { size: "sm" } }
                    }
                    Label { role: "hint"; text: "TabPages shows the open page alone. Ctrl+Tab steps the page from the strip and from a control in the page."; wrapMode: Text.Wrap }
                }
                // The rows and their cursor, beside the rows' column.
                Item {
                    width: parent.width
                    height: listRows.height
                    ListCursor { id: listRowsCursor }
                    Column {
                        id: listRows
                        width: parent.width
                        ListItem { text: "Plugin updates"; secondary: "1 update available"; iconName: "package"; clickable: false; width: parent.width; trailing: [ Badge { text: "new"; tone: "accent" } ] }
                        Divider { width: parent.width }
                        ListItem { text: "Workspaces"; secondary: "up to date"; iconName: "layout-grid"; clickable: false; highlighted: true; width: parent.width }
                        ListItem { text: "Clock"; iconName: "clock"; clickable: false; width: parent.width; trailing: [ Switch { size: "sm"; checked: true } ] }
                        // A row read for its secondary line: it breaks onto a
                        // second line and is cut past it.
                        ListItem { text: "Backup"; secondary: "Every 10 minutes, at least 30 seconds after the last run ends, until Friday 25 December 2026, 12 times"; secondaryWraps: true; iconName: "calendar-check"; clickable: false; width: parent.width; trailing: [ Switch { size: "sm"; checked: true } ] }
                        // Content rows: one item with its action at its end and no
                        // hover, the same height whatever the secondary line holds.
                        ContentRow { text: "Clock"; secondary: "Show the time and date"; iconName: "clock"; width: parent.width; trailing: [ Button { size: "sm"; variant: "secondary"; text: "Add"; iconName: "plus"; anchors.verticalCenter: parent.verticalCenter } ] }
                        ContentRow { text: "Weather"; secondary: "Show the weather where you are, with the temperature, the wind and the chance of rain for the next hours"; iconName: "cloud"; width: parent.width; trailing: [ Button { size: "sm"; variant: "secondary"; text: "Add"; iconName: "plus"; anchors.verticalCenter: parent.verticalCenter } ] }
                        ContentRow {
                            text: "Battery"
                            secondary: "Show battery level"
                            iconName: "battery"
                            width: parent.width
                            trailing: [
                                Button {
                                    property string focusExample: "ContentRow action"
                                    focusPreview: true
                                    size: "sm"
                                    variant: "secondary"
                                    text: "Remove"
                                    iconName: "minus"
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            ]
                        }
                        ContentRow { text: "Printers"; secondary: "Turn this plugin on to add its widget"; iconName: "printer"; width: parent.width; trailing: [ Button { size: "sm"; variant: "secondary"; text: "Settings"; iconName: "settings"; anchors.verticalCenter: parent.verticalCenter } ] }
                        // Stacked content rows: a state, a line, small buttons
                        // and a row menu under the name. A row that opens its
                        // folder takes the list's cursor; the others are passive.
                        // focus-indicator: ListItem's FocusRing and the list's ListCursor plate show the focused row
                        ContentRow {
                            property string focusExample: "Stacked content row"
                            text: "Documents"
                            iconName: "folder-sync"
                            status: "Sync stopped"
                            statusTone: "warning"
                            detail: "Drive/Documents ⇄ ~/Drive/Documents"
                            actions: [{ key: "setup", text: "Set up two-way sync" }]
                            menuActions: [{ key: "remove", text: "Remove", iconName: "trash" }]
                            clickable: true
                            cursor: listRowsCursor
                            focusPolicy: Qt.StrongFocus
                            highlighted: visualFocus
                            width: parent.width
                        }
                        ContentRow {
                            text: "Agent uploads"
                            iconName: "folder-sync"
                            status: "Up to date"
                            statusTone: "success"
                            detail: "Drive/VGS/Uploads ⇄ ~/inbox/agent-uploads"
                            menuActions: [{ key: "remove", text: "Remove", iconName: "trash" }]
                            clickable: true
                            cursor: listRowsCursor
                            width: parent.width
                        }
                        ContentRow {
                            text: "Taxes"
                            iconName: "folder-sync"
                            status: "2 files need you"
                            statusTone: "danger"
                            detail: "Drive/Finance/Taxes ⇄ ~/Documents/Taxes"
                            actions: [{ key: "setup", text: "Set up two-way sync", disabledReason: "Fix the 2 files first" }]
                            menuActions: [{ key: "remove", text: "Remove", iconName: "trash" }]
                            width: parent.width
                        }
                        ContentRow {
                            text: "Music"
                            iconName: "folder-sync"
                            status: "Syncing"
                            statusTone: "info"
                            detail: "Drive/Music ⇄ ~/Music"
                            menuActions: [{ key: "remove", text: "Remove", iconName: "trash" }]
                            width: parent.width
                        }
                        ContentRow { text: "Photos"; iconName: "folder-sync"; detail: "Drive/Photos ⇄ ~/Pictures"; menuActions: [{ key: "remove", text: "Remove", iconName: "trash" }]; width: parent.width }
                        ContentRow { text: "crashy"; iconName: "bell-off"; actions: [{ key: "unmute", text: "Unmute" }]; width: parent.width }
                        // Navigation rows: the whole row opens a page and ends in a
                        // chevron; the list's cursor draws the hover.
                        NavigationRow { text: "Bluetooth"; secondary: "1.4.0  Included"; iconName: "bluetooth"; cursor: listRowsCursor; width: parent.width }
                        NavigationRow { text: "Network"; secondary: "Selected row"; iconName: "wifi"; cursor: listRowsCursor; highlighted: true; width: parent.width }
                        NavigationRow { text: "Sound"; secondary: "The page shown now"; iconName: "volume-2"; cursor: listRowsCursor; active: true; width: parent.width }
                        NavigationRow {
                            text: "Updates"
                            secondary: "With accessories"
                            iconName: "package"
                            cursor: listRowsCursor
                            width: parent.width
                            accessories: [
                                Badge { tone: "danger"; iconName: "circle-alert"; text: "2"; anchors.verticalCenter: parent.verticalCenter },
                                Badge { tone: "warning"; text: "Setup needed"; anchors.verticalCenter: parent.verticalCenter }
                            ]
                        }
                        Disclosure {
                            width: parent.width
                            cursor: listRowsCursor
                            text: "System"
                            secondary: "2 updates"
                            iconName: "package"
                            expanded: true
                            trailing: [ Badge { text: "2"; tone: "accent"; anchors.verticalCenter: parent.verticalCenter } ]
                            Label { role: "code"; text: "linux 6.1 -> 6.2" }
                            Label { role: "code"; text: "mesa 25.1 -> 25.2" }
                        }
                        // The card follows its content's height through
                        // SurfaceHeight, as a summoned panel's card does.
                        // The card's fill would cover a plate under it, so the
                        // row's cursor stands on the card.
                        SurfaceHeight {
                            width: parent.width
                            target: grower.implicitHeight
                            Surface { anchors.fill: parent }
                            Item {
                                width: parent.width
                                height: grower.height
                                ListCursor { id: growerCursor }
                                Disclosure {
                                    id: grower
                                    width: parent.width
                                    cursor: growerCursor
                                    text: "Card height"
                                    secondary: "Open it to watch the card grow"
                                    iconName: "info"
                                    Label { role: "hint"; text: "The card animates to its new height while its surface keeps one size."; width: parent.width; wrapMode: Text.Wrap }
                                }
                            }
                        }
                        Disclosure {
                            width: parent.width
                            cursor: listRowsCursor
                            text: "No details"
                            secondary: "Trailing badge meets the row edge"
                            iconName: "info"
                            expandable: false
                            trailing: [ Badge { text: "ready"; tone: "success"; anchors.verticalCenter: parent.verticalCenter } ]
                        }
                        Divider { width: parent.width }
                        MenuItem { text: "Menu entry"; iconName: "check"; shortcut: "Enter" }
                        MenuItem { text: "Selected menu entry"; iconName: "palette"; checked: true }
                    }
                }
                DeviceList {
                    property string focusExample: "Device list"
                    width: parent.width
                    rows: [
                        { key: "Headphones", text: "Headphones", secondary: "Connected", iconName: "headphones", battery: 0.72 },
                        { key: "Mouse", text: "Mouse", secondary: "Connected", iconName: "mouse", battery: 0.08 },
                        { key: "Printer", text: "Printer", secondary: "Stopped: Paper jam", secondaryTone: "danger", iconName: "printer-x" },
                        { key: "Displays", text: "Displays", secondary: "2 screens", iconName: "monitor", opens: true },
                        { key: "Speaker", text: "Speaker", secondary: "Not connected", iconName: "speaker", badge: "Nearby", badgeTone: "info" }
                    ]
                    actionOf: row => row.key === "Headphones" ? { text: "Disconnect" } : row.key === "Speaker" ? { text: "Connect" } : null
                    menuOf: row => row.key === "Headphones"
                        ? [{ key: "rename", text: "Rename" }, { key: "trust", text: "Trust" }, { key: "forget", text: "Forget" }]
                        : row.key === "Mouse" ? [{ key: "rename", text: "Rename" }, { key: "forget", text: "Forget" }] : []
                }
                DeviceList {
                    width: parent.width
                    rows: [{ key: "Earbuds", text: "Earbuds", secondary: "Connecting…", iconName: "headphones", busy: true }]
                    actionOf: row => ({ text: "Connect" })
                }
                // Locked: the row that opens keeps working, the other draws
                // faded and says why.
                DeviceList {
                    width: parent.width
                    disabledReason: "Sign in as the administrator to change these devices"
                    rows: [
                        { key: "Displays", text: "Displays", secondary: "2 screens", iconName: "monitor", opens: true },
                        { key: "Keyboard", text: "Keyboard", secondary: "Connected", iconName: "keyboard" }
                    ]
                }
                }
                Section {
                    title: "List motion"
                    description: "Up and Down move the selection. The plate follows the pointer."
                    rowSpacing: Theme.stack.group
                Button {
                    text: "Replay the entrance"
                    iconName: "refresh-cw"
                    variant: "secondary"
                    onClicked: {
                        motionRows.model = 0;
                        motionRows.model = 5;
                    }
                }
                // focus-indicator: ListCursor shows the current row
                Item {
                    id: motionList
                    property int current: 0
                    width: parent.width
                    height: motionColumn.height
                    activeFocusOnTab: true
                    Keys.onUpPressed: { motionCursor.disarm(); current = Math.max(0, current - 1); }
                    Keys.onDownPressed: { motionCursor.disarm(); current = Math.min(motionRows.count - 1, current + 1); }

                    ListCursor { id: motionCursor }
                    Column {
                        id: motionColumn
                        width: parent.width
                        Repeater {
                            id: motionRows
                            model: 5
                            ListItem {
                                required property int index
                                width: motionColumn.width
                                text: ["Workspaces", "Clock", "Battery", "Network", "Volume"][index]
                                secondary: index % 2 === 0 ? "bar widget" : ""
                                iconName: ["layout-grid", "clock", "battery", "wifi", "volume-2"][index]
                                cursor: motionCursor
                                highlighted: index === motionList.current
                                onClicked: motionList.forceActiveFocus()
                            }
                        }
                    }
                }
                }
            }
    }
}
