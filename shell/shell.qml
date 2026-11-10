//@ pragma UseQApplication
// Avoid incremental mark/sweep interleaving while the suspected collector
// double-destruction remains unresolved; that cause is not reproduced.
// GCStateMachine reads QV4_GC_TIMELIMIT when the engine is built, and 0
// completes collection in one step (Qt GCStateMachine::transition):
// https://github.com/qt/qtdeclarative/blob/6.12/src/qml/memory/qv4mm.cpp
// The Env pragma sets it before engine creation, over any inherited value.
// Remove it only on a Qt verified to fix the collector fault; the candidate
// upstream fixes are QTBUG-149512 and QTBUG-151273 (fix version 6.12.1).
//@ pragma Env QV4_GC_TIMELIMIT = 0
//@ pragma AppId org.vgs.shell
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Core
import qs.Hosts

// The runner's child exports its own pid and execs qs in the same process.
// Comparing that pid rejects another process with an inherited value.
// An unguarded instance keeps read-only IPC available for diagnosis.
ShellRoot {
    id: root

    readonly property bool guarded: Quickshell.env("VGSHELL_RUNNER_PID") === String(Quickshell.processId)
    readonly property string guardRefusal: "refused: guard=unowned pid=" + Quickshell.processId
    // env() reads a string or null (Quickshell 0.3.1 reference:
    // https://quickshell.org/docs/v0.3.1/types/Quickshell/Quickshell/#env).
    // The runner reads its tree once per child; IPC keeps that start reading.
    readonly property string startedVersion: guarded ? (Quickshell.env("VGSHELL_VERSION") || "") : ""

    function ifGuarded(reply) {
        return guarded ? reply() : guardRefusal;
    }

    Component.onCompleted: {
        console.info("shell: version=" + (startedVersion || "unavailable"));
        // Recover an outstanding temporary lock release before any window.
        if (guarded) Capabilities.sessionLock.recoverRelease();
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
            // On demand, not exclusive: Hyprland 0.56.2 sends every pointer
            // event to an exclusive layer (InputManager mouseMoveUnified),
            // so the other screens' covers would never see the pointer.
            keyboardFocus: WlrKeyboardFocus.OnDemand
        }
    }

    // The stage owner's cover must survive moving into the session lock.
    Variants {
        model: root.guarded ? Quickshell.screens : []
        CoverHost {}
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

    LazyLoader {
        active: root.guarded
        FreezeHost {}
    }

    // Every scan ends with a follow of the applied theme package, which
    // writes the theme and application files: the guarded instance alone
    // asks for it. An unguarded one names no Registry here, so a read-only
    // call is all that starts its scan.
    Connections {
        target: root.guarded ? Registry : null
        function onScanFinished() { Capabilities.themes.follow(); }
    }

    // Theme targets include the terminal font, so its changes need a follow.
    readonly property string terminalFont: Theme.appearanceState.values.terminalFont || ""
    onTerminalFontChanged: if (root.guarded) Capabilities.themes.follow()

    // The Hyprland layer's one writer, in the runner's shell alone.
    LazyLoader {
        id: hyprland
        active: root.guarded
        HyprlandLayer {}
    }

    // Typed IPC arguments are required by Quickshell 0.3.1 IpcHandler:
    // https://quickshell.org/docs/v0.3.1/types/Quickshell.Io/IpcHandler/.
    IpcHandler {
        target: "config"
        function packageReviewRead(): string {
            if (!Config.ready || (Config.userState !== "loaded" && Config.userState !== "absent")) return "refused: package-review=user-config-unavailable";
            return JSON.stringify({ version: 1, text: Config.userText, settings: Config.effective.packages === undefined ? {} : (Config.effective.packages.review || {}) });
        }
        function packageReviewWrite(request: string): string { return Config.packageReviewWrite(request); }
    }

    IpcHandler {
        target: "shell"

        function ping(): string { return "ok"; }
        function version(): string { return root.startedVersion || "refused: version=unavailable"; }
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
        function pluginInstalled(id: string): string { return root.ifGuarded(() => Notices.installed(id)); }
        function themeCompleted(verb: string, resultJson: string): string { return root.ifGuarded(() => Capabilities.themes.completed(verb, resultJson)); }
        function setPluginEnabled(id: string, enabled: bool): string { return root.ifGuarded(() => Plugins.setEnabled(id, enabled)); }
        function setPluginPlaced(id: string, placed: bool): string { return root.ifGuarded(() => Plugins.setPlaced(id, placed)); }
        function movePluginWidget(id: string, section: string, index: int): string { return root.ifGuarded(() => Plugins.moveWidget(id, section, index, null)); }
        function summon(kind: string, id: string, payloadJson: string): string { return root.ifGuarded(() => Plugins.route("summon", kind, id, payloadJson, null)); }
        function hide(kind: string, id: string): string { return root.ifGuarded(() => Plugins.route("hide", kind, id, "", null)); }
        function toggle(kind: string, id: string, payloadJson: string): string { return root.ifGuarded(() => Plugins.route("toggle", kind, id, payloadJson, null)); }
        function listTuis(): string { return JSON.stringify(Capabilities.tuis.entries); }
        function openTui(key: string): string { return root.ifGuarded(() => Capabilities.tuis.open(key)); }
        function askReset(): string { return root.ifGuarded(() => Notices.askReset()); }
        function renderHyprland(): string { return root.ifGuarded(() => hyprland.item === null ? "refused: hyprland=pending" : hyprland.item.render()); }
    }
}
