import QtQuick
import QtTest
import qs.Ui
import qs.Unit
import "../../shell/plugins/vgs.settings"

// Removing an item of a Settings list field (ListField) on a scrolled page,
// by pointer or key, keeps the page where it is and hands the keyboard to
// the Remove of the item that takes the removed one's place, else of the
// one above it, else to Add.
Item {
    id: root
    width: 700
    height: 400

    function itemsOf(count) {
        const out = [];
        for (let i = 1; i <= count; i++) out.push({ name: String(i), account: "account " + i });
        return out;
    }

    ScrollArea {
        id: page
        width: 600
        height: 300

        // A Settings page's rows sit in TabPages, a focus scope as tall as
        // the page.
        FocusScope {
            width: page.contentWidth
            height: rows.height

            Column {
                id: rows
                width: parent.width
                Item { width: 1; height: 200 }
                ListField {
                    id: list
                    key: "hidden"
                    spec: ({ type: "list", label: "Hidden accounts", items: { account: { type: "string", label: "Account" } }, defaults: { account: "" } })
                    // The page's write lands as a plain list, as the
                    // manager's does; the signal hands over an array-like.
                    onApply: v => list.value = Array.from(v)
                }
                Item { width: 1; height: 400 }
            }
        }
    }

    UnitCase {
        name: "listfield_remove"
        when: windowShown

        function removeOf(name) {
            const found = [list];
            for (let i = 0; i < found.length; i++) {
                const item = found[i];
                if (item.removesItem === true && item.parent.modelData.name === name) return item;
                for (const child of item.children) found.push(child);
            }
            return null;
        }

        function addAction() {
            const found = [list];
            for (let i = 0; i < found.length; i++) {
                const item = found[i];
                if (item.text === "Add" && item.removesItem === false) return item;
                for (const child of item.children) found.push(child);
            }
            return null;
        }

        function test_removing_an_item_keeps_the_place_and_the_keyboard_beside_it_data() {
            return [
                { tag: "pointer, an item in the middle", count: 12, remove: "6", next: "7", key: false },
                { tag: "key, an item in the middle", count: 12, remove: "6", next: "7", key: true },
                { tag: "key, the last item", count: 12, remove: "12", next: "11", key: true },
                { tag: "key, the only item", count: 1, remove: "1", next: "", key: true }
            ];
        }

        function test_removing_an_item_keeps_the_place_and_the_keyboard_beside_it(data) {
            list.value = root.itemsOf(data.count);
            page.contentY = 0;
            // The rows' Column places them in the window's polish.
            verify(renderedFrame(page), "the page draws its items");
            const target = removeOf(data.remove);
            verify(target !== null, "the item's Remove is drawn");
            page.contentY = Math.max(0, Math.min(page.contentHeight - page.height, target.mapToItem(page.contentItem, 0, 0).y - page.height / 2));
            const place = page.contentY;
            verify(place > 0, "the page is scrolled");
            if (data.key) {
                target.forceActiveFocus(Qt.TabFocusReason);
                keyClick(Qt.Key_Space);
            } else {
                mouseClick(target);
            }
            compare(list.items.length, data.count - 1);
            compare(removeOf(data.remove), null, "the item is gone");
            verify(renderedFrame(page), "the page draws the shorter list");
            compare(page.contentY, place, "the page stays where it was");
            const neighbour = data.next === "" ? addAction() : removeOf(data.next);
            verify(neighbour.activeFocus, "the keyboard lands beside the removed item");
        }
    }
}
