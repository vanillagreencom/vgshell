import QtQuick
import qs.Commons

// A bounded square QR matrix with an encoder-supplied quiet zone. Integer
// modules avoid interpolation. The caller owns the data and clears it on close.
Item {
    id: root
    property string matrixData: ""
    readonly property var rows: accepted(matrixData)
    readonly property int side: rows.length
    readonly property int moduleSize: side === 0 ? 0 : Math.max(0, Math.floor(Math.min(width, height) / side))
    readonly property int drawnSize: side * moduleSize
    implicitWidth: Theme.qrMatrix.size
    implicitHeight: implicitWidth
    Accessible.ignored: true

    function accepted(text) {
        if (text === "") return [];
        const found = text.replace(/\n$/, "").split("\n");
        if (found.length > 185 || found.some(row => row.length !== found.length || !/^[01]+$/.test(row))) return [];
        return found;
    }

    Rectangle {
        id: canvas
        anchors.centerIn: parent
        width: root.drawnSize
        height: width
        visible: root.side > 0 && root.moduleSize > 0
        color: Theme.qrMatrix.background
        Grid {
            anchors.fill: parent
            columns: root.side
            Repeater {
                model: root.side * root.side
                Rectangle {
                    required property int index
                    width: root.moduleSize
                    height: width
                    color: root.rows[Math.floor(index / root.side)].charAt(index % root.side) === "1" ? Theme.qrMatrix.foreground : Theme.qrMatrix.background
                }
            }
        }
    }
}
