import QtQuick
import qs.Commons
import qs.Ui
import "WidgetView.js" as View

// Jarvis's reply card under the bar J, declared in the J's BarItem: one
// shared MessageRow on a floating Card in qs.Ui's PassivePopup. The
// service's `replyCard` status holds the card's whole decision
// (WidgetView.replyCard): what it shows, in which mode, on which output, and
// when it hides. This file draws it: the answer cut at its first 4 lines,
// the words as Jarvis speaks them (Words.qml) while the voice speaks, or a
// fault in its plain words with its Settings link as its only action. It
// keeps what it drew while it closes. The pointer on the card holds it: the
// card tells the service through its `reply-hover` handler, and withdraws
// that claim when it stops showing or goes.
PassivePopup {
    id: root

    required property var shell
    readonly property var values: shell === null ? ({}) : shell.status.values
    readonly property var card: values.replyCard === undefined ? null : values.replyCard
    readonly property var output: OverlayState.outputOf(anchorItem)
    readonly property bool wanted: card !== null && output !== null && output.name === card.output
    readonly property var caption: values.transcript || null
    // What the card draws now, or null; `drawn` keeps the last of it while
    // the card closes.
    readonly property var live: {
        if (!wanted) return null;
        if (card.mode === "fault") return { mode: "fault", title: card.fault.title, action: card.fault.action, at: 0, text: "" };
        const row = Array.isArray(values.conversation) ? values.conversation.find(entry => View.isAnswer(entry, card.answer)) : undefined;
        if (row === undefined) return null;
        return { mode: card.mode, title: "", action: "", at: row.at,
            text: card.mode === "follow" && caption !== null ? String(caption.text) : String(row.text) };
    }
    property var drawn: null
    onLiveChanged: if (live !== null) drawn = live
    readonly property bool hovered: hover.hovered

    shown: live !== null
    width: Theme.size.panel.md
    onHoveredChanged: claim(hovered)
    onShownChanged: if (!shown && hovered) claim(false)
    Component.onDestruction: if (hovered) claim(false)

    function claim(on) {
        if (shell !== null) shell.ipc.call("reply-hover", on && shown ? "true" : "false");
    }

    Component {
        id: spokenWords
        // The words as Jarvis speaks them, in a box that grows a line at a
        // time up to the card's 4.
        Item {
            width: parent ? parent.width : 0
            height: Math.min(words.lineCount, words.window) * words.lineBox
            clip: true
            Words {
                id: words
                objectName: "replyWords"
                width: parent.width
                y: parent.height - implicitHeight
                window: 4
                stepDuration: Theme.motion.reveal.step
                fadeDuration: Theme.motion.duration.normal
                liftDuration: Theme.motion.duration.slow
                newestInk: Theme.color.text
                olderInk: Theme.color.textMuted
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

    Item {
        objectName: "replyCard"
        width: parent.width
        height: frame.implicitHeight

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
