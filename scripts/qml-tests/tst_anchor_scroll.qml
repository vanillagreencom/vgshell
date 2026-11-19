import QtQuick
import QtTest
import qs.Ui
import qs.Unit

// An open Select's list while its page scrolls: a scroll that leaves part
// of the field in view keeps the list open and moves its anchor with the
// field, and a scroll that takes the whole field out of the page's view
// closes the list. The nested sandbox proves the compositor's placement.
Item {
    id: root
    width: 300
    height: 240

    ScrollArea {
        id: page
        width: 300
        height: 120

        Column {
            width: page.width
            Item { width: 1; height: 40 }
            Select { id: select; model: ["Average", "Most left", "Most used"] }
            Item { width: 1; height: 400 }
        }
    }

    UnitCase {
        name: "anchor_scroll"
        when: windowShown

        // The Select's popup window, the one resource with an anchor.
        function listWindow() {
            for (let i = 0; i < select.resources.length; i++)
                if (select.resources[i].anchor !== undefined) return select.resources[i];
            return null;
        }

        function init() {
            page.contentY = 0;
            select.openList();
            verify(select.listOpen, "the list opens");
        }

        function cleanup() {
            listWindow().visible = false;
        }

        function test_a_scroll_that_leaves_part_of_the_field_in_view_keeps_the_list_on_it() {
            const window = listWindow();
            const updates = window.anchor.updates;
            // The field's top half lies above the page's top edge.
            page.contentY = 40 + select.height / 2;
            verify(select.listOpen, "the list stays open while part of its field shows");
            verify(window.anchor.updates > updates, "the list's anchor moves with the field");
        }

        function test_a_scroll_that_takes_the_field_out_of_view_closes_the_list() {
            page.contentY = 40 + select.height + 10;
            compare(select.listOpen, false, "the list closes once its field is out of view");
        }
    }
}
