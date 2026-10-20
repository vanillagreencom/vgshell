import QtQuick
import Quickshell
import Quickshell.Io
import "VpnLogic.js" as Logic

// One owner of the NetworkManager profile readers, actions and deadlines.
// Views hold a lease for the fast poll and use the plugin's IPC:
// lease {id,open}, action {kind,id} for profile-up/profile-down,
// import-wireguard, refresh and open. No Tailscale action is registered.
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
    property var profileSnapshot: Logic.emptyProfiles()
    property string profileAction: ""
    property string profileOperation: ""
    property string profileProblem: ""
    readonly property var profiles: Object.assign({}, profilesMissing ? Logic.emptyProfiles() : profileSnapshot,
        { action: profileAction, problem: profileProblem })

    readonly property var connection: Logic.connection(profilesMissing, profiles)

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
    onShellChanged: {
        if (shell === null) return;
        if (!registered) {
            registered = true;
            shell.ipc.handle("lease", arg => root.lease(arg));
            shell.ipc.handle("action", arg => root.actProfile(JSON.parse(arg)));
            shell.ipc.handle("import-wireguard", () => root.importWireguard());
            shell.ipc.handle("refresh", () => root.refresh());
            shell.ipc.handle("open", arg => shell.surfaces.summon("panel", arg || "{}"));
            refresh();
        }
        publish();
    }
    onScansChanged: refresh()
    onProfilesMissingChanged: {
        if (profilesMissing) profileSnapshot = Logic.emptyProfiles();
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

    function readProfiles() {
        if (!registered || profilesMissing) return;
        if (profilesReader.running) { profilesReader.again = true; return; }
        profilesReader.completion = null;
        profilesReader.running = true;
        profilesDeadline.restart();
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
        command: ["nmcli", "-t", "-f", "NAME,TYPE,STATE", "connection", "show"]
        clearEnvironment: true
        environment: root.nmcliEnvironment
        stdout: StdioCollector { id: profilesText; waitForEnd: true }
        stderr: StdioCollector { waitForEnd: true }
        onExited: (code, status) => { profilesReader.completion = { code: code, status: status }; }
        onRunningChanged: {
            if (running) return;
            profilesDeadline.stop();
            const code = root.codeOf(completion);
            root.profileSnapshot = Logic.profiles(code, profilesText.text);
            if (root.profileSnapshot.state === "unavailable") {
                const diagnostic = "vpn: operation=profile-read completion=" + (code === -1 ? "interrupted" : code === 0 ? "invalid-reply" : "failed") + " code=" + code;
                // An optional availability read can fail normally. nmcli's
                // 1 is unspecified; 8 means NetworkManager is not running.
                // https://networkmanager.dev/docs/api/latest/nmcli.html#exit_status
                if (code === 1 || code === 8) console.log(diagnostic);
                else console.warn(diagnostic);
            }
            if (again) { again = false; root.readProfiles(); }
        }
    }

    function actProfile(request) {
        const plan = Logic.profileCommand(request, profiles);
        if (plan.refusal !== undefined) return plan.refusal;
        if (profileActor.running) return "busy";
        profileAction = request.id;
        profileOperation = request.kind;
        profileProblem = "";
        profileActor.completion = null;
        profileActor.command = plan.argv;
        profileActor.running = true;
        profileActionDeadline.restart();
        return "ok";
    }
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
        stdout: StdioCollector { waitForEnd: true }
        stderr: StdioCollector { waitForEnd: true }
        onExited: (code, status) => { profileActor.completion = { code: code, status: status }; }
        onRunningChanged: {
            if (running) return;
            profileActionDeadline.stop();
            const code = root.codeOf(completion);
            if (code !== 0) {
                console.warn("vpn: operation=" + root.profileOperation + " completion=" + (code === -1 ? "interrupted" : "failed") + " code=" + code);
                root.profileProblem = code === -1 ? "NetworkManager did not answer." : "NetworkManager could not change this connection.";
            }
            root.profileOperation = "";
            root.profileAction = "";
            root.readProfiles();
        }
    }
    function importWireguard() {
        if (profiles.state !== "available") return "refused: import=unavailable";
        const needed = ["nmcli", "gum"].filter(command => shell.requirements.missing.indexOf(command) !== -1);
        // The notice opens the import once it installs what is missing, so
        // a notice that shows is the press's answer.
        if (needed.length > 0)
            return shell.requirements.offer(needed, "import-wireguard") === "ok" ? "ok" : "refused: import=missing-tool";
        return shell.tui.run("import-wireguard", [], () => root.readProfiles());
    }

}
