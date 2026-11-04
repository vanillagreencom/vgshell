import QtQuick
import qs.Commons
import qs.Ui
import "PrintersLogic.js" as Logic

// System → Printers, mounted in the holder of the `panes` capability,
// which draws its title and scrolls it: a body alone, from x 0, its height
// its implicitHeight. It draws the `printers` status the service publishes
// and asks the service for every change through the plugin's IPC, so a
// change outlives the pane.
//
// From the top: a line while printing is not installed, is off, could not
// be read or the list stopped following CUPS, with Install printing, the
// plugin's own offer of CUPS's commands, or the `printing` entry's Turn on
// printing as the core's status rows offer it, and Try again; the printers,
// each with its state, its queued jobs and a Default badge, whose action
// and menu set the default, whose menu and Delete remove it; the last
// change's problem; Add a printer: Find printers, the devices CUPS found,
// each with Add, or Print Settings for one that needs a driver, and one
// field for a printer's address; then Print Settings, which opens
// system-config-printer for drivers, paper, two-sided printing and quality,
// in every state but printing not installed, since it needs CUPS.
// While the printer helper is missing, every change button offers its
// install instead.
//
// The pane holds the service's view lease from open() until close() or
// its destruction, whichever comes first, so the service watches CUPS
// only while the pane is shown. A lease the service refused, such as one
// asked for before it was built, is logged and asked for again when
// `shell` next changes.
//
// The payload is `{}`; the pane takes no keys.
FocusScope {
    id: root

    property var shell: null
    // The service's `printers` status, null before it published.
    readonly property var values: shell === null ? ({}) : shell.status.values
    readonly property var view: values.printers === undefined ? null : values.printers
    readonly property string cups: view === null ? "unread" : view.cups
    readonly property var printers: view === null ? [] : view.printers
    readonly property var rows: Logic.printerRows(printers)
    readonly property var found: view === null ? ({ state: "idle", devices: [] }) : view.found
    readonly property var foundList: Logic.foundRows(found.devices)
    readonly property var op: view === null ? Logic.opView(Logic.opIdle()) : view.op
    readonly property bool busy: op.phase === "running"
    readonly property bool helperMissing: view !== null && view.helper === "missing"
    readonly property bool settingsMissing: shell !== null && shell.requirements.missing.indexOf("system-config-printer") !== -1
    // The line's step, { label }, else null: Install printing while CUPS
    // is missing, else the `printing` entry's action while the core offers
    // it.
    readonly property var printingAction: {
        if (shell === null) return null;
        if (cups === "missing") return { label: "Install printing" };
        const row = shell.status.rows.find(r => r.key === "printing");
        return row === undefined || row.action === null || !row.action.offered ? null : { label: row.action.label };
    }
    // The line over the list, "" for none.
    readonly property string stateLine: {
        if (cups === "down") return "Printing is off.";
        if (cups === "missing") return "Printing is not installed.";
        if (cups === "failed") return "VGS could not read the printers.";
        if (cups === "read" && view.watch === "ended") return "The list does not update by itself now.";
        return "";
    }
    readonly property string problem: op.phase === "failed" ? Logic.problemText(op.problem) : ""
    // The address field's refusal, "" for none.
    property string addressProblem: ""
    // The list while it holds a printer, else the address field while Add a
    // printer is shown and takes input, else the state line's action, else
    // the body: never a hidden or disabled item.
    readonly property Item initialFocus: rows.length > 0 ? printerList
        : cups === "read" && !busy ? address
        : stateAction.visible ? stateAction
        : retryAction.visible ? retryAction
        : root

    implicitWidth: Theme.size.window.width
    implicitHeight: content.implicitHeight
    focus: true

    // Whether the pane is open, and the service's id for its view lease, 0
    // while none is held.
    property bool opened: false
    property int viewLease: 0

    function open(payloadJson) {
        opened = true;
        syncView();
    }
    function close() {
        opened = false;
        syncView();
    }
    onShellChanged: syncView()
    Component.onDestruction: {
        opened = false;
        syncView();
    }

    function syncView() {
        if (shell === null) return;
        if (opened && viewLease === 0) {
            const reply = shell.ipc.call("view", "begin");
            const match = /^lease=([1-9][0-9]*)$/.exec(reply);
            if (match === null) console.warn("printers: view lease " + reply);
            else viewLease = Number(match[1]);
        } else if (!opened && viewLease !== 0) {
            const reply = shell.ipc.call("view", "end " + viewLease);
            viewLease = 0;
            if (reply !== "ok") console.warn("printers: view release " + reply);
        }
    }

    // Each answers the service's reply, or `offered` when the press
    // offered the printer helper's install instead.
    function call(name, arg) {
        const reply = shell.ipc.call(name, arg);
        if (reply !== "ok") console.warn("printers: " + name + " " + reply);
        return reply;
    }
    function offerHelper() {
        const reply = shell.requirements.offer([Logic.HELPER]);
        if (reply !== "ok" && reply !== "satisfied") console.warn("printers: requirements " + reply);
        return "offered";
    }
    function setDefault(name) { return helperMissing ? offerHelper() : call("default", name); }
    function remove(name) { return helperMissing ? offerHelper() : call("remove", name); }
    function find() { return helperMissing ? offerHelper() : call("find", ""); }
    function addFound(uri) {
        const device = found.devices.find(d => d.uri === uri);
        if (device !== undefined && !device.driverless) return openSettings();
        return helperMissing ? offerHelper() : call("add", uri);
    }
    function addAddress(text) {
        if (helperMissing) return offerHelper();
        const reply = call("address", text);
        const refused = /^refused: address=([a-z-]+)$/.exec(reply);
        addressProblem = refused === null ? "" : Logic.problemText(refused[1]);
        if (reply === "ok") address.text = "";
        return reply;
    }
    function openSettings() {
        if (settingsMissing) {
            const offered = shell.requirements.offer(["system-config-printer"]);
            if (offered !== "ok" && offered !== "satisfied") console.warn("printers: requirements " + offered);
            return "offered";
        }
        const reply = shell.run.detached(["system-config-printer"]);
        if (reply !== "ok") console.warn("printers: print settings " + reply);
        return reply;
    }
    function runPrintingAction() {
        const reply = cups === "missing" ? shell.requirements.offer(Logic.CUPS_COMMANDS) : shell.status.act("printing");
        if (reply !== "ok") console.warn("printers: printing step " + reply);
        return reply;
    }

    Column {
        id: content
        width: root.width
        spacing: Theme.stack.group

        Column {
            width: parent.width
            visible: root.stateLine !== ""
            spacing: Theme.stack.row

            Label {
                width: parent.width
                role: "body"
                text: root.stateLine
                color: root.cups === "failed" ? Theme.color.danger : Theme.color.text
                wrapMode: Text.Wrap
            }
            RowActions {
                RowAction {
                    id: stateAction
                    visible: root.printingAction !== null
                    text: root.printingAction === null ? "" : root.printingAction.label
                    onClicked: root.runPrintingAction()
                }
                RowAction {
                    id: retryAction
                    visible: root.cups !== "missing"
                    text: "Try again"
                    onClicked: root.call("retry", "")
                }
            }
        }

        Section {
            title: "Printers"
            width: parent.width
            visible: root.cups === "read"

            DeviceList {
                id: printerList
                objectName: "printers-list"
                width: parent.width
                rows: root.rows
                removable: true
                actionOf: row => Logic.printerAction(row)
                menuOf: row => Logic.printerMenu(row)
                onActed: key => {
                    const row = root.rows.find(r => r.key === key);
                    if (row !== undefined && !row.isDefault) root.setDefault(key);
                }
                onChose: (key, entry) => {
                    if (entry === "default") root.setDefault(key);
                    else if (entry === "remove") root.remove(key);
                    else throw new Error("printers: printer menu key " + JSON.stringify(entry) + " is not one of default, remove");
                }
                onRemoved: key => root.remove(key)
            }
            Label {
                width: parent.width
                visible: root.rows.length === 0
                role: "hint"
                text: "No printers yet"
            }
        }

        Label {
            objectName: "printers-problem"
            width: parent.width
            visible: text !== ""
            role: "body"
            text: root.problem
            color: Theme.color.danger
            wrapMode: Text.Wrap
        }

        Column {
            width: parent.width
            visible: root.helperMissing
            spacing: Theme.stack.row

            Label {
                width: parent.width
                role: "hint"
                text: "Adding, removing and choosing printers needs the printer helper."
                wrapMode: Text.Wrap
            }
            RowAction {
                text: "Install printer helper"
                onClicked: root.offerHelper()
            }
        }

        Section {
            title: "Add a printer"
            width: parent.width
            visible: root.cups === "read"
            rowSpacing: Theme.stack.group

            Row {
                spacing: Theme.control.gap

                Button {
                    text: "Find printers"
                    variant: "secondary"
                    iconName: "search"
                    enabled: !root.busy
                    onClicked: root.find()
                }
                Spinner {
                    anchors.verticalCenter: parent.verticalCenter
                    running: root.found.state === "finding"
                    visible: running
                }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    role: "hint"
                    visible: text !== ""
                    text: root.found.state === "finding" ? "Looking for printers"
                        : root.found.state === "found" && root.foundList.length === 0 ? "No new printers found"
                        : root.found.state === "failed" ? "The search did not finish" : ""
                }
            }

            DeviceList {
                objectName: "printers-found"
                width: parent.width
                visible: root.foundList.length > 0
                rows: root.foundList
                actionOf: row => Logic.foundAction(row)
                onActed: key => root.addFound(key)
            }

            Field {
                width: parent.width
                inline: true
                label: "Printer address"
                hint: "A network printer's name or IP address."
                error: root.addressProblem

                TextField {
                    id: address
                    objectName: "printers-address"
                    width: parent.width
                    placeholderText: "printer.local"
                    error: root.addressProblem !== ""
                    enabled: !root.busy
                    onTextChanged: root.addressProblem = ""
                    onAccepted: if (text !== "") root.addAddress(text)
                    actions: [
                        IconButton {
                            iconName: "plus"
                            label: "Add printer"
                            size: "sm"
                            enabled: address.text !== "" && !root.busy
                            onClicked: root.addAddress(address.text)
                        }
                    ]
                }
            }
        }

        Button {
            objectName: "printers-settings"
            visible: Logic.settingsOffered(root.cups)
            text: "Print Settings"
            variant: "secondary"
            iconName: "settings"
            onClicked: root.openSettings()
        }
    }
}
