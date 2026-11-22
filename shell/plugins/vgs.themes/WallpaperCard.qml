import QtQuick
import qs.Commons
import qs.Ui

// A wallpaper's card: its image, or the download or update offer. The
// view shows a wallpaper's name under the rail, not on its card. Keep
// side-card offer names and icons above the dim wash so the wash fades
// neither. Inset the centre label by the card's lean to clear the angled
// edges.
BrowserCard {
    id: root

    readonly property bool offer: modelData.kind !== "image"
    readonly property bool side: offer && !current

    picture: offer ? "" : modelData.path

    Column {
        anchors.centerIn: parent
        width: parent.width - 2 * Theme.angledCard.skew
        visible: !root.pictureShown
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
}
