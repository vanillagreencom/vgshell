import QtQuick
import Quickshell.Io
import Quickshell.Networking
import "VpnLogic.js" as Logic

// One sign-in pause for the current outer link. Network uses the same
// NetworkManager result to offer Sign in. The state file keeps the
// deadline across a shell restart, and nft expires the exception even
// if this service stops.
Item {
    id: root
    required property var controller

    // https://quickshell.org/docs/v0.3.1/types/Quickshell.Networking/Networking/
    // NetworkManager supplies both the successful portal probe and its
    // connectivity updates. No probe or browser is started here.
    readonly property string link: !controller.killReady || !Networking.connectivityCheckEnabled ? ""
        : Networking.devices.values.filter(device => device.connected
            && (device.type === DeviceType.Wired || (device.type === DeviceType.Wifi && Networking.wifiEnabled)))
            .map(device => device.name).sort().join(" ")
    readonly property string connectivity: link === "" ? ""
        : Networking.connectivity === NetworkConnectivity.Portal ? "portal"
        : Networking.connectivity === NetworkConnectivity.Full ? "full" : "other"
    // A lost list has no identity. A disconnected device set is a known
    // change, even if the list did not answer.
    readonly property var outerKey: link === "" ? ""
        : controller.networks.state === "available" ? link + ":" + Logic.networkKey(controller.networks) : null
    readonly property var file: controller.killFile
    readonly property var status: controller.killStatus
    readonly property bool ready: controller.registered && controller.killReady && !controller.profilesMissing
    readonly property bool busy: controller.changeBusy
    readonly property bool actuating: commandKind !== ""
    readonly property bool blocksConnect: session !== null && !["done", "reset-failed", "resume-failed"].includes(session.phase)
    // File and status updates can come from a single read. Coalesce before
    // deciding, since FileView cannot start a fresh read inside onLoaded.
    readonly property var observed: [ready, outerKey, connectivity, file, status, busy, controller.profiles, controller.leakCheckRunning]
    onObservedChanged: Qt.callLater(advance)

    property var session: null
    property string commandKind: ""
    property int reads: 0

    function advance() {
        if (!ready || file.kind !== "valid") return;
        const now = Math.floor(Date.now() / 1000);
        const uuid = Logic.portalProfile(file);
        if (session === null) {
            if (busy || !outerKey || uuid === "" || controller.profiles.state !== "available"
                || !controller.profiles.rows.some(row => row.uuid === uuid && row.type === "wireguard")) return;
            if (file.portalUntil !== "0") {
                if (status === null || status.state === "unreachable" || status.state === "unreadable") return;
                // The previous service's link identity is gone. Close
                // its exception before restoring the saved VPN intent.
                session = { uuid: uuid, link: outerKey, until: file.portalUntil, phase: "closing" };
            } else {
                // A running leak check may rely on the closed kernel
                // rule for its outside DNS. Let its bounded read finish.
                if (controller.leakCheckRunning) return;
                const lease = Logic.portalOpen(file, status, outerKey, connectivity, now);
                if (lease === null) return;
                session = Object.assign(lease, { phase: "saving" });
                const reply = controller.writeState(current => {
                    const plan = Logic.portalOpen(current, status, outerKey, connectivity, Math.floor(Date.now() / 1000));
                    return plan?.uuid === lease.uuid && outerKey === lease.link ? { portalUntil: lease.until } : null;
                }, ok => {
                    session = Object.assign({}, session, { phase: ok && file.portalUntil === lease.until ? "opening" : "done" });
                    requestRead();
                    Qt.callLater(advance);
                });
                if (reply !== "ok") session = null;
                return;
            }
        }
        if (session.phase === "saving" || session.phase === "clearing") return;
        if (session.phase === "opening" || session.phase === "open") {
            if (uuid !== session.uuid || file.mode === "off" || Logic.portalShouldClose(session, outerKey, connectivity, now)) {
                phase("closing");
            } else if (session.phase === "opening" && !busy && status?.reason === "portal-open" && status.profile === session.uuid) {
                phase("open");
                run("disable");
            } else if (session.phase === "opening") requestRead();
        }
        if (session.phase === "wait-expiry" && now >= Number(session.until)) {
            waitForClosed();
            return;
        }
        if (["open", "opening", "wait-expiry"].includes(session.phase) && !expiry.running) startExpiry();
        if (session.phase === "closing" && !controller.killBusy) {
            if (file.portalUntil === Logic.PORTAL_CLOSED || file.portalUntil === "0") {
                waitForClosed();
                return;
            }
            phase("clearing");
            const reply = controller.writeState(current => current.kind === "valid" && current.portalUntil !== "0"
                ? { portalUntil: Logic.PORTAL_CLOSED } : null, ok => {
                    if (ok && [Logic.PORTAL_CLOSED, "0"].includes(file.portalUntil)) waitForClosed();
                    else {
                        // The writer's own busy signal can wake this
                        // instance. Let nft expire the lease without
                        // another attempt against the same directory.
                        phase("wait-expiry");
                        Qt.callLater(advance);
                    }
                });
            if (reply !== "ok") phase("closing");
        }
        if (session.phase === "closed" && !busy && controller.profiles.state === "available") {
            if (uuid !== session.uuid || !controller.profiles.rows.some(row => row.uuid === uuid && row.type === "wireguard")) phase("done");
            else if (status !== session.before && Logic.portalClosed(file, status)) {
                phase("resuming");
                run("enable");
            } else requestRead();
        }
        if (session.phase === "done" && !busy && (connectivity === "full" || (outerKey !== null && outerKey !== session.link))) {
            if (file.portalUntil === "0") { session = null; Qt.callLater(advance); return; }
            const stored = file.portalUntil;
            phase("resetting");
            const reply = controller.writeState(current => current.kind === "valid" && current.portalUntil === stored
                && (stored === Logic.PORTAL_CLOSED || Number(stored) <= now) ? { portalUntil: "0" } : null,
                ok => { if (ok && file.portalUntil === "0") session = null; else phase("reset-failed"); });
            if (reply !== "ok") phase("done");
        }
    }

    function startExpiry() {
        expiry.interval = Math.max(1, Math.min(Logic.PORTAL_SECONDS * 1000, Number(session.until) * 1000 - Date.now()));
        expiry.start();
    }
    function waitForClosed() {
        phase("closed");
        // An answer read before the write or deadline cannot confirm
        // that the kernel removed the exception.
        session = Object.assign({}, session, { before: status });
        requestRead();
    }
    function phase(next) {
        session = Object.assign({}, session, { phase: next });
        reads = 0;
        statusRetry.stop();
        if (!["opening", "open", "wait-expiry"].includes(next)) expiry.stop();
    }
    function requestRead() {
        if (statusRetry.running || reads * Logic.ARM_RETRY_MS >= Logic.ARM_WAIT_MS) return;
        reads++;
        statusRetry.start();
        controller.readKillStatus();
    }
    function run(kind) {
        commandKind = kind;
        actor.completion = null;
        actor.command = Logic.portalCommand(kind, session.uuid);
        actor.running = true;
        commandDeadline.restart();
    }
    function ended(code) {
        const kind = commandKind;
        commandDeadline.stop();
        if (code !== 0 && !(kind === "down" && Logic.downOutcome(code) === "inactive"))
            console.warn("vpn: operation=portal-" + kind + " completion=failed code=" + code);
        if (kind === "disable" && code === 0 && session.phase === "open") {
            run("down");
            return;
        }
        if (kind === "enable" && code === 0 && status?.reason !== "tunnel-up") {
            run("up");
            return;
        }
        commandKind = "";
        // Keep the marker if NetworkManager could not restore autoconnect.
        // A restart can still recover it, and a manual Reconnect is allowed.
        if (kind === "enable" && code !== 0) phase("resume-failed");
        else if (kind === "enable" || kind === "up") phase("done");
        else if (code !== 0 && !(kind === "down" && Logic.downOutcome(code) === "inactive") && session.phase === "open") phase("closing");
        controller.readProfiles();
        Qt.callLater(advance);
    }
    Timer { id: expiry; objectName: "vpn-portal-expiry"; onTriggered: root.advance() }
    Timer { id: statusRetry; interval: Logic.ARM_RETRY_MS; onTriggered: root.advance() }
    Timer { id: commandDeadline; interval: Logic.ACTION_MS; onTriggered: actor.signal(9) }
    // Process owns the nmcli child and emits runningChanged on failure to
    // start. https://quickshell.org/docs/v0.3.1/types/Quickshell.Io/Process/
    Process {
        id: actor
        property var completion: null
        clearEnvironment: true
        environment: root.controller.nmcliEnvironment
        stdout: StdioCollector { waitForEnd: true }
        stderr: StdioCollector { waitForEnd: true }
        onExited: (code, status) => { actor.completion = { code: code, status: status }; }
        onRunningChanged: if (!running && root.commandKind !== "") root.ended(root.controller.codeOf(completion))
    }
}
