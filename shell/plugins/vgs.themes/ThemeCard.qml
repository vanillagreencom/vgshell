import QtQuick
import qs.Commons
import qs.Ui
import "BrowserLogic.js" as BrowserLogic
import "Files.js" as Files

// One theme's card on the browser's rail. A slice shows the theme's eight
// colours (BrowserLogic.SWATCHES) stacked top to bottom and the theme's
// name along its slanted edge, reading upward, in the shell's heading text
// over a 1 px hard shadow in the shell's background: the side card's dim
// mixes the stack toward that background, so the name keeps its contrast
// on every colour and in either mode. The selected card
// shows the package's preview image when one ships, else the theme's first
// wallpaper over its background with a desktop drawn from the package's
// tokens on it, and the eight colours across its foot. A card with no
// colours, a refused package's, names its theme instead; the name keeps
// the card's lean from each side, which clears the angled edge at
// mid-height for every unit up to `carousel.maxScale` 2, where the drawn
// lean is twice the token. Every built card loads its image at the
// carousel's decodeSize, so a step finds the next card's picture decoded.
// A Spinner turns over the card while the browser installs or applies its
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
    // Whether the browser is installing, applying or downloading for this
    // theme.
    property bool busy: false

    readonly property var colors: modelData.palette
    readonly property var swatches: BrowserLogic.swatches(modelData.palette, modelData.tokens)
    readonly property bool packagePreview: typeof modelData.previewImage === "string" && modelData.previewImage !== ""
    readonly property bool live: !packagePreview && modelData.state === "ok"
    // The first wallpaper: the package's first image or the catalog
    // wallpaper on disk, else the one the browser fetched for this card.
    readonly property string wallpaper: typeof modelData.image === "string" ? modelData.image : typeof modelData.sharpenedImage === "string" ? modelData.sharpenedImage : ""
    readonly property string image: packagePreview ? modelData.previewImage : live ? wallpaper : ""
    readonly property bool expanded: current && (packagePreview || live)
    // The image the card draws, "" for none: a slice draws none.
    readonly property string picture: expanded ? image : ""

    anchors.fill: parent

    Rectangle {
        anchors.fill: parent
        visible: root.expanded && root.live
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

    Loader {
        id: preview
        anchors.fill: parent
        active: root.expanded && root.live
        visible: status === Loader.Ready
        asynchronous: true
        sourceComponent: DesktopPreview {
            tokens: root.modelData.tokens
            terminal: root.modelData.terminal
            name: root.modelData.name
            label: root.modelData.label
            footHeight: Theme.space.xxl
        }
    }

    ThemePaletteStrip {
        objectName: "paletteStack"
        anchors.fill: parent
        visible: !root.expanded && root.swatches !== null
        vertical: true
        colours: root.swatches === null ? [] : root.swatches
    }

    // The slant is the card's lean over its height, which the carousel
    // scales by one unit, so the token ratio gives the drawn angle.
    Label {
        objectName: "sliceName"
        role: "h3"
        anchors.centerIn: parent
        width: parent.height - 2 * Theme.space.xl
        visible: !root.expanded && root.swatches !== null
        rotation: Math.atan2(Theme.angledCard.skew, Theme.carousel.sliceHeight) * 180 / Math.PI - 90
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        text: root.modelData.label
        style: Text.Raised
        styleColor: Theme.color.background
    }

    Rectangle {
        anchors.fill: parent
        visible: root.swatches === null && !(root.expanded && picture.visible)
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
