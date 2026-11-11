pragma Singleton
import QtQuick
import Quickshell
import qs.Core
import "KeyNavLogic.js" as Logic

// Display data only: HyprlandState remains the device/layout reader and
// owns every resolver request. Binding and capture continue to use raw keys.
// The single shared instance follows the Quickshell 0.3.1 singleton contract:
// https://quickshell.org/docs/v0.3.1/guide/qml-language#singletons
Singleton {
    id: root

    readonly property var physicalKeys: {
        const shortcuts = [];
        for (const id of Object.keys(Registry.manifests)) {
            const manifest = Registry.manifests[id];
            for (const bind of PluginLogic.hyprlandSection(Config.effective, manifest).binds)
                shortcuts.push(bind.key);
            if (manifest.hyprland !== undefined)
                for (const bind of manifest.hyprland.binds)
                    shortcuts.push(...PluginLogic.keyValues(bind.key));
        }
        return Logic.physicalKeys(shortcuts);
    }
    readonly property var symbolNames: Logic.symbolNames(PluginLogic.CAPTURE_KEY_NAMES)
    readonly property string inputs: JSON.stringify([physicalKeys, Capabilities.hyprland.devices, Capabilities.hyprland.keymapRevision])
    property var names: symbolNames
    property int generation: 0
    property bool pending: false

    onInputsChanged: {
        generation++;
        names = symbolNames;
        // Coalesce reads after the current binding turn:
        // https://doc.qt.io/qt-6/qml-qtqml-qt.html#callLater-method
        Qt.callLater(root.readNext);
    }
    Connections {
        target: Capabilities.hyprland
        function onResolvingKeysChanged() { Qt.callLater(root.readNext); }
    }

    function keyCaps(shortcut) {
        return Logic.keyCaps(shortcut, root.names);
    }

    function shortcutText(shortcut) {
        return Logic.shortcutText(shortcut, root.names);
    }

    function readNext() {
        if (pending || Capabilities.hyprland.resolvingKeys || Capabilities.hyprland.devices === null) return;
        const key = physicalKeys.find(key => !Object.prototype.hasOwnProperty.call(names, key.toUpperCase()));
        if (key === undefined) return;
        const askedGeneration = generation;
        pending = true;
        // One unresolved physical key must not hide the names of other keys:
        // xkb-keys resolves a batch wholly or refuses it wholly.
        Capabilities.hyprland.resolveKeys([key], answer => {
            pending = false;
            if (askedGeneration === generation) {
                const next = Object.assign({}, names);
                next[key.toUpperCase()] = answer.ok && answer.keys !== undefined ? answer.keys[0] : null;
                names = next;
            }
            Qt.callLater(root.readNext);
        });
    }
}
