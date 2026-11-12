import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "../foundation/KeyNavLogic.js" as KeyNavLogic

// A row that shows one item, its icon, its name and one secondary line,
// with its actions at its end in `trailing`, such as an Add button or a
// row's RowActions. It takes no click: no plate, no press and no pointing
// hand, and each trailing control keeps its own hover, focus and click
// (ListItem's `clickable`). Its text starts on the content edge, as the
// other lines of a section do, since a row that takes no click draws no
// box to inset. The secondary line elides on one line, so every content
// row of a list is the same height. A row that opens a page is a
// NavigationRow.
//
// A row that carries a state, a needed action or a removing action
// stacks them under its name instead (owner, Slack 1794380399.262309,
// VGS-2458): `status` with its tone's mark, `statusTone` one of "",
// "success", "info", "warning" or "danger"; `detail`, a line that wraps;
// and `actions`, each a small secondary Button. `menuActions` go in a row
// menu, a "⋯" button at the end of the name's line, named "More actions
// for" the row, with the tooltip "More actions"; it holds the removing action, so Remove never stands
// beside a needed step; an entry there is led by its `iconName`, the trash
// mark for a removing action, in the menu's own ink. An entry reads its
// action's text alone, and its accessible name adds the row's name, as
// the button's does, so a screen reader hears which row Remove removes.
// Each action is
// { key, text, iconName, disabledReason }, the last two optional, and comes
// back through `actionTriggered` or `menuActionTriggered`. `key` keeps
// each button and menu entry, and the focus and highlight it holds, when
// the row is handed new action objects with the same keys, as a status
// write does. A part that is empty takes no room, and a row with none of
// them is the plain row above, pixel for pixel, its stacked lines and row
// menu never built: two inactive Loaders are all it adds. The stacked
// lines start under the name and stand `space.md` apart ink to ink
// (Theme.inkAbove, Theme.inkBelow), and the row's box holds
// `listItem.paddingX` above the first ink and below the last, so a plate
// that rests on it, a clickable row's ListCursor, keeps that room top and
// bottom while the row keeps the content edge at its sides; a passive row
// draws its name's line where a plain row does (`passiveTop`). The dots' ink
// ends on the row's end, as a trailing mark's does, and the name stops
// `listItem.gap` before the button.
// keyboard-path: each trailing control, stacked action and the row menu button is its own focus target
ListItem {
    id: root

    property string status: ""
    property string statusTone: ""
    property string detail: ""
    property var actions: []
    property var menuActions: []

    signal actionTriggered(var action)
    signal menuActionTriggered(var action)

    readonly property bool stacked: status !== "" || detail !== "" || actions.length > 0 || menuActions.length > 0
    readonly property real stackPad: Theme.listItem.paddingX

    // The ink of the name's line inside the content item: how far below
    // its top it starts and above its bottom it ends, an icon's by its
    // painted extent, since its box leaves room around each shape. The
    // content item's height follows the paddings these set, so they settle
    // a turn later, as ClearingInset settles, rather than in a binding that
    // reads its own result.
    property real headInkAbove: 0
    property real headInkBelow: 0
    property bool settlePending: false
    function scheduleSettle() {
        if (settlePending || !stacked) return;
        settlePending = true;
        Qt.callLater(settle);
    }
    function settle() {
        settlePending = false;
        if (!stacked || contentItem === null) return;
        let top = contentItem.height;
        let bottom = 0;
        for (const child of contentItem.children) {
            if (!child.visible || child.width <= 0 || child.height <= 0) continue;
            const painted = child instanceof Icon ? child.painted : null;
            top = Math.min(top, child.y + (painted !== null ? painted[1] : Theme.inkAbove(child)));
            bottom = Math.max(bottom, child.y + (painted !== null ? painted[3] : child.height - Theme.inkBelow(child)));
        }
        headInkAbove = top;
        headInkBelow = contentItem.height - bottom;
    }
    onStackedChanged: scheduleSettle()
    onHeightChanged: scheduleSettle()
    onWidthChanged: scheduleSettle()
    onTextChanged: scheduleSettle()
    onIconNameChanged: scheduleSettle()
    Component.onCompleted: scheduleSettle()

    // The stacked lines' top under the content item's top, on a whole
    // pixel so their text draws sharp, the room they add under the name's
    // line, and their last ink's distance above their bottom.
    readonly property Item stackItem: stackLoader.item
    readonly property bool stackShown: stackItem !== null && stackItem.shown
    readonly property real stackOffset: Math.round(implicitContentHeight - headInkBelow + Theme.space.md - (stackItem === null ? 0 : Theme.inkAbove(stackItem)))
    readonly property real stackSpan: stackShown ? stackOffset + stackItem.height - implicitContentHeight : 0
    readonly property real endInkBelow: stackShown ? Theme.inkBelow(stackItem) : headInkBelow
    readonly property Item menuButton: moreLoader.item

    clickable: false
    leftPadding: 0
    rightPadding: menuButton !== null ? menuButton.width - menuButton.glyphEnd + Theme.listItem.gap : leftPadding
    // A row a ListCursor plates keeps `stackPad` above its first ink and
    // below its last, so the plate's padding is even. A passive row draws
    // no plate: its name's line stands where a plain row of
    // `listItem.height` centres it, so a heading above it keeps the gap it
    // keeps over plain rows (VGS-2458), and its last ink stands
    // `2 * stackPad` less that first-ink offset above its bottom, so two
    // rows' inks stay as far apart as plated rows' do.
    readonly property bool plated: cursor !== null
    // Floored as a plain row's centred children land, on a whole pixel.
    readonly property real passiveTop: Math.floor((Theme.listItem.height - implicitContentHeight) / 2)
    readonly property real passiveBottom: 2 * stackPad - passiveTop - headInkAbove
    // undefined resets a padding to the control's own, as on a plain row:
    // https://doc.qt.io/qt-6/qml-qtquick-controls-control.html#topPadding-prop
    topPadding: !stacked ? undefined : plated ? stackPad - Math.floor(headInkAbove) : passiveTop
    bottomPadding: !stacked ? undefined : plated ? stackSpan + stackPad - Math.floor(endInkBelow) : Math.round(stackSpan + passiveBottom - endInkBelow)

    onStatusToneChanged: if (["", "success", "info", "warning", "danger"].indexOf(statusTone) === -1) console.error("ContentRow: statusTone " + JSON.stringify(statusTone) + " is not one of \"\", success, info, warning, danger")

    // A stacked row's first ink is its name line's, an icon's by its painted
    // shape, and its last is the stack's, which the content item does not
    // hold. These shadow ListItem's own: a read through the row, as
    // Theme.inkAbove makes, finds this type's value (qmltestrunner, Qt
    // 6.12.0), and ListItem reads neither itself.
    readonly property real inkAbove: drawsNoBox ? (stacked ? topPadding + headInkAbove : contentInkAbove()) : 0
    readonly property real inkBelow: drawsNoBox ? drawnInkBelow : 0
    // How far above the row's bottom its last drawn ink ends, a plate or
    // not, for a list that spaces what follows it from its rows' ink.
    readonly property real drawnInkBelow: stacked ? bottomPadding - stackSpan + endInkBelow : contentInkBelow()

    Loader {
        id: stackLoader
        active: root.stacked
        x: root.textStart
        y: root.topPadding + root.stackOffset
        width: Math.max(0, root.width - x)
        sourceComponent: Item {
            id: stack

            // Whether `line` draws: an empty line takes no gap. Each line's own
            // `wanted`, not `visible`, which reads false while this item hides
            // and so would hide it for good. A line its row's teardown already
            // took is null.
            function drawn(line) { return line !== null && line.wanted && line.height > 0; }
            // Each line's top, its ink `space.md` under the ink of the drawn
            // line above it, or its ink on this item's top for the first, with
            // the first and last drawn lines' ink and this item's height. Read
            // from heights and ink alone and placed by `place`, as GroupList
            // places its groups, so no line's y binds to another's. Each line
            // declares its ink as a number, read here directly: Theme's
            // readers first read the line's `visible`, which follows this
            // item's, which follows `shown`, so a read through Theme makes
            // this binding depend on its own result.
            readonly property var layout: {
                const tops = [];
                let first = -1, last = -1, inkBottom = 0, inkTop = 0;
                [statusLine, detailLine, actionRow].forEach((line, i) => {
                    if (!drawn(line)) { tops.push(0); return; }
                    const top = Math.round(last === -1 ? -line.inkAbove : inkBottom + Theme.space.md - line.inkAbove);
                    tops.push(top);
                    if (first === -1) { first = i; inkTop = top + line.inkAbove; }
                    last = i;
                    inkBottom = top + line.height - line.inkBelow;
                });
                const lines = [statusLine, detailLine, actionRow];
                return { tops: tops, shown: last !== -1, inkTop: inkTop, inkBottom: inkBottom,
                    height: last === -1 ? 0 : tops[last] + lines[last].height };
            }
            readonly property bool shown: layout.shown
            function place() { [statusLine, detailLine, actionRow].forEach((line, i) => { if (line !== null) line.y = layout.tops[i]; }); }
            onLayoutChanged: place()
            Component.onCompleted: place()
            readonly property real inkAbove: layout.inkTop
            readonly property real inkBelow: layout.height - layout.inkBottom

            visible: shown
            height: layout.height

            Item {
                id: statusLine
                readonly property var marks: ({ "": "", success: "check", info: "info", warning: "triangle-alert", danger: "circle-alert" })
                readonly property bool wanted: root.status !== ""
                readonly property bool alarm: root.statusTone === "warning" || root.statusTone === "danger"
                // On the plate the words take the plate's ink, as the name does;
                // the mark keeps its tone.
                readonly property color ink: root.lit ? Theme.listItem.selectedForeground : alarm ? Theme.color[root.statusTone] : Theme.text.itemHint.color
                readonly property real inkAbove: mark.drawn ? Math.min(stateText.inkAbove, mark.y + mark.painted[1]) : stateText.inkAbove
                readonly property real inkBelow: height - (mark.drawn ? Math.max(stateText.height - stateText.inkBelow, mark.y + mark.painted[3]) : stateText.height - stateText.inkBelow)
                visible: wanted
                width: stack.width
                height: wanted ? stateText.height : 0
                Icon {
                    id: mark
                    readonly property bool drawn: name !== ""
                    visible: drawn
                    name: statusLine.marks[root.statusTone] || ""
                    size: Theme.rowAction.icon
                    color: statusLine.alarm ? Theme.color[root.statusTone] : root.lit ? Theme.listItem.selectedForeground : Theme.color.textMuted
                    y: stateText.topForLeadingIcon(height, 0, false)
                }
                Label {
                    id: stateText
                    x: mark.drawn ? Theme.rowAction.icon + Theme.rowAction.iconGap : 0
                    width: parent.width - x
                    role: "itemHint"
                    textFormat: Text.PlainText
                    text: root.status
                    color: statusLine.ink
                    wrapMode: Text.Wrap
                }
            }
            Label {
                id: detailLine
                readonly property bool wanted: root.detail !== ""
                visible: wanted
                width: stack.width
                role: "itemHint"
                textFormat: Text.PlainText
                text: root.detail
                color: root.lit ? Theme.listItem.selectedForeground : Theme.text.itemHint.color
                wrapMode: Text.Wrap
            }
            Row {
                id: actionRow
                readonly property bool wanted: root.actions.length > 0
                // Boxed buttons: their boxes are the ink.
                readonly property real inkAbove: 0
                readonly property real inkBelow: 0
                visible: wanted
                spacing: Theme.stack.inline
                Repeater {
                    model: ScriptModel { values: root.actions; objectProp: "key" }
                    Button {
                        required property var modelData
                        size: "sm"
                        variant: "secondary"
                        text: modelData.text
                        iconName: modelData.iconName || ""
                        disabledReason: modelData.disabledReason || ""
                        onClicked: root.actionTriggered(modelData)
                    }
                }
            }
        }

    }

    // The row menu: its dots centre on the name's line, and their ink ends
    // on the row's end.
    Loader {
        id: moreLoader
        active: root.menuActions.length > 0
        x: root.width - (item === null ? 0 : item.width - item.glyphEnd)
        y: Math.round(root.topPadding + root.implicitContentHeight / 2 - (item === null ? 0 : item.height) / 2)
        sourceComponent: IconButton {
            id: more
            size: "sm"
            iconName: "ellipsis"
            label: "More actions for " + root.text
            tooltip: "More actions"
            onClicked: menu.toggle(KeyNavLogic.opener(more))
            Menu {
                id: menu
                Repeater {
                    model: ScriptModel { values: root.menuActions; objectProp: "key" }
                    MenuItem {
                        required property var modelData
                        text: modelData.text
                        Accessible.name: modelData.text + " " + root.text
                        iconName: modelData.iconName || ""
                        disabledReason: modelData.disabledReason || ""
                        onTriggered: root.menuActionTriggered(modelData)
                    }
                }
            }
        }
    }
}
