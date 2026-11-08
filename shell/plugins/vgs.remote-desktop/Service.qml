import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "Remote.js" as Remote

// The one owner of the session probe, its event cue and its poll, the SSH
// host reading, every gliff launch and the end of a session while hosting
// is off. Hyprland reports a capture stopped when frames pause and nothing
// when gliff-server exits later, so only the 2 s poll, which runs while a
// session is active, sees a session end (Omarchy's remote-session
// Service.qml). Hosting off: the core's permission block refuses
// gliff-server's capture and keyboard, but Hyprland 0.57.0 has no
// permission for a virtual pointer (DynamicPermissionManager.hpp), so the
// service also ends each gliff-server it finds.
Item {
    id: root

    property var shell: null
    property bool registered: false

    readonly property string sessionsHelper: decodeURIComponent(String(Qt.resolvedUrl("helper/sessions.py")).replace(/^file:\/\//, ""))
    readonly property string hostsHelper: decodeURIComponent(String(Qt.resolvedUrl("helper/hosts.py")).replace(/^file:\/\//, ""))

    readonly property bool hosting: shell === null || shell.settings.hosting !== false
    readonly property var profiles: shell === null ? [] : shell.settings.profiles
    readonly property var items: shell === null ? ({}) : shell.manifest.schema.profiles.items
    readonly property var missing: shell === null ? [] : shell.requirements.missing
    readonly property string ssh: stepState("service-sshd")
    readonly property string permission: shell === null || shell.hyprland.permissions === null ? "" : shell.hyprland.permissions

    // The last good reading: the sessions and the SSH hosts.
    property var sessions: []
    property bool probedOnce: false
    property var hosts: []
    readonly property var session: Remote.sessionValue(sessions, hosts)
    readonly property bool active: session.active
    property bool pending: false
    property int probeExit: 0
    // Until when the next gliff window opens full screen.
    property double fullscreenUntil: 0
    // Sessions being ended or ended, as "pid start" to the row, kept only
    // while a probe still lists them.
    property var ended: ({})
    property var ending: []
    property int endExit: 0
    property int hostsExit: 0

    // The published forms, one change handler each.
    readonly property var sessionStatus: probedOnce ? session : null
    readonly property string hostingProblem: Remote.hostingText(hosting, ssh, missing.indexOf("gliff-server") === -1, permission)
    readonly property var sshStatus: Remote.sshStep(hosting, ssh)
    readonly property var connectRows: Remote.launcherRows(profiles, items)
    onSessionStatusChanged: if (registered) set("session", sessionStatus)
    onHostingProblemChanged: if (registered) set("hostingProblem", hostingProblem === "" ? null : hostingProblem)
    onSshStatusChanged: if (registered) set("ssh", sshStatus)
    onConnectRowsChanged: if (registered) set("connectRows", connectRows)
    onHostingChanged: if (registered && !hosting) refresh()

    function stepState(name) {
        const step = shell === null ? undefined : shell.system.state[name];
        return step === undefined ? "" : step.state;
    }

    function set(key, value) {
        const reply = shell.status.set(key, value);
        if (!shell.status.isOk(reply)) console.warn("remote-desktop: status " + key + " " + reply);
    }

    function lastLine(text) {
        const lines = String(text).trim().split("\n");
        return lines[lines.length - 1];
    }

    function notify(title, message) {
        const reply = shell.notify.send({ title: title, message: message, icon: "screen-share", tone: "info" });
        if (!shell.status.isOk(reply)) console.warn("remote-desktop: notify " + reply);
    }

    onShellChanged: {
        if (shell === null || registered) return;
        registered = true;
        shell.shortcut.register("connect", "Open a remote desktop", item => root.connect(String(item)));
        shell.shortcut.register("connect-first", "Open first computer", () => {
            if (root.profiles.length > 0) root.connect(root.profiles[0].name);
        });
        shell.ipc.handle("connect", arg => root.connect(String(arg)));
        shell.status.handleRefresh("hosts", () => root.readHosts());
        set("session", sessionStatus);
        set("hostingProblem", hostingProblem === "" ? null : hostingProblem);
        set("ssh", sshStatus);
        set("connectRows", connectRows);
        readHosts();
        refresh();
    }

    function refresh() {
        if (prober.running) { pending = true; return; }
        pending = false;
        prober.running = true;
    }

    // Quickshell 0.3.1 Process drains its parsers before it clears
    // running (as vgs.clipboard's Service.qml states), so both collectors
    // hold the whole run here.
    function probed() {
        let found = null;
        try {
            if (probeExit === 0) found = Remote.parseSessions(proberOut.text);
        } catch (error) {
            console.warn(error.message);
        }
        // A failed read keeps the last reading: it is no idle reading.
        if (found === null) {
            console.warn("remote-desktop: probe=failed exit=" + probeExit + " " + lastLine(proberErr.text));
        } else {
            sessions = found;
            probedOnce = true;
            const kept = {};
            found.forEach(row => { if (ended[row.pid + " " + row.start]) kept[row.pid + " " + row.start] = true; });
            ended = kept;
            if (!hosting) endSessions(found);
        }
        if (pending) Qt.callLater(refresh);
    }

    function endSessions(found) {
        const fresh = found.filter(row => !ended[row.pid + " " + row.start]);
        if (fresh.length === 0 || ender.running) return;
        const next = Object.assign({}, ended);
        fresh.forEach(row => { next[row.pid + " " + row.start] = true; });
        ended = next;
        ending = fresh;
        ender.command = ["python3", sessionsHelper, "end"].concat(...fresh.map(row => [String(row.pid), row.start]));
        ender.running = true;
    }

    // Notifies the sessions the ender reports ended; any other session
    // leaves `ended`, so the next probe tries again.
    function endsRead() {
        const results = {};
        enderOut.text.split("\n").forEach(line => { const words = line.split(" "); if (words.length === 2) results[words[0]] = words[1]; });
        if (endExit !== 0) console.warn("remote-desktop: end=failed exit=" + endExit + " " + lastLine(enderErr.text));
        const done = ending.filter(row => results[String(row.pid)] === "ended");
        const next = Object.assign({}, ended);
        ending.filter(row => results[String(row.pid)] !== "ended" && results[String(row.pid)] !== "gone").forEach(row => { delete next[row.pid + " " + row.start]; });
        ended = next;
        ending = [];
        if (done.length > 0)
            notify("Remote session ended", Remote.tooltip(Remote.sessionValue(done, hosts)).title + " ended, because hosting is off.");
        refresh();
    }

    function readHosts() {
        if (!hostReader.running) hostReader.running = true;
        return "ok";
    }

    function hostsRead() {
        let read = null;
        try {
            if (hostsExit === 0) read = JSON.parse(hostReaderOut.text).hosts;
        } catch (error) {}
        if (!Array.isArray(read)) {
            console.warn("remote-desktop: hosts=unreadable exit=" + hostsExit + " " + lastLine(hostReaderErr.text));
            return;
        }
        hosts = read;
        set("hosts", Remote.hostChoices(hosts));
        if (shell.settings.seeded === true) return;
        // The one automatic write: the computers SSH knows, while the user
        // has none and the plugin has never seeded, so a removal stays.
        if (profiles.length === 0) {
            const reply = shell.configure.set("profiles", Remote.seedProfiles(hosts, shell.manifest.schema.profiles.defaults));
            if (reply !== "ok") console.warn("remote-desktop: seed " + reply);
        }
        const seeded = shell.configure.set("seeded", true);
        if (seeded !== "ok") console.warn("remote-desktop: seeded " + seeded);
    }

    // The one place a connect is refused: a keyed log line and a
    // notification in plain words, whichever route asked.
    function refuse(key, message) {
        console.warn("remote-desktop: connect refused: " + key);
        notify("Could not connect", message);
        return "refused: " + key;
    }

    // Opens gliff with profile NAME's options. Missing tools raise the
    // core's requirement notice, which installs them in one press.
    function connect(name) {
        const profile = profiles.find(item => item.name === name);
        if (profile === undefined) return refuse("profile=" + name, "This computer is no longer in your Remote desktop list.");
        if (missing.indexOf("gliff") !== -1 || missing.indexOf("systemd-cat") !== -1)
            return shell.requirements.offer(["gliff", "systemd-cat"]);
        const built = Remote.argv(profile);
        if (built.field === "host")
            return refuse("profile=" + name + " field=host", "The Computer of this entry is not a computer name. Change it in [Remote desktop settings](page:vgs.remote-desktop/Settings/profiles).");
        if (built.field === "output")
            return refuse("profile=" + name + " field=output", "One screen needs a Screen name for " + profile.host + ". Choose one in [Remote desktop settings](page:vgs.remote-desktop/Settings/profiles).");
        console.info("remote-desktop: connect profile=" + profile.name + " journal=" + Remote.JOURNAL_IDENTIFIER);
        const check = serverCheck.createObject(root, { profile: Object.assign({}, profile), viewer: built.argv });
        check.start();
        return "ok";
    }

    function checked(check, completion) {
        const profile = check.profile;
        Qt.callLater(() => check.destroy());
        if (completion !== null && completion.status === 0 && completion.code === 1)
            return refuse("profile=" + profile.name + " server=missing host=" + profile.host,
                profile.host + " has no remote desktop server. On that computer, install gliff from [Remote desktop Setup](page:vgs.remote-desktop/Setup).");
        // An unavailable read, including a timeout, leaves connecting to
        // gliff as before; it establishes nothing about the remote server.
        // createObject's property map exposes the saved argv as a QML
        // sequence; detached's judge needs a JS array (remote-desktop
        // smoke, scripts/validate 2026-11-08).
        const reply = shell.run.detached(Array.from(check.viewer));
        if (reply !== "ok") return refuse("profile=" + profile.name + " " + reply, "VGS could not start gliff.");
        if (profile.window === "fullscreen") fullscreenUntil = Date.now() + 15000;
        return "ok";
    }

    Component {
        id: serverCheck
        Item {
            id: check
            objectName: "remote-desktop-connect-check"
            required property var profile
            required property var viewer
            property var completion: null
            function start() { reader.running = true; }
            // Process.running is false after a failed start too; no exit
            // then means an unavailable read. The service owns both the
            // process and deadline, and destroying it kills the child.
            // https://quickshell.org/docs/v0.3.1/types/Quickshell.Io/Process
            Process {
                id: reader
                objectName: "remote-desktop-ssh-check"
                command: Remote.checkArgv(check.profile)
                stdout: StdioCollector {}
                stderr: StdioCollector {}
                onExited: (code, status) => { check.completion = { code: code, status: status }; }
                onRunningChanged: if (!running) root.checked(check, check.completion)
            }
            Timer {
                interval: 5000
                running: reader.running
                onTriggered: reader.signal(9)
            }
        }
    }

    // gliff sets its Wayland app id to its program name, "gliff"
    // (omacom/gliff crates/gliff/src/main.rs, glib::set_prgname), and
    // Hyprland's `openwindow` data is ADDRESS,WORKSPACE,CLASS,TITLE.
    // fullscreenWindow acts on the focused window, so the window is
    // focused and read back first.
    function fullscreen(address) {
        fullscreenUntil = 0;
        const focused = shell.compositor.focusWindow(address);
        if (focused !== "ok") { console.warn("remote-desktop: fullscreen step=focus " + focused); return; }
        shell.compositor.readWindows(read => {
            if (root.shell === null) return;
            const client = read.ok ? read.clients.find(c => c.address === address) : undefined;
            if (client === undefined || client.focusHistoryID !== 0) {
                console.warn("remote-desktop: fullscreen step=read " + (read.ok ? "focus=" + (client === undefined ? "gone" : client.focusHistoryID) : read.error));
                return;
            }
            const reply = root.shell.compositor.fullscreenWindow("fullscreen", "set");
            if (reply !== "ok") console.warn("remote-desktop: fullscreen step=set " + reply);
        });
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            // `screencast` comes with every capture's start and stop, so it
            // is only a cue to probe; `screencastv2` follows each one and
            // is left alone, so one change costs one probe.
            if (event.name === "screencast") { debounce.restart(); return; }
            if (event.name !== "openwindow" || root.fullscreenUntil < Date.now()) return;
            const parts = String(event.data).split(",");
            if (parts.length >= 3 && parts[2] === "gliff") root.fullscreen("0x" + parts[0].toLowerCase());
        }
    }

    Timer {
        id: debounce
        interval: 150
        onTriggered: root.refresh()
    }

    Timer {
        objectName: "remote-desktop-poll"
        interval: 2000
        repeat: true
        running: root.active
        onTriggered: root.refresh()
    }

    Process {
        id: prober
        command: ["python3", root.sessionsHelper, "list"]
        stdout: StdioCollector { id: proberOut }
        stderr: StdioCollector { id: proberErr }
        onExited: (exitCode, exitStatus) => root.probeExit = exitStatus === 0 ? exitCode : -1
        onRunningChanged: if (!running) root.probed()
    }

    Process {
        id: ender
        stdout: StdioCollector { id: enderOut }
        stderr: StdioCollector { id: enderErr }
        onExited: (exitCode, exitStatus) => root.endExit = exitStatus === 0 ? exitCode : -1
        onRunningChanged: if (!running) root.endsRead()
    }

    Process {
        id: hostReader
        command: ["python3", root.hostsHelper]
        stdout: StdioCollector { id: hostReaderOut }
        stderr: StdioCollector { id: hostReaderErr }
        onExited: (exitCode, exitStatus) => root.hostsExit = exitStatus === 0 ? exitCode : -1
        onRunningChanged: if (!running) root.hostsRead()
    }
}
