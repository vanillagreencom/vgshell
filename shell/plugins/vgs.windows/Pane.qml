import QtQuick
import qs.Commons
import qs.Ui

// Windows pane: the corner radius and the border width over the theme, each
// Set by theme until the user moves it, and VGlass. The corner radius is one
// base: windows take it, flyouts three quarters of it and grouped window
// tabs half of it (ThemeLogic.APPEARANCE_RATIOS). Both map to a Hyprland
// option, so each row also offers the user's own Hyprland value. Each
// slider runs between the bounds the `appearance` capability lends for its
// value, the judge's own. VGlass is on or off everywhere, or each surface's
// own choice, Hyprland's windows being one such surface; the Windows switch
// shows the state Theme.glassOn gives them.
FocusScope {
    id: root

    property var shell: null
    property string problem: ""
    readonly property var appearance: shell === null ? null : shell.appearance
    readonly property Item initialFocus: radius.slider

    function open(payloadJson) {}
    function close() {}

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
        { label: "On everywhere", value: "on" },
        { label: "Off everywhere", value: "off" }
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
                info: "Use my Hyprland value also keeps the border colours from your Hyprland config."
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
            description: "Set frosted glass for shell surfaces and windows."
        }

        Column {
            width: parent.width
            spacing: Theme.stack.row

            FormRow {
                width: parent.width
                label: "VGlass"
                info: "Each surface decides: each surface uses its own VGlass setting. The launcher and notifications use glass by default. On everywhere and Off everywhere set all surfaces and your windows."
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
                info: "On: Hyprland draws your windows with blur, transparency and a shadow. Off: Hyprland keeps the window look from your own Hyprland config. The VGlass choice above sets this unless each surface decides."
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
