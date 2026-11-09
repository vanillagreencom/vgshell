import QtQuick
import Quickshell.Bluetooth
import qs.Commons
import qs.Ui
import qs.Ui as Ui
import "BluetoothLogic.js" as Logic

// The two device lists the flyout and the pane share, each a qs.Ui
// DeviceList over BluetoothLogic.deviceRows: My Devices, whose action
// connects, disconnects or retries a device while its row shows Connecting…,
// Disconnecting… and one failure sentence; Nearby, whose Pair asks the
// owner through `pairRequested`, hidden while `pairBusy` holds. With
// `manage`, My Devices offers Rename, which asks the owner through
// `renameRequested`, Trust or Don't trust, and Forget, which Delete runs
// too. A page pairing's follow-up connect (`connectPaired`) is pressed and
// recorded as a row's Connect is. Both lists show only while Bluetooth is on.
Column {
    id: root

    property bool powerOn: false
    property bool opened: false
    onPowerOnChanged: root.refreshLifecycle()
    onOpenedChanged: root.refreshLifecycle()
    property bool manage: false
    property bool pairBusy: false
    property var attempts: ({})
    // Quickshell 0.3.1 publishes BluetoothDevice.state with stateChanged,
    // and BluetoothDeviceState.toString returns the four state names.
    readonly property var states: Logic.stateMap(Bluetooth.devices.values, root.stateOf)
    onStatesChanged: {
        root.attempts = Logic.settleAttempts(root.attempts, root.states);
        root.refresh(true);
    }
    onAttemptsChanged: root.refresh(true)
    property var lists: ({ mine: [], nearby: [] })
    property real lastPublication: 0
    readonly property var failures: root.lists.mine.filter(r => r.failed).map(r => Logic.failureText(r.text))
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool searching: adapter !== null && adapter.discovering
    readonly property alias mine: mineList

    signal pairRequested(string address)
    signal renameRequested(string address)

    spacing: Theme.stack.group

    function deviceFor(address) { return Logic.deviceAt(Bluetooth.devices.values, address); }
    function stateOf(device) { return BluetoothDeviceState.toString(device.state); }

    function refreshLifecycle() {
        // My Devices remains immediate if a rapid reopen or power change
        // reaches the full publication guard. The opening Nearby snapshot
        // must exist before the floating host takes its first size request.
        root.refresh(true);
        root.refresh(false);
    }

    function refresh(mineOnly) {
        if (!root.opened || !root.powerOn) return;
        const now = Date.now();
        // Qt Timer follows animation ticks. This clock check holds the
        // publication bound even when adjacent ticks are slightly early.
        // https://doc.qt.io/qt-6/qml-qtqml-timer.html
        if (!mineOnly && now - root.lastPublication < Logic.DEVICE_REFRESH_MS) return;
        const mineKey = mineList.currentKey, nearbyKey = nearbyList.currentKey;
        const mineIndex = mineList.current, nearbyIndex = nearbyList.current;
        const focused = mineList.activeFocus ? mineList : nearbyList.activeFocus ? nearbyList : null;
        // Pane.scrollArea is the shared container's public scroll owner.
        // Qt Item.parent is the visual parent, including the mounted pane:
        // https://doc.qt.io/qt-6/qml-qtquick-item.html#parent-prop
        let pane = root.parent;
        while (pane !== null && !(pane instanceof Ui.Pane)) pane = pane.parent;
        const view = pane === null ? null : pane.scrollArea;
        const offset = view === null ? 0 : view.contentY;
        const next = Logic.deviceRows(Bluetooth.devices.values, root.stateOf, root.attempts, root.lists, now, mineOnly);
        root.lists = next;
        function restore(list, key, index) {
            const at = list.rows.findIndex(row => row.key === key);
            list.current = at >= 0 ? at : Math.max(0, Math.min(index, list.rows.length - 1));
            if (focused === list && list.currentKey !== key) list.focusCurrent(Qt.TabFocusReason);
            else if (focused === list && list.current !== index) list.focusCurrent(Qt.TabFocusReason);
        }
        restore(mineList, mineKey, mineIndex);
        restore(nearbyList, nearbyKey, nearbyIndex);
        // Reading and restoring both lists completes synchronous row
        // notifications. Start the next interval after that work so its
        // cost cannot shorten the gap between Nearby publications.
        if (!mineOnly) root.lastPublication = Date.now();
        // Focus transfer can make ScrollArea reveal a different row. Restore
        // the held offset after layout, within the remaining scroll extent.
        Qt.callLater(() => {
            if (root !== null && view !== null && root.opened)
                view.contentY = Math.max(0, Math.min(offset, view.contentHeight - view.height));
        });
    }

    Timer {
        // At most one Nearby publication every 500 ms (2 per second), while
        // this view is open. Qt Timer stops when running becomes false:
        // https://doc.qt.io/qt-6/qml-qtqml-timer.html#running-prop
        interval: Logic.DEVICE_REFRESH_MS
        repeat: true
        running: root.opened && root.visible && root.powerOn
        onTriggered: root.refresh(false)
    }

    function toggle(address) {
        const device = deviceFor(address);
        if (device !== null) press(device, address, Logic.pressAction(stateOf(device)));
    }

    // A page pairing's follow-up once its device reads paired.
    function connectPaired(address) {
        const device = deviceFor(address);
        if (device !== null) press(device, address, Logic.pairFollowUp(stateOf(device)));
    }

    function press(device, address, action) {
        if (action === null) return;
        device.connected = action === "connect";
        // Quickshell 0.3.1 sets Connecting or Disconnecting during this write.
        // Recording after it keeps settlement from reading the old state, and no failure reason is exposed.
        root.attempts = Logic.attemptPressed(root.attempts, address, action);
    }

    // A menu entry of one of your devices.
    function choose(address, key) {
        const device = deviceFor(address);
        if (device === null) return;
        switch (key) {
        case "rename":
            root.renameRequested(address);
            break;
        case "trust":
            device.trusted = true;
            break;
        case "untrust":
            device.trusted = false;
            break;
        case "forget":
            device.forget();
            break;
        default:
            throw new Error("bluetooth: device menu key " + JSON.stringify(key) + " is not one of rename, trust, untrust, forget");
        }
    }

    Section {
        title: "My Devices"
        visible: root.powerOn
        width: parent.width
        DeviceList {
            id: mineList
            width: parent.width
            rows: root.lists.mine
            removable: root.manage
            actionOf: row => Logic.mineAction(row)
            menuOf: row => root.manage ? Logic.mineMenu(row) : []
            onActed: key => root.toggle(key)
            onChose: (key, entry) => root.choose(key, entry)
            onRemoved: key => root.choose(key, "forget")
        }
        Repeater {
            model: root.failures
            Label {
                width: parent.width
                role: "hint"
                color: Theme.color.danger
                wrapMode: Text.Wrap
                text: modelData
            }
        }
        Label {
            width: parent.width
            visible: root.lists.mine.length === 0
            role: "hint"
            text: "No devices yet"
        }
    }

    Section {
        title: "Nearby"
        visible: root.powerOn
        width: parent.width
        DeviceList {
            id: nearbyList
            width: parent.width
            rows: root.lists.nearby
            actionOf: row => Logic.nearbyAction(row, root.pairBusy)
            onActed: key => { if (!root.pairBusy) root.pairRequested(key); }
        }
        Row {
            visible: root.lists.nearby.length === 0
            spacing: Theme.control.gap
            Spinner {
                anchors.verticalCenter: parent.verticalCenter
                running: root.searching
                visible: root.searching
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                role: "hint"
                text: root.searching ? "Looking for devices" : "No devices nearby"
            }
        }
    }
}
