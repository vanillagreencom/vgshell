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
function groundUnder(item, win) {
    for (var at = item.parent; at !== null; at = at.parent)
        if (at.hintGround !== undefined) return at.hintGround;
    return win !== null && win.color.a > 0 ? win.color : null;
}
