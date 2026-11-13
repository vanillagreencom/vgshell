import QtQuick
import qs.Commons
import qs.Ui

// Windows pane: the corner radius and the border width over the theme, each
// Set by theme until the user moves it, and VGlass. The corner radius is one
// base: windows take it, flyouts three quarters of it and grouped window
// tabs half of it (ThemeLogic.APPEARANCE_RATIOS). Both map to a Hyprland
// option, so each row also offers the user's own Hyprland value. Each
// slider runs between the bounds the `appearance` capability lends for its
// value, the judge's own. VGlass is on or off for every glass surface, or each surface's
// own choice, Hyprland's windows being one such surface; the Windows switch
// shows the state Theme.glassOn gives them, and the Glow switch, open only
// while that state is on, adds a glow to the focused window.
FocusScope {
    id: root

    property var shell: null
    property string problem: ""
    readonly property var appearance: shell === null ? null : shell.appearance
    readonly property var layerGlass: shell === null ? null : shell.hyprland.layerGlass
    readonly property bool layerGlassBusy: layerGlass !== null && layerGlass.operation.phase !== "idle"
    readonly property string layerGlassProblem: layerGlass === null ? "" : layerGlass.operation.reason !== ""
        ? layerGlass.operation.reason : ["eligible", "not-loaded", "checking"].indexOf(layerGlass.observed.kind) === -1
            ? layerGlass.observed.reason : ""
    readonly property Item initialFocus: radius.slider

    function open(payloadJson) {}
    function close() {}
    onShellChanged: if (shell !== null) shell.hyprland.refreshLayerGlass()

    function chooseLayerGlass(enabled, rebuild) {
        const done = result => { if (!result.ok) console.warn("windows: layer-glass " + result.reason); };
        const reply = rebuild ? shell.appearance.rebuildLayerGlass("layer-glass", done)
            : shell.appearance.chooseLayerGlass(enabled, "layer-glass", done);
        if (reply !== "ok") console.warn("windows: layer-glass " + reply);
    }

    function answer(reply) {
        problem = reply === "ok" ? "" : "VGS could not save this setting.";
        if (reply !== "ok") console.warn("windows: appearance " + reply);
    }

    function openHyprlandConfig() {
        const reply = shell.tui.edit("hypr/hyprland.lua");
        if (reply !== "ok") console.warn("windows: edit " + reply);
    }

    implicitWidth: Theme.size.window.width
    implicitHeight: content.implicitHeight
    focus: true

    // Where Appearance value KEY comes from, the theme's value and the
    // user's, as the `appearance` capability lends them.
    function sourceOf(key) { return appearance === null ? "theme" : appearance.sources[key]; }
    function themeOf(key) { return appearance === null ? 0 : appearance.theme[key]; }
    function valueOf(key) { return appearance === null ? undefined : appearance.values[key]; }
    function pathOf(key) { return appearance === null ? "" : appearance.keys[key].hyprland; }
    function boundOf(key, bound) { return appearance === null ? 0 : appearance.keys[key][bound]; }

    // The VGlass choices, in the order the select lists them: unset first.
    readonly property var glassChoices: [
        { label: "Each surface decides", value: undefined },
        { label: "On for every glass surface", value: "on" },
        { label: "Off for every glass surface", value: "off" }
    ]
    readonly property bool surfacesDecide: valueOf("glass") === undefined

    Column {
        id: content
        width: root.width
        spacing: Theme.stack.group

        SectionHeader {
            width: parent.width
            text: "Shape"
            description: "Set the corners and borders of windows."
        }

        Column {
            width: parent.width
            spacing: Theme.stack.row

            ValueSourceRow {
                id: radiusRow
                width: parent.width
                label: "Corner radius"
                themeOffered: true
                source: root.sourceOf("windowRadius")
                themeValue: root.themeOf("windowRadius")
                userValue: root.valueOf("windowRadius")
                hyprland: root.shell === null ? null : root.shell.hyprland
                path: root.pathOf("windowRadius")
                formatValue: value => value + " px"
                onUseHyprlandValue: root.answer(root.shell.appearance.set("windowRadius", "hyprland"))
                onUseThemeValue: root.answer(root.shell.appearance.unset("windowRadius"))
                onOpenHyprlandConfig: root.openHyprlandConfig()
                info: "Windows use this radius. Flyouts use three quarters of it. Grouped window tabs use half of it."
                SavedSlider {
                    id: radius
                    width: parent.width
                    from: root.boundOf("windowRadius", "min")
                    to: root.boundOf("windowRadius", "max")
                    formatValue: value => Math.round(value) + " px"
                    shown: radiusRow.shownValue === undefined ? 0 : radiusRow.shownValue
                    onSaved: value => root.answer(root.shell.appearance.set("windowRadius", Math.round(value)))
                }
            }

            ValueSourceRow {
                id: borderRow
                width: parent.width
                label: "Border width"
                themeOffered: true
                source: root.sourceOf("borderWidth")
                themeValue: root.themeOf("borderWidth")
                userValue: root.valueOf("borderWidth")
                hyprland: root.shell === null ? null : root.shell.hyprland
                path: root.pathOf("borderWidth")
                formatValue: value => value + " px"
                onUseHyprlandValue: root.answer(root.shell.appearance.set("borderWidth", "hyprland"))
                onUseThemeValue: root.answer(root.shell.appearance.unset("borderWidth"))
                onOpenHyprlandConfig: root.openHyprlandConfig()
                info: "Use my Hyprland value also keeps the border colours from " + PageReference.fileReference("your Hyprland config", "hypr/hyprland.lua") + "."
                onInfoPageActivated: (page, tab) => root.shell.surfaces.openPage(page, tab)
                SavedSlider {
                    width: parent.width
                    from: root.boundOf("borderWidth", "min")
                    to: root.boundOf("borderWidth", "max")
                    formatValue: value => Math.round(value) + " px"
                    shown: borderRow.shownValue === undefined ? 0 : borderRow.shownValue
                    onSaved: value => root.answer(root.shell.appearance.set("borderWidth", Math.round(value)))
                }
            }
        }

        SectionHeader {
            width: parent.width
            text: "Glass"
            description: "Set frosted glass for the launcher, notifications and windows."
        }

        Column {
            width: parent.width
            spacing: Theme.stack.row

            FormRow {
                width: parent.width
                label: "VGlass"
                info: "The glass surfaces are the launcher, notifications and your windows. Each surface decides: each one uses its own VGlass setting, and the launcher and notifications use glass by default. On or Off for every glass surface sets all of them."
                Select {
                    width: parent.width
                    Accessible.name: "VGlass"
                    model: root.glassChoices
                    textRole: "label"
                    currentIndex: root.glassChoices.findIndex(choice => choice.value === root.valueOf("glass"))
                    onActivated: index => {
                        const wanted = root.glassChoices[index].value;
                        currentIndex = Qt.binding(() => root.glassChoices.findIndex(choice => choice.value === root.valueOf("glass")));
                        root.answer(wanted === undefined ? root.shell.appearance.unset("glass") : root.shell.appearance.set("glass", wanted));
                    }
                }
            }

            FormRow {
                width: parent.width
                label: "Windows"
                info: "On: Hyprland draws your windows with blur, transparency and a shadow. Off: Hyprland keeps the window look from " + PageReference.fileReference("your own Hyprland config", "hypr/hyprland.lua") + ". The VGlass choice above sets this unless each surface decides."
                onInfoPageActivated: (page, tab) => root.shell.surfaces.openPage(page, tab)
                Switch {
                    size: "sm"
                    Accessible.name: "Windows"
                    enabled: root.surfacesDecide
                    checked: Theme.glassOn(root.valueOf("windowGlass") === true)
                    onToggled: {
                        const wanted = checked;
                        checked = Qt.binding(() => Theme.glassOn(root.valueOf("windowGlass") === true));
                        root.answer(wanted ? root.shell.appearance.set("windowGlass", true) : root.shell.appearance.unset("windowGlass"));
                    }
                }
            }

            FormRow {
                width: parent.width
                label: "Glow"
                info: "On: Hyprland draws a soft glow inside your focused window in your theme's colours while Windows glass is on. Off: Hyprland keeps the glow from " + PageReference.fileReference("your own Hyprland config", "hypr/hyprland.lua") + "."
                onInfoPageActivated: (page, tab) => root.shell.surfaces.openPage(page, tab)
                Switch {
                    size: "sm"
                    Accessible.name: "Glow"
                    enabled: Theme.glassOn(root.valueOf("windowGlass") === true)
                    checked: root.valueOf("windowGlow") === true
                    onToggled: {
                        const wanted = checked;
                        checked = Qt.binding(() => root.valueOf("windowGlow") === true);
                        root.answer(wanted ? root.shell.appearance.set("windowGlow", true) : root.shell.appearance.unset("windowGlow"));
                    }
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
                label: "Enabled"
                info: "Adds compositor glass to VGS panels, independently of VGlass. Turning it on offers to install hyprglass. Turning it off unloads the whole plugin, including glass configured outside VGS, and keeps its packages."
                Switch {
                    size: "sm"
                    Accessible.name: "Layer glass"
                    disabledReason: root.layerGlassBusy ? "Finish the current layer-glass request first." : ""
                    checked: root.layerGlass !== null && root.layerGlass.requested
                    onToggled: {
                        const wanted = checked;
                        checked = Qt.binding(() => root.layerGlass !== null && root.layerGlass.requested);
                        root.chooseLayerGlass(wanted, false);
                    }
                }
            }

            FormRow {
                width: parent.width
                label: "Plugin"
                Label {
                    width: parent.width
                    text: root.layerGlassBusy ? "Working…" : root.layerGlass === null || root.layerGlass.observed.stale
                        ? "Checking…" : root.layerGlass.observed.kind === "eligible" ? "On"
                            : root.layerGlass.observed.kind === "not-loaded" ? "Off" : "Needs attention"
                }
            }

            FormRow {
                width: parent.width
                label: ""
                RowActions {
                    width: parent.width
                    RowAction {
                        text: "Check again"
                        disabledReason: root.layerGlassBusy ? "Finish the current layer-glass request first." : ""
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
                        disabledReason: root.layerGlassBusy ? "Finish the current layer-glass request first." : ""
                        onClicked: root.chooseLayerGlass(false, false)
                    }
                }
            }

            Callout {
                visible: root.layerGlassProblem !== ""
                width: parent.width
                tone: "danger"
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
