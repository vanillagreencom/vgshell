import QtQuick
import QtQuick.Effects
import qs.Commons

// VGlass, the one shared glass look, or the standard surface. While
// `drawn`: a soft drop shadow, a translucent fill, a faint top-down sheen
// and a hairline inner edge, every value from `Theme.glass` or what the
// surface hands: its own `fill`, `radius` and `elevation`. Every layer
// takes the surface's whole geometry and `radius`, so all of them round to
// the same corner: `clip` cuts only to the bounding box, and a layer of
// another size rounds to another corner that shows past the surface's
// curve. The compositor blurs what is behind it when a layer rule asks it
// to, which reaches only what lies under the surface's own window: glass
// is `drawn` where it is `on` and is its window's `backdrop`. While not
// `drawn`, it draws `standard`, the surface's own look without glass: a
// token group's `background` and `border` at its `radius`, the raised
// surface's unless the surface hands its own, such as `Theme.popover`,
// with no shadow, sheen or hairline. `optIn` is the surface's own VGlass
// choice; the user's Appearance values decide `on` from it
// (ThemeLogic.glassOn). `follow` lays it under another item, taking that
// item's geometry, opacity, scale and transform origin. Children go into
// the clipped body, above the sheen and below the hairline.
Item {
    id: glass

    property bool optIn: false
    readonly property bool on: Theme.glassOn(optIn)
    // Whether the compositor's blur can reach what lies under this surface:
    // the first thing its window draws there, in a window whose own colour
    // is transparent, a VGS layer or popup, and inside no other
    // GlassSurface. Under a surface drawn over its window's own content, a
    // dialog inline in a page or a card in an application window, that
    // content shows through unblurred, so such a surface draws its standard
    // look. A sibling drawn under it in the same window is not read.
    readonly property bool backdrop: Window.window !== null && Window.window.color.a === 0 && !heldBy(parent)
    readonly property bool drawn: on && backdrop
    // What heldBy reads to find another GlassSurface among the ancestors.
    readonly property bool glassSurface: true
    default property alias content: body.data
    property color fill: Theme.glass.glass.fill
    property var standard: ({ background: Theme.surface.level.raised.background, border: Theme.surface.level.raised.border, radius: Theme.surface.radius })
    property real radius: standard.radius
    // `wide` for a large card, `tight` for a small transient surface: a
    // group of `Theme.glass.shadow`. One the table lacks is logged and
    // drawn as wide.
    property string elevation: "wide"
    readonly property var shadow: shadowOf(elevation)
    // Cache the shadow only for a surface that keeps its size; a resizing
    // or morphing surface would rebuild the cache every frame.
    property bool shadowCached: true
    property Item follow: null
    property real padding: 0
    readonly property real contentInset: padding
    // The corner the body rounds to: the handed radius as a real radius,
    // which a pill-shaped radius larger than a side needs for the shadow,
    // or the standard look's.
    readonly property real corner: drawn ? Math.min(radius, width / 2, height / 2) : standard.radius

    function heldBy(item) {
        for (let at = item; at !== null; at = at.parent)
            if (at.glassSurface === true) return true;
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
        visible: glass.drawn
        anchors.fill: parent
        radius: glass.corner
        blur: glass.shadow.blur
        spread: glass.shadow.spread
        offset: Qt.vector2d(0, glass.shadow.offsetY)
        color: glass.shadow.color
        cached: glass.shadowCached
    }

    Rectangle {
        id: body
        anchors.fill: parent
        radius: glass.corner
        color: glass.drawn ? glass.fill : glass.standard.background
        clip: true

        // Light falling on the top of the glass, fading out `sheenHeight`
        // down, under the fill.
        Rectangle {
            visible: glass.drawn
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
        anchors.fill: parent
        radius: body.radius
        color: "transparent"
        border.width: glass.drawn ? Theme.glass.glass.hairlineWidth : Theme.surface.border
        border.color: glass.drawn ? Theme.glass.glass.hairline : glass.standard.border
    }
}
