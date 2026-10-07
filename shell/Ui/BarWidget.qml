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
// Every widget gets the same right-click menu, with no code in the plugin:
// Hide, then the entries the widget hands in `frameActions`, each
// { label, action }, which a click or Enter runs. Hide asks first in a small dialog under the widget,
// which says how to bring the widget back, shows the shortcuts that keep
// working, and says when hiding also turns the plugin off. Cancel holds the
// focus, so Enter and Escape change nothing; a press outside closes it too.
// The menu and the dialog are built on the first right click and released
// once both are closed, so a widget at rest holds neither.
Item {
    id: root

    property var shell: null
    property QtObject bar: null
    property string moduleName: ""
    property var settings: ({})
    property var frame: null
    // The widget's own menu entries after Hide, each { label, action }.
    property var frameActions: []

    readonly property int barSize: bar ? bar.barSize : Theme.bar.height
    readonly property bool frameMenuOpen: frameUi.item !== null && frameUi.item.menuOpened
    readonly property bool frameDialogOpen: frameUi.item !== null && frameUi.item.dialogOpened
    readonly property bool frameDragging: dragHandler.active
    // The texts of the open menu's entries, in order; [] while it is closed.
    readonly property var frameMenuEntries: frameUi.item !== null ? frameUi.item.menuEntries : []

    opacity: frameDragging ? Theme.opacity.disabled : 1

    // One setting with a fallback for a missing or null value.
    function setting(name, fallback) {
        const value = settings ? settings[name] : undefined;
        return value === undefined || value === null ? fallback : value;
    }

    // pointer-cursor-exempt: it adds the right click to the widget, whose own controls show the hand
    // keyboard-path: the Show in bar switch on the plugin's Settings page hides and shows the widget
    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: {
            frameUi.active = true;
            frameUi.item.openMenu();
        }
    }

    function dragPoint() {
        // HandlerPoint.scenePressPosition keeps the pickup offset when a
        // drag activates after its threshold (Qt Quick HandlerPoint reference).
        const centroid = dragHandler.centroid;
        return { x: centroid.scenePosition.x, y: centroid.scenePosition.y,
            pressX: centroid.scenePressPosition.x, pressY: centroid.scenePressPosition.y };
    }

    // Qt Quick still hands a press a child button accepted to this parent
    // handler, which takes the grab from the button once the drag starts,
    // so the button emits no click (QQuickPointerHandler::
    // approveGrabTransition; QQuickAbstractButton sets no keepMouseGrab,
    // qtdeclarative 6.11).
    DragHandler {
        id: dragHandler
        target: null
        acceptedButtons: Qt.LeftButton
        enabled: root.frame !== null
        onActiveChanged: {
            if (active) {
                root.frame.dragStart(root.dragPoint());
            }
            else {
                if (root.frame !== null) {
                    const p = root.dragPoint();
                    root.frame.dragMove(p);
                    root.frame.dragEnd(p);
                }
            }
        }
        onActiveTranslationChanged: if (active) root.frame.dragMove(root.dragPoint())
    }

    Loader {
        id: frameUi

        // Release the menu and the dialog once neither is open nor about
        // to open.
        function release() {
            if (item !== null && !item.asking && !item.menuOpened && !item.dialogOpened) active = false;
        }

        anchors.fill: parent
        active: false
        sourceComponent: Item {
            id: ui

            readonly property bool menuOpened: hideMenu.opened
            readonly property bool dialogOpened: dialogWindow.visible
            readonly property var menuEntries: hideMenu.opened ? hideMenu.items().map(entry => entry.text) : []
            // Hide was chosen and the dialog has not opened yet.
            property bool asking: false
            // What the open dialog says, read from `frame` when it opens.
            property var facts: ({ name: "", keys: [], stops: false })

            function openMenu() { hideMenu.open(); }

            function askHide() {
                asking = false;
                if (root.frame === null) return;
                facts = root.frame.describe();
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

            onMenuOpenedChanged: if (!menuOpened) Qt.callLater(frameUi.release)
            onDialogOpenedChanged: if (!dialogOpened) Qt.callLater(frameUi.release)

            Menu {
                id: hideMenu

                MenuItem {
                    text: "Hide"
                    iconName: "eye-off"
                    // The menu's grab ends before the dialog takes its own.
                    onTriggered: {
                        ui.asking = true;
                        Qt.callLater(ui.askHide);
                    }
                }
                Repeater {
                    model: root.frameActions
                    MenuItem {
                        required property var modelData
                        required property int index
                        text: modelData.label
                        // Read from the list itself: a model entry is a copy
                        // that need not keep the function.
                        onTriggered: root.frameActions[index].action()
                    }
                }
            }

            PopupWindow {
                id: dialogWindow

                anchor.item: ui
                anchor.edges: Edges.Bottom | Edges.Left
                anchor.gravity: Edges.Bottom | Edges.Right
                anchor.adjustment: PopupAdjustment.Flip | PopupAdjustment.Slide
                anchor.margins.bottom: -Theme.popover.gap
                grabFocus: true
                visible: false
                color: "transparent"
                implicitWidth: Math.max(1, OverlayState.widthFor(ui, Theme.dialog.width))
                implicitHeight: Math.max(1, dialog.implicitHeight)
                onVisibleChanged: ui.share(visible)

                DismissScope {
                    popup: dialogWindow
                    anchor: ui

                    Dialog {
                        id: dialog
                        anchors.fill: parent
                        title: "Hide " + ui.facts.name + "?"
                        message: ui.facts.stops
                            ? ui.facts.name + " leaves the bar. To show it again, turn on Enabled on its page in Plugins. Hiding it also turns it off."
                            : ui.facts.name + " leaves the bar. To show it again, turn on Show in bar on its page in Plugins."
                        actions: [{ label: "Cancel", role: "cancel", focused: true }, { label: "Hide", role: "accept", variant: "danger" }]
                        onAccepted: {
                            dialogWindow.visible = false;
                            const reply = root.frame.hide();
                            if (reply !== "ok") console.warn("bar widget: hide " + root.moduleName + " " + reply);
                        }
                        onRejected: dialogWindow.visible = false

                        Label {
                            text: "Its shortcuts still work."
                            visible: ui.facts.keys.length > 0 && !ui.facts.stops
                        }
                        Repeater {
                            model: ui.facts.stops ? [] : ui.facts.keys
                            KeyCaps { shortcut: modelData }
                        }
                    }
                }
            }

            readonly property AnchorTracker tracker: AnchorTracker { popup: dialogWindow; anchor: ui }
        }
    }
}
