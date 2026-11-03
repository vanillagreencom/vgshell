import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Appearance.js" as Appearance
import "Session.js" as Session
import "WidgetView.js" as View

// Jarvis's overlay at the bottom centre of the focused screen: the particle
// orb in the look of the Session's phase, its icon row at the orb's top
// right, the state line or the fault under it, the held request in place
// of that line, and Jarvis's words above the orb while its voice is muted.
// It draws in the plugin's own look (Appearance.js) on no card; a passive
// layer takes clicks only on `inputItems` (D026).
Item {
    id: root
    property var screen: null
    property var service: null
    readonly property var look: Theme.appearance(Appearance.TOKENS, Appearance.LIGHT)
    readonly property var host: QsWindow.window
    readonly property var state: service === null ? null : service.sessionState
    readonly property string phase: state === null ? "down" : Session.phaseOf(state)
    readonly property bool shown: service !== null && service.bubbleWanted && screen !== null
        && screen.name === service.focusedOutput
    readonly property bool presented: shown && visible && host !== null && host.presented === true
        && overlay.width > 0 && overlay.height > 0 && overlay.x >= 0 && overlay.y >= 0
        && overlay.width <= width && overlay.height + look.layout.margin <= height
    readonly property var hold: state !== null && state.approval.kind === "held" ? state.approval : null
    // A held request would cover the console's message field and hint line
    // where the console on this screen reaches the band the overlay draws in
    // at the bottom; the overlay then takes the top edge. Both boxes are in this
    // layer's coordinates (Service.consoleBox).
    readonly property var consoleBox: service === null ? null : service.consoleBox
    readonly property bool overConsole: hold !== null && consoleBox !== null && screen !== null
        && consoleBox.output === screen.name
        && consoleBox.y + consoleBox.height > height - look.layout.margin - overlay.height
        && consoleBox.y < height - look.layout.margin
        && consoleBox.x < overlay.x + overlay.width && consoleBox.x + consoleBox.width > overlay.x
    // The current hold's placement is known: the service's last finished
    // read answers this hold. Until then no frame acknowledges the request,
    // so the drawn frame is the placed one.
    readonly property bool placed: service !== null && service.consoleKey === service.heldKey
    property var displayedHold: null
    property var approvalFrames: []
    property var synchronizedHold: null
    readonly property bool approvalPresented: presented && displayedHold !== null && hold !== null
        && displayedHold.id === hold.id && displayedHold.digest === hold.digest && displayedHold.gen === hold.gen
        && approvalText.text === hold.text && approvalText.height >= approvalText.implicitHeight
    onHoldChanged: {
        if (hold === null || displayedHold === null || hold.id !== displayedHold.id
                || hold.gen !== displayedHold.gen || hold.digest !== displayedHold.digest) displayedHold = null;
    }
    // Qt 6.11 afterAnimating runs on the GUI thread after polish, before sync.
    // afterSynchronizing and frameSwapped queue from the render thread in order.
    // Pair each sync with its polish snapshot, including frames without a hold:
    // a queued old swap must not consume a newer request's GUI state.
    // https://doc.qt.io/qt-6/qquickwindow.html#afterSynchronizing
    function approvalPolished() {
        approvalFrames.push(shown && visible && placed && approvalText.text === (hold === null ? "" : hold.text)
            && approvalText.height >= approvalText.implicitHeight ? hold : null);
    }
    function approvalSynchronized() {
        synchronizedHold = approvalFrames.length === 0 ? null : approvalFrames.shift();
    }
    function approvalSwapped() {
        const drawn = synchronizedHold;
        if (drawn === null || displayedHold !== null) return;
        // LayerHost observes this swap too. Its presented value must settle
        // before the service checks this frame's unchanged request identity.
        Qt.callLater(() => {
            if (!root.presented || root.hold === null || root.hold.id !== drawn.id
                    || root.hold.gen !== drawn.gen || root.hold.digest !== drawn.digest) return;
            root.displayedHold = drawn;
            if (root.service !== null) root.service.shownApproval(root, drawn);
        });
    }
    Connections {
        target: root.Window.window
        function onAfterAnimating() { root.approvalPolished(); }
        function onAfterSynchronizing() { root.approvalSynchronized(); }
        function onFrameSwapped() { root.approvalSwapped(); }
    }
    readonly property bool micMuted: state !== null && state.mute.kind !== "off"
    readonly property bool voiceMuted: state !== null && state.voiceMute.kind === "on"
    // A fault reads as the bar says it: what went wrong, then what to do.
    readonly property var fault: phase === "error" ? View.faultText(state.fault, state.engine.kind, service.shell === null ? {} : service.shell.status.values) : null
    readonly property string stateText: state === null ? "" : micMuted ? "Microphone off"
        : fault !== null ? fault.title
        : stateWords[phase]
    readonly property var levels: service === null || service.shell === null ? {}
        : service.shell.status.values.level || {}
    readonly property var caption: service === null || service.shell === null ? null
        : service.shell.status.values.transcript || null
    // Jarvis's words for this conversation, shown only while its voice is
    // muted. The caption is the conversation's latest line, the user's or
    // Jarvis's; only Jarvis's draws, so the user's words clear it. The
    // status keeps an ended conversation's caption until the next one.
    // Waiting for the word shows no words: a reply left on screen could
    // stand there until the next request, however long that is. A held
    // request shows its own question in their place.
    readonly property string words: state === null || !voiceMuted || root.hold !== null || phase === "armed" ? ""
        : caption !== null && caption.role === "assistant" && caption.gen === state.gen ? caption.text : ""
    readonly property var shortcutKeys: service === null ? null : service.effectiveKeys
    // The ring of the orb at rest, which the icon row and the line under
    // the orb stand against.
    readonly property real ring: look.state.armed.radius * look.orb.size / 2
    readonly property var inputItems: [mic, voice, stop].concat(hold === null ? [] : [cancel, confirm])
        .concat(faultAction.visible && faultAction.linked ? [faultAction] : [])
    readonly property var stateWords: ({
        armed: "Say Hey Jarvis", idle: "Getting ready", listening: "Listening", thinking: "Thinking",
        acting: "Working", speaking: "Speaking", confirming: "Waiting for you", error: "", down: "Stopping"
    })

    // One button of the icon row: the look's glyph and ring colours, the
    // intent it sends, and its label with the effective key, or the label
    // alone with none. An inline component does not share this file's
    // scope (https://doc.qt.io/qt-6/qtqml-documents-definetypes.html#inline-components),
    // so each takes the look, the service and the keys. Its instances read
    // as type RowButton, not IconButton (qml-unit run, Qt 6.12.0), which
    // scripts/smoke/rows/jarvis-bubble.sh names.
    component RowButton: IconButton {
        required property var look
        required property var service
        required property var keys
        required property string intentName
        size: "sm"
        tooltip: keys === null || !keys[intentName] ? label : label + " (" + keys[intentName] + ")"
        restColor: look.icon.rest
        activeColor: look.icon.active
        onColor: look.palette.accent
        ringColor: look.icon.ring
        onClicked: if (service !== null) service.intent(intentName)
    }

    // One answer of the approval prompt in the look's form (Appearance.js
    // `answer`): Confirm or Yes on its fill with the shimmer, Cancel or No
    // as bare words. It is a qs.Ui Button handed the look's values, since a
    // surface draws no private control for what a component draws
    // (design-system.md § Components). The variant names the answer for
    // scripts/smoke/rows/jarvis-bubble.sh and sets the label's weight.
    component Answer: Button {
        required property var look
        property bool bare: false
        size: "sm"
        variant: bare ? "ghost" : "secondary"
        controlHeight: look.answer.height
        paddingX: look.answer.paddingX
        radius: look.answer.radius
        restFill: bare ? look.answer.clear : look.answer.fill
        hoverFill: bare ? look.answer.clear : look.answer.hoverFill
        pressedFill: look.answer.pressedFill
        borderColor: look.answer.clear
        textColor: bare ? look.answer.bareInk : look.answer.ink
        hoverTextColor: bare ? look.answer.bareHoverInk : look.answer.hoverInk
        ringColor: look.icon.ring
        shimmer: bare ? null : look.answer.shimmer
    }

    visible: shown
    Component.onCompleted: if (service !== null) service.attachBubble(root)
    Component.onDestruction: if (service !== null) service.detachBubble(root)

    Item {
        id: overlay
        // The box scripts/smoke/rows/jarvis-bubble.sh places.
        objectName: "overlay"
        readonly property real centre: width / 2
        readonly property real orbCentre: orb.y + orb.height / 2
        readonly property real below: orbCentre + root.ring + root.look.layout.below
        width: Math.min(root.look.layout.width, Math.max(0, root.width - 2 * root.look.layout.margin))
        height: Math.max(orb.y + orb.height, root.hold === null ? stateBox.y + stateBox.height : approvalText.y + approvalText.height)
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.look.layout.margin
        anchors.topMargin: root.look.layout.margin
        // AnchorChanges releases the bottom anchor as it sets the top one,
        // where two bindings could hold both for a moment and stretch the
        // overlay: https://doc.qt.io/qt-6/qml-qtquick-anchorchanges.html
        states: State {
            name: "top"
            when: root.overConsole
            AnchorChanges { target: overlay; anchors.bottom: undefined; anchors.top: root.top }
        }

        Words {
            id: words
            look: root.look
            x: overlay.centre - width / 2
            width: root.look.layout.prompt
            height: visible ? implicitHeight : 0
            text: root.words
        }

        // Waiting for the wake word is the resting look: the room's sound is
        // not speech to Jarvis, and a wait can last all day, so it draws no
        // level and stands still (ParticleOrb's driver).
        ParticleOrb {
            id: orb
            look: root.look
            x: overlay.centre - width / 2
            y: words.height
            width: root.look.orb.size
            height: root.look.orb.size
            phase: root.micMuted ? "muting" : root.phase
            capture: root.levels.capture || 0
            playback: root.levels.playback || 0
            active: root.shown
        }

        Row {
            id: icons
            x: overlay.centre + root.ring
            y: overlay.orbCentre - root.ring - height / 2
            RowButton {
                id: mic
                look: root.look
                service: root.service
                keys: root.shortcutKeys
                intentName: "mute"
                iconName: root.micMuted ? "mic-off" : "mic"
                label: root.micMuted ? "Turn on microphone" : "Mute microphone"
                checked: root.micMuted
            }
            RowButton {
                id: voice
                look: root.look
                service: root.service
                keys: root.shortcutKeys
                intentName: "voice-mute"
                iconName: root.voiceMuted ? "volume-x" : "volume-2"
                label: root.voiceMuted ? "Unmute Jarvis's voice" : "Mute Jarvis's voice"
                checked: root.voiceMuted
            }
            RowButton {
                id: stop
                look: root.look
                service: root.service
                keys: root.shortcutKeys
                intentName: "stop"
                iconName: "square"
                label: "Stop Jarvis"
            }
        }

        Column {
            id: stateBox
            x: overlay.centre - width / 2
            y: overlay.below
            width: root.look.layout.line
            visible: root.hold === null
            spacing: root.look.layout.gap
            Label {
                width: parent.width
                role: root.fault !== null ? "bodyStrong" : "label"
                color: root.fault !== null ? root.look.ink.title : root.look.ink.state
                text: root.stateText
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
            }
            // The fault's action, its page reference drawn as a link that
            // opens the page (design-system.md § Copy).
            LinkText {
                id: faultAction
                width: parent.width
                visible: root.fault !== null
                role: "body"
                color: root.look.ink.action
                linkColor: root.look.ink.link
                text: root.fault === null ? "" : root.fault.action
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                onPageActivated: (page, tab) => {
                    if (root.service !== null && root.service.shell !== null) root.service.shell.surfaces.openPage(page, tab);
                }
            }
        }

        Column {
            id: approvalText
            x: overlay.centre - width / 2
            y: overlay.below
            width: root.look.layout.prompt
            visible: root.hold !== null
            spacing: root.look.layout.gap
            readonly property var prompt: View.approvalPrompt(root.hold)
            // Recombine the actual drawn labels for the existing frame
            // identity check; a missing path or detail cannot acknowledge.
            readonly property string text: question.text + (prompt !== null && prompt.filePrompt ? "\n" + (fullPath.visible ? fullPath.text : "")
                + (prompt.detail ? "\n" + (payload.visible ? payload.text : "") : "") : "")
            Label {
                id: question
                width: parent.width
                role: "bodyStrong"
                color: root.look.ink.question
                text: approvalText.prompt === null ? "" : approvalText.prompt.question
                textFormat: Text.PlainText
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
            }
            Label {
                id: fullPath
                width: parent.width
                visible: text !== ""
                role: "hint"
                color: root.look.ink.path
                text: approvalText.prompt === null ? "" : approvalText.prompt.path
                textFormat: Text.PlainText
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
            }
            Label {
                id: payload
                width: parent.width
                visible: text !== ""
                role: "body"
                color: root.look.ink.payload
                text: approvalText.prompt === null ? "" : approvalText.prompt.payload
                textFormat: Text.PlainText
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
            }
            Label {
                width: parent.width
                visible: root.hold !== null && root.hold.physical
                role: "hint"
                color: root.look.ink.hint
                text: "Use the button or key to confirm."
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
            }
            Row {
                id: answerButtons
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: root.look.answer.gap
                // keyboard-path: the effective Confirm and Stop shortcuts.
                Answer {
                    id: cancel
                    look: root.look
                    bare: true
                    text: root.hold !== null && root.hold.purpose === "release" ? "No" : "Cancel"
                    onClicked: if (root.service !== null) root.service.cancelApproval(root.displayedHold)
                }
                Answer {
                    id: confirm
                    look: root.look
                    text: root.hold !== null && root.hold.purpose === "release" ? "Yes" : "Confirm"
                    onClicked: if (root.service !== null) root.service.confirmApproval(root.displayedHold, "button")
                }
            }
            // The key hints stand `layout.hints` under the answers: the
            // column's gap and the rest of that distance above the row.
            Item {
                width: parent.width
                height: answerHints.height + root.look.layout.hints - root.look.layout.gap
                visible: answerHints.hints.length > 0
                KeyHints {
                    id: answerHints
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    hints: root.shortcutKeys === null ? [] : [
                        {key: root.shortcutKeys.stop || "", text: root.hold !== null && root.hold.purpose === "release" ? "No" : "Cancel"},
                        {key: root.shortcutKeys.confirm || "", text: root.hold !== null && root.hold.purpose === "release" ? "Yes" : "Confirm"}
                    ]
                }
            }
        }
    }
}
