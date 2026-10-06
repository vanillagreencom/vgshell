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
// requirement notice has priority: each missing requirement with its purpose
// first, then Install and Not now, or Close alone when no manager here
// installs a listed package. The command Install runs is only behind Show
// command (D061). Install runs Notices.accept, every other answer
// Notices.dismiss. The consent slot draws its view's title, message,
// lines, file link, quick commands and actions: the Hyprland question's
// Connect and Not now, with its command only behind Show command, or the
// welcome's Connect, Not now or Close without a command disclosure. The
// restart notice is drawn as the consent slot is, from Notices.restartView, and its
// Restart runs Notices.restartShell; so are the reset question, from
// Notices.resetView, whose Reset runs Notices.resetVgs, and the "VGS was
// reset" notice, from Notices.resetDoneView, whose Restore previous
// settings runs Notices.restoreReset and whose Escape runs
// Notices.hideResetDone. While the
// shown notice's install runs the window is gone, so the floating TUI it
// opened, centred on the same monitor, shows whole; a notice the scan
// after the run keeps comes back as a new window that takes the keyboard. The window fills the area other
// layers leave free, less `dialog.margin`, whatever the dialog's size; the
// dialog sits in its centre and alone takes pointer input.
Scope {
    id: host

    Component.onCompleted: Plugins.registerHost("notice", host)

    // The dialog, for a validation row that reads its focus.
    readonly property Item dialog: loader.item === null ? null : loader.item.dialog

    // What names a listed requirement under its purpose: the requirement,
    // then this system's package for it, as the command line's reports
    // name it (requirements.md § Command line), then whether it is
    // optional, joined by a middle dot.
    function rowNote(row) {
        return [row.name].concat(row.package === null ? [] : ["package " + row.package.name], row.optional ? ["optional"] : []).join(" · ");
    }

    function message(shown) {
        if (shown.install !== null) return "Install the missing packages now? The package manager asks for your password in a terminal.";
        if (shown.byHand.length > 0) return "Add these packages to the system configuration: " + shown.byHand.map(g => g.manager + " " + g.names.join(" ")).join(", ") + ".";
        if (Notices.detection === "failed") return "VGS could not detect this system's package manager. Install these requirements by hand.";
        return "No package manager here provides these requirements. Install them by hand.";
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
            readonly property var shown: Notices.view
            readonly property var consent: host.consent()
            readonly property bool consentMode: win.shown === null && win.consent !== null

            screen: Notices.screen
            placement: "center"
            inset: Theme.dialog.margin
            inputItems: [card]
            WlrLayershell.namespace: "vgs:notice"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

            Dialog {
                id: card
                anchors.centerIn: parent
                width: implicitWidth
                title: win.consentMode ? win.consent.title : win.shown.name + " needs " + (win.shown.rows.length === 1 ? "one requirement" : win.shown.rows.length + " requirements")
                message: win.consentMode ? win.consent.message : host.message(win.shown)
                actions: win.consentMode ? win.consent.actions : win.shown.install !== null ? [{ label: "Install", role: "accept" }, { label: "Not now", role: "cancel" }] : [{ label: "Close", role: "cancel" }]
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

                function tabStops() {
                    const links = consentLines.visible ? consentLines.visibleChildren.filter(item => item.linked === true) : [];
                    const command = disclosure.command === "" ? [] : [disclosure.toggle, disclosure.copyButton];
                    return links.concat(command);
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
                // The missing requirements, one list `stack.row` apart, a
                // block of the dialog's body `dialog.gap` under the message:
                // each its purpose, with its name under it as a hint, as a
                // Field draws a label's hint.
                Column {
                    width: parent.width
                    spacing: Theme.stack.row
                    visible: !win.consentMode
                    Repeater {
                        model: win.consentMode ? [] : win.shown.rows
                        Column {
                            required property var modelData
                            width: parent.width
                            spacing: Theme.field.gap
                            Label {
                                role: Theme.dialog.bodyRole
                                width: parent.width
                                wrapMode: Text.Wrap
                                text: modelData.purpose
                            }
                            Label {
                                role: "hint"
                                width: parent.width
                                wrapMode: Text.Wrap
                                text: host.rowNote(modelData)
                            }
                        }
                    }
                }
                // The command Install runs, for a reader who runs it by hand.
                CommandDisclosure {
                    id: disclosure
                    width: parent.width
                    command: win.consentMode ? win.consent.disclosure : win.shown.commandLine
                }
                Label {
                    role: Theme.dialog.bodyRole
                    width: parent.width
                    wrapMode: Text.Wrap
                    visible: win.consentMode ? win.consent.failure !== "" : Notices.failure !== ""
                    text: win.consentMode ? "The last connection did not finish: " + win.consent.failure : "The last install did not finish: " + Notices.failure
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
