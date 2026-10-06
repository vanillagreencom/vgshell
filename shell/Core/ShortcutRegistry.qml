import QtQuick
import Quickshell
import Quickshell.Hyprland
import "PluginLogic.js" as Logic
import "HyprlandLayer.js" as Layer

// Owns shortcut registrations across plugin instances. Each registration
// belongs to its instance lifetime and releases its native object with it.
// Key capture, the Settings key field's press-the-key entry, is the
// `capture` member, which KeyCapture owns. The enabled plugins' launcher
// rows, Registry.menu, are the `menu` member, and `activate` runs the
// shortcut a listed row names.
Scope {
    id: root
    property var shortcuts: ({})
    // HyprlandState, whose foreign binds the key capture's hint reads.
    property var bindsSource: null
    readonly property alias keyCapture: capture

    KeyCapture { id: capture; bindsSource: root.bindsSource }

    Component.onCompleted: {
        const capture = Layer.OVERLAY_CAPTURE;
        for (const direction of Layer.overlayCaptureDirections())
            registerCoreShortcut(capture.appid, capture.shortcuts[direction], "Navigate the open overlay " + direction, () => Plugins.navigateOverlay(direction));
    }

    function provider(ctx) {
        // REVISIT(D059): A compositor readback API could include later user overrides.
        return {
            get keys() { return Layer.shortcutKeys(Registry.hyprlandSections, ctx.id); },
            register: (name, description, onPressed, onReleased) => root.registerShortcut(ctx, name, description, onPressed, onReleased),
            // Every enabled plugin's launcher rows, a frozen copy per read.
            get menu() { return Logic.frozenJson(Registry.menu.rows); },
            rows: menuId => root.rows(menuId),
            get revision() { return root.providerRevision(); },
            activate: (key, item) => root.activate(key, item),
            capture: capture.provider(ctx)
        };
    }

    // One registration owns the main GlobalShortcut and, for an onReleased
    // caller, its release companion. The instance owns one disposer for both.
    function registerShortcut(ctx, name, description, onPressed, onReleased) {
        Capabilities.checkName("shortcut", name);
        const shortcut = root.registerHeldShortcut(ctx.id, name, description, onPressed, onReleased);
        return ctx.onDispose(() => root.releaseShortcut(ctx.id + ":" + name, shortcut));
    }

    // Run the press handler of global KEY, `<plugin id>:<name>`, for a
    // launcher row: only a key a listed row names and a live registration
    // holds, as PluginLogic.menuActivation answers.
    function providerValues() {
        const out = {};
        const plugins = {};
        for (const row of Registry.menu.rows) if (row.provider) plugins[row.plugin] = true;
        for (const id of Object.keys(plugins)) out[id] = PluginStatus.valuesOf(id);
        return out;
    }

    function rows(menuId) {
        let owner = null;
        for (const row of Registry.menu.rows) if (row.id === menuId && row.provider) owner = row;
        return Logic.frozenJson(owner === null ? [] : Logic.providerRows(Registry.menu.rows, menuId, PluginStatus.valuesOf(owner.plugin)));
    }

    function providerRevision() {
        // Reads Registry.menu and PluginStatus.records, so bindings refresh
        // after either provider membership or its published rows change.
        void PluginStatus.records;
        return Registry.menu.rows.filter(row => row.provider).map(row => row.plugin + ":" + PluginStatus.revisionOf(row.plugin)).join("|");
    }

    function activate(key, item) {
        const answer = Logic.menuActivation(Registry.menu.rows, shortcuts, key, item, providerValues());
        if (answer === "ok") shortcuts[key].handler(item);
        return answer;
    }

    function registerCoreShortcut(appid, name, description, onPressed) {
        Capabilities.checkName("shortcut", name);
        registerHeldShortcut(appid, name, description, onPressed);
    }

    function registerHeldShortcut(appid, name, description, onPressed, onReleased) {
        if (typeof onPressed !== "function")
            throw new Error("refused: shortcut=" + name + " handler=not-a-function");
        if (onReleased !== undefined && typeof onReleased !== "function")
            throw new Error("refused: shortcut=" + name + " release-handler=not-a-function");
        const key = appid + ":" + name;
        if (Logic.hasOwn(shortcuts, key))
            throw new Error("refused: shortcut=" + key + " held");
        const shortcut = shortcutComponent.createObject(root, { appid: appid, name: name, description: String(description || "") });
        shortcut.handler = onPressed;
        if (onReleased !== undefined) {
            shortcut.releaseHandler = onReleased;
            const companion = releaseComponent.createObject(shortcut, { appid: appid, name: Layer.releaseShortcutName(name), description: String(description || "") });
            companion.owner = shortcut;
            shortcut.companion = companion;
        }
        const next = Object.assign({}, shortcuts);
        next[key] = shortcut;
        shortcuts = next;
        return shortcut;
    }

    function releaseShortcut(key, shortcut) {
        const rest = Object.assign({}, root.shortcuts);
        delete rest[key];
        root.shortcuts = rest;
        try { shortcut.finish("disposed"); }
        finally { shortcut.destroy(); }
    }

    // The `pressed` property shadows the `pressed` signal from script, so
    // the handler runs from the signal handler instead of a connect().
    Component {
        id: shortcutComponent
        GlobalShortcut {
            id: shortcut
            property var handler: null
            property var releaseHandler: null
            property var companion: null
            property var stroke: ({ kind: "idle" })
            readonly property var effectiveKey: Layer.shortcutKeys(Registry.hyprlandSections, appid)[name]

            function finish(nextKind) {
                const held = stroke.kind === "held";
                stroke = { kind: nextKind };
                if (held) releaseHandler();
            }

            onEffectiveKeyChanged: {
                if (stroke.kind === "held" && stroke.key !== effectiveKey)
                    finish("idle");
            }

            onPressed: {
                if (stroke.kind === "disposed") return;
                if (releaseHandler === null) { handler(); return; }
                if (stroke.kind === "held") return;
                // Registry can change before Hyprland replaces its old binds.
                const key = Layer.shortcutKeys(Registry.hyprlandSections, appid)[name];
                if (key === null || key === undefined) return;
                stroke = { kind: "held", key: key };
                handler();
            }
            // Lua global dispatch can lose this object's native release
            // when the modifier mask changes. The companion owns that edge.
        }
    }

    // The companion bind ignores modifiers, so it also fires on releases of
    // unrelated chords, and a virtual keyboard can send one: it only ends a
    // stroke a press started.
    Component {
        id: releaseComponent
        GlobalShortcut {
            property var owner: null
            onReleased: {
                if (owner.stroke.kind === "held") owner.finish("idle");
            }
        }
    }

}
