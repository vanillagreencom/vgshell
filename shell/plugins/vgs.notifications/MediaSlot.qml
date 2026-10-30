import QtQuick
import Quickshell.Widgets
import qs.Ui
import "NotificationLogic.js" as Logic

// The one slot a card's media sits in: a square `look.media.size` wide,
// whatever the media, so the text after it starts at the same x on every
// card. `kind` names what it draws:
// `faces`, the people `names` holds through the AvatarGroup of qs.Ui, one
// person as a circle that fills the slot; `thumbnail`, the image `source`
// cropped to the square with the slot's corner radius; `icon`, the
// application icon `source` drawn at the slot's icon size;
// `glyph`, the Lucide icon `glyph` names at the same icon size in
// `glyphColor`, the x-vgs-icon hint's. Every kind is centred in the square,
// whatever the card's text, so a symbol and an application icon share one
// size and one centre. `avatar` draws a round plugin glyph with an
// optional filled outcome badge staggered over its top-right corner.
// Automations opts into this exception to VGS-1613/VGS-1947; ordinary
// application and symbol icons retain their one size.
Item {
    id: slot

    required property var look
    property string kind: ""
    property string source: ""
    // The people, the count past them, one image per person where the
    // sender's cache knows one, and the image the notification carries,
    // which the first face shows when no per-person image is known.
    property var names: []
    property int more: 0
    property var images: []
    property string carried: ""
    property string glyph: ""
    property color glyphColor: look.text.foreground
    property string badgeGlyph: ""
    property string badgeTone: ""
    readonly property bool showsOutcome: badgeGlyph !== "" && badgeTone !== ""
    // Existing outcome hints also name an outlined circle; the filled
    // badge supplies that circle, so it draws only the inner mark.
    readonly property string outcomeGlyph: badgeGlyph === "circle-check" ? "check" : badgeGlyph === "circle-x" ? "x" : badgeGlyph
    readonly property var spec: look.media
    // False while the image or icon the slot draws failed to load, so the
    // card leaves the slot out.
    readonly property bool drawable: kind === "faces" || (kind === "thumbnail" && thumbnail.status !== Image.Error) || (kind === "icon" && icon.status !== Image.Error) || (kind === "glyph" && glyphIcon.paths[0] !== "") || (kind === "avatar" && avatarIcon.paths[0] !== "")

    function imageFor(index) {
        if (index < images.length && images[index] !== "") return images[index];
        return index === 0 ? carried : "";
    }

    implicitWidth: spec.size
    implicitHeight: spec.size

    AvatarGroup {
        visible: slot.kind === "faces"
        size: slot.spec.size
        people: slot.kind === "faces" ? slot.names.map((name, i) => ({ image: slot.imageFor(i), initials: Logic.initialsOf(name), tint: slot.look.face.tint[Logic.faceTint(name)] })) : []
        more: slot.kind === "faces" ? slot.more : 0
        faceShare: slot.look.face.share
        ringWidth: slot.look.face.ringWidth
        ring: slot.look.face.ring
        tint: slot.look.face.chip
        chip: slot.look.face.chip
        foreground: slot.look.text.foreground
        fontFamily: slot.look.font.family.sans
        initialsShare: slot.look.face.initials
        initialsWeight: slot.look.face.initialsWeight
    }

    ClippingRectangle {
        anchors.fill: parent
        visible: slot.kind === "thumbnail"
        radius: slot.spec.radius
        color: "transparent"

        Image {
            id: thumbnail
            anchors.fill: parent
            source: slot.kind === "thumbnail" ? slot.source : ""
            sourceSize.width: slot.spec.size * Screen.devicePixelRatio
            sourceSize.height: slot.spec.size * Screen.devicePixelRatio
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            smooth: true
        }
    }

    Image {
        id: icon
        anchors.centerIn: parent
        width: slot.spec.icon
        height: slot.spec.icon
        visible: slot.kind === "icon"
        source: slot.kind === "icon" ? slot.source : ""
        sourceSize.width: slot.spec.icon * Screen.devicePixelRatio
        sourceSize.height: slot.spec.icon * Screen.devicePixelRatio
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
    }

    Icon {
        id: glyphIcon
        anchors.centerIn: parent
        visible: slot.kind === "glyph"
        name: slot.kind === "glyph" ? slot.glyph : ""
        size: slot.spec.icon
        stroke: slot.look.card.glyphStroke
        color: slot.glyphColor
    }

    Rectangle {
        id: avatar
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        width: slot.spec.avatar.size
        height: width
        radius: slot.look.radius.full
        color: slot.spec.avatar.fill
        visible: slot.kind === "avatar"

        Icon {
            id: avatarIcon
            anchors.centerIn: parent
            name: slot.kind === "avatar" ? slot.glyph : ""
            size: slot.spec.avatar.icon
            stroke: slot.look.card.glyphStroke
            color: slot.look.text.foreground
        }
    }

    // Qt Quick paints later siblings over earlier ones; top/right anchors
    // keep the badge inside the media square while overlapping the avatar.
    // https://doc.qt.io/qt-6/qml-qtquick-item.html#z-prop
    Rectangle {
        anchors.top: parent.top
        anchors.right: parent.right
        width: slot.spec.outcome.size
        height: width
        radius: slot.look.radius.full
        visible: slot.showsOutcome
        color: visible ? slot.look.tone[slot.badgeTone] : "transparent"
        border.width: slot.spec.outcome.ringWidth
        border.color: slot.look.face.ring

        Icon {
            anchors.centerIn: parent
            name: slot.showsOutcome ? slot.outcomeGlyph : ""
            size: slot.spec.outcome.icon
            stroke: slot.look.card.glyphStroke
            color: slot.showsOutcome ? slot.spec.outcome.ink[slot.badgeTone] : slot.look.text.foreground
        }
    }
}
