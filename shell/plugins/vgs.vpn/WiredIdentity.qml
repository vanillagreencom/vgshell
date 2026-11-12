import QtQuick
import Quickshell
import Quickshell.Io
import "VpnLogic.js" as Logic

// The wired identity's readers (VpnLogic.wiredIdentity), owned by the
// service: one read at a time, of the active wired profiles the service
// hands `read`, each in turn through its interface (VpnLogic.linkArgv,
// the link read the leak check takes), its device read and, with a
// router, its neighbour read. The service reads once per network change
// and at a capture, never on a timer; no read waits for or asks the
// kernel to resolve the router. A declared requirement that is missing
// runs no process and reads as unread. `value` is null before a read for
// the current change, else one identity per profile read, in order, null
// for one it could not read. `forget`, at a network change, marks the
// read in flight so its end discards it, since its readings belong to
// the change before. `settled` follows each read's end.
Item {
    id: root
    property var nmcliEnvironment: ({})
    property var missing: []
    property var value: null
    // The read in flight: { queue, found, device, route, stale }, QUEUE
    // the profiles not yet read, DEVICE and ROUTE the current profile's
    // interface and router.
    property var run: null
    readonly property bool reading: run !== null

    signal settled()

    function read(uuids) {
        if (run !== null) return;
        run = { queue: uuids.slice(), found: [], device: "", route: null, stale: false };
        next();
    }
    function forget() {
        if (run !== null) run = Object.assign({}, run, { stale: true });
        else value = null;
    }

    function next() {
        if (run.queue.length > 0) {
            const uuid = run.queue[0];
            run = Object.assign({}, run, { queue: run.queue.slice(1) });
            launch(linkReader, Logic.linkArgv(uuid), "nmcli");
            return;
        }
        deadline.stop();
        const ended = run;
        run = null;
        value = ended.stale ? null : ended.found;
        if (!ended.stale && ended.found.indexOf(null) !== -1) console.log("vpn: operation=wired-read completion=unread");
        settled();
    }
    function launch(reader, argv, command) {
        deadline.restart();
        if (missing.indexOf(command) !== -1) {
            Qt.callLater(() => root.ended(reader.key, -1, "", command));
            return;
        }
        reader.completion = null;
        reader.command = argv;
        reader.running = true;
    }
    // A reader's end: CODE as Service.codeOf gives it, ABSENT the command
    // when it is not installed, else "".
    function ended(key, code, text, absent) {
        if (run === null) return;
        if (run.stale) {
            run = Object.assign({}, run, { queue: [] });
            return next();
        }
        if (key === "link") {
            const link = absent !== "" ? { kind: "unreadable" } : Logic.linkRead(code, text);
            if (link.kind !== "active") return found(null);
            run = Object.assign({}, run, { device: link.link });
            launch(routeReader, Logic.wiredRouteArgv(link.link), "nmcli");
        } else if (key === "route") {
            const route = absent !== "" ? null : Logic.wiredRoute(code, text);
            if (route === null) return found(null);
            run = Object.assign({}, run, { route: route });
            launch(neighReader, Logic.wiredNeighArgv(run.device, route), "ip");
        } else {
            found(absent !== "" ? null : Logic.wiredIdentity(run.route, code, text));
        }
    }
    function found(identity) {
        run = Object.assign({}, run, { found: run.found.concat([identity]) });
        next();
    }
    // A reader still out at the deadline is ended, and its end reads -1.
    function expired() {
        for (const reader of [linkReader, routeReader, neighReader]) if (reader.running) reader.signal(9);
    }
    Timer {
        id: deadline
        interval: Logic.WATCHDOG_MS
        onTriggered: root.expired()
    }

    // Process takes argv and owns the child for this service lifetime.
    // https://quickshell.org/docs/v0.3.1/types/Quickshell.Io/Process
    // Each reader inherits only PATH and LC_ALL; nmcli also reaches its
    // bus as the service's do.
    component Reader: Process {
        id: reader
        property string key: ""
        property var completion: null
        clearEnvironment: true
        environment: ({ PATH: Quickshell.env("PATH"), LC_ALL: "C" })
        stdout: StdioCollector { id: readerText; waitForEnd: true }
        stderr: StdioCollector { waitForEnd: true }
        onExited: (code, status) => { reader.completion = { code: code, status: status }; }
        // A run that never started emits runningChanged alone, and reads -1.
        onRunningChanged: {
            if (running) return;
            const code = completion === null || completion.status !== 0 ? -1 : completion.code;
            root.ended(key, code, readerText.text, "");
        }
    }
    Reader { id: linkReader; key: "link"; environment: root.nmcliEnvironment }
    Reader { id: routeReader; key: "route"; environment: root.nmcliEnvironment }
    Reader { id: neighReader; key: "neigh" }
}
