import QtQuick

// The layout slot keeps its size and position while its contents move
// together onto whole screen rows and columns: a text at a fractional
// position spreads each stem over two pixels and reads fainter.
Item {
    id: root

    default property alias content: snapped.data

    data: Item {
        id: snapped
        // Item x/y are relative to the parent (Qt 6 Item documentation).
        // The browser's ancestors, including SummonLayer's host slot, have
        // translation only. Reading each position here keeps the origin
        // reactive when the pane centres again, without moving its rail.
        // https://doc.qt.io/qt-6/qml-qtquick-item.html#x-prop
        readonly property point origin: {
            let x = 0, y = 0;
            for (let item = parent; item !== null; item = item.parent) {
                x += item.x;
                y += item.y;
            }
            return Qt.point(x, y);
        }
        x: Math.round(origin.x) - origin.x
        y: Math.round(origin.y) - origin.y
        width: root.width
        height: root.height
    }
}
