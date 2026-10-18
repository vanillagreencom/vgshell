import QtQuick
import QtTest
import qs.Commons
import qs.Core
import qs.Ui
import qs.Unit
import "../../shell/plugins/vgs.settings"

// A Settings list field (ListField): each item shows its declared fields
// and its Remove, the trash mark alone, and never its storage key, the
// `name` the field writes for it. Remove sends the list without that item,
// stands `stack.inline` after the first field's value and centres on it,
// and its trash ink ends where a flat setting's select beside the list
// ends, whether that value fills the value column or stops at its widest.
// Add still keys a new item by the lowest whole number no item names, and
// the list it sends is one the manager's judge accepts and writes as a list.
Item {
    id: root
    width: 1100
    height: 800

    property var writes: []
    property var refusals: []
    property var written: []

    // The plugin the field belongs to, as the manager's judge reads it.
    function manifest() {
        return {
            id: "acme.unit",
            schema: {
                pairs: {
                    type: "list",
                    label: "Pairs",
                    items: {
                        kind: { type: "string", label: "Kind", presets: [{ value: "a", label: "Alpha" }, { value: "b", label: "Beta" }] },
                        wide: { type: "boolean", label: "Wide" }
                    },
                    defaults: { kind: "a", wide: false }
                }
            }
        };
    }

    ListField {
        id: list
        width: 480
        pluginId: "acme.unit"
        key: "pairs"
        spec: root.manifest().schema.pairs
        value: [{ name: "7", kind: "a", wide: false }, { name: "9", kind: "b", wide: true }]
        // Plugins.writeSetting judges the value the page relays from this
        // signal with PluginLogic.settingRefusal before it writes it with
        // PluginLogic.withSetting.
        onApply: v => {
            root.writes = root.writes.concat([v]);
            root.refusals = root.refusals.concat([PluginLogic.settingRefusal(root.manifest(), "pairs", v)]);
            root.written = root.written.concat([Array.isArray(PluginLogic.withSetting({}, root.manifest(), "pairs", v, {}).plugins[0].pairs)]);
        }
    }

    // A flat setting as wide as the list, as the page draws one beside it:
    // its select ends on the page's control edge.
    SettingField {
        id: flat
        y: 600
        width: list.width
        key: "sort"
        spec: ({ type: "string", label: "Sort", presets: [{ value: "a", label: "Alpha" }] })
        value: "a"
    }

    TestCase {
        name: "listfield"
        when: windowShown

        function init() {
            UnitTheme.reset();
            root.writes = [];
            root.refusals = [];
            root.written = [];
            list.width = 480;
            list.value = [{ name: "7", kind: "a", wide: false }, { name: "9", kind: "b", wide: true }];
        }

        function descendants(item) {
            const found = [item];
            for (let i = 0; i < found.length; i++)
                for (const child of found[i].children || []) found.push(child);
            return found;
        }
        function shown(item) {
            for (let at = item; at !== null; at = at.parent) if (!at.visible) return false;
            return true;
        }
        function groups() {
            return descendants(list).filter(child => child.modelData !== undefined && child.modelData !== null && typeof child.modelData === "object" && typeof child.modelData.name === "string" && child.index !== undefined)
                .sort((a, b) => a.index - b.index);
        }
        function removes(group) { return descendants(group).filter(child => child instanceof RowAction && child.removesItem && shown(child)); }
        function fields(group) { return descendants(group).filter(child => child instanceof SettingField && shown(child)); }
        function select(item) { return descendants(item).find(child => child instanceof Select && shown(child)); }
        function box(item) {
            const at = item.mapToItem(root, 0, 0);
            return { x: at.x, y: at.y, right: at.x + item.width, centre: at.y + item.height / 2 };
        }

        function test_an_item_draws_its_fields_and_remove_and_no_storage_key() {
            tryCompare(groups(), "length", 2);
            for (const group of groups()) {
                compare(fields(group).map(field => field.key), ["kind", "wide"], "item " + group.modelData.name + " draws its declared fields");
                compare(removes(group).length, 1, "item " + group.modelData.name + " draws one Remove");
                const texts = descendants(group).filter(child => child instanceof Label && shown(child)).map(label => label.text);
                compare(texts.filter(text => text.toLowerCase() === "name"), [], "item " + group.modelData.name + " draws no Name label");
                compare(texts.filter(text => text === "7" || text === "9"), [], "item " + group.modelData.name + " draws no storage key");
            }
        }

        function test_remove_sends_the_list_without_its_item() {
            tryCompare(groups(), "length", 2);
            const remove = removes(groups()[1])[0];
            compare(remove.Accessible.name, "Remove");
            mouseClick(remove);
            compare(root.writes.length, 1);
            compare(root.writes[0], [{ name: "7", kind: "a", wide: false }]);
        }

        function test_remove_stands_after_the_first_value_and_centres_on_it_data() {
            return [{ tag: "a value that fills the column", width: 480 }, { tag: "a value at its widest", width: 1000 }];
        }
        function test_remove_stands_after_the_first_value_and_centres_on_it(data) {
            list.width = data.width;
            tryCompare(groups(), "length", 2);
            for (const group of groups()) {
                const value = select(fields(group)[0]);
                verify(value !== undefined, "the first field draws its select");
                const remove = removes(group)[0];
                tryVerify(() => Math.abs(box(remove).x - (box(value).right + Theme.stack.inline)) < 0.5, 1000,
                          "Remove starts at " + box(remove).x + ", the value ends at " + box(value).right);
                verify(Math.abs(box(remove).centre - box(value).centre) <= 1, "Remove centres at " + box(remove).centre + ", the value at " + box(value).centre);
                const mark = descendants(remove).find(child => child instanceof Icon && shown(child));
                const inkEnd = box(mark).x + mark.painted[2];
                const edge = box(select(flat)).right;
                verify(Math.abs(inkEnd - edge) < 0.5, "the trash ink ends at " + inkEnd + ", a flat select at " + edge);
            }
        }

        function test_add_keys_the_new_item_by_the_lowest_free_number() {
            list.value = [{ name: "1", kind: "a", wide: false }, { name: "3", kind: "b", wide: true }];
            tryCompare(groups(), "length", 2);
            const add = descendants(list).find(child => child instanceof RowAction && child.text === "Add");
            mouseClick(add);
            compare(root.writes.length, 1);
            compare(root.writes[0][2], { name: "2", kind: "a", wide: false });
        }

        function test_add_sends_a_list_the_manager_judge_accepts() {
            tryCompare(groups(), "length", 2);
            const add = descendants(list).find(child => child instanceof RowAction && child.text === "Add");
            mouseClick(add);
            compare(root.refusals, [""]);
            compare(root.written, [true], "the manager writes a list");
        }
    }
}
