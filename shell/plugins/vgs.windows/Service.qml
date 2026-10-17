import QtQuick

// The Windows service: the shortcut `group-lock` (SUPER+CTRL+G in the
// manifest) locks or unlocks the focused window's group and says which in
// one notification.
//
// Hyprland 0.56.2 reports no change of a group's lock, so the service
// learns the lock only by reading it, through the core's group lock read,
// around its own toggle. It listens to no group event and polls nothing:
// a lock made by another key, and a group made, joined, left or focused,
// sends nothing.
//
// A press reads the lock first and toggles only a window in a group, so a
// window in no group or no focused window sends Hyprland nothing. A read
// after the toggle, queued behind it, gives the state the notification
// names; a read that shows no change, or that failed, sends nothing. A
// classic (non-Lua) session has no group lock read, which the core
// refuses and logs, so there the key toggles nothing and sends nothing.
//
// Presses run one at a time: a press during another waits for it, so each
// press reads its own state before and after its own toggle, and two
// quick presses lock and then unlock rather than both reading the first
// press's state.
Item {
    id: root

    // The core assigns the plugin's scoped shell object after creation.
    property var shell: null
    // The shell this service registered with, so a settings change that
    // hands over a new object registers nothing twice.
    property var registeredWith: null
    // Presses not yet started, and whether one is between its first read
    // and its last answer.
    property int presses: 0
    property bool pressing: false
    // Presses finished, whatever each did; the windows-group-lock smoke row
    // waits on it before it changes a group itself.
    property int finished: 0

    readonly property var notices: ({
        locked: { title: "Group locked", message: "No window can join or leave this group.", icon: "lock", transient: true },
        unlocked: { title: "Group unlocked", message: "Windows can join and leave this group again.", icon: "lock-open", transient: true }
    })

    onShellChanged: {
        if (shell === null || registeredWith !== null) return;
        registeredWith = shell;
        shell.shortcut.register("group-lock", "Lock or unlock group", () => root.press());
    }

    function press() {
        presses += 1;
        next();
    }

    function next() {
        if (pressing || presses === 0) return;
        presses -= 1;
        const reply = shell.compositor.readGroupLock(before => root.toggle(before));
        if (reply === "ok") {
            pressing = true;
            return;
        }
        // The core logged its refusal, a classic session's among them; the
        // presses waiting would meet the same refusal.
        finished += 1 + presses;
        presses = 0;
    }

    // BEFORE is the lock this press found.
    function toggle(before) {
        if (!before.ok) console.warn("windows: group-lock before " + before.error);
        if (!before.ok || notices[before.state] === undefined) {
            finish();
            return;
        }
        const toggled = shell.compositor.lockActiveGroup("toggle");
        const read = toggled === "ok" ? shell.compositor.readGroupLock(after => root.toggled(before.state, after)) : toggled;
        if (read !== "ok") finish();
    }

    // WAS is the state before the toggle, AFTER the read behind it.
    function toggled(was, after) {
        if (!after.ok) {
            console.warn("windows: group-lock after " + after.error);
        } else if (after.state !== was && notices[after.state] !== undefined) {
            const reply = shell.notify.send(notices[after.state]);
            if (reply !== "ok") console.warn("windows: group-lock notify " + reply);
        }
        finish();
    }

    function finish() {
        finished += 1;
        pressing = false;
        next();
    }
}
