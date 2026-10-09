import QtQuick
import qs.Commons
import qs.Ui

// Fonts pane: the interface font and the terminal font over the theme, each
// Set by theme until the user chooses one. The interface font is the family
// of the shell's reading text and of its capitals; code and key names keep
// the theme's fixed-width family. The terminal font sets no token: the
// kitty and Ghostty theme targets write it, so it reaches a terminal once a
// theme is applied, and no theme states one, so Set by theme leaves each
// terminal its own font. kitty takes a new family when its configuration
// reloads (kitty 0.49.2, boss.py apply_new_options). Both selects offer
// the families Qt lists.
FocusScope {
    id: root

    property var shell: null
    property string problem: ""
    readonly property var appearance: shell === null ? null : shell.appearance
    // Qt.fontFamilies() answers a string list that is no Array to
    // Array.isArray, which Select counts its model with (a run under
    // qmltestrunner, Qt 6.11.2), so the selects take a copy that is one.
    readonly property var families: Array.from(Qt.fontFamilies())
    readonly property Item initialFocus: interfaceSelect

    function open(payloadJson) {}
    function close() {}

    function answer(reply) {
        problem = reply === "ok" ? "" : "VGS could not save this setting.";
        if (reply !== "ok") console.warn("fonts: appearance " + reply);
    }

    // The families a select offers: Qt's, with SHOWN, the family in effect,
    // first when Qt does not list it, so the select reads it.
    function offers(shown) {
        return typeof shown !== "string" || families.indexOf(shown) !== -1 ? families : [shown].concat(families);
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
                    model: root.offers(interfaceRow.shownValue)
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
                    model: root.offers(terminalRow.shownValue)
                    placeholderText: "Your terminal's font"
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
            visible: root.problem !== ""
            width: parent.width
            role: "hint"
            color: Theme.color.danger
            text: root.problem
            wrapMode: Text.Wrap
        }
    }
}
