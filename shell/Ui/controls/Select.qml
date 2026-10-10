import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Templates as T
import Quickshell
import qs.Commons
import qs.Ui

// A dropdown choice. `model` is a list of strings, or of objects with
// `textRole` naming the text; `currentIndex` is the choice. A click, Space
// or Enter opens the list in its own surface under the control; Up and
// Down move the highlight there and Enter chooses, a click chooses, and a
// press outside or Escape closes it (DismissScope). One ListCursor draws the highlight
// and travels between entries, and a hover moves it once the pointer moves
// (ListCursor). With the list closed, Up and Down on the focused control
// move the choice. The list opens on the control's edges, as wide as it,
// and its entries fill it inside the menu's border, so a highlight or the
// chosen entry's fill meets the border at the top and both sides
// (Theme.menuListInset); an entry's side padding is the control's less
// that border, so its text starts where the control's does. A list taller
// than `menu.maxHeight` scrolls under the module's embedded bar, which
// draws over the strip each entry keeps clear at its end while the bar
// shows. Under a rounded corner the list is cut to the window's rounded
// interior (ListMask), so a row scrolled part way past an edge stays inside
// the curve. The control draws like a text field; the template owns its
// click, hover and focus. With nothing to choose the list never opens, so
// no popup repeats what the closed control says, and nothing promises it
// will: the pointer stays the arrow and the chevron draws in the disabled
// text colour. With `emptyText` set, the control reads that text dimmed.
// With entries to choose,
// none chosen (`currentIndex` outside the model) and `placeholderText` set,
// the control reads that text dimmed, and the list opens with no entry
// highlighted; Down then moves to the first entry.
T.AbstractButton {
    id: root

    readonly property real minimumWidth: Theme.field.minWidth
    readonly property real maximumWidth: Theme.control.maxWidth
    Layout.minimumWidth: minimumWidth
    Layout.maximumWidth: maximumWidth
    width: Math.max(minimumWidth, Math.min(maximumWidth, implicitWidth))
    InputWidth { target: root }

    property var model: []
    property int currentIndex: 0
    property string textRole: ""
    readonly property int count: Array.isArray(model) ? model.length : 0
    readonly property bool opens: count > 0
    readonly property string currentText: textAt(currentIndex)
    readonly property bool listOpen: list.visible
    property bool counted: false
    readonly property string typed: closedNav.typed
    property string emptyText: ""
    readonly property bool showsEmpty: count === 0 && emptyText !== ""
    property string placeholderText: ""
    readonly property bool showsPlaceholder: count > 0 && !(currentIndex >= 0 && currentIndex < count) && placeholderText !== ""
    // A user choice only. Model and binding updates never emit this.
    signal activated(int index)
    // The list opened, so an owner can refresh the model it shows.
    signal opened()

    function share(open) {
        if (open === counted) return;
        counted = open;
        if (open) OverlayState.opened(); else OverlayState.closed();
    }
    Component.onDestruction: share(false)
    readonly property color outline: focusRing.visible || list.visible ? Theme.textField.focus : hovered ? Theme.textField.hover : Theme.textField.borderColor
    readonly property real sidePadding: Theme.controlPadding(Theme.textField.paddingX, Theme.textField.radius, Math.max(Theme.textField.height, height), implicitContentHeight)
    // The list's top and bottom inset inside its window; its side inset is
    // the border.
    readonly property real listInset: Theme.menuListInset(list.width)

    function textAt(index) {
        if (index < 0 || index >= count) return "";
        const entry = model[index];
        if (textRole !== "" && entry !== null && typeof entry === "object") return String(entry[textRole]);
        return String(entry);
    }

    // Choose the entry at `index` and close the list. Choosing the current
    // entry assigns nothing, so a binding on `currentIndex` survives it.
    function choose(index) {
        if (index < 0 || index >= count) return;
        if (index !== currentIndex) currentIndex = index;
        activated(index);
        list.visible = false;
    }

    function openList() {
        if (!opens) return;
        // The cursor lands on the choice rather than travelling from where
        // the last opening left it.
        plate.disarm();
        plate.snap();
        entries.currentIndex = currentIndex;
        list.visible = true;
        entries.forceActiveFocus();
        opened();
    }

    // The open list's rectangle in the coordinates of the window the
    // control draws in, as JSON, or "closed".
    function listGeometry() {
        if (!list.visible) return "closed";
        const p = entries.mapToGlobal(-entries.x, -entries.y);
        return JSON.stringify([p.x, p.y, list.width, list.height]);
    }

    implicitWidth: Theme.size.panel.sm / 2
    implicitHeight: Theme.textField.height
    leftPadding: sidePadding
    rightPadding: sidePadding + Theme.icon.size.sm + Theme.textField.gap
    hoverEnabled: true
    // A disabled HoverHandler is never hovered, so Qt takes no cursor from
    // it and the arrow of the surface under the control shows.
    PointerCursor { enabled: root.opens }
    focusPolicy: Qt.StrongFocus
    opacity: enabled ? 1 : Theme.opacity.disabled
    Accessible.name: showsEmpty ? emptyText : showsPlaceholder ? placeholderText : currentText
    onClicked: if (list.visible) list.visible = false; else openList()
    Keys.onPressed: event => { event.accepted = closedNav.handle(event); }

    property KeyNav closedNav: KeyNav {
        focusTarget: root
        count: root.count
        currentIndex: root.currentIndex
        wrap: false /* closed select */
        labelAt: index => root.textAt(index)
        onMoved: index => root.choose(index)
        onActivated: root.openList()
    }

    contentItem: Label {
        id: shown
        role: "item"
        text: root.showsEmpty ? root.emptyText : root.showsPlaceholder ? root.placeholderText : root.currentText
        color: root.showsEmpty || root.showsPlaceholder ? Theme.textField.placeholder : shown.typography.color
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    indicator: Icon {
        name: "chevron-down"
        size: Theme.icon.size.sm
        color: root.opens ? Theme.textField.icon : Theme.color.textDisabled
        x: root.width - width - root.sidePadding
        y: (root.height - height) / 2
    }

    background: Rectangle {
        radius: Theme.textField.radius
        color: Theme.textField.background
        border.width: Theme.textField.border
        border.color: root.outline
        // Resetting retained focus must clear the drawn border immediately.
        FocusRing { id: focusRing; target: root }
    }

    PopupWindow {
        id: list

        anchor.item: root
        anchor.edges: Edges.Bottom | Edges.Left
        anchor.gravity: Edges.Bottom | Edges.Right
        anchor.adjustment: PopupAdjustment.Flip | PopupAdjustment.Slide
        anchor.margins.bottom: -Theme.select.gap
        grabFocus: true
        visible: false
        color: "transparent"
        // The field's width, never wider than the output's room.
        implicitWidth: Math.max(1, OverlayState.widthFor(root, root.width))
        implicitHeight: Math.max(1, Math.min(Theme.menu.maxHeight, entries.contentHeight) + 2 * root.listInset)
        onVisibleChanged: root.share(visible)

        DismissScope {
            popup: list
            anchor: root

            GlassSurface {
                anchors.fill: parent
                standard: Theme.menu
                elevation: "tight"
            }

            ListView {
                id: entries
                anchors.fill: parent
                anchors.topMargin: root.listInset
                anchors.bottomMargin: root.listInset
                anchors.leftMargin: Theme.border.thin
                anchors.rightMargin: Theme.border.thin
                model: root.model
                clip: true
                // Under a rounded corner the list is cut to the curve of the
                // interior.
                layer.enabled: listMask.cuts
                layer.smooth: true
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: listMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1
                }
                focus: true
                keyNavigationEnabled: true
                keyNavigationWraps: false
                boundsBehavior: Flickable.StopAtBounds
                acceptedButtons: Qt.NoButton
                TouchpadScroll { view: entries }
                // The bar's own test, so an entry keeps the bar's strip exactly
                // while the bar shows.
                readonly property bool overflowing: listBar.needed
                // A key moves the highlight: the pointer resting over the list
                // takes it again only once it moves. The key goes on to the view.
                Keys.onPressed: event => { event.accepted = openNav.handle(event); }

                property KeyNav openNav: KeyNav {
                    count: entries.count
                    currentIndex: entries.currentIndex
                    wrap: false /* open select */
                    viewHeight: entries.height
                    rowHeight: Theme.menu.item.height
                    labelAt: index => root.textAt(index)
                    cursor: plate
                    onMoved: index => {
                        entries.currentIndex = index;
                        entries.positionViewAtIndex(index, ListView.Contain);
                    }
                    onActivated: index => root.choose(index)
                }

                delegate: T.ItemDelegate {
                    id: entry
                    required property int index
                    readonly property bool chosen: index === root.currentIndex

                    width: ListView.view.width
                    implicitHeight: Theme.menu.item.height
                    leftPadding: root.sidePadding - Theme.border.thin
                    rightPadding: root.sidePadding - Theme.border.thin + (entries.overflowing ? Theme.scrollArea.gutter : 0)
                    text: root.textAt(index)
                    highlighted: ListView.isCurrentItem
                    hoverEnabled: true
                    PointerCursor {}
                    Accessible.name: text
                    onClicked: root.choose(index)

                    ListCursorRow {
                        cursor: plate
                        holds: entry.highlighted
                        onPointed: entries.currentIndex = entry.index
                    }

                    contentItem: Label {
                        role: "item"
                        text: entry.text
                        color: entry.chosen ? Theme.select.selectedForeground : Theme.menu.item.foreground
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }

                    background: Rectangle {
                        radius: Theme.menu.item.radius
                        color: entry.chosen ? Theme.select.selected : "transparent"
                    }
                }

                ListCursor {
                    id: plate
                    parent: entries.contentItem
                    color: Theme.select.highlight
                    pressedColor: Theme.menu.item.pressed
                    radius: Theme.menu.item.radius
                }

                HoverHandler { id: listHover }

                ScrollBar {
                    id: listBar
                    flickable: entries
                    hovered: listHover.hovered
                }
            }

            ListMask {
                id: listMask
                anchors.fill: entries
                frameWidth: list.width
                frameHeight: list.height
            }
        }
    }

    readonly property AnchorTracker tracker: AnchorTracker { popup: list; anchor: root }
}
