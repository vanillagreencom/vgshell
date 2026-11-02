import QtQuick
import qs.Commons

// The actions of one row side by side, such as a plugin's Update and
// Remove: links or small buttons `gap` apart, by default `rowAction.gap`, top-aligned on one
// line as tall as the tallest. A hidden action takes no room, and nor does
// a child without a size, such as the Repeater that makes the actions.
// Every row that sets two or more actions beside each other composes it,
// so the gap is one rule. With no width set it is as wide as its actions
// and stands on one line. Given less width, the actions continue on a new
// line once the next one would pass that width; each line then takes
// `row.height` with its actions centred in it, and the lines stand
// `stack.row` apart, as the rows of a page stack do, so a line starts
// where the next row of the page would and the first sits where a
// one-line row's action does. `firstLineHeight` is that first line's height while the
// actions wrap and 0 while they stand on one line; FormRow reads it to set
// its label beside the first line. `inkAbove()` and `inkBelow()` are how
// far inside its top and bottom edges the highest and the lowest action
// are drawn.
Item {
    id: root

    property real gap: Theme.rowAction.gap

    // The children that take room, in drawn order. A Repeater's items are
    // children of its parent, placed right after it
    // (https://doc.qt.io/qt-6/qml-qtquick-repeater.html), so `children`
    // holds them in the model's order.
    readonly property var shown: children.filter(child => child.visible && child.width > 0 && child.height > 0)
    // Where one line of them ends, summed in the order `placed` sums, so
    // the last action of a RowActions with no width set ends on that width
    // to the last bit and stays on the line.
    readonly property real lineWidth: shown.reduce((end, child, index) => (index > 0 ? end + root.gap : 0) + child.width, 0)
    // Where each action goes. It reads `width`, which follows `lineWidth`
    // while none is set, so it is a property apart from `lineWidth`: one
    // that set the implicit width it reads would be a binding loop.
    readonly property var placed: {
        const spots = [];
        let x = 0;
        let line = 0;
        for (const child of shown) {
            if (x > 0 && x + child.width > width) {
                x = 0;
                line++;
            }
            spots.push({ item: child, x: x, line: line });
            x += child.width + root.gap;
        }
        return { spots: spots, lines: line + 1 };
    }
    readonly property real firstLineHeight: placed.lines > 1 ? Theme.row.height : 0

    function inkAbove() {
        return shown.length === 0 ? 0 : Math.min(...shown.map(child => child.y + Theme.inkAbove(child)));
    }

    function inkBelow() {
        return shown.length === 0 ? 0 : height - Math.max(...shown.map(child => child.y + child.height - Theme.inkBelow(child)));
    }

    implicitWidth: lineWidth
    implicitHeight: placed.lines > 1 ? placed.lines * Theme.row.height + (placed.lines - 1) * Theme.stack.row : shown.reduce((tallest, child) => Math.max(tallest, child.height), 0)
    onPlacedChanged: {
        const wrapped = placed.lines > 1;
        for (const spot of placed.spots) {
            spot.item.x = spot.x;
            spot.item.y = wrapped ? spot.line * (Theme.row.height + Theme.stack.row) + Math.round((Theme.row.height - spot.item.height) / 2) : 0;
        }
    }
}
