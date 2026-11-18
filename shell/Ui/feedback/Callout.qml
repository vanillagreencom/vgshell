import QtQuick
import qs.Commons
import qs.Ui
import "../foundation/HintGround.js" as HintGround

// The notice banner: one thing a reader needs before the rows under it,
// such as an error that stops a feature, a warning that limits one, or a
// guide to read first. The banner blends callout.background over its
// container's published ground, with no border. `tone` names a group of
// `Theme.callout.tone`: `danger`, `warning` or `info`, the default; an
// unknown name is logged and drawn as `info`. The tone supplies the icon
// when `iconName` is empty. Only the leading icon
// takes its `foreground`; the title and text use callout.title in
// bodyStrong and callout.text in body, solved from normal text and muted
// text to the readability floor on the banner fill. The lines stand
// `callout.gap` apart, `callout.iconGap`
// after the icon. The icon centres on the first shown line as a leading
// icon centres (Label.topForLeadingIcon), the title's, or the text's when
// there is no title, so on several lines it stays at the top.
//
// The text may hold page references, `[words](page:<plugin id>/<tab>)`,
// drawn as links in running text (LinkText) in callout.link.foreground,
// solved from the accent to the same floor;
// A trailing line containing only a reference joins the bottom action row,
// before the other actions. Activating either form emits `pageActivated` with its page
// and tab. `plain` draws the title and the text as the characters they
// are, with no markup and no page or file reference, for words another
// program supplies: Text's default AutoText draws text that looks like
// markup as rich text
// (https://doc.qt.io/qt-6/qml-qtquick-text.html#textFormat-prop).
// `linkText`, when set, is a RowAction at the bottom in callout.link inks,
// which emits `activated`. `links`, a list of labels, are
// RowActions in that same bottom row, after `linkText`,
// wrapping at the banner's width; activating
// one emits `actionActivated` with its index in the list; each carries the
// title as its accessible description. `dismissible` offers a small
// IconButton X at the top right, centred on the title's first ink line, or the
// first text line when there is no title, and emits `dismissed`.
// `showDontShowAgain` offers a muted text link at the bottom right, in the
// calloutDismiss role and callout.dismiss ink, and emits `dontShowAgain`. The caller hides the
// banner and owns any saved choice. That link drops below the actions
// when they cannot fit beside it. Page links, bottom actions, Don't show
// this again and the X are independent Tab stops, in that order, with the
// shared focus ring; `firstStop` is the
// first one shown, or null, for a host that routes Tab into the banner.
// A title-less banner can keep its link inside its single text line.
//
// The banner has no motion of its own: it shows, hides and changes state
// at once, and the surface or layout that holds it moves it, under that
// owner's motion tokens.
// It takes its parent's width and wraps its lines.
Rectangle {
    id: root

    property string iconName: ""
    property string title: ""
    property string text: ""
    property string linkText: ""
    property string tone: "info"
    property bool plain: false
    property bool dismissible: false
    property bool showDontShowAgain: false
    property var links: []
    readonly property var message: splitMessage()
    readonly property var tokens: toneOf(tone)
    readonly property var ground: Theme.hintContext(null, () => HintGround.groundUnder(root, Window.window, true))
    readonly property Item firstStop: body.visible && body.linked ? body : pageRepeater.count > 0 ? pageRepeater.itemAt(0) : link.visible ? link : linkRepeater.count > 0 ? linkRepeater.itemAt(0) : dismissal.visible ? dismissal : close.visible ? close : null
    // The first shown line, which the icon leads.
    readonly property Item leadLine: titleLabel.visible ? titleLabel : plain ? plainBody : body

    signal activated()
    signal actionActivated(int index)
    signal pageActivated(string page, string tab)
    signal dismissed()
    signal dontShowAgain()

    // PageReference owns syntax and targets. Only whole trailing link lines
    // move; running-text references keep LinkText's inline treatment.
    function splitMessage() {
        if (plain) return { body: text, actions: [] };
        const parsed = PageReference.references(text);
        const actions = [];
        let plainEnd = parsed.text.length;
        let sourceEnd = text.length;
        for (let index = parsed.links.length - 1; index >= 0; index--) {
            const reference = parsed.links[index];
            const line = parsed.text.lastIndexOf("\n", reference.start - 1);
            if (reference.page === "" || line < 0 || parsed.text.slice(line + 1, reference.start).trim() !== ""
                    || parsed.text.slice(reference.end, plainEnd).trim() !== "") break;
            actions.unshift(reference);
            // Walk the known parsed literals backwards, so repeated labels
            // and targets retain their original source boundary.
            sourceEnd = text.lastIndexOf(reference.reference, sourceEnd - reference.reference.length);
            plainEnd = line;
        }
        return { body: actions.length > 0 ? text.slice(0, sourceEnd).replace(/\s+$/, "") : text, actions };
    }

    function toneOf(name) {
        const found = Theme.callout.tone[name];
        if (found !== undefined) return found;
        console.error("Callout: no tone named " + JSON.stringify(name));
        return Theme.callout.tone.info;
    }

    width: parent ? parent.width : implicitWidth
    implicitHeight: content.height + inset.topPadding + inset.bottomPadding
    radius: Theme.callout.radius
    border.width: 0
    color: ground === null ? Theme.callout.background : Theme.composite(Theme.callout.background, ground.fill)

    ClearingInset {
        id: inset
        pad: Theme.callout.padding
        content: content
    }

    Item {
        id: content
        width: root.width
        height: Math.max(lines.implicitHeight, close.visible ? close.y + close.height : 0)
        y: inset.topPadding

        Icon {
            id: icon
            name: root.iconName !== "" ? root.iconName : root.tokens.icon
            size: Theme.icon.size.md
            color: root.tokens.foreground
            x: Theme.callout.padding
            y: lines.y + root.leadLine.y + root.leadLine.topForLeadingIcon(height, lines.y + root.leadLine.y, true)
        }

        Column {
            id: lines
            x: Theme.callout.padding + (icon.visible ? icon.width + Theme.callout.iconGap : 0)
            width: Math.max(0, root.width - Theme.callout.padding - x)
            spacing: Theme.callout.gap

            Label {
                id: titleLabel
                width: Math.max(0, parent.width - (close.visible ? close.width + Theme.callout.iconGap : 0))
                visible: text !== ""
                role: "bodyStrong"
                color: Theme.callout.title
                textFormat: root.plain ? Text.PlainText : Text.AutoText
                text: root.title
                wrapMode: Text.Wrap
            }
            LinkText {
                id: body
                width: Math.max(0, parent.width - (!titleLabel.visible && close.visible ? close.width + Theme.callout.iconGap : 0))
                visible: text !== ""
                role: "body"
                color: Theme.callout.text
                linkColor: Theme.callout.link.foreground
                text: root.plain ? "" : root.message.body
                wrapAtSpaces: true
                wrapMode: Text.Wrap
                onPageActivated: (page, tab) => root.pageActivated(page, tab)
            }
            Label {
                id: plainBody
                width: Math.max(0, parent.width - (!titleLabel.visible && close.visible ? close.width + Theme.callout.iconGap : 0))
                visible: text !== ""
                role: "body"
                color: Theme.callout.text
                textFormat: Text.PlainText
                text: root.plain ? root.text : ""
                wrapMode: Text.Wrap
            }
            Item {
                id: footer
                width: parent.width
                // Read inputs, not effective child visibility: a hidden
                // parent's children are hidden too:
                // https://doc.qt.io/qt-6/qml-qtquick-item.html#visible-prop
                visible: root.message.actions.length > 0 || root.linkText !== "" || root.links.length > 0 || root.showDontShowAgain
                readonly property bool stacked: dismissal.visible && linkRow.lineWidth > width - dismissal.width - Theme.rowAction.gap
                implicitHeight: Math.max(linkRow.height, dismissal.visible ? dismissal.y + dismissal.height : 0)
                RowActions {
                    id: linkRow
                    width: footer.stacked || !dismissal.visible ? parent.width : Math.max(0, parent.width - dismissal.width - Theme.rowAction.gap)
                    // Repeater inserts its items in model order before the
                    // following child (doc.qt.io/qt-6/qml-qtquick-repeater.html).
                    Repeater {
                        id: pageRepeater
                        model: root.message.actions
                        RowAction {
                            required property var modelData
                            text: modelData.words
                            tokens: Theme.callout.link
                            Accessible.description: root.title
                            onClicked: root.pageActivated(modelData.page, modelData.tab)
                        }
                    }
                    RowAction {
                        id: link
                        visible: root.linkText !== ""
                        text: root.linkText
                        tokens: Theme.callout.link
                        onClicked: root.activated()
                    }
                    Repeater {
                        id: linkRepeater
                        model: root.links
                        RowAction {
                            required property string modelData
                            required property int index
                            text: modelData
                            tokens: Theme.callout.link
                            Accessible.description: root.title
                            onClicked: root.actionActivated(index)
                        }
                    }
                }
                LinkText {
                    id: dismissal
                    visible: root.showDontShowAgain
                    text: "Don't show this again"
                    link: text
                    role: "calloutDismiss"
                    color: Theme.callout.dismiss
                    linkColor: Theme.callout.dismiss
                    width: Math.min(implicitWidth, parent.width)
                    x: parent.width - width
                    y: footer.stacked ? linkRow.height + Theme.callout.gap : Math.max(0, (linkRow.height - height) / 2)
                    onActivated: root.dontShowAgain()
                }
            }
        }

        IconButton {
            id: close
            visible: root.dismissible
            x: root.width - Theme.callout.padding - width
            y: lines.y + root.leadLine.y + root.leadLine.topForLeadingIcon(height, lines.y + root.leadLine.y, true)
            size: "sm"
            iconName: "x"
            label: "Dismiss notice"
            onClicked: root.dismissed()
        }
    }
}
