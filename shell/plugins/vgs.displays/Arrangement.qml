import QtQuick
import QtQuick.Templates as T
import qs.Commons
import qs.Ui
import "DisplaysLogic.js" as Logic

T.Control {
    id: root

    property var outputs: []
    property var savedRules: ({})
    property var draftRules: ({})
    property string selected: ""
    property bool locked: false
    signal selectedChangedByUser(string identifier)
    signal moved(var rules)
    signal identify(string identifier)

    readonly property var items: Logic.arrangementItems(outputs, savedRules, draftRules)
    // Every display at its place and size, scaled to fit the box with an
    // even margin, as a { scale, x, y, height } the tiles and a drag read.
    readonly property var fit: Logic.arrangementFit(Logic.arrangementBounds(items), width, Theme.size.panel.sm, Theme.space.xxl)
    readonly property real step: Logic.NUDGE
    readonly property real bigStep: Logic.NUDGE_BIG

    function select(identifier) {
        selectedChangedByUser(identifier);
    }

    implicitHeight: fit.height
    focus: true
    activeFocusOnTab: true
    Accessible.name: "Display arrangement"
    Keys.onPressed: event => {
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
        root.focusReason = Qt.ShortcutFocusReason;
        event.accepted = true;
        root.moved(Logic.nudgeGroup(outputs, savedRules, draftRules, selected, dx, dy));
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radius.md
        color: Theme.color.surface
        border.width: Theme.border.thin
        border.color: root.visualFocus ? Theme.color.focus : Theme.color.border
        // A tile dragged past the edge draws nothing outside the box.
        clip: true

        Repeater {
            model: root.items

            Item {
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
                x: dragging ? dragX : root.fit.x + modelData.x * root.fit.scale
                y: dragging ? dragY : root.fit.y + modelData.y * root.fit.scale
                width: modelData.width * root.fit.scale
                height: modelData.height * root.fit.scale

                // Inset so two displays that touch draw two outlines with a
                // gap between them, not one doubled line.
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: Theme.space.xxs
                    radius: Theme.radius.sm
                    color: tile.current ? Theme.color.accentSubtle : Theme.color.surfaceRaised
                    border.width: tile.current ? Theme.border.thick : Theme.border.thin
                    border.color: tile.current ? Theme.color.accent : Theme.color.border

                    Column {
                        anchors.centerIn: parent
                        width: parent.width - 2 * Theme.stack.inline

                        Label {
                            width: parent.width
                            role: "item"
                            horizontalAlignment: Text.AlignHCenter
                            text: tile.modelData.label
                            elide: Text.ElideRight
                        }

                        Label {
                            width: parent.width
                            visible: text !== ""
                            role: "itemHint"
                            horizontalAlignment: Text.AlignHCenter
                            text: tile.modelData.product
                            elide: Text.ElideRight
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: !root.locked
                    onPressed: {
                        root.forceActiveFocus(Qt.MouseFocusReason);
                        root.select(tile.modelData.identifier);
                        const point = mapToItem(root, mouse.x, mouse.y);
                        tile.pressX = point.x;
                        tile.pressY = point.y;
                        tile.startX = tile.x;
                        tile.startY = tile.y;
                    }
                    onPositionChanged: {
                        if (!pressed) return;
                        const point = mapToItem(root, mouse.x, mouse.y);
                        const dx = point.x - tile.pressX;
                        const dy = point.y - tile.pressY;
                        // A press that moves no further than the platform's
                        // drag threshold is a click and only selects:
                        // QStyleHints.startDragDistance, read in QML as
                        // Application.styleHints (doc.qt.io/qt-6/qstylehints.html,
                        // qml-qtquick-application.html).
                        const threshold = Application.styleHints.startDragDistance;
                        if (!tile.dragging && Math.abs(dx) <= threshold && Math.abs(dy) <= threshold) return;
                        tile.dragX = tile.startX + dx;
                        tile.dragY = tile.startY + dy;
                        tile.dragging = true;
                    }
                    onReleased: {
                        if (!tile.dragging) return;
                        tile.dragging = false;
                        const x = (tile.dragX - root.fit.x) / root.fit.scale;
                        const y = (tile.dragY - root.fit.y) / root.fit.scale;
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
    }
}
