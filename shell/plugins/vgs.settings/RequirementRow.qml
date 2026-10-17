import QtQuick
import qs.Commons
import qs.Ui

// One read-only Requirements row of a plugin's page, drawn from one entry
// of its manager row's `requirements` (PluginLogic.requirementRows): the
// requirement beside its state from the last scan as a Badge of one word,
// the entry's `badge` (PluginLogic.requirementBadge, the rule the
// requirement notice draws its chips with too): Present, Missing, Optional
// for a missing optional requirement, since the purpose under it says what
// the tool adds, or Outdated for a command below the version the plugin
// needs, optional or not, since an installed tool the plugin calls fails
// below that version. Details lists the optional tools with it, by the
// requirement's title, its command or its D-Bus label; the row draws no
// step of its own, and the section's Review action installs them.
Column {
    id: row

    // One entry of a manager row's `requirements`.
    required property var requirement

    Field {
        width: row.width
        label: row.requirement.title
        inline: true
        hint: row.requirement.purpose
        Item {
            implicitHeight: chip.height
            Badge { id: chip; text: row.requirement.badge.text; tone: row.requirement.badge.tone }
        }
    }
}
