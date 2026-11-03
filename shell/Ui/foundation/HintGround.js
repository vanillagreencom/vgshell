.pragma library

// The fill under a shared key hint at ITEM, as the surface it draws on
// publishes it: the effectiveFill of the nearest GlassSurface, a Surface
// included, that holds ITEM or lies under it, else the colour of WIN,
// such as an application window's glass, or null where that window paints
// none, as a layer does. At each level up it reads the ancestor itself,
// then the topmost shown sibling drawn before it that it overlaps, in the
// order GlassSurface.overContent reads what lies under a surface. Every
// property read is a notifying one, an Item's parent, children, z,
// visible, opacity and geometry and a Window's color, so a binding that
// calls this follows a move, a hidden surface or a changed fill
// (https://doc.qt.io/qt-6/qml-qtquick-item.html,
// https://doc.qt.io/qt-6/qml-qtquick-window-window.html#color-prop).
function groundUnder(item, win) {
    for (var at = item; at.parent !== null; at = at.parent) {
        var level = at.parent;
        if (level.glassSurface === true) return level.effectiveFill;
        var kids = level.children;
        var index = 0;
        while (index < kids.length && kids[index] !== at) index++;
        var found = null;
        var foundIndex = -1;
        for (var i = 0; i < kids.length; i++) {
            var other = kids[i];
            if (other === at || other.glassSurface !== true) continue;
            if (other.z > at.z || (other.z === at.z && i > index)) continue;
            if (!other.visible || other.opacity <= 0) continue;
            if (other.x >= at.x + at.width || at.x >= other.x + other.width || other.y >= at.y + at.height || at.y >= other.y + other.height) continue;
            if (found === null || other.z > found.z || (other.z === found.z && i > foundIndex)) {
                found = other;
                foundIndex = i;
            }
        }
        if (found !== null) return found.effectiveFill;
    }
    return win !== null && win.color.a > 0 ? win.color : null;
}
