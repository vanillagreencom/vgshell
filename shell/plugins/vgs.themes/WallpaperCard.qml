import QtQuick
import qs.Commons
import qs.Ui
import "Files.js" as Files

// One card on the wallpaper browser's rail: an image card draws its image,
// decoded at the size the carousel hands it and loaded under the view's
// generation, so a file replaced under its name is read again. An image
// card while its image loads or when it cannot be read fills with the
// surface colour under an image icon. The download or update card fills
// the same way and names itself: the centre card under its icon, the
// name keeping the card's lean from each side, as the theme card's does,
// and a side card up the slice's slanted axis from
// `carousel.sliceName.inset` above its bottom edge, where the whole line
// fits, its icon `stack.group` past the line's end on that axis, both in
// the card's layer over its dim wash, so the wash fades neither. A
// Spinner turns
// over the card while the browser sets its image or runs its download.
Item {
    id: root

    // The card BrowserLogic.wallpaperCards built, with the view's
    // `generation`.
    required property var modelData
    required property size decodeSize
    // Whether the browser is setting this image or running this card's
    // download.
    property bool busy: false
    // Whether this is the centre card, and the card's layer over its dim
    // wash. The carousel sets each only for delegates that declare it.
    property bool current: false
    property Item foreground: null

    readonly property bool offer: modelData.kind !== "image"
    // Whether this is a download or update card beside the centre one.
    readonly property bool side: offer && !current
    readonly property bool named: !offer && typeof modelData.name === "string" && modelData.name !== ""

    anchors.fill: parent

    Rectangle {
        anchors.fill: parent
        visible: image.status !== Image.Ready
        color: Theme.color.surface

        Column {
            anchors.centerIn: parent
            width: parent.width - 2 * Theme.angledCard.skew
            spacing: Theme.stack.group

            Icon {
                id: mark
                anchors.horizontalCenter: parent.horizontalCenter
                visible: !root.side
                name: root.modelData.kind === "download" ? "download" : root.modelData.kind === "update" ? "refresh-cw" : "image"
                size: Theme.icon.size.xl
                color: Theme.color.textMuted
            }

            Label {
                role: "bodyStrong"
                visible: root.offer && root.current
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideMiddle
                text: root.offer ? root.modelData.label : ""
                color: Theme.color.textMuted
            }
        }
    }

    // The side card's name turns about its start, as ThemeCard's slice
    // name does: the start stands the inset up the axis from the bottom
    // edge's centre.
    Label {
        readonly property real inset: Theme.carousel.sliceName.inset
        readonly property real lean: Math.atan2(Theme.angledCard.skew, Theme.carousel.sliceHeight)
        id: sideName
        objectName: "offerName"
        parent: root.foreground ?? root
        role: "bodyStrong"
        x: (parent.width - parent.height * Math.tan(lean)) / 2 + inset * Math.sin(lean)
        y: parent.height - inset * Math.cos(lean) - height / 2
        width: Math.min(implicitWidth, parent.height / Math.cos(lean) - 2 * inset - Theme.stack.group - mark.size)
        transformOrigin: Item.Left
        rotation: lean * 180 / Math.PI - 90
        visible: root.side
        elide: Text.ElideRight
        text: root.offer ? root.modelData.label : ""
    }

    // The side card's icon stands upright past its name's end, its centre
    // on the name's axis.
    Icon {
        readonly property real along: sideName.inset + sideName.width + Theme.stack.group + size / 2
        objectName: "offerMark"
        parent: sideName.parent
        x: (parent.width - parent.height * Math.tan(sideName.lean)) / 2 + along * Math.sin(sideName.lean) - size / 2
        y: parent.height - along * Math.cos(sideName.lean) - size / 2
        visible: root.side
        name: mark.name
        size: mark.size
        color: sideName.color
    }

    Image {
        id: image
        anchors.fill: parent
        visible: status === Image.Ready
        source: root.offer ? "" : Files.stampedUrl(root.modelData.path, root.modelData.generation)
        sourceSize: root.decodeSize
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        onStatusChanged: if (status === Image.Error) console.warn("themes: wallpaper card image unreadable path=" + root.modelData.path)
    }

    // The image's name in a box `carousel.namePadding` from its ink on every
    // side. The box is the capitals' height plus that padding above and
    // below, and the capitals start that padding under its top: the
    // label's line box holds leading above the capitals and the descent
    // below them, so centring the line box would set the name low. The
    // box fills with the card background at `carousel.nameFillOpacity`,
    // has no border, and rounds its corners by the Corner radius a user
    // sets for controls on the UI page (APPEARANCE.controlRadius in
    // ThemeLogic sets `button.radius`), square at 0.
    Item {
        id: nameBox
        readonly property real pad: Theme.carousel.namePadding
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.card.padding
        width: Math.min(parent.width - 2 * Theme.angledCard.skew, Math.ceil(nameLabel.implicitWidth) + 2 * pad)
        height: Math.round(nameLabel.lastBaseline() - nameLabel.capTop()) + 2 * pad
        visible: root.named

        Rectangle {
            anchors.fill: parent
            color: Theme.card.background
            opacity: Theme.carousel.nameFillOpacity
            radius: Theme.button.radius
        }

        Label {
            id: nameLabel
            x: nameBox.pad
            y: Math.round(nameBox.pad - capTop())
            width: parent.width - 2 * nameBox.pad
            role: "bodyStrong"
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: root.named ? root.modelData.name : ""
            color: Theme.color.text
        }
    }

    Spinner {
        anchors.centerIn: parent
        visible: root.busy
    }
}
