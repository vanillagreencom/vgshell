import QtQuick
import Quickshell
import Quickshell.Io
import "VpnLogic.js" as Logic

// The leak check's readers (VpnLogic.leakCheck), owned by the service:
// one check at a time, of one WireGuard profile, which the service starts
// when a connect it ran ends and on a press of Check, never on a timer.
// It reads the tunnel's interface first; once that answers, the route of
// each family and systemd-resolved's settings; with those and the kill
// switch status in, for a connected profile, the public address through
// the tunnel's interface, only when VpnLogic.publicPlan places every
// lookup of the provider's name in the tunnel. The kill switch status
// comes from the service's one status reader, which it starts on
// statusWanted and hands back through statusRead. A declared requirement
// that is missing runs no process. `value` is the published `leakCheck`:
// { uuid, busy, active, result }, ACTIVE the profile connected when the
// check started. `lastKill`, the last check's kill switch reading, is the
// one reading kept, for its count's rise.
Item {
    id: root
    property var nmcliEnvironment: ({})
    property var missing: []
    property var value: null
    property var lastKill: null
    // The rows of the service's last list NetworkManager answered, or
    // null, and the profile change in flight: a result they outdate goes
    // (VpnLogic.checkStale).
    property var rows: null
    property var action: null
    // The check in flight: { uuid, active, readings, waiting, dropped },
    // WAITING the readings not yet in, DROPPED once a list outdated it.
    property var run: null

    signal statusWanted()

    // A dropped check asks the provider nothing: the tunnel it would ask
    // through may be gone, and curl's lookup of the provider's name would
    // then go to another network's DNS. A question already out is ended.
    onRowsChanged: judgeStale()
    onActionChanged: judgeStale()
    function judgeStale() {
        if (rows === null || !Logic.checkStale(value, rows, action)) return;
        if (run === null) {
            value = Object.assign({}, value, { result: null });
            return;
        }
        run = Object.assign({}, run, { dropped: true });
        if (publicReader.running) publicReader.signal(9);
    }

    function start(uuid, active) {
        if (run !== null) return "busy";
        run = { uuid: uuid, active: active === true, readings: { uuid: uuid, public: null }, waiting: ["link", "status"], dropped: false };
        value = { uuid: uuid, busy: true, active: active === true, result: null };
        deadline.restart();
        launch(linkReader, Logic.linkArgv(uuid), "nmcli");
        statusWanted();
        return "ok";
    }
    // STATUS: VpnLogic.killStatus's reading, or null while the kill
    // switch is not set up.
    function statusRead(status) {
        if (run !== null && run.waiting.indexOf("status") !== -1) settle("status", status);
    }

    function launch(reader, argv, command) {
        if (missing.indexOf(command) !== -1) {
            Qt.callLater(() => root.ended(reader.key, -1, "", "", command));
            return;
        }
        reader.completion = null;
        reader.command = argv;
        reader.running = true;
    }
    // A reader's end: CODE as Service.codeOf gives it, ABSENT the command
    // when it is not installed, else "".
    function ended(key, code, text, errors, absent) {
        if (run === null || run.waiting.indexOf(key) === -1) return;
        if (code !== 0) console.log("vpn: operation=leak-check reading=" + key + " completion=" + (absent !== "" ? "missing" : code === -1 ? "interrupted" : "failed") + " code=" + code);
        const notInstalled = { kind: "missing", command: absent };
        switch (key) {
        case "link": linked(absent !== "" ? { kind: "unreadable" } : Logic.linkRead(code, text)); break;
        case "ipv4":
        case "ipv6": settle(key, absent !== "" ? notInstalled : Logic.routeRead(code, text, errors)); break;
        case "dns": settle(key, absent !== "" ? notInstalled : Logic.dnsRead(code, text)); break;
        case "public": settle(key, absent !== "" ? { kind: "failed", reason: "missing" } : Logic.insights(code, text)); break;
        }
    }
    // With the interface read, the routes and the DNS settings are read.
    function linked(link) {
        const readers = link.kind === "unreadable" ? [] : [[ipv4Reader, Logic.routeArgv("ipv4"), "ip"],
            [ipv6Reader, Logic.routeArgv("ipv6"), "ip"], [dnsReader, Logic.DNS_ARGV, "varlinkctl"]];
        const readings = Object.assign({}, run.readings, { link: link });
        if (link.kind === "unreadable") Object.assign(readings, { ipv4: link, ipv6: link, dns: link });
        run = Object.assign({}, run, { readings: readings, waiting: run.waiting.filter(key => key !== "link").concat(readers.map(entry => entry[0].key)) });
        for (const entry of readers) launch(entry[0], entry[1], entry[2]);
        finish();
    }
    function settle(key, reading) {
        const readings = Object.assign({}, run.readings);
        readings[key] = reading;
        run = Object.assign({}, run, { readings: readings, waiting: run.waiting.filter(other => other !== key) });
        finish();
    }
    // With every other reading in, a connected profile's check asks the
    // provider, or records why it does not; the deadline starts again for
    // the question.
    function finish() {
        if (run.waiting.length > 0) return;
        if (run.active && run.readings.public === null) {
            const plan = run.dropped ? { kind: "failed", reason: "inactive" } : Logic.publicPlan(run.readings);
            if (plan.kind === "ask") {
                run = Object.assign({}, run, { waiting: ["public"] });
                deadline.restart();
                launch(publicReader, Logic.insightsArgv(plan.link), "curl");
                return;
            }
            settle("public", plan);
            return;
        }
        deadline.stop();
        const result = Logic.leakCheck(run.readings, lastKill);
        lastKill = result.kill;
        value = { uuid: run.uuid, busy: false, active: run.active, result: run.dropped ? null : result };
        run = null;
    }
    // A reading still out at the deadline ends unread: a reader is ended,
    // and its end reads -1; a status the service did not hand back reads
    // as a read that never started.
    function expired() {
        if (run === null) return;
        for (const reader of [linkReader, ipv4Reader, ipv6Reader, dnsReader, publicReader]) if (reader.running) reader.signal(9);
        if (run.waiting.indexOf("status") !== -1) settle("status", Logic.killStatus(-1, "", ""));
    }
    // curl's own bound is INSIGHTS_SECONDS; the deadline leaves it room to end.
    Timer {
        id: deadline
        interval: (Logic.INSIGHTS_SECONDS + 5) * 1000
        onTriggered: root.expired()
    }

    // Process takes argv and owns the child for this service lifetime.
    // https://quickshell.org/docs/v0.3.1/types/Quickshell.Io/Process
    // Each reader inherits only PATH and LC_ALL, so curl reads no proxy
    // from the caller; nmcli also reaches its bus as the service's do.
    component Reader: Process {
        id: reader
        property string key: ""
        property var completion: null
        clearEnvironment: true
        environment: ({ PATH: Quickshell.env("PATH"), LC_ALL: "C" })
        stdout: StdioCollector { id: readerText; waitForEnd: true }
        stderr: StdioCollector { id: readerErrors; waitForEnd: true }
        onExited: (code, status) => { reader.completion = { code: code, status: status }; }
        // A run that never started emits runningChanged alone, and reads -1.
        onRunningChanged: {
            if (running) return;
            const code = completion === null || completion.status !== 0 ? -1 : completion.code;
            root.ended(key, code, readerText.text, readerErrors.text, "");
        }
    }
    Reader { id: linkReader; key: "link"; environment: root.nmcliEnvironment }
    Reader { id: ipv4Reader; key: "ipv4" }
    Reader { id: ipv6Reader; key: "ipv6" }
    Reader { id: dnsReader; key: "dns" }
    Reader { id: publicReader; key: "public" }
}
