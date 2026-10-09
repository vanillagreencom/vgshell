import QtQuick
import qs.Commons
import qs.Ui

FocusScope {
    id: root
    property var shell: null
    property var request: ({ id: "", windows: [], remember: false })
    property int tab: 0
    property int selected: 0
    property bool remember: false
    property var region: ({ x: 0, y: 0, width: 0, height: 0 })
    readonly property bool sharing: typeof request.id === "string" && request.id !== ""
    // ShellScreen dimensions are logical pixels, as xdph's region grammar
    // requires; monitor pixels alone would share the wrong area at scale > 1.
    // https://quickshell.org/docs/v0.3.1/types/Quickshell/ShellScreen
    readonly property var screens: shell === null ? [] : shell.screens.all
    readonly property var rows: tab === 1 ? request.windows : screens
    readonly property var current: rows[selected] || null
    readonly property string output: current === null || tab === 1 ? "" : current.name
    readonly property string address: current === null || tab !== 1 ? "" : current.address
    readonly property bool previewReady: preview.item !== null && preview.item.hasContent
    readonly property rect previewRect: previewReady ? preview.item.contentRect : Qt.rect(0, 0, imageBox.width, imageBox.height)
    readonly property var initialFocus: sharing ? tabs : captureControls.item === null ? null : captureControls.item.initialFocus
    implicitWidth: Theme.size.window.width
    implicitHeight: Theme.size.panel.maxHeight
    focus: true

    function open(payloadJson) {
        const next = JSON.parse(payloadJson);
        if (sharing && request.id !== next.id) close();
        request = next.id === undefined ? { id: "", windows: [], remember: false } : next;
        if (!sharing) return;
        remember = request.remember;
        switchTab(0);
    }
    function close() { if (shell !== null && sharing) shell.ipc.call("share-close", JSON.stringify({ id: request.id })); }
    function select(index) {
        if (selected === index && region.width > 0) return;
        selected = index;
        const screen = screens[index];
        if (tab !== 1 && screen !== undefined) region = { x: 0, y: 0, width: screen.width, height: screen.height };
    }
    // setCurrentIndex preserves Qt's binding for programmatic requests;
    // page keys update root.tab through currentIndexChanged.
    // https://doc.qt.io/qt-6/qml-qtquick-controls-tabbar.html
    function switchTab(index) { tab = index; tabs.setCurrentIndex(index); region = { x: 0, y: 0, width: 0, height: 0 }; select(0); }
    function share() {
        if (current === null) return;
        let choice;
        if (tab === 1) choice = { type: "window", id: current.id, remember: remember };
        else if (tab === 0) choice = { type: "screen", output: output, remember: remember };
        else choice = { type: "region", output: output, x: region.x, y: region.y, width: region.width, height: region.height, remember: remember };
        shell.ipc.call("share-choice", JSON.stringify({ id: request.id, choice: choice }));
    }
    function setRegion(key, value) {
        const next = Object.assign({}, region);
        next[key] = Math.round(value);
        next.width = Math.min(next.width, current.width - next.x);
        next.height = Math.min(next.height, current.height - next.y);
        region = next;
    }

    // Settings Open uses the same Capture controls as the bar's panel.
    Loader {
        id: captureControls
        anchors.fill: parent
        active: !root.sharing
        sourceComponent: Component { Panel { shell: root.shell; surfaceKind: "window" } }
        onLoaded: item.open("{}")
    }

    Pane {
        id: pane
        visible: root.sharing
        anchors.fill: parent
        container: "window"
        title: "Share your screen"
        bodySpacing: Theme.stack.group
        header: Tabs {
            id: tabs
            width: pane.contentWidth
            model: ["Screens", "Windows", "Area"]
            currentIndex: root.tab
            onCurrentIndexChanged: if (currentIndex !== root.tab) root.switchTab(currentIndex)
        }

        Column {
            width: pane.contentWidth
            spacing: Theme.stack.group
            Label {
                id: hint
                width: parent.width
                role: "hint"
                wrapMode: Text.Wrap
                text: root.tab === 2 ? "Drag over the preview, or adjust the area below." : "Choose what the app can see."
            }
            // One live stream shows the selected source. The capability lends
            // its component so plugins create no Wayland capture objects.
            Rectangle {
                id: imageBox
                width: parent.width
                // Keep the chosen source's name above the pinned footer.
                height: Math.min(Theme.size.panel.sm, width * 9 / 16, Math.max(Theme.size.control.lg, pane.bodyRoom - hint.implicitHeight - sources.height - Theme.stack.group * 2))
                color: Theme.color.background
                radius: Theme.surface.radius
                clip: true
                Loader {
                    id: preview
                    anchors.fill: parent
                    sourceComponent: !root.sharing || root.shell === null || root.current === null ? null : root.shell.screencopy.preview
                    onLoaded: {
                        item.output = Qt.binding(() => root.output);
                        item.address = Qt.binding(() => root.address);
                    }
                }
                Label {
                    anchors.centerIn: parent
                    role: "hint"
                    visible: !root.previewReady
                    text: root.current === null ? "No sources available" : "Waiting for preview"
                }
                Rectangle {
                    visible: root.tab === 2 && root.current !== null
                    x: root.current === null ? 0 : root.previewRect.x + root.region.x / root.current.width * root.previewRect.width
                    y: root.current === null ? 0 : root.previewRect.y + root.region.y / root.current.height * root.previewRect.height
                    width: root.current === null ? 0 : root.region.width / root.current.width * root.previewRect.width
                    height: root.current === null ? 0 : root.region.height / root.current.height * root.previewRect.height
                    color: "transparent"
                    border.width: Theme.border.thick
                    border.color: Theme.color.accent
                }
                // keyboard-path: the four sliders below adjust the same area
                MouseArea {
                    x: root.previewRect.x
                    y: root.previewRect.y
                    width: root.previewRect.width
                    height: root.previewRect.height
                    enabled: root.tab === 2 && root.current !== null
                    property real startX: 0
                    property real startY: 0
                    PointerCursor {}
                    onPressed: mouse => { startX = mouse.x; startY = mouse.y; }
                    onPositionChanged: mouse => {
                        if (!pressed) return;
                        const a = Math.max(0, Math.min(width, mouse.x));
                        const b = Math.max(0, Math.min(height, mouse.y));
                        const x = Math.floor(Math.min(startX, a) / width * root.current.width);
                        const y = Math.floor(Math.min(startY, b) / height * root.current.height);
                        root.region = { x: x, y: y, width: Math.max(1, Math.floor(Math.abs(a - startX) / width * root.current.width)), height: Math.max(1, Math.floor(Math.abs(b - startY) / height * root.current.height)) };
                    }
                }
            }
            // focus-indicator: the list's FocusRing surrounds its one Tab stop
            FocusScope {
                id: sources
                width: parent.width
                height: sourceColumn.implicitHeight
                activeFocusOnTab: true
                Keys.onPressed: event => { event.accepted = sourceKeys.handle(event); }
                KeyNav {
                    id: sourceKeys
                    count: root.rows.length
                    currentIndex: root.selected
                    cursor: sourceCursor
                    onMoved: index => root.select(index)
                    onActivated: index => root.share()
                }
                ListCursor { id: sourceCursor }
                Column {
                    id: sourceColumn
                    width: parent.width
                    Repeater {
                        model: root.rows
                        // keyboard-path: sourceKeys moves and activates the list's selection
                        ListItem {
                            required property int index
                            required property var modelData
                            width: sourceColumn.width
                            text: root.tab === 1 ? modelData.title : modelData.name
                            secondary: root.tab === 1 ? modelData.class : modelData.width + " × " + modelData.height + (modelData.model && modelData.model !== modelData.name ? " · " + modelData.model : "")
                            iconName: root.tab === 1 ? "app-window" : "monitor"
                            cursor: sourceCursor
                            highlighted: index === root.selected
                            focusPolicy: Qt.NoFocus
                            onPointed: root.select(index)
                            onClicked: { sources.forceActiveFocus(Qt.MouseFocusReason); root.select(index); }
                        }
                    }
                }
                FocusRing { target: sources; targetRadius: Theme.listItem.radius }
            }
            Column {
                id: areaControls
                width: pane.contentWidth
                visible: root.tab === 2 && root.current !== null
                spacing: Theme.stack.row
                Repeater {
                    model: [{ key: "x", label: "Left" }, { key: "y", label: "Top" }, { key: "width", label: "Width" }, { key: "height", label: "Height" }]
                    FormRow {
                        id: areaField
                        required property var modelData
                        width: areaControls.width
                        label: modelData.label + " · " + root.region[modelData.key]
                        Slider {
                            width: Math.min(areaField.valueRoom, Theme.control.maxWidth)
                            from: modelData.key === "width" || modelData.key === "height" ? 1 : 0
                            to: root.current === null ? 1 : modelData.key === "x" ? root.current.width - 1 : modelData.key === "y" ? root.current.height - 1 : modelData.key === "width" ? root.current.width - root.region.x : root.current.height - root.region.y
                            stepSize: 1
                            value: root.region[modelData.key]
                            onMoved: root.setRegion(modelData.key, value)
                        }
                    }
                }
            }
        }
        footer: Column {
            width: pane.contentWidth
            spacing: Theme.stack.group
            Checkbox { text: "Remember this choice"; checked: root.remember; onToggled: root.remember = checked }
            Row {
                spacing: Theme.stack.inline
                Button { text: "Cancel"; variant: "tertiary"; onClicked: root.shell.surfaces.hide("window") }
                Button { text: "Share"; iconName: "screen-share"; variant: "primary"; enabled: root.current !== null; onClicked: root.share() }
            }
        }
    }
}
