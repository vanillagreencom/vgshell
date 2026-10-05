import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "TrayLogic.js" as TrayLogic

// One tray item's menu, drawn by qs.Ui's Menu in its own popup under the
// item, never a platform menu. An entry that holds a submenu opens it in
// place: a new QsMenuOpener on that entry is pushed on `levels`, one live
// opener per level, since a child entry belongs to its parent opener's
// list and dies with it. A level below the root starts with a Back entry
// named after the level above it. Any other entry is the app's action: its
// trigger reaches the app and the menu closes. Closing destroys the
// openers deepest first, then `closed` lets the owner release this item.
Item {
    id: root

    property var trayItem: null
    // The name the root level goes by, which its first submenu's Back
    // entry shows.
    property string title: ""
    // Each level below the root, deepest last: { opener, title }.
    property var levels: []
    readonly property var current: levels.length > 0 ? levels[levels.length - 1].opener : rootOpener
    readonly property bool opened: menu.opened
    // Whether the shown level's entries have taken the highlight, which a
    // level whose entries arrive after it opens gives them once they do.
    property bool settled: false

    signal closed()

    function open() {
        settled = false;
        menu.open();
        Qt.callLater(settle);
    }

    function enter(entry, title) {
        const opener = openerComponent.createObject(root, { menu: entry });
        if (opener === null) return;
        levels = levels.concat([{ opener: opener, title: title }]);
        settled = false;
        Qt.callLater(settle);
    }

    function leave() {
        if (levels.length === 0) return;
        const top = levels[levels.length - 1];
        levels = levels.slice(0, -1);
        top.opener.destroy();
        settled = false;
        Qt.callLater(settle);
    }

    // The stack emptied before any opener goes, so no binding reads one
    // half destroyed, then each destroyed deepest first: an inner opener's
    // entry lives in its parent's list.
    function reset() {
        const stack = levels;
        levels = [];
        for (let i = stack.length - 1; i >= 0; i--) stack[i].opener.destroy();
    }

    // The highlight on the shown level's first entry, past its Back entry,
    // once the entries are there.
    function settle() {
        if (!menu.opened || settled || entries.count === 0) return;
        const all = menu.items();
        const first = all.findIndex((entry, index) => menu.reachable(entry) && !(levels.length > 0 && entry === back));
        if (first === -1) return;
        settled = true;
        menu.currentIndex = -1;
        menu.keyTo(first);
    }

    QsMenuOpener {
        id: rootOpener
        menu: root.trayItem !== null ? root.trayItem.menu : null
    }

    Component {
        id: openerComponent
        QsMenuOpener {}
    }

    Menu {
        id: menu

        onOpenedChanged: if (!opened) {
            root.reset();
            root.closed();
        }

        MenuItem {
            id: back
            visible: root.levels.length > 0
            keepsOpen: true
            iconName: "chevron-left"
            text: root.levels.length > 1 ? root.levels[root.levels.length - 2].title : root.title
            onTriggered: root.leave()
        }

        Repeater {
            id: entries
            model: root.current.children
            onCountChanged: Qt.callLater(root.settle)

            // A separator is an entry that takes no highlight, drawn as a
            // divider.
            MenuItem {
                id: entry
                required property var modelData
                required property int index
                readonly property bool separator: modelData.isSeparator

                visible: !TrayLogic.rowHidden(root.levels.length, index, modelData, root.title)
                height: separator ? 2 * Theme.menu.gap + Theme.divider.thickness : implicitHeight
                text: separator ? "" : modelData.text
                enabled: !separator && modelData.enabled
                opacity: separator || modelData.enabled ? 1 : Theme.opacity.disabled
                checked: modelData.checkState === Qt.Checked
                opensSubmenu: !separator && modelData.hasChildren
                onTriggered: {
                    if (modelData.hasChildren) root.enter(modelData, modelData.text);
                    else modelData.triggered();
                }

                Divider {
                    visible: entry.separator
                    x: entry.sidePadding
                    width: entry.width - 2 * entry.sidePadding
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }
}
