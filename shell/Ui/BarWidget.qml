import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Base item every bar widget extends. The core assigns five properties
// after it builds the widget: `shell` (the widget's own scoped object),
// `bar` (the bar API), `moduleName` (the plugin id), `settings` (the
// manifest defaults under the widget's layout entry) and `frame`, what Hide
// reads and calls: `describe()` answers { name, keys, stops } and `hide()`
// takes the widget out of every bar section.
//
// Every widget gets the same right-click menu with one entry, Hide, with no
// code in the plugin. Hide asks first in a small dialog under the widget,
// which says how to bring the widget back, shows the shortcuts that keep
// working, and says when hiding also turns the plugin off. Cancel holds the
// focus, so Enter and Escape change nothing; a press outside closes it too.
Item {
    id: root

    property var shell: null
    property QtObject bar: null
    property string moduleName: ""
    property var settings: ({})
    property var frame: null

    readonly property int barSize: bar ? bar.barSize : Theme.bar.height
    readonly property bool menuOpen: hideMenu.opened
    readonly property bool hideDialogOpen: dialogWindow.visible
    // What the open dialog says, read from `frame` when it opens.
    property var facts: ({ name: "", keys: [], stops: false })

    // One setting with a fallback for a missing or null value.
    function setting(name, fallback) {
        const value = settings ? settings[name] : undefined;
        return value === undefined || value === null ? fallback : value;
    }

    function askHide() {
        if (frame === null) return;
        facts = frame.describe();
        dialogWindow.visible = true;
        Qt.callLater(() => dialog.forceActiveFocus(Qt.TabFocusReason));
    }

    // The dialog's share of OverlayState, taken as Popover takes its own.
    property bool counted: false
    function share(open) {
        if (open === counted) return;
        counted = open;
        if (open) OverlayState.opened(); else OverlayState.closed();
    }
    Component.onDestruction: share(false)

    // pointer-cursor-exempt: it adds the right click to the widget, whose own controls show the hand
    // keyboard-path: the Show in bar switch on the plugin's Settings page hides and shows the widget
    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: hideMenu.open()
    }

    Menu {
        id: hideMenu

        MenuItem {
            text: "Hide"
            iconName: "eye-off"
            // The menu's grab ends before the dialog takes its own.
            onTriggered: Qt.callLater(root.askHide)
        }
    }

    PopupWindow {
        id: dialogWindow

        anchor.item: root
        anchor.edges: Edges.Bottom | Edges.Left
        anchor.gravity: Edges.Bottom | Edges.Right
        anchor.adjustment: PopupAdjustment.Flip | PopupAdjustment.Slide
        anchor.margins.bottom: -Theme.popover.gap
        grabFocus: true
        visible: false
        color: "transparent"
        implicitWidth: Math.max(1, OverlayState.widthFor(root, Theme.dialog.width))
        implicitHeight: Math.max(1, dialog.implicitHeight)
        onVisibleChanged: root.share(visible)

        DismissScope {
            popup: dialogWindow
            anchor: root

            Dialog {
                id: dialog
                anchors.fill: parent
                title: "Hide " + root.facts.name + "?"
                message: root.facts.stops
                    ? root.facts.name + " leaves the bar. To show it again, turn on Enabled on its page in Settings. Hiding it also turns it off."
                    : root.facts.name + " leaves the bar. To show it again, turn on Show in bar on its page in Settings."
                actions: [{ label: "Cancel", role: "cancel", focused: true }, { label: "Hide", role: "accept", variant: "danger" }]
                onAccepted: {
                    dialogWindow.visible = false;
                    const reply = root.frame.hide();
                    if (reply !== "ok") console.warn("bar widget: hide " + root.moduleName + " " + reply);
                }
                onRejected: dialogWindow.visible = false

                Label {
                    text: "Its shortcuts still work."
                    visible: root.facts.keys.length > 0 && !root.facts.stops
                }
                Repeater {
                    model: root.facts.stops ? [] : root.facts.keys
                    KeyCaps { shortcut: modelData }
                }
            }
        }
    }

    readonly property AnchorTracker tracker: AnchorTracker { popup: dialogWindow; anchor: root }
}
