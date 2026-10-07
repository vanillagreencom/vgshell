import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import qs.Commons
import qs.Ui

// One choice among a few, drawn as equal tiles, each an icon over a short
// caption: `model` lists `{ text, icon, available }` entries and
// `currentIndex` the chosen one. The tiles share the control's width
// equally; unsized, each is as wide as the widest tile's content. A click
// or the left and right keys choose a tile, and `activated` fires on a
// change the user made. A tile whose `available` is false is disabled, and
// the keys pass over it. The control is one tab stop: the tiles take no
// focus of their own. The ring draws on the chosen tile's edge in
// `tileGroup.focus`, since a ring in the accent would only thicken the
// chosen tile's accent border.
T.Control {
    id: root

    readonly property real minimumWidth: Theme.field.minWidth
    readonly property real maximumWidth: Theme.control.maxWidth
    Layout.minimumWidth: minimumWidth
    Layout.maximumWidth: maximumWidth
    width: Math.max(minimumWidth, Math.min(maximumWidth, implicitWidth))
    InputWidth { target: root }

    property var model: []
    property int currentIndex: 0
    property bool focusPreview: false
    // The widest tile's content, which every tile is given when the
    // control is not set wider.
    readonly property real tileImplicitWidth: {
        let widest = 0;
        for (const child of row.children) {
            if (child.implicitWidth !== undefined) widest = Math.max(widest, child.implicitWidth);
        }
        return widest;
    }
    readonly property real tileWidth: model.length === 0 ? 0 : Math.max(0, (availableWidth - (model.length - 1) * Theme.tileGroup.gap) / model.length)
    signal activated(int index)

    function available(index) {
        const entry = model[index];
        return entry !== undefined && (entry.available === undefined || entry.available === true);
    }

    function choose(index) {
        if (index < 0 || index >= model.length || index === currentIndex || !available(index)) return;
        currentIndex = index;
        activated(index);
    }

    implicitWidth: model.length * tileImplicitWidth + Math.max(0, model.length - 1) * Theme.tileGroup.gap
    implicitHeight: Theme.tileGroup.height
    focusPolicy: Qt.StrongFocus
    opacity: enabled ? 1 : Theme.opacity.disabled
    Keys.onPressed: event => { event.accepted = nav.handle(event); }

    property KeyNav nav: KeyNav {
        count: root.model.length
        currentIndex: root.currentIndex
        orientation: "horizontal"
        wrap: false
        reachable: index => root.available(index)
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
                readonly property color tileForeground: current ? Theme.tileGroup.selectedForeground : Theme.tileGroup.foreground

                width: root.tileWidth
                height: row.height
                implicitWidth: Math.max(Theme.tileGroup.height, implicitContentWidth + leftPadding + rightPadding)
                leftPadding: Theme.tileGroup.paddingX
                rightPadding: Theme.tileGroup.paddingX
                focusPolicy: Qt.NoFocus
                enabled: root.available(index)
                hoverEnabled: true
                // A disabled group fades once, as a whole.
                opacity: enabled || !root.enabled ? 1 : Theme.opacity.disabled
                PointerCursor {}
                text: modelData.text === undefined ? String(modelData) : String(modelData.text)
                Accessible.name: text
                onClicked: { root.forceActiveFocus(Qt.MouseFocusReason); root.choose(index); }

                contentItem: Item {
                    implicitWidth: Math.max(glyph.width, caption.implicitWidth)
                    implicitHeight: glyph.height + Theme.tileGroup.contentGap + caption.lineBox
                    Icon {
                        id: glyph
                        name: tile.modelData.icon === undefined ? "" : String(tile.modelData.icon)
                        size: Theme.tileGroup.icon
                        color: tile.tileForeground
                        x: Math.round((parent.width - width) / 2)
                        y: Math.round((parent.height - parent.implicitHeight) / 2)
                    }
                    Label {
                        id: caption
                        role: Theme.tileGroup.captionRole
                        text: tile.text
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
                        ringColor: Theme.tileGroup.focus
                        visible: tile.current && (root.focusPreview || root.visualFocus)
                    }
                }
            }
        }
    }
}
