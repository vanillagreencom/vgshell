import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit
import "../../shell/plugins/vgs.settings"

Item {
    id: root
    width: 480
    height: 480

    property var applied: []

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

    TestCase {
        name: "settingfield"
        when: windowShown

        function init() {
            UnitTheme.reset();
            root.applied = [];
            field.value = "HH:mm";
            picked.value = "";
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

        function selectOf(item) {
            return descendants(item).find(child => String(child).indexOf("Select") === 0);
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
            compare(list.currentIndex, -1, "an unset choice opens with no entry highlighted");
            list.Window.window.requestActivate();
            list.forceActiveFocus();
            tryCompare(list.Window, "active", true);
            tryCompare(list, "activeFocus", true);
            keyClick(Qt.Key_Down);
            compare(list.currentIndex, 0, "Down moves to the first entry");
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
            compare(list.currentIndex, 2);
            Time.now = new Date(2026, 8, 30, 20, 35, 0);
            compare(list.currentIndex, 2, "a clock tick does not reset the highlighted preset");
            keyClick(Qt.Key_Return);
            tryCompare(select, "listOpen", false);
            compare(root.applied, ["yyyy-MM-dd HH:mm"]);
        }
    }
}
