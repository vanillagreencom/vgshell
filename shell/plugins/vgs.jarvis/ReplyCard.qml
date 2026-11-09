import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "AccountProviders.js" as Providers
import "Session.js" as Session
import "WidgetView.js" as View

// Jarvis's reply card under the bar J, declared in the J's BarItem: one
// shared MessageRow on a floating Card. The service's `replyCard` status
// names what it shows and when it hides (WidgetView.replyCard); this file
// draws it, on the output that status names, which is the focused one.
// An answer is cut at its first 4 lines; while the voice speaks it, the
// row's body is Words.qml, the words as Jarvis speaks them; a fault reads
// in its plain words with its Settings link as its only action. The
// pointer on the card holds it: the card tells the service through its
// `reply-hover` handler. It opens and closes with the bar flyouts' fade
// and slide (`motion.flyout`), at once at motion scale 0, and keeps what
// it drew while it closes.
Item {
    id: root

    required property var shell
    readonly property Item anchorItem: parent
    readonly property var values: shell === null ? ({}) : shell.status.values
    readonly property var card: values.replyCard === undefined ? null : values.replyCard
    readonly property var output: OverlayState.outputOf(anchorItem)
    readonly property bool wanted: card !== null && output !== null && output.name === card.output
    readonly property var state: values.detail === undefined || values.detail === null ? null : values.detail.state
    readonly property var answerRow: !wanted || card.answer === null || !Array.isArray(values.conversation) ? null
        : values.conversation.find(row => row.role === "assistant" && row.gen === card.answer.gen && row.at === card.answer.at) || null
    readonly property var caption: values.transcript || null
    // What the card draws now, or null; `drawn` keeps the last of it while
    // the card closes.
    readonly property var live: {
        if (!wanted || state === null) return null;
        if (card.fault) {
            if (Session.phaseOf(state) !== "error") return null;
            const fault = View.faultText(state.fault, state.engine.kind, Providers.cloudVoice(shell.settings.voiceProvider));
            return { mode: "fault", title: fault.title, action: fault.action, at: 0, text: "" };
        }
        if (answerRow === null) return null;
        const speaking = state.voiceMute.kind !== "on" && Session.phaseOf(state) === "speaking"
            && caption !== null && caption.role === "assistant" && caption.gen === answerRow.gen;
        return { mode: speaking ? "follow" : "answer", title: "", action: "", at: answerRow.at,
            text: speaking ? String(caption.text) : String(answerRow.text) };
    }
    property var drawn: null
    onLiveChanged: if (live !== null) drawn = live
    readonly property bool shown: live !== null
    readonly property bool hovered: hover.hovered
    // Whether the card is on screen, closing included, and its box under
    // the J, which the widget declares as its cover.
    readonly property bool drawing: window.visible
    readonly property real cardWidth: window.implicitWidth
    readonly property real cardHeight: window.implicitHeight
    // How far the card has come in: 0 closed, 1 open.
    property real motionProgress: 0

    visible: false
    onHoveredChanged: if (shell !== null) shell.ipc.call("reply-hover", hovered ? "true" : "false")
    onShownChanged: {
        if (shown) window.visible = true;
        setMotion(shown ? 1 : 0);
    }

    function setMotion(target) {
        motion.stop();
        if (Theme.motion.flyout.travel.duration <= 0) {
            motionProgress = target;
            if (target === 0) window.visible = false;
            return;
        }
        motion.to = target;
        motion.duration = Theme.motion.flyout.travel.duration;
        motion.easing.type = Theme.motion.flyout.travel.easing;
        motion.start();
    }

    NumberAnimation {
        id: motion
        target: root
        property: "motionProgress"
        onStopped: if (!root.shown && root.motionProgress === 0) window.visible = false
    }

    // The words as Jarvis speaks them, in a box that grows a line at a time
    // up to the card's 4.
    Component {
        id: spokenWords
        Item {
            readonly property int lineCount: words.lineCount
            readonly property bool lifting: words.lift > 0
            width: parent ? parent.width : 0
            height: Math.min(words.lineCount, words.window) * words.lineBox
            clip: true
            Words {
                id: words
                width: parent.width
                y: parent.height - implicitHeight
                window: 4
                stepDuration: Theme.motion.reveal.step
                fadeDuration: Theme.motion.duration.normal
                liftDuration: Theme.motion.duration.slow
                newestInk: Theme.color.text
                middleInk: Theme.color.textMuted
                oldestInk: Theme.color.textMuted
                newestOpacity: 1
                middleOpacity: 1
                oldestOpacity: 1
                horizontalAlignment: Text.AlignLeft
                text: root.drawn === null || root.drawn.mode !== "follow" ? "" : root.drawn.text
            }
        }
    }
    Component {
        id: faultAction
        LinkText {
            width: parent ? parent.width : 0
            role: "body"
            color: Theme.color.textMuted
            wrapMode: Text.Wrap
            text: root.drawn === null ? "" : root.drawn.action
            onPageActivated: (page, tab) => root.shell.surfaces.openPage(page, tab)
        }
    }

    PopupWindow {
        id: window
        anchor.item: root.anchorItem
        anchor.edges: Edges.Bottom | Edges.Right
        anchor.gravity: Edges.Bottom | Edges.Left
        anchor.adjustment: PopupAdjustment.Slide
        anchor.margins.bottom: -Theme.popover.gap
        // No grab: the card never takes the keyboard (Tooltip.qml).
        grabFocus: false
        visible: false
        color: "transparent"
        implicitWidth: Theme.size.panel.md
        implicitHeight: Math.max(1, frame.implicitHeight)
        readonly property AnchorTracker tracker: AnchorTracker { popup: window; anchor: root.anchorItem }

        // The card fades as one image while it moves (SummonPopup.qml).
        Item {
            objectName: "replyCard"
            anchors.fill: parent
            opacity: root.motionProgress
            layer.enabled: root.motionProgress < 1
            transform: Translate { y: -Theme.motion.flyout.slide * (1 - root.motionProgress) }

            Card {
                id: frame
                floating: true
                width: parent.width

                MessageRow {
                    id: row
                    readonly property string mode: root.drawn === null ? "" : root.drawn.mode
                    width: parent.width
                    sender: "Jarvis"
                    avatarIcon: "vgs-letter-j"
                    timeText: mode === "fault" || root.drawn === null ? "" : Timestamp.text(root.drawn.at, Time.now.getTime())
                    stateText: mode === "fault" ? "Problem" : mode === "follow" ? "Speaking" : ""
                    stateTone: mode === "fault" ? "danger" : "neutral"
                    title: mode === "fault" ? root.drawn.title : ""
                    bodyText: mode === "answer" ? root.drawn.text : ""
                    bodyLines: 4
                    cutHint: "Click to read the full answer"
                    bodyComponent: mode === "follow" ? spokenWords : mode === "fault" ? faultAction : null
                }
            }

            HoverHandler { id: hover }
            // A fault's one action is its link; an answer takes the click.
            PointerCursor { enabled: row.mode !== "fault" }
            // keyboard-path: the Open Jarvis console shortcut runs the same
            // Service.summonConsole, which opens the console at this answer
            TapHandler {
                enabled: row.mode !== "fault"
                onTapped: {
                    const reply = root.shell.ipc.call("console", "");
                    if (reply !== "ok") console.warn("jarvis reply card: console " + reply);
                }
            }
        }
    }
}
