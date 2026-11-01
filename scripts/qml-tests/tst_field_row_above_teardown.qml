import QtQuick
import QtTest
import qs.Commons
import qs.Core
import qs.Ui
import qs.Unit

// A Field under a key/value row that QML has begun to destroy. QML marks an
// item and its QObject children deleted before the item leaves its parent,
// so for that moment the row is still the Field's row above while every
// property it has reads as undefined. A value the Field's top padding reads
// moves in that moment here as on a Settings page: a SettingField leaving
// with the row tells the page's set of unsaved edits (EditSet.forget), and
// the planted set moves the page step. The Field then stands under no row
// and logs nothing, where reading the marked SettingField's children logged
// `Field.qml:163: TypeError: Value is undefined and could not be converted
// to an object` (the control in scripts/test-qml-unit.sh). A group list
// that ends a live row and is marked the same way is left out of the row's
// measure, as a hidden group is. A bare FormRow measures the space above it
// by the same search (FormRow `rowAbove`, `inkTop`), so under a marked
// setting or a marked bare row it too stands under no row.
Item {
    id: root
    width: 600
    height: 800

    // The page's set of unsaved edits as the leaving SettingField tells it:
    // telling it moves the page step, and it records what the Field below
    // reads at that moment.
    QtObject {
        id: edits
        property var below: null
        property var seen: null
        function track() {}
        function forget() {
            if (below === null) return;
            UnitTheme.override({ stack: { page: Theme.stack.page + 7 } });
            const row = root.rowOf(below);
            seen = { item: row.rowAbove === null ? null : row.rowAbove.item, top: row.inkTop };
        }
    }

    // The FormRow that measures ITEM's space above it: the item, or a
    // Field's row.
    function rowOf(item) {
        return item.objectName === "fieldRow" ? item : item.children.find(child => child.objectName === "fieldRow");
    }

    // Owns the rows the test marks, apart from the column that draws them,
    // so they are marked while that column still holds them.
    Component { id: owner; Item {} }
    Component { id: setting; SettingField { key: "k"; spec: ({ type: "boolean", label: "Key" }); value: true } }
    Component {
        id: plainRow
        Column {
            readonly property bool keyValueRow: true
            Rectangle { width: 100; height: 20 }
        }
    }
    Component { id: groups; GroupList { Rectangle { width: 100; height: 20 } } }
    Component { id: bareRow; FormRow { label: "Bare"; width: parent === null ? 0 : parent.width; Label { role: "item"; text: "Ready" } } }
    Component { id: field; Field { label: "Below"; inline: true; width: parent === null ? 0 : parent.width; Label { role: "item"; text: "Ready" } } }

    Rectangle {
        anchors.fill: parent
        color: Theme.color.surface
    }

    Column { id: host; width: 400 }

    TestCase {
        name: "field_row_above_teardown"
        when: windowShown

        function init() {
            UnitTheme.reset();
            edits.below = null;
            edits.seen = null;
        }
        function cleanup() { UnitTheme.reset(); }

        // The SettingField that tells the edits goes first among the
        // owner's children: QML marks the last child first, so the row is
        // already marked when the teller's destruction handler runs.
        function test_a_marked_setting_above_is_no_row() {
            const doomed = owner.createObject(root);
            setting.createObject(doomed, { edits: edits });
            const row = setting.createObject(doomed, { edits: null });
            row.parent = host;
            row.width = host.width;
            const below = createTemporaryObject(field, host);
            tryVerify(() => root.rowOf(below).rowAbove !== null && root.rowOf(below).rowAbove.item === row, 2000, "the setting is the field's row above");
            edits.below = below;
            doomed.destroy();
            tryVerify(() => edits.seen !== null, 2000, "the leaving setting tells the edits");
            verify(edits.seen.item === row, "the marked setting is still the row above while the page step moves");
            compare(edits.seen.top, 0, "a field under a marked row stands under no row");
            tryCompare(root.rowOf(below), "rowAbove", null, 2000);
            compare(below.topPadding, 0);
        }

        function test_b_marked_group_list_in_a_live_row_is_out_of_its_measure() {
            const doomed = owner.createObject(root);
            setting.createObject(doomed, { edits: edits });
            const row = createTemporaryObject(plainRow, host, { width: host.width });
            const list = groups.createObject(doomed);
            list.parent = row;
            const below = createTemporaryObject(field, host);
            tryVerify(() => root.rowOf(below).rowAbove !== null && root.rowOf(below).rowAbove.item === row, 2000, "the row is the field's row above");
            edits.below = below;
            doomed.destroy();
            tryVerify(() => edits.seen !== null, 2000, "the leaving setting tells the edits");
            verify(edits.seen.item === row);
            tryVerify(() => row.children.length === 1, 2000, "the list leaves the row");
            compare(edits.seen.top, below.topPadding, "the marked list is measured as gone");
        }

        // A bare FormRow under a marked setting, whose children read as
        // undefined, or under a marked bare row, whose lines read as none.
        function test_c_a_marked_row_above_a_bare_row_is_no_row_data() {
            return [{ tag: "setting", above: setting }, { tag: "bare row", above: bareRow }];
        }

        function test_c_a_marked_row_above_a_bare_row_is_no_row(data) {
            const doomed = owner.createObject(root);
            setting.createObject(doomed, { edits: edits });
            const row = data.above.createObject(doomed, data.above === setting ? { edits: null } : {});
            row.parent = host;
            row.width = host.width;
            const below = createTemporaryObject(bareRow, host);
            tryVerify(() => below.rowAbove !== null && below.rowAbove.item === row, 2000, "the row is the bare row's row above");
            verify(below.inkTop !== 0, "the bare row stands by ink under a live row");
            edits.below = below;
            doomed.destroy();
            tryVerify(() => edits.seen !== null, 2000, "the leaving setting tells the edits");
            verify(edits.seen.item === row, "the marked row is still the row above while the page step moves");
            compare(edits.seen.top, 0, "a bare row under a marked row stands under no row");
            tryCompare(below, "rowAbove", null, 2000);
            compare(below.shift, 0);
        }
    }
}
