import QtQuick
Item {
    id: root
    property var shell: null
    readonly property string label: shell === null ? "" : String(shell.settings.label)
    readonly property string shellKeys: shell === null ? "" : Object.keys(shell).sort().join(",")
    readonly property string shortcutKeys: shell === null ? "" : JSON.stringify(shell.shortcut.keys)
    property bool registered: false
    // The file turnedOff() makes, "" for none.
    property string offMark: ""
    function turnedOff() { if (offMark !== "") shell.run.detached(["touch", offMark]); }
    property int presses: 0
    property string duplicateShortcut: ""
    property string duplicateIpc: ""
    property int notified: 0
    property string lastSummary: ""
    // What the theme capability's callbacks last received, as JSON, and
    // how many times each ran.
    property string themeListed: ""
    property int themeLists: 0
    property string themeApplied: ""
    property int themeApplies: 0
    property string themeStepped: ""
    property int themeSteps: 0
    // What the compositor's group lock read last handed its callback, and
    // how many times the callback ran.
    property var groupLock: null
    property int groupLockReads: 0
    function keepGroupLock(answer) { groupLock = answer; groupLockReads += 1; }
    readonly property bool lockSecure: shell !== null && shell.lock.secure
    // The core's idle stage record as JSON, bound, and whether every entry
    // of it is frozen.
    readonly property string idleStages: shell === null ? "" : JSON.stringify(shell.idle.stages)
    readonly property bool idleStagesFrozen: shell !== null && Object.isFrozen(shell.idle.stages) && shell.idle.stages.every(Object.isFrozen)
    readonly property bool hasAgent: shell !== null && shell.polkit.agent !== null
    readonly property bool agentRegistered: shell !== null && shell.polkit.registered
    readonly property int screenCount: shell === null ? -1 : shell.screens.all.length
    readonly property bool noCurrentScreen: shell !== null && shell.screens.current === null

    Component { id: lockContent; Item { property var screen: null } }

    onShellChanged: {
        if (shell === null || registered) return;
        registered = true;
        shell.shortcut.register("ping", "smoke probe", () => root.presses += 1);
        try { shell.shortcut.register("ping", "again", () => {}); } catch (e) { root.duplicateShortcut = e.message; }
        shell.ipc.handle("echo", arg => arg);
        shell.ipc.handle("mutate-keys", () => {
            const keys = root.shell.shortcut.keys;
            keys.ping = "planted";
            keys.inbox = "planted";
            return JSON.stringify(root.shell.shortcut.keys);
        });
        try { shell.ipc.handle("echo", arg => arg); } catch (e) { root.duplicateIpc = e.message; }
        // `call NAME [ARG]` reaches this plugin's own handler NAME through
        // shell.ipc.call.
        shell.ipc.handle("call", arg => { const at = arg.indexOf(" "); return at < 0 ? root.shell.ipc.call(arg, "") : root.shell.ipc.call(arg.slice(0, at), arg.slice(at + 1)); });
        shell.ipc.handle("off-mark", path => { root.offMark = path; return "ok"; });
        shell.ipc.handle("dispatch", arg => { const a = arg.split(" "); return root.shell.compositor[a[0]].apply(null, a.slice(1)); });
        // reveal <address>[,<address>...] [sender]: the compositor's reveal
        // of those windows, awaiting the sender with the word `sender`.
        shell.ipc.handle("reveal", arg => { const a = arg.split(" "); return root.shell.compositor.reveal(a[0].split(","), a[1] === "sender"); });
        // Several dispatches in one call, separated by ";", so they reach
        // the queue back to back; answers every reply joined by ",".
        shell.ipc.handle("batch", arg => arg.split(";").map(one => { const a = one.split(" "); return root.shell.compositor[a[0]].apply(null, a.slice(1)); }).join(","));
        // group-lock-read answers what the compositor's group lock read
        // returned, and its callback keeps the answer in groupLock;
        // group-lock-state answers { reads, answer } as JSON.
        // group-lock-after <action> locks and then reads in one turn, as a
        // plugin acting on its own lock does; group-lock-throws <action>
        // queues a read whose callback throws and then the lock; both
        // answer the two returns joined by ",". group-lock-no-callback
        // answers the refusal a read without a callback throws.
        shell.ipc.handle("group-lock-read", () => root.shell.compositor.readGroupLock(root.keepGroupLock));
        shell.ipc.handle("group-lock-after", action => [root.shell.compositor.lockActiveGroup(action), root.shell.compositor.readGroupLock(root.keepGroupLock)].join(","));
        shell.ipc.handle("group-lock-throws", action => [root.shell.compositor.readGroupLock(() => { throw new Error("planted"); }), root.shell.compositor.lockActiveGroup(action)].join(","));
        shell.ipc.handle("group-lock-no-callback", () => { try { return root.shell.compositor.readGroupLock(); } catch (e) { return e.message; } });
        shell.ipc.handle("group-lock-state", () => JSON.stringify({ reads: root.groupLockReads, answer: root.groupLock }));
        // N dispatches of one request in one call; answers the last reply.
        shell.ipc.handle("flood", arg => { const a = arg.split(" "); let last = ""; for (let i = 0; i < Number(a[0]); i++) last = root.shell.compositor[a[1]].apply(null, a.slice(2)); return last; });
        shell.notifications.subscribe(n => { root.notified += 1; root.lastSummary = n.summary; });
        // theme-list, theme-apply <name> and theme-background <step> keep
        // what their callbacks received; theme <member> answers one member
        // as JSON, and theme swatch=<name> one package's swatch.
        shell.ipc.handle("theme-list", () => { root.shell.theme.list(result => { root.themeListed = JSON.stringify(result); root.themeLists += 1; }); return "ok"; });
        shell.ipc.handle("theme-apply", name => root.shell.theme.apply(name, result => { root.themeApplied = JSON.stringify(result); root.themeApplies += 1; }));
        shell.ipc.handle("theme-background", step => root.shell.theme.background(step, result => { root.themeStepped = JSON.stringify(result); root.themeSteps += 1; }));
        shell.ipc.handle("theme", member => JSON.stringify(member.startsWith("swatch=") ? root.shell.theme.swatch(member.slice(7)) : root.shell.theme[member]));
        // A lock holder rebuilt into a locked session hands its screen over again.
        if (shell.lock.locked) shell.lock.lock(lockContent, { cause: "restore" });
    }
}
