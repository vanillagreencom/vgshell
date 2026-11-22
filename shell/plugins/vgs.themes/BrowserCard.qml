import QtQuick
import qs.Commons
import qs.Ui
import "Files.js" as Files

// One card of a browser's rail, drawn the same in the theme and the
// wallpaper view: `picture` fills the card, cropped to it, over `ground`
// while it loads or when the card has none, and a spinner shows while
// `busy`. A view's card adds only what its own cards draw over that.
// Load the picture under the view's generation so replacing a file at the
// same path decodes it again.
Item {
    id: root

    // The card the view built, with the view's `generation`.
    required property var modelData
    required property size decodeSize
    // Whether this is the centre card, and the card's layer over its dim
    // wash. The carousel sets each only for delegates that declare it.
    property bool current: false
    property Item foreground: null
    property bool busy: false
    // The image file the card draws, "" for none.
    property string picture: ""
    property color ground: Theme.color.surface
    readonly property bool pictureShown: image.status === Image.Ready
    // No picture to draw: none named, or one that cannot be read.
    readonly property bool pictureMissing: picture === "" || image.status === Image.Error

    anchors.fill: parent

    Rectangle {
        anchors.fill: parent
        visible: !root.pictureShown
        color: root.ground
    }

    Image {
        id: image
        anchors.fill: parent
        visible: status === Image.Ready
        source: root.picture === "" ? "" : Files.stampedUrl(root.picture, root.modelData.generation)
        sourceSize: root.decodeSize
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        onStatusChanged: if (status === Image.Error) console.warn("themes: card image unreadable path=" + root.picture)
    }

    // Over what a view's card adds, which is built after these.
    Spinner {
        z: 1
        anchors.centerIn: parent
        visible: root.busy
    }
}
