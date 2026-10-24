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
// press outside or Escape closes it (DismissScope). Each entry is a
// MenuItem: one ListCursor draws the highlight, as a menu's does, and
// travels between entries, a hover moves it once the pointer moves
// (ListCursor) and scrolls nothing, and the chosen entry draws the menu's
// check mark. With the list closed, Up and Down on the focused control
// move the choice. The list opens on the control's edges, as wide as it,
// and its entries fill it inside the menu's border, so a highlight meets
// the border at the top and both sides (Theme.menuListInset); an entry's
// leading padding is the control's less that border, so its text starts
// where the control's does. Under its last
// entry the list's own fill runs `listCover` further, the gap above the
// list plus a field's border, before its bottom border. The entry count,
// not the page, sets where the entries end, so a field drawn under the list
// can end just below them; the fill covers that field's edge, which would
// otherwise show as a second line under the list's border. A list taller
// than `menu.maxHeight` scrolls under the module's embedded bar, which
// draws over the strip each entry keeps clear at its end while the bar
// shows. Under a rounded corner the list is cut to the window's rounded
// interior (ListMask), so a row scrolled part way past an edge stays inside
// the curve. The control draws like a text field; the template owns its
// click, hover and focus. A choice wider than the control wraps onto
// further lines and never elides, as an entry of the list does (MenuItem):
// the control grows by those lines, its first line and the chevron stand
// where a one-line choice's do, and `firstLineHeight` keeps its row's label
// beside that line (FormRow). A line breaks only at a space
// (LineBreak.atSpaces); the accessible name is the plain text. Page Up and
// Page Down in the open list step by one-line entries, so over wrapped
// entries a page moves fewer. With nothing to choose the list never opens, so
// no popup repeats what the closed control says, and nothing promises it
// will: the pointer stays the arrow and the chevron draws in the disabled
// text colour. With `emptyText` set, the control reads that text dimmed.
// With entries to choose,
// none chosen (`currentIndex` outside the model) and `placeholderText` set,
// the control reads that text dimmed, and the list opens with no entry
// highlighted; Down then moves to the first entry. A set `disabledReason`
// disables the control: it stays a Tab stop, its list never opens, as with
// nothing to choose, a key moves no choice, it draws faded with no hover
// outline, and it shows the reason on hover and keyboard focus
// (DisabledReason).
// `iconRole` names the field of a model entry that holds the name of an
// icon the entry leads with, such as an Add entry's plus mark. With
// `entryAction` set, { iconName, label }, each entry whose `actionRole`
// field is true draws an icon button at its end, labelled with the action
// and the entry's text, such as Play Puck: a click on it, or Enter or
// Space while the keyboard is on it, emits `entryActionActivated` with the
// entry's index and chooses nothing. In the open list Right moves the
// keyboard from the highlighted entry to its button and Left back; Up and
// Down move the highlight and take the keyboard back to the entry, and no
// arrow presses the button (docs/architecture/design-system.md § Keyboard).
// The button of the entry last pressed draws checked while the list stays
// open.
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
    property string disabledReason: ""
    readonly property DisabledReason lock: lockState
    readonly property int count: Array.isArray(model) ? model.length : 0
    readonly property bool opens: count > 0 && !lockState.locked
    readonly property string currentText: textAt(currentIndex)
    readonly property bool listOpen: list.visible
    property bool counted: false
    readonly property string typed: closedNav.typed
    property string emptyText: ""
    readonly property bool showsEmpty: count === 0 && emptyText !== ""
    property string placeholderText: ""
    property string iconRole: ""
    property var entryAction: null
    property string actionRole: ""
    // Whether the keyboard is on the highlighted entry's button.
    readonly property bool entryActionFocused: entries.actionFocused
    // The index of the entry whose button was pressed last, -1 for none.
    readonly property int pressedAction: entries.pressedAction
    readonly property bool showsPlaceholder: count > 0 && !(currentIndex >= 0 && currentIndex < count) && placeholderText !== ""
    // A user choice only. Model and binding updates never emit this.
    signal activated(int index)
    // The list opened, so an owner can refresh the model it shows.
    signal opened()
    // The button of the entry at INDEX was pressed (entryAction).
    signal entryActionActivated(int index)

    function share(open) {
        if (open === counted) return;
        counted = open;
        if (open) OverlayState.opened(); else OverlayState.closed();
    }
    Component.onDestruction: share(false)
    readonly property color outline: focusRing.visible || list.visible ? Theme.textField.focus : hovered ? Theme.textField.hover : Theme.textField.borderColor
    readonly property real sidePadding: Theme.controlPadding(Theme.textField.paddingX, Theme.textField.radius, Math.max(Theme.textField.height, height), implicitContentHeight)
    // The list's top inset inside its window, and its bottom inset with
    // `listCover` added; its side inset is the border.
    readonly property real listInset: Theme.menuListInset(list.width)
    readonly property real listCover: Theme.select.gap + Theme.textField.border

    // Whether the entry at INDEX draws the entry action's button.
    function actionAt(index) {
        if (entryAction === null || actionRole === "" || index < 0 || index >= count) return false;
        const entry = model[index];
        return entry !== null && typeof entry === "object" && entry[actionRole] === true;
    }
    function iconAt(index) {
        if (iconRole === "" || index < 0 || index >= count) return "";
        const entry = model[index];
        return entry !== null && typeof entry === "object" && typeof entry[iconRole] === "string" ? entry[iconRole] : "";
    }
    function pressAction(index) {
        if (!actionAt(index)) return;
        entries.pressedAction = index;
        entryActionActivated(index);
    }

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
        entries.actionFocused = false;
        entries.pressedAction = -1;
        entries.highlightIndex = currentIndex;
        list.visible = true;
        if (currentIndex >= 0 && currentIndex < count) entries.positionViewAtIndex(currentIndex, ListView.Contain);
        else entries.positionViewAtBeginning();
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
    // A wrapped choice keeps a one-line choice's room above its first line
    // and under its last.
    readonly property real lineInset: Math.max(0, (Theme.textField.height - shown.lineBox) / 2)
    // The first line's height while the choice wraps, 0 otherwise.
    readonly property real firstLineHeight: shown.lineCount > 1 ? Theme.textField.height : 0
    implicitHeight: Math.max(Theme.textField.height, implicitContentHeight + 2 * lineInset)
    leftPadding: sidePadding
    rightPadding: sidePadding + Theme.icon.size.sm + Theme.textField.gap
    hoverEnabled: !lockState.locked
    // A disabled HoverHandler is never hovered, so Qt takes no cursor from
    // it and the arrow of the surface under the control shows.
    PointerCursor { enabled: root.opens }
    focusPolicy: Qt.StrongFocus
    opacity: enabled ? 1 : Theme.opacity.disabled
    Accessible.name: showsEmpty ? emptyText : showsPlaceholder ? placeholderText : currentText
    onClicked: if (list.visible) list.visible = false; else openList()
    Keys.onPressed: event => { event.accepted = lockState.locked ? lockState.takeKey(event) : closedNav.handle(event); }

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
        spaceWrappedText: root.showsEmpty ? root.emptyText : root.showsPlaceholder ? root.placeholderText : root.currentText
        role: "item"
        color: root.showsEmpty || root.showsPlaceholder ? Theme.textField.placeholder : shown.typography.color
        opacity: lockState.fade
        verticalAlignment: Text.AlignVCenter
        wrapMode: Text.Wrap
    }

    indicator: Icon {
        name: "chevron-down"
        size: Theme.icon.size.sm
        color: root.opens ? Theme.textField.icon : Theme.color.textDisabled
        x: root.width - width - root.sidePadding
        y: (Theme.textField.height - height) / 2
        opacity: lockState.fade
    }

    background: Rectangle {
        radius: Theme.textField.radius
        color: lockState.faded(Theme.textField.background)
        border.width: Theme.textField.border
        border.color: lockState.faded(root.outline)
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
        implicitHeight: Math.max(1, Math.min(Theme.menu.maxHeight, entries.contentHeight) + 2 * root.listInset + root.listCover)
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
                anchors.bottomMargin: root.listInset + root.listCover
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
                // openNav owns the keys.
                keyNavigationEnabled: false
                boundsBehavior: Flickable.StopAtBounds
                acceptedButtons: Qt.NoButton
                TouchpadScroll { view: entries }
                // The bar's own test, so an entry keeps the bar's strip exactly
                // while the bar shows.
                readonly property bool overflowing: listBar.needed
                // The highlighted entry, which a key and a hover move. It is
                // not the view's currentIndex: a ListView scrolls to keep a
                // new current item in view as its highlight moves there, so
                // a hover over an entry part way past the bottom scrolled
                // the list (scripts/qml-unit.sh tst_overlays.qml,
                // 2026-10-16: contentY 0 to 18; design-system.md § Pointer).
                // Only a key move, through openNav, and an opening scroll an
                // entry into view.
                property int highlightIndex: -1
                // Whether the keyboard is on the highlighted entry's button
                // (entryAction), and the entry whose button was pressed last.
                property bool actionFocused: false
                property int pressedAction: -1
                onHighlightIndexChanged: actionFocused = false
                // A key moves the highlight: the pointer resting over the list
                // takes it again only once it moves. Right and Left move the
                // keyboard between the highlighted entry and its button, and
                // Enter or Space presses the button while the keyboard is on
                // it; every other key goes to the list's navigation.
                Keys.onPressed: event => {
                    // Up and Down take the keyboard back to the entry even
                    // at the list's end, where the highlight stays put.
                    if (event.key === Qt.Key_Up || event.key === Qt.Key_Down) entries.actionFocused = false;
                    if (root.actionAt(entries.highlightIndex) && event.modifiers === Qt.NoModifier) {
                        if (event.key === Qt.Key_Right && !entries.actionFocused) { entries.actionFocused = true; event.accepted = true; return; }
                        if (event.key === Qt.Key_Left && entries.actionFocused) { entries.actionFocused = false; event.accepted = true; return; }
                        if (entries.actionFocused && [Qt.Key_Return, Qt.Key_Enter, Qt.Key_Space].indexOf(event.key) !== -1) {
                            root.pressAction(entries.highlightIndex);
                            event.accepted = true;
                            return;
                        }
                    }
                    event.accepted = openNav.handle(event);
                }

                property KeyNav openNav: KeyNav {
                    count: entries.count
                    currentIndex: entries.highlightIndex
                    wrap: false /* open select */
                    viewHeight: entries.height
                    rowHeight: Theme.menu.item.height
                    labelAt: index => root.textAt(index)
                    cursor: plate
                    onMoved: index => {
                        entries.highlightIndex = index;
                        entries.positionViewAtIndex(index, ListView.Contain);
                    }
                    onActivated: index => root.choose(index)
                }

                delegate: MenuItem {
                    id: entry
                    required property int index

                    // The scroll bar's strip. A delegate that outlives its
                    // list while it tears down reads none.
                    readonly property real gutter: entries !== null && entries.overflowing ? Theme.scrollArea.gutter : 0

                    width: ListView.view.width
                    leftPadding: root.sidePadding - Theme.border.thin
                    barRoom: entry.gutter + (action.visible ? action.width + spacing : 0)
                    text: root.textAt(index)
                    iconName: root.iconAt(index)
                    checked: index === root.currentIndex
                    highlighted: index === entries.highlightIndex
                    cursor: plate
                    onPointed: entries.highlightIndex = entry.index
                    onClicked: root.choose(index)
                    // The view gives its current item the focus, and a
                    // MenuItem takes Return and Enter as its own click, so an
                    // entry hands every key to the list's navigation first,
                    // which chooses the highlighted entry (layers,
                    // automations and network smoke rows, 2026-10-18:
                    // Return chose the view's current entry instead).
                    Keys.forwardTo: [entries]

                    // The entry action's button, in the strip the entry keeps
                    // clear at its end (barRoom), before the scroll bar's,
                    // beside the entry's first line. Only an entry that
                    // offers the action builds one.
                    Loader {
                        id: action
                        active: root.actionAt(entry.index)
                        visible: active
                        y: entry.firstLineCentre - height / 2
                        x: entry.width - entry.gutter - width - Theme.border.thin
                        // keyboard-path: the open list's Right moves to it and Enter or Space presses it (entries Keys.onPressed)
                        sourceComponent: IconButton {
                            size: "sm"
                            iconName: root.entryAction === null ? "" : root.entryAction.iconName
                            label: root.entryAction === null ? "" : root.entryAction.label + " " + entry.text
                            checked: entries.pressedAction === entry.index
                            focusPreview: entry.highlighted && entries.actionFocused
                            focusPolicy: Qt.NoFocus
                            onClicked: root.pressAction(entry.index)
                        }
                    }
                }

                ListCursor {
                    id: plate
                    parent: entries.contentItem
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

    DisabledReason { id: lockState; control: root }
}
