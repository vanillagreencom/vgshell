import QtQuick
import QtQuick.Templates as T
import qs.Commons
import qs.Ui

// One choice among equal-width icon tiles. The group is one tab stop: Left
// and Right choose tiles, and each tile takes no focus of its own.
T.Control {
    id: root

    property var model: []
    property int currentIndex: 0
    property bool focusPreview: false
    readonly property real naturalContentWidth: {
        let total = Math.max(0, model.length - 1) * Theme.tileGroup.gap;
        for (const child of row.children) {
            if (child.implicitWidth !== undefined) total += child.implicitWidth;
        }
        return total;
    }
    signal activated(int index)

    function choose(index) {
        if (index < 0 || index >= model.length || index === currentIndex) return;
        currentIndex = index;
        activated(index);
    }

    implicitWidth: naturalContentWidth
    implicitHeight: Theme.tileGroup.height
    focusPolicy: Qt.StrongFocus
    opacity: enabled ? 1 : Theme.opacity.disabled
    Keys.onPressed: event => { event.accepted = nav.handle(event); }

    property KeyNav nav: KeyNav {
        count: root.model.length
        currentIndex: root.currentIndex
        orientation: "horizontal"
        wrap: false
        onMoved: index => root.choose(index)
    }

    contentItem: Row {
        id: row
        height: root.availableHeight
        spacing: Theme.tileGroup.gap

        Repeater {
            model: root.model
            // keyboard-path: the tile group is one tab stop and its arrow keys choose tiles
            T.Button {
                id: tile
                required property int index
                required property var modelData
                readonly property bool current: index === root.currentIndex
                readonly property bool tileAvailable: modelData.available === undefined || modelData.available
                readonly property string tileText: modelData.text === undefined ? String(modelData) : String(modelData.text)
                readonly property string tileIcon: modelData.icon === undefined ? "" : String(modelData.icon)
                readonly property color tileForeground: current ? Theme.tileGroup.selectedForeground : Theme.tileGroup.foreground
                readonly property bool fillWidth: root.width > 0 && root.width !== root.implicitWidth

                height: row.height
                width: fillWidth && root.model.length > 0
                    ? Math.max(0, (root.availableWidth - Math.max(0, root.model.length - 1) * Theme.tileGroup.gap) / root.model.length)
                    : implicitWidth
                implicitWidth: Math.max(Theme.tileGroup.height, implicitContentWidth + leftPadding + rightPadding)
                implicitHeight: Theme.tileGroup.height
                leftPadding: Theme.tileGroup.paddingX
                rightPadding: Theme.tileGroup.paddingX
                focusPolicy: Qt.NoFocus
                enabled: root.enabled && tileAvailable
                hoverEnabled: true
                opacity: tileAvailable ? 1 : Theme.opacity.disabled
                PointerCursor {}
                Accessible.name: tileText
                onClicked: { root.forceActiveFocus(Qt.MouseFocusReason); root.choose(index); }

                contentItem: Item {
                    implicitWidth: Math.max(glyph.implicitWidth, caption.implicitWidth)
                    implicitHeight: glyph.height + Theme.tileGroup.contentGap + caption.lineBox
                    Icon {
                        id: glyph
                        name: tile.tileIcon
                        size: Theme.tileGroup.icon
                        color: tile.tileForeground
                        x: Math.round((parent.width - width) / 2)
                        y: Math.round((parent.height - glyph.height - Theme.tileGroup.contentGap - caption.lineBox) / 2)
                    }
                    Label {
                        id: caption
                        role: Theme.tileGroup.captionRole
                        text: tile.tileText
                        color: tile.tileForeground
                        width: parent.width
                        y: glyph.y + glyph.height + Theme.tileGroup.contentGap
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }
                }

                background: Rectangle {
                    radius: Theme.tileGroup.radius
                    color: tile.current ? Theme.tileGroup.selectedBackground : tile.down ? Theme.tileGroup.pressed : tile.hovered ? Theme.tileGroup.hover : Theme.tileGroup.background
                    border.width: Theme.border.thin
                    border.color: tile.current ? Theme.tileGroup.selectedBorder : Theme.tileGroup.border
                    Behavior on color { ColorAnimation { duration: Theme.motion.duration.fast; easing.type: Theme.motion.easing.standard } }
                    FocusRing {
                        target: root
                        targetRadius: Theme.tileGroup.radius
                        visible: tile.current && (root.focusPreview || root.visualFocus)
                    }
                }
            }
        }
    }
}
