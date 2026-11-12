import QtQuick
import QtQuick.Effects
import qs.Commons

// VGlass, the one shared glass look, or the standard surface. The
// material is the lens form, which a surface that hands `lens` draws: the
// tinted body over the compositor's blur and a clear rim band with its
// light, in one pass (shaders/glasslens.frag). A surface that hands none
// still draws the flat form while `drawn`: a soft drop shadow, a
// translucent fill, a faint top-down sheen and a hairline inner edge.
// Every value is from `Theme.glass` or what the surface hands: its own
// `fill`, `radius`, `elevation` and `lens`. Every layer
// takes the surface's whole geometry and `radius`, so all of them round to
// the same corner: `clip` cuts only to the bounding box, and a layer of
// another size rounds to another corner that shows past the surface's
// curve. The compositor blurs what is behind it when a layer rule asks it
// to, which reaches only what lies under the surface's own window: glass
// is `drawn` where it is `on` and nothing its window draws lies under it.
// Glass that is `on` but not drawn is `solid`: the same fill made opaque
// and lifted (Theme.glassSolid), at the same corner under the hairline,
// with no shadow or sheen, so it hides the content under it and keeps the
// surface's hue and shape. While glass is off, it draws `standard`, the
// surface's own look without glass: a token group's `background` and
// `border` at its `radius`, the raised surface's unless the surface hands
// its own, such as `Theme.popover`, with no shadow, sheen or hairline.
// `optIn` is the surface's own VGlass choice; the user's Appearance values
// decide `on` from it (ThemeLogic.glassOn). `follow` lays it under another
// item, taking that item's geometry, opacity, scale and transform origin.
// Children go into the clipped body, above the sheen and below the
// hairline.
Item {
    id: glass

    property bool optIn: false
    readonly property bool on: Theme.glassOn(optIn)
    // A surface whose text must read over any backdrop, such as a tooltip,
    // hands true: it never draws translucent glass, and draws solid while
    // glass is on wherever it lies.
    property bool solidOnly: false
    // Whether glass is drawn: `on`, not `solidOnly`, in a window whose own
    // colour is transparent, as every VGS layer and popup is, and over
    // nothing that window draws (overContent). Under a surface drawn over
    // its window's own content, a dialog inline in a page, a menu over a
    // glass card or a card in an application window, that content would
    // show through unblurred.
    // `on` comes first, so a surface without glass reads none of its
    // window's items.
    readonly property bool drawn: on && !solidOnly && Window.window !== null && Window.window.color.a === 0 && !overContent()
    // Glass that is on but not drawn: its fill made opaque hides the
    // content under it.
    readonly property bool solid: on && !drawn
    // The markers overContent reads to find a GlassSurface among the items
    // under another, and Scrim.qml has its own `scrim`.
    readonly property bool glassSurface: true
    default property alias content: body.data
    property color fill: Theme.glass.glass.fill
    // The body fill before a translucent window meets its backdrop.
    readonly property color effectiveFill: drawn ? fill : solid ? Theme.glassSolid(fill) : standard.background
    // The ground a shared key hint inside this surface reads on, published
    // to its descendants (HintGround.js): drawn glass made opaque, as the
    // theme judge reads list text on glass (Theme.hintContext), else the
    // body fill.
    readonly property color hintGround: drawn ? Theme.glassSolid(fill) : effectiveFill
    // The look without glass of a surface that hands none.
    readonly property var raised: ({ background: Theme.surface.level.raised.background, border: Theme.surface.level.raised.border, radius: Theme.surface.radius })
    property var standard: raised
    // The corner while glass is on: the standard look's, which is the
    // role's own token, unless the surface hands one. A surface that hands
    // neither has no role token and takes the glass corner. A `var`
    // property answers the object its binding answered, so `===` tells the
    // look no surface handed (a run under qmltestrunner, Qt 6.11.2).
    property real radius: standard === raised ? Theme.radius.glass : standard.radius
    // `wide` for a large card, `tight` for a small transient surface: a
    // group of `Theme.glass.shadow`. One the table lacks is logged and
    // drawn as wide. `none` draws no shadow, for a plate whose rim alone
    // marks its edge on the wallpaper.
    property string elevation: "wide"
    readonly property var shadow: elevation === "none" ? null : shadowOf(elevation)
    // Cache the shadow only for a surface that keeps its size; a resizing
    // or morphing surface would rebuild the cache every frame.
    property bool shadowCached: true
    property Item follow: null
    property real padding: 0
    // The lens form: a surface that hands its look's lens values draws the
    // lens pass (shaders/glasslens.frag) in place of the sheen and the
    // hairline while glass is on: `bezel`, the rim band's width;
    // `clarity`, the share of the tint the band loses, which takes it
    // under the layer rule's blur threshold; `glint` and `glow`, the light
    // on the rim and inside it; `exit`, the share of that light the far
    // wall takes; `outline`, the dark line outside the rim; and `seam`,
    // the line where the band meets the body. Solid glass draws the same
    // pass over its opaque fill with no clear band. While glass is off no
    // pass draws.
    property var lens: null
    readonly property bool lensed: on && lens !== null
    // The band's drawn width: the handed bezel, held to the corner and to
    // a quarter of the surface's short side, and never under a pixel.
    readonly property real bezel: lensed ? Math.max(1, Math.min(lens.bezel, corner, Math.min(width, height) / 4)) : 0
    // Where content starts: inside the band, where the pass draws the fill
    // alone, so an ink's ground is that fill.
    readonly property real contentInset: Math.max(padding, bezel)
    // The corner the body rounds to while glass is on, drawn or solid:
    // `radius` as a real radius, which a pill-shaped radius larger than a
    // side needs for the shadow; while it is off, the standard look's.
    readonly property real corner: on ? Math.min(radius, width / 2, height / 2) : standard.radius

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

    function shadowOf(name) {
        const found = Theme.glass.shadow[name];
        if (found !== undefined) return found;
        console.error("GlassSurface: no elevation named " + JSON.stringify(name));
        return Theme.glass.shadow.wide;
    }

    Binding on x { when: glass.follow !== null; value: glass.follow ? glass.follow.x : 0 }
    Binding on y { when: glass.follow !== null; value: glass.follow ? glass.follow.y : 0 }
    Binding on width { when: glass.follow !== null; value: glass.follow ? glass.follow.width : 0 }
    Binding on height { when: glass.follow !== null; value: glass.follow ? glass.follow.height : 0 }
    Binding on opacity { when: glass.follow !== null; value: glass.follow ? glass.follow.opacity : 1 }
    Binding on scale { when: glass.follow !== null; value: glass.follow ? glass.follow.scale : 1 }
    Binding on transformOrigin { when: glass.follow !== null; value: glass.follow ? glass.follow.transformOrigin : Item.Center }

    RectangularShadow {
        visible: glass.drawn && glass.elevation !== "none"
        z: -2
        anchors.fill: parent
        radius: glass.corner
        blur: glass.shadow === null ? 0 : glass.shadow.blur
        spread: glass.shadow === null ? 0 : glass.shadow.spread
        offset: Qt.vector2d(0, glass.shadow === null ? 0 : glass.shadow.offsetY)
        color: glass.shadow === null ? "transparent" : glass.shadow.color
        cached: glass.shadowCached
    }

    Rectangle {
        id: body
        anchors.fill: parent
        radius: glass.corner
        color: glass.lensed ? "transparent" : glass.effectiveFill
        clip: true

        // Light falling on the top of the glass, fading out `sheenHeight`
        // down, under the fill.
        Rectangle {
            visible: glass.drawn && !glass.lensed
            anchors.fill: parent
            radius: glass.radius
            z: -1
            gradient: Gradient {
                GradientStop { position: 0; color: Theme.glass.glass.sheen }
                GradientStop { position: Math.min(1, Theme.glass.glass.sheenHeight / glass.height); color: Theme.glass.glass.sheenEnd }
            }
        }
    }

    // The hairline, or the standard border, sits above the content, so no
    // row covers it.
    Rectangle {
        visible: !glass.lensed
        anchors.fill: parent
        radius: body.radius
        color: "transparent"
        border.width: glass.on ? Theme.glass.glass.hairlineWidth : Theme.surface.border
        border.color: glass.on ? Theme.glass.glass.hairline : glass.standard.border
    }

    // The lens pass, built only for a surface that hands a lens, so a
    // flat surface holds none of it. Qt paints a lower `z` first (Qt 6
    // Item.z reference), so it draws over the drop shadow and under the
    // body's content, whatever its place among the children.
    Loader {
        id: pass
        // The dark line lies in the two pixels outside the surface.
        readonly property real reach: 2
        active: glass.lens !== null
        visible: glass.lensed
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
            property color uTint: glass.effectiveFill
            property vector4d uLens: glass.lens === null ? Qt.vector4d(0, 0, 0, 0)
                : Qt.vector4d(glass.bezel, glass.solid ? 0 : glass.lens.clarity, glass.lens.glint, glass.lens.glow)
            property vector4d uLight: glass.lens === null ? Qt.vector4d(0, 0, 0, 0)
                : Qt.vector4d(glass.lens.exit, glass.lens.outline, glass.lens.seam, 0)
            fragmentShader: Qt.resolvedUrl("shaders/glasslens.frag.qsb")
        }
    }
}
