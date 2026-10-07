import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Steps.js" as Steps

// One Status row of a plugin's page, drawn from one entry of its manager
// row's `status` (PluginLogic.statusRows) as StatusLines: the entry's label
// beside its value, the entry's hint and, while its step applies
// (Steps.js), its action. A presence
// or a state draws as a Badge in the tone the entry carries, a state's
// further lines each as a Badge of that tone under it; a text, a
// count or a time as one line of text; an entry the plugin has not
// published, or published while disabled, as "Not reported". A presence
// list draws its label and hint alone, "None detected" while the list is
// empty, then one line per item: the item's label beside a Badge of its
// presence, its hint, and Connect or Disconnect for an item that is a secret's
// presence. Each line is one
// group of the row's GroupList, divided from the next as the rows of a
// section are. No row takes an edit of a value: a step goes to the manager
// through `panel` (D061).
GroupList {
    id: row

    // One entry of a manager row's `status`, or null for a row whose entry
    // left the page's manager row before the row itself goes.
    required property var entry
    // The Settings panel, whose manager calls run each step and whose
    // `replyOf` and `writing` each line reads, and the plugin's id.
    required property Item panel
    required property string pluginId
    // The plugin's `secrets` label, which a Connect's field asks for.
    property string secretLabel: ""

    // The panel's last refusal or failure of this row's entry, or of
    // ACCOUNT's secret in it, "" for none and while the page is torn down,
    // when `panel` is already null.
    function replyOf(account) {
        return panel === null || entry === null ? "" : panel.replyOf(pluginId, entry.key, account);
    }

    // What the row draws: Steps.statusView of its entry.
    readonly property var view: Steps.statusView(entry, ms => new Date(ms).toLocaleString(Qt.locale(), Locale.ShortFormat))

    visible: entry !== null

    StatusLine {
        width: row.width
        label: row.view.label
        hint: row.view.hint
        info: row.view.info
        tone: row.view.tone
        text: row.view.text
        lines: row.view.lines
        muted: row.view.muted
        actionLabel: row.entry === null || row.entry.action === null ? "" : row.entry.action.label
        actionOffered: row.view.offered
        error: row.replyOf()
        onAct: row.panel.act(row.pluginId, row.entry.key)
    }

    Repeater {
        model: ScriptModel {
            values: row.view.items
            objectProp: "key"
        }
        StatusLine {
            required property var modelData
            width: row.width
            label: modelData.label
            hint: modelData.hint
            tone: modelData.tone
            text: Steps.PRESENCE_WORDS[modelData.value]
            access: modelData.access
            secretLabel: row.secretLabel
            busy: row.panel !== null && row.panel.writing !== ""
            error: row.replyOf(modelData.secret)
            onStoreSecret: value => row.panel.storeSecret(row.pluginId, row.entry.key, modelData.secret, value)
            onClearSecret: row.panel.clearSecret(row.pluginId, row.entry.key, modelData.secret)
        }
    }
}
