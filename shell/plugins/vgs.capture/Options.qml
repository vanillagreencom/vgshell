import QtQuick
import qs.Commons
import qs.Ui

// The Capture options, the plugin window's content while no app asks to
// share the screen. The mode switch picks what to capture, the tiles pick
// its target, and one primary action runs it; a few options follow, and
// Settings holds the rest. Every action, including a setting change, goes
// through the service's IPC.
Item {
    id: root
    property var shell: null
    property Item initialFocus: primaryAction
    property string problem: ""
    readonly property string mode: modes[modeSwitch.currentIndex]
    // Each mode's own target, kept while the window is open.
    property int screenshotTargetIndex: 0
    property int recordTargetIndex: 0
    readonly property var capture: shell === null || shell.status.values.capture === undefined ? ({ phase: "idle", available: {} }) : shell.status.values.capture
    readonly property bool recording: capture.phase === "recording" || capture.phase === "stopping"
    readonly property var values: shell === null ? ({}) : shell.status.values
    readonly property var languagesRow: shell === null ? null : shell.status.rows.find(row => row.key === "languages") || null
    readonly property bool languagesOffered: languagesRow !== null && languagesRow.action !== null && languagesRow.action.offered
    readonly property var modes: ["Screenshot", "Record", "Text"]
    // Each option here names its setting and its choices as the Settings
    // page does, from the manifest's schema entry.
    readonly property var schema: shell === null ? ({}) : shell.manifest.schema
    readonly property var processingChoices: choices("processing")
    // The usual delays, and the kept one when it is none of them. The
    // manifest gives `delay` no schema entry: the choice made here is kept
    // for the next open, and Settings draws no field for it.
    readonly property var delayChoices: {
        const current = setting("delay", 0);
        const seconds = [0, 3, 5, 10];
        if (seconds.indexOf(current) < 0) seconds.push(current);
        seconds.sort((a, b) => a - b);
        return seconds.map(value => ({ label: value === 0 ? "None" : value + " seconds", value: value }));
    }
    readonly property var audioChoices: choices("audio")
    // The language presets, and the saved value when Settings set codes no
    // preset names, such as deu+fra, so the select shows it.
    readonly property var languageChoices: {
        const presets = shell === null ? [] : schema.ocrLanguages.presets;
        const current = setting("ocrLanguages", "");
        return current === "" || presets.some(preset => preset.value === current) ? presets : presets.concat([{ label: current, value: current }]);
    }
    readonly property var qualityChoices: choices("quality")
    // Every target stays choosable and pressable while a tool it needs is
    // missing: the press reaches the service, which offers the install
    // notice, and the window says why the action did not start.
    readonly property var screenshotTargets: [
        { text: "Area", icon: "scan", action: "screenshot-area" },
        { text: "Window", icon: "app-window", action: "screenshot-window" },
        { text: "Display", icon: "monitor", action: "screenshot-display" },
        { text: "All", icon: "monitor-check", action: "screenshot-all" }
    ]
    readonly property var recordTargets: [
        { text: "Area", icon: "scan", action: "record" },
        { text: "Window", icon: "app-window", action: "record-window" },
        { text: "Display", icon: "monitor", action: "record-display" },
        { text: "Picker", icon: "screen-share", action: "record-portal" }
    ]
    readonly property var currentTargets: mode === "Screenshot" ? screenshotTargets : mode === "Record" ? recordTargets : []
    readonly property int currentTargetIndex: mode === "Record" ? recordTargetIndex : screenshotTargetIndex
    readonly property var currentTarget: currentTargets.length === 0 ? null : currentTargets[currentTargetIndex]
    // The action the primary button hands the service.
    readonly property string primaryActionName: recording ? "record" : mode === "Text" ? "text" : currentTarget === null ? "" : currentTarget.action
    readonly property string primaryText: recording ? "Stop recording" : mode === "Screenshot" ? "Take screenshot" : mode === "Record" ? "Start recording" : "Copy text"
    readonly property string primaryIcon: recording ? "circle-stop" : mode === "Screenshot" ? "camera" : mode === "Record" ? "video" : "scan-text"

    function open(payloadJson) {
        problem = "";
        if (shell !== null) shell.ipc.call("probe", "");
    }
    function close() {}
    function invoke(name) {
        const reply = shell.ipc.call(name, "");
        problem = reply === "ok" ? "" : reply.indexOf("capture=missing") >= 0 ? "Install the missing tools to use this action." : "Capture is busy. Wait for it to finish.";
        if (reply === "ok") shell.surfaces.hide("window");
        return reply;
    }
    function installLanguages() { return shell.status.act("languages"); }
    function fieldLabel(key) { return schema[key] === undefined ? "" : schema[key].label; }
    function choices(key) { return schema[key] === undefined ? [] : schema[key].options; }
    function setting(key, fallback) { return shell === null || shell.settings[key] === undefined ? fallback : shell.settings[key]; }
    function choiceIndex(choices, value) { return choices.findIndex(choice => choice.value === value); }
    function save(key, value) {
        const reply = shell.ipc.call("setting", JSON.stringify({ key: key, value: value }));
        problem = reply === "ok" ? "" : "The setting could not be saved.";
        return reply;
    }
    function chooseTarget(index) {
        if (mode === "Record") recordTargetIndex = index;
        else screenshotTargetIndex = index;
        targetTiles.currentIndex = Qt.binding(() => root.currentTargetIndex);
    }

    // Hyprland owns a mapped window's size, so a change of the options'
    // height, such as another mode's options or the reason a press did not
    // start, resizes the shown window to it as Settings does
    // (vgs.settings Window.qml `fitWindow`): one placeWindow request keeps
    // the client's top and width, up to the cap of the screen it is on
    // (OverlayState.windowRoom) and the bottom of that screen's room. The
    // window is the one client of the shell's app-id, `org.vgs.shell`,
    // titled with this plugin's name, as the window host titles it.
    // callLater runs one fit for the changes of one turn
    // (https://doc.qt.io/qt-6/qml-qtqml-qt.html#callLater-method).
    onImplicitHeightChanged: if (root.Window.window !== null && root.Window.window.visible) Qt.callLater(fitWindow)
    function fitWindow() {
        shell.compositor.readWindows(state => {
            if (root.Window.window === null || !root.Window.window.visible) return;
            if (!state.ok) {
                console.warn("capture: resize " + state.error);
                return;
            }
            const own = state.clients.filter(c => c.class === "org.vgs.shell" && c.title === shell.manifest.name && c.mapped);
            if (own.length !== 1) {
                console.warn("capture: resize clients=" + own.length);
                return;
            }
            const client = own[0];
            // A tiled or fullscreen window is the user's layout choice.
            if (client.floating !== true || client.fullscreen !== 0) return;
            const monitors = state.monitors.filter(m => m.id === client.monitor);
            // Read by index, as Compositor.focusedScreen reads
            // Quickshell.screens.
            const all = shell.screens.all;
            let screen = null;
            for (let i = 0; i < all.length; i++)
                if (monitors.length === 1 && all[i].name === monitors[0].name) screen = all[i];
            if (screen === null) {
                console.warn("capture: resize screen=none monitor=" + client.monitor);
                return;
            }
            // A ShellScreen's y is its output's logical position, the space
            // of a client's `at`.
            const room = OverlayState.room(screen);
            const bottom = Math.floor(screen.y + room.y + room.height);
            const height = Math.min(Math.ceil(root.implicitHeight), OverlayState.windowRoom(screen).height, bottom - client.at[1]);
            if (height < 1 || client.size[1] === height) return;
            const placed = shell.compositor.placeWindow(client.address, client.at[0], client.at[1], client.size[0], height);
            if (!Reply.isOk(placed)) console.warn("capture: place " + placed);
        });
    }

    implicitWidth: Theme.size.panel.lg
    implicitHeight: layout.implicitHeight
    Pane {
        id: layout
        anchors.fill: parent
        container: "window"
        title: "Capture"
        Column {
            width: layout.contentWidth
            spacing: Theme.stack.section

            Tabs {
                id: modeSwitch
                width: parent.width
                model: root.modes
                currentIndex: 0
            }

            Column {
                width: parent.width
                spacing: Theme.stack.group
                TileGroup {
                    id: targetTiles
                    width: parent.width
                    visible: root.mode !== "Text"
                    enabled: !root.recording
                    model: root.currentTargets
                    currentIndex: root.currentTargetIndex
                    onActivated: index => root.chooseTarget(index)
                }
                Label {
                    width: parent.width
                    visible: root.mode === "Text"
                    role: "hint"
                    wrapMode: Text.Wrap
                    text: "Select an area. Its text goes to the clipboard."
                }
                Button {
                    id: primaryAction
                    width: parent.width
                    size: "lg"
                    variant: root.recording ? "danger" : "primary"
                    text: root.primaryText
                    iconName: root.primaryIcon
                    enabled: root.capture.phase !== "stopping"
                    onClicked: root.invoke(root.primaryActionName)
                }
                Label {
                    width: parent.width
                    visible: text !== ""
                    role: "hint"
                    wrapMode: Text.Wrap
                    text: root.problem
                }
            }

            Column {
                width: parent.width
                spacing: Theme.stack.row
                SectionHeader { text: "Persistent Options" }

                Column {
                    width: parent.width
                    spacing: Theme.stack.row
                    visible: root.mode === "Screenshot"
                    FormRow {
                        width: parent.width
                        label: root.fieldLabel("processing")
                        Select {
                            width: parent.width
                            model: root.processingChoices
                            textRole: "label"
                            currentIndex: root.choiceIndex(root.processingChoices, root.setting("processing", "save-copy"))
                            onActivated: index => {
                                root.save("processing", root.processingChoices[index].value);
                                currentIndex = Qt.binding(() => root.choiceIndex(root.processingChoices, root.setting("processing", "save-copy")));
                            }
                        }
                    }
                    FormRow {
                        width: parent.width
                        label: "Delay"
                        Select {
                            width: parent.width
                            model: root.delayChoices
                            textRole: "label"
                            currentIndex: root.choiceIndex(root.delayChoices, root.setting("delay", 0))
                            onActivated: index => {
                                root.save("delay", root.delayChoices[index].value);
                                currentIndex = Qt.binding(() => root.choiceIndex(root.delayChoices, root.setting("delay", 0)));
                            }
                        }
                    }
                    FormRow {
                        width: parent.width
                        label: root.fieldLabel("cursor")
                        Switch {
                            checked: root.setting("cursor", false)
                            onClicked: { root.save("cursor", checked); checked = Qt.binding(() => root.setting("cursor", false)); }
                        }
                    }
                }

                Column {
                    width: parent.width
                    spacing: Theme.stack.row
                    visible: root.mode === "Record"
                    FormRow {
                        width: parent.width
                        label: root.fieldLabel("audio")
                        Select {
                            width: parent.width
                            model: root.audioChoices
                            textRole: "label"
                            currentIndex: root.choiceIndex(root.audioChoices, root.setting("audio", "desktop"))
                            onActivated: index => {
                                root.save("audio", root.audioChoices[index].value);
                                currentIndex = Qt.binding(() => root.choiceIndex(root.audioChoices, root.setting("audio", "desktop")));
                            }
                        }
                    }
                    FormRow {
                        width: parent.width
                        label: root.fieldLabel("quality")
                        Select {
                            width: parent.width
                            model: root.qualityChoices
                            textRole: "label"
                            currentIndex: root.choiceIndex(root.qualityChoices, root.setting("quality", "very_high"))
                            onActivated: index => {
                                root.save("quality", root.qualityChoices[index].value);
                                currentIndex = Qt.binding(() => root.choiceIndex(root.qualityChoices, root.setting("quality", "very_high")));
                            }
                        }
                    }
                    FormRow {
                        width: parent.width
                        label: root.fieldLabel("recordCursor")
                        Switch {
                            checked: root.setting("recordCursor", false)
                            onClicked: { root.save("recordCursor", checked); checked = Qt.binding(() => root.setting("recordCursor", false)); }
                        }
                    }
                    FormRow {
                        width: parent.width
                        label: root.fieldLabel("webcam")
                        Switch {
                            checked: root.setting("webcam", false)
                            onClicked: { root.save("webcam", checked); checked = Qt.binding(() => root.setting("webcam", false)); }
                        }
                    }
                }

                Column {
                    width: parent.width
                    spacing: Theme.stack.row
                    visible: root.mode === "Text"
                    FormRow {
                        width: parent.width
                        label: root.fieldLabel("ocrLanguages")
                        Select {
                            width: parent.width
                            model: root.languageChoices
                            textRole: "label"
                            currentIndex: root.choiceIndex(root.languageChoices, root.setting("ocrLanguages", ""))
                            onActivated: index => {
                                root.save("ocrLanguages", root.languageChoices[index].value);
                                currentIndex = Qt.binding(() => root.choiceIndex(root.languageChoices, root.setting("ocrLanguages", "")));
                            }
                        }
                    }
                    Label {
                        width: parent.width
                        visible: text !== "" && (root.languagesOffered || root.values.languages.tone !== "info")
                        role: "hint"
                        wrapMode: Text.Wrap
                        text: root.values.languages === undefined ? "" : root.values.languages.text
                    }
                    RowAction {
                        visible: root.languagesOffered
                        text: visible ? root.languagesRow.action.label : ""
                        onClicked: root.installLanguages()
                    }
                }

                Column {
                    width: parent.width
                    // One blank body line above the closing line, this
                    // column's row gap included.
                    topPadding: Theme.stack.titleSpace - parent.spacing
                    LinkText {
                        width: parent.width
                        role: "hint"
                        wrapMode: Text.Wrap
                        onPageActivated: (page, tab) => root.shell.surfaces.openPage(page, tab)
                        text: "More options are in [Settings](page:vgs.capture/Settings)."
                    }
                }
            }
        }
    }
}
