import QtQuick
import qs.Commons

// The actions of one key/value row side by side, such as a plugin's Update
// and Remove: RowAction children `rowAction.gap` apart on one line, each
// the same height. A hidden action takes no room. Every row that sets two
// or more actions beside each other composes it, so the gap is one rule.
Row {
    spacing: Theme.rowAction.gap
}
