import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "Session.js" as Session
import "WidgetView.js" as View

Item {
    id: root
    property var screen: null
    property var service: null
    readonly property var host: QsWindow.window
    readonly property var state: service === null ? null : service.sessionState
    readonly property string phase: state === null ? "down" : Session.phaseOf(state)
    readonly property bool shown: service !== null && service.bubbleWanted && screen !== null
        && screen.name === service.focusedOutput
    readonly property bool presented: shown && visible && host !== null && host.presented === true
        && card.width > 0 && card.height > 0 && card.x >= 0 && card.y >= 0
        && card.width <= width && card.height + Theme.voiceBubble.margin <= height
    readonly property var hold: state !== null && state.approval.kind === "held" ? state.approval : null
    property var displayedHold: null
    readonly property bool approvalPresented: presented && displayedHold !== null && hold !== null
        && displayedHold.id === hold.id && displayedHold.digest === hold.digest && displayedHold.gen === hold.gen
        && approvalText.text === hold.text && approvalText.height >= approvalText.implicitHeight
    readonly property var inputItems: hold === null ? [mute, stop] : [mute, stop, confirm, cancel]
    onHoldChanged: {
        if (hold === null || displayedHold === null || hold.id !== displayedHold.id
                || hold.gen !== displayedHold.gen || hold.digest !== displayedHold.digest) displayedHold = null;
    }
    // Qt's backing Window.frameSwapped is the same presented-frame observation
    // LayerHost uses. A mapped old frame does not acknowledge new approval text.
    Connections {
        target: root.Window.window
        function onFrameSwapped() {
            if (root.hold === null || root.displayedHold !== null) return;
            const shown = root.hold;
            // LayerHost sets presented from this same frame. Observe it after
            // its handler, while retaining the identity this frame drew.
            Qt.callLater(() => {
                if (!root.presented || root.hold === null || root.hold.id !== shown.id
                        || root.hold.gen !== shown.gen || root.hold.digest !== shown.digest) return;
                root.displayedHold = shown;
                if (root.service !== null) root.service.shownApproval(root, shown);
            });
        }
    }
    readonly property string tone: state !== null && state.mute.kind !== "off" ? "muted"
        : phase === "error" ? "danger"
        : phase === "confirming" || phase === "acting" ? "warning"
        : phase === "speaking" ? "success" : phase === "thinking" ? "info" : "accent"
    // A fault reads as the bar says it: what went wrong, then what to do.
    readonly property var fault: phase === "error" ? View.faultText(state.fault) : null
    readonly property string stateText: state === null ? "" : state.mute.kind !== "off" ? "Muting"
        : fault !== null ? fault.title
        : phase === "idle" ? "Waiting for indicator" : phase === "down" ? "Stopping"
        : phase[0].toUpperCase() + phase.slice(1)
    readonly property var levels: service === null || service.shell === null ? {}
        : service.shell.status.values.level || {}
    readonly property var caption: service === null || service.shell === null ? null
        : service.shell.status.values.transcript || null
    // The user's words while they arrive, then Jarvis's for this conversation.
    // The status keeps an ended conversation's caption until the next one.
    readonly property string words: state === null ? ""
        : fault !== null ? fault.action
        : state.turn.kind === "collecting" ? state.turn.partial
        : caption !== null && caption.role === "assistant" && caption.gen === state.gen ? caption.text : ""

    visible: shown
    Component.onCompleted: if (service !== null) service.attachBubble(root)
    Component.onDestruction: if (service !== null) service.detachBubble(root)

    Surface {
        id: card
        level: "raised"
        width: Math.min(Theme.voiceBubble.maxWidth, Math.max(0, root.width - 2 * Theme.voiceBubble.margin))
        height: pane.implicitHeight
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.voiceBubble.margin

        Pane {
            id: pane
            anchors.fill: parent
            container: "panel"
            fitToContent: true
            bodySpacing: Theme.voiceBubble.gap

            RowLayout {
                width: pane.contentWidth
                spacing: Theme.voiceBubble.gap

                VoiceOrb {
                    tone: root.tone
                    level: root.levels.capture || 0
                    secondaryLevel: root.levels.playback || 0
                    active: root.shown
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.stack.row
                    Label {
                        Layout.fillWidth: true
                        role: "label"
                        text: root.stateText
                        elide: Text.ElideRight
                    }
                    // Qt elides wrapped text on the right alone, so the whole
                    // text hangs from the bottom of a clipped window and its
                    // newest lines are the ones drawn.
                    Item {
                        Layout.fillWidth: true
                        visible: tail.text !== ""
                        implicitHeight: Math.min(tail.implicitHeight, Theme.voiceBubble.textLines * tail.lineBox)
                        clip: true
                        Label {
                            id: tail
                            width: parent.width
                            y: parent.height - height
                            role: "body"
                            text: root.words
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                        }
                    }
                }
                IconButton {
                    id: mute
                    size: "sm"
                    iconName: "mic-off"
                    label: "Mute Jarvis"
                    onClicked: if (root.service !== null) root.service.intent("mute")
                    Tooltip {
                        text: root.service === null || root.service.effectiveKeys === null ? mute.label
                            : mute.label + (root.service.effectiveKeys.mute === null ? " (unbound)" : " (" + root.service.effectiveKeys.mute + ")")
                    }
                }
                IconButton {
                    id: stop
                    size: "sm"
                    iconName: "square"
                    label: "Stop Jarvis"
                    onClicked: if (root.service !== null) root.service.intent("stop")
                    Tooltip {
                        text: root.service === null || root.service.effectiveKeys === null ? stop.label
                            : stop.label + (root.service.effectiveKeys.stop === null ? " (unbound)" : " (" + root.service.effectiveKeys.stop + ")")
                    }
                }
            }
            Label {
                id: approvalText
                width: pane.contentWidth
                visible: root.hold !== null
                role: "body"
                text: root.hold === null ? "" : root.hold.text
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
            }
            Label {
                width: pane.contentWidth
                visible: root.hold !== null && root.hold.physical
                role: "hint"
                text: "Use the button or key to confirm."
                wrapMode: Text.Wrap
            }
            RowLayout {
                width: pane.contentWidth
                visible: root.hold !== null
                spacing: Theme.stack.inline
                // keyboard-path: the effective Confirm and Stop shortcuts.
                Button {
                    id: confirm
                    size: "sm"
                    text: root.hold !== null && root.hold.purpose === "release" ? "Yes" : "Confirm"
                    onClicked: if (root.service !== null) root.service.confirmApproval(root.displayedHold, "button")
                }
                Button {
                    id: cancel
                    size: "sm"
                    variant: "secondary"
                    text: root.hold !== null && root.hold.purpose === "release" ? "No" : "Cancel"
                    onClicked: if (root.service !== null) root.service.cancelApproval(root.displayedHold)
                }
            }
            KeyHints {
                visible: root.hold !== null
                hints: root.service === null || root.service.effectiveKeys === null ? [] : [
                    {key: root.service.effectiveKeys.confirm || "", text: root.hold !== null && root.hold.purpose === "release" ? "Yes" : "Confirm"},
                    {key: root.service.effectiveKeys.stop || "", text: "Cancel"}
                ]
            }
        }
    }
}
