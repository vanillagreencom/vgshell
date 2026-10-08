import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Core
import qs.Commons
import "Commons/Tokens.js" as Tokens
import "Commons/ThemeLogic.js" as ThemeLogic

// Loaded only into the sandbox copy. It observes the shipped objects and
// owns test setup, so tests add no callable methods to the shipped shell.
Scope {
    id: root
    property var rememberedBarWidgets: []
    property string rememberedBarHost: ""
    property var rememberedNetworkDevice: null
    property Item rememberedNetworkShare: null
    property var networkOriginalShell: null
    property int builds: 0
    property int frames: 0
    property int holdMarkers: 0
    property var holdMarker: null
    Component {
        id: holdMarkerComponent
        GlobalShortcut {
            appid: "smoke"
            name: "hold-marker"
            description: "Order hold shortcut observations"
            onPressed: root.holdMarkers += 1
        }
    }
    property var layerFrameSurface: null
    readonly property var layerFrameWindow: layerFrameSurface === null ? null : layerFrameSurface.contentItem.Window.window
    property int layerFrames: 0
    property bool layerFrameListening: true
    property int changes: 0
    property int userLoads: 0
    property var previousRows: []
    // What the shell did from its start, in order, for rows/start-order.sh:
    // ["scan"] per ended scan and ["scan-turn-end"] once the event loop has
    // run past the turn that ended it, ["frame", n] when a bar window
    // presents its first frame, n the bar windows presented so far,
    // ["service", id] per service the core built, ["release", reason] when
    // ServiceGate releases the services, and ["follow"] per follow job the
    // theme runner queued.
    property var startOrder: []
    property var presentedWindows: []
    property var followJobs: []
    property var heldField: null
    property var heldEditor: null
    property string grab: ""
    // A plugin instance's status provider, kept past the instance, so a row
    // writes through it once the core has retired the instance.
    property var heldStatus: null
    // A copy of the core's ThemeRunner built from a file for a control, and
    // what each of its members' callbacks received: verb -> { count,
    // result }. The copy's context is never torn down.
    property var runnerCopy: null
    property var runnerAnswers: ({})
    // Copies of a core popup, a qs.Ui overlay or SummonPopup, built from a
    // file a row writes beside the shipped one for a dismissal control, by
    // the name the row gives each.
    property var popupCopies: ({})
    // name -> how many times the SummonLayer copy of that name was dismissed.
    property var layerDismissals: ({})
    // [window, size] per window windowDrawn listens on: the size, `WxH`,
    // of the last frame it presented.
    property var drawnWindows: []
    property var rememberedLayers: []
    // The vgs.polkit prompt over a stand-in authentication flow, for the
    // polkit scene of scripts/sandbox-shots.sh: no sandbox path runs a live
    // flow (docs/decisions/D062-native-lock-and-polkit-plugins.md). While shown it
    // is { surface, prompt, flow }, else null.
    property var polkitStandIn: null
    readonly property var runnerContext: ({ id: "smoke-runner-copy", onDispose: () => () => {} })

    // JSON reply helper for every probe answer that can grow.
    function json(value) {
        const text = JSON.stringify(value);
        return IpcPages.answer(text === undefined ? "undefined" : text);
    }

    // Call the copy's member VERB with ARGS, then `done`, then any EXTRA,
    // its answers kept by verb; the member's reply, `ok` for none.
    function callRunner(verb, args, ...extra) {
        if (root.runnerCopy === null) return "absent";
        const done = result => {
            const next = Object.assign({}, root.runnerAnswers);
            next[verb] = { count: (verb in root.runnerAnswers ? root.runnerAnswers[verb].count : 0) + 1, result: result };
            root.runnerAnswers = next;
        };
        const reply = root.runnerCopy[verb](root.runnerContext, ...args, done, ...extra);
        return reply === undefined ? "ok" : IpcPages.answer(String(reply));
    }

    function note(event) { root.startOrder = root.startOrder.concat([event]); }

    Connections {
        target: Plugins
        function onBuiltChanged() {
            const rows = [];
            for (const key of Object.keys(Plugins.built))
                for (const row of Plugins.built[key])
                    if (row.origin === "core") rows.push(row);
            for (const row of rows)
                if (root.previousRows.indexOf(row) === -1) {
                    root.builds += 1;
                    if (row.kind === "service") root.note(["service", row.id]);
                }
            root.previousRows = rows;
        }
    }
    Connections {
        target: Registry
        function onScanFinished() {
            root.note(["scan"]);
            Qt.callLater(() => root.note(["scan-turn-end"]));
        }
    }
    Connections {
        target: ServiceGate
        function onReleaseChanged() { root.note(["release", ServiceGate.release]); }
    }
    Connections {
        target: Capabilities.themes
        function onJobsChanged() {
            for (const job of Capabilities.themes.jobs)
                if (job.verb === "follow" && root.followJobs.indexOf(job) === -1) {
                    root.followJobs = root.followJobs.concat([job]);
                    root.note(["follow"]);
                }
        }
    }
    Connections {
        target: Config
        function onEffectiveChanged() { root.changes += 1; }
    }
    Connections {
        target: Config.smokeUserView
        function onLoaded() { root.userLoads += 1; }
        function onLoadFailed(error) { root.userLoads += 1; }
    }
    Variants {
        model: {
            const windows = [];
            for (const key of Object.keys(Plugins.built))
                for (const row of Plugins.built[key])
                    if (row.origin === "core" && row.kind === "bar") windows.push(row.instance.Window.window);
            return windows;
        }
        Connections {
            required property var modelData
            target: modelData
            function onFrameSwapped() {
                root.frames += 1;
                if (root.presentedWindows.indexOf(modelData) !== -1) return;
                root.presentedWindows = root.presentedWindows.concat([modelData]);
                root.note(["frame", root.presentedWindows.length]);
            }
        }
    }

    FileView { id: uiModule; path: Qt.resolvedUrl("Ui/qmldir"); blockLoading: true }

    // The stand-in flow holds the members of Quickshell's AuthFlow that
    // PolkitModel.viewOf and the prompt read, as pkexec asks for a
    // program. Its submit and cancel only count, so nothing reaches polkitd
    // or PAM, and no password is ever typed into it.
    Component {
        id: polkitStandInFlow
        QtObject {
            property string message: "Authentication is needed to run `/usr/bin/pacman' as the super user"
            property string actionId: "org.freedesktop.policykit.exec"
            property var identities: [{ displayName: "Ada Lovelace", string: "ada", isGroup: false }]
            property var selectedIdentity: identities[0]
            property bool isResponseRequired: true
            property string inputPrompt: "Password: "
            property bool responseVisible: false
            property string supplementaryMessage: ""
            property bool supplementaryIsError: false
            property bool failed: false
            property bool isCompleted: false
            property bool isCancelled: false
            property int submits: 0
            property int cancels: 0
            function submit(response) { submits += 1; }
            function cancelAuthenticationRequest() {
                cancels += 1;
                isCancelled = true;
            }
        }
    }

    // The overlay layer surface the summon host builds for an unanchored
    // summon (the `layer` component of shell/Hosts/SummonHost.qml), with
    // the placement and keyboard focus the core's judge gives kind overlay.
    Component {
        id: polkitStandInSurface
        PanelWindow {
            readonly property var place: PluginLogic.surfacePlacement("overlay", {}, Theme.space.md)
            anchors { top: place.anchors.top; bottom: place.anchors.bottom; left: place.anchors.left; right: place.anchors.right }
            margins { top: place.margins.top; bottom: place.margins.bottom; left: place.margins.left; right: place.margins.right }
            exclusionMode: place.exclusion === "ignore" ? ExclusionMode.Ignore : ExclusionMode.Normal
            exclusiveZone: 0
            color: "transparent"
            WlrLayershell.namespace: "vgs:overlay"
            WlrLayershell.layer: place.layer === "top" ? WlrLayer.Top : WlrLayer.Overlay
            WlrLayershell.keyboardFocus: PluginLogic.layerKeyboardFocus("overlay", false) === "exclusive" ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand
        }
    }

    Connections {
        target: root.layerFrameListening ? root.layerFrameWindow : null
        function onFrameSwapped() { root.layerFrames += 1; }
    }

    function instance(hostKey, id) {
        const rows = Plugins.built[hostKey] || [];
        const row = rows.find(r => r.id === id);
        return row === undefined ? null : row.instance;
    }

    function descendants(item) {
        const found = [item];
        for (let i = 0; i < found.length; i++)
            for (const child of found[i].children || []) found.push(child);
        return found;
    }

    function shownScrollAreas(item) {
        const shown = child => { for (let at = child; at !== null; at = at.parent) if (!at.visible) return false; return true; };
        const isScroll = child => child.bar !== undefined && child.contentY !== undefined;
        const nested = child => {
            for (let at = child.parent; at !== null && at !== item; at = at.parent)
                if (isScroll(at) && shown(at)) return true;
            return false;
        };
        return root.descendants(item).filter(child => isScroll(child) && shown(child) && !nested(child) && child.mapToItem(item, 0, 0).x >= 0 && child.mapToItem(item, 0, 0).x < item.width);
    }

    // The first visible, enabled item named `type` whose `text` is `text`
    // under an instance, or null.
    function textItem(hostKey, id, type, text) {
        const item = root.instance(hostKey, id);
        if (item === null) return null;
        const found = root.descendants(item).find(child => root.typeName(child) === type && child.text === text && child.visible && child.enabled);
        return found === undefined ? null : found;
    }

    // The first visible, enabled item named `type` whose `property` reads
    // `value` in a plugin's layer copies, sorted by screen, or null.
    function layerItem(id, type, property, value) {
        for (const entry of Layers.entries.filter(e => e.pluginId === id))
            for (const screen of Object.keys(entry.screens).sort()) {
                const found = root.descendants(entry.screens[screen]).find(child => root.typeName(child) === type && String(child[property]) === value && child.visible && child.enabled);
                if (found !== undefined) return found;
            }
        return null;
    }

    // The first visible, enabled item named `type` whose `text`, `name`
    // for an icon, `label` for an icon button or `currentText` for a
    // Select is `text` inside the first visible item named
    // `scopeType` that draws `scopeText`, under an instance, or null: one
    // row's button among rows that each draw a button with the same text.
    function scopedItem(hostKey, id, scopeType, scopeText, type, text) {
        const item = root.instance(hostKey, id);
        if (item === null) return null;
        const draws = node => root.descendants(node).some(child => child instanceof Text && child.visible && child.text === scopeText);
        const scope = root.descendants(item).find(child => root.typeName(child) === scopeType && child.visible && draws(child));
        if (scope === undefined) return null;
        const found = root.descendants(scope).find(child => root.typeName(child) === type && root.reads(child, text) && child.visible && child.enabled);
        return found === undefined ? null : found;
    }

    // The first visible, enabled item named `type` that reads `text`
    // (reads) inside an open overlay of an instance, a Menu, a Popover or a
    // Select's list, whose content lives in its own popup window, found
    // through the overlay's AnchorTracker; inside the first item named
    // `scopeType` that draws `scopeText` when `scopeType` is not empty, as
    // scopedItem scopes. null when there is none.
    function popupItem(hostKey, id, scopeType, scopeText, type, text) {
        const item = root.instance(hostKey, id);
        if (item === null) return null;
        const draws = node => root.descendants(node).some(child => child instanceof Text && root.visibleInTree(child) && child.text === scopeText);
        for (const owner of root.descendants(item)) {
            const popup = owner.tracker !== undefined && owner.tracker !== null ? owner.tracker.popup : null;
            if (popup === null || popup === undefined || !popup.visible) continue;
            let within = popup.contentItem;
            if (scopeType !== "") {
                const scope = root.descendants(within).find(child => root.typeName(child) === scopeType && root.visibleInTree(child) && draws(child));
                if (scope === undefined) continue;
                within = scope;
            }
            const found = root.descendants(within).find(child => root.typeName(child) === type && root.reads(child, text) && root.visibleInTree(child) && child.enabled);
            if (found !== undefined) return found;
        }
        return null;
    }

    // Whether an item reads `text`: its `text`, its `name` for an icon,
    // its `label` for an icon button, or its `currentText` for a Select,
    // which draws its choice and holds no text of its own.
    function reads(child, text) {
        return child.text === text || child.name === text || child.label === text || child.currentText === text;
    }

    // The window box of the first visible item named `type` under an
    // instance that reads `text` (reads), and enabled when `enabledOnly`
    // holds, or "absent".
    function labelledBox(hostKey, id, type, text, enabledOnly) {
        const item = root.instance(hostKey, id);
        if (item === null) return "absent";
        const found = root.descendants(item).find(child => root.typeName(child) === type && root.reads(child, text) && child.visible && (child.enabled || !enabledOnly));
        return found === undefined ? "absent" : root.json(root.windowBox(found));
    }

    function fieldOf(panel, id, key) {
        return descendants(panel).find(item => item.pluginId === id && item.key === key && typeof item.apply === "function") || null;
    }

    // A Select's list as drawn: whether it is open, the texts its open
    // window shows, the entries it can choose and its `emptyText`.
    function selectList(select) {
        const content = select.tracker.popup.contentItem;
        const view = descendants(content).find(child => child instanceof ListView);
        return { open: select.listOpen, empty: select.emptyText,
            lines: select.listOpen ? descendants(content).filter(child => child instanceof Text && child.text !== "" && visibleInTree(child)).map(child => child.text) : [],
            entries: view === undefined ? -1 : view.count };
    }

    function visibleInTree(child) {
        for (let at = child; at !== null; at = at.parent)
            if (at.visible === false) return false;
        return true;
    }

    function geometry(item) {
        if (item === null) return "absent";
        const at = item.mapToGlobal(0, 0);
        return root.json([at.x, at.y, item.width, item.height]);
    }

    function topRoot(item) {
        let at = item;
        while (at !== null && at.parent !== null) at = at.parent;
        return at;
    }

    function chromeRoots() {
        const roots = [];
        const add = item => {
            if (item === null || item === undefined) return;
            const top = root.topRoot(item);
            if (top !== null && roots.indexOf(top) === -1) roots.push(top);
        };
        for (const key of Object.keys(Plugins.built))
            for (const row of Plugins.built[key]) add(row.instance);
        for (const entry of Layers.entries)
            for (const screen of Object.keys(entry.screens).sort()) add(entry.screens[screen]);
        return roots;
    }

    function chromeShown(child) {
        const target = root.typeName(child) === "Tooltip" ? child.anchorItem : child;
        if (target === null || target === undefined || target.width <= 0 || target.height <= 0) return false;
        for (let at = target; at !== null; at = at.parent)
            if (at.visible === false) return false;
        const window = target.Window.window;
        if (window === null) return false;
        const onWindow = target.mapToItem(null, 0, 0);
        if (onWindow.x + target.width <= 0 || onWindow.y + target.height <= 0 || onWindow.x >= window.width || onWindow.y >= window.height)
            return false;
        for (let at = target.parent; at !== null; at = at.parent) {
            if (at.clip !== true) continue;
            const pos = target.mapToItem(at, 0, 0);
            if (pos.x + target.width <= 0 || pos.y + target.height <= 0 || pos.x >= at.width || pos.y >= at.height)
                return false;
        }
        return true;
    }

    function clearVisualFocusFrom(item) {
        for (const child of root.descendants(item)) {
            try {
                if (child.visualFocus === true && ("focusReason" in child))
                    child.focusReason = Qt.OtherFocusReason;
            } catch (e) {}
        }
    }

    function chromeWord(clear) {
        const roots = root.chromeRoots();
        if (clear) for (const item of roots) root.clearVisualFocusFrom(item);
        const words = [];
        const add = word => { if (words.indexOf(word) === -1) words.push(word); };
        for (const item of roots) {
            for (const child of root.descendants(item)) {
                const type = root.typeName(child);
                try {
                    if (type === "Tooltip" && child.opened === true && root.chromeShown(child)) add("tooltip");
                    if (type === "FocusRing" && child.visible === true && root.chromeShown(child)) add("focus-ring");
                } catch (e) {}
            }
        }
        return words.length === 0 ? "clean" : words.join(",");
    }

    // An item's box in its own window's coordinates, as [x, y, w, h]: a
    // layer surface the compositor centres knows no place of its own on the
    // screen, so a row adds the layer's position from `hyprctl layers`.
    // The innermost shown ScrollArea under `item` that holds `target`.
    function scrollAreaHolding(item, target) {
        const areas = root.shownScrollAreas(item).filter(area => root.descendants(area).indexOf(target) !== -1);
        return areas.find(area => !areas.some(other => other !== area && root.descendants(area).indexOf(other) !== -1));
    }
    // revealText moves the target a third of the way down its view.
    function revealIn(item, target) {
        if (item === null || target === null) return "absent";
        const flick = root.scrollAreaHolding(item, target);
        if (flick === undefined) return "unscrolled";
        const y = target.mapToItem(flick.contentItem, 0, 0).y - flick.height / 3;
        flick.contentY = Math.max(0, Math.min(y, flick.contentHeight - flick.height));
        return String(flick.contentY);
    }

    // viewHolding's view: the nearest Flickable ancestor of the first
    // shown item under the instance that reads `text`, or `absent` for no
    // such item, `no-view` for one no Flickable holds.
    function viewOf(hostKey, id, text) {
        const item = root.instance(hostKey, id);
        if (item === null) return "absent";
        const target = root.descendants(item).find(child => root.reads(child, text) && root.visibleInTree(child));
        if (target === undefined) return "absent";
        for (let at = target.parent; at !== null && at !== item.parent; at = at.parent)
            if (at.contentY !== undefined && at.flickableDirection !== undefined) return at;
        return "no-view";
    }

    // dialogCard's items: the one Dialog under the instance and the
    // MouseArea among the children of its card, the Rectangle it draws
    // behind its content, or `absent`, `dialogs=<n>` or `no-card-area`.
    function dialogCardArea(hostKey, id) {
        const item = root.instance(hostKey, id);
        if (item === null) return "absent";
        const dialogs = root.descendants(item).filter(child => root.typeName(child) === "Dialog");
        if (dialogs.length !== 1) return "dialogs=" + dialogs.length;
        for (const card of dialogs[0].children) {
            if (root.typeName(card) !== "QQuickRectangle") continue;
            const area = card.children.find(child => root.typeName(child) === "QQuickMouseArea");
            if (area !== undefined) return { dialog: dialogs[0], area: area };
        }
        return "no-card-area";
    }

    function windowBox(item) {
        const at = item.mapToItem(null, 0, 0);
        return [at.x, at.y, item.width, item.height];
    }

    // An item's type name, with the engine's suffixes for a QML-defined type
    // and for one extended in place (a delegate that declares a property of
    // its own) removed.
    function typeName(item) {
        return String(item).split("(")[0].replace(/(_QML(TYPE)?_\d+)+$/, "");
    }

    function read(hostKey, id, property) {
        const item = instance(hostKey, id);
        if (item === null) return "absent";
        const value = item[property];
        const json = root.json(value);
        return json === undefined ? "undefined" : json;
    }

    // Build a disposable host copy from FILE on the focused screen, kept
    // under NAME for popupDrop, with the properties PROPERTIESOF returns for
    // that screen: the made copy, or the answer that refuses it.
    function hostCopy(name, file, propertiesOf) {
        if (name in root.popupCopies) return "loaded";
        const screen = Compositor.focusedScreen();
        if (screen === null) return "refused: screen=none";
        const component = Qt.createComponent("file://" + file);
        if (component.status !== Component.Ready) return IpcPages.answer("error: " + component.errorString().trim().replace(/\n/g, " "));
        const made = component.createObject(root, propertiesOf(screen));
        if (made === null) return "error: create";
        const next = Object.assign({}, root.popupCopies);
        next[name] = made;
        root.popupCopies = next;
        return made;
    }

    function invoke(hostKey, id, name, arg) {
        const item = instance(hostKey, id);
        if (item === null) return "absent";
        // A Settings step as its button hands it to the window (D061):
        // `act` {id, key}, `openTui` {id, name}, `storeSecret` {id, key,
        // account, secret} and `clearSecret` {id, key, account}; each
        // answers the manager.
        if (name === "act") {
            const a = JSON.parse(arg);
            return item.act(a.id, a.key);
        }
        if (name === "openTui") {
            const a = JSON.parse(arg);
            return item.openTui(a.id, a.name);
        }
        if (name === "storeSecret") {
            const a = JSON.parse(arg);
            return item.storeSecret(a.id, a.key, a.account, a.secret);
        }
        if (name === "clearSecret") {
            const a = JSON.parse(arg);
            return item.clearSecret(a.id, a.key, a.account);
        }
        if (name === "applySetting") {
            const a = JSON.parse(arg);
            return IpcPages.answer(item.writeSetting(a.id, a.key, a.value));
        }
        if (name === "fieldChoice" || name === "chooseField" || name === "focusField") {
            const a = JSON.parse(arg);
            const field = fieldOf(item, a.id, a.key);
            if (field === null) return "absent";
            const editor = descendants(field).find(child => typeName(child) === "Select");
            if (editor === undefined) return "no-select";
            if (name === "chooseField") {
                editor.choose(a.index);
                return "chosen";
            }
            if (name === "focusField") {
                // As a Tab gives it, so a row's real key press reaches it.
                editor.forceActiveFocus(Qt.TabFocusReason);
                return editor.activeFocus ? "focused" : "unfocused";
            }
            return root.json({ model: editor.model, index: editor.currentIndex, text: editor.currentText, value: field.value, enabled: editor.enabled,
                shown: editor.contentItem.text, list: root.selectList(editor) });
        }
        if (name === "fieldBoolean" || name === "focusBoolean") {
            const a = JSON.parse(arg);
            const field = fieldOf(item, a.id, a.key);
            if (field === null) return "absent";
            const editor = descendants(field).find(child => typeName(child) === "Switch");
            if (editor === undefined) return "no-switch";
            if (name === "focusBoolean") {
                editor.forceActiveFocus(Qt.TabFocusReason);
                return editor.activeFocus ? "focused" : "unfocused";
            }
            return root.json({ type: field.spec.type, value: field.value, checked: editor.checked, enabled: editor.enabled });
        }
        if (name === "fieldCustom" || name === "editFieldCustom") {
            const a = JSON.parse(arg);
            const field = fieldOf(item, a.id, a.key);
            if (field === null) return "absent";
            const shown = descendants(field).filter(child => visibleInTree(child));
            const editor = shown.find(child => child instanceof TextInput);
            const formatted = editor === undefined || SettingValues.datetimeFormatProblem(editor.text) !== "" ? "" : Qt.formatDateTime(Time.now, editor.text);
            const problem = editor === undefined ? "" : SettingValues.datetimeFormatProblem(editor.text);
            const problemText = problem === "" ? "" : SettingValues.PROBLEM_TEXT[problem];
            const labels = shown.filter(child => root.typeName(child) === "Label" && child.role === "hint");
            const preview = labels.find(child => formatted !== "" && child.text === formatted) || null;
            const error = labels.find(child => problemText !== "" && child.text === problemText) || null;
            if (name === "editFieldCustom") {
                if (editor === undefined) return "absent";
                editor.forceActiveFocus();
                editor.text = a.text;
                return "edited";
            }
            return root.json({
                visible: editor !== undefined,
                text: editor === undefined ? "" : editor.text,
                preview: preview === null ? "" : preview.text,
                formatted: formatted,
                previewBox: preview === null ? [0, 0, 0, 0] : root.windowBox(preview),
                error: problemText !== "" ? problemText : error === null ? "" : error.text
            });
        }
        if (name === "fieldPresetPreviews") {
            const a = JSON.parse(arg);
            const field = fieldOf(item, a.id, a.key);
            if (field === null) return "absent";
            const editor = descendants(field).find(child => typeName(child) === "Select");
            if (editor === undefined) return "no-select";
            const row = item.plugins.find(plugin => plugin.id === a.id);
            if (row === undefined) return "no-plugin";
            const spec = row.schema[a.key];
            const out = [];
            for (let i = 0; i < spec.presets.length; i++) {
                const want = Qt.formatDateTime(Time.now, spec.presets[i].value);
                if (editor.model[i].label !== want) out.push(spec.presets[i].value + "=" + editor.model[i].label + " want=" + want);
            }
            return root.json(out);
        }
        if (name === "openPluginByPointer") {
            // The Settings window's page for plugin ARG, opened as a click
            // opens it, so no keyboard focus ring or tooltip shows. The
            // window takes the focus first: a back button that holds it
            // from a page opened by keys keeps that reason otherwise.
            item.forceActiveFocus(Qt.MouseFocusReason);
            return item.openPlugin(arg, Qt.MouseFocusReason);
        }
        if (name === "focusInstance") {
            // The instance's root takes the keyboard focus as a click on
            // its blank area gives it, so no control draws its focus ring.
            item.forceActiveFocus(Qt.MouseFocusReason);
            for (const child of root.descendants(item))
                if (child !== item && child.focus === true) child.focus = false;
            return item.activeFocus ? "focused" : "unfocused";
        }
        if (name === "listItems" || name === "listAdd" || name === "listRemove" || name === "listApply") {
            // A drawn `list` field of the Settings page (ListField):
            // `listItems` reads each drawn item's name and its fields'
            // shown values, `listAdd` and `listRemove` click its Add and an
            // item's Remove action, and `listApply` sends one item field's
            // drawn editor a value as the editor does.
            const a = JSON.parse(arg);
            const list = descendants(item).find(child => child.pluginId === a.id && child.key === a.key && typeof child.add === "function");
            if (list === undefined) return "absent";
            const groups = descendants(list).filter(child => child.modelData !== undefined && child.modelData !== null && typeof child.modelData === "object" && typeof child.modelData.name === "string" && child.index !== undefined);
            const editors = group => descendants(group).filter(child => typeName(child) === "SettingField");
            const button = (within, text) => descendants(within).find(child => typeName(child) === "RowAction" && child.text === text);
            if (name === "listItems")
                return root.json(groups.map(group => {
                    const out = { name: group.modelData.name };
                    for (const editor of editors(group)) out[editor.key] = editor.value;
                    return out;
                }));
            if (name === "listAdd") {
                const add = button(list, "Add");
                if (add === undefined || !add.enabled) return "no-add";
                add.clicked();
                return "clicked";
            }
            const group = groups.find(g => g.modelData.name === a.name);
            if (group === undefined) return "no-item";
            if (name === "listRemove") {
                const remove = button(group, "Remove");
                if (remove === undefined || !remove.enabled) return "no-remove";
                remove.clicked();
                return "clicked";
            }
            const editor = editors(group).find(e => e.key === a.field);
            if (editor === undefined) return "no-field";
            editor.apply(a.value);
            return "applied";
        }
        if (name === "fieldGeometry") {
            const a = JSON.parse(arg);
            return root.geometry(fieldOf(item, a.id, a.key));
        }
        if (name === "applyKey") {
            // A drawn Keys row's edit, as the row emits it: `key` absent
            // is a reset.
            const a = JSON.parse(arg);
            const row = descendants(item).find(child => child.pluginId === a.id && child.bind !== undefined && child.bind.shortcut === a.shortcut && typeof child.applyKey === "function");
            if (row === undefined) return "absent";
            row.applyKey("key" in a ? a.key : undefined);
            return "applied";
        }
        if (name === "keyField" || name === "focusKeyField" || name === "typeKeyField") {
            // A drawn Keys row's ShortcutField: `keyField` reads it,
            // `focusKeyField` gives it the keyboard focus as a Tab does, and
            // `typeKeyField` opens its text entry as its keyboard button
            // does.
            const a = JSON.parse(arg);
            const row = descendants(item).find(child => child.pluginId === a.id && child.bind !== undefined && child.bind.shortcut === a.shortcut && typeof child.applyKey === "function");
            if (row === undefined) return "absent";
            const field = descendants(row).find(child => typeName(child) === "ShortcutField");
            if (field === undefined) return "no-field";
            const box = descendants(field).find(child => typeName(child) === "QQuickAbstractButton");
            if (box === undefined) return "no-box";
            if (name === "focusKeyField") {
                field.forceActiveFocus(Qt.TabFocusReason);
                return box.activeFocus ? "focused" : "unfocused";
            }
            if (name === "typeKeyField") {
                field.startTyping();
                return field.typing ? "typing" : "not-typing";
            }
            return root.json({ key: field.key, capturing: field.capturing, typing: field.typing, caps: field.caps,
                conflict: field.conflict, notice: field.notice, hint: field.hint, focus: box.activeFocus, visualFocus: box.visualFocus });
        }
        if (name === "applyField" || name === "holdField") {
            const a = JSON.parse(arg);
            const field = fieldOf(item, a.id, a.key);
            if (field === null) return "absent";
            if (name === "applyField") { field.apply(a.value); return "applied"; }
            const editor = descendants(field).find(child => child instanceof TextInput);
            if (editor === undefined) return "absent";
            editor.forceActiveFocus();
            editor.text = a.text;
            editor.cursorPosition = 1;
            heldField = { id: a.id, key: a.key, field: field };
            heldEditor = editor;
            return root.json(windowBox(editor));
        }
        if (name === "heldFieldState") {
            if (heldField === null || heldEditor === null) return "absent";
            return root.json({ same: fieldOf(item, heldField.id, heldField.key) === heldField.field,
                focus: heldEditor.focus, activeFocus: heldEditor.activeFocus,
                text: heldEditor.text, cursor: heldEditor.cursorPosition });
        }
        if (typeof item[name] !== "function") return "no-function";
        const result = item[name](arg);
        return result === undefined ? "" : IpcPages.answer(String(result));
    }

    // A token's QML value as JSON.
    function themeValue(path) {
        let node = Theme;
        for (const key of path.split(".")) {
            if (node === undefined || node === null) return "absent";
            node = node[key];
        }
        return node === undefined ? "absent" : root.json(node);
    }

    // Write into a published group the way a careless plugin would; answers
    // the value read back after the write, so the row proves nothing moved.
    function themeWrite(path, value) {
        const keys = path.split(".");
        let node = Theme;
        for (const key of keys.slice(0, -1)) node = node[key];
        try { node[keys[keys.length - 1]] = value; } catch (e) {}
        return themeValue(path);
    }

    IpcHandler {
        target: "smoke"
        function pageChars(): int { return IpcPages.replyChars; }
        // The shell process's value of an environment variable after its
        // pragmas, "" when unset: Quickshell.env reads the process
        // environment, which an Env pragma sets before the engine starts.
        function environment(name: string): string { return Quickshell.env(name) ?? ""; }
        // Every top-level group of the token table that Theme does not
        // publish as a frozen object, so an empty list is the pass.
        function themeUnpublished(): string {
            return root.json(Object.keys(Tokens.TOKENS).filter(group => typeof Theme[group] !== "object" || Theme[group] === null || !Object.isFrozen(Theme[group])));
        }
        function themeValue(path: string): string { return root.themeValue(path); }
        // Each surface the layer host built for a plugin, sorted by screen:
        // [screen, takes no keyboard, on the overlay layer, clear of
        // reserved space].
        function layerSurfaces(id: string): string {
            const out = [];
            for (const entry of Layers.entries.filter(e => e.pluginId === id))
                for (const name of Object.keys(entry.screens).sort()) {
                    const win = entry.screens[name].QsWindow.window;
                    out.push([name, win.WlrLayershell.keyboardFocus === WlrKeyboardFocus.None, win.WlrLayershell.layer === WlrLayer.Overlay, win.exclusionMode === ExclusionMode.Normal]);
                }
            return root.json(out);
        }
        function layerWindows(id: string): string {
            const out = [];
            for (const entry of Layers.entries.filter(e => e.pluginId === id))
                for (const name of Object.keys(entry.screens).sort()) {
                    const item = entry.screens[name];
                    const win = item.QsWindow.window;
                    out.push({ screen: name, shown: item.shown, visible: win !== null && win.visible,
                        presented: win !== null && win.presented, width: win === null ? 0 : win.width,
                        height: win === null ? 0 : win.height });
                }
            return root.json(out);
        }
        function layerWindowRemember(id: string): string {
            const entries = Layers.entries.filter(e => e.pluginId === id);
            if (entries.length !== 1) return "registrations=" + entries.length;
            const entry = entries[0];
            root.rememberedLayers = Object.keys(entry.screens).map(name =>
                ({ serial: entry.serial, name: name, window: entry.screens[name].QsWindow.window }));
            return "ok";
        }
        function layerWindowForget(): string { root.rememberedLayers = []; return "ok"; }
        // Plant lost map, screen or presentation in the owned sandbox host.
        // Disable/redraw restores its original bindings.
        function layerWindowSet(id: string, property: string, value: bool): string {
            const entries = Layers.entries.filter(e => e.pluginId === id);
            if (entries.length !== 1) return "registrations=" + entries.length;
            for (const name of Object.keys(entries[0].screens)) {
                let win = entries[0].screens[name].QsWindow.window;
                if (win === null) {
                    const remembered = root.rememberedLayers.find(row => row.serial === entries[0].serial && row.name === name);
                    if (remembered !== undefined) win = remembered.window;
                }
                if (win === null) return "no-window";
                if (property === "screen") win.targetScreen = null;
                else if (property === "visible") win.visible = value;
                else if (property === "framePresented") win.framePresented = value;
                else return "refused: property";
            }
            return "ok";
        }
        function layerShaderSet(id: string, visible: bool): string {
            const item = root.layerItem(id, "VoiceOrb", "active", "true");
            if (item === null) return "absent";
            const shader = root.descendants(item).find(child => child.fragmentShader !== undefined);
            if (shader === undefined) return "missing-shader";
            shader.visible = visible;
            return "ok";
        }
        // A missing LayerHost inputItems binding, planted only in the
        // sandbox instance. A redraw restores the shipped binding.
        function layerInputDrop(id: string): string {
            const entries = Layers.entries.filter(e => e.pluginId === id);
            if (entries.length !== 1) return "registrations=" + entries.length;
            for (const name of Object.keys(entries[0].screens))
                entries[0].screens[name].QsWindow.window.inputItems = [];
            return "ok";
        }
        // The box of the first visible, enabled item named `type` whose
        // `property` reads `value` in a plugin's layer copies, sorted by
        // screen, as [x, y, w, h] in its window, or "absent". A layer the
        // compositor places knows no position of its own, so a row adds the
        // layer's position from `hyprctl layers`.
        function layerItemGeometry(id: string, type: string, property: string, value: string): string {
            const found = root.layerItem(id, type, property, value);
            return found === null ? "absent" : root.json(root.windowBox(found));
        }
        // Whether that item reports the pointer over it: "true", "false",
        // or "absent" with no such item, as itemHovered answers for an
        // instance's item.
        function layerItemHovered(id: string, type: string, property: string, value: string): string {
            const found = root.layerItem(id, type, property, value);
            return found === null ? "absent" : String(found.hovered === true);
        }
        // Every item of a type in a plugin's layer copies, sorted by screen:
        // [screen, [x, y, width, height] in its window, { property: value }]
        // for each property named in the comma list.
        function layerItems(id: string, type: string, properties: string): string {
            const names = properties === "" ? [] : properties.split(",");
            const out = [];
            for (const entry of Layers.entries.filter(e => e.pluginId === id))
                for (const screen of Object.keys(entry.screens).sort())
                    for (const item of root.descendants(entry.screens[screen]).filter(i => root.typeName(i) === type)) {
                        const at = item.mapToGlobal(0, 0);
                        const values = {};
                        // A colour reads as its #aarrggbb name, not its channels.
                        for (const name of names) values[name] = item[name] !== null && typeof item[name] === "object" && "hslHue" in item[name] ? item[name].toString() : item[name];
                        out.push([screen, [Math.round(at.x), Math.round(at.y), Math.round(item.width), Math.round(item.height)], values]);
                    }
            return root.json(out);
        }
        // The count of visible items named TYPE whose PROPERTY text
        // contains NEEDLE, in a plugin's layer copies.
        function layerItemsWith(id: string, type: string, property: string, needle: string): int {
            let total = 0;
            for (const entry of Layers.entries.filter(e => e.pluginId === id))
                for (const screen of Object.keys(entry.screens).sort()) {
                    for (const item of root.descendants(entry.screens[screen]).filter(i => root.typeName(i) === type && i.visible))
                        if (String(item[property]).indexOf(needle) !== -1) total += 1;
                }
            return total;
        }
        // The count of visible text items whose text contains NEEDLE under
        // the items named SCOPE whose PROPERTY reads VALUE, in a plugin's
        // layer copies: one card's texts, not those of other cards the
        // layers still hold.
        function layerTextsWithin(id: string, scope: string, property: string, value: string, needle: string): int {
            let total = 0;
            for (const entry of Layers.entries.filter(e => e.pluginId === id))
                for (const screen of Object.keys(entry.screens).sort())
                    for (const holder of root.descendants(entry.screens[screen]).filter(i => root.typeName(i) === scope && String(i[property]) === value))
                        for (const item of root.descendants(holder).filter(i => i instanceof Text && i.visible))
                            if (item.text.indexOf(needle) !== -1) total += 1;
            return total;
        }
        // Saves the first item of a type in a plugin's layer copies whose
        // property reads the value to PATH as a PNG: the item and its
        // children as its window draws them, without the items under or
        // over it. Answers grabbing, absent, or refused when the item cannot
        // be grabbed now; grabbed() answers the outcome.
        function grabLayerItem(id: string, type: string, property: string, value: string, path: string): string {
            for (const entry of Layers.entries.filter(e => e.pluginId === id))
                for (const screen of Object.keys(entry.screens).sort())
                    for (const item of root.descendants(entry.screens[screen]).filter(i => root.typeName(i) === type && String(i[property]) === value)) {
                        root.grab = "pending " + path;
                        if (!item.grabToImage(result => root.grab = (result.saveToFile(path) ? "saved " : "unsaved ") + path)) {
                            root.grab = "";
                            return "refused";
                        }
                        return "grabbing";
                    }
            return "absent";
        }
        // pending, saved or unsaved, and the path, for the last grab.
        function grabbed(): string { return IpcPages.answer(root.grab); }
        // Every shader effect in a plugin's layer copies: [screen, its
        // fragment shader's URL, whether it compiled].
        function layerShaders(id: string): string {
            const out = [];
            for (const entry of Layers.entries.filter(e => e.pluginId === id))
                for (const screen of Object.keys(entry.screens).sort())
                    for (const item of root.descendants(entry.screens[screen]).filter(i => i instanceof ShaderEffect))
                        out.push([screen, String(item.fragmentShader), item.status === ShaderEffect.Compiled]);
            return root.json(out);
        }
        // A service's ListModel property as a list of rows, each the roles
        // named in the comma list.
        function modelRows(id: string, property: string, roles: string): string {
            const model = root.instance("service", id);
            if (model === null) return "absent";
            const list = model[property];
            const out = [];
            for (let i = 0; i < list.count; i++) {
                const row = list.get(i);
                out.push(roles.split(",").map(r => row[r]));
            }
            return root.json(out);
        }
        // The core notice dialog: whether an item in it holds the keyboard
        // focus, and what it draws as { title, message, rows, groups,
        // actions, busy }, `rows` the visible lines under the message and
        // `groups` each chip with the lines under it.
        function noticeFocused(): bool {
            const dialog = Plugins.hosts.notice === undefined ? null : Plugins.hosts.notice.dialog;
            return dialog !== null && root.descendants(dialog).some(child => child.activeFocus);
        }
        // The dialog's box, or its title's for `title`, in the notice
        // window's coordinates, or "absent" while no notice shows.
        function noticeWindowGeometry(part: string): string {
            const dialog = Plugins.hosts.notice === undefined ? null : Plugins.hosts.notice.dialog;
            if (dialog === null) return "absent";
            if (part === "card") return root.json(root.windowBox(dialog));
            if (part !== "title") return "refused: part=" + part + " want=card|title";
            const title = root.descendants(dialog).find(child => root.typeName(child) === "Label" && child.visible && child.text === dialog.title);
            return title === undefined ? "absent" : root.json(root.windowBox(title));
        }
        // The dialog's height, its window's, and how many of its shown
        // scroll areas overflow, or "absent" while no notice shows.
        function noticeFit(): string {
            const dialog = Plugins.hosts.notice === undefined ? null : Plugins.hosts.notice.dialog;
            if (dialog === null) return "absent";
            let top = dialog;
            while (top.parent !== null) top = top.parent;
            return root.json({ dialog: dialog.height, surface: top.height, overflowing: root.shownScrollAreas(dialog).filter(area => area.overflowing).length });
        }
        function noticeDrawn(): string {
            const dialog = Plugins.hosts.notice === undefined ? null : Plugins.hosts.notice.dialog;
            if (dialog === null) return "absent";
            const linkTexts = root.descendants(dialog).filter(child => root.typeName(child) === "LinkText" && child.visible);
            const inLinkText = item => {
                for (let p = item.parent; p !== null; p = p.parent)
                    if (linkTexts.indexOf(p) !== -1) return true;
                return false;
            };
            const keyCaps = root.descendants(dialog).filter(child => root.typeName(child) === "KeyCaps" && child.visible);
            const keyTitle = root.descendants(dialog).find(child => root.typeName(child) === "Label" && child.visible && child.role === "eyebrow");
            const hasAncestor = (item, type) => {
                for (let p = item.parent; p !== null; p = p.parent)
                    if (root.typeName(p) === type) return true;
                return false;
            };
            const inKeyRow = item => (item.parent !== null && root.descendants(item.parent).some(child => root.typeName(child) === "KeyCaps")) || hasAncestor(item, "KeyCaps") || hasAncestor(item, "Kbd");
            const labels = root.descendants(dialog).filter(child => root.typeName(child) === "Label" && child.visible && !inLinkText(child) && !inKeyRow(child) && child.role !== "eyebrow");
            const keyRows = keyCaps.map(cap => {
                const label = root.descendants(cap.parent).find(child => root.typeName(child) === "Label" && child.visible);
                return { shortcut: cap.shortcut, text: label === undefined ? "" : label.text };
            });
            // A requirement notice's entries: each chip's text, then the
            // lines drawn under it in its block.
            const groups = root.descendants(dialog).filter(child => root.typeName(child) === "Badge" && child.visible).map(badge => {
                const inBadge = root.descendants(badge);
                const lines = root.descendants(badge.parent).filter(child => root.typeName(child) === "Label" && child.visible && inBadge.indexOf(child) === -1);
                return [badge.text, lines.map(line => line.text)];
            });
            return root.json({
                title: dialog.title,
                message: dialog.message,
                rows: linkTexts.map(link => link.text).concat(labels.map(label => label.text)).filter(text => text !== dialog.title && text !== dialog.message && !dialog.entries.some(entry => entry.label === text)),
                groups: groups,
                keysTitle: keyTitle === undefined ? "" : keyTitle.text,
                keys: keyRows,
                // The button that holds the keyboard, by its text or label.
                focused: (() => {
                    const held = root.descendants(dialog).find(child => child.activeFocus === true && ["Button", "IconButton"].includes(root.typeName(child)));
                    if (held !== undefined) return held.text || held.label;
                    const linked = root.descendants(dialog).find(child => child.activeFocus === true && root.typeName(child) === "LinkText");
                    return linked === undefined ? null : "link:" + linked.link;
                })(),
                actions: dialog.entries.map(entry => entry.label),
                busy: dialog.busy
            });
        }
        // The components of qs.Ui, read from its qmldir, that the gallery
        // draws no instance of; an empty list is the pass. A QML-defined
        // type prints as `<Name>_QMLTYPE_<n>(...)`. PointerCursor is a
        // pointer handler, which no item list holds; every gallery control
        // declares one. ListEntrance is a transform, read from each item's
        // `transform` list.
        function galleryMissing(hostKey: string, id: string): string {
            const item = root.instance(hostKey, id);
            if (item === null || item.examples === undefined) return "absent";
            const names = [];
            for (const line of uiModule.text().split("\n")) {
                const m = /^(\w+) 1\.0 (\S+)$/.exec(line);
                if (m !== null && m[1] !== "BarWidget" && m[1] !== "PointerCursor" && !m[2].endsWith(".js")) names.push(m[1]);
            }
            if (names.length < 20) return "qmldir-read-broken=" + names.length;
            const seen = {};
            for (const child of root.descendants(item.examples))
                for (const drawn of [child].concat(Array.from(child.transform || []))) {
                    const m = /^(\w+)_QMLTYPE_/.exec(String(drawn));
                    if (m !== null) seen[m[1]] = true;
                }
            return root.json(names.filter(name => !seen[name]));
        }
        // Focus examples that the Gallery promises. Most controls must draw
        // through focusPreview, while composite controls use their own
        // selected item or modal setting as the focus contract.
        function galleryFocusMissingAt(copyName: string, hostKey: string, id: string): string {
                const item = copyName === "" ? root.instance(hostKey, id) : root.popupCopies[copyName];
                if (item === null || item === undefined || item.examples === undefined) return "absent";
                const required = [
                    "Button primary", "Button secondary", "Button tertiary", "Button ghost", "Button danger",
                    "IconButton", "ToggleButton", "BarItem", "Switch", "Checkbox", "Radio",
                    "SegmentedControl", "TileGroup", "Select", "TextField", "ShortcutField", "Slider", "TitleButton", "RowAction",
                    "Tabs", "Disclosure", "DeviceRow", "Dialog accept action", "CardCarousel", "KeyCaps", "KeyNav list"
                ];
                const previewRequired = {
                    "Button primary": true, "Button secondary": true, "Button tertiary": true, "Button ghost": true, "Button danger": true,
                    "IconButton": true, "ToggleButton": true, "BarItem": true, "Switch": true, "Checkbox": true, "Radio": true,
                    "SegmentedControl": true, "TileGroup": true, "Select": true, "TextField": true, "ShortcutField": true, "Slider": true, "TitleButton": true, "RowAction": true
                };
                const found = {};
                for (const child of root.descendants(item.examples)) {
                    try {
                        if (child.focusExample === undefined || child.focusExample === "") continue;
                        found[String(child.focusExample)] = child;
                    } catch (e) {}
                }
                const missing = [];
                for (const name of required) {
                    const child = found[name];
                    if (child === undefined) {
                        missing.push(name + ":absent");
                        continue;
                    }
                    if (previewRequired[name] === true && child.focusPreview !== true) missing.push(name + ":focusPreview");
                    else if (name === "Dialog accept action" && child.modal !== false) missing.push(name + ":modal");
                    else if (name === "CardCarousel" && child.tabSteps !== false) missing.push(name + ":tabSteps");
                    else if (name === "KeyNav list" && child.activeFocusOnTab !== true) missing.push(name + ":tabStop");
                }
                return root.json(missing);
        }
        function galleryFocusMissing(hostKey: string, id: string): string {
                return galleryFocusMissingAt("", hostKey, id);
        }
        function galleryFocusMissingCopy(name: string): string {
                return galleryFocusMissingAt(name, "", "");
        }
        // Examples drawn past the gallery's right edge, so a row that does
        // not wrap to the panel names itself; an empty list is the pass.
        function galleryOverflow(hostKey: string, id: string): string {
            const item = root.instance(hostKey, id);
            if (item === null || item.examples === undefined) return "absent";
            const out = [];
            for (const child of root.descendants(item.examples)) {
                if (!child.visible || child.width === undefined || child.width === 0) continue;
                if (root.typeName(child) === "QQuickItem") continue;
                const right = child.mapToItem(item, child.width, 0).x;
                if (right > item.width + 1) out.push(String(child).split("(")[0] + ":" + Math.round(right));
            }
            return root.json(out);
        }
        // Scrolls the one shown ScrollArea under an instance to `y`, held
        // inside its content, so scripts/sandbox-shots.sh captures each
        // page of a scrolling panel. Answers [contentY, contentHeight,
        // height], or shown-scroll-areas=N when the target is ambiguous.
        // Scrolls the shown ScrollArea holding the first shown, enabled
        // item named `type` that reads `text` (reads) under an instance so
        // the item sits a third of the way down its view, for a real click
        // on a control below the fold. Answers the new contentY, `absent`
        // for no such item, or `unscrolled` for one no shown area holds.
        function revealText(hostKey: string, id: string, type: string, text: string): string {
            const item = root.instance(hostKey, id);
            if (item === null) return "absent";
            const target = root.descendants(item).find(child => root.typeName(child) === type && root.reads(child, text) && child.visible && child.enabled);
            return root.revealIn(item, target === undefined ? null : target);
        }
        // revealText for the item scopedItem finds, such as one row's
        // control among rows that each draw one with the same text.
        function revealScopedText(hostKey: string, id: string, scopeType: string, scopeText: string, type: string, text: string): string {
            return root.revealIn(root.instance(hostKey, id), root.scopedItem(hostKey, id, scopeType, scopeText, type, text));
        }
        // The first shown Section titled `title` under an instance, as
        // [top, bottom, contentY, height]: its span in its one shown scroll
        // area's content and that area's scroll and height, for a reader
        // that brings the whole section into view through scrollTo;
        // "absent" without such a section or scroll area.
        function sectionSpan(hostKey: string, id: string, title: string): string {
            const item = root.instance(hostKey, id);
            if (item === null) return "absent";
            const section = root.descendants(item).find(child => root.typeName(child) === "Section" && child.visible && child.title === title);
            const areas = root.shownScrollAreas(item);
            if (section === undefined || areas.length !== 1) return "absent";
            const flick = areas[0];
            const top = section.mapToItem(flick.contentItem, 0, 0).y;
            return root.json([top, top + section.height, flick.contentY, flick.height]);
        }
        function scrollTo(hostKey: string, id: string, y: int): string {
            const item = root.instance(hostKey, id);
            if (item === null) return "absent";
            const areas = root.shownScrollAreas(item);
            if (areas.length !== 1) return "shown-scroll-areas=" + areas.length;
            const flick = areas[0];
            flick.contentY = Math.max(0, Math.min(y, flick.contentHeight - flick.height));
            return root.json([flick.contentY, flick.contentHeight, flick.height]);
        }
        function galleryHeadings(hostKey: string, id: string): string {
            const item = root.instance(hostKey, id);
            if (item === null || item.examples === undefined) return "absent";
            const drawn = root.descendants(item.examples).filter(child => /^SectionHeader_QMLTYPE_/.test(String(child)) && child.width > 0 && child.height > 0);
            return String(drawn.length);
        }
        // Use the component's reveal path to bring the whole orb into view.
        function revealVoiceOrb(hostKey: string, id: string, index: int): string {
            const item = root.instance(hostKey, id);
            if (item === null) return "absent";
            const orbs = root.descendants(item).filter(child => root.typeName(child) === "VoiceOrb");
            if (index < 0 || index >= orbs.length) return "absent";
            const viewport = root.scrollAreaHolding(item, orbs[index]);
            if (viewport === undefined) return "unscrolled";
            viewport.reveal(orbs[index]);
            return String(viewport.contentY);
        }
        // VoiceOrb examples and their actual shader status. A disposable
        // popup copy supplies the uncompiled control without a shipped hook.
        function galleryOrbs(hostKey: string, id: string, copyName: string): string {
            const item = copyName === "" ? root.instance(hostKey, id) : root.popupCopies[copyName];
            if (item === null || item === undefined) return "absent";
            const orbs = copyName === "" ? root.descendants(item).filter(child => root.typeName(child) === "VoiceOrb") : [item];
            const title = root.descendants(item).find(child => root.typeName(child) === "Label" && child.text === "VGS Components");
            const viewport = root.shownScrollAreas(item)[0];
            let clip = viewport === undefined ? null : viewport.contentItem.parent;
            while (clip !== null && !clip.clip) clip = clip.parent;
            const clipPoint = clip === null ? null : clip.mapToItem(viewport, 0, 0);
            return root.json(orbs.map(orb => {
                const shader = root.descendants(orb).find(child => child instanceof ShaderEffect);
                const point = orb.mapToGlobal(0, 0);
                const viewPoint = viewport === undefined ? null : orb.mapToItem(viewport, 0, 0);
                const window = orb.Window.window;
                return {
                    tone: orb.tone, active: orb.active, level: orb.level, secondaryLevel: orb.secondaryLevel,
                    width: orb.width, height: orb.height,
                    box: root.windowBox(orb),
                    ink: ThemeLogic.formatColor(Qt.color(Theme.voiceOrb.tone[orb.tone])),
                    scrollOffset: title === undefined ? null : Math.round(orb.mapToGlobal(0, 0).y - title.mapToGlobal(0, 0).y),
                    url: shader === undefined ? "" : String(shader.fragmentShader),
                    shaderLog: shader === undefined ? "no-shader" : shader.log,
                    shaderStatus: shader === undefined ? null : shader.status,
                    visible: orb.visible, shaderVisible: shader !== undefined && shader.visible,
                    windowVisible: window !== null && window.visible,
                    windowVisibility: window === null ? null : window.visibility,
                    global: [point.x, point.y],
                    viewportPosition: viewPoint === null ? null : [viewPoint.x, viewPoint.y],
                    viewport: viewport === undefined ? null : {
                        contentY: viewport.contentY, originY: viewport.originY,
                        contentHeight: viewport.contentHeight, width: viewport.width, height: viewport.height,
                        clip: clipPoint === null ? null : [clipPoint.x, clipPoint.y, clip.width, clip.height]
                    },
                    compiled: shader !== undefined && shader.status === ShaderEffect.Compiled
                };
            }));
        }
        // ImageText items under an instance or popup copy. Each held image
        // names the pool URL, load status and sourceSize in device pixels.
        function imageTextItems(hostKey: string, id: string, copyName: string): string {
            const item = copyName === "" ? root.instance(hostKey, id) : root.popupCopies[copyName];
            if (item === null || item === undefined) return "absent";
            const statusName = status => status === Image.Null ? "Null" : status === Image.Ready ? "Ready" : status === Image.Loading ? "Loading" : status === Image.Error ? "Error" : String(status);
            return root.json(root.descendants(item).filter(child => root.typeName(child) === "ImageText").map(text => {
                const held = [];
                for (const url of Object.keys(text.held)) {
                    const image = text.held[url];
                    held.push({
                        url: url,
                        status: statusName(image.status),
                        source: String(image.source),
                        sourceSize: [image.sourceSize.width, image.sourceSize.height]
                    });
                }
                const point = text.mapToGlobal(0, 0);
                const window = text.Window.window;
                return {
                    box: root.windowBox(text),
                    global: [point.x, point.y],
                    imageMode: text.imageMode,
                    failed: text.failed,
                    imageSize: text.imageSize,
                    deviceSize: text.deviceSize,
                    held: held,
                    visible: text.visible,
                    windowVisible: window !== null && window.visible
                };
            }));
        }
        // Bring the indexed ImageText item under an instance into view.
        function revealImageText(hostKey: string, id: string, index: int): string {
            const item = root.instance(hostKey, id);
            if (item === null) return "absent";
            const texts = root.descendants(item).filter(child => root.typeName(child) === "ImageText");
            return index < 0 || index >= texts.length ? "absent" : root.revealIn(item, texts[index]);
        }
        // A colour one gallery example draws with, read as a property: the
        // first shown item named `type` in the section under the SectionHeader
        // reading `section`, through `property`, a dotted path. Written as
        // ThemeLogic writes a resolved colour, `#rrggbbaa`, so a row compares
        // it with the package's token without reading a frame.
        function galleryColour(hostKey: string, id: string, section: string, type: string, property: string): string {
            const item = root.instance(hostKey, id);
            if (item === null || item.examples === undefined) return "absent";
            const typeOf = child => String(child).split("_QMLTYPE_")[0];
            const header = root.descendants(item.examples).find(child => typeOf(child) === "SectionHeader" && child.text === section);
            if (header === undefined) return "no-section";
            const siblings = header.parent.children;
            let at = 0;
            while (siblings[at] !== header) at++;
            for (at++; at < siblings.length && typeOf(siblings[at]) !== "SectionHeader"; at++) {
                const example = root.descendants(siblings[at]).find(child => typeOf(child) === type && root.visibleInTree(child));
                if (example === undefined) continue;
                let value = example;
                for (const key of property.split(".")) value = value === null || value === undefined ? undefined : value[key];
                if (value === null || value === undefined || typeof value.a !== "number") return "not-colour";
                return IpcPages.answer(ThemeLogic.formatColor(value));
            }
            return "no-example";
        }
        function themeWrite(path: string, value: string): string { return root.themeWrite(path, value); }
        function themeName(): string { return IpcPages.answer(Theme.name); }
        function themeRevision(): int { return Theme.revision; }
        function fontAvailable(family: string): bool { return Qt.fontFamilies().indexOf(family) !== -1; }
        function buildCount(): int { return root.builds; }
        function frames(): int { return root.frames; }
        function holdMarkerCount(): int { return root.holdMarkers; }
        function holdMarkerStart(): string {
            if (root.holdMarker !== null) return "held";
            root.holdMarkers = 0;
            root.holdMarker = holdMarkerComponent.createObject(root);
            return root.holdMarker === null ? "error: marker-create" : "ok";
        }
        function holdMarkerStop(): string {
            if (root.holdMarker === null) return "absent";
            root.holdMarker.destroy();
            root.holdMarker = null;
            return "ok";
        }
        // Observe only the selected layer's own QQuickWindow, not any bar.
        function watchLayerFrames(id: string): string {
            const entry = Layers.entries.find(e => e.pluginId === id);
            if (entry === undefined) return "absent";
            const surface = entry.screens[Object.keys(entry.screens).sort()[0]];
            if (surface === undefined) return "no-screen";
            root.layerFrameSurface = surface.QsWindow.window;
            root.layerFrames = 0;
            return root.layerFrameSurface.contentItem.Window.window === null ? "no-window" : "ok";
        }
        function layerFrames(): string {
            return root.layerFrameSurface === null ? "absent" : String(root.layerFrames);
        }
        function layerFrameListening(listen: bool): string {
            root.layerFrameListening = listen;
            return "ok";
        }
        function layerFrameVisible(show: bool): string {
            if (root.layerFrameSurface === null) return "absent";
            root.layerFrameSurface.visible = show;
            return "ok";
        }
        // A driver mutant draws in the same real layer as the fixture.
        // popupDrop owns it with the other disposable object copies.
        function layerOrbLoad(name: string, file: string): string {
            if (name in root.popupCopies) return "loaded";
            if (root.layerFrameSurface === null) return "absent";
            const component = Qt.createComponent("file://" + file);
            if (component.status !== Component.Ready) return "error: " + component.errorString();
            const made = component.createObject(root.layerFrameSurface.contentItem, { active: true, level: 0.8 });
            if (made === null) return "error: create";
            const next = Object.assign({}, root.popupCopies);
            next[name] = made;
            root.popupCopies = next;
            return "ok";
        }
        function dropLayerFrames(): string {
            root.layerFrameSurface = null;
            return "ok";
        }
        function startOrder(): string { return root.json(root.startOrder); }
        // A detached process the shell starts that runs until GATE exists,
        // for SECONDS at most, so it can outlive the shell and never the
        // row. It stands in for a long child of the shell, such as a
        // download, in rows/start-order.sh's instance lock readings: it
        // inherits the shell's descriptors, and holds the instance lock
        // only under a runner that hands the shell the lock's descriptor.
        function holdUntil(gate: string, seconds: int): string {
            Quickshell.execDetached(["timeout", String(seconds), "sh", "-c", 'until [ -e "$1" ]; do sleep 0.05; done', "sh", gate]);
            return "ok";
        }
        function configChanges(): int { return root.changes; }
        function configUserLoads(): int { return root.userLoads; }
        function failedBuilds(hostKey: string): int {
            return Object.keys(Plugins.failedBuilds).filter(key => JSON.parse(key)[0] === hostKey).length;
        }
        function configSettled(): bool { return !Config.smokeUserView.busy; }
        function readInstance(hostKey: string, id: string, property: string): string { return root.read(hostKey, id, property); }
        function rememberBarWidgets(hostKey: string): string {
            const rows = Plugins.built[hostKey];
            if (!rows) return "absent";
            root.rememberedBarHost = hostKey;
            root.rememberedBarWidgets = rows.filter(row => row.origin === "plugin" || row.kind === "bar-widget")
                .map(row => ({ id: row.id, item: row.instance }));
            return root.json(root.rememberedBarWidgets.map(row => row.id).sort());
        }
        function barWidgetIdentities(): string {
            const rows = Plugins.built[root.rememberedBarHost];
            if (!rows || root.rememberedBarWidgets.length === 0) return "absent";
            return root.json(root.rememberedBarWidgets.filter(saved => !rows.some(row => row.instance === saved.item))
                .map(saved => saved.id).sort());
        }
        function forgetBarWidgets(): string {
            root.rememberedBarWidgets = [];
            root.rememberedBarHost = "";
            return "ok";
        }
        function barDragGeometry(hostKey: string): string {
            const drag = Plugins.barDrag;
            if (drag === null || drag.hostKey !== hostKey) return "absent";
            const bar = Plugins.mounts[hostKey].row.instance;
            return root.json({ section: drag.section, index: drag.index,
                item: root.windowBox(drag.item), gap: root.windowBox(drag.gap),
                target: root.windowBox(bar[drag.section + "Section"]) });
        }

        function shotChrome(clear: bool): string { return root.chromeWord(clear); }
        // The core's session lock, taken and released without a password,
        // for rows/lock.sh: a sandbox row never runs PAM against the real
        // account (docs/decisions/D062-native-lock-and-polkit-plugins.md). The bare
        // lock takes the session over with no lock screen, as after a lock
        // client died, so the release can follow.
        function sessionUnlock(): string { return Capabilities.sessionLock.unlock(); }
        function sessionLockBare(): string { Capabilities.sessionLock.lockRequested = true; return "ok"; }
        // Each lock screen the lock plugin ID reports in its service's
        // `views`: its surface's size and the box, in that surface's
        // coordinates, of each descendant that carries an object name.
        function lockScreens(id: string): string {
            const service = root.instance("service", id);
            if (service === null) return "absent";
            if (!Array.isArray(service.views)) return "no-views";
            return root.json(service.views.filter(view => view !== null).map(view => {
                const parts = {};
                for (const child of root.descendants(view))
                    if (child.objectName !== "") parts[child.objectName] = root.windowBox(child);
                return { width: view.width, height: view.height, parts: parts };
            }));
        }
        // A plugin's published status values, as each of its instances reads them.
        function statusValues(id: string): string { return JSON.stringify(PluginStatus.valuesOf(id)); }
        // Sandbox-only scanner and masked-field observations. Never read a PSK.
        function networkScan(): string {
            const service = root.instance("service", "vgs.network");
            if (service === null) return "absent";
            const device = service.scannerDevice;
            return root.json({ leases: service.leaseCount, device: device === null ? null : device.name,
                scanning: service.wifiDevice === null ? false : service.wifiDevice.scannerEnabled });
        }
        function networkRememberDevice(): string {
            const service = root.instance("service", "vgs.network");
            if (service === null) return "absent";
            root.rememberedNetworkDevice = service.wifiDevice;
            return "ok";
        }
        function networkRememberedScanning(): bool {
            return root.rememberedNetworkDevice !== null && root.rememberedNetworkDevice.scannerEnabled;
        }
        function networkWatchdog(fast: bool): string {
            const service = root.instance("service", "vgs.network");
            if (service === null) return "absent";
            const timer = Array.from(service.resources).find(resource => resource.objectName === "network-operation-watchdog");
            if (timer === undefined) return "no-timer";
            if (fast) { timer.interval = 60; return "ok"; }
            return root.json({ running: timer.running, bounded: timer.interval > 0 && timer.interval <= service.transitionTimeout });
        }
        function networkBackgroundFailure(unrelated: bool): string {
            const service = root.instance("service", "vgs.network");
            if (service === null || service.wifiObjects.length === 0) return "absent";
            const network = unrelated ? { name: "Other", device: { name: "wlan0" }, known: true } : service.wifiObjects[0];
            service.failed(network, service.failureVariants.NoSecrets);
            return "ok";
        }
        function networkPermissionsTool(present: bool): string {
            const service = root.instance("service", "vgs.network");
            if (service === null) return "absent";
            if (present && root.networkOriginalShell !== null) {
                service.shell = root.networkOriginalShell;
                root.networkOriginalShell = null;
            } else if (!present && root.networkOriginalShell === null) {
                root.networkOriginalShell = service.shell;
                service.shell = Object.assign({}, service.shell, { requirements: { missing: ["nmcli"], revision: service.shell.requirements.revision } });
            }
            return "ok";
        }
        function networkPermissionNotice(hostKey: string): string {
            const item = root.instance(hostKey, "vgs.network");
            if (item === null) return "absent";
            const notice = root.descendants(item).find(child => child.objectName === "network-permission-notice");
            if (notice === undefined) return "no-notice";
            let shown = true;
            for (let at = notice; at !== null && at !== item; at = at.parent) if (!at.visible) shown = false;
            return root.json({ visible: shown, text: notice.text });
        }
        function networkDetails(hostKey: string): string {
            const item = root.instance(hostKey, "vgs.network");
            if (item === null) return "absent";
            const section = root.descendants(item).find(child => child.objectName === "network-details");
            if (section === undefined) return "no-section";
            let shown = true;
            for (let at = section; at !== null && at !== item; at = at.parent) if (!at.visible) shown = false;
            const rows = root.descendants(section).filter(child => root.typeName(child) === "Field").map(field => [field.label, Array.from(field.control).map(child => child.text).join("")]);
            return root.json({ visible: shown, rows: rows });
        }
        function networkField(hostKey: string): string {
            const item = root.instance(hostKey, "vgs.network");
            if (item === null) return "absent";
            const field = root.descendants(item).find(child => child.objectName === "network-password");
            if (field === undefined) return "no-field";
            return root.json({ masked: field.password, length: field.text.length, focused: field.activeFocus });
        }
        // The QR matrix is secret-derived. Report geometry and owner lifetime,
        // never matrix data or collector output through the smoke IPC.
        function networkShare(hostKey: string): string {
            const item = root.instance(hostKey, "vgs.network");
            if (item === null) return "absent";
            const view = root.descendants(item).find(child => child.objectName === "network-share-view");
            if (view === undefined) return "closed";
            const matrix = root.descendants(view).find(child => child.objectName === "network-share-matrix");
            return root.json({ state: view.shareState.kind, side: matrix.side, moduleSize: matrix.moduleSize,
                visible: matrix.visible });
        }
        function networkRememberShare(hostKey: string): string {
            const item = root.instance(hostKey, "vgs.network");
            if (item === null) return "absent";
            const view = root.descendants(item).find(child => child.objectName === "network-share-view");
            if (view === undefined) return "closed";
            root.rememberedNetworkShare = view;
            return "ok";
        }
        function networkRememberedShareAlive(): bool { return root.rememberedNetworkShare !== null; }
        function jarvisProcess(): string {
            const service = root.instance("service", "vgs.jarvis");
            if (service === null) return "absent";
            const process = Array.from(service.resources).find(resource => resource.processId !== undefined);
            if (process === undefined) return "missing";
            return JSON.stringify({ pid: process.processId, lifetime: service.lifetime, retries: service.retries,
                cause: service.cause, audioHealth: service.audioHealth, status: service.shell.status.values });
        }
        function instanceGeometry(hostKey: string, id: string): string { return root.geometry(root.instance(hostKey, id)); }
        function barSectionGeometry(hostKey: string, section: string): string {
            if (PluginLogic.SECTIONS.indexOf(section) === -1) return "unknown";
            const mount = Plugins.mounts[hostKey];
            return root.geometry(mount === undefined ? null : mount.row.instance[section + "Section"]);
        }
        // All mounted entries and the production drop reader, without a
        // visibility projection that could hide an empty layout slot.
        function barParticipationGeometry(hostKey: string): string {
            const mount = Plugins.mounts[hostKey];
            if (mount === undefined) return "absent";
            const bar = mount.row.instance;
            // Hide unmaps BarHost and clears the attached Window.window.
            // The mounted Items remain alive. Effective visibility and
            // section geometry return when BarHost maps the window again.
            return root.json({ shown: PluginLogic.barShown(bar), windowVisible: bar.Window.window !== null && bar.Window.window.visible,
                sections: PluginLogic.SECTIONS.map(section => {
                    const container = bar[section + "Section"];
                    return { section: section, width: container.width, gap: container.spacing,
                        drop: Plugins.barDragSectionGeometry(hostKey, section),
                        entries: mount.sections[section].entries.map(entry => {
                            const item = entry.widget;
                            return { id: entry.locator.id, locator: entry.locator, present: item !== null,
                                visible: item === null ? false : item.visible,
                                box: item === null ? null : [item.x, item.y, item.width, item.height] };
                        }) };
                }) });
        }
        function builtinContentProperty(hostKey: string, id: string, key: string): string {
            const item = root.instance(hostKey, id);
            const content = item === null ? undefined : root.descendants(item).find(child => root.typeName(child) === "Clock");
            return content === undefined || content[key] === undefined ? "absent" : root.json(content[key]);
        }
        function barWidgetFrameFacts(hostKey: string, id: string): string {
            const item = root.instance(hostKey, id);
            return item === null || item.frame === null ? "absent" : root.json(item.frame.describe());
        }
        // `drawn` once the window of plugin ID's HOST_KEY instance has
        // presented a frame at its current size, else `pending`. The first
        // read starts listening, and each pending read asks the window for
        // a frame. A layer surface takes a press only where its presented
        // buffer reaches, so a row waits for this before it presses beside
        // a summon that has just mapped.
        function windowDrawn(hostKey: string, id: string): string {
            const item = root.instance(hostKey, id);
            if (item === null) return "absent";
            const win = item.Window.window;
            if (win === null) return "no-window";
            let entry = root.drawnWindows.find(row => row[0] === win);
            if (entry === undefined) {
                entry = [win, ""];
                root.drawnWindows = root.drawnWindows.concat([entry]);
                win.frameSwapped.connect(() => { entry[1] = win.width + "x" + win.height; });
            }
            if (entry[1] === win.width + "x" + win.height) return "drawn";
            win.update();
            return "pending";
        }
        // Every item under an instance, the instance first, breadth first:
        // its type name as typeName writes it, its objectName, its box in screen
        // coordinates, its implicit size, the index of its parent in the
        // list, a Label's role and a text's line height, at which only 1
        // makes a box its glyphs. A row measures alignment from it, so the
        // shipped item carries no readback of its own.
        function descendantGeometry(hostKey: string, id: string): string {
            const item = root.instance(hostKey, id);
            if (item === null) return "absent";
            const items = root.descendants(item);
            return root.json(items.map(child => {
                const at = child.mapToGlobal(0, 0);
                return {
                    type: root.typeName(child),
                    box: [at.x, at.y, child.width, child.height],
                    implicit: [child.implicitWidth, child.implicitHeight],
                    minimumWidth: child.minimumWidth,
                    maximumWidth: child.maximumWidth,
                    parent: items.indexOf(child.parent),
                    name: child.objectName,
                    visible: child.visible,
                    role: child.role,
                    lineHeight: child.lineHeight,
                    text: child.text,
                    visible: child.visible
                };
            }));
        }
        // Every item named `type` under an instance, in tree order, as the
        // texts it draws: its visible, non-empty Text items depth first, so
        // a row reads a list item's title, its secondary line, its trailing
        // badges and then whatever follows it, as drawn now.
        function itemTexts(hostKey: string, id: string, type: string): string {
            const item = root.instance(hostKey, id);
            if (item === null) return "absent";
            const texts = node => {
                const own = node instanceof Text && node.visible && node.text !== "" ? [node.text] : [];
                return own.concat(...Array.from(node.children || []).map(texts));
            };
            return root.json(root.descendants(item).filter(child => root.typeName(child) === type).map(texts));
        }
        // Every item named `type` under an instance, in tree order, as the
        // colours its visible descendants named `childType` fill with,
        // written as ThemeLogic writes a resolved colour, `#rrggbbaa`.
        function itemColours(hostKey: string, id: string, type: string, childType: string): string {
            const item = root.instance(hostKey, id);
            if (item === null) return "absent";
            return root.json(root.descendants(item).filter(child => root.typeName(child) === type).map(found =>
                root.descendants(found).filter(child => child !== found && child.visible && root.typeName(child) === childType).map(child => ThemeLogic.formatColor(child.color))));
        }
        // The box of the first visible, enabled item named `type` whose
        // `text` is `text`, in screen coordinates, so a row can click it.
        function itemGeometry(hostKey: string, id: string, type: string, text: string): string {
            return root.geometry(root.textItem(hostKey, id, type, text));
        }
        // Whether that item reports the pointer over it: "true", "false",
        // or "absent" with no such item. The compositor routes a click by
        // where it has placed the surface, which can trail the layout
        // itemGeometry reads, so a row clicks once this reads "true".
        function itemHovered(hostKey: string, id: string, type: string, text: string): string {
            const found = root.textItem(hostKey, id, type, text);
            return found === null ? "absent" : String(found.hovered === true);
        }
        // The same for the first visible, enabled item named `type` whose
        // `label` is `label`, for an icon button, which draws no text.
        function labelledGeometry(hostKey: string, id: string, type: string, label: string): string {
            const item = root.instance(hostKey, id);
            if (item === null) return "absent";
            const found = root.descendants(item).find(child => root.typeName(child) === type && child.label === label && child.visible && child.enabled);
            return root.geometry(found === undefined ? null : found);
        }
        // Every Image under an instance, in tree order, as the local path it
        // draws, without a query ("" for none), its status (`null`, `ready`, `loading` or
        // `error`), its box's size, the size it decoded the file to, and
        // its requested source size, so a row reads what a background draws.
        function images(hostKey: string, id: string): string {
            const item = root.instance(hostKey, id);
            if (item === null) return "absent";
            const states = { [Image.Null]: "null", [Image.Ready]: "ready", [Image.Loading]: "loading", [Image.Error]: "error" };
            const local = url => url === "" ? "" : decodeURIComponent(url.replace(/^file:\/\//, "").replace(/\?.*$/, ""));
            return root.json(root.descendants(item).filter(child => child instanceof Image).map(image =>
                [local(image.source.toString()), states[image.status], [image.width, image.height], [image.implicitWidth, image.implicitHeight], [image.sourceSize.width, image.sourceSize.height]]));
        }
        // The screen the host handed an instance, as [width, height,
        // devicePixelRatio], the size in logical pixels, or "absent", so a
        // row reads the scale the shell started on.
        function screenOf(hostKey: string, id: string): string {
            const item = root.instance(hostKey, id);
            if (item === null || !item.screen) return "absent";
            return root.json([item.screen.width, item.screen.height, item.screen.devicePixelRatio]);
        }
        function hasWorkspaceAction(hostKey: string, id: string): bool {
            const item = root.instance(hostKey, id);
            const content = item === null ? undefined : root.descendants(item).find(child => root.typeName(child) === "Workspaces");
            if (content === undefined || !content.bar || !content.bar.shell) return false;
            const compositor = content.bar.shell.compositor;
            return compositor !== undefined && compositor !== null && typeof compositor.focusWorkspace === "function";
        }
        function textOf(hostKey: string, id: string): string {
            const item = root.instance(hostKey, id);
            const label = item === null ? undefined : root.descendants(item).find(child => child instanceof Text);
            return label === undefined ? "absent" : root.json(label.text);
        }
        function drawnFields(hostKey: string, id: string): string {
            const item = root.instance(hostKey, id);
            if (item === null) return "absent";
            const counts = {};
            for (const row of item.plugins) counts[row.id] = 0;
            for (const field of root.descendants(item))
                if (typeof field.apply === "function" && field.pluginId !== undefined) counts[field.pluginId] += 1;
            return root.json(counts);
        }
        function childIndex(hostKey: string, id: string): int {
            const item = root.instance(hostKey, id);
            if (item === null || item.parent === null) return -1;
            for (let i = 0; i < item.parent.children.length; i++)
                if (item.parent.children[i] === item) return i;
            return -1;
        }
        function invokeInstance(hostKey: string, id: string, name: string, arg: string): string { return root.invoke(hostKey, id, name, arg); }
        // Calls the instance's member NAME with the list ARGS_JSON's `args`
        // holds, spread, answering as invokeInstance does. The list sits in
        // an object, since qs ipc call strips the brackets of an argument
        // that opens with `[`.
        function invokeInstanceArgs(hostKey: string, id: string, name: string, argsJson: string): string {
            const item = root.instance(hostKey, id);
            if (item === null) return "absent";
            if (typeof item[name] !== "function") return "no-function";
            const result = item[name](...JSON.parse(argsJson).args);
            return result === undefined ? "" : IpcPages.answer(String(result));
        }
        // Calls the instance's member NAME with ARG COUNT times in one turn,
        // as a burst of input events lands between two frames: the answers,
        // one JSON list.
        function invokeBurst(hostKey: string, id: string, name: string, arg: string, count: int): string {
            const answers = [];
            for (let i = 0; i < count; i++) answers.push(root.invoke(hostKey, id, name, arg));
            return root.json(answers);
        }
        // Every StatusRow under an instance, in tree order, as the type
        // names of its descendants that take an edit: a text input, a text
        // edit that is not read-only, a checkable control, or an item with
        // a setting's or a key's apply. A read-only row lists none.
        function statusRowInputs(hostKey: string, id: string): string {
            const item = root.instance(hostKey, id);
            if (item === null) return "absent";
            const takesEdit = child => child instanceof TextInput || (child instanceof TextEdit && !child.readOnly) || child.checkable === true || typeof child.apply === "function" || typeof child.applyKey === "function";
            return root.json(root.descendants(item).filter(child => root.typeName(child) === "StatusRow").map(row =>
                root.descendants(row).filter(child => child !== row && takesEdit(child)).map(child => root.typeName(child))));
        }
        // Each shown TextField of every StatusRow as [the length of its text,
        // whether it or an item inside it holds the keyboard], one list per
        // row: a row reads a Connect field's state without its secret.
        function statusRowFields(hostKey: string, id: string): string {
            const item = root.instance(hostKey, id);
            if (item === null) return "absent";
            return root.json(root.descendants(item).filter(child => root.typeName(child) === "StatusRow").map(row =>
                root.descendants(row).filter(child => root.typeName(child) === "TextField" && child.visible).map(field =>
                    [field.text.length, field.activeFocus || root.descendants(field).some(inner => inner.activeFocus === true)])));
        }
        // Keep an instance's `status` provider, answering `held` or `absent`.
        function holdStatus(hostKey: string, id: string): string {
            const item = root.instance(hostKey, id);
            if (item === null || item.shell === null || item.shell.status === undefined) return "absent";
            root.heldStatus = item.shell.status;
            return "held";
        }
        // The `sudo` capability of an instance: a grant of DURATION with no
        // `done`, answering its reply, or `absent` while the instance holds
        // no `sudo`.
        function sudoGrant(hostKey: string, id: string, duration: string): string {
            const item = root.instance(hostKey, id);
            if (item === null || item.shell === null || item.shell.sudo === undefined) return "absent";
            return IpcPages.answer(item.shell.sudo.grant(duration));
        }
        // The `doctor` capability of an instance: an offer for OWNER's
        // COMMANDS, comma-separated since qs reads a bracketed argument as a
        // list, and its `missing` as JSON.
        function doctorOffer(hostKey: string, id: string, owner: string, commands: string): string {
            const item = root.instance(hostKey, id);
            if (item === null || item.shell === null || item.shell.doctor === undefined) return "absent";
            return IpcPages.answer(item.shell.doctor.offer(owner, commands.split(",")));
        }
        function doctorMissing(hostKey: string, id: string): string {
            const item = root.instance(hostKey, id);
            if (item === null || item.shell === null || item.shell.doctor === undefined) return "absent";
            return root.json(item.shell.doctor.missing);
        }
        // Publish a JSON value through the kept provider; its reply.
        function heldStatusSet(key: string, valueJson: string): string {
            return root.heldStatus === null ? "absent" : IpcPages.answer(root.heldStatus.set(key, JSON.parse(valueJson)));
        }
        // The first visible, enabled item named `type` under an instance
        // whose `text`, or `label` for an icon button, is `text`, as its
        // box in its window's coordinates, or "absent".
        // windowGeometry for the item scopedItem finds.
        // popupItem's box in screen coordinates, so a row clicks an entry
        // of an open menu or a control in an open popover, and whether it
        // reports the pointer over it: "true", "false", or "absent".
        function popupItemGeometry(hostKey: string, id: string, scopeType: string, scopeText: string, type: string, text: string): string {
            return root.geometry(root.popupItem(hostKey, id, scopeType, scopeText, type, text));
        }
        function popupItemHovered(hostKey: string, id: string, scopeType: string, scopeText: string, type: string, text: string): string {
            const found = root.popupItem(hostKey, id, scopeType, scopeText, type, text);
            return found === null ? "absent" : String(found.hovered === true);
        }
        function scopedWindowGeometry(hostKey: string, id: string, scopeType: string, scopeText: string, type: string, text: string): string {
            const found = root.scopedItem(hostKey, id, scopeType, scopeText, type, text);
            return found === null ? "absent" : root.json(root.windowBox(found));
        }
        function windowGeometry(hostKey: string, id: string, type: string, text: string): string {
            return root.labelledBox(hostKey, id, type, text, true);
        }
        // windowGeometry for a shown item enabled or not, so a row reaches
        // a disabled control.
        function shownWindowGeometry(hostKey: string, id: string, type: string, text: string): string {
            return root.labelledBox(hostKey, id, type, text, false);
        }
        // The keyboard's focus chain from the focused item under an
        // instance: the page, `ListPage` or `PluginPage`, owning that item
        // and each of the next STEPS items Tab reaches, or Shift+Tab for a
        // negative count, "none" for one outside both, as a list. Nothing
        // is focused by the walk.
        function focusChain(hostKey: string, id: string, steps: int): string {
            const item = root.instance(hostKey, id);
            if (item === null) return "absent";
            const focused = root.descendants(item).filter(child => child.activeFocus);
            if (focused.length === 0) return "no-focus";
            const pageOf = node => {
                for (let at = node; at !== null && at !== undefined; at = at.parent) {
                    const type = root.typeName(at);
                    if (type === "ListPage" || type === "PluginPage") return type;
                }
                return "none";
            };
            let at = focused[focused.length - 1];
            const out = [pageOf(at)];
            for (let i = 0; i < Math.abs(steps) && at; i++) {
                at = at.nextItemInFocusChain(steps > 0);
                out.push(at ? pageOf(at) : "end");
            }
            return root.json(out);
        }
        // Every Menu under an instance, in tree order, as it stands: open or
        // not, its entries' texts, the checked ones, the highlighted one and
        // whether its entries scroll.
        function menus(hostKey: string, id: string): string {
            const item = root.instance(hostKey, id);
            if (item === null) return "absent";
            return root.json(root.descendants(item).filter(child => typeof child.items === "function" && child.opened !== undefined).map(menu => {
                const entries = menu.items();
                return {
                    opened: menu.opened,
                    entries: entries.map(e => e.text),
                    checked: entries.filter(e => e.checked).map(e => e.text),
                    current: menu.currentIndex >= 0 && menu.currentIndex < entries.length ? entries[menu.currentIndex].text : null,
                    overflowing: menu.scrollArea.overflowing,
                    barVisible: menu.scrollArea.bar.visible,
                    barHovered: menu.scrollArea.bar.hovered,
                    anchorType: root.typeName(menu.anchorItem)
                };
            }));
        }
        // The one open Menu under an instance scrolled so its highlighted
        // entry's top is `offset` above the list's top edge, held inside
        // its entries, as the distance the entry's top then lies above that
        // edge; `menus-open=<n>` or `no-highlight` when there is none.
        function scrollMenu(hostKey: string, id: string, offset: real): string {
            const item = root.instance(hostKey, id);
            if (item === null) return "absent";
            const open = root.descendants(item).filter(child => typeof child.items === "function" && child.opened === true);
            if (open.length !== 1) return "menus-open=" + open.length;
            const entries = open[0].items();
            const current = open[0].currentIndex;
            if (current < 0 || current >= entries.length) return "no-highlight";
            const area = open[0].scrollArea;
            area.contentY = Math.max(0, Math.min(entries[current].y + offset, area.contentHeight - area.height));
            return root.json(area.contentY - entries[current].y);
        }
        // Every shown ScrollArea under an instance, in tree order: its
        // scroll position, content height and height, and its bar's and
        // thumb's boxes in the window's coordinates.
        function scrollAreas(hostKey: string, id: string): string {
            const item = root.instance(hostKey, id);
            if (item === null) return "absent";
            return root.json(root.shownScrollAreas(item).map(area => ({
                contentY: area.contentY,
                contentHeight: area.contentHeight,
                height: area.height,
                contentWidth: area.contentWidth,
                width: area.width,
                barVisible: area.bar.visible,
                bar: root.windowBox(area.bar),
                thumb: root.windowBox(area.bar.thumb)
            })));
        }
        // The innermost Flickable, a ScrollArea or a list view included,
        // holding the first shown item under an instance that reads `text`
        // (reads): its type, scroll position, content height, height, the
        // mouse buttons that drag it and its box in the window's
        // coordinates, or `absent` / `no-view`.
        function viewHolding(hostKey: string, id: string, text: string): string {
            const view = root.viewOf(hostKey, id, text);
            if (typeof view === "string") return view;
            return root.json({
                type: root.typeName(view), contentY: view.contentY, contentHeight: view.contentHeight,
                height: view.height, acceptedButtons: view.acceptedButtons, box: root.windowBox(view)
            });
        }
        // Sets the mouse buttons that drag the view viewHolding finds, so a
        // row's control gives one view Qt's left-button drag back; answers
        // the buttons it held before.
        function setViewButtons(hostKey: string, id: string, text: string, buttons: int): string {
            const view = root.viewOf(hostKey, id, text);
            if (typeof view === "string") return view;
            const before = view.acceptedButtons;
            view.acceptedButtons = buttons;
            return String(before);
        }
        // Turns the touchpad scroll of the view viewHolding finds off, or
        // back on while the view is interactive, as it declares it, so a
        // row's control gives one view Qt's own handling of a swipe back;
        // answers whether it was on before, or `no-touchpad` for a view
        // that declares none.
        function setViewTouchpad(hostKey: string, id: string, text: string, on: bool): string {
            const view = root.viewOf(hostKey, id, text);
            if (typeof view === "string") return view;
            const area = view.contentItem.children.find(child => root.typeName(child) === "TouchpadScroll");
            if (area === undefined) return "no-touchpad";
            const before = area.enabled;
            area.enabled = on ? Qt.binding(() => view.interactive) : false;
            return String(before);
        }
        // The one Dialog under an instance: its box in the window's
        // coordinates and whether its card's own MouseArea, which takes the
        // presses that land on the card's empty space, is enabled; or a
        // failure word from dialogCardArea.
        function dialogCard(hostKey: string, id: string): string {
            const area = root.dialogCardArea(hostKey, id);
            if (typeof area === "string") return area;
            return root.json({ box: root.windowBox(area.dialog), enabled: area.area.enabled, shown: root.visibleInTree(area.dialog) });
        }
        // Turns that MouseArea on or off, so a row's control lets a click
        // on the card fall through to what lies under the dialog; answers
        // whether it was enabled before.
        function setDialogCard(hostKey: string, id: string, enabled: bool): string {
            const area = root.dialogCardArea(hostKey, id);
            if (typeof area === "string") return area;
            const before = area.area.enabled;
            area.area.enabled = enabled;
            return String(before);
        }
        // Whether an item under the instance holds keyboard focus in an
        // active window, so a row types only once the compositor gave the
        // surface the keyboard.
        // PROPERTY of the first item named TYPE under an instance, in tree
        // order, as JSON: a view a Loader holds inside an overlay.
        // Every item named `type` under an instance, in tree order, as the
        // values of its comma-separated `properties`, a colour as its
        // #aarrggbb name, as layerItems reads a layer's.
        // A plugin page's shown Setup section, as { chips, lines, buttons }:
        // each visible Badge as [text, tone], every other visible line of
        // text outside a Badge or a RowAction, and each visible RowAction
        // as [text, tone, enabled, its Tooltip's text or ""], each in tree
        // order, which is the drawn order; "absent" while no Setup section
        // shows.
        function setupSection(hostKey: string, id: string): string {
            const item = root.instance(hostKey, id);
            if (item === null) return "absent";
            const section = root.descendants(item).find(child => root.typeName(child) === "Section" && child.visible && child.title === "Setup");
            if (section === undefined) return "absent";
            const shown = root.descendants(section).filter(child => child.visible);
            const badges = shown.filter(child => root.typeName(child) === "Badge");
            const buttons = shown.filter(child => root.typeName(child) === "RowAction");
            const inside = (child, owners) => owners.some(owner => owner !== child && root.descendants(owner).indexOf(child) !== -1);
            const lines = shown.filter(child => root.typeName(child) === "Label" && child.text !== "" && !inside(child, badges) && !inside(child, buttons) && child.text !== section.title && child.text !== section.description);
            return root.json({
                chips: badges.map(badge => [badge.text, badge.tone]),
                lines: lines.map(line => line.text),
                buttons: buttons.map(button => {
                    const tip = root.descendants(button).find(child => root.typeName(child) === "Tooltip");
                    return [button.text, button.tone, button.enabled, tip === undefined ? "" : tip.text];
                })
            });
        }
        // A plugin page's shown Setup section by row, as [{ label, chips,
        // buttons, lines }]: each shown step row of the section, a Field
        // drawn for one of Steps.setupRows, its label, its Badges as [text,
        // tone], its RowActions as { tui, tone, enabled }, tui the screen
        // the row's step opens (its Steps.setupRows button), and the shown
        // lines of text the Field draws under its value, each in tree
        // order; "absent" while no Setup section shows.
        function setupRows(hostKey: string, id: string): string {
            const item = root.instance(hostKey, id);
            if (item === null) return "absent";
            const section = root.descendants(item).find(child => root.typeName(child) === "Section" && child.visible && child.title === "Setup");
            if (section === undefined) return "absent";
            const fields = root.descendants(section).filter(child => root.typeName(child) === "Field" && child.visible && child.modelData !== undefined);
            return root.json(fields.map(field => {
                const shown = root.descendants(field).filter(child => child.visible);
                const value = shown.find(child => root.typeName(child) === "FormRow");
                const inValue = value === undefined ? [] : root.descendants(value);
                const under = shown.filter(child => root.typeName(child) === "Label" && child.text !== "" && inValue.indexOf(child) === -1);
                const step = field.modelData.button;
                return {
                    label: field.label,
                    chips: shown.filter(child => root.typeName(child) === "Badge").map(badge => [badge.text, badge.tone]),
                    buttons: shown.filter(child => root.typeName(child) === "RowAction").map(button => ({
                        tui: step === null || step === undefined ? "" : step.name, tone: button.tone, enabled: button.enabled })),
                    lines: under.map(line => line.text)
                };
            }));
        }
        function itemValues(hostKey: string, id: string, type: string, properties: string): string {
            const item = root.instance(hostKey, id);
            if (item === null) return "absent";
            const names = properties === "" ? [] : properties.split(",");
            return root.json(root.descendants(item).filter(child => root.typeName(child) === type).map(child => {
                const values = {};
                for (const name of names) values[name] = child[name] !== null && typeof child[name] === "object" && "hslHue" in child[name] ? child[name].toString() : child[name];
                return values;
            }));
        }
        // Plant an oversized rendered control for the input-width smoke
        // check. Disable the private allocation correction on this instance.
        // Closing the disposable window destroys the planted fault.
        function forceInputWidth(hostKey: string, id: string, type: string, width: real): string {
            const item = root.instance(hostKey, id);
            if (item === null) return "absent";
            const input = root.descendants(item).find(child => root.typeName(child) === type && child.visible && child.maximumWidth !== undefined);
            if (input === undefined) return "absent";
            const constraint = Array.from(input.data).find(child => root.typeName(child) === "InputWidth");
            if (constraint === undefined) return "constraint-absent";
            constraint.ready = false;
            input.width = width;
            return root.json(input.width);
        }
        function readDescendant(hostKey: string, id: string, type: string, property: string): string {
            const item = root.instance(hostKey, id);
            if (item === null) return "absent";
            const found = root.descendants(item).find(child => root.typeName(child) === type);
            if (found === undefined) return "absent";
            const json = root.json(found[property]);
            return json === undefined ? "undefined" : json;
        }
        function readMatchingDescendant(hostKey: string, id: string, type: string, key: string, value: string, property: string): string {
            const item = root.instance(hostKey, id);
            if (item === null) return "absent";
            const found = root.descendants(item).find(child => root.typeName(child) === type && String(child[key]) === value);
            if (found === undefined) return "absent";
            const json = root.json(found[property]);
            return json === undefined ? "undefined" : json;
        }
        // The first titled Pane under an instance: the title, its content
        // edges, the title row centre, and the boxes of the h3 title label,
        // the header switch and the settings gear, all in the pane's own
        // coordinates. Rows use it for shared dropdown header geometry
        // without adding readbacks to the shipped Pane API.
        function paneHeader(hostKey: string, id: string): string {
            const item = root.instance(hostKey, id);
            if (item === null) return "absent";
            const pane = root.descendants(item).find(child => root.typeName(child) === "Pane" && child.title !== undefined && child.title !== "");
            if (pane === undefined) return "absent";
            const title = root.descendants(pane).find(child => root.typeName(child) === "Label" && child.role === "h3" && child.text === pane.title && child.visible);
            const gear = root.descendants(pane).find(child => root.typeName(child) === "IconButton" && child.label === "Settings" && child.visible);
            const sw = pane.headerSwitch;
            // Boxes in the pane's own coordinates, the frame its content
            // edges and title row are read in.
            const box = child => { const at = child.mapToItem(pane, 0, 0); return [at.x, at.y, child.width, child.height]; };
            return root.json({
                title: pane.title,
                contentLeft: pane.contentInset,
                contentRight: pane.contentInset + pane.contentWidth,
                inlineGap: Theme.stack.inline,
                titleCenterY: pane.contentInset + pane.titleRowHeight / 2,
                titleBox: title === undefined ? null : box(title),
                switchBox: sw === null ? null : box(sw),
                switchChecked: sw === null ? null : sw.checked,
                switchEnabled: sw === null ? null : sw.enabled,
                gearBox: gear === undefined ? null : box(gear)
            });
        }
        // readDescendant over the items whose every ancestor is visible:
        // a list's own cursor rather than one in a closed flyout of the
        // same instance, whatever the cursor itself shows.
        function readShownDescendant(hostKey: string, id: string, type: string, property: string): string {
            const item = root.instance(hostKey, id);
            if (item === null) return "absent";
            const placed = child => { for (let at = child.parent; at !== null && at !== item; at = at.parent) if (!at.visible) return false; return true; };
            const found = root.descendants(item).find(child => root.typeName(child) === type && placed(child));
            if (found === undefined) return "absent";
            const json = root.json(found[property]);
            return json === undefined ? "undefined" : json;
        }
        // The name the theme browser's centre card draws, as JSON, or
        // `absent` while no ThemeCard is current.
        function currentThemeCardName(hostKey: string, id: string): string {
            const item = root.instance(hostKey, id);
            if (item === null) return "absent";
            const found = root.descendants(item).find(child => root.typeName(child) === "ThemeCard" && child.current === true);
            return found === undefined ? "absent" : root.json(found.modelData.name);
        }
        function paletteStrips(hostKey: string, id: string): string {
            const item = root.instance(hostKey, id);
            if (item === null) return "absent";
            const shown = child => {
                for (let at = child; at !== null && at !== item; at = at.parent)
                    if (at.visible === false) return false;
                return true;
            };
            return root.json(root.descendants(item)
                .filter(child => root.typeName(child) === "ThemeCard")
                .map(card => {
                    const strip = root.descendants(card).find(child => child.objectName === "paletteStrip" || (root.typeName(child) === "Row" && child.parent === card && child.height === Theme.space.xxl));
                    const swatches = strip === undefined ? [] : root.descendants(strip).filter(child => child !== strip && child.visible && child.width > 0 && child.color !== undefined);
                    return [card.modelData.name, shown(card), strip !== undefined && shown(strip), swatches.length];
                }));
        }
        // The deepest item under an instance holding the active focus, as
        // [type, text], an icon button's label as its text, so a keyboard row types only once the field it
        // means holds the keys, or "no-focus".
        function activeFocusItem(hostKey: string, id: string): string {
            const item = root.instance(hostKey, id);
            if (item === null) return "absent";
            const focused = root.descendants(item).filter(child => child.activeFocus);
            if (focused.length === 0) return "no-focus";
            const at = focused[focused.length - 1];
            return root.json([root.typeName(at), at.label !== undefined && at.label !== "" ? String(at.label) : at.text !== undefined ? String(at.text) : null]);
        }
        // Whether the item holding the keys under an instance lies inside
        // an item named `type`, such as a page, whichever of its controls
        // holds them.
        function activeFocusWithin(hostKey: string, id: string, type: string): bool {
            const item = root.instance(hostKey, id);
            if (item === null) return false;
            const focused = root.descendants(item).filter(child => child.activeFocus);
            if (focused.length === 0) return false;
            for (let at = focused[focused.length - 1]; at !== null && at !== undefined && at !== item; at = at.parent)
                if (root.typeName(at) === type) return true;
            return false;
        }
        function activeFocusIn(hostKey: string, id: string): bool {
            const item = root.instance(hostKey, id);
            return item !== null && root.descendants(item).some(child => child.activeFocus);
        }
        // Whether Qt has activated the window that holds an instance: its
        // root item, the instance's topmost ancestor, holds the active
        // focus. A plugin that takes no focus leaves it on the host's slot,
        // so this reads a window whatever its plugin focuses.
        function windowFocused(hostKey: string, id: string): bool {
            let at = root.instance(hostKey, id);
            if (at === null) return false;
            while (at.parent !== null) at = at.parent;
            return at.activeFocus;
        }
        // The focused descendant of an instance as [type, text or label,
        // visualFocus, ringShown, inView], or no-focus / absent.
        function focused(hostKey: string, id: string): string {
            const item = root.instance(hostKey, id);
            if (item === null) return "absent";
            const focused = root.descendants(item).filter(child => child.activeFocus);
            if (focused.length === 0) return "no-focus";
            const target = focused[focused.length - 1];
            const label = () => {
                for (let at = target; at !== null && at !== item && at !== undefined; at = at.parent) {
                    try {
                        if (at.focusExample !== undefined && at.focusExample !== "") return String(at.focusExample);
                    } catch (e) {}
                }
                if (target.text !== undefined && target.text !== "") return String(target.text);
                if (target.label !== undefined && target.label !== "") return String(target.label);
                try {
                    if (target.Accessible !== undefined && target.Accessible.name !== "") return String(target.Accessible.name);
                } catch (e) {}
                return "";
            };
            const targetIsScrollAreaProxy = target.parent !== null && root.typeName(target.parent) === "ScrollArea";
            const ringOwner = targetIsScrollAreaProxy ? target.parent : target;
            const ringShown = root.descendants(ringOwner).some(child => root.typeName(child) === "FocusRing" && child.visible);
            const window = target.Window.window;
            let inView = window !== null && target.width > 0 && target.height > 0;
            if (inView) {
                const at = target.mapToItem(null, 0, 0);
                inView = at.x >= 0 && at.y >= 0 && at.x + target.width <= window.width && at.y + target.height <= window.height;
            }
            for (let at = target.parent; inView && at !== null && at !== item; at = at.parent) {
                if (at.contentY === undefined || at.contentX === undefined || at.clip !== true) continue;
                const pos = target.mapToItem(at, 0, 0);
                inView = pos.x >= 0 && pos.y >= 0 && pos.x + target.width <= at.width && pos.y + target.height <= at.height;
            }
            return root.json([targetIsScrollAreaProxy ? "ScrollArea" : root.typeName(target), label(), target.visualFocus === true || ringShown, ringShown, inView]);
        }
        function focusExample(hostKey: string, id: string, name: string): string {
            return focusExampleAt("", hostKey, id, name);
        }
        function popupFocusExample(copyName: string, name: string): string {
            return focusExampleAt(copyName, "", "", name);
        }
        function focusExampleAt(copyName: string, hostKey: string, id: string, name: string): string {
            const item = copyName === "" ? root.instance(hostKey, id) : root.popupCopies[copyName];
            if (item === null || item === undefined) return "absent";
            const owner = root.descendants(item).find(child => {
                try { return child.focusExample === name; } catch (e) { return false; }
            });
            if (owner === undefined) return "absent";
            let target = owner;
            const focusable = child => child !== undefined && child.forceActiveFocus !== undefined && child.visible !== false && child.enabled !== false && (child.activeFocusOnTab === true || child.focusPolicy === Qt.StrongFocus || child.focusPolicy === Qt.TabFocus);
            if (!focusable(target)) {
                target = root.descendants(owner).find(child => focusable(child));
            }
            if (target === undefined) return "no-focusable";
            target.forceActiveFocus(Qt.TabFocusReason);
            return "focused";
        }
        // The launcher's rows as it draws them, in list order: each
        // LauncherRow delegate's kind, label and detail.
        function launcherRows(hostKey: string, id: string): string {
            const item = root.instance(hostKey, id);
            if (item === null) return "absent";
            const rows = root.descendants(item).filter(child => /^LauncherRow_QMLTYPE_/.test(String(child)) && child.index >= 0);
            rows.sort((a, b) => a.index - b.index);
            return root.json(rows.map(row => [row.kind, row.label, row.detail]));
        }
        // The launcher's edge light: the URL its shader loaded from and
        // whether the engine compiled it.
        function launcherShader(hostKey: string, id: string): string {
            const item = root.instance(hostKey, id);
            if (item === null) return "absent";
            const shader = root.descendants(item).find(child => child instanceof ShaderEffect);
            if (shader === undefined) return "no-shader";
            return root.json({ url: String(shader.fragmentShader), compiled: shader.status === ShaderEffect.Compiled, log: shader.log });
        }
        // Build a copy of a popup from FILE, a path beside the shipped file
        // so its imports and sibling types resolve as the shipped one's do,
        // as a child of the instance HOST_KEY/ID, whose item it anchors to,
        // with PROPERTIES, a JSON object, as its initial properties; a value
        // "@instance" there, at the top or one object down, is that item.
        // A list is assigned once the copy is made, since a list handed to
        // createObject stops being an array. Kept under
        // NAME: `ok`, or the component's error.
        function popupLoad(name: string, file: string, hostKey: string, id: string, properties: string): string {
            if (name in root.popupCopies) return "loaded";
            const item = root.instance(hostKey, id);
            if (item === null) return "absent";
            const resolve = value => value === "@instance" ? item : value;
            const given = JSON.parse(properties);
            const initial = {};
            const lists = {};
            for (const key of Object.keys(given)) {
                const value = given[key];
                if (Array.isArray(value)) lists[key] = value;
                else if (value !== null && typeof value === "object") {
                    const inner = {};
                    for (const k of Object.keys(value)) inner[k] = resolve(value[k]);
                    initial[key] = inner;
                } else initial[key] = resolve(value);
            }
            const component = Qt.createComponent("file://" + file);
            if (component.status !== Component.Ready) return IpcPages.answer("error: " + component.errorString().trim().replace(/\n/g, " "));
            const made = component.createObject(item, initial);
            if (made === null) return "error: create";
            for (const key of Object.keys(lists)) made[key] = lists[key];
            const next = Object.assign({}, root.popupCopies);
            next[name] = made;
            root.popupCopies = next;
            return "ok";
        }
        // Call member VERB of copy NAME with no argument: `ok`, or `absent`.
        function popupCall(name: string, verb: string): string {
            const copy = root.popupCopies[name];
            if (copy === undefined) return "absent";
            copy[verb]();
            return "ok";
        }
        // The list of Select copy NAME as selectList reads it, or `absent`.
        function popupSelectList(name: string): string {
            const copy = root.popupCopies[name];
            return copy === undefined ? "absent" : root.json(root.selectList(copy));
        }
        // PROPERTY of copy NAME as JSON, or `absent`.
        function popupRead(name: string, property: string): string {
            const copy = root.popupCopies[name];
            return copy === undefined ? "absent" : root.json(copy[property]);
        }
        function popupDrop(name: string): string {
            const copy = root.popupCopies[name];
            if (copy === undefined) return "absent";
            const next = Object.assign({}, root.popupCopies);
            delete next[name];
            root.popupCopies = next;
            copy.destroy();
            return "ok";
        }
        // Build a disposable panel host copy from FILE on the focused
        // screen. Rows use this for host controls whose window activation
        // must behave like a real unanchored summon.
        function panelHostLoad(name: string, file: string, id: string): string {
            const made = root.hostCopy(name, file, screen => ({ pluginId: id, screen: screen }));
            return typeof made === "string" ? made : "ok";
        }
        // Build a disposable SummonLayer copy from FILE: plugin ID's KIND
        // summoned without an anchor on the focused screen, as SummonHost
        // builds it; the row calls the plugin's open(), as the host does
        // once the slot has built it. The copy's `dismissed` is counted
        // under NAME, which summonLayerDismissals reads.
        function summonLayerLoad(name: string, file: string, id: string, kind: string): string {
            const made = root.hostCopy(name, file, screen => ({ pluginId: id, kind: kind, request: { payloadJson: "{}", anchor: null, anchored: false, screen: screen, returnFocus: null, returnFocusWasVisual: false } }));
            if (typeof made === "string") return made;
            const counts = Object.assign({}, root.layerDismissals);
            counts[name] = 0;
            root.layerDismissals = counts;
            made.dismissed.connect(() => {
                const next = Object.assign({}, root.layerDismissals);
                next[name] = (next[name] || 0) + 1;
                root.layerDismissals = next;
            });
            return "ok";
        }
        function summonLayerDismissals(name: string): string {
            return name in root.layerDismissals ? String(root.layerDismissals[name]) : "absent";
        }
        // Build a disposable OverlaySurface copy with the real layer
        // component, on its first screen. Only the copy's mask differs;
        // the fixture, pointer and receiver are the row's normal ones.
        // popupDrop owns its teardown with the other surface copies.
        function layerSurfaceLoad(name: string, file: string, id: string): string {
            if (name in root.popupCopies) return "loaded";
            const entry = Layers.entries.find(e => e.pluginId === id);
            if (entry === undefined) return "absent";
            const original = entry.screens[Object.keys(entry.screens).sort()[0]];
            if (original === undefined) return "no-screen";
            const component = Qt.createComponent("file://" + file);
            if (component.status !== Component.Ready) return IpcPages.answer("error: " + component.errorString().trim().replace(/\n/g, " "));
            const made = component.createObject(root, { placement: "center", inset: 0, visible: false });
            if (made === null) return "error: create";
            made.screen = original.screen;
            made.WlrLayershell.namespace = "vgs:layer-control";
            made.WlrLayershell.keyboardFocus = WlrKeyboardFocus.None;
            const content = entry.component.createObject(made.contentItem);
            if (content === null) {
                made.destroy();
                return "error: content";
            }
            content.screen = original.screen;
            content.anchors.fill = made.contentItem;
            made.inputItems = Qt.binding(() => content.inputItems);
            made.inputAll = Qt.binding(() => content.inputAll);
            const next = Object.assign({}, root.popupCopies);
            next[name] = made;
            root.popupCopies = next;
            made.visible = true;
            return "ok";
        }
        // The prompt of FILE, the sandbox tree's vgs.polkit Prompt.qml,
        // built in a stand-in of the summon host's overlay layer surface on
        // the focused screen and opened as the host opens it, over a fresh
        // stand-in flow its `shell` lends as the polkit agent's. The plugin
        // itself stays disabled, so the core builds no agent. `ok`, or a
        // keyed refusal.
        function polkitStandInOpen(file: string): string {
            if (root.polkitStandIn !== null) return "refused: stand-in=open";
            const screen = Compositor.focusedScreen();
            if (screen === null) return "refused: screen=none";
            const component = Qt.createComponent("file://" + file);
            if (component.status !== Component.Ready) return IpcPages.answer("error: " + component.errorString().trim().replace(/\n/g, " "));
            const flow = polkitStandInFlow.createObject(root);
            const surface = polkitStandInSurface.createObject(root, { visible: false });
            if (flow === null || surface === null) {
                if (flow !== null) flow.destroy();
                if (surface !== null) surface.destroy();
                return "error: create";
            }
            const prompt = component.createObject(surface.contentItem);
            if (prompt === null) {
                surface.destroy();
                flow.destroy();
                return "error: prompt";
            }
            surface.screen = screen;
            prompt.anchors.fill = surface.contentItem;
            // Assigned after creation, as the core assigns it: a JS object
            // handed to createObject crosses a QVariant conversion.
            prompt.shell = { polkit: { agent: { flow: flow } } };
            root.polkitStandIn = { surface: surface, prompt: prompt, flow: flow };
            surface.visible = true;
            try {
                prompt.open("{}");
            } catch (e) {
                return IpcPages.answer("error: open " + e.message);
            }
            return "ok";
        }
        // The stand-in flow after a failed attempt: PAM asks again and
        // the prompt shows the failed note.
        function polkitStandInFail(): string {
            if (root.polkitStandIn === null) return "absent";
            root.polkitStandIn.flow.failed = true;
            return "ok";
        }
        // Close the prompt as the host does before it hides a surface,
        // then destroy the surface, the prompt and the flow. Answers the
        // flow's submit and cancel counts as JSON, read after the close.
        function polkitStandInDrop(): string {
            const standIn = root.polkitStandIn;
            if (standIn === null) return "absent";
            root.polkitStandIn = null;
            standIn.prompt.close();
            const counts = root.json({ submits: standIn.flow.submits, cancels: standIn.flow.cancels });
            standIn.surface.destroy();
            standIn.flow.destroy();
            return counts;
        }
        // Build a copy of ThemeRunner from FILE, a path under the shell's
        // Core directory so its imports resolve as the shipped one's do:
        // `ok`, or the component's error.
        function runnerLoad(file: string): string {
            if (root.runnerCopy !== null) return "loaded";
            const component = Qt.createComponent("file://" + file);
            if (component.status !== Component.Ready) return IpcPages.answer("error: " + component.errorString());
            const made = component.createObject(root);
            if (made === null) return "error: create";
            root.runnerAnswers = {};
            root.runnerCopy = made;
            return "ok";
        }
        // Call the copy's member VERB with ARG as a capability call would,
        // its answers kept by verb; the member's reply, `ok` for none.
        function runnerCall(verb: string, arg: string): string {
            return root.callRunner(verb, [arg]);
        }
        // runnerCall with OPTIONS, a JSON value, after `done`, as
        // `wallpapers(name, done, options)` takes it.
        function runnerCallWith(verb: string, arg: string, options: string): string {
            return root.callRunner(verb, [arg], JSON.parse(options));
        }
        // How many times the copy answered VERB.
        function runnerAnswered(verb: string): int {
            return verb in root.runnerAnswers ? root.runnerAnswers[verb].count : 0;
        }
        // The copy's lending record, or `absent`.
        function runnerRecord(): string { return root.runnerCopy === null ? "absent" : root.json(root.runnerCopy.record()); }
        function runnerDrop(): string {
            if (root.runnerCopy === null) return "absent";
            root.runnerCopy.destroy();
            root.runnerCopy = null;
            return "ok";
        }
        // Count visible text nodes under items named `type` whose text
        // contains NEEDLE. Rows use this for large drawn-text checks where
        // the count is the contract and the full text would page.
        function itemTextCount(hostKey: string, id: string, type: string, needle: string): int {
            const item = root.instance(hostKey, id);
            if (item === null) return 0;
            const shown = child => {
                for (let at = child; at !== null && at !== item; at = at.parent)
                    if (at.visible === false) return false;
                return true;
            };
            const texts = node => {
                let count = node instanceof Text && shown(node) && node.text.indexOf(needle) !== -1 ? 1 : 0;
                for (const child of Array.from(node.children || [])) count += texts(child);
                return count;
            };
            const found = root.descendants(item).find(child => root.typeName(child) === type && shown(child));
            return found === undefined ? 0 : texts(found);
        }
        // Count visible ImageText items under items named `type` that hold
        // at least one image segment. The row separately controls paged IPC.
        function itemImageTextCount(hostKey: string, id: string, type: string): int {
            const item = root.instance(hostKey, id);
            if (item === null) return 0;
            const shown = child => {
                for (let at = child; at !== null && at !== item; at = at.parent)
                    if (at.visible === false) return false;
                return true;
            };
            const hasImage = child => {
                for (const segment of child.segments || [])
                    if (segment.image !== undefined && segment.image !== "") return true;
                return false;
            };
            const found = root.descendants(item).find(child => root.typeName(child) === type && shown(child));
            if (found === undefined) return 0;
            return root.descendants(found).filter(child => root.typeName(child) === "ImageText" && shown(child) && hasImage(child)).length;
        }
    }
}
