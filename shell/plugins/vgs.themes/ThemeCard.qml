import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Ui
import "BrowserLogic.js" as BrowserLogic
import "Files.js" as Files

// Keep the palette and name above the side card's dim wash so their
// colours and the name's shadow stay unchanged on hover. The shadow
// keeps the name readable over every palette colour.
// Align the name with the slice's slanted axis to keep its edge gaps equal.
// Inset a centred name by the card's lean to clear the angled edges.
// Load every built card at decodeSize so the next card is already decoded.
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
    // delegates that declare it; null draws the stack and the name with the
    // rest of the card.
    property Item foreground: null
    property bool busy: false

    readonly property var colors: modelData.palette
    readonly property var swatches: BrowserLogic.swatches(modelData.terminal)
    readonly property bool packagePreview: typeof modelData.previewImage === "string" && modelData.previewImage !== ""
    readonly property bool backdrop: !packagePreview && modelData.state === "ok"
    readonly property string wallpaper: typeof modelData.image === "string" ? modelData.image : ""
    readonly property string image: packagePreview ? modelData.previewImage : backdrop ? wallpaper : ""
    readonly property bool expanded: current && (packagePreview || backdrop)
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
        parent: root.foreground ?? root
        anchors.fill: parent
        visible: !root.expanded && root.swatches !== null
        columns: 2
        colours: root.swatches === null ? [] : root.swatches
    }

    Label {
        id: sliceName
        objectName: "sliceName"
        readonly property real inset: Theme.carousel.sliceName.inset
        parent: root.foreground ?? root
        // The carousel hands `foreground` after both are built, so the
        // stack and the name reparent in no set order; z keeps the name on
        // top.
        z: 1
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
        // shadowBlur 1 uses the full blurMax radius. Turn the screen's
        // down-right shadow offset back through the name's rotation because
        // the layer effect shares the item's frame.
        // Automatic padding covers blurMax alone; add the offset's length
        // on every side to prevent clipping the shadow.
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
        columns: 8
        colours: root.swatches === null ? [] : root.swatches
    }

    Spinner {
        anchors.centerIn: parent
        visible: root.busy
    }
}
