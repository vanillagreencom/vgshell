import QtQuick
import qs.Commons
import qs.Ui
import "Files.js" as Files

// Load images under the view's generation so replacing a file at the
// same path decodes it again. Keep side-card names and icons above the
// dim wash so the wash fades neither. Inset the centre label by the
// card's lean to clear the angled edges.
Item {
    id: root

    // The card BrowserLogic.wallpaperCards built, with the view's
    // `generation`.
    required property var modelData
    required property size decodeSize
    property bool busy: false
    // Whether this is the centre card, and the card's layer over its dim
    // wash. The carousel sets each only for delegates that declare it.
    property bool current: false
    property Item foreground: null

    readonly property bool offer: modelData.kind !== "image"
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

    // Centre the capitals rather than the line box: leading and descent
    // would set the name low. Use button.radius so the name plate follows
    // the user's control corner radius.
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
