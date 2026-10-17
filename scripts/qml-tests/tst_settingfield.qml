import QtQuick
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

        function selectList(owner) {
            let window = null;
            for (let i = 0; i < owner.resources.length; i++)
                if (owner.resources[i].anchor !== undefined) window = owner.resources[i];
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
            compare(shownCustomText(customFed), "b", "the editor holds the configured value");
            compare(root.applied, [], "choosing Custom… writes nothing");
            compare(select.currentIndex, 1, "an offered value keeps its own row");
            customFed.value = "";
            verify(!customFed.customVisible, "a write of an offered value closes the custom editor");
            select.choose(customFed.choices.length);
            select.choose(1);
            verify(!customFed.customVisible, "choosing an offer closes the custom editor");
            compare(root.applied, ["b"], "choosing an offer writes its value");
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
                verify(tip.opened, "the explainer opens its own surface");
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
            verify(longLabel.height >= label.implicitHeight, "the row holds every line");
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
