.pragma library

// The ground a shared key hint at ITEM reads on: the `hintGround` its
// nearest ancestor publishes, a GlassSurface, a Surface or a Dialog that
// holds it, else the colour of WIN, such as an application window's glass,
// or null where that window paints none, as a layer does. It reads only
// each ancestor's parent and the publisher's value, both notifying, so a
// binding that calls it follows the hint to another surface or a changed
// ground and never re-evaluates when a sibling moves
// (https://doc.qt.io/qt-6/qml-qtquick-item.html#parent-prop,
// https://doc.qt.io/qt-6/qml-qtquick-window-window.html#color-prop). A
// hint drawn over a surface it is not inside takes its ground from its
// caller instead.
// A banner also reads a surface painted behind its container, as a panel
// places Surface beside Pane. Existing key hints keep their ancestor-only
// read. Qt paints lower z first, then earlier children at equal z:
// https://doc.qt.io/qt-6/qml-qtquick-item.html#z-prop
function groundUnder(item, win, painted) {
    for (var child = item; child.parent !== null; child = child.parent) {
        var at = child.parent;
        if (painted) {
            var children = at.children;
            var index = 0;
            while (index < children.length && children[index] !== child) index++;
            var found = null;
            for (var i = 0; i < children.length; i++) {
                var candidate = children[i];
                if (candidate.hintGround === undefined || candidate === child) continue;
                if (candidate.z > child.z || (candidate.z === child.z && i > index)) continue;
                if (!candidate.visible || candidate.opacity <= 0) continue;
                if (candidate.x >= child.x + child.width || child.x >= candidate.x + candidate.width || candidate.y >= child.y + child.height || child.y >= candidate.y + candidate.height) continue;
                if (found === null || candidate.z >= found.z) found = candidate;
            }
            if (found !== null) return found.hintGround;
        }
        if (at.hintGround !== undefined) return at.hintGround;
    }
    return win !== null && win.color.a > 0 ? win.color : null;
}
