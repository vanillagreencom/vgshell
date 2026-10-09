import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Base item for plugin widgets and registered builtin wrappers. The core assigns five properties to plugin widgets
// after it builds the widget: `shell` (the widget's own scoped object),
// `bar` (the bar API), `moduleName` (the plugin id), `settings` (the
// manifest defaults under the widget's layout entry) and `frame`, what Hide
// and a drag read and call: `describe()` answers { name, keys, stops,
// builtin, owner }, `hide()` takes the widget out of every bar section,
// `dragStart`, `dragMove` and `dragEnd` take the drag's points, and
// `dragCancel()` ends a remove question, putting the widget back where the
// drag found it.
//
// Every widget gets the same right-click menu, with no code in the plugin:
// Hide, then the entries the widget hands in `frameActions`, each
// { label, action }, which a click or Enter runs. A builtin hides at once;
// its Settings > Bar switch restores it. A plugin widget asks first in a small dialog under the widget,
// which says how to bring the widget back, shows the shortcuts that keep
// working, and says when hiding also turns the plugin off. Cancel holds the
// focus, so Enter and Escape change nothing; a press outside closes it too.
// A drag released far outside the bar asks in the same dialog whether to
// remove the widget from the bar, which is what Hide does; every other
// answer puts the widget back where the drag found it. That dialog opens
// from the pointer, so Cancel holds the focus with no focus ring.
// The menu and the dialog are built on the first right click or that
// release and released once both are closed, so a widget at rest holds
// neither.
Item {
    id: root

    property var shell: null
    property QtObject bar: null
    property string moduleName: ""
    property var settings: ({})
    property var frame: null
    // The widget's own menu entries after Hide, each { label, action }.
    property var frameActions: []
    // The first entry's text and icon. It runs Hide; a builtin the user
    // added from the bar's own menu names it as a removal.
    property string frameHideText: "Hide"
    property string frameHideIcon: "eye-off"

    readonly property int barSize: bar ? bar.barSize : Theme.bar.height
    readonly property bool frameMenuOpen: frameUi.item !== null && frameUi.item.menuOpened
    readonly property bool frameDialogOpen: frameUi.item !== null && frameUi.item.dialogOpened
    readonly property bool frameDragging: dragHandler.active
    // The texts of the open menu's entries, in order; [] while it is closed.
    readonly property var frameMenuEntries: frameUi.item !== null ? frameUi.item.menuEntries : []

    opacity: frameDragging ? Theme.opacity.disabled : 1

    // Behavior animates changes to this x property alone:
    // https://doc.qt.io/qt-6/qml-qtquick-behavior.html
    // The grabbed widget follows the pointer directly. At rest, intrinsic
    // size changes keep the right section's edge fixed without animation.
    Behavior on x {
        enabled: !root.frameDragging && root.bar !== null
            && root.bar.children.some(item => item.frameDragging === true)
        NumberAnimation { duration: Theme.motion.duration.normal; easing.type: Theme.motion.easing.standard }
    }

    // One setting with a fallback for a missing or null value.
    function setting(name, fallback) {
        const value = settings ? settings[name] : undefined;
        return value === undefined || value === null ? fallback : value;
    }

    // pointer-cursor-exempt: it adds the right click to the widget, whose own controls show the hand
    // keyboard-path: Settings has placement switches for plugins and bar builtins
    TapHandler {
        acceptedButtons: Qt.RightButton
        enabled: root.frame !== null && typeof root.frame.hide === "function"
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
            // Release commits the last preview; displaced neighbours
            // must not select a new slot without pointer motion.
            else if (root.frame !== null && root.frame.dragEnd(root.dragPoint()) === "ask") {
                frameUi.active = true;
                frameUi.item.asking = true;
                Qt.callLater(frameUi.item.ask, "remove");
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
            // Hide or a far drop was chosen and the dialog has not opened yet.
            property bool asking: false
            // What the dialog asks: "hide" from the menu, "remove" from a drop.
            property string question: "hide"
            // What the open dialog says, read from `frame` when it opens.
            property var facts: ({ name: "", keys: [], stops: false, builtin: false, owner: "" })

            function openMenu() { hideMenu.open(); }

            function ask(kind) {
                asking = false;
                if (root.frame === null) return;
                question = kind;
                facts = root.frame.describe();
                dialogWindow.visible = true;
                Qt.callLater(() => {
                    if (kind === "remove") dialog.focusInitial(Qt.MouseFocusReason);
                    else dialog.forceActiveFocus(Qt.TabFocusReason);
                });
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
            onDialogOpenedChanged: {
                if (dialogOpened) return;
                if (question === "remove" && root.frame !== null) root.frame.dragCancel();
                Qt.callLater(frameUi.release);
            }

            Menu {
                id: hideMenu

                MenuItem {
                    text: root.frameHideText
                    iconName: root.frameHideIcon
                    // The menu's grab ends before the dialog takes its own.
                    onTriggered: {
                        if (root.frame.describe().builtin) {
                            const reply = root.frame.hide();
                            if (reply !== "ok") console.warn("bar widget: hide " + root.moduleName + " " + reply);
                            return;
                        }
                        ui.asking = true;
                        Qt.callLater(ui.ask, "hide");
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
                        title: ui.question === "remove" ? "Remove " + ui.facts.name + " from the bar?" : "Hide " + ui.facts.name + "?"
                        message: ui.facts.builtin
                            ? ui.facts.name + " leaves the bar. To show it again, turn on Show on the bar under " + ui.facts.name + " on the " + ui.facts.owner + " page in Plugins."
                            : ui.facts.stops
                            ? ui.facts.name + " leaves the bar. To show it again, turn on Enabled on its page in Plugins. Hiding it also turns it off."
                            : ui.facts.name + " leaves the bar. To show it again, turn on Show in bar on its page in Plugins."
                        actions: [{ label: "Cancel", role: "cancel", focused: true }, { label: ui.question === "remove" ? "Remove" : "Hide", role: "accept", variant: "danger" }]
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
