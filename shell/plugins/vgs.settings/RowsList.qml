import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Steps.js" as Steps

// A `rows` status entry of a plugin's page (PluginLogic.statusRows) as a
// section of its own, the list full width under its label: one ListItem per
// published row, led by the entry's `icon`, with the row's label, its
// secondary line and, at its end, its state, as plain text for a calm state
// and as a chip for one that needs the user (`chip`), then its row actions.
// A row takes no click (ListItem's `clickable` is false), so it draws no hover, no press
// and no pointing hand; each row action is a RowAction with its own hover,
// pointer, keyboard focus and click. A danger action that removes its row
// draws the trash mark alone (RowAction's `removesItem`), its text, which
// names the row, its tooltip and accessible name. The rows are the groups
// of one GroupList, divided as a section's groups are. Under the list stand
// "None yet" or "Not reported" while it shows no row, the entry's action on
// the whole list, such as Add, its hint, whose `link` words open an address
// through `openLink` and whose page reference opens a page through the
// section's `pageActivated`, and `reply`, the refusal of the last press
// on the list, in the error colour. While the plugin is off the list reads
// so, with Turn on under it (Steps.rowsView). A press records its line
// action in `lastPress` and emits `pressed` with it, which the page routes
// and whose reply it hands back.
Section {
    id: root

    // One `rows` entry of a manager row's `status`, or null for an entry
    // that left the row before the section goes.
    required property var entry
    // The plugin the page shows, { enabled, name } (PluginPage.plugin).
    required property var plugin
    // The line action of the last press on the list, null before one, and
    // the page's reply to it, "" for none.
    property var lastPress: null
    property string reply: ""

    signal pressed(var button)
    signal openLink(var link)

    function press(button) {
        lastPress = button;
        pressed(button);
    }

    readonly property var view: entry === null ? ({ rows: [], add: null, text: "" }) : Steps.rowsView(entry, plugin)

    visible: entry !== null
    title: entry === null ? "" : entry.label
    info: entry === null ? "" : entry.info

    GroupList {
        id: list
        width: root.width
        visible: root.view.rows.length > 0

        Repeater {
            model: ScriptModel {
                values: root.view.rows
                objectProp: "key"
            }
            // The text sits on the content edge, as the section's other
            // lines do: a row that takes no click draws no box to inset.
            // A trash mark drawn alone ends its ink on the content edge
            // too, as a list item's does (ListField), so its square, whose
            // hit target and focus ring reach past the mark, stands past
            // that edge by `overhang`.
            ListItem {
                id: line
                required property var modelData
                width: list.width
                leftPadding: 0
                rightPadding: -actions.overhang
                clickable: false
                iconName: root.entry === null ? "" : root.entry.icon
                text: modelData.label
                secondary: modelData.secondary
                trailing: [
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !line.modelData.chip && text !== ""
                        role: "itemHint"
                        text: line.modelData.state
                    },
                    Badge {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: line.modelData.chip
                        text: line.modelData.state
                        tone: line.modelData.tone === "" ? "neutral" : line.modelData.tone
                    },
                    RowActions {
                        id: actions
                        // How far the last action's square reaches past
                        // its ink, RowAction's `glyphEnd`: 0 for any
                        // action but a trash mark drawn alone.
                        readonly property real overhang: shown.length === 0 ? 0 : shown[shown.length - 1].glyphEnd
                        anchors.verticalCenter: parent.verticalCenter
                        Repeater {
                            // Keyed, so a status write elsewhere, which hands
                            // the page new objects, keeps each action and the
                            // keyboard focus it holds.
                            model: ScriptModel { values: line.modelData.buttons; objectProp: "key" }
                            RowAction {
                                required property var modelData
                                text: modelData.text
                                tone: modelData.tone === "" ? "accent" : modelData.tone
                                markName: modelData.icon
                                removesItem: modelData.removesItem
                                onClicked: root.press(modelData)
                            }
                        }
                    }
                ]
            }
        }
    }

    Label {
        width: root.width
        visible: text !== ""
        role: "itemHint"
        text: root.view.text
    }

    RowAction {
        visible: root.view.add !== null
        text: root.view.add === null ? "" : root.view.add.label
        tone: root.view.add === null || root.view.add.tone === "" ? "accent" : root.view.add.tone
        markName: root.view.add === null ? "" : root.view.add.icon
        onClicked: root.press(root.view.add)
    }

    LinkText {
        width: root.width
        visible: root.entry !== null && root.entry.hint !== ""
        role: "hint"
        text: root.entry === null ? "" : root.entry.hint
        link: root.entry === null || root.entry.link === null ? "" : root.entry.link.text
        color: Theme.text.hint.color
        wrapMode: Text.Wrap
        onActivated: root.openLink(root.entry.link)
        onPageActivated: (page, tab) => root.pageActivated(page, tab)
    }

    Label {
        width: root.width
        visible: text !== ""
        role: "hint"
        color: Theme.color.danger
        text: root.reply
        wrapMode: Text.Wrap
    }
}
