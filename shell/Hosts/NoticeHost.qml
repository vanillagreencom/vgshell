import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Core
import qs.Commons
import qs.Ui

// Hide the notice during installation so its floating TUI shows whole.
// A notice retained by the next scan maps anew and takes the keyboard.
// Keep the scrim outside the input mask: notices dim the desktop but
// must not block pointer input outside their dialog.
// References use the core's one route, including its file edit route.
Scope {
    id: host

    Component.onCompleted: Plugins.registerHost("notice", host)

    // The dialog, for a validation row that reads its focus.
    readonly property Item dialog: loader.item === null ? null : loader.item.dialog
    // The scrim under it, for a validation row that reads where it is drawn.
    readonly property Item scrim: loader.item === null ? null : loader.item.scrim

    function openReference(page, tab) {
        const answer = Plugins.openReference(page, tab);
        if (answer !== "ok") console.warn("notices: reference " + answer);
    }

    function step(shown) {
        if (shown.run === null) return "";
        if (shown.run.updates.length === 0) return "Install";
        return shown.run.installs.length === 0 ? "Update" : "Install and update";
    }

    function actionLabel(shown) {
        if (shown.action !== null && shown.action.action === "retry") return "Retry without tests";
        const normal = step(shown);
        return normal === "Install" && ((Notices.failure !== null && Notices.failure.kind === "failed") || shown.packageFailure !== null) ? "Install again" : normal;
    }

    function failureLine(shown, failure) {
        switch (failure.kind) {
        case "failed":
            if (shown.action !== null && shown.action.action === "retry") return Reply.line(failure.reason);
            return "The last " + step(shown).toLowerCase() + " did not finish: " + failure.reason;
        case "unchanged":
            return failure.left.map(entry => leftLine(shown, entry)).join(" ");
        }
        throw new Error("notices: failure kind " + JSON.stringify(failure.kind) + " has no line");
    }

    function leftLine(shown, entry) {
        switch (entry.kind) {
        case "missing":
            return entry.optional ? entry.name + " is optional. " + step(shown) + " left it out, and " + shown.name + " works without it." : entry.name + " is still missing after the install.";
        case "outdated":
            return entry.name + " is still version " + entry.version + " after the update. " + shown.name + " needs version " + entry.floor + " or later.";
        }
        throw new Error("notices: unchanged kind " + JSON.stringify(entry.kind) + " has no line");
    }

    // Each later entry names its manager; repeating it in the message adds nothing.
    function message(shown) {
        if (shown.packageFailure !== null) {
            const available = shown.packageFailure.retry !== null && shown.packageFailure.retry.state === "available";
            const consumed = shown.packageFailure.retry !== null && shown.packageFailure.retry.state === "consumed";
            return (consumed ? "The retry without tests for " + shown.packageFailure.package + " failed."
                : shown.packageFailure.package + " failed its package tests.") + " This build was not installed.\n"
                + (available ? "This retry skips package tests, including tests for any dependency the helper builds. It does not turn off source checks."
                    : shown.packageFailure.retry !== null ? "The retry without tests was used. It skipped package and dependency tests. Source checks stayed on. Install or update again to run the tests."
                    : "No retry without tests is available. Install or update again to run package tests and source checks.");
        }
        if (step(shown) !== "") return actionLabel(shown) + " opens a terminal. The package manager asks for your password there.";
        if (shown.byHand.length > 0) return "Add these packages to the system configuration: " + shown.byHand.map(g => g.manager + " " + g.names.join(" ")).join(", ") + ".";
        if (Notices.detection === "failed") return "VGS could not detect this system's package manager. Install these requirements by hand.";
        return "No package manager here provides these requirements. Install them by hand.";
    }

    function consent() {
        if (Notices.showingNewer) return Notices.newerView;
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
            // Exclusive holds the keyboard for this visible lifetime; OnDemand
            // leaves it to the compositor (Quickshell 0.3.1):
            // https://quickshell.org/docs/v0.3.1/types/Quickshell.Wayland/WlrKeyboardFocus/
            // Hyprland 0.57 refocuses under the pointer after map and after an
            // Exclusive-to-OnDemand commit (LayerSurface.cpp:224-225,426-427).
            // Keep the card-only mask: keyboard ownership does not widen it.
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

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
                actions: win.consentMode ? win.consent.actions : host.step(win.shown) !== "" ? [{ label: host.actionLabel(win.shown), role: "accept" }, { label: "Not now", role: "cancel" }] : [{ label: "Close", role: "cancel" }]
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
                    return links.concat(KeyNavLogic.focusables(consentKeys));
                }

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
                    id: consentKeys
                    width: parent.width
                    spacing: Theme.stack.row
                    visible: win.consentMode && win.consent.keys !== undefined && win.consent.keys.length > 0
                    Label {
                        role: "eyebrow"
                        text: consentKeys.visible ? win.consent.keysTitle : ""
                    }
                    Repeater {
                        model: win.consentMode && win.consent.keys !== undefined ? win.consent.keys : []
                        Row {
                            required property var modelData
                            spacing: Theme.stack.inline
                            width: parent.width
                            KeyCaps {
                                id: shortcutCaps
                                shortcut: modelData.shortcut
                                anchors.verticalCenter: parent.verticalCenter
                                onPageActivated: (page, tab) => host.openReference(page, tab)
                            }
                            Label {
                                role: Theme.dialog.bodyRole
                                text: modelData.text
                                visible: !shortcutCaps.linked
                                width: parent.width - x
                                wrapMode: Text.Wrap
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                }
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

            Connections {
                target: Notices
                function onShownIdChanged() { card.forceActiveFocus(); }
            }
            Component.onCompleted: card.forceActiveFocus()
        }
    }
}
