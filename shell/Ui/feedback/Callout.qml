import QtQuick
import qs.Commons
import qs.Ui

// The notice banner: one thing a reader needs before the rows under it,
// such as an error that stops a feature, a warning that limits one, or a
// guide to read first. `tone` names its state, a group of
// `Theme.callout.tone`: `danger`, `warning` or `info`, the default; an
// unknown name is logged and drawn as `info`. The state's `background`
// fills the banner, inside `callout.padding`, and its `foreground` draws
// every part: the leading `iconName`, the `title` in the strong body role,
// the `text` in the body role under it, and the label and outline of the
// trailing button. The lines stand `callout.gap` apart, `callout.iconGap`
// after the icon. The icon centres on the first shown line as a leading
// icon centres (Label.topForLeadingIcon), the title's, or the text's when
// there is no title, so on several lines it stays at the top.
//
// The text may hold page references, `[words](page:<plugin id>/<tab>)`,
// drawn as links in running text (LinkText) in the state's
// `link.foreground`; activating one emits `pageActivated` with its page
// and tab. `plain` draws the title and the text as the characters they
// are, with no markup and no page or file reference, for words another
// program supplies: Text's default AutoText draws text that looks like
// markup as rich text
// (https://doc.qt.io/qt-6/qml-qtquick-text.html#textFormat-prop).
// `linkText`, when set, is a RowAction under the lines in the state's
// link colours, which emits `activated`. `links`, a list of labels, are
// RowActions in one RowActions row under the lines, after `linkText`'s,
// in the state's link colours, wrapping at the banner's width; activating
// one emits `actionActivated` with its index in the list; each carries the
// title as its accessible description. `buttonText`,
// when set, is a secondary Button `callout.buttonGap` after the lines at
// the banner's right end, in the state's ink with its hover and pressed
// fills, which emits `buttonActivated`. The lines and the button centre
// on each other, so one line of text beside the button sits level with
// its label. Each link, each of `links` and the button is its own Tab
// stop, in that order, with the shared focus ring; `firstStop` is the
// first one shown, or null, for a host that routes Tab into the banner.
// A title-less, icon-less banner of one line and a button is the
// sheet-style error banner.
//
// The banner has no motion of its own: it shows, hides and changes state
// at once, and the surface or layout that holds it moves it, under that
// owner's motion tokens. Its button's fill moves as every Button's does.
// It takes its parent's width and wraps its lines.
Rectangle {
    id: root

    property string iconName: ""
    property string title: ""
    property string text: ""
    property string linkText: ""
    property string buttonText: ""
    property string tone: "info"
    property bool plain: false
    property var links: []
    readonly property var tokens: toneOf(tone)
    readonly property Item firstStop: body.visible && body.linked ? body : link.visible ? link : linkRepeater.count > 0 ? linkRepeater.itemAt(0) : button.visible ? button : null
    // The first shown line, which the icon leads.
    readonly property Item leadLine: titleLabel.visible ? titleLabel : plain ? plainBody : body

    signal activated()
    signal actionActivated(int index)
    signal pageActivated(string page, string tab)
    signal buttonActivated()

    function toneOf(name) {
        const found = Theme.callout.tone[name];
        if (found !== undefined) return found;
        console.error("Callout: no tone named " + JSON.stringify(name));
        return Theme.callout.tone.info;
    }

    // The height the lines and the button share, each centred in it.
    readonly property real band: Math.max(lines.implicitHeight, button.visible ? button.height : 0)

    width: parent ? parent.width : implicitWidth
    implicitHeight: band + inset.topPadding + inset.bottomPadding
    radius: Theme.callout.radius
    color: tokens.background

    ClearingInset {
        id: inset
        pad: Theme.callout.padding
        content: content
    }

    Item {
        id: content
        width: root.width
        height: root.band
        y: inset.topPadding

        Icon {
            id: icon
            visible: root.iconName !== ""
            name: root.iconName
            size: Theme.icon.size.md
            color: root.tokens.foreground
            x: Theme.callout.padding
            y: lines.y + root.leadLine.y + root.leadLine.topForLeadingIcon(height, lines.y + root.leadLine.y)
        }

        Column {
            id: lines
            x: Theme.callout.padding + (icon.visible ? icon.width + Theme.callout.iconGap : 0)
            y: Math.round((root.band - implicitHeight) / 2)
            width: Math.max(0, (button.visible ? button.x - Theme.callout.buttonGap : root.width - Theme.callout.padding) - x)
            spacing: Theme.callout.gap

            Label {
                id: titleLabel
                width: parent.width
                visible: text !== ""
                role: "bodyStrong"
                color: root.tokens.foreground
                textFormat: root.plain ? Text.PlainText : Text.AutoText
                text: root.title
                wrapMode: Text.Wrap
            }
            LinkText {
                id: body
                width: parent.width
                visible: text !== ""
                role: "body"
                color: root.tokens.foreground
                linkColor: root.tokens.link.foreground
                text: root.plain ? "" : root.text
                wrapMode: Text.Wrap
                onPageActivated: (page, tab) => root.pageActivated(page, tab)
            }
            Label {
                id: plainBody
                width: parent.width
                visible: text !== ""
                role: "body"
                color: root.tokens.foreground
                textFormat: Text.PlainText
                text: root.plain ? root.text : ""
                wrapMode: Text.Wrap
            }
            RowAction {
                id: link
                visible: root.linkText !== ""
                text: root.linkText
                tokens: root.tokens.link
                onClicked: root.activated()
            }
            RowActions {
                id: linkRow
                width: parent.width
                visible: root.links.length > 0
                Repeater {
                    id: linkRepeater
                    model: root.links
                    RowAction {
                        required property string modelData
                        required property int index
                        text: modelData
                        // The title tells a screen reader which banner's
                        // action this is, so two banners' Stop links differ.
                        Accessible.description: root.title
                        tokens: root.tokens.link
                        onClicked: root.actionActivated(index)
                    }
                }
            }
        }

        Button {
            id: button
            visible: root.buttonText !== ""
            x: root.width - Theme.callout.padding - width
            y: Math.round((root.band - height) / 2)
            variant: "secondary"
            text: root.buttonText
            textColor: root.tokens.foreground
            borderColor: root.tokens.foreground
            hoverFill: root.tokens.button.hover
            pressedFill: root.tokens.button.pressed
            onClicked: root.buttonActivated()
        }
    }
}
