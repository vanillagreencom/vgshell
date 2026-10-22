import QtQuick
import QtQuick.Window as QtWindow
import QtTest
import qs.Commons
import qs.Core
import qs.Ui
import qs.Unit
import "../../shell/plugins/vgs.settings"

Item {
    id: root
    width: 960
    height: 1040

    property var applied: []
    // The private opener: the addresses the fields' description links
    // asked the page to open, in order. No browser starts.
    property var opened: []
    // The pages the fields' page references asked for, as "page/tab".
    property var pages: []

    SettingField {
        id: field
        width: 420
        pluginId: "vgs.bar"
        key: "clockFormat"
        spec: ({
            type: "string",
            label: "Clock format",
            format: "datetime",
            allowCustom: true,
            presets: [
                { value: "HH:mm" },
                { value: "ddd HH:mm" },
                { value: "yyyy-MM-dd HH:mm" }
            ]
        })
        value: "HH:mm"
        onApply: value => root.applied.push(value)
    }

    // A choice whose unset value means nothing is chosen declares a
    // placeholder, which its Select reads while no offer is chosen.
    SettingField {
        id: picked
        y: 120
        width: 420
        pluginId: "vgs.jarvis"
        key: "brain"
        spec: ({ type: "string", label: "Model", optionsFrom: "brains", placeholder: "Pick a model" })
        choices: [{ label: "Alpha", value: "a" }, { label: "Beta", value: "b" }]
        value: ""
    }

    // A field whose description or custom field's description sits under
    // it is followed by a group space, `stack.group`; the last ends at its
    // line.
    Column {
        id: settingRows
        y: 200
        width: 420
        spacing: Theme.stack.row
        SettingField { id: described; key: "interval"; spec: ({ type: "boolean", label: "Check interval", description: "How often it checks." }); value: true }
        SettingField { id: customDescribed; key: "unit"; spec: ({ type: "string", label: "Unit", description: "The unit it shows.", allowCustom: true, presets: [{ value: "kB" }] }); value: "MiB" }
        SettingField { id: following; key: "view"; spec: ({ type: "boolean", label: "View" }); value: false }
        SettingField { id: lastDescribed; key: "last"; spec: ({ type: "boolean", label: "Last", description: "Ends the column." }); value: true }
    }

    // A key field whose description carries a link at its start, so a
    // click at the line's start lands on it, and a custom field whose
    // description carries one too. The error field's error holds its hint
    // link's words, which an error line still draws as no link.
    Column {
        id: linkRows
        y: 360
        width: 420
        spacing: Theme.stack.row
        SettingField {
            id: keyLinked
            key: "voiceAccount"
            spec: ({ type: "boolean", label: "Realtime key", description: "OpenAI API keys gives you a key.", link: { text: "OpenAI API keys", url: "https://platform.openai.com/api-keys" } })
            value: true
            onOpenLink: link => root.opened.push(link.url)
        }
        SettingField {
            id: customLinked
            key: "unit"
            spec: ({ type: "string", label: "Unit", description: "Units listed at the unit guide.", link: { text: "unit guide", url: "https://example.org/units" }, allowCustom: true, presets: [{ value: "kB" }] })
            value: "MiB"
            onOpenLink: link => root.opened.push(link.url)
        }
        Field {
            id: erred
            width: 420
            label: "Erred"
            hint: "Get one at the key page."
            hintLink: "key page"
            error: "The key page refused that key."
        }
    }

    // A field whose description opens with a page reference.
    SettingField {
        id: pageLinked
        y: 960
        width: 420
        key: "model"
        spec: ({ type: "boolean", label: "Model", description: "[Models page](page:acme.models/Setup) holds the keys." })
        value: true
        onOpenPage: (page, tab) => root.pages.push(page + "/" + tab)
    }

    // A status-fed choice that takes a custom value: Custom… follows the
    // published choices, and a configured value no choice holds shows
    // under it. Without allowCustom the same value reads as the
    // unavailable row settingChoices adds, and no custom editor shows.
    SettingField {
        id: customFed
        y: 560
        width: 420
        key: "device"
        spec: ({ type: "string", label: "Device", optionsFrom: "devices", allowCustom: true })
        value: ""
        onApply: value => root.applied.push(value)
    }
    SettingField {
        id: plainFed
        y: 620
        width: 420
        key: "device"
        spec: ({ type: "string", label: "Device", optionsFrom: "devices" })
        choices: [{ label: "Alpha", value: "" }, { label: "Beta", value: "b" }, { label: "gone (unavailable)", value: "gone" }]
        value: "gone"
    }

    // An enum draws each option's label and writes its value: three
    // options in a segmented control, more in a Select.
    SettingField {
        id: fewOptions
        x: 480
        y: 220
        width: 420
        key: "mode"
        spec: ({ type: "enum", label: "Mode", options: [{ value: "save-copy", label: "Save and copy" }, { value: "copy", label: "Copy" }, { value: "save", label: "Save" }] })
        value: "copy"
        onApply: value => root.applied.push(value)
    }
    SettingField {
        id: manyOptions
        x: 480
        y: 280
        width: 420
        key: "quality"
        spec: ({ type: "enum", label: "Quality", options: [{ value: "medium", label: "Medium" }, { value: "high", label: "High" }, { value: "very_high", label: "Very high" }, { value: "ultra", label: "Ultra" }] })
        value: "very_high"
        onApply: value => root.applied.push(value)
    }

    // A page taller than its view whose status-fed field sits at the
    // view's bottom edge, so its custom editor appears under that edge.
    ScrollArea {
        id: page
        x: 480
        width: 420
        height: 200
        Column {
            width: page.contentWidth
            Item { width: parent.width; height: 160 }
            SettingField {
                id: pageFed
                key: "device"
                spec: ({ type: "string", label: "Device", optionsFrom: "devices", allowCustom: true })
                choices: [{ label: "Alpha", value: "" }, { label: "Beta", value: "b" }]
                value: ""
            }
            Item { width: parent.width; height: 400 }
        }
    }

    // A label that needs more words carries a tooltip; a label wraps and
    // never elides; `probe` takes the labels whose drawn lines the
    // manifest judge's line count must match.
    Column {
        id: labelRows
        y: 700
        width: 420
        spacing: Theme.stack.row
        SettingField { id: explained; key: "smart"; spec: ({ type: "boolean", label: "Click to select", tooltip: "A click takes the window under it." }); value: true }
        SettingField { id: unexplained; key: "cursor"; spec: ({ type: "boolean", label: "Include pointer" }); value: true }
        SettingField { id: longLabel; key: "long"; spec: ({ type: "boolean", label: "A label that is far too long for two lines of its column" }); value: true }
        SettingField { id: probe; key: "probe"; spec: ({ type: "boolean", label: "Probe" }); value: true }
        SettingField { id: explainedChoice; key: "mode"; spec: ({ type: "enum", label: "Result", tooltip: "What a capture does.", options: [{ value: "both", label: "Save and copy" }, { value: "copy", label: "Copy" }] }); value: "both" }
    }

    Component { id: shippedField; SettingField { pluginId: "vgs.capture" } }
    Component {
        id: committingField
        SettingField {
            width: 420
            // QtTest constructor properties turn arrays into QVariant
            // sequences; decode the schema here as native JavaScript.
            required property string schemaJson
            spec: JSON.parse(schemaJson)
            property var written: []
            onApply: wanted => { written.push(wanted); value = wanted; }
        }
    }

    SettingField {
        id: languages
        x: 480
        y: 350
        width: 420
        key: "languages"
        spec: ({ type: "string", label: "Languages", separator: "+", allowCustom: true, presets: [{ value: "eng", label: "English" }, { value: "deu", label: "German" }, { value: "fra", label: "French" }] })
        value: "eng"
        property bool acceptWrites: true
        onApply: wanted => { root.applied.push(wanted); if (acceptWrites) value = wanted; }
    }

    // A Settings page over the rest of the window, so its image holds only
    // its own ink on the surface colour.
    Item {
        id: fakePanel
        property var shell: null
        property var plugins: []
        property var capture: null
        function writeKey() { return "ok"; }
        function writeSetting() { return "ok"; }
        function writePlacement() { return "ok"; }
        function setEnabled() { return "ok"; }
        function openTui() { return "ok"; }
        function refreshChoices() {}
        function openLink() {}
        function openPage() {}
        function leave(next) { next(); }
        function replyOf() { return ""; }
        function tuiKey(name) { return "tui:" + name; }
        function headReplies() { return []; }
    }
    Component {
        id: coveredPage
        Rectangle {
            property alias page: shown
            anchors.fill: parent
            z: 1
            color: Theme.color.surface
            PluginPage {
                id: shown
                width: 520
                height: parent.height
                panel: fakePanel
            }
        }
    }

    // Read-only key/value rows, as a device's details draw them, whose
    // values and hints hold descenders, tall glyphs, both or neither.
    Component {
        id: coveredText
        Rectangle {
            property alias rows: textRows
            anchors.fill: parent
            z: 1
            color: Theme.color.surface
            Column {
                id: textRows
                width: 420
                spacing: Theme.stack.row
                Field { label: "Name"; hint: "Seen here"; inline: true; width: parent.width; Label { role: "value"; text: "desk" } }
                Field { label: "Address"; hint: "Typing jumpy query"; inline: true; width: parent.width; Label { role: "value"; text: "100.64.0.1" } }
                Field { label: "Network"; inline: true; width: parent.width; Label { role: "value"; text: "jpqy.example" } }
                Field { label: "Account"; inline: true; width: parent.width; Label { role: "value"; text: "owner@fixture.example" } }
                Field { label: "State"; inline: true; width: parent.width; Label { role: "value"; text: "100 (connected)" } }
                Field { label: "Type"; inline: true; width: parent.width; Label { role: "value"; text: "ethernet" } }
            }
        }
    }

    // A grouped enum, as a provider choice of Local and three Cloud
    // offers, between two switches on the surface colour, so the rendered
    // image reads its rows' ink.
    Component {
        id: coveredGrouped
        Rectangle {
            id: groupedCover
            property alias rows: groupedRows
            property alias grouped: groupedField
            property alias after: afterField
            property var written: []
            anchors.fill: parent
            z: 1
            color: Theme.color.surface
            Column {
                id: groupedRows
                width: 420
                spacing: Theme.stack.row
                SettingField { key: "before"; spec: ({ type: "boolean", label: "Before" }); value: true }
                SettingField {
                    id: groupedField
                    key: "provider"
                    spec: ({ type: "enum", label: "Voice provider", groupLabel: "Cloud voice", options: [{ value: "local", label: "Local", group: "Local" },
                        { value: "realtime", label: "OpenAI Realtime", group: "Cloud" }, { value: "gemini", label: "Gemini Live", group: "Cloud" },
                        { value: "elevenlabs", label: "ElevenLabs", group: "Cloud" }] })
                    groups: [{ name: "Local", values: ["local"] }, { name: "Cloud", values: ["realtime", "gemini", "elevenlabs"] }]
                    value: "local"
                    onApply: chosen => {
                        groupedCover.written = groupedCover.written.concat([chosen]);
                        groupedField.value = chosen;
                    }
                }
                SettingField { id: afterField; key: "after"; spec: ({ type: "boolean", label: "After" }); value: true }
            }
        }
    }

    // A status-fed select whose entry ends its list with an Add entry and
    // plays each offer (`addChoice`, `preview`).
    Component {
        id: offeringField
        SettingField {
            property var written: []
            property int adds: 0
            property var previews: []
            width: 420
            key: "voiceAccount"
            spec: ({ type: "string", label: "Voice key", optionsFrom: "voiceAccounts", placeholder: "Choose a key", addChoice: { label: "Add a key", tui: "add-voice-key" }, preview: true })
            choices: [{ label: "OpenAI, key 1", value: "k1", offer: "k1" }, { label: "OpenAI, key 2", value: "k2", offer: "k2" }]
            value: "k1"
            onApply: chosen => { written = written.concat([chosen]); }
            onAddWanted: adds += 1
            onPreviewWanted: offer => { previews = previews.concat([offer]); }
        }
    }

    // The Voice list as PluginLogic.settingChoices gives it under the default
    // voice: the first offer stands for the unset "" and carries its own id,
    // and a stored voice no offer holds is listed with none.
    Component {
        id: voiceField
        SettingField {
            property var previews: []
            width: 420
            key: "voice"
            spec: ({ type: "string", label: "Voice", optionsFrom: "voices", preview: true })
            choices: [{ label: "Heart", value: "", offer: "af_heart" }, { label: "Bella", value: "af_bella", offer: "af_bella" }, { label: "Voice (unavailable)", value: "af_gone" }]
            value: ""
            onPreviewWanted: offer => { previews = previews.concat([offer]); }
        }
    }

    // A column of bare key/value rows, as the Displays, Capture and Sound
    // panes draw them: a select, a level slider, a level meter, a slider
    // with its reading, a slider, a segmented control, switches, one with a
    // message, and a text value, `spacing` apart by their boxes.
    Component {
        id: coveredBare
        Rectangle {
            property alias rows: bareRows
            property real spacing: 0
            anchors.fill: parent
            z: 1
            color: Theme.color.surface
            Column {
                id: bareRows
                width: 420
                spacing: parent.spacing
                FormRow { label: "Display"; width: parent.width; Select { width: parent.width; model: ["Built-in", "External"] } }
                FormRow { label: "Volume"; width: parent.width; LevelSlider { width: parent.width; iconName: "volume-2"; buttonLabel: "Mute output"; value: 0.5 } }
                FormRow { label: "Level"; width: parent.width; ProgressBar { width: parent.width; value: 0.4 } }
                FormRow { label: "Radius"; width: parent.width; SavedSlider { width: parent.width; from: 0; to: 32; shown: 12; formatValue: value => Math.round(value) + " px" } }
                FormRow { label: "Scale"; width: parent.width; Slider { width: parent.width; from: 0; to: 100; value: 40 } }
                FormRow { label: "Mode"; width: parent.width; SegmentedControl { width: parent.width; model: ["Extend", "Mirror"] } }
                FormRow { label: "Mute"; width: parent.width; Switch { size: "sm"; checked: true } }
                FormRow { label: "Speed"; warning: "Overridden by policy"; width: parent.width; Switch { size: "sm" } }
                FormRow { label: "Device"; width: parent.width; Label { role: "value"; text: "Analog stereo output" } }
                FormRow { label: "Linked"; width: parent.width; Switch { checked: false } }
            }
        }
    }

    // Rows a Repeater draws from a model a test reorders, as Sound's Apps
    // rows follow a ScriptModel: bare rows, and fields.
    ListModel { id: order }
    Component {
        id: reorderedBare
        Column {
            x: 480
            width: 420
            spacing: Theme.stack.row
            Repeater {
                model: order
                FormRow { required property string name; label: name; width: parent === null ? 0 : parent.width; Switch { size: "sm" } }
            }
        }
    }
    Component {
        id: reorderedFields
        Column {
            x: 480
            width: 420
            spacing: Theme.stack.row
            Repeater {
                model: order
                Field { required property string name; label: name; inline: true; width: parent === null ? 0 : parent.width; Switch { size: "sm" } }
            }
        }
    }

    // A preset select whose stored value, a review command, is wider than
    // its control, between two switches on the surface colour, so the
    // rendered image reads its rows' ink. Both commands hold hyphens a line
    // could break after.
    readonly property string longClaude: "claude --model opus --effort medium --permission-mode default"
    readonly property string longCodex: "codex -m gpt-6.1-sol -c model_reasoning_effort=medium --sandbox workspace-write --ask-for-approval on-request"
    Component {
        id: coveredLong
        Rectangle {
            property alias rows: longRows
            property alias before: longBefore
            property alias long: longField
            property alias after: longAfter
            anchors.fill: parent
            z: 1
            color: Theme.color.surface
            Column {
                id: longRows
                width: 420
                spacing: Theme.stack.row
                SettingField { id: longBefore; key: "before"; spec: ({ type: "boolean", label: "Before" }); value: true }
                SettingField {
                    id: longField
                    key: "reviewCommand"
                    spec: ({ type: "string", label: "Review command", allowCustom: true, presets: [{ value: "", label: "Automatic" }, { value: root.longClaude }, { value: root.longCodex }] })
                    value: root.longCodex
                }
                SettingField { id: longAfter; key: "after"; spec: ({ type: "boolean", label: "After" }); value: true }
            }
        }
    }
    // A window on the screen a test names, which draws at that screen's
    // scale, for the long value at 2x. The plugin's own Window shadows
    // Qt's.
    Component {
        id: scaledWindow
        QtWindow.Window { width: 480; height: 360; color: Theme.color.surface }
    }
    // A TextEdit lays its text out as a Text of the same width, font and
    // wrap does, and reports where each character went.
    Component {
        id: layoutTwin
        TextEdit { textFormat: TextEdit.PlainText; readOnly: true; visible: false }
    }

    TestCase {
        name: "settingfield"
        when: windowShown

        function init() {
            UnitTheme.reset();
            root.applied = [];
            root.opened = [];
            field.value = "HH:mm";
            picked.value = "";
            customFed.choices = [{ label: "Alpha", value: "" }, { label: "Beta", value: "b" }];
            customFed.value = "";
            customFed.customChosen = false;
            pageFed.value = "";
            pageFed.customChosen = false;
            page.contentY = 0;
            languages.acceptWrites = true;
            languages.editable = true;
            languages.value = "eng";
            languages.customChosen = false;
            Time.now = new Date(2026, 8, 30, 20, 34, 0);
        }

        function descendants(item) {
            const found = [item];
            for (let i = 0; i < found.length; i++)
                for (const child of found[i].children || []) found.push(child);
            return found;
        }

        function lineBottom(field, text) {
            const line = descendants(field).find(child => child.role === "hint" && child.text === text && child.visible);
            return line.mapToItem(settingRows, 0, line.height).y;
        }

        function test_a_group_space_follows_a_description() {
            verify(customDescribed.customVisible, "the custom field shows");
            tryVerify(() => customDescribed.y - lineBottom(described, "How often it checks.") === Theme.stack.group, 1000, "the field after a description");
            compare(following.y - lineBottom(customDescribed, "The unit it shows."), Theme.stack.group, "the field after a custom field's description");
            compare(settingRows.height, lineBottom(lastDescribed, "Ends the column."), "the column's end after its last field");
        }

        // The shown LinkText: `linked` is its own, where `hoveredLink` is
        // also every Text's.
        function linkOf(item) {
            return descendants(item).find(child => child.linked !== undefined && child.visible);
        }

        function test_a_description_link_opens_its_address_by_pointer() {
            const link = linkOf(keyLinked);
            verify(link !== undefined, "the description draws through a link text");
            compare(link.text, "OpenAI API keys gives you a key.");
            verify(link.linked, "the link's words are a link");
            mouseClick(link, 4, link.height / 2);
            compare(root.opened, ["https://platform.openai.com/api-keys"], "a click opens the address");
            mouseClick(link, link.width - 4, link.height / 2);
            compare(root.opened, ["https://platform.openai.com/api-keys"], "a click past the link's words opens nothing");
        }

        function test_a_description_link_opens_its_address_by_keyboard() {
            const link = linkOf(keyLinked);
            verify(link.activeFocusOnTab, "the link is a Tab stop");
            link.forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Return);
            keyClick(Qt.Key_Enter);
            compare(root.opened, ["https://platform.openai.com/api-keys", "https://platform.openai.com/api-keys"], "Return and Enter open the address");
        }

        function test_a_description_page_reference_asks_for_its_page() {
            root.pages = [];
            const link = linkOf(pageLinked);
            verify(link !== undefined && link.linked, "the reference's words are a link");
            mouseClick(link, 4, link.height / 2);
            compare(root.pages, ["acme.models/Setup"], "a click asks for the page and tab");
            compare(root.opened, [], "and opens no address");
        }

        function test_a_custom_field_description_link_opens_its_address() {
            verify(customLinked.customVisible, "the custom field shows");
            const link = linkOf(customLinked);
            verify(link !== undefined && link.linked, "the custom field's description draws its link");
            link.forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Return);
            compare(root.opened, ["https://example.org/units"]);
        }

        function test_a_field_without_a_link_draws_none() {
            const link = linkOf(described);
            verify(link !== undefined, "a description draws through a link text");
            verify(!link.linked, "a description without a link draws none");
            verify(!link.activeFocusOnTab, "and takes no Tab stop");
        }

        function test_an_error_line_carries_no_link() {
            const link = linkOf(erred);
            compare(link.text, "The key page refused that key.");
            verify(!link.linked, "the error line draws no link");
        }

        function selectOf(item) {
            return descendants(item).find(child => String(child).indexOf("Select") === 0);
        }

        function languageMenu() {
            const button = descendants(languages).find(child => String(child).indexOf("Button") === 0 && child.listOpen !== undefined);
            verify(button !== undefined, "joined presets draw the button editor");
            return descendants(button).find(child => typeof child.items === "function" && typeof child.toggle === "function");
        }

        function checkedLanguages(menu) {
            return menu.items().filter(item => item.checked).map(item => item.modelData.value);
        }

        function test_joined_values_load_without_writes_data() {
            return [
                { tag: "saved pair", value: "deu+fra", checked: ["deu", "fra"], custom: false },
                { tag: "old pair", value: "eng+deu", checked: ["eng", "deu"], custom: false },
                { tag: "custom order", value: "fra+lat+deu", checked: ["deu", "fra"], custom: true },
                { tag: "empty", value: "", checked: [], custom: false }
            ];
        }

        function test_joined_values_load_without_writes(data) {
            languages.value = data.value;
            compare(checkedLanguages(languageMenu()), data.checked);
            compare(languages.customVisible, data.custom);
            compare(root.applied, []);
            compare(languages.value, data.value);
        }

        function test_language_ticks_write_joined_values_and_keep_the_menu_open() {
            const menu = languageMenu();
            menu.open("key");
            try {
                menu.items()[0].clicked();
                menu.items()[1].clicked();
                menu.items()[2].clicked();
                compare(root.applied, ["", "deu", "deu+fra"]);
                compare(languages.value, "deu+fra");
                compare(checkedLanguages(menu), ["deu", "fra"]);
                compare(languages.customVisible, false);
                compare(menu.opened, true);
                menu.move(1);
                compare(root.applied, ["", "deu", "deu+fra"]);
            } finally { menu.close(); }
        }

        function test_language_ticks_preserve_custom_order_and_refused_writes() {
            const menu = languageMenu();
            languages.value = "fra+lat+deu";
            menu.items()[1].clicked();
            menu.items()[0].clicked();
            compare(languages.value, "fra+lat+eng");
            compare(root.applied, ["fra+lat", "fra+lat+eng"]);
            languages.acceptWrites = false;
            menu.items()[2].clicked();
            compare(languages.value, "fra+lat+eng");
            compare(checkedLanguages(menu), ["eng", "fra"]);
            languages.editable = false;
            menu.items()[0].clicked();
            compare(root.applied, ["fra+lat", "fra+lat+eng", "lat+eng"]);
        }

        function test_a_short_enum_draws_labels_and_writes_values() {
            const segments = descendants(fewOptions).find(child => String(child).indexOf("SegmentedControl") === 0);
            verify(segments !== undefined, "three options draw as a segmented control");
            compare(segments.model, ["Save and copy", "Copy", "Save"], "each segment reads its option's label");
            compare(segments.currentIndex, 1, "the stored value chooses its segment");
            segments.choose(0);
            compare(root.applied, ["save-copy"], "a segment writes its option's value");
            compare(segments.currentIndex, 1, "the segment follows what the configuration holds");
        }

        function test_a_long_enum_draws_labels_and_writes_values() {
            const select = selectOf(manyOptions);
            verify(select !== undefined, "four options draw as a Select");
            compare(select.contentItem.text, "Very high", "the Select reads the stored value's label");
            compare(select.model.map(row => row.label), ["Medium", "High", "Very high", "Ultra"], "each row reads its option's label");
            select.choose(3);
            compare(root.applied, ["ultra"], "a row writes its option's value");
            compare(select.currentIndex, 2, "the Select follows what the configuration holds");
        }

        function selectListWindow(owner) {
            let window = null;
            for (let i = 0; i < owner.resources.length; i++)
                if (owner.resources[i].anchor !== undefined) window = owner.resources[i];
            return window;
        }

        function selectList(owner) {
            const window = selectListWindow(owner);
            const scope = window.contentItem.children.find(child => child.popup !== undefined);
            return scope.children.find(child => child.currentIndex !== undefined);
        }

        function test_unset_choice_reads_its_placeholder() {
            const select = selectOf(picked);
            verify(select !== undefined, "the choice Select exists");
            compare(select.contentItem.text, picked.spec.placeholder, "unset, the Select reads the placeholder");
            compare(select.Accessible.name, picked.spec.placeholder, "unset, the Select is named by the placeholder");
            verify(Qt.colorEqual(select.contentItem.color, Theme.textField.placeholder), "the placeholder draws dimmed");
            picked.value = picked.choices[1].value;
            tryCompare(select.contentItem, "text", picked.choices[1].label, 1000, "a chosen value reads its offer");
            compare(select.Accessible.name, picked.choices[1].label, "a chosen value names its offer");
            verify(!Qt.colorEqual(select.contentItem.color, Theme.textField.placeholder), "a chosen value draws undimmed");
        }

        function test_unset_choice_opens_with_nothing_highlighted() {
            const select = selectOf(picked);
            select.openList();
            const list = selectList(select);
            tryVerify(() => list.itemAtIndex(0) !== null, 1000, "the choice list builds entries");
            compare(list.highlightIndex, -1, "an unset choice opens with no entry highlighted");
            list.Window.window.requestActivate();
            list.forceActiveFocus();
            tryCompare(list.Window, "active", true);
            tryCompare(list, "activeFocus", true);
            keyClick(Qt.Key_Down);
            compare(list.highlightIndex, 0, "Down moves to the first entry");
            keyClick(Qt.Key_Escape);
            tryCompare(select, "listOpen", false);
            compare(picked.value, "", "moving the highlight chooses nothing");
        }

        function test_open_datetime_list_keeps_highlight_across_clock_tick() {
            const select = selectOf(field);
            verify(select !== undefined, "the preset Select exists");
            select.openList();
            const list = selectList(select);
            tryVerify(() => list.itemAtIndex(0) !== null, 1000, "the preset list builds entries");
            list.Window.window.requestActivate();
            list.forceActiveFocus();
            tryCompare(list.Window, "active", true);
            tryCompare(list, "activeFocus", true);
            tryVerify(() => list.itemAtIndex(2) !== null, 1000, "the preset list builds the target entry");
            keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Down);
            compare(list.highlightIndex, 2);
            Time.now = new Date(2026, 8, 30, 20, 35, 0);
            compare(list.highlightIndex, 2, "a clock tick does not reset the highlighted preset");
            keyClick(Qt.Key_Return);
            tryCompare(select, "listOpen", false);
            compare(root.applied, ["yyyy-MM-dd HH:mm"]);
        }

        // The text of the custom editor `owner` shows, or null.
        function shownCustomText(owner) {
            const input = descendants(owner).find(child => child instanceof TextInput && child.visible);
            return input === undefined ? null : input.text;
        }

        function test_a_custom_status_choice_lists_its_choices_then_custom() {
            const select = selectOf(customFed);
            compare(select.count, customFed.choices.length + 1, "one row follows the published choices");
            compare(JSON.stringify(select.model.slice(0, customFed.choices.length)), JSON.stringify(customFed.choices), "the published choices lead in order");
            compare(select.model[customFed.choices.length].custom, true, "the last row is Custom…");
            compare(select.currentIndex, 0, "the unset value reads as the first offer");
            verify(!customFed.customVisible, "an offered value opens no custom editor");
            compare(shownCustomText(customFed), null);
        }

        function test_choosing_custom_opens_the_editor_and_writes_nothing() {
            const select = selectOf(customFed);
            customFed.value = "b";
            select.choose(customFed.choices.length);
            verify(customFed.customVisible, "Custom… opens the custom editor");
            compare(shownCustomText(customFed), "b", "status-fed Custom retains the configured choice");
            compare(root.applied, [], "choosing Custom… writes nothing");
            compare(select.currentIndex, 1, "an offered value keeps its own row");
            customFed.value = "";
            verify(!customFed.customVisible, "a write of an offered value closes the custom editor");
            select.choose(customFed.choices.length);
            compare(shownCustomText(customFed), "", "status-fed choices supply no preset seed");
            select.choose(1);
            verify(!customFed.customVisible, "choosing an offer closes the custom editor");
            compare(root.applied, ["b"], "choosing an offer writes its value");
        }

        function test_custom_prefill_is_an_unsaved_draft_data() {
            const request = new XMLHttpRequest();
            request.open("GET", Qt.resolvedUrl("../../shell/plugins/vgs.updates/manifest.json"), false);
            request.send();
            const schema = JSON.parse(request.responseText).schema;
            return [
                { tag: "AUR automatic", spec: schema.aurCommand, held: "", seed: "paru -Sua" },
                { tag: "review automatic", spec: schema.reviewCommand, held: "", seed: "claude --model opus --effort medium --permission-mode default" },
                { tag: "chosen preset", spec: schema.aurCommand, held: "yay -Sua", seed: "yay -Sua" },
                { tag: "saved custom", spec: schema.aurCommand, held: "own-update --aur", seed: "own-update --aur" },
                { tag: "unbounded number", spec: { type: "number", allowCustom: true, presets: [{ value: 0 }, { value: 30 }] }, held: 0, seed: "0" },
                { tag: "bounded slider", spec: { type: "number", allowCustom: true, min: 0, max: 60, presets: [{ value: 0 }, { value: 30 }] }, held: 0, bounded: true },
                { tag: "no nonempty preset", spec: { type: "string", allowCustom: true, presets: [{ value: "" }] }, held: "", seed: "" }
            ];
        }

        function test_custom_prefill_is_an_unsaved_draft(data) {
            const made = createTemporaryObject(committingField, root, { schemaJson: JSON.stringify(data.spec), value: data.held });
            verify(made !== null);
            tryVerify(() => selectOf(made) !== undefined);
            const select = selectOf(made);
            select.choose(select.count - 1);
            if (data.bounded === true) {
                verify(made.customVisible);
                compare(shownCustomText(made), null, "bounded Custom keeps its slider");
                verify(descendants(made).some(child => String(child).indexOf("Slider") === 0));
                compare(made.written, []);
                return;
            }
            const input = descendants(made).find(child => child instanceof TextInput && child.visible);
            verify(input !== undefined);
            compare(input.text, data.seed, "Custom starts from the chosen value or the first nonempty own preset");
            compare(made.value, data.held, "opening Custom stores nothing");
            compare(made.written, []);
            input.forceActiveFocus();
            keyClick(Qt.Key_Escape);
            compare(input.text, String(data.held), "Escape drops the seeded draft");
            compare(made.written, []);
            verify(!made.edited);
            select.choose(0);
            made.value = data.held;
            made.written = [];
            select.choose(select.count - 1);
            compare(input.text, data.seed, "reopening starts a new draft");
            made.editable = false;
            compare(input.text, String(data.held), "a read-only field drops the draft");
            verify(!made.edited);
            made.editable = true;
            select.choose(0);
            made.value = data.held;
            made.written = [];
            select.choose(select.count - 1);
            const saved = data.seed !== String(data.held) ? data.seed : data.spec.type === "number" ? "31" : data.seed + " edited";
            input.text = saved;
            select.choose(select.count - 1);
            compare(input.text, saved, "choosing Custom again preserves entered text");
            input.forceActiveFocus();
            keyClick(Qt.Key_Return);
            compare(made.value, data.spec.type === "number" ? Number(saved) : saved);
            compare(made.written, [made.value], "Enter saves the draft");
            verify(!made.edited);
        }

        function test_custom_prefill_requires_an_editable_custom_choice_data() {
            const request = new XMLHttpRequest();
            request.open("GET", Qt.resolvedUrl("../../shell/plugins/vgs.jarvis/manifest.json"), false);
            request.send();
            const home = JSON.parse(request.responseText).schema.home;
            request.open("GET", Qt.resolvedUrl("../../shell/plugins/vgs.bar/manifest.json"), false);
            request.send();
            const calendar = JSON.parse(request.responseText).schema.calendarUrl;
            return [
                { tag: "read-only Custom", editable: false, statusFed: false, spec: { type: "string", allowCustom: true, presets: [{ value: "" }, { value: "example" }] } },
                { tag: "choices cleared", editable: true, statusFed: true, spec: home },
                { tag: "plugin disabled clears choices", editable: false, statusFed: true, spec: home },
                { tag: "initially visible blank calendar URL", editable: true, statusFed: false, spec: calendar, visibleInitially: true, typed: "https://calendar.example.org/" }
            ];
        }

        function test_custom_prefill_requires_an_editable_custom_choice(data) {
            // Plugin disable clears Jarvis's Home folder choices while its
            // stored folder remains. That reveals a row, not a Custom choice.
            const held = data.statusFed ? "chosen-home" : "";
            const made = createTemporaryObject(committingField, root, { schemaJson: JSON.stringify(data.spec), value: held });
            verify(made !== null);
            made.choices = [{ label: "Chosen home", value: held }];
            compare(made.customVisible, data.visibleInitially === true);
            const input = descendants(made).find(child => child instanceof TextInput);
            verify(input !== undefined);
            if (data.typed !== undefined) input.text = data.typed;
            made.editable = data.editable;
            if (data.statusFed) made.choices = [];
            else selectOf(made).choose(selectOf(made).count - 1);
            compare(input.text, data.typed === undefined ? held : data.typed, "a read-only or unchosen row gets no seed, and an entered draft survives Custom");
            compare(input.readOnly, !data.editable);
            compare(made.customChosen, data.typed !== undefined);
            compare(made.edited, data.typed !== undefined);
            compare(made.written, []);
            compare(made.customVisible, data.statusFed || data.visibleInitially === true, "a lost or custom stored value remains visible");
        }

        function test_a_value_no_choice_holds_shows_under_custom() {
            const select = selectOf(customFed);
            customFed.value = "gone";
            tryCompare(select, "currentIndex", customFed.choices.length, 1000, "the select reads Custom…");
            verify(customFed.customVisible, "the custom editor shows");
            compare(shownCustomText(customFed), "gone", "the editor holds the configured value");
            customFed.value = "";
            customFed.choices = [];
            verify(!customFed.customVisible, "the unset value is never a custom one");
            compare(select.currentIndex, -1, "an unset value with no offers reads no row");
        }

        // The bottom of the custom editor's text box in the page's view.
        function customBottomInView() {
            const input = descendants(pageFed).find(child => child instanceof TextInput && child.visible);
            return input === undefined ? Infinity : input.mapToItem(page, 0, input.height).y;
        }

        function test_an_appearing_custom_editor_scrolls_into_view() {
            verify(customBottomInView() === Infinity, "no custom editor shows at first");
            pageFed.value = "gone";
            tryVerify(() => customBottomInView() <= page.height && page.contentY > 0, 1000, "a value no choice holds brings its editor into view");
            page.contentY = 0;
            pageFed.value = "";
            verify(!pageFed.customVisible);
            selectOf(pageFed).choose(pageFed.choices.length);
            tryVerify(() => customBottomInView() <= page.height && page.contentY > 0, 1000, "choosing Custom… brings its editor into view");
        }

        function test_a_custom_editor_in_view_moves_no_page() {
            page.contentY = 120;
            pageFed.value = "gone";
            tryVerify(() => pageFed.customVisible && !pageFed.revealPending, 1000, "the editor is laid out");
            wait(0);
            compare(page.contentY, 120, "an editor the view already shows scrolls nothing");
            verify(customBottomInView() < page.height, "the editor shows");
        }

        function labelOf(owner) {
            return descendants(owner).find(child => child.objectName === "fieldLabel" && child.visible);
        }

        // Whether the setting's explainer, opened under its row over the
        // description, takes more than one line, which the row hands to its
        // info dialog. The room under a
        // description's top holds a band of one line and no more. The row
        // is as wide as a Settings page: the window less its panel inset.
        function explainerWraps(key, spec) {
            const made = createTemporaryObject(shippedField, root, { width: Theme.size.window.width - 2 * Theme.surface.padding, key: key, spec: spec, value: spec.default });
            const row = descendants(made).find(child => child.objectName === "fieldRow");
            if (row.explainInDialog) return true;
            if (row.explainBeside) return false;
            const tip = descendants(labelOf(made)).find(child => String(child).indexOf("Tooltip") === 0);
            compare(tip.text, spec.tooltip);
            tip.shown = true;
            try {
                // A tooltip made in this turn builds its window on the next
                // (stand-ins/LazyLoader.qml).
                tryVerify(() => tip.opened, 1000, "the explainer opens its own surface");
                const title = descendants(tip.tracker.popup.contentItem).find(child => child.objectName === "tooltipTitle");
                return title.lineCount > 1;
            } finally {
                tip.shown = false;
            }
        }

        // Capture ships the settings that carry both an explainer and a
        // description; a plugin that adds one adds its manifest here.
        function test_a_shipped_explainer_over_a_description_keeps_one_line() {
            const request = new XMLHttpRequest();
            request.open("GET", Qt.resolvedUrl("../../shell/plugins/vgs.capture/manifest.json"), false);
            request.send();
            const schema = JSON.parse(request.responseText).schema;
            const keys = Object.keys(schema).filter(key => schema[key].tooltip !== undefined && schema[key].description !== undefined);
            verify(keys.length > 0, "the manifest holds no explained setting with a description");
            for (const key of keys)
                verify(!explainerWraps(key, schema[key]), key + ": the explainer wraps over its description: " + schema[key].tooltip);
            const planted = Object.assign({}, schema[keys[0]], { tooltip: "Records every frame at the same interval, even when nothing on the screen moves, for as long as the recording runs." });
            verify(explainerWraps(keys[0], planted), "control: a planted long explainer wraps");
        }

        function test_a_label_tooltip_opens_on_hover_and_keyboard_focus() {
            compare(UnitTheme.override({ tooltip: { delay: 50 } }), "ok");
            const label = labelOf(explained);
            const tip = descendants(label).find(child => String(child).indexOf("Tooltip") === 0);
            compare(tip.text, explained.spec.tooltip, "the label's tooltip reads the schema's tooltip");
            mouseMove(root, root.width - 1, root.height - 1);
            mouseMove(label, label.width / 2, label.height / 2);
            tryCompare(tip, "opened", true, 2000, "hover opens the tooltip");
            mouseMove(root, root.width - 1, root.height - 1);
            tryCompare(tip, "opened", false);
            root.Window.window.requestActivate();
            tryCompare(root.Window.window, "active", true);
            const labelControl = label.children.find(child => child.visualFocus !== undefined);
            verify(labelControl.activeFocusOnTab, "the label is a Tab stop");
            const shown = [];
            const record = () => { if (tip.opened) shown.push(tip.text); };
            tip.openedChanged.connect(record);
            try {
                labelControl.forceActiveFocus(Qt.TabFocusReason);
                tryVerify(() => shown.length > 0, 2000, "keyboard focus opens the tooltip");
            } finally {
                tip.openedChanged.disconnect(record);
            }
            compare(shown[0], explained.spec.tooltip);
            const plain = labelOf(unexplained).children.find(child => child.visualFocus !== undefined);
            verify(!plain.activeFocusOnTab, "a label without a tooltip is no Tab stop");
        }

        // A short segmented editor draws less than its row's value column,
        // so the label's explainer opens past its last segment.
        function test_a_segmented_editor_ends_where_its_segments_end() {
            const row = descendants(explainedChoice).find(child => child.objectName === "fieldRow");
            const segmented = descendants(explainedChoice).find(child => String(child).indexOf("SegmentedControl") === 0);
            const end = segmented.mapToItem(row, segmented.width, 0).x;
            verify(end < row.width, "the segments stop short of the row's end edge");
            fuzzyCompare(row.controlEnd, end, 1, "the row reads the segments' end");
        }

        function test_a_long_label_wraps_and_never_elides() {
            const label = labelOf(longLabel);
            verify(label.lineCount > 2, "the label wraps past two lines");
            compare(label.truncated, false, "the label elides");
            // The row box, which a row stood under another by ink may
            // overlap, holds the label.
            verify(label.parent.objectName === "fieldRow" && label.parent.height >= label.implicitHeight, "the row holds every line");
        }

        // The manifest judge's characters a line, with and without an info
        // mark, are the drawn label's at the default theme: that many of the
        // widest capital fill one line, and one more wraps.
        function test_the_judge_line_counts_fill_one_drawn_line_data() {
            return [
                { tag: "plain", info: false, characters: PluginLogic.LABEL_LINE_CHARACTERS },
                { tag: "beside an info mark", info: true, characters: PluginLogic.INFO_LABEL_LINE_CHARACTERS }
            ];
        }

        function test_the_judge_line_counts_fill_one_drawn_line(data) {
            for (const [characters, lines] of [[data.characters, 1], [data.characters + 1, 2]]) {
                const spec = { type: "boolean", label: "M".repeat(characters) };
                if (data.info) spec.info = "Why it matters.";
                probe.spec = spec;
                tryCompare(labelOf(probe), "lineCount", lines, 2000, characters + " characters");
            }
        }

        // The judge's line count of a label is the drawn one: a line breaks
        // after a space or after a hyphen no digit follows.
        function test_the_judge_counts_the_drawn_lines_data() {
            return [
                { tag: "one line", label: "Include pointer" },
                { tag: "a space break", label: "Click to select a window or display" },
                { tag: "a hyphen break", label: "Review third-party packages" },
                { tag: "a hyphen break beside an info mark", label: "Use third-party keys", info: true },
                { tag: "a hyphen before a digit keeps its word", label: "Aaaa bbbbbbbbbbb-10 ccccccccccccc" },
                { tag: "three lines", label: "Trim and level finished recordings" }
            ];
        }

        function test_the_judge_counts_the_drawn_lines(data) {
            const spec = { type: "boolean", label: data.label };
            if (data.info === true) spec.info = "Why it matters.";
            probe.spec = spec;
            const characters = data.info === true ? PluginLogic.INFO_LABEL_LINE_CHARACTERS : PluginLogic.LABEL_LINE_CHARACTERS;
            tryCompare(labelOf(probe), "lineCount", PluginLogic.labelLines(data.label, characters), 2000);
        }

        // A plugin's row whose settings hold each control a Settings row
        // draws, in GROUP ("" for none): a slider, a segmented control, a
        // select, a switch, a select with a description and two switches,
        // the first with its stored key's line under it. A group follows its bar widget's Show on the bar switch, a
        // SettingField of its own.
        function controlRow(group) {
            const at = spec => group === "" ? spec : Object.assign({ group: group }, spec);
            const four = [{ value: "a", label: "Alpha" }, { value: "b", label: "Beta" }, { value: "c", label: "Gamma" }, { value: "d", label: "Delta" }];
            const schema = {
                interval: at({ type: "number", label: "Interval", min: 1, max: 60 }),
                view: at({ type: "enum", label: "View", options: [{ value: "compact", label: "Compact" }, { value: "full", label: "Full" }] }),
                sort: at({ type: "enum", label: "Sort", options: four }),
                colour: at({ type: "boolean", label: "Colour" }),
                number: at({ type: "enum", label: "Number", description: "How the bar picks one number", options: four }),
                after: at({ type: "boolean", label: "After" }),
                last: at({ type: "boolean", label: "Last" })
            };
            const status = { afterKeys: { type: "presenceList", label: "After keys", setting: "after" } };
            return {
                id: "acme.rows", name: "Rows", version: "1.0.0", description: "", author: "", license: "", icon: "package",
                source: "bundled", enabled: true, alwaysOn: false, placed: true, kinds: ["service"], capabilities: [],
                builtins: group === "" ? [] : [{ id: "acme.rows.bar", name: group, placed: true }],
                schema: schema, settings: { interval: 15, view: "full", sort: "a", colour: true, number: "b", after: false, last: true },
                settingChoices: ({}), status: PluginLogic.statusRows({ status: status, secrets: { service: "acme-unit", label: "Key" } }, { afterKeys: [] }),
                secretLabel: "Key", tuis: [], opens: "", paneHolder: "", binds: [], requirements: [],
                errors: [], fieldRows: PluginLogic.fieldRows(schema, status)
            };
        }

        function inked(img, x, y) {
            const bg = Qt.color(Theme.color.surface);
            return Math.abs(img.red(x, y) - Math.round(bg.r * 255)) > 8 || Math.abs(img.green(x, y) - Math.round(bg.g * 255)) > 8
                || Math.abs(img.blue(x, y) - Math.round(bg.b * 255)) > 8;
        }
        function rowInked(img, y, width) {
            for (let x = 0; x < width; x++) if (inked(img, x, y)) return true;
            return false;
        }
        // The blank pixel rows of the band that holds the top edge of
        // LOWER's row box: the drawn space between the row above it and
        // LOWER, 0 when ink crosses that edge.
        function gapOver(img, lower, width) {
            const edge = Math.floor(lower.mapToItem(root, 0, 0).y);
            if (rowInked(img, edge, width)) return 0;
            let top = edge;
            let bottom = edge;
            while (top > 0 && !rowInked(img, top - 1, width)) top--;
            while (bottom < img.height - 1 && !rowInked(img, bottom + 1, width)) bottom++;
            return bottom - top + 1;
        }

        // The blank pixel rows of the band between UPPER's lowest text line
        // and LOWER's highest: the band that holds the row halfway between
        // them, 0 when ink crosses it. A column whose spacing exceeds the
        // space can put LOWER's own edge inside its ink.
        function gapBetween(img, upper, lower, width) {
            const bottom = upper.mapToItem(root, 0, upper.height - upper.lineBelow()).y;
            const top = lower.mapToItem(root, 0, lower.lineAbove()).y;
            const middle = Math.floor((bottom + top) / 2);
            if (rowInked(img, middle, width)) return 0;
            let from = middle;
            let to = middle;
            while (from > 0 && !rowInked(img, from - 1, width)) from--;
            while (to < img.height - 1 && !rowInked(img, to + 1, width)) to++;
            return to - from + 1;
        }

        // Every key/value row of a Settings page leaves the same drawn
        // space, `stack.page`, between its lowest drawn pixel and the next
        // row's highest, whatever control either holds: rows of no group
        // under the Enabled switch, and rows of one section, whose first
        // row stands under its heading instead. A theme's step moves it.
        // Spaced by their boxes, `stack.row` apart, the same rows stand 8
        // (select over select), 16 (select over switch) and 24 (switch over
        // switch) blank rows apart: the control in scripts/test-qml-unit.sh.
        function test_rows_stand_one_step_apart_by_ink_data() {
            const all = ["Enabled", "Interval", "View", "Sort", "Colour", "Number", "After", "After keys", "Last"];
            return [
                { tag: "no group", group: "", labels: all, step: 0 },
                { tag: "one section", group: "Bar", labels: [SettingValues.PAGE_LABELS.showOnBar].concat(all.slice(1)), step: 0 },
                { tag: "a theme's step", group: "", labels: all, step: 20 }
            ];
        }

        function test_rows_stand_one_step_apart_by_ink(data) {
            if (data.step > 0) compare(UnitTheme.override({ stack: { page: data.step } }), "ok");
            const cover = createTemporaryObject(coveredPage, root);
            verify(cover !== null);
            cover.page.row = controlRow(data.group);
            const rows = () => descendants(cover.page).filter(item => item.objectName === "fieldRow" && item.visible && item.height > 0);
            const byLabel = label => rows().find(item => item.label === label);
            tryVerify(() => data.labels.every(label => byLabel(label) !== undefined), 2000, "the page draws every row");
            verify(waitForRendering(cover));
            const img = grabImage(root);
            const gaps = data.labels.slice(1).map((label, i) => ({ pair: data.labels[i] + "/" + label, gap: gapOver(img, byLabel(label), cover.page.width) }));
            const want = Theme.stack.page;
            const read = gaps.map(entry => entry.pair + " " + entry.gap).join(", ");
            for (const entry of gaps)
                verify(Math.abs(entry.gap - want) <= 1, "every row stands " + want + " blank rows under the one above: " + read);
        }

        // A column of bare FormRows leaves the same drawn space between its
        // rows as a column of Fields, `stack.page`, by the one rule a Field
        // stands by (FormRow `inkTop`), whatever the column's spacing, and
        // each row box stays `row.height`. Spaced by their boxes, the
        // control in scripts/test-qml-unit.sh, the rows stand apart by the
        // column's spacing and what each control leaves blank in its box.
        function test_bare_rows_stand_one_step_apart_by_ink_data() {
            return [
                { tag: "row spacing", spacing: "row", step: 0 },
                { tag: "group spacing", spacing: "group", step: 0 },
                { tag: "a theme's step", spacing: "group", step: 20 },
                { tag: "a reading taller than the level slider's glyph", spacing: "row", step: 0, label: 24 }
            ];
        }

        function test_bare_rows_stand_one_step_apart_by_ink(data) {
            if (data.step > 0) compare(UnitTheme.override({ stack: { page: data.step } }), "ok");
            if (data.label !== undefined) compare(UnitTheme.override({ text: { label: { size: data.label } } }), "ok");
            const cover = createTemporaryObject(coveredBare, root, { spacing: Theme.stack[data.spacing] });
            verify(cover !== null);
            verify(waitForRendering(cover));
            const rows = cover.rows.children.filter(item => item.objectName === "fieldRow");
            compare(rows.length, 10);
            for (const row of rows) compare(row.boxHeight, Theme.row.height, row.label + " keeps the row box");
            const img = grabImage(root);
            const gaps = rows.slice(1).map((row, i) => ({ pair: rows[i].label + "/" + row.label, gap: gapBetween(img, rows[i], row, cover.rows.width) }));
            const want = Theme.stack.page;
            const read = gaps.map(entry => entry.pair + " " + entry.gap).join(", ");
            for (const entry of gaps)
                verify(Math.abs(entry.gap - want) <= 1, "every bare row stands " + want + " blank rows under the one above: " + read);
        }

        // Each shown key/value row of COLUMN, in its children's order, the
        // FormRow that measures it, and whether each stands under the one
        // before it.
        function orderedRows(column) {
            return column.children.filter(child => child.keyValueRow === true && child.visible);
        }
        function formRowOf(item) {
            return item.objectName === "fieldRow" ? item : item.children.find(child => child.objectName === "fieldRow");
        }
        function eachUnderTheOneBefore(column) {
            const rows = orderedRows(column);
            return rows.every((row, i) => {
                const above = formRowOf(row).rowAbove;
                return i === 0 ? above === null : above !== null && above.item === rows[i - 1];
            });
        }
        function readOrder(column) {
            return orderedRows(column).map(row => {
                const above = formRowOf(row).rowAbove;
                return row.label + "<" + (above === null ? "none" : above.item.label);
            }).join(", ");
        }
        function labelsOf(column) { return orderedRows(column).map(row => row.label).join(""); }

        function reorder_data() {
            return [{ tag: "bare rows", rows: reorderedBare }, { tag: "fields", rows: reorderedFields }];
        }

        // A Repeater that moves its rows changes no `children` of their
        // column: each row still stands under the row now above it, a row
        // under two that swap and a row that had no row above alike, and
        // the run logs no binding loop, which fails the file.
        function test_rows_follow_a_reorder_of_their_column_data() { return reorder_data(); }
        function test_rows_follow_a_reorder_of_their_column(data) {
            order.clear();
            for (const name of ["A", "B", "C"]) order.append({ name: name });
            const column = createTemporaryObject(data.rows, root);
            tryVerify(() => eachUnderTheOneBefore(column), 2000, "each row stands under the one before it: " + readOrder(column));
            const placed = orderedRows(column)[2].y;
            order.move(0, 1, 1);
            tryVerify(() => labelsOf(column) === "BAC", 2000, "the Repeater reorders its rows");
            tryVerify(() => eachUnderTheOneBefore(column), 2000, "a row under two that swap stands under the one now above it: " + readOrder(column));
            compare(orderedRows(column)[2].y, placed, "the row under the two that swap keeps its place");
            order.move(2, 0, 1);
            tryVerify(() => labelsOf(column) === "CBA", 2000, "the Repeater reorders its rows");
            tryVerify(() => eachUnderTheOneBefore(column), 2000, "a row that had no row above stands under the one moved above it: " + readOrder(column));
        }

        // A move, then a change the rows read: the first row takes a line
        // under it, which re-spaces the rows under it in their new order.
        function test_a_change_after_a_reorder_respaces_the_rows_data() { return reorder_data(); }
        function test_a_change_after_a_reorder_respaces_the_rows(data) {
            order.clear();
            for (const name of ["P", "X", "Y"]) order.append({ name: name });
            const column = createTemporaryObject(data.rows, root);
            tryVerify(() => eachUnderTheOneBefore(column), 2000, "each row stands under the one before it: " + readOrder(column));
            order.move(2, 1, 1);
            tryVerify(() => labelsOf(column) === "PYX", 2000, "the Repeater reorders its rows");
            tryVerify(() => eachUnderTheOneBefore(column), 2000, "each row stands under the one now above it: " + readOrder(column));
            const rows = orderedRows(column);
            const first = rows[0];
            const next = formRowOf(rows[1]);
            if (first.objectName === "fieldRow") first.warning = "Overridden by policy";
            else first.hint = "Overridden by policy";
            tryVerify(() => eachUnderTheOneBefore(column), 2000, "each row stands under the one before it: " + readOrder(column));
            const gap = () => next.mapToItem(column, 0, next.lineAbove()).y - first.mapToItem(column, 0, first.height - first.lineBelow()).y;
            tryVerify(() => Math.abs(gap() - Theme.stack.page) <= 1, 2000, "the row stands one step under the line: " + gap());
        }

        // The first row of ink in LABEL's box.
        function inkTop(img, label) {
            const at = label.mapToItem(root, 0, 0);
            for (let y = Math.floor(at.y); y < at.y + label.height; y++)
                for (let x = Math.floor(at.x); x < at.x + label.width; x++) if (inked(img, x, y)) return y;
            return -1;
        }

        // A text line counts from its capital top to its font's descent
        // line, so rows of text keep one pitch whatever their values and
        // hints hold: the labels' capitals stand as far apart under a hint
        // with descenders as under one without, and under a value with
        // descenders, tall glyphs or neither. Read by their glyphs, as
        // Section reads a heading's space, the labels stood 48 and 50 px
        // apart under the two hints and 30, 31 and 29 px under the values,
        // under scripts/qml-unit.sh on 732f0dae5: the controls in
        // scripts/test-qml-unit.sh.
        function test_text_rows_keep_one_pitch_whatever_they_read() {
            const cover = createTemporaryObject(coveredText, root);
            verify(cover !== null);
            verify(waitForRendering(cover));
            const img = grabImage(root);
            const labels = cover.rows.children.map(field => descendants(field).find(child => child.objectName === "fieldLabel"));
            const tops = labels.map(label => inkTop(img, label));
            verify(tops.every(top => top >= 0), "every label draws: " + tops.join(", "));
            const pitch = tops.slice(1).map((top, i) => top - tops[i]);
            compare(pitch[0], pitch[1], "under a hint with descenders as without: " + pitch.join(", "));
            verify(pitch.slice(2).every(step => step === pitch[2]), "under values with descenders, tall glyphs or neither: " + pitch.join(", "));
        }

        function segmentsOf(item) { return descendants(item).find(child => String(child).indexOf("SegmentedControl") === 0); }
        function fieldRowOf(item, label) { return descendants(item).find(child => child.objectName === "fieldRow" && child.label === label && child.visible); }

        // A grouped enum draws one segment per group. The stored value's
        // group is pressed, and under a group of several the second row,
        // labelled by `groupLabel`, chooses among them; under a group of
        // one no second row shows.
        function test_a_grouped_enum_draws_its_groups_as_segments() {
            const cover = createTemporaryObject(coveredGrouped, root);
            verify(cover !== null);
            const segments = segmentsOf(cover.grouped);
            compare(segments.model, ["Local", "Cloud"]);
            compare(segments.currentIndex, 0);
            compare(fieldRowOf(cover.grouped, "Cloud voice"), undefined, "a group of one draws no second row");
            cover.grouped.value = "gemini";
            compare(segments.currentIndex, 1);
            tryVerify(() => fieldRowOf(cover.grouped, "Cloud voice") !== undefined, 1000, "the group of several draws its row");
            const select = selectOf(fieldRowOf(cover.grouped, "Cloud voice"));
            compare(select.model.map(option => option.label), ["OpenAI Realtime", "Gemini Live", "ElevenLabs"]);
            compare(select.currentText, "Gemini Live");
        }

        // The second row stands `stack.page` under the segments by ink, and
        // the row under the field stands `stack.page` under the second row,
        // as every key/value row does (design-system § Layout). Held in a
        // Loader, the row stood 8 blank rows under the segments, its
        // column's spacing alone.
        function test_a_grouped_enums_second_row_stands_one_step_under_the_segments() {
            const cover = createTemporaryObject(coveredGrouped, root);
            cover.grouped.value = "realtime";
            tryVerify(() => fieldRowOf(cover.grouped, "Cloud voice") !== undefined, 1000);
            verify(waitForRendering(cover));
            const img = grabImage(root);
            const width = cover.rows.width;
            const gaps = [["Voice provider/Cloud voice", gapOver(img, fieldRowOf(cover.grouped, "Cloud voice"), width)], ["Cloud voice/After", gapOver(img, fieldRowOf(cover.after, "After"), width)]];
            const read = gaps.map(entry => entry.join(" ")).join(", ");
            for (const entry of gaps)
                verify(Math.abs(entry[1] - Theme.stack.page) <= 1, "each row stands " + Theme.stack.page + " blank rows under the one above: " + read);
        }

        // The text a reader sees: no character that draws nothing, and a
        // no-break hyphen read as the hyphen it draws.
        function seen(text) {
            return text.replace(/[\u200b-\u200d\u2060\ufeff]/g, "").replace(/\u2011/g, "-");
        }
        // The text before each hyphen of LABEL's text that ends a drawn
        // line while more of the word follows on the next one.
        function breaksAfterHyphen(label) {
            const twin = createTemporaryObject(layoutTwin, root, { width: label.width, wrapMode: label.wrapMode, font: label.font, text: label.text });
            compare(twin.lineCount, label.lineCount, "the twin lays the text out as the label does");
            const text = label.text;
            const broken = [];
            for (let i = 0; i < text.length; i++) {
                if (text[i] !== "-" && text[i] !== "\u2011") continue;
                let next = i + 1;
                while (next < text.length && /[\u200b-\u200d\u2060\ufeff]/.test(text[next])) next++;
                if (next >= text.length || text[next] === " ") continue;
                if (twin.positionToRectangle(next).y > twin.positionToRectangle(i).y) broken.push(seen(text.slice(Math.max(0, i - 12), i + 1)));
            }
            return broken;
        }
        function readsInFull(label, value, where) {
            compare(seen(label.text), value, where + " draws the whole value");
            compare(label.truncated, false, where + " elides the value");
            verify(label.lineCount > 1, where + " wraps a value wider than itself: " + label.lineCount + " line");
            compare(breaksAfterHyphen(label), [], where + " breaks no line after a hyphen");
        }

        // The long-value rows in a window on the screen at SCALE, which a
        // device-pixel font can lay out on other lines than at 1x.
        function longAt(scale) {
            const screen = Qt.application.screens[scale - 1];
            const window = createTemporaryObject(scaledWindow, null, { screen: screen, x: screen.virtualX + 10, y: screen.virtualY + 10 });
            window.visible = true;
            const cover = createTemporaryObject(coveredLong, window.contentItem);
            verify(cover !== null);
            compare(cover.Screen.devicePixelRatio, scale, "the rows draw at their screen's scale");
            return cover;
        }

        function test_a_long_value_reads_in_full_in_its_closed_select_data() {
            return [{ tag: "1x", scale: 1 }, { tag: "2x", scale: 2 }];
        }

        // A value too long for its select reads in full: the control
        // draws the whole value on as many lines as it needs and elides
        // nothing, its chevron and its row's label stay beside the first
        // line, a screen reader reads the plain value, and no line breaks
        // after a hyphen, where a reader would take the break for a space.
        function test_a_long_value_reads_in_full_in_its_closed_select(data) {
            const cover = longAt(data.scale);
            const select = selectOf(cover.long);
            const shown = select.contentItem;
            readsInFull(shown, root.longCodex, "the closed select");
            verify(shown.contentHeight <= shown.height + 0.5, "the control holds every line: " + shown.contentHeight + " in " + shown.height);
            compare(select.Accessible.name, root.longCodex, "a screen reader reads the plain value");
            const chevron = select.indicator.y + select.indicator.height / 2;
            fuzzyCompare(chevron, Theme.textField.height / 2, 1, "the chevron stands beside the first line");
            const label = labelOf(cover.long);
            const middle = label.mapToItem(select, 0, label.height / 2).y;
            verify(middle >= 0 && middle <= Theme.textField.height, "the label stands beside the value's first line: " + middle);
        }

        function test_a_long_value_reads_in_full_in_the_open_list_data() {
            return [{ tag: "1x", scale: 1 }, { tag: "2x", scale: 2 }];
        }

        // Each list entry too long for the list reads in full the same way.
        // The unit stand-in positions no window, so the test puts the
        // list's window on its select's screen.
        function test_a_long_value_reads_in_full_in_the_open_list(data) {
            const cover = longAt(data.scale);
            const select = selectOf(cover.long);
            const screen = Qt.application.screens[data.scale - 1];
            const window = selectListWindow(select);
            window.screen = screen;
            window.x = screen.virtualX + 10;
            window.y = screen.virtualY + 10;
            select.openList();
            const list = selectList(select);
            tryCompare(list.Screen, "devicePixelRatio", data.scale, 1000, "the list draws at its screen's scale");
            // The list's window lays its content out once it shows.
            tryVerify(() => list.width >= select.width - 2 * Theme.border.thin - 0.5, 1000, "the list is as wide as the control: " + list.width);
            for (const index of [1, 2]) {
                list.positionViewAtIndex(index, ListView.Contain);
                tryVerify(() => list.itemAtIndex(index) !== null, 1000, "the list builds entry " + index);
                const entry = list.itemAtIndex(index);
                const title = descendants(entry).find(child => child.role === "menuItem" && child.visible);
                const value = select.model[index].value;
                readsInFull(title, value, "entry " + index);
                verify(title.mapToItem(entry, 0, title.contentHeight).y <= entry.height + 0.5, "entry " + index + " holds every line");
                compare(entry.Accessible.name, value, "a screen reader reads entry " + index + "'s plain value");
            }
        }

        // The rows above and under a select that wraps stand `stack.page`
        // from it by ink, as every key/value row does (design-system §
        // Layout): the control grows the row, and the next row moves down.
        function test_rows_around_a_long_value_stand_one_step_apart_by_ink() {
            const cover = createTemporaryObject(coveredLong, root);
            verify(cover !== null);
            verify(selectOf(cover.long).contentItem.lineCount > 1, "the value wraps");
            verify(waitForRendering(cover));
            const img = grabImage(root);
            const width = cover.rows.width;
            const row = (field, label) => fieldRowOf(field, label);
            const gaps = [["Before/Review command", gapBetween(img, row(cover.before, "Before"), row(cover.long, "Review command"), width)], ["Review command/After", gapBetween(img, row(cover.long, "Review command"), row(cover.after, "After"), width)]];
            const read = gaps.map(entry => entry.join(" ")).join(", ");
            for (const entry of gaps)
                verify(Math.abs(entry[1] - Theme.stack.page) <= 1, "each row stands " + Theme.stack.page + " blank rows under the one above: " + read);
        }

        // Pressing the group of several while another group's value is
        // stored opens its list and stores nothing until a choice; a choice
        // stores it, and a list closed with no choice puts the stored
        // value's segment back. The group of one stores its option at once.
        function test_pressing_a_group_of_several_opens_its_list_and_stores_nothing() {
            const cover = createTemporaryObject(coveredGrouped, root);
            const segments = segmentsOf(cover.grouped);
            segments.activated(1);
            tryVerify(() => fieldRowOf(cover.grouped, "Cloud voice") !== undefined && selectOf(fieldRowOf(cover.grouped, "Cloud voice")).listOpen, 1000, "the Cloud voice list opens");
            const select = selectOf(fieldRowOf(cover.grouped, "Cloud voice"));
            compare(cover.written, [], "pressing Cloud stores nothing");
            compare(segments.currentIndex, 1, "Cloud reads pressed while its list is open");
            compare(select.currentIndex, -1, "no Cloud voice reads chosen");
            keyClick(Qt.Key_Escape);
            tryVerify(() => !select.listOpen, 1000);
            compare(cover.written, [], "a list closed with no choice stores nothing");
            tryCompare(segments, "currentIndex", 0, 1000, "the stored value's segment comes back");
            tryVerify(() => fieldRowOf(cover.grouped, "Cloud voice") === undefined, 1000, "the second row goes with it");
            segments.activated(1);
            tryVerify(() => selectOf(fieldRowOf(cover.grouped, "Cloud voice")).listOpen, 1000);
            selectOf(fieldRowOf(cover.grouped, "Cloud voice")).choose(1);
            compare(cover.written, ["gemini"], "a choice stores it");
            compare(segments.currentIndex, 1);
            segments.activated(0);
            compare(cover.written, ["gemini", "local"], "the group of one stores its option at once");
        }

        // An Add entry ends a status-fed select's list, led by the plus
        // mark; choosing it asks for the screen and stores nothing. A
        // preview field draws the entry action on each offer, never on the
        // Add entry, and pressing it plays that offer and stores nothing.
        function test_an_add_entry_ends_the_list_and_stores_nothing() {
            const offering = createTemporaryObject(offeringField, root);
            verify(offering !== null);
            const select = selectOf(offering);
            compare(select.model.map(entry => entry.label), ["OpenAI, key 1", "OpenAI, key 2", "Add a key"]);
            compare([select.iconAt(0), select.iconAt(2)], ["", "plus"]);
            compare([select.actionAt(0), select.actionAt(1), select.actionAt(2)], [true, true, false], "each offer plays; the Add entry does not");
            select.choose(2);
            compare([offering.adds, offering.written, select.currentIndex], [1, [], 0], "the Add entry asks for its screen, stores nothing and keeps the choice");
            select.entryActionActivated(1);
            compare([offering.previews, offering.written], [["k2"], []], "a preview plays its offer and stores nothing");
            select.choose(1);
            compare(offering.written, ["k2"], "an offer still stores itself");
        }

        // Play on the first voice, which stands for the unset voice, plays
        // that voice by its own id; an unavailable stored voice draws no
        // speaker.
        function test_a_preview_plays_the_offer_not_the_stored_value() {
            const field = createTemporaryObject(voiceField, root);
            verify(field !== null);
            const select = selectOf(field);
            compare([select.actionAt(0), select.actionAt(1), select.actionAt(2)], [true, true, false], "each offer plays; the unavailable voice does not");
            select.entryActionActivated(0);
            compare(field.previews, ["af_heart"], "the first offer plays its own voice");
        }

        // With no offer the list holds the Add entry alone, under the
        // field's placeholder.
        function test_an_add_entry_alone_under_the_placeholder() {
            const offering = createTemporaryObject(offeringField, root, { choices: [], value: "" });
            const select = selectOf(offering);
            compare(select.model.map(entry => entry.label), ["Add a key"]);
            verify(select.showsPlaceholder, "the placeholder reads while nothing is chosen");
            compare(select.currentText, "");
        }

        function test_a_status_choice_without_custom_reads_unavailable() {
            const select = selectOf(plainFed);
            compare(select.count, plainFed.choices.length, "no row follows the choices");
            compare(select.currentIndex, 2, "the configured value reads its unavailable row");
            compare(select.currentText, plainFed.choices[2].label);
            verify(!plainFed.customVisible, "no custom editor shows");
            compare(shownCustomText(plainFed), null);
        }
    }
}
