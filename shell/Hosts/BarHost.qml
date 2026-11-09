import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Wayland
import qs.Core
import qs.Commons
import qs.Ui

// A disabled, unknown or broken bar must reserve no desktop space.
// Hiding a layer-shell window releases its Wayland surface's reserved
// space while retaining the plugin instance for the next show.
Item {
    id: host

    required property var modelData
    readonly property var screen: modelData
    readonly property bool screenPresent: Quickshell.screens.indexOf(screen) !== -1
    // The screen is null while its Variants entry is torn down.
    readonly property string hostKey: "bar:" + (screen ? screen.name : "")

    // The slot key the active bar would load under, or "" when no bar can
    // be built. A key whose build failed is remembered so the window is not
    // re-created for it; a source revision change makes a new key.
    readonly property string wantedKey: Registry.slotKey(Registry.activeBarId)
    property string brokenKey: ""

    Loader {
        id: surface
        // Quickshell.screens drops a removed screen before Qt moves its
        // windows to another screen, and a window still built then gets a
        // layer surface there, reserving space twice until it goes.
        active: host.screenPresent && host.wantedKey !== "" && host.wantedKey !== host.brokenKey
        sourceComponent: PanelWindow {
            id: barWindow
            screen: host.screen

            anchors { top: true; left: true; right: true }
            implicitHeight: Theme.bar.height
            exclusiveZone: implicitHeight
            color: Theme.bar.background
            WlrLayershell.namespace: "vgs:bar"
            WlrLayershell.layer: WlrLayer.Top
            // Quickshell 0.3.1 defers native window deletion after the Loader
            // drops its item. Hide first, or Qt can remap it as a toplevel
            // while a removed output migrates its windows.
            visible: host.screenPresent && PluginLogic.barShown(slot.instance)

            // QsWindow's visible and backingWindowVisible are distinct;
            // windowTransform invalidates its non-reactive item mapping.
            // https://quickshell.org/docs/v0.3.1/types/Quickshell/QsWindow/
            // As in LayerHost and Bubble's approval handshake, polish,
            // sync and swap travel in order. Never acknowledge GUI state
            // that changed after that frame's polish.
            property int frameEpoch: 0
            // Keep the publication address while a removed screen becomes null.
            property string observationHost: ""
            property var observedWidgets: []
            property var frames: []
            property var synchronizedFrame: null
            readonly property var candidates: observeItems()
            readonly property string candidateKey: JSON.stringify(candidates)
            onCandidateKeyChanged: invalidateFrame()
            readonly property var covers: observeCovers()
            onCoversChanged: Layers.setBarCovers(observationHost, covers)
            onVisibleChanged: invalidateFrame()
            onBackingWindowVisibleChanged: invalidateFrame()
            Component.onCompleted: {
                observationHost = host.hostKey;
                widgetSetChanged();
            }
            Component.onDestruction: {
                invalidateFrame();
                Layers.setBarCovers(observationHost, []);
            }

            function invalidateFrame() {
                frameEpoch++;
                Layers.setBarFrame(observationHost, []);
            }

            // The rows of Plugins.built for the core's bar widgets on this bar.
            function widgetRows() {
                return (Plugins.built[host.hostKey] || []).filter(row => row.origin === "core" && row.kind === "bar-widget");
            }

            // Those rows while this bar is mapped on its own screen; none
            // otherwise, so nothing is observed on an unmapped bar.
            function mappedWidgetRows() {
                if (!visible || !backingWindowVisible || !host.screenPresent || screen !== host.screen) return [];
                return widgetRows();
            }

            function widgetSetChanged() {
                const current = widgetRows().map(row => row.instance);
                if (current.length === observedWidgets.length && current.every((item, i) => item === observedWidgets[i])) return;
                observedWidgets = current;
                invalidateFrame();
            }

            // Refuse a partial, faded, clipped or transformed indicator.
            // Read every ancestor's geometry in this binding as mapToItem
            // alone records no dependency (QsWindow reference above).
            function whole(item, owner) {
                if (item === null || item.width <= 0 || item.height <= 0) return false;
                let owned = false;
                for (let at = item; at !== null; at = at.parent) {
                    if (at === owner) owned = true;
                    if (!at.visible || at.opacity !== 1 || at.scale !== 1 || at.rotation !== 0 || at.transform.length !== 0) return false;
                    const geometry = [at.x, at.y, at.width, at.height];
                    if (at.clip || at === contentItem) {
                        const p = item.mapToItem(at, 0, 0);
                        if (p.x < 0 || p.y < 0 || p.x + item.width > geometry[2] || p.y + item.height > geometry[3]) return false;
                    }
                    // A scrolling bar section already owns its whole-widget
                    // viewport, excluding its scroller buttons and fades.
                    if (at.shownX !== undefined && at.shownWidth !== undefined) {
                        const p = item.mapToItem(at, 0, 0);
                        if (p.x < at.shownX || p.x + item.width > at.shownX + at.shownWidth) return false;
                    }
                    if (at === contentItem) return owned;
                }
                return false;
            }

            function observeItems() {
                const transform = windowTransform;
                const out = [];
                for (const row of mappedWidgetRows()) {
                    const widget = row.instance;
                    const item = widget.presentationItem;
                    if (!(item instanceof BarItem) || !whole(item, widget) || widget.presentationKey === "") continue;
                    const dot = item.stateDotItem;
                    out.push({ plugin: row.id, revision: row.revision, output: screen.name,
                        key: widget.presentationKey, dot: dot !== null && whole(dot, item) ? item.stateDot : "" });
                }
                return out;
            }

            // Each widget's declared cover, a box in this window, which
            // spans its output from the output's top edge (anchors above):
            // `x` across the output, `top` and `bottom` counted down from
            // this bar's bottom edge. The popup that draws the box follows its
            // anchor and empties the box as it closes (PassivePopup).
            function observeCovers() {
                const out = [];
                for (const row of mappedWidgetRows()) {
                    const cover = row.instance.cover;
                    if (!(cover.width > 0 && cover.height > 0)) continue;
                    out.push({ output: screen.name, x: cover.x, width: cover.width,
                        top: cover.y - height, bottom: cover.y + cover.height - height });
                }
                return out;
            }

            function framePolished() {
                frames.push({ epoch: frameEpoch, rows: candidates });
            }
            function frameSynchronized() {
                synchronizedFrame = frames.length === 0 ? null : frames.shift();
            }
            function frameSwapped() {
                const drawn = synchronizedFrame;
                if (drawn === null) return;
                Qt.callLater(() => {
                    if (drawn.epoch !== frameEpoch || !visible || !backingWindowVisible) return;
                    Layers.setBarFrame(observationHost, drawn.rows);
                });
            }
            Connections {
                target: slot.instance !== null ? slot.instance.Window.window : null
                function onAfterAnimating() { barWindow.framePolished(); }
                function onAfterSynchronizing() { barWindow.frameSynchronized(); }
                function onFrameSwapped() { barWindow.frameSwapped(); }
            }
            Connections {
                target: Plugins
                function onBuiltChanged() { barWindow.widgetSetChanged(); }
            }

            PluginSlot {
                id: slot
                listed: surface.active
                kind: "bar"
                pluginId: Registry.activeBarId
                hostKey: host.hostKey
                screen: host.screen
                context: ({ screen: host.screen })
                anchors.fill: parent
                onBuildFailed: key => host.brokenKey = key
            }
        }
    }
}
