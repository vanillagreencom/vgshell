import QtQuick
import Quickshell
import Quickshell.Io
import "VpnLogic.js" as Logic

// One owner of the NetworkManager profile readers, actions and deadlines.
// Views hold a lease for the fast poll and use the plugin's IPC:
// lease {id,open}; action {kind,id} with the profile's uuid for
// profile-up, profile-down, profile-remove and profile-details; import,
// refresh and open. A password connect is no IPC action: the prompt that
// owns the masked field calls VpnLogic.submitConnect, which reaches
// connectWithPassword here directly with the one-use stdin closure.
// nmcli's output stays in this file: VpnLogic parses the fields a view
// shows and drops the rest, and a log line names the operation, its
// completion and its exit code alone.
Item {
    id: root
    property var shell: null
    property bool registered: false
    property var leases: ({})
    readonly property int leaseCount: Object.keys(leases).length
    readonly property int pollInterval: Logic.pollInterval(leaseCount > 0, shell === null ? 30 : shell.settings.pollSeconds)
    readonly property int scans: shell === null ? 0 : shell.requirements.revision
    // nmcli reaches the private test bus in validation and the session's
    // NetworkManager in use. No other caller environment is inherited.
    readonly property var nmcliEnvironment: ({ PATH: Quickshell.env("PATH"), HOME: Quickshell.env("HOME"), LC_ALL: "C",
        DBUS_SYSTEM_BUS_ADDRESS: Quickshell.env("DBUS_SYSTEM_BUS_ADDRESS") || null,
        DBUS_SESSION_BUS_ADDRESS: Quickshell.env("DBUS_SESSION_BUS_ADDRESS") || null, XDG_RUNTIME_DIR: Quickshell.env("XDG_RUNTIME_DIR") })
    readonly property bool profilesMissing: shell === null || shell.requirements.missing.indexOf("nmcli") !== -1
    property var listing: Logic.emptyProfiles("reading")
    // Per uuid: { service, server } from the one detail read of the
    // current uuid set, the address while activated, and the failure the
    // last `up` left, which stays until an `up` succeeds, the profile is
    // seen activated or it leaves the list; a requirements rescan also
    // clears a sign-in or missing-plugin failure (VpnLogic.afterRescan).
    // The problem line of the last failed action, { uuid, kind, text },
    // lives until the next action starts or VpnLogic.problemAfter finds
    // it no longer describes a listed profile.
    property var detailMap: ({})
    property string detailsRead: ""
    property var addresses: ({})
    property var failures: ({})
    property var addressQueue: []
    property var profileAction: null
    property var profileProblem: null
    // The password connect's stdin closure until its run starts or ends.
    property var connectFeed: null
    readonly property var profiles: Logic.compose(profilesMissing ? Logic.emptyProfiles("missing") : listing,
        detailMap, addresses, failures, profileAction, profileProblem === null ? "" : profileProblem.text)

    readonly property var connection: Logic.connection(profiles)

    function publish() {
        if (shell === null) return;
        const writes = Logic.statusWrites(connection, profiles);
        for (const write of writes) {
            const reply = shell.status.set(write[0], write[1]);
            if (reply !== "ok") console.warn("vpn: status " + write[0] + " " + reply);
        }
    }
    onConnectionChanged: publish()
    onProfilesChanged: publish()
    Component.onCompleted: Logic.attachConnect(root)
    Component.onDestruction: {
        Logic.releaseConnect(root);
        connectFeed = null;
    }
    onShellChanged: {
        if (shell === null) return;
        if (!registered) {
            registered = true;
            shell.ipc.handle("lease", arg => root.lease(arg));
            shell.ipc.handle("action", arg => root.actProfile(JSON.parse(arg)));
            shell.ipc.handle("import", () => root.importFile());
            shell.ipc.handle("refresh", () => root.refresh());
            shell.ipc.handle("open", arg => shell.surfaces.summon("panel", arg || "{}"));
            refresh();
        }
        publish();
    }
    onScansChanged: {
        failures = Logic.afterRescan(failures);
        profileProblem = Logic.problemAfter(profileProblem, listing.rows, failures);
        refresh();
    }
    onProfilesMissingChanged: {
        if (profilesMissing) listing = Logic.emptyProfiles("reading");
        else readProfiles();
    }
    function refresh() {
        readProfiles();
        return "ok";
    }

    function lease(arg) {
        const request = JSON.parse(arg);
        if (typeof request.id !== "string" || request.id === "" || typeof request.open !== "boolean") return "refused: lease=value";
        const next = Object.assign({}, leases);
        if (request.open) next[request.id] = true;
        else delete next[request.id];
        leases = next;
        if (request.open) refresh();
        return "ok";
    }

    // The exit code of a run that ended on its own, -1 for one a signal
    // ended or that never started, which leaves `completion` null.
    function codeOf(completion) {
        return completion === null || completion.status !== 0 ? -1 : completion.code;
    }
    function completionWord(code) {
        return code === -1 ? "interrupted" : code === 0 ? "invalid-reply" : "failed";
    }

    function readProfiles() {
        if (!registered || profilesMissing) return;
        if (profilesReader.running) { profilesReader.again = true; return; }
        profilesReader.completion = null;
        profilesReader.running = true;
        profilesDeadline.restart();
    }

    // A new list keeps only what still applies to its rows, then reads the
    // details of a changed uuid set and the address of each activated
    // profile that has none yet: an address lands a moment after
    // activation, so the next poll asks again.
    function listed(next) {
        listing = next;
        const rows = next.state === "available" ? next.rows : [];
        const kept = (map, keep) => {
            const out = {};
            for (const row of rows) if (map[row.uuid] !== undefined && keep(row)) out[row.uuid] = map[row.uuid];
            return out;
        };
        failures = kept(failures, row => row.state !== "activated");
        addresses = kept(addresses, row => row.state === "activated");
        profileProblem = Logic.problemAfter(profileProblem, rows, failures);
        if (next.state !== "available") return;
        if (Logic.detailsKey(next) !== detailsRead) readDetails();
        for (const row of rows) if (row.state === "activated" && addresses[row.uuid] === undefined) queueAddress(row.uuid);
    }

    Timer {
        interval: root.pollInterval
        repeat: true
        running: root.registered && !root.profilesMissing
        onTriggered: root.readProfiles()
    }
    Timer {
        id: profilesDeadline
        interval: Logic.WATCHDOG_MS
        onTriggered: profilesReader.signal(9)
    }
    // Process takes argv and owns the child for this service lifetime.
    // https://quickshell.org/docs/v0.3.1/types/Quickshell.Io/Process
    Process {
        id: profilesReader
        property var completion: null
        property bool again: false
        command: ["nmcli", "-t", "-f", "NAME,UUID,TYPE,STATE", "connection", "show"]
        clearEnvironment: true
        environment: root.nmcliEnvironment
        stdout: StdioCollector { id: profilesText; waitForEnd: true }
        stderr: StdioCollector { waitForEnd: true }
        onExited: (code, status) => { profilesReader.completion = { code: code, status: status }; }
        onRunningChanged: {
            if (running) return;
            profilesDeadline.stop();
            const code = root.codeOf(completion);
            const next = Logic.list(code, profilesText.text);
            if (next.state !== "available") {
                const diagnostic = "vpn: operation=profile-read completion=" + root.completionWord(code) + " code=" + code;
                // An optional availability read can fail normally. nmcli's
                // 1 is unspecified; 8 means NetworkManager is not running.
                // https://networkmanager.dev/docs/api/latest/nmcli.html#exit_status
                if (code === 1 || code === 8) console.log(diagnostic);
                else console.warn(diagnostic);
            }
            root.listed(next);
            if (again) { again = false; root.readProfiles(); }
        }
    }

    // One process reads the service and server of every listed profile.
    // A failed read leaves the set unread, so the next list asks again.
    function readDetails() {
        if (detailsReader.running) { detailsReader.again = true; return; }
        const key = Logic.detailsKey(listing);
        if (key === "") {
            detailMap = {};
            detailsRead = "";
            return;
        }
        detailsReader.key = key;
        detailsReader.completion = null;
        detailsReader.command = Logic.detailsArgv(key);
        detailsReader.running = true;
        detailsDeadline.restart();
    }
    Timer {
        id: detailsDeadline
        interval: Logic.WATCHDOG_MS
        onTriggered: detailsReader.signal(9)
    }
    Process {
        id: detailsReader
        property var completion: null
        property bool again: false
        property string key: ""
        clearEnvironment: true
        environment: root.nmcliEnvironment
        stdout: StdioCollector { id: detailsText; waitForEnd: true }
        stderr: StdioCollector { waitForEnd: true }
        onExited: (code, status) => { detailsReader.completion = { code: code, status: status }; }
        onRunningChanged: {
            if (running) return;
            detailsDeadline.stop();
            const code = root.codeOf(completion);
            const read = Logic.details(code, detailsText.text, key);
            if (read === null) {
                console.warn("vpn: operation=profile-details completion=" + root.completionWord(code) + " code=" + code);
            } else {
                root.detailMap = read;
                root.detailsRead = key;
            }
            if (again || (read !== null && Logic.detailsKey(root.listing) !== key)) { again = false; root.readDetails(); }
        }
    }

    function queueAddress(uuid) {
        if (addressQueue.indexOf(uuid) === -1 && !(addressReader.running && addressReader.uuid === uuid))
            addressQueue = addressQueue.concat([uuid]);
        readAddress();
    }
    function readAddress() {
        if (addressReader.running || addressQueue.length === 0) return;
        addressReader.uuid = addressQueue[0];
        addressQueue = addressQueue.slice(1);
        addressReader.completion = null;
        addressReader.command = Logic.addressArgv(addressReader.uuid);
        addressReader.running = true;
        addressDeadline.restart();
    }
    Timer {
        id: addressDeadline
        interval: Logic.WATCHDOG_MS
        onTriggered: addressReader.signal(9)
    }
    Process {
        id: addressReader
        property var completion: null
        property string uuid: ""
        clearEnvironment: true
        environment: root.nmcliEnvironment
        stdout: StdioCollector { id: addressText; waitForEnd: true }
        stderr: StdioCollector { waitForEnd: true }
        onExited: (code, status) => { addressReader.completion = { code: code, status: status }; }
        onRunningChanged: {
            if (running) return;
            addressDeadline.stop();
            const code = root.codeOf(completion);
            const found = Logic.address(code, addressText.text);
            const row = root.listing.rows.find(candidate => candidate.uuid === uuid);
            if (found === null) {
                console.warn("vpn: operation=profile-address completion=" + root.completionWord(code) + " code=" + code);
            } else if (found !== "" && row !== undefined && row.state === "activated") {
                const next = Object.assign({}, root.addresses);
                next[uuid] = found;
                root.addresses = next;
            }
            root.readAddress();
        }
    }

    function actProfile(request) {
        const plan = Logic.profileCommand(request, profiles);
        if (plan.refusal !== undefined) return plan.refusal;
        if (plan.address !== undefined) {
            const row = listing.rows.find(candidate => candidate.uuid === plan.address);
            if (row !== undefined && row.state === "activated") queueAddress(plan.address);
            return "ok";
        }
        return startAction(request.kind, request.id, plan.argv, null);
    }
    // VpnLogic.submitConnect's direct call: connect UUID with FEED writing
    // the passwd-file line once nmcli has started. Only FEED's closure
    // holds the password, and it is dropped when the run starts or ends.
    function connectWithPassword(uuid, feed) {
        const plan = Logic.passwordCommand(uuid, profiles);
        if (plan.refusal !== undefined) return plan.refusal;
        return startAction("profile-up", uuid, plan.argv, feed);
    }
    // One change at a time: FEED is null for a run whose stdin stays closed.
    function startAction(kind, uuid, argv, feed) {
        if (profileActor.running) return "busy";
        const row = profiles.rows.find(candidate => candidate.uuid === uuid);
        profileAction = { kind: kind, uuid: row.uuid, name: row.name, password: feed !== null };
        profileProblem = null;
        connectFeed = feed;
        profileActor.completion = null;
        profileActor.stdinEnabled = feed !== null;
        profileActor.command = argv;
        profileActor.running = true;
        profileActionDeadline.restart();
        return "ok";
    }
    // The deadline also bounds a password connect: openvpn asks for the
    // password again after a refusal and nmcli answers with the same line
    // until its own --wait ends (90 s by default), so the kill here ends it
    // first (VGS-1932 verify-first § 6, read from NetworkManager-openvpn
    // 1.12.5 and nmcli 1.58.1 source, not run).
    Timer {
        id: profileActionDeadline
        interval: Logic.ACTION_MS
        onTriggered: profileActor.signal(9)
    }
    Process {
        id: profileActor
        property var completion: null
        clearEnvironment: true
        environment: root.nmcliEnvironment
        stdout: StdioCollector { id: actorText; waitForEnd: true }
        stderr: StdioCollector { id: actorErrors; waitForEnd: true }
        // Quickshell 0.3.1 Process.write needs a started child, and turning
        // stdinEnabled off closes stdin after the queued bytes, which nmcli
        // reads to its end before it activates:
        // https://quickshell.org/docs/v0.3.1/types/Quickshell.Io/Process
        onStarted: {
            const once = root.connectFeed;
            root.connectFeed = null;
            if (once !== null) once(profileActor);
        }
        onExited: (code, status) => { profileActor.completion = { code: code, status: status }; }
        onRunningChanged: {
            if (running) return;
            // A run that never started emits runningChanged alone.
            root.connectFeed = null;
            profileActionDeadline.stop();
            const code = root.codeOf(completion);
            const action = root.profileAction;
            const output = actorText.text + "\n" + actorErrors.text;
            const failed = action.kind === "profile-remove" ? Logic.removeOutcome(code, output) === "failed" : code !== 0;
            if (code !== 0) console.warn("vpn: operation=" + action.kind + " completion=" + (code === -1 ? "interrupted" : "failed") + " code=" + code);
            if (action.kind === "profile-up") {
                const next = Object.assign({}, root.failures);
                if (code === 0) delete next[action.uuid];
                else {
                    const row = root.profiles.rows.find(candidate => candidate.uuid === action.uuid);
                    next[action.uuid] = Logic.upFailure(code, output, row === undefined ? { type: "", service: "" } : row, action.password === true);
                }
                root.failures = next;
            }
            if (failed) root.profileProblem = { uuid: action.uuid, kind: action.kind, text: Logic.problem(action.kind, action.name, code) };
            root.profileAction = null;
            root.readProfiles();
        }
    }
    function importFile() {
        if (profiles.state !== "available") return "refused: import=unavailable";
        const needed = ["nmcli", "gum"].filter(command => shell.requirements.missing.indexOf(command) !== -1);
        // The notice opens the import once it installs what is missing, so
        // a notice that shows is the press's answer.
        if (needed.length > 0)
            return shell.requirements.offer(needed, "import") === "ok" ? "ok" : "refused: import=missing-tool";
        return shell.tui.run("import", [], () => root.readProfiles());
    }

}
