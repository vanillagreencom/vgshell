import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Steps.js" as Steps

// One Status row of a plugin's page, drawn from one entry of its manager
// row's `status` (PluginLogic.statusRows) as StatusLines: the entry's label
// beside its value and the entry's hint; the words of the hint the entry's
// `link` names open that address through `openLink`, and a page reference
// in a hint (LinkText), or in an entry's or item's info, asks for its page
// through `openPage`. Beside its value the row draws `action` and
// `asideAction`, the buttons its page reads for the entry on Details
// (Steps.detailButtons), and emits `actionPressed` with the one pressed;
// `actionReply`, the last refusal of their presses, reads in place of the
// entry's own. A presence
// or a state draws as a Badge in the tone the entry carries, a state's
// further lines each as a Badge of that tone under it, and its hint, the
// state's sentence where the state carries one, wrapped under them; a
// text, a count or a time as one line of text, a time through Timestamp;
// an entry the plugin has not published, or published while disabled, as
// "Not reported", or as Checking… for one that waits on the core's first
// system probe while `plugin` is on (Steps.statusView). A presence
// list draws its label and hint alone, "None detected" while the list is
// empty, then one line per item: the item's label, with the info icon of
// its own `info` when it carries one, beside a Badge of its presence, its
// hint, and, for an item that is a secret's presence, Add key
// in the chip's place while nothing is stored, or Replace and Remove after
// the chip (Steps.itemView). On Setup (`setup`), a key list stands under
// the required step it serves, which names it, so it draws its item lines
// alone. Each line is one group of the row's GroupList, divided from the
// next as the rows of a section are. No row takes an edit
// of a value: a key's step goes to the manager through `panel` (D061).
GroupList {
    id: row

    // One entry of a manager row's `status`, or null for a row whose entry
    // left the page's manager row before the row itself goes.
    required property var entry
    // The Settings panel, whose manager calls store and clear a key and
    // whose `replyOf` and `writing` each line reads, and the plugin's id.
    required property Item panel
    required property string pluginId
    // The plugin's `secrets` label, which a line's masked field asks for.
    property string secretLabel: ""
    // The plugin as the page reads it, { enabled, failed }, or undefined,
    // where no start applies, which reads every unpublished entry Not
    // reported. A `var` property with no value reads undefined (Qt 6 qml
    // run, `typeof` of an unset `property var`).
    property var plugin
    property bool setup: false
    // The buttons of Steps.detailButtons, each null for none.
    property var action: null
    property var asideAction: null
    property string actionReply: ""

    signal openLink(var link)
    signal actionPressed(var button)
    signal openPage(string page, string tab)

    // The panel's last refusal or failure of this row's entry, or of
    // ACCOUNT's secret in it, "" for none and while the page is torn down,
    // when `panel` is already null.
    function replyOf(account) {
        return panel === null || entry === null ? "" : panel.replyOf(pluginId, entry.key, account);
    }

    // What the row draws: Steps.statusView of its entry, a time in the
    // shell's one wording of a past moment, which reads Time.now and so
    // moves on with the clock.
    readonly property var view: Steps.statusView(entry, ms => Timestamp.text(ms, Time.now.getTime()), plugin)

    // Whether the row's last line ends in sub-text (StatusLine.subText), so
    // a row that holds it takes the room under it a Field takes.
    readonly property bool subText: itemLines.count > 0 ? itemLines.itemAt(itemLines.count - 1) !== null && itemLines.itemAt(itemLines.count - 1).subText : head.subText

    visible: entry !== null

    StatusLine {
        id: head
        visible: !row.setup
        width: row.width
        label: row.view.label
        hint: row.view.hint
        hintLink: row.view.link === null ? "" : row.view.link.text
        onHintLinkActivated: row.openLink(row.view.link)
        onHintPageActivated: (page, tab) => row.openPage(page, tab)
        onInfoPageActivated: (page, tab) => row.openPage(page, tab)
        info: row.view.info
        tone: row.view.tone
        text: row.view.text
        lines: row.view.lines
        muted: row.view.muted
        error: row.actionReply !== "" ? row.actionReply : row.replyOf()
        actionOffered: row.action !== null
        actionLabel: row.action === null ? "" : row.action.label
        actionTone: row.action === null ? "" : row.action.tone
        actionIcon: row.action === null ? "" : row.action.icon
        onAct: row.actionPressed(row.action)
        asideOffered: row.asideAction !== null
        asideLabel: row.asideAction === null ? "" : row.asideAction.label
        asideTone: row.asideAction === null ? "" : row.asideAction.tone
        asideIcon: row.asideAction === null ? "" : row.asideAction.icon
        onAside: row.actionPressed(row.asideAction)
    }

    Repeater {
        id: itemLines
        model: ScriptModel {
            values: row.view.items
            objectProp: "key"
        }
        StatusLine {
            required property var modelData
            readonly property var presence: Steps.itemView(modelData, row.setup)
            width: row.width
            label: modelData.label
            info: modelData.info
            hint: row.setup && presence.reason !== "" ? presence.reason + (modelData.hint === "" ? "" : ": " + modelData.hint) : modelData.hint
            onHintPageActivated: (page, tab) => row.openPage(page, tab)
            onInfoPageActivated: (page, tab) => row.openPage(page, tab)
            tone: presence.tone
            text: presence.text
            access: modelData.access
            secretLabel: row.secretLabel
            busy: row.panel !== null && row.panel.writing !== ""
            error: row.replyOf(modelData.secret)
            onStoreSecret: value => row.panel.storeSecret(row.pluginId, row.entry.key, modelData.secret, value)
            onClearSecret: row.panel.clearSecret(row.pluginId, row.entry.key, modelData.secret)
        }
    }
}
