import QtQuick
import qs.Commons
import qs.Ui

// Glass pane: the main switch, the style and the surfaces glass appears
// on, which the one deciding place reads (ThemeLogic.glassFor), and the
// compositor's layer glass. Each choice is one shell.json `appearance` key
// written through capability `appearance`: `glassEnabled` and `glassStyle`
// unset at their defaults, `glassSurfaces` holding only the rows that
// differ from their default. A row edit also clears that row's choice kept
// by the version 7 conversion (`glassRememberedChoices`), which Restore
// moves back into the rows. Controls follow the card they lie on and save
// nothing. Layer glass keeps its install, check and rebuild route.
FocusScope {
    id: root

    property var shell: null
    property string problem: ""
    readonly property var appearance: shell === null ? null : shell.appearance
    readonly property var values: appearance === null ? ({}) : appearance.values
    readonly property bool glassOn: values.glassEnabled !== false
    readonly property var saved: values.glassSurfaces === undefined ? ({}) : values.glassSurfaces
    readonly property var remembered: values.glassRememberedChoices === undefined ? ({}) : values.glassRememberedChoices
    readonly property var layerGlass: shell === null ? null : shell.hyprland.layerGlass
    readonly property bool layerGlassBusy: layerGlass !== null && layerGlass.operation.phase !== "idle"
    readonly property bool layerGlassWaiting: layerGlass !== null && layerGlass.operation.phase === "verifying"
        && layerGlass.observed.kind === "shaders-pending"
    readonly property string layerGlassProblem: layerGlass === null ? "" : layerGlass.operation.reason !== ""
        ? layerGlass.operation.reason : ["eligible", "not-loaded", "checking"].indexOf(layerGlass.observed.kind) === -1
            ? layerGlass.observed.reason : ""
    readonly property bool layerGlassRecovery: layerGlass !== null && (layerGlassBusy || layerGlassProblem !== ""
        || (layerGlass.requested && (layerGlass.observed.stale || layerGlass.observed.kind !== "eligible"))
        || (layerGlass.observed.loaded === true && !layerGlass.requested))
    readonly property string offReason: glassOn ? "" : "Turn on Glass first."
    readonly property Item initialFocus: mainSwitch

    // The styles, in the order the select lists them. Auto is the unset
    // key; it has a value of its own so the select can match it, and that
    // value is never written.
    readonly property var styles: [
        { label: "Auto", value: "auto" },
        { label: "Light", value: "light" },
        { label: "Dark", value: "dark" },
        { label: "Clear", value: "clear" }
    ]
    // The rows a user turns on or off, as ThemeLogic.GLASS_SURFACES names
    // them, in the order the page lists them, each with its default.
    readonly property var rows: [
        { id: "windows", label: "Windows", on: false, info: "On: Hyprland draws your windows with blur, transparency and a shadow. Off: Hyprland keeps the window look from " + PageReference.fileReference("your own Hyprland config", "hypr/hyprland.lua") + "." },
        { id: "tooltips", label: "Tooltips", on: false, info: "Tooltips keep a solid ground in every style, so their text reads on any background." },
        { id: "flyouts", label: "Widget flyouts", on: false, info: "" },
        { id: "menus", label: "Menus", on: false, info: "Menus include the list a choice opens." },
        { id: "launcher", label: "Launcher", on: true, info: "" },
        { id: "notifications", label: "Notifications", on: true, info: "" },
        { id: "jarvis", label: "Jarvis", on: true, info: "Jarvis's cards take glass. The orb never does." },
        { id: "dialogs", label: "Dialogs", on: false, info: "" },
        { id: "indicators", label: "On-screen indicators", on: false, info: "On-screen indicators include the volume and brightness levels and the display messages." },
        { id: "clipboard", label: "Clipboard", on: false, info: "" }
    ]
    readonly property string styleShown: typeof values.glassStyle === "string" ? values.glassStyle : "auto"
    readonly property bool clearWaits: glassOn && Theme.glassStyle === "clear" && !Theme.layerGlassReady

    function open(payloadJson) {}
    function close() {}
    onShellChanged: if (shell !== null) shell.hyprland.refreshLayerGlass()

    function answer(reply) {
        problem = reply === "ok" ? "" : "VGS could not save this setting.";
        if (reply !== "ok") console.warn("glass: appearance " + reply);
    }

    function write(key, value) {
        return value === undefined ? appearance.unset(key) : appearance.set(key, value);
    }

    // The saved map with ROW at ON, holding only rows off their default,
    // or undefined for none.
    function surfacesWith(row, on) {
        const next = Object.assign({}, saved);
        if (on === row.on) delete next[row.id];
        else next[row.id] = on ? "on" : "off";
        return Object.keys(next).length > 0 ? next : undefined;
    }

    function isOn(row) {
        return saved[row.id] === undefined ? row.on : saved[row.id] === "on";
    }

    function choose(row, on) {
        let reply = write("glassSurfaces", surfacesWith(row, on));
        if (reply === "ok" && remembered[row.id] !== undefined) {
            const kept = Object.assign({}, remembered);
            delete kept[row.id];
            reply = write("glassRememberedChoices", Object.keys(kept).length > 0 ? kept : undefined);
        }
        answer(reply);
    }

    function restore() {
        const next = Object.assign({}, saved, remembered);
        let reply = write("glassSurfaces", next);
        if (reply === "ok") reply = write("glassRememberedChoices", undefined);
        answer(reply);
    }

    function chooseLayerGlass(enabled, rebuild) {
        const done = result => { if (!result.ok) console.warn("glass: layer-glass " + result.reason); };
        const reply = rebuild ? shell.appearance.rebuildLayerGlass("layer-glass", "layer-glass-control", done)
            : shell.appearance.chooseLayerGlass(enabled, "layer-glass", "layer-glass-control", done);
        if (reply !== "ok") console.warn("glass: layer-glass " + reply);
    }

    implicitWidth: Theme.size.window.width
    implicitHeight: content.implicitHeight
    focus: true

    Column {
        id: content
        width: root.width
        spacing: Theme.stack.group

        Column {
            width: parent.width
            spacing: Theme.stack.row

            FormRow {
                width: parent.width
                label: "Glass"
                info: "Off: every surface draws solid. Your choices below stay saved."
                Switch {
                    id: mainSwitch
                    objectName: "glassMain"
                    size: "sm"
                    Accessible.name: "Glass"
                    checked: root.glassOn
                    onToggled: {
                        const wanted = checked;
                        checked = Qt.binding(() => root.glassOn);
                        root.answer(root.write("glassEnabled", wanted ? undefined : false));
                    }
                }
            }

            FormRow {
                width: parent.width
                label: "Style"
                info: "Auto: light glass on a light theme and dark glass on a dark theme. Clear shows the background through the glass and shades it under white text."
                Select {
                    objectName: "glassStyle"
                    Accessible.name: "Style"
                    disabledReason: root.offReason
                    model: root.styles
                    textRole: "label"
                    currentIndex: root.styles.findIndex(style => style.value === root.styleShown)
                    onActivated: index => {
                        const wanted = root.styles[index].value;
                        currentIndex = Qt.binding(() => root.styles.findIndex(style => style.value === root.styleShown));
                        root.answer(root.write("glassStyle", wanted === "auto" ? undefined : wanted));
                    }
                }
            }

            Callout {
                level: "raised"
                visible: root.clearWaits
                width: parent.width
                tone: "info"
                text: "Clear needs layer glass. Until it is on, Clear surfaces draw on a solid ground."
            }
        }

        SectionHeader {
            width: parent.width
            text: "Where glass appears"
        }

        Column {
            id: surfaceOptions
            width: parent.width
            spacing: Theme.stack.row

            Repeater {
                model: root.rows

                FormRow {
                    required property var modelData
                    width: surfaceOptions.width
                    label: modelData.label
                    info: modelData.info
                    onInfoPageActivated: (page, tab) => root.shell.surfaces.openPage(page, tab)
                    Switch {
                        objectName: "glass-" + modelData.id
                        size: "sm"
                        Accessible.name: modelData.label
                        disabledReason: root.offReason
                        checked: root.isOn(modelData)
                        onToggled: {
                            const wanted = checked;
                            checked = Qt.binding(() => root.isOn(modelData));
                            root.choose(modelData, wanted);
                        }
                    }
                }
            }

            FormRow {
                width: parent.width
                label: "Glow"
                info: "On: Hyprland draws a soft glow inside your focused window in your theme's colours while Windows has glass. Off: Hyprland keeps the glow from " + PageReference.fileReference("your own Hyprland config", "hypr/hyprland.lua") + "."
                onInfoPageActivated: (page, tab) => root.shell.surfaces.openPage(page, tab)
                Switch {
                    size: "sm"
                    Accessible.name: "Glow"
                    disabledReason: root.glassOn && root.isOn(root.rows[0]) ? "" : "Turn on glass for Windows first."
                    checked: root.values.windowGlow === true
                    onToggled: {
                        const wanted = checked;
                        checked = Qt.binding(() => root.values.windowGlow === true);
                        root.answer(root.write("windowGlow", wanted ? true : undefined));
                    }
                }
            }

            FormRow {
                width: parent.width
                label: "Controls"
                info: "Buttons, switches and fields take the look of the card they are on."
                Label {
                    width: parent.width
                    text: "Follows its card"
                }
            }

            FormRow {
                visible: Object.keys(root.remembered).length > 0
                width: parent.width
                label: ""
                RowAction {
                    text: "Restore saved surface choices"
                    onClicked: root.restore()
                }
            }
        }

        SectionHeader {
            width: parent.width
            text: "Layer glass"
        }

        Column {
            width: parent.width
            spacing: Theme.stack.row

            FormRow {
                width: parent.width
                label: "Layer glass"
                info: "Hyprland bends the background at the edges of Jarvis, notifications and the launcher, and shades Clear glass. On offers to install hyprglass."
                Switch {
                    size: "sm"
                    Accessible.name: "Layer glass"
                    disabledReason: root.layerGlassBusy && !root.layerGlassWaiting ? "Finish the current layer-glass request first." : ""
                    checked: root.layerGlass !== null && (root.layerGlass.requested || root.layerGlassWaiting)
                    onToggled: {
                        const wanted = checked;
                        checked = Qt.binding(() => root.layerGlass !== null && (root.layerGlass.requested || root.layerGlassWaiting));
                        root.chooseLayerGlass(wanted, false);
                    }
                }
            }

            FormRow {
                visible: root.layerGlassRecovery
                width: parent.width
                label: "Status"
                Label {
                    width: parent.width
                    text: root.layerGlassWaiting ? "Waiting for a panel" : root.layerGlassBusy ? "Working…" : root.layerGlass === null || root.layerGlass.observed.stale
                        ? "Checking…" : root.layerGlass.observed.kind === "eligible" ? "On"
                            : root.layerGlass.observed.kind === "not-loaded" ? "Off" : "Needs attention"
                }
            }

            FormRow {
                visible: root.layerGlassRecovery
                width: parent.width
                label: ""
                RowActions {
                    width: parent.width
                    RowAction {
                        text: "Check again"
                        disabledReason: root.layerGlassBusy && !root.layerGlassWaiting ? "Finish the current layer-glass request first." : ""
                        onClicked: root.shell.hyprland.refreshLayerGlass()
                    }
                    RowAction {
                        visible: root.layerGlass !== null && (root.layerGlass.requested || root.layerGlass.observed.loaded === true)
                            && root.layerGlass.observed.kind !== "eligible"
                        text: "Rebuild"
                        disabledReason: root.layerGlassBusy ? "Finish the current layer-glass request first." : ""
                        onClicked: root.chooseLayerGlass(true, true)
                    }
                    RowAction {
                        visible: root.layerGlass !== null && root.layerGlass.observed.loaded === true && !root.layerGlass.requested
                        text: "Turn off"
                        disabledReason: root.layerGlassBusy && !root.layerGlassWaiting ? "Finish the current layer-glass request first." : ""
                        onClicked: root.chooseLayerGlass(false, false)
                    }
                }
            }

            Callout {
                level: "raised"
                visible: root.layerGlassProblem !== ""
                width: parent.width
                tone: root.layerGlass !== null && root.layerGlass.operation.reason === "" && root.layerGlass.observed.kind === "shaders-pending" ? "info" : "danger"
                text: root.layerGlassProblem
                plain: true
            }
        }

        Label {
            visible: root.problem !== ""
            width: parent.width
            role: "hint"
            color: Theme.color.danger
            text: root.problem
            wrapMode: Text.Wrap
        }
    }
}
