import QtQuick
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Services.UPower
import qs.Commons
import "PowerLogic.js" as Logic

// The Power service is the only reader of Quickshell's UPower service and
// of the power profiles daemon, the only writer of the power profile, and
// the only sender of low-battery notices. Widgets and panels read the
// status value and ask this service through IPC. Quickshell 0.3.1 documents
// UPower.displayDevice and UPower.onBattery.
//
// The profiles come from the daemon through gdbus, never from Quickshell's
// PowerProfiles singleton: in Quickshell 0.3.1 its constructor
// (src/services/upower/powerprofiles.cpp) connects its properties only when
// the daemon answers then or starts on its one launch request, so it never
// reads a daemon that appears later. One `gdbus monitor` child stays up and
// prints a line when the daemon's name gains or loses its owner and on each
// of its signals; every line starts one Properties.GetAll read, which is
// also the first read. gdbus's --system takes its address from
// DBUS_SYSTEM_BUS_ADDRESS when that is set and the standard socket when it
// is not, and monitor writes each line to a pipe as it happens (runs on
// GLib 2.88.3 against a mock daemon on a private bus), so the argv names no
// address.
//
// Installing the daemon's package adds only its D-Bus activation file,
// which makes the name activatable and changes no owner, so the watch
// prints nothing, while bin/vgshell-scan counts an activatable name as
// present. When a scan stops listing the service as missing, one more read
// runs: its GetAll, a method call to an activatable name, starts the
// daemon, and the watch then reports the new owner (dbus-daemon 1.16.2, a
// private bus with a service directory and python-dbusmock 0.38.1 as the
// activated daemon, 2026-10-19).
Item {
    id: root

    property var shell: null
    property bool registered: false
    property var sourceState: ({ ready: false, onBattery: false })
    property var noticeLatch: Logic.latchInitial()

    property var profile: Logic.profileView("")
    // A daemon line that arrived while a read ran: one more read follows.
    property bool profileReadStale: false
    // The newest profile asked for while a write ran: it is written next.
    property string profileWanted: ""
    readonly property bool upowerReady: UPower.displayDevice !== null && UPower.displayDevice.ready === true
    readonly property var battery: Logic.batteryView(UPower.displayDevice, UPower.onBattery)
    readonly property var view: ({ battery: battery, profile: profile })
    readonly property string viewKey: JSON.stringify(view)
    readonly property string noticeKey: JSON.stringify({
        battery: battery,
        onBattery: UPower.onBattery,
        low: shell === null ? 20 : shell.settings.lowThreshold,
        critical: shell === null ? 10 : shell.settings.criticalThreshold
    })
    readonly property string sourceKey: JSON.stringify({ ready: upowerReady, onBattery: UPower.onBattery })
    readonly property string profilesInterface: "org.freedesktop.UPower.PowerProfiles"
    readonly property var profilesBus: ["--system", "--dest", profilesInterface, "--object-path", "/org/freedesktop/UPower/PowerProfiles"]
    readonly property bool profilesMissing: shell !== null && shell.requirements.missing.indexOf(profilesInterface) !== -1
    readonly property var diskSleepStep: shell === null ? undefined : shell.system.state["disk-sleep"]
    // Wake on LAN is a setting of each wired NetworkManager connection,
    // which NetworkManager hands the device when it activates the
    // connection (act_stage2_config in src/core/devices/nm-device-ethernet.c,
    // NetworkManager 1.58.1), so a connection already up takes a new value
    // at its next activation. The wired devices come from
    // Quickshell.Networking (Quickshell 0.3.1 NetworkDevice.type,
    // .connected and .nmManaged, as vgs.network reads them); a device
    // NetworkManager does not manage activates none of its connections, so
    // it does not count. Quickshell lists no connections, so a pass lists
    // them with one nmcli run, then reads each wired one and writes it only
    // when it holds another value. Logic.wakeObserved decides when a pass
    // runs.
    readonly property bool nmcliPresent: shell !== null && shell.requirements.missing.indexOf("nmcli") === -1
    readonly property var wiredDevices: Networking.devices.values.filter(d => d.type === DeviceType.Wired && d.nmManaged)
    readonly property bool ethernetPresent: nmcliPresent && wiredDevices.length > 0
    readonly property bool wakeOn: shell !== null && shell.settings.wakeOnLan === true
    readonly property string wakeWired: wiredDevices.map(d => d.name + ":" + d.connected).sort().join(",")
    readonly property string wakeKey: JSON.stringify({ present: ethernetPresent, on: wakeOn, wired: wakeWired })
    property var wakeState: Logic.wakeInitial()
    // One pass: its flag value, the wired connections still to read, the
    // one read or written now, the first step that failed, and whether a
    // reading asked for a pass while this one ran: one more pass follows.
    property string wakeTarget: ""
    property var wakeQueue: []
    property string wakeConnection: ""
    property string wakeFailure: ""
    property bool wakeStale: false

    onShellChanged: {
        if (shell === null || registered) return;
        registered = true;
        shell.ipc.handle("profile", arg => root.profileRequest(arg));
        // The step resolves hdparm in safe system directories; the scan
        // can miss an installed command outside the session's PATH.
        shell.ipc.handle("disk-sleep", () => root.diskSleepNeedsInstall()
            ? root.shell.requirements.offer(["hdparm"]) : root.shell.status.act("diskSleep"));
        shell.shortcut.register("power-saver", "Use the power saver profile", () => root.setProfile("power-saver", true));
        shell.shortcut.register("balanced", "Use the balanced profile", () => root.setProfile("balanced", true));
        shell.shortcut.register("performance", "Use the performance profile", () => root.setProfile("performance", true));
        profileWatch.running = true;
        publish();
        observeWake();
        checkNotices();
    }
    onViewKeyChanged: publish()
    onDiskSleepStepChanged: publish()
    onNoticeKeyChanged: checkNotices()
    onSourceKeyChanged: observeSource()
    onEthernetPresentChanged: publish()
    onWakeKeyChanged: observeWake()
    onProfilesMissingChanged: {
        if (registered && !profilesMissing) readProfiles();
    }
    Component.onCompleted: observeSource()

    Connections {
        target: UPower
        function onOnBatteryChanged() {
            root.observeSource();
        }
    }

    // `battery` is the presence the Settings page shows the battery fields
    // by (their shownWhen), and `profiles` the one it shows the two
    // per-source profile fields by: a battery to switch on and a profiles
    // service to switch, since the service is optional. `profileRule` is
    // the Details line that says how the profile is set on this machine.
    // The status capability keeps a value it already holds, so a repeat
    // write changes nothing.
    function publish() {
        if (shell === null) return;
        report("power", root.view);
        report("battery", battery.present ? "present" : "absent");
        report("profiles", battery.present && profile.available ? "present" : "absent");
        report("profileRule", Logic.profileRuleText(battery.present));
        report("ethernet", ethernetPresent ? "present" : "absent");
        if (diskSleepStep !== undefined) {
            const install = diskSleepNeedsInstall();
            report("diskSleepInstall", install ? "present" : "absent");
            report("diskSleep", diskSleepValue(install));
        }
    }

    // Read the probe synchronously: its changed handler can run before
    // a binding derived from it updates. Details' direct system action
    // cannot open the missing tool's install as the pane's IPC route can.
    function diskSleepNeedsInstall() {
        return diskSleepStep !== undefined && diskSleepStep.state === "needed" && diskSleepStep.reason === "hdparm-missing";
    }

    // The core probes the step once for all holders. Publish nothing until
    // that reading arrives, so Details keeps its standard Checking state.
    function diskSleepValue(install) {
        switch (diskSleepStep.state) {
        case "absent": return { hidden: true };
        case "ready": return { tone: "ok", text: "Allowed", action: false };
        case "needed": return { tone: "warning", text: "Not allowed", action: !install };
        case "nixos": return { tone: "warning", text: "Needs your NixOS configuration", action: true };
        case "denied": return { tone: "warning", text: "Managed elsewhere", action: false, hint: "Another disk sleep rule is already installed" };
        case "unknown": return { tone: "warning", text: "Could not check", action: false, hint: "VGS could not read the hard disk setup" };
        }
        throw new Error("power: disk-sleep state=" + diskSleepStep.state);
    }

    function report(key, value) {
        const reply = shell.status.set(key, value);
        if (reply !== "ok") console.error("power: status " + key + " " + reply);
    }

    function profileRequest(arg) {
        const profile = String(arg || "");
        if (!Logic.validProfile(profile)) return "refused: profile=" + profile + " want=power-saver|balanced|performance";
        return setProfile(profile, true);
    }

    function setProfile(name, remember) {
        if (!profile.available) return "refused: profile=unavailable";
        if (!Logic.validProfile(name)) return "refused: profile=" + name + " want=power-saver|balanced|performance";
        if (profile.choices.indexOf(name) === -1) return "refused: profile=" + name + " reason=unavailable";
        writeProfile(name);
        const key = remember === true && shell !== null ? Logic.rememberedSetting(battery.present, UPower.onBattery) : "";
        if (key !== "") {
            const saved = shell.configure.set(key, name);
            if (saved !== "ok") console.warn("power: configure " + saved);
        }
        return name;
    }

    // The mark moves at once; the daemon's signal, or the read after a
    // refused write, then states what the daemon holds.
    function writeProfile(name) {
        profile = Logic.profileMarked(profile, name);
        if (profileWriter.running) {
            profileWanted = name;
            return;
        }
        profileWanted = "";
        profileWriter.command = ["gdbus", "call"].concat(profilesBus, ["--method", "org.freedesktop.DBus.Properties.Set", profilesInterface, "ActiveProfile", "<'" + name + "'>"]);
        profileWriter.running = true;
    }

    function readProfiles() {
        if (profileReader.running) {
            profileReadStale = true;
            return;
        }
        profileReadStale = false;
        profileReader.running = true;
    }

    function applySourceProfile() {
        if (shell === null || !profile.available) return;
        setProfile(Logic.profileForSource(UPower.onBattery, shell.settings, profile.choices), false);
    }

    function observeSource() {
        const result = Logic.sourceObserved(sourceState, upowerReady, UPower.onBattery, battery.present);
        sourceState = result.state;
        if (result.apply) applySourceProfile();
    }

    function checkNotices() {
        if (shell === null || !battery.present) return;
        const discharging = battery.state === "discharging";
        const result = Logic.notices(noticeLatch, battery.level, discharging, shell.settings.lowThreshold, shell.settings.criticalThreshold);
        noticeLatch = result.latch;
        for (const notice of result.notices) sendNotice(notice);
    }

    function sendNotice(notice) {
        const reply = shell.notify.send(Logic.noticePayload(notice));
        if (reply !== "ok") console.warn("power: notify " + reply);
    }

    function observeWake() {
        if (!registered) return;
        const result = Logic.wakeObserved(wakeState, ethernetPresent, wakeOn, wakeWired);
        wakeState = result.state;
        if (result.write) writeWakeOnLan();
    }

    function writeWakeOnLan() {
        if (wakeLister.running || wakeReader.running || wakeWriter.running) {
            wakeStale = true;
            return;
        }
        wakeStale = false;
        wakeTarget = Logic.wakeTarget(wakeOn);
        wakeFailure = "";
        wakeLister.completion = null;
        wakeLister.running = true;
    }

    // A failed step ends that connection's part of the pass; the others
    // still run, and the field shows the first failure until a pass ends
    // with none.
    function wakeFailed(step, code) {
        console.warn("power: wake-on-lan step=" + step + " connection=" + (wakeConnection || "-") + " code=" + code);
        if (wakeFailure === "") wakeFailure = step;
    }

    function readNextConnection() {
        if (wakeQueue.length === 0) {
            wakeConnection = "";
            const text = Logic.wakeProblemText(wakeFailure);
            report("wakeOnLanProblem", text === "" ? null : text);
            if (wakeStale) writeWakeOnLan();
            return;
        }
        wakeConnection = wakeQueue[0];
        wakeQueue = wakeQueue.slice(1);
        wakeReader.completion = null;
        wakeReader.command = ["nmcli", "-g", "802-3-ethernet.wake-on-lan", "connection", "show", wakeConnection];
        wakeReader.running = true;
    }

    // The exit code of a run that ended on its own, -1 for one a signal
    // ended or that never started, which leaves `completion` null.
    function codeOf(completion) {
        return completion === null || completion.status !== 0 ? -1 : completion.code;
    }

    // Each run ends on runningChanged: a command that fails to start emits
    // only that (shell/Core/SystemSteps.qml), so no exit recorded is a
    // failed start, and the pass goes on.
    Process {
        id: wakeLister
        property var completion: null
        command: ["nmcli", "-t", "-f", "UUID,TYPE", "connection", "show"]
        stdout: StdioCollector { id: wakeListerOut; waitForEnd: true }
        onExited: (code, status) => { wakeLister.completion = { code: code, status: status }; }
        onRunningChanged: {
            if (running) return;
            const code = root.codeOf(completion);
            if (code !== 0) root.wakeFailed("list", code);
            root.wakeQueue = code === 0 ? Logic.wiredConnections(wakeListerOut.text) : [];
            root.readNextConnection();
        }
    }

    Process {
        id: wakeReader
        property var completion: null
        stdout: StdioCollector { id: wakeReaderOut; waitForEnd: true }
        onExited: (code, status) => { wakeReader.completion = { code: code, status: status }; }
        onRunningChanged: {
            if (running) return;
            const code = root.codeOf(completion);
            if (code !== 0) {
                root.wakeFailed("read", code);
                root.readNextConnection();
            } else if (wakeReaderOut.text.trim() === root.wakeTarget) {
                root.readNextConnection();
            } else {
                wakeWriter.completion = null;
                wakeWriter.command = ["nmcli", "connection", "modify", root.wakeConnection, "802-3-ethernet.wake-on-lan", root.wakeTarget];
                wakeWriter.running = true;
            }
        }
    }

    Process {
        id: wakeWriter
        property var completion: null
        onExited: (code, status) => { wakeWriter.completion = { code: code, status: status }; }
        onRunningChanged: {
            if (running) return;
            const code = root.codeOf(completion);
            if (code !== 0) root.wakeFailed("write", code);
            root.readNextConnection();
        }
    }

    // The watch ends with the shell: setpriv hands gdbus the parent-death
    // signal. It ends early when gdbus cannot connect to the system bus or
    // that bus closes; neither leaves a daemon to read, so it is not started
    // again.
    Process {
        id: profileWatch
        command: ["setpriv", "--pdeathsig", "TERM", "--", "gdbus", "monitor"].concat(root.profilesBus)
        stdout: SplitParser { onRead: () => root.readProfiles() }
        onExited: code => {
            console.warn("power: profile watch ended exit=" + code);
            root.profile = Logic.profileView("");
        }
    }

    Process {
        id: profileReader
        command: ["gdbus", "call"].concat(root.profilesBus, ["--method", "org.freedesktop.DBus.Properties.GetAll", root.profilesInterface])
        stdout: StdioCollector { id: profileReaderOut; waitForEnd: true }
        onExited: code => {
            root.profile = Logic.profileView(code === 0 ? profileReaderOut.text : "");
            if (root.profileReadStale) root.readProfiles();
        }
    }

    Process {
        id: profileWriter
        onExited: code => {
            if (code !== 0) {
                console.warn("power: profile write exit=" + code);
                root.readProfiles();
            }
            if (root.profileWanted !== "") root.writeProfile(root.profileWanted);
        }
    }
}
