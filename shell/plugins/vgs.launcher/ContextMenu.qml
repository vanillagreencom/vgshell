import QtQuick
import qs.Ui

// The pointer flyout: a small glass menu that opens at a point and closes
// on a pick, Escape (through close()) or a click outside. Put it in a
// full-size parent. `items` is [{ id, label, icon?, glyph?, detail?,
// separator? }]: `icon` an image URL, `glyph` a Lucide name. The hovered
// entry holds a ListCursor at `motion`, the launcher's list motion, so one
// plate glides between entries.
Item {
    id: menu

    required property var look
    required property var motion
    // Whether the flyout draws glass: the launcher card's effective state.
    property bool glass: false
    property var items: []
    readonly property bool opened: state === "open"
    property int hovered: -1
    property point anchorPoint: Qt.point(0, 0)
    signal triggered(string id)

    anchors.fill: parent
    visible: panel.opacity > 0
    z: 100

    function openAt(px, py) {
        anchorPoint = Qt.point(px, py);
        reclamp();
        hovered = firstReachable();
        state = "open";
    }

    // Keeps the flyout on screen; called again when `items` changes its size.
    function reclamp() {
        const px = anchorPoint.x, py = anchorPoint.y;
        const w = panel.width, h = panel.implicitHeight, m = look.flyout.margin;
        const flip = py + h + m > height;
        panel.x = Math.max(m, Math.min(px, width - w - m));
        panel.y = flip ? Math.max(m, py - h) : py;
        panel.transformOrigin = flip ? Item.BottomLeft : Item.TopLeft;
    }

    function close() { state = ""; }

    function firstReachable() {
        for (let i = 0; i < items.length; i++) if (reachable(i)) return i;
        return -1;
    }

    function reachable(index) {
        return index >= 0 && index < items.length && !items[index].separator;
    }

    function labelAt(index) {
        return reachable(index) ? (items[index].label || "") : "";
    }

    function triggerIndex(index) {
        if (!reachable(index)) return false;
        close();
        triggered(items[index].id);
        return true;
    }

    function handleKey(event) {
        if (event.key === Qt.Key_Escape) {
            close();
            return true;
        }
        nav.handle(event);
        return true;
    }

    onItemsChanged: if (opened) Qt.callLater(() => {
        reclamp();
        if (!reachable(hovered)) hovered = firstReachable();
    })

    KeyNav {
        id: nav
        count: menu.items.length
        currentIndex: menu.hovered
        wrap: false
        reachable: index => menu.reachable(index)
        labelAt: index => menu.labelAt(index)
        cursor: plate
        onMoved: index => menu.hovered = index
        onActivated: index => menu.triggerIndex(index)
    }

    // The click-away catcher also takes hover, so nothing behind the flyout
    // reacts to the pointer while it is open.
    // pointer-cursor-exempt: a press here is a click away from the flyout, not a control
    // keyboard-path: Escape closes the flyout
    MouseArea {
        anchors.fill: parent
        enabled: menu.opened
        hoverEnabled: true
        acceptedButtons: Qt.AllButtons
        onPressed: menu.close()
    }

    GlassSurface {
        id: panel
        optIn: menu.glass
        // The card's fill: solid over the card, the flyout draws it
        // opaque, so it keeps the card's hue.
        fill: menu.look.card.fill
        width: menu.look.flyout.width
        height: implicitHeight
        implicitHeight: column.implicitHeight + 2 * menu.look.flyout.padding
        elevation: "tight"
        opacity: menu.opened ? 1 : 0
        scale: menu.opened ? 1 : menu.look.flyout.openScale
        Behavior on opacity {
            Anim { duration: menu.look.motion.duration.short3; curve: menu.look.motion.curve.standard }
        }
        Behavior on scale {
            Anim { duration: menu.look.motion.duration.medium1; curve: menu.look.motion.curve.emphasizedDecel }
        }

        // The whole flyout owns the pointer, gaps and separators included.
        // pointer-cursor-exempt: it holds the presses on the flyout's gaps, where nothing is clickable
        // keyboard-path: the flyout handles every key while open
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.AllButtons
            onEntered: menu.hovered = -1
        }

        // The entries and their cursor, in an item that draws nothing:
        // the glass body paints its fill, which would cover the cursor.
        Item {
            anchors.fill: parent

            ListCursor {
                id: plate
                motion: menu.motion
                // Concentric with the flyout: the corner its surface draws
                // less the padding.
                background: Highlight { look: menu.look; radius: Math.max(0, panel.corner - menu.look.flyout.padding) }
            }

            Column {
                id: column
                x: menu.look.flyout.padding
                y: menu.look.flyout.padding
                width: parent.width - 2 * menu.look.flyout.padding

                Repeater {
                    model: menu.items

                    Item {
                        id: entry
                        required property var modelData
                        required property int index
                        readonly property bool separator: !!modelData.separator
                        readonly property bool hasIcon: !separator && (!!modelData.icon || !!modelData.glyph)
                        readonly property bool hasCursor: menu.hovered === index
                        onHasCursorChanged: plate.follow(entry, hasCursor)

                        width: column.width
                        height: separator ? menu.look.flyout.separatorHeight : menu.look.flyout.rowHeight

                        Rectangle {
                            visible: entry.separator
                            anchors.centerIn: parent
                            width: parent.width - menu.look.flyout.separatorInset
                            height: menu.look.row.dividerWidth
                            color: menu.look.row.divider
                        }

                        Item {
                            id: iconBox
                            visible: entry.hasIcon
                            anchors.left: parent.left
                            anchors.leftMargin: menu.look.flyout.iconInset
                            y: entryText.y + entryReading.topForLeadingIcon(height, entryText.y)
                            width: menu.look.flyout.iconSize
                            height: menu.look.flyout.iconSize

                            Image {
                                anchors.fill: parent
                                visible: !!entry.modelData.icon
                                sourceSize.width: width * Screen.devicePixelRatio
                                sourceSize.height: height * Screen.devicePixelRatio
                                source: entry.modelData.icon || ""
                                asynchronous: true
                            }
                            Icon {
                                anchors.centerIn: parent
                                visible: !entry.modelData.icon && !!entry.modelData.glyph
                                name: entry.modelData.glyph || ""
                                size: menu.look.flyout.iconSize
                                stroke: menu.look.tile.stroke
                                color: menu.look.text.foreground
                            }
                        }

                        Text {
                            id: entryText
                            visible: !entry.separator
                            anchors.left: iconBox.visible ? iconBox.right : parent.left
                            anchors.leftMargin: iconBox.visible ? menu.look.flyout.iconGap : menu.look.flyout.textInset
                            anchors.right: detail.left
                            anchors.rightMargin: menu.look.flyout.detailGap
                            anchors.verticalCenter: parent.verticalCenter
                            textFormat: Text.PlainText
                            text: entry.modelData.label || ""
                            color: menu.look.text.foreground
                            elide: Text.ElideRight
                            font.family: menu.look.font.family.sans
                            font.pixelSize: menu.look.text.flyout.size
                        }

                        // The entry text's leading icon reading, which the
                        // icon box takes its top from. It draws nothing. Its
                        // font binding replaces Label's role font whole (a
                        // qmltestrunner 6.11.2 run read the source's family,
                        // size and weight back), so it reads the launcher's
                        // own font.
                        Label {
                            id: entryReading
                            visible: false
                            text: entryText.text
                            font: entryText.font
                        }

                        Text {
                            id: detail
                            visible: !entry.separator && !!entry.modelData.detail
                            anchors.right: parent.right
                            anchors.rightMargin: menu.look.flyout.textInset
                            anchors.verticalCenter: parent.verticalCenter
                            textFormat: Text.PlainText
                            text: entry.modelData.detail || ""
                            color: menu.look.text.detail.color
                            font.family: menu.look.font.family.sans
                            font.pixelSize: menu.look.text.flyout.detail
                        }

                        // keyboard-path: the flyout's KeyNav moves to this entry and Enter triggers it
                        MouseArea {
                            anchors.fill: parent
                            enabled: !entry.separator
                            hoverEnabled: true
                            PointerCursor {}
                            onEntered: menu.hovered = entry.index
                            onExited: if (menu.hovered === entry.index) menu.hovered = -1
                            onClicked: {
                                menu.close();
                                menu.triggered(entry.modelData.id);
                            }
                        }
                    }
                }
            }
        }
    }
}
