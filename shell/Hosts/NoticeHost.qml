import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Core
import qs.Commons
import qs.Ui

// The core notice surface: one OverlaySurface on the screen Notices chose,
// existing only while a requirement notice, the restart notice, the reset
// question, the "VGS was reset" notice or the core consent slot shows,
// taking the keyboard on demand. It draws one Dialog at a time. A
// requirement notice has priority: one entry per package its step installs
// for a missing requirement or updates for an outdated one, its name as a
// chip with its state beside it, Missing, Optional or Outdated in the tone
// the Requirements row draws it with (PluginLogic.requirementBadge), and
// each purpose under it, then one per package a later step offers, drawn alike with a line
// naming the manager that offers it, its title counting the entries whose
// chip reads Missing or Outdated, then
// Install, Update or Install and update, with Not now, or Close alone when
// no manager here installs a listed package. The step runs Notices.accept, every other
// answer Notices.dismiss. The consent slot draws its view's title, message,
// lines, file link, quick commands and actions: the Hyprland question's
// Connect and Not now, or the welcome's Connect, Not now or Close. The
// restart notice is drawn as the consent slot is, from Notices.restartView, and its
// Restart runs Notices.restartShell; so are the reset question, from
// Notices.resetView, whose Reset runs Notices.resetVgs, and the "VGS was
// reset" notice, from Notices.resetDoneView, whose Restore previous
// settings runs Notices.restoreReset and whose Escape runs
// Notices.hideResetDone. While the
// shown notice's install runs the window is gone, so the floating TUI it
// opened, centred on the same monitor, shows whole; a notice the scan
// after the run keeps comes back as a new window that takes the keyboard. The window fills the area other
// layers leave free, less `dialog.margin`, whatever the dialog's size, and
// the dialog sits in its centre. The scrim, `color.scrim`, fills the window
// under the dialog and dims what lies behind it. The dialog alone takes
// pointer input, so a click on the scrim reaches what is under it, and no
// notice is modal for the pointer. A reference in the message or a
// consent line (PageReference), a page's or a file's, opens through the
// core's one reference route, Plugins.openReference: a file through the
// core edit route.
Scope {
    id: host

    Component.onCompleted: Plugins.registerHost("notice", host)

    // The dialog, for a validation row that reads its focus.
    readonly property Item dialog: loader.item === null ? null : loader.item.dialog
    // The scrim under it, for a validation row that reads where it is drawn.
    readonly property Item scrim: loader.item === null ? null : loader.item.scrim

    // Open what an activated reference names; a refused one logs its
    // reply, and its words stay words.
    function openReference(page, tab) {
        const answer = Plugins.openReference(page, tab);
        if (answer !== "ok") console.warn("notices: reference " + answer);
    }

    // The label of the step the notice runs, PluginLogic.noticeView's
    // `run`, "" when no manager here runs one.
    function step(shown) {
        if (shown.run === null) return "";
        if (shown.run.updates.length === 0) return "Install";
        return shown.run.installs.length === 0 ? "Update" : "Install and update";
    }

    // The line under SHOWN's entries for FAILURE, Notices.failure: why its
    // last run did not finish, or what a run that finished left as it was,
    // one leftLine for each package it left.
    function failureLine(shown, failure) {
        switch (failure.kind) {
        case "failed":
            return "The last " + step(shown).toLowerCase() + " did not finish: " + failure.reason;
        case "unchanged":
            return failure.left.map(entry => leftLine(shown, entry)).join(" ");
        }
        throw new Error("notices: failure kind " + JSON.stringify(failure.kind) + " has no line");
    }

    // What a run left of one package, ENTRY of PluginLogic.noticeUnchanged:
    // still missing, an optional one said to be optional, or still below
    // the floor SHOWN's owner needs.
    function leftLine(shown, entry) {
        switch (entry.kind) {
        case "missing":
            return entry.optional ? entry.name + " is optional. " + step(shown) + " left it out, and " + shown.name + " works without it." : entry.name + " is still missing after the install.";
        case "outdated":
            return entry.name + " is still version " + entry.version + " after the update. " + shown.name + " needs version " + entry.floor + " or later.";
        }
        throw new Error("notices: unchanged kind " + JSON.stringify(entry.kind) + " has no line");
    }

    // The dialog's message for SHOWN: what its step does, or how to install
    // its requirements when no manager here installs them. The line under
    // each later entry names its manager, so the message names none.
    function message(shown) {
        if (step(shown) !== "") return step(shown) + " opens a terminal. The package manager asks for your password there.";
        if (shown.byHand.length > 0) return "Add these packages to the system configuration: " + shown.byHand.map(g => g.manager + " " + g.names.join(" ")).join(", ") + ".";
        if (Notices.detection === "failed") return "VGS could not detect this system's package manager. Install these requirements by hand.";
        return "No package manager here provides these requirements. Install them by hand.";
    }

    // Whether the notice's window holds the keyboard.
    readonly property bool keyboardHeld: loader.item !== null && loader.item.keyboardHeld

    // Take the keyboard back after another shell surface that took it lost
    // it, as the bar does when a widget's press grab ends
    // (Plugins.returnKeyboard). Hyprland v0.56.2 gives an on-demand
    // layer the keyboard at its map and at a press on it, never because the
    // surface that held it went: refocusLastWindow passes an on-demand
    // layer over (InputManager.cpp). A layer that turns exclusive is
    // focused at that commit (LayerSurface.cpp onCommit), so the window
    // asks for that until the keyboard arrives and is on demand again
    // after; rows/bar.sh reads the welcome focused after a drag.
    function retakeKeyboard() {
        if (loader.item !== null && !loader.item.keyboardHeld) loader.item.retaking = true;
    }

    function consent() {
        if (Notices.showingRestart) return Notices.restartView;
        if (Notices.showingResetAsk) return Notices.resetView;
        if (Notices.showingResetDone) return Notices.resetDoneView;
        return Notices.showingConsent ? Notices.consent : null;
    }

    Loader {
        id: loader
        active: ((Notices.view !== null && !Notices.installing) || host.consent() !== null) && Notices.screen !== null
        sourceComponent: OverlaySurface {
            id: win

            readonly property Item dialog: card
            readonly property Item scrim: wash
            readonly property var shown: Notices.view
            readonly property var consent: host.consent()
            readonly property bool consentMode: win.shown === null && win.consent !== null

            screen: Notices.screen
            placement: "center"
            inset: Theme.dialog.margin
            inputItems: [card]
            WlrLayershell.namespace: "vgs:notice"
            WlrLayershell.keyboardFocus: win.retaking ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand

            // QQuickWindow.active follows the keyboard's enter and leave
            // (Qt Quick Window reference, `active`).
            readonly property bool keyboardHeld: card.Window.window !== null && card.Window.window.active
            property bool retaking: false
            onKeyboardHeldChanged: if (keyboardHeld) retaking = false

            // Outside `inputItems`, so the window's mask leaves it out and
            // its presses, hover and wheel go to what lies under it.
            Scrim {
                id: wash
            }

            Dialog {
                id: card
                anchors.centerIn: parent
                width: implicitWidth
                title: win.consentMode ? win.consent.title : win.shown.title
                message: win.consentMode ? win.consent.message : host.message(win.shown)
                actions: win.consentMode ? win.consent.actions : host.step(win.shown) !== "" ? [{ label: host.step(win.shown), role: "accept" }, { label: "Not now", role: "cancel" }] : [{ label: "Close", role: "cancel" }]
                busy: win.consentMode && win.consent.busy
                tabItems: card.tabStops()
                onAccepted: {
                    if (!win.consentMode) Notices.accept();
                    else if (Notices.showingRestart) Notices.restartShell();
                    else if (Notices.showingResetAsk) Notices.resetVgs();
                    else if (Notices.showingResetDone) Notices.restoreReset();
                    else Notices.answerConsent("accept");
                }
                onRejected: Notices.dismiss()
                onMessagePageActivated: (page, tab) => host.openReference(page, tab)

                function tabStops() {
                    const links = consentLines.visible ? consentLines.visibleChildren.filter(item => item.linked === true) : [];
                    return links;
                }

                // The consent slot's lines, the welcome's: paragraphs
                // `dialog.gap` apart, as the dialog's message and body are.
                Column {
                    id: consentLines
                    width: parent.width
                    spacing: Theme.dialog.gap
                    visible: win.consentMode && win.consent.lines.length > 0
                    Repeater {
                        model: win.consentMode ? win.consent.lines : []
                        LinkText {
                            required property var modelData
                            role: Theme.dialog.bodyRole
                            width: parent.width
                            wrapMode: Text.Wrap
                            text: modelData
                            link: win.consent.link === null || win.consent.link === undefined ? "" : win.consent.link.text
                            onActivated: Notices.openConsentLink()
                            onPageActivated: (page, tab) => host.openReference(page, tab)
                        }
                    }
                }
                Column {
                    width: parent.width
                    spacing: Theme.stack.row
                    visible: win.consentMode && win.consent.keys !== undefined && win.consent.keys.length > 0
                    Label {
                        role: "eyebrow"
                        text: win.consentMode ? win.consent.keysTitle : ""
                    }
                    Repeater {
                        model: win.consentMode && win.consent.keys !== undefined ? win.consent.keys : []
                        Row {
                            required property var modelData
                            spacing: Theme.stack.inline
                            width: parent.width
                            KeyCaps {
                                shortcut: modelData.shortcut
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Label {
                                role: Theme.dialog.bodyRole
                                text: modelData.text
                                width: parent.width - x
                                wrapMode: Text.Wrap
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                }
                // The packages the notice asks for, a block of the dialog's body
                // `dialog.gap` under the message: first those this step
                // handles, each its name as a chip
                // and its state beside it, a chip that elides before the
                // state leaves the dialog,
                // with each purpose under it as a hint, as a Field draws a
                // label's hint, then the packages a later step offers,
                // drawn alike with one more hint naming the manager that
                // offers them. The entries are groups of the shared
                // GroupList, which spaces them and centres the hairline
                // between two of them by their drawn ink.
                GroupList {
                    id: entryList
                    visible: !win.consentMode
                    Repeater {
                        model: win.consentMode ? [] : win.shown.drawn
                        Column {
                            required property var modelData
                            width: entryList.width
                            spacing: Theme.field.gap
                            Row {
                                id: entryHead
                                width: parent.width
                                spacing: Theme.stack.inline
                                // A package or command name is case-sensitive,
                                // so the chip draws it as written.
                                Badge {
                                    width: Math.min(implicitWidth, entryHead.width - entryHead.spacing - entryState.width)
                                    text: modelData.chip
                                    tone: "neutral"
                                    size: "sm"
                                    verbatim: true
                                }
                                Badge {
                                    id: entryState
                                    text: modelData.badge.text
                                    tone: modelData.badge.tone
                                    size: "sm"
                                }
                            }
                            Repeater {
                                model: modelData.purposes
                                Label {
                                    required property string modelData
                                    role: "hint"
                                    width: parent.width
                                    wrapMode: Text.Wrap
                                    text: modelData
                                }
                            }
                            Label {
                                role: "hint"
                                width: parent.width
                                wrapMode: Text.Wrap
                                visible: modelData.later
                                text: "Offered after this step, through " + modelData.manager + "."
                            }
                        }
                    }
                }
                Label {
                    role: Theme.dialog.bodyRole
                    width: parent.width
                    wrapMode: Text.Wrap
                    visible: win.consentMode ? win.consent.failure !== "" : Notices.failure !== null
                    text: win.consentMode ? "The last connection did not finish: " + win.consent.failure : win.shown !== null && Notices.failure !== null ? host.failureLine(win.shown, Notices.failure) : ""
                }
            }

            // Escape on the "VGS was reset" notice hides it for this run and
            // keeps the restore for the next start, while Keep these, its
            // cancel action, forgets it. The shortcut takes Escape before the
            // dialog's own Escape, which rejects.
            Shortcut {
                sequence: "Escape"
                enabled: win.consentMode && Notices.showingResetDone
                onActivated: Notices.hideResetDone()
            }

            // Each notice that comes to the front takes the keyboard.
            Connections {
                target: Notices
                function onShownIdChanged() { card.forceActiveFocus(); }
            }
            Component.onCompleted: card.forceActiveFocus()
        }
    }
}
