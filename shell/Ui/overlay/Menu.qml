import QtQuick
import QtQuick.Effects
import Quickshell
import qs.Commons
import qs.Core
import qs.Ui

// A menu of MenuItem entries under the item it is declared in, in its own
// surface. One ListCursor draws the highlight and travels between entries,
// with every list's plate and accent text (ListItem.lit), on glass or not.
// `open` names its opener: a key opening highlights the checked entry,
// else the first reachable one; a pointer opening highlights none, and
// the first Up or Down then lands where a key opening would have. Up and
// Down move the highlight, a hover moves it once the pointer moves
// (ListCursor), and the pointer leaving the entries returns it to the
// entry a key chose, or clears it when no key chose one since the menu
// opened, as a desktop menu does. Enter triggers the highlighted entry and
// does nothing while none is highlighted, a
// click triggers an entry, and a trigger closes the menu unless the entry
// `keepsOpen`, as one that opens a submenu does; a press outside and
// Escape close it too (DismissScope). Typing letters highlights the first
// reachable entry whose text starts with them, the letters kept for
// `menu.typeahead` milliseconds. Entries taller than `maxHeight` scroll
// inside the menu: a key move keeps the highlighted entry in view, a hover
// scrolls nothing, and opening shows the top, and a key opening's
// highlighted entry in view. It follows its anchor when that
// moves and closes when it hides. The declaring item is an invisible,
// sizeless member of its parent. The entries fill the list inside the
// menu's border, so an entry's highlight meets the border at the top and
// both sides (Theme.menuListInset); each entry insets its own text, and
// keeps `scrollArea.gutter` clear at its end for the bar while the entries
// overflow. Under a rounded corner the list is cut to the window's rounded
// interior (ListMask), so an entry scrolled part way past an edge stays
// inside the curve. The menu's window and its content are built on its
// first open and kept after (`surface`); until then the entries wait,
// undrawn, in the declaring item, so `items()` answers from the start.
Item {
    id: root

    default property alias entries: column.data
    // The menu's PopupWindow, null until the first open. Built with the
    // menu, it cost a device list about 10 ms a row, each row holding an
    // overflow menu: 100 DeviceList rows took 1215-1341 ms with the window
    // built with each row and 105-126 ms with it built on the first open,
    // in qmltestrunner offscreen runs (VGS-1929, 2026-10-21).
    readonly property var surface: built.window
    readonly property bool opened: surface !== null && surface.visible
    readonly property Item anchorItem: parent
    property int currentIndex: -1
    // Whether a key chose the highlighted entry since the menu opened.
    property bool keyChose: false
    // Optional callback: the index a key opening highlights, for an owner
    // whose entries name their own first choice; unset, the checked
    // reachable entry, else the first reachable one.
    property var home: null
    // The height the entries take before the menu scrolls.
    property real maxHeight: Theme.menu.maxHeight
    readonly property string typed: nav.typed
    // The entries' ScrollArea and their one ListCursor, in the window, and
    // null until the first open.
    readonly property Item scrollArea: surface === null ? null : surface.scroll
    readonly property ListCursor plate: surface === null ? null : surface.plate
    readonly property AnchorTracker tracker: surface === null ? null : surface.tracker
    // The list's top and bottom inset inside the window; its side inset is
    // the border.
    readonly property real listInset: surface === null ? 0 : Theme.menuListInset(surface.width)

    visible: false

    property bool counted: false
    function share(open) {
        if (open === counted) return;
        counted = open;
        if (open) OverlayState.opened(); else OverlayState.closed();
    }
    Component.onDestruction: share(false)

    // The MenuItem children of the column, in order, and the ones the
    // keyboard may reach: enabled and shown.
    function items() { return column.children.filter(child => child.triggered !== undefined); }
    function reachable(item) { return item.enabled && item.visible; }

    // The entry a key opening highlights, and the first Up or Down from
    // none lands on: `home`'s answer, else the checked reachable entry,
    // else the first reachable one; -1 when none is reachable.
    function homeIndex() {
        if (home !== null) return home();
        const all = items();
        const checked = all.findIndex(item => reachable(item) && item.checked);
        return checked !== -1 ? checked : all.findIndex(item => reachable(item));
    }

    // Open the menu; `opener` is "key" or "pointer", the input that
    // opened it.
    function open(opener) {
        if (opener !== "key" && opener !== "pointer") throw new Error("menu-opener: " + opener + " is neither key nor pointer");
        if (surface === null) build();
        // Until now the entries stood under this undrawn item, where a
        // Column places no child; the window sizes from their places, so
        // they take them before it shows rather than on the next frame.
        // https://doc.qt.io/qt-6/qml-qtquick-column.html#forceLayout-method
        column.forceLayout();
        nav.typed = "";
        // The cursor lands on the opening entry rather than travelling
        // from where the last opening left it.
        plate.disarm();
        plate.snap();
        currentIndex = opener === "key" ? homeIndex() : -1;
        // The opening entry is the menu's, not a key's choice.
        keyChose = false;
        surface.visible = true;
        surface.scope.forceActiveFocus();
        scrollArea.contentY = 0;
        reveal();
    }
    // Escape's inherited DismissScope handler may already have hidden the
    // popup. Intentional closes still return native keys to the opener.
    function close(restore) {
        if (surface === null) return;
        const owner = restore && anchorItem !== null ? anchorItem.QsWindow.window : null;
        surface.visible = false;
        if (owner !== null && owner !== undefined) Compositor.activateWindow(owner);
    }
    function toggle(opener) { if (opened) close(); else open(opener); }

    // Move the highlight by `step` over the reachable entries, as Up and
    // Down do: from none, the first step lands on the home entry.
    function move(step) {
        if (currentIndex === -1) nav.moveTo(homeIndex());
        else nav.moveBy(step);
    }

    // Highlight the entry at `index` from a key: the pointer resting over
    // the menu takes the highlight again only once it moves.
    function keyTo(index) {
        if (plate !== null) plate.disarm();
        keyChose = true;
        currentIndex = index;
    }

    function triggerCurrent() {
        const all = items();
        if (currentIndex >= 0 && currentIndex < all.length && reachable(all[currentIndex])) all[currentIndex].triggered();
    }

    // Add `letter` to the typed letters and highlight the first reachable
    // entry whose text starts with them; when none does, start again from
    // `letter` alone. Answers whether an entry matched.
    function typeAhead(letter) {
        return nav.typeAhead(letter);
    }

    // Scroll the highlighted entry into view.
    function reveal() {
        const all = items();
        if (currentIndex < 0 || currentIndex >= all.length) return;
        nav.reveal(currentIndex);
    }

    // The widest entry by its own content, before the column sets every
    // entry's width, with the bar's strip while the entries pass
    // `maxHeight`. The strip is read from the entries' heights, not from
    // their `barRoom`: the list takes the window's size only after the
    // window shows and overflows until then. Read from `barRoom`, a menu
    // that fits opened a strip wider than it settled (scripts/qml-unit.sh,
    // 2026-10-10: 112 px, then 104).
    readonly property real widest: {
        let width = 0;
        for (const item of items()) width = Math.max(width, item.implicitWidth - item.barRoom);
        return width + (column.implicitHeight - root.maxHeight >= 0.5 ? Theme.scrollArea.gutter : 0);
    }

    // A hover changes the index too, so a change reveals nothing: a key
    // move reveals through KeyNav.moveTo and an opening through open(). A
    // reveal here would scroll a menu under a resting pointer, whose next
    // row then takes the hover, one row a frame (design-system.md § Pointer).
    onCurrentIndexChanged: items().forEach((item, index) => { item.highlighted = index === currentIndex; })

    property KeyNav nav: KeyNav {
        count: root.items().length
        currentIndex: root.currentIndex
        viewHeight: root.scrollArea === null ? 0 : root.scrollArea.height
        rowHeight: Theme.menu.item.height
        reachable: index => root.reachable(root.items()[index])
        labelAt: index => root.items()[index].text
        cursor: root.plate
        flickable: root.scrollArea
        itemAt: index => root.items()[index]
        onMoved: index => root.keyTo(index)
        onActivated: index => root.triggerCurrent()
    }

    // Every entry draws its highlight through the menu's cursor, and a
    // hover the cursor lets through highlights a reachable entry.
    readonly property Instantiator pointers: Instantiator {
        model: root.items()
        delegate: Connections {
            required property var modelData
            target: modelData
            Component.onCompleted: {
                modelData.cursor = Qt.binding(() => root.plate);
                modelData.barRoom = Qt.binding(() => root.scrollArea !== null && root.scrollArea.overflowing ? Theme.scrollArea.gutter : 0);
            }
            function onPointed() { if (root.reachable(modelData)) root.currentIndex = root.items().indexOf(modelData); }
        }
    }

    // An entry's trigger closes the menu, by click or by key, unless the
    // entry keeps it open for its owner to change the entries.
    readonly property Instantiator closers: Instantiator {
        model: root.opened ? root.items() : []
        delegate: Connections {
            required property var modelData
            target: modelData
            function onTriggered() { if (!modelData.keepsOpen) root.close(true); }
        }
    }

    // The entries until the first open, which moves them into the
    // window's list; this item draws nothing, so neither do they.
    Column {
        id: column
        width: root.scrollArea === null ? 0 : root.scrollArea.contentWidth
    }

    // The window the first open built.
    QtObject {
        id: built
        property var window: null
    }

    // Builds the window, which the menu owns from then. createObject
    // builds to completion before it returns, in any turn of the event
    // loop: https://doc.qt.io/qt-6/qml-qtqml-component.html#createObject-method
    // Quickshell's LazyLoader builds nothing until its own reload, which
    // a loader made after the shell loaded gets on the event loop's next
    // turn, and a bar widget makes its menu and opens it in one turn
    // (Quickshell 2b4501a, src/core/reload.cpp componentComplete and
    // src/core/lazyloader.cpp incubateIfReady).
    function build() {
        const window = windowComponent.createObject(root);
        if (window === null) throw new Error("menu-window: build failed");
        built.window = window;
    }

    Component {
        id: windowComponent

        PopupWindow {
            id: window

            readonly property alias scroll: scroll
            readonly property alias plate: plate
            readonly property alias scope: scope
            readonly property AnchorTracker tracker: AnchorTracker { popup: window; anchor: root.anchorItem }

            anchor.item: root.anchorItem
            anchor.edges: Edges.Bottom | Edges.Left
            anchor.gravity: Edges.Bottom | Edges.Right
            anchor.adjustment: PopupAdjustment.Flip | PopupAdjustment.Slide
            anchor.margins.bottom: -Theme.menu.gap
            grabFocus: true
            visible: false
            color: "transparent"
            // As wide as the widest entry, rounded up to the whole pixel the
            // window takes, never wider than `menu.maxWidth` or the output
            // allows; a longer entry elides.
            implicitWidth: Math.min(OverlayState.widthFor(root.anchorItem, Theme.menu.maxWidth), Math.max(Theme.menu.minWidth, Math.ceil(root.widest) + 2 * Theme.border.thin))
            implicitHeight: Math.max(1, Math.min(column.implicitHeight, root.maxHeight) + 2 * root.listInset)
            onVisibleChanged: root.share(visible)
            // The open that builds the window shows it before Quickshell
            // makes its backing window, on the next turn of the event loop,
            // so that open's focus finds no window; the list takes the keys
            // once the backing window holds it. windowConnected:
            // https://quickshell.org/docs/v0.3.1/types/Quickshell/QsWindow/
            onWindowConnected: scope.forceActiveFocus()

            DismissScope {
                id: scope
                popup: window
                anchor: root.anchorItem
                Keys.onEscapePressed: root.close(true)
                Keys.onTabPressed: event => event.accepted = true
                Keys.onBacktabPressed: event => event.accepted = true
                Keys.onPressed: event => {
                    const action = KeyNavLogic.intent(event.key, event.modifiers, nav.orientation, false);
                    if (root.currentIndex === -1 && (action === "prev" || action === "next")) event.accepted = nav.moveTo(root.homeIndex(), true);
                    else event.accepted = nav.handle(event);
                }

                GlassSurface {
                    anchors.fill: parent
                    standard: Theme.menu
                    elevation: "tight"
                }

                // The entries span the list inside the border; the bar draws
                // over the strip each entry keeps clear at its end. Under a
                // rounded corner the list is cut to the curve of the interior.
                ScrollArea {
                    id: scroll
                    x: Theme.border.thin
                    y: root.listInset
                    width: parent.width - 2 * Theme.border.thin
                    height: parent.height - 2 * root.listInset
                    barOverContent: true
                    layer.enabled: listMask.cuts
                    layer.smooth: true
                    layer.effect: MultiEffect {
                        maskEnabled: true
                        maskSource: listMask
                        maskThresholdMin: 0.5
                        maskSpreadAtMin: 1
                    }

                    ListCursor {
                        id: plate
                        radius: Theme.menu.item.radius
                        onPointerLeft: if (!root.keyChose) root.currentIndex = -1
                    }

                    Component.onCompleted: column.parent = scroll.contentItem
                }

                ListMask {
                    id: listMask
                    anchors.fill: scroll
                    frameWidth: window.width
                    frameHeight: window.height
                }
            }
        }
    }
}
