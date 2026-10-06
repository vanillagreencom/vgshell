import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Commons
import "PowerLogic.js" as Logic

// The Power service is the only reader of Quickshell's UPower and
// PowerProfiles services, the only writer of the power profile, and the
// only sender of low-battery notices. Widgets and panels read the status
// value and ask this service through IPC. Quickshell 0.3.1 documents
// UPower.displayDevice, UPower.onBattery, PowerProfiles.profile and
// PowerProfiles.hasPerformanceProfile. In the source, UPowerService and
// PowerProfileService call tryLaunchService and init when the singleton is
// first created; powerprofiles.cpp exposes no daemon-present property, and
// powerprofiles.hpp makes profile writable.
Item {
    id: root

    property var shell: null
    property bool registered: false
    property var sourceState: ({ ready: false, onBattery: false })
    property var noticeLatch: Logic.latchInitial()

    property bool profileAvailable: false
    readonly property bool upowerReady: UPower.displayDevice !== null && UPower.displayDevice.ready === true
    readonly property var battery: Logic.batteryView(UPower.displayDevice, UPower.onBattery)
    readonly property var profile: Logic.profileView(profileAvailable, PowerProfiles.profile, PowerProfiles.hasPerformanceProfile)
    readonly property var view: ({ battery: battery, profile: profile })
    readonly property string viewKey: JSON.stringify(view)
    readonly property string noticeKey: JSON.stringify({
        battery: battery,
        onBattery: UPower.onBattery,
        low: shell === null ? 20 : shell.settings.lowThreshold,
        critical: shell === null ? 10 : shell.settings.criticalThreshold
    })
    readonly property string sourceKey: JSON.stringify({ ready: upowerReady, onBattery: UPower.onBattery })
    readonly property var profileProbeCommand: Quickshell.env("DBUS_SYSTEM_BUS_ADDRESS") === "" ? [
        "gdbus", "call", "--system", "--dest", "org.freedesktop.UPower.PowerProfiles", "--object-path", "/org/freedesktop/UPower/PowerProfiles", "--method", "org.freedesktop.DBus.Properties.Get", "org.freedesktop.UPower.PowerProfiles", "ActiveProfile"
    ] : [
        "gdbus", "call", "--address", Quickshell.env("DBUS_SYSTEM_BUS_ADDRESS"), "--dest", "org.freedesktop.UPower.PowerProfiles", "--object-path", "/org/freedesktop/UPower/PowerProfiles", "--method", "org.freedesktop.DBus.Properties.Get", "org.freedesktop.UPower.PowerProfiles", "ActiveProfile"
    ]

    onShellChanged: {
        if (shell === null || registered) return;
        registered = true;
        shell.ipc.handle("profile", arg => root.profileRequest(arg));
        shell.shortcut.register("power-saver", "Use the power saver profile", () => root.setProfile("power-saver", true));
        shell.shortcut.register("balanced", "Use the balanced profile", () => root.setProfile("balanced", true));
        shell.shortcut.register("performance", "Use the performance profile", () => root.setProfile("performance", true));
        profileProbe.running = true;
        publish();
        checkNotices();
    }
    onViewKeyChanged: publish()
    onNoticeKeyChanged: checkNotices()
    onSourceKeyChanged: observeSource()
    Component.onCompleted: observeSource()

    Connections {
        target: UPower
        function onOnBatteryChanged() {
            root.observeSource();
        }
    }

    function publish() {
        if (shell === null) return;
        const reply = shell.status.set("power", root.view);
        if (reply !== "ok") console.error("power: status power " + reply);
    }

    function profileRequest(arg) {
        const profile = String(arg || "");
        if (!Logic.validProfile(profile)) return "refused: profile=" + profile + " want=power-saver|balanced|performance";
        return setProfile(profile, true);
    }

    function setProfile(name, remember) {
        if (!profileAvailable) return "refused: profile=unavailable";
        if (!Logic.validProfile(name)) return "refused: profile=" + name + " want=power-saver|balanced|performance";
        if (name === "performance" && !PowerProfiles.hasPerformanceProfile) return "refused: profile=performance reason=unavailable";
        PowerProfiles.profile = Logic.profileEnum(name);
        if (Logic.profileName(PowerProfiles.profile) !== name) return "refused: profile=" + name + " reason=not-applied";
        if (remember === true && shell !== null) {
            const key = UPower.onBattery ? "batteryProfile" : "chargerProfile";
            const saved = shell.configure.set(key, name);
            if (saved !== "ok") console.warn("power: configure " + saved);
        }
        publish();
        return name;
    }

    function applySourceProfile() {
        if (shell === null || !profileAvailable) return;
        setProfile(Logic.profileForSource(UPower.onBattery, shell.settings, PowerProfiles.hasPerformanceProfile), false);
    }

    function observeSource() {
        const result = Logic.sourceObserved(sourceState, upowerReady, UPower.onBattery);
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
        const argv = [
            "notify-send",
            "--urgency=" + notice.urgency,
            "--expire-time=30000",
            "--icon=battery-caution",
            "--",
            "Time to recharge!",
            "Battery is down to " + notice.level + "%"
        ];
        const reply = shell.run.detached(argv);
        if (reply !== "ok") console.warn("power: notify " + reply);
    }

    Process {
        id: profileProbe
        command: root.profileProbeCommand
        stdout: StdioCollector { id: profileProbeOut; waitForEnd: true }
        onExited: code => {
            root.profileAvailable = code === 0 && profileProbeOut.text.trim() !== "";
            root.publish();
        }
    }
}
