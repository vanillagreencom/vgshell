import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "FontsLogic.js" as Fonts

// Fonts pane: the interface font and the terminal font over the theme, each
// Set by theme until the user chooses one. The interface font is the family
// of the shell's reading text and of its capitals; code and key names keep
// the theme's fixed-width family. The terminal font sets no token: the
// kitty and Ghostty theme targets write it, so it reaches a terminal once a
// theme is applied, and no theme states one, so Set by theme leaves each
// terminal its own font. kitty takes a new family when its configuration
// reloads (kitty 0.49.2, boss.py apply_new_options). The interface select
// offers the families Qt lists less the style names fontconfig lists, so
// each family shows once, and the terminal select those of them that are
// the family of a fixed-width font that draws printable ASCII, so no icon
// or emoji font is offered.
FocusScope {
    id: root

    property var shell: null
    property string problem: ""
    readonly property var appearance: shell === null ? null : shell.appearance
    // Qt.fontFamilies() answers a string list that is no Array to
    // Array.isArray, which Select counts its model with (a run under
    // qmltestrunner, Qt 6.11.2), so the selects take a copy that is one.
    readonly property var families: Array.from(Qt.fontFamilies())
    // fontconfig's fonts: `reading` until the pane's one read ends, then
    // `read` with the fonts, or `failed`.
    property var fonts: ({ state: "reading", list: [] })
    readonly property var interfaceFamilies: Fonts.families(families, fonts.list)
    readonly property var terminalFamilies: Fonts.terminal(families, fonts.list)
    readonly property Item initialFocus: interfaceSelect

    function open(payloadJson) {}
    function close() {}

    function answer(reply) {
        problem = reply === "ok" ? "" : "VGS could not save this setting.";
        if (reply !== "ok") console.warn("fonts: appearance " + reply);
    }

    // One read a pane, in a process of its own, so the UI thread never
    // waits for fontconfig. The format prints one line a font: its spacing,
    // `100` for fixed-width and empty when the font has no spacing element,
    // then its charset only when it has one, then each name of the font as
    // fontconfig holds it, the family first, a tab before each; the default
    // output joins a font's names with commas and puts a backslash before a
    // hyphen or a comma inside one. Every font is listed, no pattern, so a
    // style name of any font leaves the interface list (FcPatternFormat,
    // fc-pattern, fontconfig 2.18.3).
    Process {
        // The run's exit, { code, status }, null until `exited` arrives: a
        // command that fails to start emits `runningChanged` alone.
        property var completion: null

        command: ["fc-list", "--format", "%{spacing}\\t%{?spacing{%{charset}}{}}%{[]family{\\t%{family}}}\\n"]
        running: true
        stdout: StdioCollector { id: fontsOut }
        stderr: StdioCollector { id: fontsErr }
        onExited: (code, status) => { completion = { code: code, status: status }; }
        onRunningChanged: {
            if (running) return;
            if (completion !== null && completion.code === 0 && completion.status === 0) {
                root.fonts = { state: "read", list: Fonts.listed(fontsOut.text) };
                return;
            }
            root.fonts = { state: "failed", list: [] };
            console.warn("fonts: fc-list=unread " + JSON.stringify(completion) + " " + fontsErr.text.trim().split("\n")[0]);
        }
    }

    implicitWidth: Theme.size.window.width
    implicitHeight: content.implicitHeight
    focus: true

    // Where Appearance value KEY comes from, the theme's value and the
    // user's, as the `appearance` capability lends them.
    function sourceOf(key) { return appearance === null ? "theme" : appearance.sources[key]; }
    function themeOf(key) { return appearance === null ? undefined : appearance.theme[key]; }
    function valueOf(key) { return appearance === null ? undefined : appearance.values[key]; }

    Column {
        id: content
        width: root.width
        spacing: Theme.stack.group

        SectionHeader {
            width: parent.width
            text: "Fonts"
            description: "Set the font of the shell and of your terminals."
        }

        Column {
            width: parent.width
            spacing: Theme.stack.row

            ValueSourceRow {
                id: interfaceRow
                width: parent.width
                label: "Interface"
                info: "The text of the shell. Code and key names keep the theme's fixed-width font. The launcher and notifications keep their own fonts."
                themeOffered: true
                source: root.sourceOf("interfaceFont")
                themeValue: root.themeOf("interfaceFont")
                userValue: root.valueOf("interfaceFont")
                onUseThemeValue: root.answer(root.shell.appearance.unset("interfaceFont"))

                Select {
                    id: interfaceSelect
                    width: parent.width
                    Accessible.name: "Interface font"
                    model: Fonts.offers(root.interfaceFamilies, interfaceRow.shownValue)
                    currentIndex: model.indexOf(interfaceRow.shownValue)
                    onActivated: index => {
                        const wanted = model[index];
                        currentIndex = Qt.binding(() => model.indexOf(interfaceRow.shownValue));
                        root.answer(root.shell.appearance.set("interfaceFont", wanted));
                    }
                }
            }

            ValueSourceRow {
                id: terminalRow
                width: parent.width
                label: "Terminal"
                info: "The font of Kitty and Ghostty. Kitty changes at once. In Ghostty, open a new window if the font does not change. Without a font here, each terminal keeps the font from its own config."
                themeOffered: true
                source: root.sourceOf("terminalFont")
                userValue: root.valueOf("terminalFont")
                formatValue: value => value === undefined ? "no terminal font" : String(value)
                onUseThemeValue: root.answer(root.shell.appearance.unset("terminalFont"))

                Select {
                    width: parent.width
                    Accessible.name: "Terminal font"
                    model: Fonts.offers(root.terminalFamilies, terminalRow.shownValue)
                    placeholderText: "Your terminal's font"
                    emptyText: root.fonts.state === "read" ? "No fixed-width fonts" : ""
                    currentIndex: model.indexOf(terminalRow.shownValue)
                    onActivated: index => {
                        const wanted = model[index];
                        currentIndex = Qt.binding(() => model.indexOf(terminalRow.shownValue));
                        root.answer(root.shell.appearance.set("terminalFont", wanted));
                    }
                }
            }
        }

        // The targets render at a theme apply: a shell that has applied no
        // theme has wired no terminal.
        Label {
            visible: Theme.fileState === "absent"
            width: parent.width
            role: "hint"
            text: "Apply a theme in Themes to use the terminal font."
            wrapMode: Text.Wrap
        }

        Label {
            visible: root.fonts.state === "failed"
            width: parent.width
            role: "hint"
            color: Theme.color.danger
            text: "VGS could not read the system's fonts."
            wrapMode: Text.Wrap
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
