import QtQuick
import qs.Commons
import qs.Ui

// One thing a reader needs before the rows under it, such as a guide to
// read before a page's first step: `title` in the strong body role, `text`
// in the body role's muted colour under it, and `linkText`, when set, a
// RowAction under them that emits `activated`. The lines stand
// `callout.gap` apart beside a leading `iconName`, `callout.iconGap` from
// them, centred on the title's first line as a leading icon centres
// (Label.topForLeadingIcon), inside `callout.padding` on the faint fill of
// `tone`, a group of `Theme.callout.tone` (`accent`, `info`, `warning` or
// `danger`), whose text colour the icon takes; an unknown tone is logged
// and drawn as `accent`. It takes its parent's width and wraps its lines.
Rectangle {
    id: root

    property string iconName: ""
    property string title: ""
    property string text: ""
    property string linkText: ""
    property string tone: "accent"
    readonly property var tokens: toneOf(tone)

    signal activated()

    function toneOf(name) {
        const found = Theme.callout.tone[name];
        if (found !== undefined) return found;
        console.error("Callout: no tone named " + JSON.stringify(name));
        return Theme.callout.tone.accent;
    }

    width: parent ? parent.width : implicitWidth
    implicitHeight: lines.implicitHeight + 2 * Theme.callout.padding
    radius: Theme.callout.radius
    color: tokens.background

    Icon {
        id: icon
        visible: root.iconName !== ""
        name: root.iconName
        size: Theme.icon.size.md
        color: root.tokens.foreground
        x: Theme.callout.padding
        y: Theme.callout.padding + titleLabel.topForLeadingIcon(height)
    }

    Column {
        id: lines
        x: Theme.callout.padding + (icon.visible ? icon.width + Theme.callout.iconGap : 0)
        y: Theme.callout.padding
        width: Math.max(0, root.width - x - Theme.callout.padding)
        spacing: Theme.callout.gap

        Label {
            id: titleLabel
            width: parent.width
            visible: text !== ""
            role: "bodyStrong"
            text: root.title
            wrapMode: Text.Wrap
        }
        Label {
            width: parent.width
            visible: text !== ""
            role: "body"
            color: Theme.color.textMuted
            text: root.text
            wrapMode: Text.Wrap
        }
        RowAction {
            visible: root.linkText !== ""
            text: root.linkText
            onClicked: root.activated()
        }
    }
}
