import QtQuick
import Quickshell
import qs.Commons

// Glass, the one shared glass material, or the standard surface. A surface
// names its Glass page row, `surface` (ThemeLogic.GLASS_SURFACES, or
// "controls" for a control that follows its card), and the one deciding
// place answers whether glass is on for it and in which style
// (Theme.glassFor); no surface reads a glass setting of its own. While glass
// is on, one pass (shaders/glasslens.frag) draws the body's tint in the
// style's values (`look`), the neutral rim, one thin line at the edge, and
// the edge light, two lights that orbit the surface and catch on the rim.
// Every layer takes the surface's whole geometry and `radius`, so all of
// them round to the same corner: `clip` cuts only to the bounding box, and
// a layer of another size rounds to another corner that shows past the
// surface's curve. The compositor blurs what is behind it when a layer
// rule asks it to, which reaches only what lies under the surface's own
// window: glass is `drawn` where it is on, its style may show the backdrop
// in this window (Clear needs a material window and the compositor's layer
// glass, ThemeLogic.glassFor) and nothing its window draws lies under it.
// Glass that is on but not drawn is `solid`: the body made opaque and
// lifted (Theme.glassSolid), at the same corner under the rim, with no
// moving light, so it hides the content under it and keeps the style's hue
// and shape. While glass is off, it draws `standard`, the surface's own
// look without glass: a token group's `background` and `border` at its
// `radius`, the raised surface's unless the surface hands its own, such as
// `Theme.popover`. `follow` lays it under another item, taking that item's
// geometry, opacity, scale and transform origin. Children go into the
// clipped body, above the tint and the rim.
Item {
    id: glass

    required property string surface
    // The window's own answer to whether the compositor's layer glass
    // reaches it at the Clear body's alpha: a host that offers it sets
    // `glassMaterial` (LayerHost.qml, SummonLayer.qml). Quickshell's
    // QsWindow attached object names the item's Quickshell window, null in a
    // plain Qt window (Quickshell 0.3.1, QsWindow attached).
    readonly property bool material: QsWindow.window !== null && QsWindow.window.glassMaterial === true
    readonly property var decision: Theme.glassFor(surface, material)
    readonly property bool on: decision.on
    // The material in the surface's style: the Glass page's on a styled
    // surface, the theme's mode on any other (ThemeLogic.glassFor).
    readonly property var look: decision.style === Theme.glassStyle ? Theme.glass : Theme.themeGlass
    // A surface whose text must read over any backdrop, such as a floating
    // card, hands true: it never draws translucent glass, and draws solid
    // while glass is on wherever it lies.
    property bool solidOnly: false
    // Whether glass is drawn: on, drawable in this window, not `solidOnly`,
    // in a window whose own colour is transparent, as every VGS layer and
    // popup is, and over nothing that window draws (overContent). Under a
    // surface drawn over its window's own content, a dialog inline in a
    // page, a menu over a glass card or a card in an application window,
    // that content would show through unblurred.
    // `on` comes first, so a surface without glass reads none of its
    // window's items.
    readonly property bool drawn: on && decision.drawable && !solidOnly && Window.window !== null && Window.window.color.a === 0 && !overContent()
    // Glass that is on but not drawn: its fill made opaque hides the
    // content under it.
    readonly property bool solid: on && !drawn
    // The markers overContent reads to find a GlassSurface among the items
    // under another, and Scrim.qml has its own `scrim`.
    readonly property bool glassSurface: true
    default property alias content: body.data
    readonly property color fill: decision.themed ? look.glass.themed : look.glass.fill
    // The body fill before a translucent window meets its backdrop.
    readonly property color effectiveFill: drawn ? fill : solid ? Theme.glassSolid(fill, look) : standard.background
    // The ground a shared key hint inside this surface reads on, published
    // to its descendants (HintGround.js): drawn glass made opaque, as the
    // theme judge reads list text on glass (Theme.hintContext), else the
    // body fill.
    readonly property color hintGround: drawn ? Theme.glassSolid(fill, look) : effectiveFill
    // The look without glass of a surface that hands none.
    readonly property var raised: ({ background: Theme.surface.level.raised.background, border: Theme.surface.level.raised.border, radius: Theme.surface.radius })
    property var standard: raised
    // The corner while glass is on: the standard look's, which is the
    // role's own token, unless the surface hands one. A surface that hands
    // neither has no role token and takes the glass corner. A `var`
    // property answers the object its binding answered, so `===` tells the
    // look no surface handed (a run under qmltestrunner, Qt 6.11.2).
    property real radius: standard === raised ? Theme.radius.glass : standard.radius
    property Item follow: null
    property real padding: 0
    // `lit` blends only the edge lights to the theme's accent, leaving
    // the static rim neutral even on a critical notification; `edgeBoost`
    // multiplies both lights and `edgeSpin` adds orbits a second;
    // `edgeShown` false hides it. A surface that can stay up all day sets
    // `paced`, and the light moves at most its material's `edge.frameRate`
    // frames a second.
    property bool lit: false
    property real edgeBoost: 1
    property real edgeSpin: 0
    property bool edgeShown: true
    property bool paced: false
    // The rim's drawn width while glass is on, held to a quarter of the
    // surface's short side.
    readonly property real rim: on ? Math.min(glass.look.rim.width, Math.min(width, height) / 4) : 0
    // Where content starts: inside the rim, where the pass draws the fill
    // alone, so an ink's ground is that fill.
    readonly property real contentInset: Math.max(padding, rim)
    // The corner the body rounds to while glass is on, drawn or solid:
    // `radius` as a real radius, which a pill-shaped radius larger than a
    // side needs; while it is off, the standard look's.
    readonly property real corner: on ? Math.min(radius, width / 2, height / 2) : standard.radius
    // Whether the edge light moves: on drawn glass that shows, while the
    // theme's motion scale is above 0.
    readonly property bool lightsShown: drawn && edgeShown
    readonly property bool lightsRunning: lightsShown && visible && opacity > 0 && glass.look.motion.scale > 0 && orbitLength > 0

    // Whether this window draws something glass would show unblurred under
    // this surface. Walking from the surface up through its ancestors: an
    // ancestor that is a GlassSurface, or, at each level, a sibling of that
    // level's item painted under it that is visible, has an opacity above 0,
    // overlaps it and is a GlassSurface or a Scrim whose `overContent` holds.
    // Qt paints a lower `z` first and, at the same `z`, the earlier item in
    // `children` first (Qt 6 Item.z reference). Overlap compares x, y, width
    // and height in the shared parent's coordinates; a transform or scale is
    // not read. A sibling's other properties are read only after its marker
    // matched, so a long list binds this to its items' markers alone; the
    // binding reads each level's `children`, so it runs again when they
    // change.
    function overContent() {
        for (let at = glass; at.parent !== null; at = at.parent) {
            const level = at.parent;
            if (level.glassSurface === true) return true;
            const kids = level.children;
            let index = 0;
            while (index < kids.length && kids[index] !== at) index++;
            for (let i = 0; i < kids.length; i++) {
                const other = kids[i];
                if (other === at || (other.glassSurface !== true && other.scrim !== true)) continue;
                if (other.z > at.z || (other.z === at.z && i > index)) continue;
                if (!other.visible || other.opacity <= 0) continue;
                if (other.x >= at.x + at.width || at.x >= other.x + other.width || other.y >= at.y + at.height || at.y >= other.y + other.height) continue;
                if (other.glassSurface === true) return true;
                if (other.overContent === true) return true;
            }
        }
        return false;
    }

    // The edge lights' orbit: a rounded box `lift` outside the surface.
    // Phase is a share of its length, so the lights hold their place while
    // the surface resizes; `clock` drives the pace's wobble. Each starts at
    // a random place, so two surfaces never shine in step.
    property real phase: Math.random()
    property real clock: Math.random() * 100
    readonly property real orbitRadius: corner + glass.look.edge.lift
    readonly property real orbitW: Math.max(0, width - 2 * corner)
    readonly property real orbitH: Math.max(0, height - 2 * corner)
    readonly property real orbitLength: 2 * (orbitW + orbitH) + 2 * Math.PI * orbitRadius
    readonly property vector2d lightA: orbitPoint(phase)
    // The counter light trails half an orbit behind, drifting a little.
    readonly property vector2d lightB: orbitPoint(phase + 0.5 + 0.045 * Math.sin(clock / 5.3))

    // The point on the orbit at share F of its length, clockwise from the
    // top-left of the top edge, from the surface's centre.
    function orbitPoint(f) {
        const w = orbitW, h = orbitH, r = orbitRadius, arc = Math.PI * r / 2;
        let s = ((f % 1) + 1) % 1 * orbitLength;
        const hw = w / 2, hh = h / 2;
        if (s < w) return Qt.vector2d(-hw + s, -hh - r);
        s -= w;
        if (s < arc) return Qt.vector2d(hw + r * Math.sin(s / r), -hh - r * Math.cos(s / r));
        s -= arc;
        if (s < h) return Qt.vector2d(hw + r, -hh + s);
        s -= h;
        if (s < arc) return Qt.vector2d(hw + r * Math.cos(s / r), hh + r * Math.sin(s / r));
        s -= arc;
        if (s < w) return Qt.vector2d(hw - s, hh + r);
        s -= w;
        if (s < arc) return Qt.vector2d(-hw - r * Math.sin(s / r), hh + r * Math.cos(s / r));
        s -= arc;
        if (s < h) return Qt.vector2d(-hw - r, hh - s);
        s -= h;
        return Qt.vector2d(-hw - r * Math.cos(s / r), -hh - r * Math.sin(s / r));
    }

    // Moves the lights on by DT seconds, a long frame capped so a stall
    // never jumps them, at an uneven pace: two slow, unrelated waves on the
    // mean speed.
    function advance(dt) {
        const step = Math.min(dt, 0.05);
        clock += step;
        const pace = 1 + 0.3 * Math.sin(clock * 0.83) + 0.12 * Math.sin(clock * 2.1 + 1.3);
        phase = (phase + step * (glass.look.edge.speed * pace / orbitLength + edgeSpin)) % 1;
    }

    Binding on x { when: glass.follow !== null; value: glass.follow ? glass.follow.x : 0 }
    Binding on y { when: glass.follow !== null; value: glass.follow ? glass.follow.y : 0 }
    Binding on width { when: glass.follow !== null; value: glass.follow ? glass.follow.width : 0 }
    Binding on height { when: glass.follow !== null; value: glass.follow ? glass.follow.height : 0 }
    Binding on opacity { when: glass.follow !== null; value: glass.follow ? glass.follow.opacity : 1 }
    Binding on scale { when: glass.follow !== null; value: glass.follow ? glass.follow.scale : 1 }
    Binding on transformOrigin { when: glass.follow !== null; value: glass.follow ? glass.follow.transformOrigin : Item.Center }

    Rectangle {
        id: body
        anchors.fill: parent
        radius: glass.corner
        color: glass.on ? "transparent" : glass.standard.background
        clip: true
    }

    // The standard border sits above the content, so no row covers it.
    Rectangle {
        visible: !glass.on
        anchors.fill: parent
        radius: body.radius
        color: "transparent"
        border.width: Theme.surface.border
        border.color: glass.standard.border
    }

    // The glass pass, built only while glass is on. Qt paints a lower `z`
    // first (Qt 6 Item.z reference), so it draws under the body's content,
    // whatever its place among the children.
    Loader {
        id: pass
        // One pixel outside the surface holds the edge's antialiasing.
        readonly property real reach: 1
        active: glass.on
        z: -1
        x: -reach
        y: -reach
        width: parent.width + 2 * reach
        height: parent.height + 2 * reach
        sourceComponent: ShaderEffect {
            blending: true
            property vector2d uSize: Qt.vector2d(glass.width, glass.height)
            property real uRadius: glass.corner
            property real uMargin: pass.reach
            property real uRim: glass.rim
            property color uTint: glass.effectiveFill
            property vector4d uRimLight: Qt.vector4d(glass.look.rim.glint, glass.look.rim.ambient, glass.look.rim.far, glass.look.edge.glow)
            property vector2d uLightA: glass.lightA
            property vector2d uLightB: glass.lightB
            property vector4d uEdge: Qt.vector4d(glass.look.edge.strengthA * glass.edgeBoost, glass.look.edge.strengthB * glass.edgeBoost,
                glass.look.edge.reach, glass.lightsShown ? 1 : 0)
            property color uNeutral: glass.look.edge.neutral
            property color uAccent: glass.look.palette.accent
            property real uLit: glass.litShare
            fragmentShader: Qt.resolvedUrl("shaders/glasslens.frag.qsb")
        }
    }

    property real litShare: lit ? 1 : 0
    Behavior on litShare { NumberAnimation { duration: Theme.motion.duration.slow; easing.type: Theme.motion.easing.standard } }

    FrameAnimation {
        running: glass.lightsRunning && !glass.paced
        onTriggered: glass.advance(frameTime)
    }

    // A paced light draws at most the table's frame rate. The step is the
    // time since the last one, read from the clock, so a late timer never
    // slows the light.
    Timer {
        property real last: 0
        running: glass.lightsRunning && glass.paced
        repeat: true
        interval: Math.round(1000 / glass.look.edge.frameRate)
        onRunningChanged: last = Date.now()
        onTriggered: {
            const now = Date.now();
            glass.advance((now - last) / 1000);
            last = now;
        }
    }
}
