import QtQuick
import qs.Commons
import qs.Ui
import "DisplaysLogic.js" as Logic

FocusScope {
    id: root

    property var outputs: []
    property var savedRules: ({})
    property var draftRules: ({})
    property string selected: ""
    property bool locked: false
    property bool focusPreview: false
    signal selectedChangedByUser(string identifier)
    signal moved(var rules)
    signal identify(string identifier)

    readonly property var items: Logic.arrangementItems(outputs, savedRules, draftRules)
    readonly property real contentWidth: Logic.arrangementContentWidth(items)
    readonly property real contentHeight: Logic.arrangementContentHeight(items)
    readonly property real scaleFactor: Math.min(width / contentWidth, implicitHeight / contentHeight)
    readonly property real step: Logic.NUDGE
    readonly property real bigStep: Logic.NUDGE_BIG

    function select(identifier) {
        selectedChangedByUser(identifier);
    }

    implicitHeight: Math.max(Theme.size.control.lg, Theme.size.panel.sm / 3)
    focus: true
    activeFocusOnTab: true
    Accessible.name: "Display arrangement"
    Keys.onPressed: event => {
        focusPreview = true;
        if (locked || selected === "") return;
        const amount = event.modifiers & Qt.ShiftModifier ? bigStep : step;
        let dx = 0, dy = 0;
        if (event.key === Qt.Key_Left) dx = -amount;
        else if (event.key === Qt.Key_Right) dx = amount;
        else if (event.key === Qt.Key_Up) dy = -amount;
        else if (event.key === Qt.Key_Down) dy = amount;
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            root.identify(selected);
            event.accepted = true;
            return;
        } else {
            return;
        }
        event.accepted = true;
        root.moved(Logic.nudgeGroup(outputs, savedRules, draftRules, selected, dx, dy));
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radius.md
        color: Theme.color.surface
        border.width: Theme.border.thin
        border.color: root.activeFocus ? Theme.color.focus : Theme.color.border

        Repeater {
            model: root.items

            Rectangle {
                id: tile
                required property var modelData
                property bool dragging: false
                property real dragX: 0
                property real dragY: 0
                property real pressX: 0
                property real pressY: 0
                property real startX: 0
                property real startY: 0
                readonly property bool current: modelData.identifier === root.selected
                opacity: modelData.off ? Theme.opacity.disabled : 1
                x: dragging ? dragX : modelData.x * root.scaleFactor
                y: dragging ? dragY : modelData.y * root.scaleFactor
                width: Math.max(Theme.size.control.lg, modelData.width * root.scaleFactor)
                height: Math.max(Theme.size.control.lg, modelData.height * root.scaleFactor)
                radius: Theme.radius.sm
                color: current ? Theme.color.accentSubtle : Theme.color.surfaceRaised
                border.width: Theme.border.thin
                border.color: current ? Theme.color.accent : Theme.color.border

                Label {
                    anchors.centerIn: parent
                    width: parent.width - 2 * Theme.stack.inline
                    role: "item"
                    horizontalAlignment: Text.AlignHCenter
                    text: tile.modelData.label
                    elide: Text.ElideRight
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: !root.locked
                    onPressed: {
                        root.forceActiveFocus(Qt.MouseFocusReason);
                        root.focusPreview = false;
                        root.select(tile.modelData.identifier);
                        const point = mapToItem(root, mouse.x, mouse.y);
                        tile.pressX = point.x;
                        tile.pressY = point.y;
                        tile.startX = tile.x;
                        tile.startY = tile.y;
                        tile.dragX = tile.x;
                        tile.dragY = tile.y;
                        tile.dragging = true;
                    }
                    onPositionChanged: {
                        if (!pressed) return;
                        const point = mapToItem(root, mouse.x, mouse.y);
                        tile.dragX = tile.startX + point.x - tile.pressX;
                        tile.dragY = tile.startY + point.y - tile.pressY;
                    }
                    onReleased: {
                        const x = tile.dragX / root.scaleFactor;
                        const y = tile.dragY / root.scaleFactor;
                        tile.dragging = false;
                        root.moved(Logic.moveGroup(root.outputs, root.savedRules, root.draftRules, tile.modelData.identifier, x, y));
                    }
                    onCanceled: tile.dragging = false
                    onDoubleClicked: root.identify(tile.modelData.identifier)
                    PointerCursor {}
                }
            }
        }
    }

    FocusRing {
        target: root
        visible: root.focusPreview
    }
}
