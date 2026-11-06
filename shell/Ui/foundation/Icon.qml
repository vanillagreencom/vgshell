import QtQuick
import QtQuick.Shapes
import qs.Commons
import "../icons/Lucide.js" as Lucide
import "../icons/Own.js" as Own
import "IconBounds.js" as IconBounds

// One Lucide icon by name, drawn from its path data with the curve
// renderer. The stroke is `stroke` in absolute pixels whatever the size,
// so a 14 pixel icon and a 24 pixel icon carry the same line weight: the
// shape is drawn in the data's box and scaled as an item, and the stroke
// width is divided by the same factor. The item transform, not the path's
// own `scale`, keeps sub-unit strokes visible with Qt 6.11.2's curve
// renderer. A name the data lacks is logged and draws nothing.
Item {
    id: root

    property string name: ""
    property int size: Theme.icon.size.md
    property color color: Theme.color.text
    property real stroke: Theme.icon.stroke
    readonly property var paths: pathsOf(name)
    readonly property real factor: size / Lucide.VIEWBOX
    readonly property bool lowerDisabled: Own.VARIANTS[name] === "lower-disabled"
    // The ink's extent in the item, [left, top, right, bottom] in pixels:
    // the paths' extent (IconBounds.js) held inside the data's box, grown
    // by half the stroke. A header aligns a glyph by it, since each Lucide
    // shape sits differently in its box.
    readonly property var painted: paintedOf(paths)

    function paintedOf(data) {
        const box = IconBounds.bounds(data[0] + " " + data[1]);
        if (box === null) return [0, 0, 0, 0];
        const clamp = value => Math.max(0, Math.min(Lucide.VIEWBOX, value)) * factor;
        const half = stroke / 2;
        return [Math.max(0, clamp(box.left) - half), Math.max(0, clamp(box.top) - half), Math.min(size, clamp(box.right) + half), Math.min(size, clamp(box.bottom) + half)];
    }

    function pathsOf(wanted) {
        const found = Lucide.ICONS[wanted];
        if (found !== undefined) return found;
        if (wanted !== "") console.error("Icon: no icon named " + JSON.stringify(wanted));
        return ["", ""];
    }

    implicitWidth: size
    implicitHeight: size

    // Clip two copies at the box's midpoint, not at a path's endpoints,
    // so round caps and stroke width stay identical across the held variant.
    // Qt Quick Item.clip clips children to its rectangle; opacity composes
    // over the glyph ink: https://doc.qt.io/qt-6/qml-qtquick-item.html
    Item {
        width: root.size
        height: root.lowerDisabled ? root.size / 2 : root.size
        clip: root.lowerDisabled
        Loader { sourceComponent: glyph }
    }
    Loader {
        active: root.lowerDisabled
        y: root.size / 2
        width: root.size
        height: root.size / 2
        sourceComponent: Item {
            clip: true
            opacity: Theme.opacity.disabled
            Loader { y: -root.size / 2; sourceComponent: glyph }
        }
    }
    Component {
        id: glyph
        Shape {
            width: Lucide.VIEWBOX
            height: Lucide.VIEWBOX
            transform: Scale { xScale: root.factor; yScale: root.factor }
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: root.color
                fillColor: "transparent"
                strokeWidth: root.stroke / root.factor
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathSvg { path: root.paths[0] }
            }
            ShapePath {
                strokeColor: "transparent"
                fillColor: root.color
                PathSvg { path: root.paths[1] }
            }
        }
    }
}
