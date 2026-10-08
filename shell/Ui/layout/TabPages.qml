import QtQuick
import qs.Commons
import qs.Ui

// Pages under one tab strip. `model` lists the tab texts, one per page;
// the items declared inside are the pages, in that order; `currentIndex`
// is the page shown. Each page takes the component's width and only the
// shown one is visible, so Tab from the strip enters that page alone and
// Shift+Tab returns. The height is the strip, `spacing` and the shown
// page; `spacing` is `stack.page`, since tab pages are a window's pages.
// Left and Right on the strip change the page, and Ctrl+Tab,
// Ctrl+Shift+Tab, Ctrl+PageDown and Ctrl+PageUp step it, round the ends,
// from the strip and from a control of the shown page that leaves the
// key: a ShortcutField that captures takes it as the combo, and an open
// list or menu holds the keyboard in its own surface. A hidden item
// keeps the keyboard it holds, so when the page that hides holds it the
// strip takes it with the current Qt focus reason. Keyboard page keys
// give the strip a Tab reason.
FocusScope {
    id: root

    property alias model: strip.model
    property alias currentIndex: strip.currentIndex
    default property alias pages: stack.data
    property real spacing: Theme.stack.page
    readonly property int count: stack.children.length
    readonly property Item currentPage: currentIndex >= 0 && currentIndex < count ? stack.children[currentIndex] : null
    readonly property alias tabs: strip

    implicitWidth: Math.max(strip.implicitWidth, currentPage === null ? 0 : currentPage.implicitWidth)
    implicitHeight: strip.height + (currentPage === null ? 0 : spacing + currentPage.height)

    function show() {
        for (let i = 0; i < stack.children.length; i++) stack.children[i].visible = i === currentIndex;
    }

    onCurrentIndexChanged: {
        // The scope's focus is the strip's or a page's, and a page's is in
        // the page that hides. The first tab's arrival sets the index, so
        // the strip is the scope's focus from the start.
        if (!strip.focus) {
            if (root.activeFocus) {
                let focused = root.Window.activeFocusItem;
                while (focused !== null && !("focusReason" in focused)) focused = focused.parent;
                const reason = focused === null ? Qt.OtherFocusReason : focused.focusReason;
                strip.forceActiveFocus(reason);
                strip.focusReason = reason;
            }
            else strip.focus = true;
        }
        show();
    }

    // The tab keys a control of the shown page leaves: the strip steps
    // for them as it does for its own.
    Keys.onPressed: event => {
        const action = KeyNavLogic.intent(event.key, event.modifiers, "horizontal", false);
        if (action === "tabPrev" || action === "tabNext") {
            event.accepted = strip.nav.handle(event);
            if (event.accepted && root.activeFocus) {
                strip.forceActiveFocus(Qt.TabFocusReason);
                strip.focusReason = Qt.TabFocusReason;
            }
        }
    }

    Tabs {
        id: strip
        width: root.width
    }

    Item {
        id: stack
        y: strip.height + root.spacing
        width: root.width
        height: root.currentPage === null ? 0 : root.currentPage.height
        onChildrenChanged: {
            for (const page of children) page.width = Qt.binding(() => stack.width);
            root.show();
        }
    }
}
