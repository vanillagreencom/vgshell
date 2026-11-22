import QtQuick
import qs.Commons
import qs.Ui
import "BrowserLogic.js" as BrowserLogic

// A theme's card: its package preview, else an accepted package's first
// wallpaper, on its background colour. Only the selected card names a
// theme it has no picture for and lays the theme's sixteen colours across
// its foot; a side card draws its picture alone, as a wallpaper card does. Every built card loads its picture at decodeSize, so the next
// card is already decoded.
BrowserCard {
    id: root

    readonly property var colors: modelData.palette
    readonly property var swatches: BrowserLogic.swatches(modelData.terminal)
    readonly property bool packagePreview: typeof modelData.previewImage === "string" && modelData.previewImage !== ""
    readonly property bool backdrop: !packagePreview && modelData.state === "ok"
    readonly property string wallpaper: typeof modelData.image === "string" ? modelData.image : ""

    picture: packagePreview ? modelData.previewImage : backdrop ? wallpaper : ""
    ground: colors === null ? Theme.color.surface : Theme.toColor(colors.background)

    Label {
        role: "bodyStrong"
        anchors.centerIn: parent
        width: parent.width - 2 * Theme.angledCard.skew
        visible: root.current && root.pictureMissing
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        text: root.modelData.label
        color: root.colors === null ? Theme.color.textMuted : Theme.toColor(root.colors.foreground)
    }

    ThemePaletteStrip {
        objectName: "paletteStrip"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Theme.space.xxl
        visible: root.current && (root.packagePreview || root.backdrop) && root.swatches !== null
        columns: 8
        colours: root.swatches === null ? [] : root.swatches
    }
}
