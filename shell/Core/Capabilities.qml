pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Polkit
import "PluginLogic.js" as Logic
import "Dispatch.js" as Dispatch

// Maps declared capabilities to per-instance providers and accounts for
// their holds. Resource owners implement registration and teardown.
Singleton {
    id: root

    // Capability name -> { plugin id -> number of live instances holding
    // it }, replaced whole on every change so bindings re-evaluate once.
    property var held: ({})

    ShortcutRegistry { id: shortcuts; bindsSource: hyprlandState }
    IdleRegistry { id: idleWatches }
    IpcRegistry { id: commands }
    NotificationHub { id: notifications; active: root.notificationsHeld }
    SessionLock { id: sessionLock }
    ThemeRunner { id: themes }
    TuiRunner { id: tuis }
    SecretWriter { id: secrets }
    SystemSteps { id: systemSteps; active: root.systemHeld }
    SudoGrant { id: sudoGrant; active: root.sudoHeld; runner: tuis }
    HyprlandState {
        id: hyprlandState
        active: root.holderIds("hyprland").length > 0 || shortcuts.keyCapture.wantsBinds
    }
    BluetoothAgent { id: bluetoothAgent }
    MonitorState {
        id: monitorState
        active: root.holderIds("monitors").length > 0
    }
    readonly property alias sessionLock: sessionLock
    readonly property alias themes: themes
    readonly property alias tuis: tuis
    readonly property alias hyprland: hyprlandState
    readonly property alias monitors: monitorState
    readonly property alias keyCapture: shortcuts.keyCapture

    readonly property bool notificationsHeld: holderIds("notifications").length > 0
    // `<plugin id>:<name>` -> the description each registered shortcut
    // carries, for the plugin manager's Keys rows.
    readonly property var shortcutDescriptions: {
        const out = {};
        for (const key of Object.keys(shortcuts.shortcuts)) out[key] = shortcuts.shortcuts[key].description;
        return out;
    }
    readonly property bool polkitHeld: holderIds("polkit").length > 0
    readonly property bool systemHeld: holderIds("system").length > 0
    readonly property bool sudoHeld: holderIds("sudo").length > 0
    property int polkitFlows: 0

    function holderIds(name) {
        return Logic.hasOwn(held, name) ? Object.keys(held[name]).sort() : [];
    }

    // { capability -> plugin id } for every exclusive capability held.
    function exclusiveHolders() {
        const out = {};
        for (const name of Logic.EXCLUSIVE_CAPABILITIES) {
            const ids = holderIds(name);
            if (ids.length > 0) out[name] = ids[0];
        }
        return out;
    }

    function acquire(name, id) {
        const next = Logic.clone(held);
        if (!Logic.hasOwn(next, name)) next[name] = {};
        next[name][id] = (next[name][id] || 0) + 1;
        held = next;
    }

    function release(name, id) {
        if (!Logic.hasOwn(held, name) || !Logic.hasOwn(held[name], id))
            throw new Error("capabilities: release of " + name + " by " + id + " which holds none");
        const next = Logic.clone(held);
        next[name][id] -= 1;
        if (next[name][id] === 0) delete next[name][id];
        if (Object.keys(next[name]).length === 0) delete next[name];
        held = next;
    }

    // The providers for one instance: one per capability its manifest
    // names. `ctx` is { id, manifest, kind, hostKey, screen, locator,
    // onDispose(fn), active }, `active` reading the instance's lifetime,
    // `locator` being a bar widget's { section, nth }; every
    // hold and registration is released through ctx.onDispose.
    function providersFor(ctx) {
        const out = {};
        for (const name of ctx.manifest.capabilities) {
            if (!Logic.hasOwn(factories, name))
                throw new Error("capabilities: " + name + " is in PluginLogic.CAPABILITIES but has no provider");
            acquire(name, ctx.id);
            ctx.onDispose(() => root.release(name, ctx.id));
            out[name] = factories[name](ctx);
        }
        return out;
    }

    // Registration names a plugin chooses: lower case, digits and dashes.
    function checkName(kind, name) {
        if (typeof name !== "string" || !Logic.NAME_PATTERN.test(name))
            throw new Error("refused: " + kind + "=" + JSON.stringify(name) + " malformed");
    }

    readonly property var factories: ({
        compositor: ctx => {
            const out = {};
            for (const name of Dispatch.PLUGIN_DISPATCHERS)
                out[name] = (...args) => Compositor.send(name, args);
            out.reveal = (addresses, awaitSender) => Compositor.reveal(addresses, awaitSender);
            out.padWorkspace = name => Dispatch.padWorkspace(name);
            out.onScreen = (window, monitors) => Dispatch.onScreen(window, monitors);
            out.togglePad = (name, screen, done) => Compositor.togglePad(name, screen, typeof done !== "function" ? null : answer => { if (ctx.active) done(answer); });
            out.observeInput = (point, done) => {
                if (!ctx.active) return;
                Compositor.observeInput(point, value => { if (ctx.active) done(value); });
            };
            out.readWindows = done => {
                if (ctx.active) Compositor.readWindows(state => { if (ctx.active) done(state); });
            };
            return out;
        },
        configure: ctx => ({
            set: (key, value) => {
                const targets = Logic.configureTargets(Config.effective, ctx.manifest, ctx.kind);
                return Plugins.writeSetting(ctx.id, key, value, targets, ctx.locator);
            },
            unset: key => Plugins.clearSetting(ctx.id, key, Logic.configureTargets(Config.effective, ctx.manifest, ctx.kind), ctx.locator)
        }),
        idle: idleWatches.provider,
        ipc: commands.provider,
        lock: sessionLock.provider,
        session: sessionLock.sessionProvider,
        notifications: notifications.provider,
        polkit: ctx => ({
            get agent() { return polkitLoader.item; },
            get registered() { return polkitLoader.item !== null && polkitLoader.item.isRegistered; },
            register: () => root.polkitRegister()
        }),
        run: ctx => ({
            detached: argv => root.runDetached(argv)
        }),
        screens: ctx => ({
            get all() { return Quickshell.screens; },
            current: ctx.screen
        }),
        shortcut: shortcuts.provider,
        manager: ctx => ({
            get plugins() { return Registry.managerRows; },
            setEnabled: (id, enabled) => typeof enabled === "boolean" ? Plugins.setEnabled(id, enabled) : "refused: enabled=" + JSON.stringify(enabled) + " want=boolean",
            setPlaced: (id, placed) => typeof placed === "boolean" ? Plugins.setPlaced(id, placed) : "refused: placed=" + JSON.stringify(placed) + " want=boolean",
            moveWidget: (id, section, index) => typeof section !== "string" ? "refused: section=" + JSON.stringify(section) + " want=string" : typeof index === "number" && Number.isInteger(index) && index >= 0 ? Plugins.moveWidget(id, section, index, null) : "refused: index=" + JSON.stringify(index) + " want=integer>=0",
            setSetting: (id, key, value) => Plugins.setSetting(id, key, value),
            setKey: (id, shortcut, key) => Plugins.setKey(id, shortcut, key),
            update: id => root.managerTui("update", id),
            remove: id => root.managerTui("remove", id),
            installRequirements: id => Notices.requested(id),
            add: () => root.managerCoreTui("plugin-add", []),
            reset: () => Notices.askReset(),
            rescan: () => Registry.rescan().answer,
            act: (id, key) => root.managerAct(id, key),
            refreshChoices: (id, key) => PluginStatus.refresh(id, key),
            open: id => root.managerOpen(id),
            openPane: id => root.managerOpenPane(id),
            openTui: (id, name) => root.managerOpenTui(id, name),
            storeSecret: (id, key, account, secret, done) => root.managerSecret(ctx, "store", id, key, account, secret, done),
            clearSecret: (id, key, account, done) => root.managerSecret(ctx, "clear", id, key, account, null, done)
        }),
        panes: ctx => root.panesProvider(ctx),
        builtins: ctx => ({
            register: (name, item) => Plugins.recordBuiltin(ctx, name, item),
            add: (family, x) => Plugins.addBuiltin(ctx, family, x)
        }),
        surfaces: ctx => ({
            summon: (kind, payloadJson, anchor) => root.surfaceRoute(ctx, "summon", kind, payloadJson, anchor),
            hide: kind => root.surfaceRoute(ctx, "hide", kind, "", null),
            toggle: (kind, payloadJson, anchor) => root.surfaceRoute(ctx, "toggle", kind, payloadJson, anchor)
        }),
        // The sender's name on the notification is the plugin's manifest
        // name, read at each send.
        notify: ctx => ({
            send: options => Notifier.send(ctx, Registry.manifests[ctx.id].name, options, notifications)
        }),
        layers: ctx => ({
            show: component => Layers.show(ctx, component)
        }),
        // `act` runs the calling plugin's own status action, judged and run
        // as the manager's act is for that plugin; a key of another plugin
        // is one this manifest does not declare. `rows` lends the plugin's
        // own Status rows as the Settings page draws them, so its surfaces
        // take each entry's tone and offered action from the one owner.
        // `handleRefresh` registers what the plugin runs when Settings opens
        // the select one of its `choices` entries feeds.
        status: ctx => ({
            set: (key, value) => PluginStatus.set(ctx, key, value),
            handleRefresh: (key, handler) => PluginStatus.handleRefresh(ctx, key, handler),
            act: key => root.managerAct(ctx.id, key),
            get rows() { return Logic.statusRows(Registry.manifests[ctx.id], PluginStatus.valuesOf(ctx.id), Notices.missingOf(ctx.id)); },
            get values() { return PluginStatus.valuesOf(ctx.id); },
            get revision() { return PluginStatus.revisionOf(ctx.id); }
        }),
        theme: themes.provider,
        tui: tuis.provider,
        system: systemSteps.provider,
        sudo: sudoGrant.provider,
        bluetoothAgent: bluetoothAgent.provider,
        secrets: secrets.provider,
        hyprland: hyprlandState.provider,
        monitors: monitorState.provider,
        // `missing`: the plugin's own requirement commands the last scan did
        // not find, in declaration order, a copy per read; bindable.
        requirements: ctx => ({
            offer: commands => Notices.offer(ctx, commands),
            get missing() { return Notices.missingOf(ctx.id).slice(); },
            get revision() { return Registry.requirementsRevision; }
        }),
        doctor: ctx => ({
            offer: (owner, commands) => Notices.chosen(owner, commands),
            get missing() { return Registry.enabledOwnerMissing(); }
        })
    })


    function panesProvider(ctx) {
        let disposer = null;
        ctx.onDispose(() => {
            if (disposer !== null) {
                disposer();
                disposer = null;
            }
        });
        return {
            get list() { return Registry.paneRows; },
            mount: (id, container, payloadJson) => {
                const result = Plugins.mountPane(ctx, id, container, payloadJson || "");
                if (typeof result === "function") disposer = result;
                return result;
            },
            setPlaced: (id, placed) => {
                if (typeof placed !== "boolean") return "refused: placed=" + JSON.stringify(placed) + " want=boolean";
                if (!Registry.paneRows.some(row => row.id === id)) return "unknown: " + id;
                return Plugins.setPlaced(id, placed);
            }
        };
    }

    function panePayload(id, payloadJson) {
        let payload = {};
        if (payloadJson !== undefined && payloadJson !== null && payloadJson !== "") {
            if (typeof payloadJson === "string") {
                try {
                    payload = JSON.parse(payloadJson);
                } catch (e) {
                    return { ok: false, answer: "refused: pane-payload=json" };
                }
            } else if (typeof payloadJson === "object") {
                payload = payloadJson;
            } else {
                return { ok: false, answer: "refused: pane-payload=object" };
            }
        }
        if (payload === null || Array.isArray(payload) || typeof payload !== "object")
            return { ok: false, answer: "refused: pane-payload=object" };
        const out = {};
        for (const key of Object.keys(payload)) out[key] = payload[key];
        out.pane = id;
        return { ok: true, payloadJson: JSON.stringify(out) };
    }

    function panesHolderId() {
        return Registry.panesHolderId();
    }

    function surfaceRoute(ctx, verb, kind, payloadJson, anchor) {
        if (kind !== "pane")
            return Plugins.route(verb, kind, ctx.id, payloadJson || "", root.origin(ctx, anchor));
        return root.paneRoute(ctx.id, verb, payloadJson, root.origin(ctx, anchor));
    }

    // VERB on plugin ID's own page in the enabled panes holder, the one
    // route of the own-pane summon and of the manager's openPane.
    function paneRoute(id, verb, payloadJson, origin) {
        if (Registry.manifests[id].kinds.indexOf("pane") === -1)
            return "refused: kind=pane id=" + id;
        const holder = root.panesHolderId();
        if (holder === "") return "refused: panes=no-holder";
        if (verb === "hide") return Plugins.currentPaneId() === id ? Plugins.route("hide", "window", holder, "", null) : "ok";
        if (verb === "toggle" && Plugins.currentPaneId() === id) return Plugins.route("hide", "window", holder, "", null);
        const payload = panePayload(id, payloadJson);
        if (!payload.ok) return payload.answer;
        return Plugins.route("summon", "window", holder, payload.payloadJson, origin);
    }

    // Every `manager` TUI member opens a core TUI in a floating terminal,
    // so a question such as update's diff review stays a question (D007).
    // A focused live window is the same shown answer as a started launch.
    function managerTui(action, id) {
        const source = typeof id === "string" && Registry.has(id) ? Registry.sourceOf(Registry.manifests[id]) : null;
        const request = Logic.managerTui(action, id, source);
        return request.ok ? root.managerCoreTui(request.name, request.args) : request.answer;
    }

    // What the manager's steps judge plugin ID by: { manifest, enabled,
    // values }, its judged manifest or null for an id no plugin has, whether
    // it is enabled and the status values it published.
    function managerSubject(id) {
        const known = typeof id === "string" && Registry.has(id);
        return { manifest: known ? Registry.manifests[id] : null, enabled: known && Registry.isEnabled(id), values: known ? PluginStatus.valuesOf(id) : {} };
    }

    // The manager's act on plugin ID's status entry KEY (D061), as
    // PluginLogic.statusActionRequest decides from its published values.
    function managerAct(id, key) {
        const subject = managerSubject(id);
        const request = Logic.statusActionRequest(subject.manifest, id, subject.enabled, subject.values, key);
        return request.ok ? root.managerStep(id, request) : request.answer;
    }

    // The manager's open of plugin ID's window or panel, as
    // PluginLogic.openRequest decides.
    function managerOpen(id) {
        const subject = managerSubject(id);
        const request = Logic.openRequest(subject.manifest, id);
        return request.ok ? root.managerStep(id, request) : request.answer;
    }

    // The manager's open of plugin ID's page in the panes holder, as the
    // plugin's own summon of kind `pane` opens it, for an enabled plugin.
    function managerOpenPane(id) {
        const refusal = typeof id === "string" ? Registry.enableRefusal(id) : "unknown: " + id;
        return refusal === "" ? root.managerStep(id, { kind: "pane" }) : refusal;
    }

    // The manager's open of plugin ID's listed TUI NAME, a setup screen its
    // Settings page offers as a button, as PluginLogic.listedTuiRequest
    // decides.
    function managerOpenTui(id, name) {
        const subject = managerSubject(id);
        const request = Logic.listedTuiRequest(subject.manifest, id, name);
        return request.ok ? root.managerStep(id, request) : request.answer;
    }

    // Runs REQUEST, one a manager judge accepted for plugin ID: the
    // plugin's own declared TUI through TuiRunner.runFor, its own
    // requirement commands through the requirement notice after a scan, its
    // own system step in the core TUI `core/system`, after whose end the
    // steps are probed again (D081), or its summonable surface. Every step
    // of the manager's that opens a plugin's TUI or surface goes through
    // here.
    function managerStep(id, request) {
        switch (request.kind) {
        case "tui": return tuis.runFor(id, request.name);
        case "install": return Notices.chosen(id, request.commands);
        case "system": return root.managerCoreTui("system", request.args, () => systemSteps.probe());
        case "summon": return Plugins.route("summon", request.surface, id, "{}", null);
        case "pane": return root.paneRoute(id, "summon", "{}", null);
        }
        throw new Error("manager: step kind " + JSON.stringify(request.kind) + " is not one of tui, install, system, summon, pane");
    }

    // The manager's store or clear (VERB) of plugin ID's ACCOUNT, listed in
    // its status entry KEY (D061), through the one SecretWriter, as
    // PluginLogic.secretRequest decides; `done` belongs to CTX, the asking
    // instance. SECRET never enters a log line or an answer.
    function managerSecret(ctx, verb, id, key, account, secret, done) {
        if (done !== undefined && typeof done !== "function")
            throw new Error("refused: secret done=not-a-function");
        const subject = managerSubject(id);
        const request = Logic.secretRequest(subject.manifest, id, subject.enabled, subject.values, key, account, verb, secret);
        if (!request.ok) return request.answer;
        return secrets.write(ctx, id, account, verb, request, done);
    }

    // Opens the core TUI `core/<name>` for the manager and returns the
    // shared shown answer from PluginLogic.tuiShownAnswer; `done`, when
    // given, receives the run's end as TuiRunner.openCore hands it.
    function managerCoreTui(name, args, done) {
        const key = "core/" + name;
        return Logic.tuiShownAnswer(key, tuis.openCore(name, args, done));
    }

    // The compositor places anchored surfaces relative to the item's own
    // window. An instance without a screen uses the focused monitor.
    function origin(ctx, anchor) {
        if (anchor === undefined || anchor === null) return ctx.screen ? { anchor: null, screen: ctx.screen } : null;
        const window = anchor.Window.window;
        let focused = window !== null ? window.activeFocusItem : null;
        for (let at = anchor; at !== null && at !== undefined; at = at.parent) {
            if (at.initialFocus !== undefined && at.initialFocus !== null) {
                focused = at.initialFocus;
                break;
            }
        }
        return {
            anchor: anchor,
            screen: ctx.screen,
            returnFocus: focused,
            returnFocusWasVisual: focused !== null && focused.visualFocus === true
        };
    }

    // run: a detached process from an argument list. No shell parses it.
    // `ok` means the list was handed to Quickshell; a program that fails to
    // start is not reported back. The program does not inherit
    // VGSHELL_RUNNER_PID, the variable that marks the shell's own processes: a
    // terminal the user opens from the shell is not the shell, and
    // `vgshell pkg run` refuses a caller that carries it. A null
    // value removes a variable from the inherited environment.
    function runDetached(argv) {
        if (!Array.isArray(argv) || argv.length === 0 || argv.some(a => typeof a !== "string" || a.length === 0))
            return "refused: argv=" + JSON.stringify(argv);
        Quickshell.execDetached({ command: argv, environment: { VGSHELL_RUNNER_PID: null } });
        return "ok";
    }

    // Whether `polkitRegister` is between destroying the agent and building
    // the next one.
    property bool polkitRebuilding: false

    // The polkit capability's `register`: asks polkitd again for an agent it
    // has not accepted. A PolkitAgent registers once, when it is built, so
    // the core destroys it and builds the next one, in a later turn; the
    // holder reads no agent in
    // between and then the new one, through `agent` and `registered`. A
    // registered agent stays as it is, which keeps a live request. Answers
    // `ok` once the agent is destroyed, `registered`, or `refused:
    // polkit=absent` while there is no agent: no plugin holds the
    // capability, or the next agent is not built yet.
    function polkitRegister() {
        if (polkitLoader.item === null) return "refused: polkit=absent";
        if (polkitLoader.item.isRegistered) return "registered";
        polkitRebuilding = true;
        return "ok";
    }

    // Called in the turn after the destroyed agent's: the next one may be
    // built. The function is the core's own, since a call queued from the
    // destroyed agent's own scope is dropped with it.
    function polkitRebuilt() {
        polkitRebuilding = false;
    }

    LazyLoader {
        id: polkitLoader
        active: root.polkitHeld && !root.polkitRebuilding
        // Each request that went live, counted for the lending record, so
        // a validation row can read that none ever did.
        PolkitAgent {
            onIsActiveChanged: if (isActive) root.polkitFlows += 1
            Component.onDestruction: if (root.polkitRebuilding) Qt.callLater(root.polkitRebuilt)
        }
    }

    // Every capability's live state, for the validation rows and for
    // diagnosing a plugin: who holds what, and which core objects exist.
    function lentJson() {
        const holders = {};
        for (const name of Object.keys(held)) holders[name] = holderIds(name);
        return JSON.stringify({
            holders: holders,
            shortcuts: Object.keys(shortcuts.shortcuts).sort(),
            idle: idleWatches.record(),
            ipcTargets: Object.keys(commands.ipcTargets).sort(),
            subscribers: notifications.subscribers.map(s => s.id),
            notificationServer: notifications.server !== null,
            polkitAgent: polkitLoader.item !== null,
            polkitRegistered: polkitLoader.item !== null && polkitLoader.item.isRegistered,
            polkitFlows: root.polkitFlows,
            lock: { requested: sessionLock.lockRequested, secure: sessionLock.lockSecure, content: sessionLock.lockContent !== null },
            layers: Layers.record(),
            status: PluginStatus.record(),
            theme: themes.record(),
            tui: tuis.record(),
            system: systemSteps.record(),
            sudo: sudoGrant.record(),
            bluetoothAgent: bluetoothAgent.record(),
            notices: Notices.record(),
            hyprland: hyprlandState.record(),
            monitors: monitorState.record()
        });
    }
}
