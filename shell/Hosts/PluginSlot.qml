import QtQuick
import qs.Core

// One plugin instance of one kind inside a host. Owns the whole lifecycle:
// builds through the core, rebuilds when the plugin id or the plugin
// source revision changes, destroys before every rebuild and on its own
// destruction. Every host is a surface plus one of these per plugin.
FocusScope {
    id: slot

    required property string kind
    property string pluginId: ""
    // Names this slot in the core's build records; the smoke reads them.
    property string hostKey: ""
    // Host-owned properties the core assigns to the instance by name.
    property var context: ({})
    // The screen the instance draws on; null for a kind with no screen.
    property var screen: null
    property var instance: null
    property string loadedKey: ""
    // The host key the instance was built under. A host's key can change
    // while it is torn down (its screen reads null), so the instance is
    // destroyed under this one.
    property string loadedHostKey: ""
    // The plugin whose Settings page the instance's Pane offers through its
    // gear: a summoning host sets it from Registry.settingsPageOf, and ""
    // draws no gear.
    property string settingsPage: ""
    // Call the instance's close() before destroying it: a summoned kind's
    // host sets it, so a plugin closed by hide or by being disabled hears it.
    property bool closeOnUnload: false
    property var releaseInputSurface: null
    readonly property var inputWindow: slot.Window.window
    onInputWindowChanged: {
        if (releaseInputSurface !== null) releaseInputSurface();
        releaseInputSurface = Compositor.inputSurface(inputWindow);
    }

    // Only code failures suppress a host until its source changes. A
    // temporary enablement or lending refusal must remain eligible to retry.
    signal buildFailed(string key)
    // Emitted with every instance the slot builds.
    signal built(var instance)

    readonly property string key: Registry.slotKey(pluginId)

    onKeyChanged: reload()
    Component.onCompleted: reload()
    Component.onDestruction: {
        if (releaseInputSurface !== null) releaseInputSurface();
        unload();
    }

    function focusTarget() {
        let target = slot;
        if (instance !== null && instance.initialFocus !== undefined && instance.initialFocus !== null) target = instance.initialFocus;
        return typeof target.forceActiveFocus === "function" ? target : slot;
    }

    // Qt's no-keyboard reason keeps initial focus without a visible ring.
    // It also needs no deferred target across window activation or unload.
    // https://doc.qt.io/qt-6/qml-qtquick-item.html#forceActiveFocus-method
    function focusInitial() {
        const target = focusTarget();
        target.forceActiveFocus(Qt.OtherFocusReason);
        // Qt keeps a focused Control's previous reason when focus stays put.
        if ("focusReason" in target) target.focusReason = Qt.OtherFocusReason;
    }

    // Open the manager's window at the Settings page of `settingsPage`,
    // then hide this summon. The window opens first: the hide destroys
    // this slot. A refused window, such as one a restart is owed for,
    // leaves the summon open, so the click does not just close it.
    function openSettingsPage() {
        const kind = slot.kind;
        const id = slot.pluginId;
        const shown = Plugins.route("summon", "window", Registry.managerId, JSON.stringify({ plugin: settingsPage }), null);
        if (shown !== "ok") {
            console.warn("plugin slot: settings page of " + id + " " + shown);
            return;
        }
        const hidden = Plugins.route("hide", kind, id, "", null);
        if (hidden !== "ok") console.warn("plugin slot: hide of " + id + " for its settings page " + hidden);
    }

    function unload() {
        if (instance !== null) {
            if (closeOnUnload) {
                try {
                    instance.close();
                } catch (e) {
                    console.error("plugin slot: " + pluginId + " close() failed: " + e.message);
                }
            }
            Plugins.destroyInstance(instance, loadedHostKey);
            instance = null;
        }
        loadedKey = "";
        loadedHostKey = "";
    }

    function reload() {
        if (key === loadedKey) return;
        unload();
        if (key === "") return;
        // Lending changes take a refused key away, then restore it when the
        // capability becomes available. Settings alone do not trigger retries.
        loadedKey = key;
        const result = Plugins.createInstance(pluginId, kind, slot, hostKey, null, context, screen);
        if (result.state === "failed") { buildFailed(key); return; }
        if (result.state === "refused") return;
        instance = result.instance;
        instance.anchors.fill = slot;
        loadedHostKey = hostKey;
        built(instance);
    }
}
