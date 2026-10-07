//@ pragma UseQApplication
// Every QML garbage collection runs to completion in one step. Qt 6.11.2's
// incremental collector can destroy one heap object twice: Chunk::sweep
// keeps the black bitmap as the object bitmap, so a stale reference marked
// during an incremental mark brings a freed slot back and the next sweep
// destroys it again (two shell crashes, symbolized against
// libQt6Qml.so.6.11.2, in JavaScriptFunctionObject::virtualDestroy and
// ErrorObject::virtualDestroy under tryForceGCCompletion; a related fault
// is QTBUG-148459). GCStateMachine reads QV4_GC_TIMELIMIT once, when the
// engine is built, and 0 runs each collection's mark and sweep with no QML
// between them. The Env pragma sets it before the engine exists, over any
// inherited value. Cost, from the nested sandbox's rescan churn (40 rounds,
// qt.qml.gc.allocatorStats, host cachy, 2026-10-06): one whole collection
// p50 4.4 ms, p90 5.3 ms, max 7.0 ms, and no forced completion where an
// inherited 1 ms slice forced 10. Remove it on a Qt release whose
// incremental collector no longer destroys an object twice.
//@ pragma Env QV4_GC_TIMELIMIT = 0
//@ pragma AppId org.vgs.shell
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Core
import qs.Hosts

// The VGS shell root. Draws only when started by the runner that holds the
// instance lock: the runner's child exports its own process id and execs
// qs in the same process, so a second qs started by hand carries a stale
// value and refuses. Everything visible lives in a host, and every host
// draws a plugin. An unguarded
// instance answers read-only calls, so its refusal can be diagnosed, and
// refuses every call that would change state.
ShellRoot {
    id: root

    readonly property bool guarded: Quickshell.env("VGSHELL_RUNNER_PID") === String(Quickshell.processId)
    readonly property string guardRefusal: "refused: guard=unowned pid=" + Quickshell.processId

    // The reply of a state-changing call: `reply()` from the guarded
    // instance, the guard refusal from any other.
    function ifGuarded(reply) {
        return guarded ? reply() : guardRefusal;
    }

    Component.onCompleted: {
        if (!guarded) console.error("shell: refusing to draw; start it with `vgshell run`, VGSHELL_RUNNER_PID=" + JSON.stringify(Quickshell.env("VGSHELL_RUNNER_PID")) + " pid=" + Quickshell.processId);
    }

    Variants {
        model: root.guarded ? Quickshell.screens : []
        BarHost {}
    }

    Loader {
        active: root.guarded
        sourceComponent: ServiceHost {}
    }

    LazyLoader {
        active: root.guarded
        LockHost {}
    }

    Variants {
        model: root.guarded ? Quickshell.screens : []
        BackgroundHost {
            kind: "background"
            namespace: "vgs:background"
            shellLayer: WlrLayer.Background
            keyboardFocus: WlrKeyboardFocus.None
        }
    }

    Variants {
        model: root.guarded ? Quickshell.screens : []
        BackgroundHost {
            kind: "cover"
            namespace: "vgs:cover"
            shellLayer: WlrLayer.Overlay
            keyboardFocus: WlrKeyboardFocus.Exclusive
        }
    }

    LazyLoader {
        active: root.guarded
        Scope {
            SummonHost { kind: "panel" }
            SummonHost { kind: "overlay" }
            SummonHost { kind: "menu" }
            SummonHost { kind: "window" }
            PaneHost {}
        }
    }

    LazyLoader {
        active: root.guarded
        NoticeHost {}
    }

    LazyLoader {
        active: root.guarded
        LayerHost {}
    }

    // Every scan ends with a follow of the applied theme package, which
    // writes the theme and application files: the guarded instance alone
    // asks for it. An unguarded one names no Registry here, so a read-only
    // call is all that starts its scan.
    Connections {
        target: root.guarded ? Registry : null
        function onScanFinished() { Capabilities.themes.follow(); }
    }

    // The Hyprland layer's one writer, in the runner's shell alone.
    LazyLoader {
        id: hyprland
        active: root.guarded
        HyprlandLayer {}
    }

    IpcHandler {
        target: "shell"

        function ping(): string { return "ok"; }
        function guarded(): bool { return root.guarded; }
        function locked(): bool { return Capabilities.sessionLock.lockRequested; }
        // Every plugin row: the reply grows with the plugin set, so it
        // answers through the pager, and `page` hands out its pages.
        function listPlugins(): string { return IpcPages.answer(Registry.listJson()); }
        function page(id: string, index: int): string { return IpcPages.page(id, index); }
        function listShellConfig(): string { return JSON.stringify(Config.effective); }
        function built(): string { return Plugins.builtJson(); }
        function lent(): string { return Capabilities.lentJson(); }
        function reloadConfig(): string { return root.ifGuarded(() => { Config.reload(); return "ok"; }); }
        // `ok scan=<N>` or `busy scan=<N>`: the scan this call asks for has
        // landed once scanRevision reaches N.
        function rescanPlugins(): string { return root.ifGuarded(() => Registry.scanReply(Registry.rescan())); }
        function scanRevision(): int { return Registry.requirementsRevision; }
        // `vgshell plugin add` landed plugin `id`: the same scan, then the
        // requirement notice for it.
        function pluginInstalled(id: string): string { return root.ifGuarded(() => Notices.installed(id)); }
        function setPluginEnabled(id: string, enabled: bool): string { return root.ifGuarded(() => Plugins.setEnabled(id, enabled)); }
        function setPluginPlaced(id: string, placed: bool): string { return root.ifGuarded(() => Plugins.setPlaced(id, placed)); }
        function movePluginWidget(id: string, section: string, index: int): string { return root.ifGuarded(() => Plugins.moveWidget(id, section, index, null)); }
        function summon(kind: string, id: string, payloadJson: string): string { return root.ifGuarded(() => Plugins.route("summon", kind, id, payloadJson, null)); }
        function hide(kind: string, id: string): string { return root.ifGuarded(() => Plugins.route("hide", kind, id, "", null)); }
        function toggle(kind: string, id: string, payloadJson: string): string { return root.ifGuarded(() => Plugins.route("toggle", kind, id, payloadJson, null)); }
        function listTuis(): string { return JSON.stringify(Capabilities.tuis.entries); }
        function openTui(key: string): string { return root.ifGuarded(() => Capabilities.tuis.open(key)); }
        // `vgshell reset` with no terminal and no --yes: the reset question,
        // whose Reset runs `vgshell reset --yes`.
        function askReset(): string { return root.ifGuarded(() => Notices.askReset()); }
        function renderHyprland(): string { return root.ifGuarded(() => hyprland.item === null ? "refused: hyprland=pending" : hyprland.item.render()); }
    }
}
