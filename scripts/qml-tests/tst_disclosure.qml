import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit

// Disclosure: it starts with its content hidden and adds no height for it;
// a click on its row, or Space on the focused row, shows the content under
// the row and turns the chevron up, and a second click hides it again; a
// click on a control among its trailing items reaches that control and
// toggles nothing; a row that cannot expand draws no chevron, keeps no
// chevron room, and a click on it shows nothing.
Item {
    id: root
    width: 400
    height: 400

    Disclosure {
        id: disclosure
        width: 300
        text: "System"
        secondary: "2 updates"
        iconName: "package"
        trailing: [
            Button { id: action; text: "Update"; size: "sm"; anchors.verticalCenter: parent.verticalCenter }
        ]
        Label { id: line; role: "code"; text: "linux 6.1 → 6.2" }
    }
    SignalSpy { id: actions; target: action; signalName: "clicked" }

    TestCase {
        name: "disclosure"
        when: windowShown

        // The row is the first child; the chevron is the last item its
        // trailing row holds.
        function row() { return disclosure.children[0]; }
        function chevron() {
            const items = row().contentItem.children[2].children;
            return items[items.length - 1];
        }

        function init() {
            UnitTheme.reset();
            disclosure.expanded = false;
            disclosure.expandable = true;
            actions.clear();
        }

        function test_starts_hidden() {
            compare(disclosure.expanded, false);
            verify(!line.visible, "the content shows before a click");
            tryCompare(disclosure, "height", row().height);
            compare(chevron().name, "chevron-down");
        }

        function test_a_click_on_the_row_toggles_the_content() {
            mouseClick(row(), 20, row().height / 2);
            compare(disclosure.expanded, true);
            verify(line.visible, "the content is hidden after a click");
            tryCompare(disclosure, "height", row().height + line.height);
            compare(chevron().name, "chevron-up");
            verify(line.mapToItem(disclosure, 0, 0).y >= row().height, "the content sits over the row");
            mouseClick(row(), 20, row().height / 2);
            compare(disclosure.expanded, false);
            tryCompare(disclosure, "height", row().height);
        }

        function test_space_toggles_the_content() {
            row().forceActiveFocus();
            keyClick(Qt.Key_Space);
            compare(disclosure.expanded, true);
        }

        function test_return_enter_and_arrows_drive_the_disclosure() {
            compare(disclosure.focusItem, row());
            row().forceActiveFocus();
            keyClick(Qt.Key_Return);
            compare(disclosure.expanded, true);
            keyClick(Qt.Key_Left);
            compare(disclosure.expanded, false);
            keyClick(Qt.Key_Right);
            compare(disclosure.expanded, true);
            disclosure.expanded = false;
            keyClick(Qt.Key_Enter);
            compare(disclosure.expanded, true);
        }

        function test_a_row_that_cannot_expand_stays_closed() {
            disclosure.expandable = false;
            compare(chevron().visible, false, "a row that cannot expand draws its chevron");
            mouseClick(row(), 20, row().height / 2);
            compare(disclosure.expanded, false);
            verify(!line.visible, "a row that cannot expand shows its content");
        }

        function test_non_expandable_trailing_item_ends_on_the_row_edge() {
            const closed = Qt.createQmlObject('import QtQuick\nimport qs.Ui\nDisclosure { width: 300; text: "Status"; expandable: false; trailing: [ Badge { text: "ready"; anchors.verticalCenter: parent.verticalCenter } ] }', root, "closedDisclosure");
            const open = Qt.createQmlObject('import QtQuick\nimport qs.Ui\nDisclosure { width: 300; text: "Status"; trailing: [ Badge { text: "ready"; anchors.verticalCenter: parent.verticalCenter } ] }', root, "openDisclosure");
            const closedRow = closed.children[0];
            const openRow = open.children[0];
            const closedBadge = closedRow.contentItem.children[2].children[0];
            const openChevron = openRow.contentItem.children[2].children[1];
            compare(closedBadge.mapToItem(closedRow, closedBadge.width, 0).x, closedRow.width - closedRow.rightPadding);
            compare(openChevron.mapToItem(openRow, openChevron.width, 0).x, openRow.width - openRow.rightPadding);
            closed.destroy();
            open.destroy();
        }

        function test_list_item_ignores_a_hidden_trailing_button() {
            const item = Qt.createQmlObject('import QtQuick\nimport qs.Ui\nListItem { width: 300; text: "Status"; trailing: [ Badge { text: "ready"; anchors.verticalCenter: parent.verticalCenter }, Button { text: "Hidden"; visible: false; anchors.verticalCenter: parent.verticalCenter } ] }', root, "hiddenButtonRow");
            const badge = item.contentItem.children[2].children[0];
            compare(badge.mapToItem(item, badge.width, 0).x, item.width - item.rightPadding);
            item.destroy();
        }

        function test_a_trailing_control_takes_its_own_click() {
            mouseClick(action);
            compare(actions.count, 1);
            compare(disclosure.expanded, false);
        }
    }
}
