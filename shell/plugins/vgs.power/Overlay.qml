import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "PowerLogic.js" as Logic

// The power menu: a card over the scrim that lists the actions the Power
// service publishes as offered. An action runs only after a 2000 ms hold
// of Space, Enter, Return or the primary pointer button on its row
// (PowerLogic's hold); a short press, a click and KeyNav's activation only
// select. The service owns the run, so closing the menu keeps it.
//
// Each frame checks the deadline and draws the fill from one reading of
// the ElapsedTimer, so a full fill never waits on a separate Timer.
// The ElapsedTimer is Qt's QElapsedTimer, the platform's
// monotonic clock (Quickshell 0.3.1 src/core/elapsedtimer.cpp):
// https://quickshell.org/docs/v0.3.1/types/Quickshell/ElapsedTimer
// FrameAnimation keeps running with motion off, so the hold stays 2000 ms:
// https://quickshell.org/docs/v0.3.1/types/Quickshell.Services.Mpris/MprisPlayer
Item {
    id: root

    property var shell: null
    readonly property var view: shell === null || shell.status.values.actions === undefined
        ? ({ state: "checking", offered: [] }) : shell.status.values.actions
    // Status values are a fresh copy on every write of any key, so the
    // rows and the hold follow the offered ids' text, not that copy.
    readonly property string offeredKey: JSON.stringify(view.offered)
    readonly property var offered: JSON.parse(offeredKey)
    readonly property var rows: Logic.POWER_ACTIONS.filter(action => offered.indexOf(action.id) !== -1)
    // The selected action's id; "" while nothing is selected, as at open.
    property string selected: ""
    readonly property int current: offered.indexOf(selected)
    property var hold: Logic.holdIdle()
    property real fill: 0
    property bool readPending: false
    readonly property Item initialFocus: list

    function open(payloadJson) {
        JSON.parse(payloadJson);
        resetHold();
        selected = "";
        plate.snap();
        readPending = true;
        askRead();
        entrance.restart();
    }

    function close() {
        resetHold();
    }

    // A press on another screen closes the menu, as a press beside the
    // card does; the summon host calls this.
    function pressedOnOtherScreen() {
        dismiss();
    }

    function dismiss() {
        resetHold();
        if (shell === null) return;
        const reply = shell.surfaces.hide("overlay");
        if (reply !== "ok") console.warn("power menu: hide " + reply);
    }

    // Each opening asks the service to read the offers again; until it
    // has, the last published offers show.
    function askRead() {
        if (!readPending || shell === null) return;
        readPending = false;
        const reply = shell.ipc.call("read-actions", "");
        if (reply !== "ok") console.warn("power menu: read-actions " + reply);
    }
    onShellChanged: askRead()

    // This runs during creation too, when the core hands the instance its
    // shell, before `offered`'s own binding has run, so it reads the ids
    // from the key.
    onOfferedKeyChanged: {
        cancelHold();
        if (JSON.parse(offeredKey).indexOf(selected) === -1) selected = "";
        plate.rebuilt();
    }
    onSelectedChanged: cancelHold()

    // Fractional milliseconds: whole ones truncate both the start and the
    // check, which could judge a hold of 1999.001 ms complete.
    function now() { return clock.elapsedNs() / 1e6; }

    function startHold(source, action) {
        hold = Logic.holdPress(hold, source, action, now());
        fill = Logic.holdProgress(hold, now());
    }

    function releaseHold(source) {
        hold = Logic.holdRelease(hold, source);
        fill = Logic.holdProgress(hold, now());
    }

    function cancelHold() {
        hold = Logic.holdCancel(hold);
        fill = Logic.holdProgress(hold, now());
    }

    // Focus loss: the releases of what was held may never reach this
    // window, so nothing is kept for them.
    function resetHold() {
        hold = Logic.holdIdle();
        fill = Logic.holdProgress(hold, now());
    }

    function due() {
        const at = now();
        const action = hold.action;
        if (hold.phase === "holding" && !(list.activeFocus && selected === action && offered.indexOf(action) !== -1)) {
            cancelHold();
            return;
        }
        const result = Logic.holdFire(hold, at);
        hold = result.hold;
        fill = Logic.holdProgress(hold, at);
        if (result.fire === "") return;
        const reply = shell.ipc.call("action", result.fire);
        if (reply === "ok") dismiss();
        else cancelHold();
    }

    function confirmKey(key) {
        return key === Qt.Key_Space || key === Qt.Key_Return || key === Qt.Key_Enter;
    }

    // A press confirms with no modifier but the keypad's, which its Enter
    // carries. A release ends the hold whatever modifiers are down: Qt
    // reports those held at the release, such as a Shift pressed during
    // the hold.
    function confirmPress(event) {
        return confirmKey(event.key) && (event.modifiers & ~Qt.KeypadModifier) === 0;
    }

    function keyPressed(event) {
        if (event.key === Qt.Key_Escape) {
            // The host's Escape closes the menu after the hold ends here.
            cancelHold();
            return false;
        }
        if (confirmPress(event)) {
            if (event.isAutoRepeat) return true;
            plate.disarm();
            startHold("key:" + event.key, current === -1 ? "" : selected);
            return true;
        }
        return nav.handle(event);
    }

    function keyReleased(event) {
        if (!confirmKey(event.key)) return false;
        if (!event.isAutoRepeat) releaseHold("key:" + event.key);
        return true;
    }

    ElapsedTimer { id: clock }

    NumberAnimation {
        id: entrance
        target: root
        property: "opacity"
        from: 0
        to: 1
        duration: Theme.motion.duration.normal
        easing.type: Theme.motion.easing.standard
    }

    FrameAnimation {
        running: root.hold.phase === "holding"
        onTriggered: root.due()
    }

    // Focus leaving the window, as to the lock screen, closes the menu.
    Connections {
        target: root.Window.window
        function onActiveChanged() {
            if (!root.Window.window.active) root.dismiss();
        }
    }

    // A plate on another row than the held one, as a hover takes it, ends
    // the hold, so the plate always names the action that fires.
    Connections {
        target: plate
        function onPlacedChanged() {
            if (root.hold.phase === "holding" && (plate.placed === null || plate.placed.actionId !== root.hold.action)) root.cancelHold();
        }
    }

    Scrim {}

    // A press of any button beside the card cancels the hold and closes
    // the menu at the press, not at the Scrim's click on the release, which
    // could come after the deadline. A press on the card passes on to it.
    // keyboard-path: Escape closes the menu through the host
    // pointer-cursor-exempt: a press here is a press beside the menu, not a control
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onPressed: mouse => {
            if (card.contains(mapToItem(card, mouse.x, mouse.y))) mouse.accepted = false;
            else root.dismiss();
        }
    }

    Surface {
        id: card
        anchors.centerIn: parent
        width: Math.min(Math.max(list.implicitWidth, hints.implicitWidth, message.visible ? message.implicitWidth : 0) + 2 * pane.contentInset, root.width - 2 * Theme.size.window.gutter)
        height: pane.implicitHeight

        Pane {
            id: pane
            anchors.fill: parent
            container: "panel"
            title: "Power"
            bodySpacing: 0
            fitToContent: true
            maximumHeight: root.height - 2 * Theme.size.window.gutter

            Label {
                id: message
                visible: text !== ""
                width: pane.contentWidth
                role: "body"
                wrapMode: Text.Wrap
                text: root.view.state === "checking" ? "Checking available actions…"
                    : root.view.state === "failed" ? "VGS could not read the available power actions. Close and open the power menu to try again."
                    : root.rows.length === 0 ? "No power actions are available." : ""
            }

            // focus-indicator: the ListCursor plate on the selected row
            Item {
                id: list
                width: pane.contentWidth
                implicitWidth: {
                    let widest = 0;
                    for (let i = 0; i < rowItems.count; ++i) {
                        const row = rowItems.itemAt(i);
                        if (row !== null) widest = Math.max(widest, row.implicitWidth);
                    }
                    return widest;
                }
                height: column.height
                visible: root.rows.length > 0
                focus: true
                activeFocusOnTab: true
                Keys.onPressed: event => { event.accepted = root.keyPressed(event); }
                Keys.onReleased: event => { event.accepted = root.keyReleased(event); }
                onActiveFocusChanged: if (!activeFocus) root.resetHold()

                ListCursor {
                    id: plate
                    // One plate: `selected` at rest, and `selectedPressed`
                    // revealed from the row's left edge as the hold fills.
                    background: Item {
                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.listItem.radius
                            color: Theme.listItem.selected
                        }
                        Item {
                            width: parent.width * root.fill
                            height: parent.height
                            clip: true
                            Rectangle {
                                width: plate.width
                                height: plate.height
                                radius: Theme.listItem.radius
                                color: Theme.listItem.selectedPressed
                            }
                        }
                    }
                }

                KeyNav {
                    id: nav
                    focusTarget: list
                    count: root.rows.length
                    currentIndex: root.current
                    cursor: plate
                    flickable: pane.scrollArea
                    itemAt: index => rowItems.itemAt(index)
                    onMoved: index => root.selected = root.rows[index].id
                }

                Column {
                    id: column
                    width: parent.width

                    Repeater {
                        id: rowItems
                        model: ScriptModel {
                            values: root.rows
                            objectProp: "id"
                        }

                        ListItem {
                            required property var modelData
                            required property int index
                            readonly property string actionId: modelData.id
                            width: column.width
                            text: modelData.label
                            iconName: modelData.icon
                            highlighted: actionId === root.selected
                            cursor: plate
                            // A fresh press selects the row and starts its
                            // hold; `pressed` turns false on the release, on
                            // leaving the row and on a lost grab, and a
                            // return to the row with the button down is no
                            // fresh press.
                            onPressed: {
                                list.forceActiveFocus(Qt.MouseFocusReason);
                                root.selected = actionId;
                                root.startHold("pointer", actionId);
                            }
                            onPressedChanged: if (!pressed) root.releaseHold("pointer")
                        }
                    }
                }
            }

            footer: Row {
                id: hints
                width: pane.contentWidth
                spacing: Theme.stack.group

                KeyHints {
                    anchors.verticalCenter: parent.verticalCenter
                    hints: [{ keys: ["Space", "Enter"], text: "Hold 2 s" }, { key: "Esc", text: "Close" }]
                }
            }
        }
    }
}
