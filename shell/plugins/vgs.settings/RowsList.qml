import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Steps.js" as Steps

// A `rows` status entry of a plugin's page (PluginLogic.statusRows) as a
// section of its own, the list full width under its label: one ContentRow
// per published row, led by the entry's `icon`, with the row's label and,
// stacked under it, its state with its tone's mark, its secondary line and
// a small button for each row action, and its removing action in the row's
// menu, whose entry is the action's label alone (Steps.rowsView, ContentRow). A row with
// a declared folder opens it through the page's file-reference route;
// ListCursor owns its hover and keyboard-focus plate. Other rows stay
// passive and draw no plate. Each row action keeps its own focus and click,
// which opens no folder. The rows are the groups of one GroupList, divided
// as a section's groups are. Under the list stand "None yet" or "Not
// reported" while it shows no row, the entry's action on the whole list,
// such as Add, its hint, whose `link` words open an address through
// `openLink` and whose page reference opens a page through the section's
// `pageActivated`, and `reply`, the refusal of the last press on the list,
// in the error colour. While the plugin is off the list reads so, with Turn
// on under it (Steps.rowsView). A press records its line action in
// `lastPress` and emits `pressed` with it, which the page routes and whose
// reply it hands back.
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
    rowSpacing: Theme.stack.heading

    GroupList {
        id: list
        // The list ends at its last row's drawn ink, so what stands under
        // it, its action or its hint, stands `stack.heading` below that ink,
        // as the token measures, whatever box or plate the row draws. The
        // ink is floored, as ClearingInset floors it, so the list keeps a
        // whole-pixel height and the page under it scrolls in whole pixels.
        readonly property Item lastRow: rows.count > 0 ? rows.itemAt(rows.count - 1) : null
        width: root.width
        visible: root.view.rows.length > 0
        height: implicitHeight - (lastRow === null ? 0 : Math.floor(lastRow.drawnInkBelow))

        Repeater {
            id: rows
            model: ScriptModel {
                values: root.view.rows
                objectProp: "key"
            }
            ContentRow {
                id: line
                required property var modelData
                width: list.width
                clickable: modelData.folder !== ""
                cursor: clickable ? plate : null
                focusPolicy: clickable ? Qt.StrongFocus : Qt.NoFocus
                highlighted: clickable && visualFocus
                onActiveFocusChanged: if (activeFocus) plate.disarm()
                Keys.onReturnPressed: if (clickable) clicked()
                Keys.onEnterPressed: if (clickable) clicked()
                onClicked: if (clickable) root.pageActivated("file:" + encodeURIComponent(modelData.folder + "/"), "")
                iconName: root.entry === null ? "" : root.entry.icon
                text: modelData.label
                status: modelData.state
                statusTone: modelData.tone
                detail: modelData.secondary
                actions: modelData.buttons
                menuActions: modelData.menu
                onActionTriggered: action => root.press(action)
                onMenuActionTriggered: action => root.press(action)
            }
        }
    }

    ListCursor { id: plate; parent: list }
    onViewChanged: plate.rebuilt()

    Label {
        width: root.width
        visible: text !== ""
        role: "itemHint"
        text: root.view.text
    }

    Column {
        width: root.width
        spacing: Theme.stack.row
        Button {
            visible: root.view.add !== null
            variant: "secondary"
            text: root.view.add === null ? "" : root.view.add.label
            iconName: root.view.add === null ? "" : root.view.add.icon
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
}
