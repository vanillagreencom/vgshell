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
// alone. Beside its Settings field (`settingsContext`), a stored key list
// draws no head either, since the field names what its keys are for: each
// key reads as plain text, and while the list has no key to draw, its one
// sentence (Steps.keyListView) stands under the field. A key of a list
// that declares a `sourceAction` offers it under its hint while the
// plugin is on, which the manager opens for that key's account
// (`panel.actSource`); its refusal reads under the key apart from the
// key's own write. Each line is one group of the row's GroupList, divided from the
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
    // Whether the row is a stored key list beside its Settings field, which
    // needs `plugin`.
    property bool settingsContext: false
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
    // The panel's last refusal of ACCOUNT's source action, "" for none.
    function sourceReplyOf(account) {
        return panel === null || entry === null ? "" : panel.replyOf(pluginId, entry.key, panel.sourceKey(account));
    }
    // Which write of ACCOUNT runs: "store", "clear" or "".
    function writingOf(account) {
        return panel === null || entry === null || panel.writing === null || panel.writing.step !== panel.stepKey(pluginId, entry.key, account) ? "" : panel.writing.verb;
    }

    // What the row draws: Steps.statusView of its entry, a time in the
    // shell's one wording of a past moment, which reads Time.now and so
    // moves on with the clock.
    readonly property var view: Steps.statusView(entry, ms => Timestamp.text(ms, Time.now.getTime()), plugin)
    // What the row draws of a stored key list beside its Settings field.
    readonly property var keys: settingsContext && entry !== null ? Steps.keyListView(entry, plugin) : null
    // The key's source action, offered while the plugin is on.
    readonly property string sourceLabel: entry === null || entry.sourceAction === null || (plugin !== undefined && !plugin.enabled) ? "" : entry.sourceAction.label

    // Whether the row's last line ends in sub-text (StatusLine.subText), so
    // a row that holds it takes the room under it a Field takes.
    readonly property bool subText: itemLines.count > 0 ? itemLines.itemAt(itemLines.count - 1) !== null && itemLines.itemAt(itemLines.count - 1).subText : head.subText

    visible: entry !== null

    StatusLine {
        id: head
        visible: !row.setup && (row.keys === null || row.keys.note !== "")
        width: row.width
        label: row.keys === null ? row.view.label : ""
        hint: row.keys === null ? row.view.hint : row.keys.note
        hintLink: row.keys !== null || row.view.link === null ? "" : row.view.link.text
        onHintLinkActivated: row.openLink(row.view.link)
        onHintPageActivated: (page, tab) => row.openPage(page, tab)
        onInfoPageActivated: (page, tab) => row.openPage(page, tab)
        info: row.keys === null ? row.view.info : ""
        tone: row.keys === null ? row.view.tone : ""
        text: row.keys === null ? row.view.text : ""
        lines: row.keys === null ? row.view.lines : []
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
            values: row.keys === null ? row.view.items : row.keys.items
            objectProp: "key"
        }
        StatusLine {
            required property var modelData
            readonly property var presence: row.settingsContext ? Steps.keyView(modelData, row.plugin) : Steps.itemView(modelData, row.setup)
            width: row.width
            label: modelData.label
            info: modelData.info
            hint: [row.setup && presence.reason !== "" ? presence.reason + (modelData.hint === "" ? "" : ": " + modelData.hint) : modelData.hint, row.settingsContext ? presence.note : ""]
                .filter(part => part !== "").join(" ")
            onHintPageActivated: (page, tab) => row.openPage(page, tab)
            onInfoPageActivated: (page, tab) => row.openPage(page, tab)
            // The key's own write reads in its value's place while it runs.
            tone: writing !== "" ? "" : presence.tone
            text: writing !== "" ? Steps.WRITE_WORDS[writing] : presence.text
            danger: writing === "" && row.settingsContext && presence.danger
            access: modelData.access
            secretLabel: row.secretLabel
            busy: row.panel !== null && row.panel.writing !== null
            writing: row.writingOf(modelData.secret)
            // A key's write and its source action each keep their own
            // reply, so a later success of one never clears the other's.
            error: [row.replyOf(modelData.secret), row.sourceReplyOf(modelData.secret)].filter(reply => reply !== "").join(" ")
            sourceLabel: modelData.secret === "" ? "" : row.sourceLabel
            onStoreSecret: value => row.panel.storeSecret(row.pluginId, row.entry.key, modelData.secret, value)
            onClearSecret: row.panel.clearSecret(row.pluginId, row.entry.key, modelData.secret)
            onSource: row.panel.actSource(row.pluginId, row.entry.key, modelData.secret)
        }
    }
}
