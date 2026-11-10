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
// and tab. `linkText`, when set, is a RowAction under the lines in the
// state's link colours, which emits `activated`. `buttonText`, when set,
// is a secondary Button `callout.buttonGap` after the lines at the
// banner's right end, in the state's ink with its hover and pressed fills,
// which emits `buttonActivated`. The lines and the button centre on each
// other, so one line of text beside the button sits level with its label.
// Each link and the button is its own Tab stop, in that order, with the
// shared focus ring; `firstStop` is the first one shown, or null, for a
// host that routes Tab into the banner. A title-less, icon-less banner of
// one line and a button is the sheet-style error banner.
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
    readonly property var tokens: toneOf(tone)
    readonly property Item firstStop: body.visible && body.linked ? body : link.visible ? link : button.visible ? button : null
    // The first shown line, which the icon leads.
    readonly property Item leadLine: titleLabel.visible ? titleLabel : body

    signal activated()
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
    implicitHeight: band + 2 * Theme.callout.padding
    radius: Theme.callout.radius
    color: tokens.background

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
        y: Theme.callout.padding + Math.round((root.band - implicitHeight) / 2)
        width: Math.max(0, (button.visible ? button.x - Theme.callout.buttonGap : root.width - Theme.callout.padding) - x)
        spacing: Theme.callout.gap

        Label {
            id: titleLabel
            width: parent.width
            visible: text !== ""
            role: "bodyStrong"
            color: root.tokens.foreground
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
            text: root.text
            wrapMode: Text.Wrap
            onPageActivated: (page, tab) => root.pageActivated(page, tab)
        }
        RowAction {
            id: link
            visible: root.linkText !== ""
            text: root.linkText
            tokens: root.tokens.link
            onClicked: root.activated()
        }
    }

    Button {
        id: button
        visible: root.buttonText !== ""
        x: root.width - Theme.callout.padding - width
        y: Theme.callout.padding + Math.round((root.band - height) / 2)
        variant: "secondary"
        text: root.buttonText
        textColor: root.tokens.foreground
        borderColor: root.tokens.foreground
        hoverFill: root.tokens.button.hover
        pressedFill: root.tokens.button.pressed
        onClicked: root.buttonActivated()
    }
}
