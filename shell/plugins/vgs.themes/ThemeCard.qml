import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Ui
import "BrowserLogic.js" as BrowserLogic
import "Files.js" as Files

// One theme's card on the browser's rail. A slice shows the theme's eight
// colours (BrowserLogic.SWATCHES) stacked top to bottom and the theme's
// name up the slice, reading upward from `carousel.sliceName.inset` above
// its bottom edge, in the `carousel.sliceName` text and shadow, which no
// mode changes: the shadow keeps the name readable on every colour of the
// stack. The side card's dim washes the stack; the name sits in the card's
// foreground, over the wash, so neither the dim nor a hover's lighter dim
// reaches its colour or its shadow. The name runs along the slice's
// slanted axis, so it lies parallel to both slanted edges and its gap from
// each is the same at every height, bottom-anchored or not: half of the
// slice's width less its lean, times the cosine of the slant, less half the
// name's line box, at the carousel's unit. The selected card shows the
// package's preview image when one ships, else the theme's first wallpaper
// over its background, else its background and name, and the eight
// colours across its foot. A card with no colours, a refused
// package's, names its theme instead, across the card at its centre; that
// name keeps the card's lean from each side, which clears the angled edge
// at mid-height for every unit up to `carousel.maxScale` 2, where the drawn
// lean is twice the token. Every built card loads its image at the
// carousel's decodeSize, so a step finds the next card's picture decoded. A
// Spinner turns over the card while the browser installs or applies its
// theme.
Item {
    id: root

    // The card BrowserLogic.cards built for this theme, with the view's
    // `generation`, the stamp its image loads under.
    required property var modelData
    required property size decodeSize
    // Whether this is the centre card. The carousel sets it only for
    // delegates that declare it.
    property bool current: false
    // The card's layer over its dim wash, which the carousel hands only to
    // delegates that declare it; null draws the name with the rest of the
    // card.
    property Item foreground: null
    // Whether the browser is installing, applying or downloading for this
    // theme.
    property bool busy: false

    readonly property var colors: modelData.palette
    readonly property var swatches: BrowserLogic.swatches(modelData.palette, modelData.tokens)
    readonly property bool packagePreview: typeof modelData.previewImage === "string" && modelData.previewImage !== ""
    // An accepted package with no preview draws its own backdrop: its
    // wallpaper, else its background and name.
    readonly property bool backdrop: !packagePreview && modelData.state === "ok"
    // The first wallpaper: the package's first image.
    readonly property string wallpaper: typeof modelData.image === "string" ? modelData.image : ""
    readonly property string image: packagePreview ? modelData.previewImage : backdrop ? wallpaper : ""
    readonly property bool expanded: current && (packagePreview || backdrop)
    // The image the card draws, "" for none: a slice draws none.
    readonly property string picture: expanded ? image : ""
    // The slant of a slice's axis from the vertical. The slant is the
    // card's lean over its height, which the carousel scales by one unit,
    // so the token ratio gives the drawn angle.
    readonly property real lean: Math.atan2(Theme.angledCard.skew, Theme.carousel.sliceHeight)

    anchors.fill: parent

    Rectangle {
        anchors.fill: parent
        visible: root.expanded && root.backdrop
        color: root.colors === null ? Theme.color.surface : Theme.toColor(root.colors.background)
    }

    Image {
        id: picture
        anchors.fill: parent
        visible: root.expanded && status !== Image.Null && status !== Image.Error
        source: root.image === "" ? "" : Files.stampedUrl(root.image, root.modelData.generation)
        sourceSize: root.decodeSize
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        onStatusChanged: if (status === Image.Error) console.warn("themes: card image unreadable path=" + root.image)
    }

    ThemePaletteStrip {
        objectName: "paletteStack"
        anchors.fill: parent
        visible: !root.expanded && root.swatches !== null
        vertical: true
        colours: root.swatches === null ? [] : root.swatches
    }

    // The name turns about its start, which stands the inset up the axis
    // from the bottom edge's centre, where the axis meets that edge half the
    // drawn lean in from the slice's width. It is as long as its text, up
    // to the axis less the inset at each end, where it elides.
    Label {
        id: sliceName
        objectName: "sliceName"
        readonly property real inset: Theme.carousel.sliceName.inset
        parent: root.foreground ?? root
        role: Theme.carousel.sliceName.role
        x: (parent.width - parent.height * Math.tan(root.lean)) / 2 + inset * Math.sin(root.lean)
        y: parent.height - inset * Math.cos(root.lean) - height / 2
        width: Math.min(implicitWidth, parent.height / Math.cos(root.lean) - 2 * inset)
        transformOrigin: Item.Left
        rotation: root.lean * 180 / Math.PI - 90
        visible: !root.expanded && root.swatches !== null
        elide: Text.ElideRight
        text: root.modelData.label
        color: Theme.carousel.sliceName.foreground
        layer.enabled: visible
        layer.smooth: true
        // MultiEffect (doc.qt.io/qt-6/qml-qtquick-effects-multieffect.html):
        // shadowBlur 1 is the full blur blurMax allows, so the shadow blurs
        // exactly the token's pixels. The shadow offsets are in the effect's
        // own frame, which a layer's effect shares with its item, so the
        // screen's down-right offset is turned back through the name's
        // rotation (the theme-browser shots show it falling down and right).
        // Automatic padding covers blurMax alone and an offset shadow would
        // be clipped, so the padding is set by hand: the blur plus the
        // offset's length on every side.
        layer.effect: MultiEffect {
            readonly property real offset: Theme.carousel.sliceName.shadowOffset
            readonly property real turn: sliceName.rotation * Math.PI / 180
            readonly property real padding: Math.ceil(blurMax + offset * Math.SQRT2)
            objectName: "sliceNameShadow"
            shadowEnabled: true
            shadowColor: Theme.carousel.sliceName.shadow
            shadowOpacity: Theme.carousel.sliceName.shadowOpacity
            blurMax: Theme.carousel.sliceName.blur
            shadowBlur: 1
            shadowHorizontalOffset: offset * (Math.cos(turn) + Math.sin(turn))
            shadowVerticalOffset: offset * (Math.cos(turn) - Math.sin(turn))
            autoPaddingEnabled: false
            paddingRect: Qt.rect(padding, padding, padding, padding)
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: (root.swatches === null || root.expanded && root.backdrop) && !(root.expanded && picture.visible)
        color: root.colors === null ? Theme.color.surface : Theme.toColor(root.colors.background)

        Label {
            role: "bodyStrong"
            anchors.centerIn: parent
            width: parent.width - 2 * Theme.angledCard.skew
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: root.modelData.label
            color: root.colors === null ? Theme.color.textMuted : Theme.toColor(root.colors.foreground)
        }
    }

    ThemePaletteStrip {
        objectName: "paletteStrip"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Theme.space.xxl
        visible: root.expanded && root.swatches !== null
        colours: root.swatches === null ? [] : root.swatches
    }

    Spinner {
        anchors.centerIn: parent
        visible: root.busy
    }
}
