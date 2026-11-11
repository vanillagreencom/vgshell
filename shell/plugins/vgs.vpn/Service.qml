import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import "VpnLogic.js" as Logic

// One owner of the NetworkManager profile readers, actions and deadlines,
// and of the kill switch's state file and status read (D129), and of
// Connect automatically's decision (VpnLogic.autoConnectPlan).
// Views hold a lease for the fast poll and use the plugin's IPC:
// lease {id,open}; action {kind,id} with the profile's uuid for
// profile-up, profile-down, profile-remove, profile-details and
// profile-check, the leak check (LeakCheck); import,
// refresh (the edited uuid, or empty for metadata), open and kill-switch
// with the mode to write, block, block-lan or off. A password
// connect is no IPC action: its masked prompt calls VpnLogic.submitConnect, which reaches
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
    // Per uuid: { service, server } from the one detail read, or null
    // after a failed read with no previous metadata. An absent entry
    // has not answered yet. This is separate from a read's empty service.
    // The other maps hold the address while activated and the failure the
    // last `up` left, which stays until an `up` succeeds, the profile is
    // seen activated or it leaves the list. An editor handoff clears every
    // failure of its uuid; a requirements rescan clears sign-in and
    // missing-plugin failures (VpnLogic.afterRescan).
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

    // The status entry reads the drop the blocked-traffic notice shows, as
    // the flyout header does.
    readonly property var blocked: Logic.blockedNotice(killSwitch, profiles)
    readonly property var connection: Logic.connection(profiles, blocked)

    // The kill switch, once its system step is set up: the last read of
    // the state file (VpnLogic.readState, or kind reading, missing or
    // unreadable), the last status line (VpnLogic.killStatus, null before
    // the first), the one state write in flight (writeState), a profile
    // change waiting on its write or on the table, { kind, uuid, name,
    // argv, previous, phase, expired }, and the problem
    // the last kill switch change left. The status is read on the profile
    // poll; only a connect's wait for the table reads it faster, for at
    // most Logic.ARM_WAIT_MS.
    readonly property var killStep: shell === null ? undefined : shell.system.state["vpn-kill-switch"]
    readonly property bool killReady: killStep !== undefined && killStep.state === "ready"
    // The state file can still be read and written while the step reads
    // needed, as after its path unit failed, so a connect's rollback can
    // still clear its profile.
    readonly property bool killWritable: killReady || (killStep !== undefined && killStep.state === "needed")
    property var killFile: ({ kind: "reading" })
    property var killStatus: null
    property var stateWrite: null
    // The serial of the last write writeState started.
    property int stateSerial: 0
    property var stage: null
    property bool killChanging: false
    property string killProblem: ""
    // From a write's end until the next poll's status read ends: the grace
    // a sync takes to follow the write (VpnLogic.killSwitchState).
    property bool killSettling: false
    // A poll ticked during the grace: the next status read that starts
    // ends it when it ends.
    property bool killSettlePoll: false
    // Connect automatically: the profile the setting names, "" for Off,
    // the trusted networks' uuids, the saved networks of the last list
    // read (VpnLogic.networkList) and the decision's memory, whose problem
    // line Settings and the section draw.
    readonly property string autoChoice: shell === null || typeof shell.settings.autoConnect !== "string" ? "" : shell.settings.autoConnect
    readonly property var trusted: Logic.trustedUuids(shell === null ? [] : shell.settings.trustedNetworks)
    property var networks: Logic.emptyNetworks("reading")
    property var autoMemory: Logic.autoConnectStart()
    readonly property string autoProblem: Logic.autoConnectText(autoMemory.problem)
    readonly property var vpnChoices: Logic.vpnChoices(profiles)
    // NetworkManager's own device signals, read only while a profile is
    // chosen: each device's state, which Quickshell binds to the device's
    // State property, and the device list, which holds Wi-Fi and Ethernet
    // devices (Quickshell 0.3.2 src/network/nm/device.cpp and backend.cpp,
    // revision 2b4501a). A change reads the list again, so a network that
    // comes up is decided at once, not at the next poll; the poll still
    // covers a modem or a tether. Networking looks for NetworkManager once,
    // when first read (scripts/smoke/devices.sh), as vgs.network's does.
    readonly property string networkEvents: autoChoice === "" ? ""
        : Networking.devices.values.map(device => device.name + "=" + device.state).join(" ")
    onNetworkEventsChanged: readProfiles()
    onAutoChoiceChanged: readProfiles()
    onAutoProblemChanged: publishAuto()
    onVpnChoicesChanged: publishAuto()
    onNetworksChanged: publishAuto()

    readonly property var killSwitch: Logic.killSwitchState(killStep, killFile, killStatus, killChanging || stage !== null, killProblem, killSettling)
    readonly property var killSetup: Logic.killSwitchSetup(killStep)
    onKillSwitchChanged: publish()
    onKillSetupChanged: publish()
    onKillReadyChanged: {
        if (!killReady) killStatus = null;
        readKillSwitch();
    }
    onKillWritableChanged: {
        if (killWritable) return;
        // A read the gate now ignores would never answer the write.
        if (stateWrite !== null) stateInterrupted("not-writable");
        killFile = { kind: "reading" };
    }

    function publish() {
        if (shell === null) return;
        const writes = Logic.statusWrites(connection, profiles, killSwitch, killSetup);
        for (const write of writes) {
            const reply = shell.status.set(write[0], write[1]);
            if (!shell.status.isOk(reply)) console.warn("vpn: status " + write[0] + " " + reply);
        }
    }
    onConnectionChanged: publish()
    onProfilesChanged: publish()
    // Connect automatically's entries, each written only when its value
    // changed, since the list read builds new ones at every poll.
    property var reported: ({})
    function report(key, value) {
        if (shell === null) return;
        const text = JSON.stringify(value);
        if (reported[key] === text) return;
        const reply = shell.status.set(key, value);
        if (!shell.status.isOk(reply)) {
            console.warn("vpn: status " + key + " " + reply);
            return;
        }
        reported = Object.assign({}, reported, { [key]: text });
    }
    function publishAuto() {
        report("autoConnectProblem", autoProblem === "" ? null : autoProblem);
        report("vpnChoices", vpnChoices);
        report("networks", networks);
        report("networkChoices", Logic.networkChoices(networks));
    }
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
            shell.ipc.handle("refresh", arg => root.refresh(arg));
            shell.ipc.handle("open", arg => shell.surfaces.summon("panel", arg || "{}"));
            shell.ipc.handle("kill-switch", arg => root.setKillSwitch(arg));
            refresh();
        }
        publish();
        publishAuto();
    }
    onScansChanged: refresh()
    onProfilesMissingChanged: {
        if (profilesMissing) {
            listing = Logic.emptyProfiles("reading");
            networks = Logic.emptyNetworks("reading");
        } else readProfiles();
    }
    function refresh(editedUuid) {
        // A pane open or activation passes an empty UUID to read metadata;
        // an editor handoff passes its UUID to also forget learned failures.
        // Invalidation lives here even if that pane is then destroyed.
        // An in-flight detail read coalesces a new read through readDetails.
        failures = Logic.afterRescan(failures, editedUuid);
        profileProblem = Logic.problemAfter(profileProblem, listing.rows, failures);
        detailsRead = "";
        readDetails();
        readProfiles();
        readKillSwitch();
        return "ok";
    }

    function lease(arg) {
        const request = JSON.parse(arg);
        if (typeof request.id !== "string" || request.id === "" || typeof request.open !== "boolean") return "refused: lease=value";
        const next = Object.assign({}, leases);
        if (request.open) next[request.id] = true;
        else delete next[request.id];
        leases = next;
        if (request.open) {
            readProfiles();
            readKillSwitch();
        }
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

    // A run's end keeps its change in flight until a list read started
    // after it lands (listed): until then the list still shows the profile
    // as it was before the run, which, with the kill switch's status still
    // holding from the arm wait, reads as a drop. A read already running
    // started before the end, so the one after it decides.
    function runEnded() {
        if (!registered || profilesMissing) {
            profileAction = null;
            return;
        }
        profileAction = Object.assign({}, profileAction, { ended: true, stale: profilesReader.running });
        readProfiles();
    }

    // A new list keeps only what still applies to its rows, then reads the
    // details of a changed uuid set and the address of each activated
    // profile that has none yet: an address lands a moment after
    // activation, so the next poll asks again.
    function listed(next) {
        listing = next;
        if (profileAction !== null && profileAction.ended === true)
            profileAction = profileAction.stale ? Object.assign({}, profileAction, { stale: false }) : null;
        const rows = next.state === "available" ? next.rows : [];
        const kept = (map, keep) => {
            const out = {};
            for (const row of rows) if (map[row.uuid] !== undefined && keep(row)) out[row.uuid] = map[row.uuid];
            return out;
        };
        failures = kept(failures, row => row.state !== "activated");
        addresses = kept(addresses, row => row.state === "activated");
        profileProblem = Logic.problemAfter(profileProblem, rows, failures);
        autoConnect();
        if (next.state !== "available") return;
        if (Logic.detailsKey(next) !== detailsRead) readDetails();
        for (const row of rows) if (row.state === "activated" && addresses[row.uuid] === undefined) queueAddress(row.uuid);
    }

    Timer {
        interval: root.pollInterval
        repeat: true
        running: root.registered && (!root.profilesMissing || root.killReady)
        onTriggered: {
            root.readProfiles();
            // One poll of grace after a write: a read this poll starts ends it.
            if (root.killSettling) root.killSettlePoll = true;
            root.readKillSwitch();
        }
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
            // The same read holds the saved networks Connect automatically
            // decides over, set before the list that decides.
            root.networks = Logic.networkList(code, profilesText.text);
            root.listed(next);
            if (again) { again = false; root.readProfiles(); }
        }
    }

    // One process reads the service and server of every listed profile.
    // A failed read leaves the set unread, so the next list asks again.
    function readDetails() {
        if (!registered || profilesMissing) return;
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
                const next = Object.assign({}, root.detailMap);
                for (const uuid of key.split(" ")) if (next[uuid] === undefined) next[uuid] = null;
                root.detailMap = next;
                root.detailsRead = "";
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
        const plan = Logic.profileCommand(request, profiles, shell.requirements.missing, Logic.killSwitchOn(killSwitch), killReady ? killSwitch.meantOn : "");
        if (plan.refusal !== undefined) return plan.refusal;
        if (plan.check !== undefined) {
            const row = listing.rows.find(candidate => candidate.uuid === plan.check);
            return startCheck(plan.check, row !== undefined && row.state === "activated");
        }
        if (plan.address !== undefined) {
            const row = listing.rows.find(candidate => candidate.uuid === plan.address);
            if (row !== undefined && row.state === "activated") queueAddress(plan.address);
            return "ok";
        }
        const reply = startAction(request.kind, request.id, plan.argv, null);
        // A profile turned off here, by its switch or Turn VPN off, stays
        // off until the next network change (VpnLogic.autoConnectPlan).
        if (request.kind === "profile-down" && reply === "ok") autoMemory = Logic.autoConnectOff(autoMemory);
        return reply;
    }
    // Connect automatically's decision over the list read that just
    // landed: a connect goes through the switch's own IPC action, so the
    // kill switch arms first; a refusal leaves its problem line, and a busy
    // service keeps the network change for the next read.
    function autoConnect() {
        const plan = Logic.autoConnectPlan(autoMemory, autoChoice, trusted, networks, profiles, profileAction !== null || stateWrite !== null);
        autoMemory = plan.memory;
        if (plan.uuid === "") return;
        const reply = actProfile({ kind: "profile-up", id: plan.uuid });
        console.log("vpn: operation=auto-connect completion=" + reply);
        if (reply === "busy") autoMemory = Logic.autoConnectBusy(autoMemory);
        else if (reply !== "ok") {
            const row = profiles.rows.find(candidate => candidate.uuid === plan.uuid);
            autoMemory = Logic.autoConnectRefused(autoMemory, row.name,
                Logic.rowView(row, profiles, shell.requirements.missing, Logic.killSwitchOn(killSwitch)).reason);
        }
    }
    // VpnLogic.submitConnect's direct call: connect UUID with FEED writing
    // the passwd-file line once nmcli has started. Only FEED's closure
    // holds the password, and it is dropped when the run starts or ends.
    function connectWithPassword(uuid, feed) {
        const plan = Logic.passwordCommand(uuid, profiles, shell.requirements.missing, Logic.killSwitchOn(killSwitch));
        if (plan.refusal !== undefined) return plan.refusal;
        return startAction("profile-up", uuid, plan.argv, feed);
    }
    // One change at a time: FEED is null for a run whose stdin stays closed.
    // With the kill switch set up, the state file names the profile first
    // (VpnLogic.meantOnPlan over a fresh read), and a connect with the
    // switch on waits for the table; the change shows in flight meanwhile.
    function startAction(kind, uuid, argv, feed) {
        if (profileAction !== null || stateWrite !== null) return "busy";
        const row = profiles.rows.find(candidate => candidate.uuid === uuid);
        profileAction = { kind: kind, uuid: row.uuid, name: row.name, password: feed !== null };
        profileProblem = null;
        connectFeed = feed;
        if (!killReady) {
            launch(argv);
            return "ok";
        }
        stage = { kind: kind, uuid: row.uuid, name: row.name, type: row.type, argv: argv, previous: "", phase: "write" };
        writeState(file => {
            const plan = Logic.meantOnPlan(kind, row.uuid, true, file, row.type);
            return plan === null || plan.patch === undefined ? null : plan.patch;
        }, (ok, before, nudged) => root.staged(ok, before, nudged), kind === "profile-up");
        return "ok";
    }
    // ARGV null is a disconnect of a profile NetworkManager already
    // dropped (VpnLogic.profileCommand): the state file's write was the
    // change, so nmcli does not run.
    function launch(argv) {
        if (argv === null) {
            profileAction = null;
            readProfiles();
            readKillStatus();
            return;
        }
        profileActor.completion = null;
        profileActor.stdinEnabled = connectFeed !== null;
        profileActor.command = argv;
        profileActor.running = true;
        profileActionDeadline.restart();
    }
    // The staged change's state write ended over BEFORE, the file it read:
    // a profile the switch refuses runs nothing, a connect with the switch
    // on waits for the table, any other change runs.
    function staged(ok, before, nudged) {
        if (!ok) {
            stageEnded("write", "", false);
            return;
        }
        const plan = Logic.meantOnPlan(stage.kind, stage.uuid, true, before, stage.type);
        if (plan !== null && plan.refuse !== undefined) {
            stageEnded("unavailable", plan.refuse, false);
            return;
        }
        if (plan === null || !plan.arm) {
            const argv = stage.argv;
            stage = null;
            launch(argv);
            return;
        }
        stage = Object.assign({}, stage, { phase: "arm", expired: false, previous: plan.previous, answered: false, nudged: nudged === true, refusal: "" });
        armDeadline.restart();
        readKillStatus();
    }
    // A status read during the wait: a table armed for this profile runs
    // the connect; the root half's refusal of it, or the end of the wait,
    // puts the state file's profile back and runs nothing, so the block
    // does not hold for a profile that never connected. `answered` records
    // whether any read in the wait gave a line.
    function armRead() {
        const outcome = Logic.armOutcome(killStatus, stage.uuid);
        if (outcome !== "failed" && !stage.answered) stage = Object.assign({}, stage, { answered: true });
        if (outcome === "armed") {
            armDeadline.stop();
            armRetry.stop();
            const argv = stage.argv;
            stage = null;
            launch(argv);
        } else if (outcome === "unavailable" && !stage.nudged) {
            armDeadline.stop();
            rollBack("unavailable", killStatus.reason);
        } else if (outcome === "unavailable") {
            // After a nudge the table already named this profile, so its
            // refusal can be the line from before the nudged sync: it waits
            // like any other, and decides only at the deadline.
            stage = Object.assign({}, stage, { refusal: killStatus.reason });
            if (stage.expired) waitEnd();
            else armRetry.restart();
        } else if (stage.expired) waitEnd();
        else armRetry.restart();
    }
    // The wait ended with no armed table: ask the core for a fresh probe
    // of the step first, whose answer names the cause (probed), so a step
    // that reads needed, as after its units failed, points to Set up, as
    // the row then does.
    function waitEnd() {
        armRetry.stop();
        stage = Object.assign({}, stage, { phase: "probe" });
        const reply = shell === null ? "refused" : shell.system.refresh(() => root.probed());
        if (reply !== "ok") probed();
    }
    // The fresh probe answered: `setup` while the step reads needed,
    // `unchecked` when no read in the wait gave a line, else `timeout`.
    function probed() {
        if (stage === null || stage.phase !== "probe") return;
        if (Logic.stepWord(killStep) === "setup") rollBack("setup", "");
        else if (stage.refusal !== "") rollBack("unavailable", stage.refusal);
        else rollBack(stage.answered ? "timeout" : "unchecked", "");
    }
    // The wait's deadline: with no read running the wait ends now; with
    // one running, its end decides (armRead).
    function armExpired() {
        if (stage === null || stage.phase !== "arm") return;
        stage = Object.assign({}, stage, { expired: true });
        if (!killReader.running) waitEnd();
    }
    function rollBack(cause, reason) {
        armRetry.stop();
        stage = Object.assign({}, stage, { phase: "rollback" });
        const uuid = stage.uuid;
        const previous = stage.previous;
        // Only while the file still names this profile.
        const reply = writeState(file => file.kind === "valid" && file.meantOn.toLowerCase() === uuid ? { meantOn: previous } : null, ok => {
            if (!ok) console.warn("vpn: operation=kill-switch-rollback completion=failed");
            root.stageEnded(cause, reason, !ok);
        });
        if (reply !== "ok") stageEnded(cause, reason, true);
    }
    // A staged change that ran nothing leaves its problem line, kind
    // `kill-switch`, which stays until the next change starts. UNRESTORED
    // is a rollback that did not land, so the file still names the profile.
    function stageEnded(cause, reason, unrestored) {
        const ended = stage;
        stage = null;
        connectFeed = null;
        profileAction = null;
        if (cause !== "write") console.warn("vpn: operation=kill-switch-arm completion=" + cause + (reason === "" ? "" : " reason=" + reason));
        profileProblem = { uuid: ended.uuid, kind: "kill-switch", text: Logic.stageProblem(ended.kind, ended.name, cause, reason, unrestored) };
        readProfiles();
        readKillSwitch();
    }

    // The switches' IPC: MODE, one of block, block-lan or off, written as
    // kill-switch=.
    function setKillSwitch(mode) {
        if (Logic.KILL_MODES.indexOf(mode) === -1) return "refused: kill-switch=mode";
        if (!killReady) return "refused: kill-switch=not-set-up";
        if (stateWrite !== null || stage !== null) return "busy";
        killChanging = true;
        killProblem = "";
        writeState(() => ({ mode: mode }), ok => {
            root.killChanging = false;
            root.killProblem = ok ? "" : "VGS could not save the kill switch setting.";
            root.readKillStatus();
        });
        return "ok";
    }

    // The state file and the status line, on the profile poll. A read
    // waits while a write is in flight.
    function readKillSwitch() {
        if (!registered || !killReady) return;
        if (stateWrite === null) stateFile.reload();
        readKillStatus();
    }
    // A status read the leak check asked for runs while the step is not
    // set up too (VpnLogic.checkKillPlan).
    function readKillStatus() {
        if (!registered || !(killReady || checkWantsStatus)) return;
        if (killReader.running) { killReader.again = true; return; }
        killReader.forCheck = checkWantsStatus;
        checkWantsStatus = false;
        killReader.settles = killSettlePoll;
        killSettlePoll = false;
        killReader.completion = null;
        killReader.running = true;
        killDeadline.restart();
    }

    // The shell's one writer of the state file (VGS-2401's sign-in writer
    // goes through it too), as the root script's header has a writer make
    // it: read it again, so a key another writer changed since the last
    // poll is kept; unless PATCH_OF(that read) is null or changes nothing,
    // fill a dot-prefixed temporary file beside it, set its mode, rename it
    // over the state file, create the pending file, and read the write
    // back. With NUDGE, an unchanged file still gets the pending file, so
    // the root half reads it again. The rename commits the write: a
    // failure after it is logged and
    // the write counts as made, so a connect's arm wait decides. A second
    // write while one runs answers `busy`; stateDeadline ends a write
    // whose answer never comes. DONE(ok, before) runs once, BEFORE the file
    // as read.
    function writeState(patchOf, done, nudge) {
        // A step an interrupted write left running still holds its Process.
        if (stateWrite !== null || stateModer.running || stateMover.running || pendingMaker.running) return "busy";
        stateSerial += 1;
        stateWrite = { serial: stateSerial, phase: "read", patchOf: patchOf, done: done, text: "", before: { kind: "reading" }, committed: false,
            nudge: nudge === true };
        stateDeadline.restart();
        // With the step undone meanwhile, reads are gated off.
        if (!killWritable) writeEnded(false);
        else stateFile.reload();
        return "ok";
    }
    // A load of the state file during a write: the read before it, or the
    // read-back after the rename. Any other phase ignores it.
    function stateRead() {
        if (stateWrite === null) return;
        if (stateWrite.phase === "verify") {
            if (stateFile.text() !== stateWrite.text) console.warn("vpn: operation=kill-switch-write completion=read-back-differs");
            writeEnded(true);
            return;
        }
        if (stateWrite.phase !== "read") return;
        const patch = stateWrite.patchOf(killFile);
        const text = patch === null ? null : Logic.stateChange(killFile, patch);
        stateWrite = Object.assign({}, stateWrite, { before: killFile });
        if (patch === null) writeEnded(true);
        else if (text === null) writeEnded(false);
        else if (text === stateFile.text()) {
            if (!stateWrite.nudge) writeEnded(true);
            else {
                // The read-back then finds the text the file holds.
                stateWrite = Object.assign({}, stateWrite, { text: text, nudged: true });
                makePending();
            }
        } else {
            const temp = Logic.tempPath(Math.random);
            stateWrite = Object.assign({}, stateWrite, { phase: "save", text: text, temp: temp });
            // An empty path drops the text the last write left, which
            // setText compares with and would skip (FileView::setText).
            tempFile.path = "";
            tempFile.path = temp;
            tempFile.setText(text);
        }
    }
    // The temporary file is written: give it the contract's mode 0644,
    // whatever the shell's umask, then rename it.
    function tempSaved() {
        if (stateWrite === null || stateWrite.phase !== "save") return;
        stateWrite = Object.assign({}, stateWrite, { phase: "mode" });
        stateModer.command = ["chmod", "0644", "--", stateWrite.temp];
        stateModer.completion = null;
        stateModer.serial = stateWrite.serial;
        stateModer.running = true;
    }
    // The temporary file's write failed: it can hold part of the text.
    function tempSaveFailed() {
        if (stateWrite !== null && stateWrite.phase === "save") removeTemp();
    }
    function moded(code, serial) {
        if (stateWrite === null || stateWrite.phase !== "mode" || stateWrite.serial !== serial) return;
        if (code !== 0) {
            removeTemp();
            return;
        }
        stateWrite = Object.assign({}, stateWrite, { phase: "rename" });
        stateMover.command = ["mv", "-fT", "--", stateWrite.temp, Logic.STATE_FILE];
        stateMover.completion = null;
        stateMover.serial = stateWrite.serial;
        stateMover.running = true;
    }
    // The rename ended with CODE: the write is committed, so create the
    // pending file; or remove the temporary file and fail.
    function renamed(code, serial) {
        if (stateWrite === null || stateWrite.phase !== "rename" || stateWrite.serial !== serial) return;
        if (code !== 0) {
            removeTemp();
            return;
        }
        stateWrite = Object.assign({}, stateWrite, { committed: true });
        makePending();
    }
    function makePending() {
        stateWrite = Object.assign({}, stateWrite, { phase: "pending" });
        pendingMaker.command = ["touch", "--", Logic.PENDING_FILE];
        pendingMaker.completion = null;
        pendingMaker.serial = stateWrite.serial;
        pendingMaker.running = true;
    }
    // A step before the rename failed: remove the temporary file and fail.
    function removeTemp() {
        tempRemover.command = ["rm", "-f", "--", stateWrite.temp];
        tempRemover.running = true;
        writeEnded(false);
    }
    // The pending file's creation ended with CODE: read the write back. A
    // failed touch is logged; the rename already reached the path unit's
    // directory watch.
    function pendingMade(code, serial) {
        if (stateWrite === null || stateWrite.phase !== "pending" || stateWrite.serial !== serial) return;
        if (code !== 0) console.warn("vpn: operation=kill-switch-pending completion=failed code=" + code);
        stateWrite = Object.assign({}, stateWrite, { phase: "verify" });
        stateFile.reload();
    }
    // The write's deadline: end any step still running; a write past its
    // rename counts as made.
    function stateExpired() {
        if (stateWrite !== null) stateInterrupted("deadline");
    }
    // A write its answer did not end, for CAUSE: end any step still
    // running, then the write, as made once committed, else failed. The
    // ended write's steps are tagged with its serial, so a late end of one
    // is never taken as a later write's.
    function stateInterrupted(cause) {
        for (const step of [stateModer, stateMover, pendingMaker]) if (step.running) step.signal(9);
        console.warn("vpn: operation=kill-switch-write completion=" + cause + " phase=" + stateWrite.phase);
        writeEnded(stateWrite.committed === true);
    }
    function writeEnded(ok) {
        const write = stateWrite;
        stateWrite = null;
        stateDeadline.stop();
        if (!ok) console.warn("vpn: operation=kill-switch-write completion=failed phase=" + write.phase);
        killSettling = true;
        killSettlePoll = false;
        // A read started before this end cannot end this write's grace.
        killReader.settles = false;
        write.done(ok, write.before, write.nudged === true);
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
            root.runEnded();
            // nmcli's `up` ends once the profile is activated.
            if (action.kind === "profile-up" && code === 0) root.startCheck(action.uuid, true);
        }
    }
    Timer {
        id: armRetry
        interval: Logic.ARM_RETRY_MS
        onTriggered: root.readKillStatus()
    }
    Timer {
        id: armDeadline
        interval: Logic.ARM_WAIT_MS
        onTriggered: root.armExpired()
    }
    Timer {
        id: stateDeadline
        interval: Logic.WATCHDOG_MS
        onTriggered: root.stateExpired()
    }
    // The state file the root units arm from, read only, once the step is
    // set up. FileView reports a missing file through loadFailed as
    // FileNotFound (https://quickshell.org/docs/v0.3.1/types/Quickshell.Io/FileView).
    // FileView::operationFinished emits loaded or loadFailed before it
    // clears its live operation (Quickshell 0.3.1 src/io/fileview.cpp), so
    // a read started inside a handler would be dropped and never answer;
    // each handler's next step runs after it, through Qt.callLater (the
    // VGS-2397 sandbox run hung without it).
    // The path stays fixed: a path change cancels a live read with no
    // signal (FileView::setPath, cancelAsync), and a write waits on that
    // read. Its loads count only while the step is set up.
    FileView {
        id: stateFile
        path: Logic.STATE_FILE
        watchChanges: false
        printErrors: false
        onLoaded: {
            if (!root.killWritable) return;
            root.killFile = Logic.readState(text());
            if (root.stateWrite !== null) Qt.callLater(root.stateRead);
        }
        onLoadFailed: error => {
            if (!root.killWritable) return;
            const missing = error === FileViewError.FileNotFound;
            root.killFile = { kind: missing ? "missing" : "unreadable" };
            if (!missing) console.warn("vpn: operation=kill-switch-read completion=failed error=" + error);
            if (root.stateWrite === null) return;
            if (missing && root.stateWrite.phase === "read") Qt.callLater(root.stateRead);
            else if (root.stateWrite.phase === "verify") root.writeEnded(true);
            else if (root.stateWrite.phase === "read") root.writeEnded(false);
        }
    }
    // The temporary file of one write, a new path each time. blockWrites
    // makes setText write before it returns and emit saved or saveFailed
    // from it, outside any FileView operation; atomicWrites off writes the
    // file itself, which the rename then publishes; preload off reads
    // nothing at the new path (FileView reference and src/io/fileview.cpp,
    // FileView::saveSync).
    FileView {
        id: tempFile
        preload: false
        blockWrites: true
        atomicWrites: false
        watchChanges: false
        printErrors: false
        onSaved: { if (root.stateWrite !== null && root.stateWrite.phase === "save") root.tempSaved(); }
        onSaveFailed: error => root.tempSaveFailed()
    }
    // chmod sets the mode the contract names; mv -T renames within one
    // directory, rename(2), so a reader finds the old file or the new one;
    // touch creates the pending file the path unit starts a sync for. None
    // inherits the caller's environment past PATH.
    Process {
        id: stateModer
        property var completion: null
        property int serial: 0
        clearEnvironment: true
        environment: ({ PATH: Quickshell.env("PATH"), LC_ALL: "C" })
        onExited: (code, status) => { stateModer.completion = { code: code, status: status }; }
        onRunningChanged: { if (!running) root.moded(root.codeOf(completion), serial); }
    }
    Process {
        id: stateMover
        property var completion: null
        property int serial: 0
        clearEnvironment: true
        environment: ({ PATH: Quickshell.env("PATH"), LC_ALL: "C" })
        onExited: (code, status) => { stateMover.completion = { code: code, status: status }; }
        onRunningChanged: { if (!running) root.renamed(root.codeOf(completion), serial); }
    }
    Process {
        id: pendingMaker
        property var completion: null
        property int serial: 0
        clearEnvironment: true
        environment: ({ PATH: Quickshell.env("PATH"), LC_ALL: "C" })
        onExited: (code, status) => { pendingMaker.completion = { code: code, status: status }; }
        onRunningChanged: { if (!running) root.pendingMade(root.codeOf(completion), serial); }
    }
    Process {
        id: tempRemover
        clearEnvironment: true
        environment: ({ PATH: Quickshell.env("PATH"), LC_ALL: "C" })
    }
    Timer {
        id: killDeadline
        interval: Logic.WATCHDOG_MS
        onTriggered: killReader.signal(9)
    }
    // `vgs-kill-switch status` reads the line from /run/vgs-kill-switch.sock
    // as a plain user (the root script's header); the step installs it in
    // /usr/local/bin. A failed read is the reading `unreachable`, logged
    // once when it starts.
    Process {
        id: killReader
        property var completion: null
        property bool again: false
        // Started after a poll ticked in the grace (readKillStatus).
        property bool settles: false
        // Started after the leak check asked for a status (checkStatus).
        property bool forCheck: false
        command: Logic.STATUS_ARGV
        clearEnvironment: true
        environment: ({ PATH: Quickshell.env("PATH"), LC_ALL: "C" })
        stdout: StdioCollector { id: killText; waitForEnd: true }
        stderr: StdioCollector { id: killErrors; waitForEnd: true }
        onExited: (code, status) => { killReader.completion = { code: code, status: status }; }
        onRunningChanged: {
            if (running) return;
            killDeadline.stop();
            const code = root.codeOf(completion);
            const next = Logic.killStatus(code, killText.text, killErrors.text);
            // A read the leak check asked for while the step is not set up
            // is the check's alone; the kill switch row keeps its own.
            if (root.killReady) {
                const failed = next.state === "unreachable" || next.state === "unreadable";
                if (failed && (root.killStatus === null || root.killStatus.state !== next.state))
                    console.warn("vpn: operation=kill-switch-status completion=" + next.state + " code=" + code);
                root.killStatus = next;
            }
            if (forCheck) {
                forCheck = false;
                leakCheck.statusRead(Logic.checkKillStatus(root.killReady, next, completion !== null));
            }
            if (settles) {
                settles = false;
                root.killSettling = false;
            }
            if (again) { again = false; root.readKillStatus(); }
            else if (root.stage !== null && root.stage.phase === "arm") root.armRead();
        }
    }

    // The leak check (LeakCheck) of UUID, ACTIVE while it is connected:
    // `ok`, `busy` while another runs, or refused for a profile it does
    // not read (VpnLogic.checkReads).
    function startCheck(uuid, active) {
        if (!Logic.checkReads(profiles.rows.find(candidate => candidate.uuid === uuid))) return "refused: profile=type";
        const reply = leakCheck.start(uuid, active);
        if (reply !== "ok") console.log("vpn: operation=leak-check completion=" + reply);
        return reply;
    }
    // A status read the next start of the status reader hands the check;
    // while the step rules out a table, there is none to read.
    property bool checkWantsStatus: false
    function checkStatus() {
        if (Logic.checkKillPlan(killStep) === "none") {
            leakCheck.statusRead(null);
            return;
        }
        checkWantsStatus = true;
        readKillStatus();
    }
    LeakCheck {
        id: leakCheck
        nmcliEnvironment: root.nmcliEnvironment
        missing: root.shell === null ? [] : root.shell.requirements.missing
        rows: root.listing.state === "available" ? root.listing.rows : null
        action: root.profileAction
        onStatusWanted: root.checkStatus()
        onValueChanged: {
            if (root.shell === null || value === null) return;
            const reply = root.shell.status.set("leakCheck", value);
            if (!root.shell.status.isOk(reply)) console.warn("vpn: status leakCheck " + reply);
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
