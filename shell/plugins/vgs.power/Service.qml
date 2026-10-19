import QtQuick
import Quickshell.Io
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

    onShellChanged: {
        if (shell === null || registered) return;
        registered = true;
        shell.ipc.handle("profile", arg => root.profileRequest(arg));
        shell.shortcut.register("power-saver", "Use the power saver profile", () => root.setProfile("power-saver", true));
        shell.shortcut.register("balanced", "Use the balanced profile", () => root.setProfile("balanced", true));
        shell.shortcut.register("performance", "Use the performance profile", () => root.setProfile("performance", true));
        profileWatch.running = true;
        publish();
        checkNotices();
    }
    onViewKeyChanged: publish()
    onDiskSleepStepChanged: publish()
    onNoticeKeyChanged: checkNotices()
    onSourceKeyChanged: observeSource()
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
        if (diskSleepStep !== undefined) report("diskSleep", diskSleepValue());
    }

    // The core probes the step once for all holders. Publish nothing until
    // that reading arrives, so Details keeps its standard Checking state.
    function diskSleepValue() {
        switch (diskSleepStep.state) {
        case "absent": return { hidden: true };
        case "ready": return { tone: "ok", text: "Allowed", action: false };
        case "needed": return { tone: "warning", text: "Not allowed", action: true };
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
