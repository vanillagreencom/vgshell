import QtQuick

// One dark field behind a surface's content, drawn by shaders/radialbackdrop.frag
// in one pass: up to four rounded boxes joined with no crease, each with its
// own peak opacity, ink, fade and inset, so a decoration on a passive layer
// reads over any wallpaper. It is decorative: it takes no input and holds no
// process, file or cache (D026), and it draws again only when an input
// changes, since nothing in it animates.
//
// Every input is required, with no Theme default: each owner hands its own
// look's values.
// - `boxes`: at most four { x, y, w, h, corner, peak, fade, inset, ink }, in
//   this item's coordinates. The falloff runs from `inset` inside the box to
//   `fade - inset` outside it. A fifth box is not drawn.
// - `join`: the smooth union's width, and `blend`, the width over which
//   peak and ink pass from one box to the next, both in units of a box's own
//   fade.
// - `falloff`: "eased", 1 - smootherstep, which ends at zero; or "gaussian",
//   exp(-x²) past the plateau, vgs.voice's dictation orb's own edge.
// - `halo`: null, or { strength, width, ring, stops }: a glow past a ring
//   of radius `ring` round box 0's centre, `width` px wide, in the four
//   colours of `stops`, top to bottom.
// Size the item to hold every box's reach; the field is clipped to it.
ShaderEffect {
    id: root

    required property var boxes
    required property real join
    required property real blend
    required property string falloff
    required property var halo

    function boxOf(i) {
        const b = root.boxes[i];
        return b === undefined ? Qt.vector4d(0, 0, 0, 0) : Qt.vector4d(b.x + b.w / 2, b.y + b.h / 2, b.w / 2, b.h / 2);
    }
    function field(i, key, none) {
        const b = root.boxes[i];
        return b === undefined ? none : b[key];
    }
    function four(key, none) {
        return Qt.vector4d(field(0, key, none), field(1, key, none), field(2, key, none), field(3, key, none));
    }

    blending: true
    Accessible.ignored: true
    onBoxesChanged: if (boxes.length > 4) console.error("RadialBackdrop: " + boxes.length + " boxes; drawing the first 4")
    onFalloffChanged: if (falloff !== "eased" && falloff !== "gaussian") console.error('RadialBackdrop: no falloff named "' + falloff + '"; drawing eased')

    property vector2d uSize: Qt.vector2d(width, height)
    property vector4d uBox0: boxOf(0)
    property vector4d uBox1: boxOf(1)
    property vector4d uBox2: boxOf(2)
    property vector4d uBox3: boxOf(3)
    property vector4d uCorner: four("corner", 0)
    property vector4d uPeak: four("peak", 0)
    property vector4d uFade: four("fade", 1)
    property vector4d uInset: four("inset", 0)
    property vector4d uJoin: Qt.vector4d(join, blend, falloff === "gaussian" ? 1 : 0, halo === null ? 0 : 1)
    property color uInk0: field(0, "ink", "transparent")
    property color uInk1: field(1, "ink", "transparent")
    property color uInk2: field(2, "ink", "transparent")
    property color uInk3: field(3, "ink", "transparent")
    property vector4d uHalo: halo === null ? Qt.vector4d(0, 1, 0, 0) : Qt.vector4d(halo.strength, halo.width, halo.ring, 0)
    property color uHaloTop: halo === null ? "transparent" : halo.stops[0]
    property color uHaloUpper: halo === null ? "transparent" : halo.stops[1]
    property color uHaloLower: halo === null ? "transparent" : halo.stops[2]
    property color uHaloBottom: halo === null ? "transparent" : halo.stops[3]
    fragmentShader: Qt.resolvedUrl("shaders/radialbackdrop.frag.qsb")
}
