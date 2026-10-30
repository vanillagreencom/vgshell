import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.Ui
import "NotificationLogic.js" as Logic

// One notification as a glass capsule: its image, the Lucide icon its
// x-vgs-icon hint names in the tone its x-vgs-tone hint names, or its
// application icon, its summary and its body, and the hover actions at
// its right end, beside the text, or in their place a muted caption. A sender
// a NotificationLogic rule reads shows the people it names as faces in the
// icon's place, and the workspace it belongs to as that workspace's icon,
// when there is one, before the rule's title in place of the summary. It draws no fill of its
// own: the GlassSurface under it paints the glass and the slot drives its
// size, its content fade and its lifetime. It holds no notification
// object, only the values it draws. A caption-only card, the stack's
// refusal toast, draws its caption alone.
Item {
    id: card

    required property var look
    property string app: ""
    property string appIcon: ""
    property string summary: ""
    readonly property string text: summary
    property string body: ""
    property string image: ""
    property string desktopEntry: ""
    // The VGS hint roles (NotificationLogic.entryOf): a Lucide name, for a
    // VGS plugin's notice that names none its tone's, and a status tone, or
    // "".
    property string hintAvatar: ""
    property string hintIcon: ""
    property string hintTone: ""
    // The x-vgs-page hint, whose words the body draws as a link.
    property string hintPage: ""
    // The workspace the card belongs to: the one `enrichment` names, or the
    // one the service resolved for it (NotificationLogic.slackWorkspaceFor),
    // or "".
    property string workspace: ""
    // The file URL of that workspace's icon, or "".
    property string workspaceIcon: ""
    // One file URL per face, from the optional Slack token cache.
    property var faceImages: []
    // The custom emoji of the card's workspace, name -> file URL, or null
    // (NotificationLogic.slackEmojiFor).
    property var emoji: null
    // The slot fades the content during its morph. The content keeps its
    // full-size layout and stays centred while the card is narrower, so the
    // text never reflows.
    property real contentOpacity: 1
    // [{ id, label }] shown as pills at the right edge while `showActions`.
    property var actions: []
    property bool showActions: false
    // A short muted line at the right end in the actions' place, such as
    // the no-action state the act shortcut leaves; "" for none.
    property string caption: ""
    // The last caption, which the tray keeps drawing while it fades out
    // after the caption ends, so the actions do not show for that fade.
    property string heldCaption: ""
    onCaptionChanged: if (caption !== "" || trayShown || tray.opacity === 0) heldCaption = caption
    readonly property bool captionMode: caption !== "" || (heldCaption !== "" && !(showActions && actions.length > 0))
    // A toast that is only its caption, the stack's refusal toast: as wide
    // and tall as the caption with `pad` all round. It takes no click.
    property bool captionOnly: false
    property int actionIndex: -1
    property bool keyboardActions: false
    readonly property bool hovered: hoverTracker.hovered
    readonly property real radius: look.radius.full
    signal actionTriggered(string id)
    signal closeRequested()
    signal cardClicked()

    readonly property real fullWidth: captionOnly ? Math.ceil(captionText.implicitWidth) + 2 * pad : look.card.width
    // The content, or a caption-only card's caption, with `pad` all round.
    // The content never outgrows maxHeight less that pad: the body shows
    // only the lines that fit.
    // A tray releasing the text width must finish the same real layouts
    // before its virtual slot can retain the collapsed card height.
    function settleHeight() {
        content.ensurePolished();
        textBlock.settleLayout();
    }
    readonly property real fullHeight: captionOnly ? Math.ceil(captionText.implicitHeight) + 2 * pad : textBlock.fullHeight(showsSlot ? mediaSlot.implicitHeight : 0)
    readonly property real pad: look.card.pad
    // The stack's text column: text without media starts this far in from
    // either end, and every text ends this far from the right end.
    required property real textColumn
    readonly property string iconSource: image.length > 0 ? image : iconPath(appIcon)
    readonly property string sanitizedBody: Logic.sanitizeBody(body, app, appIcon)
    // The body as ImageText segments: StyledText with every image tag
    // stripped and the page hint's words drawn as a link
    // (NotificationLogic.styledBody), and the workspace's custom emoji as
    // images (emojiSegments).
    readonly property var bodySegments: Logic.emojiSegments(Logic.styledBody(body, app, appIcon, hintPage, look.text.link), emoji)
    readonly property string linkWords: Logic.pageWords(hintPage)
    readonly property bool singleLine: sanitizedBody.length === 0
    readonly property bool iconInSummary: singleLine && Logic.summaryStartsWithGlyph(summary)
    // NotificationLogic.enrich's reading of this sender, or null.
    readonly property var enrichment: Logic.enrich(app, desktopEntry, appIcon, summary, body)
    readonly property bool showsFaces: enrichment !== null && enrichment.faces.length > 0
    readonly property bool showsBadge: enrichment !== null && workspace.length > 0 && workspaceIcon.length > 0 && textBlock.badgeStatus === Image.Ready
    // What the media slot draws: the people the rule read, else the
    // notification's image, else the Lucide icon its x-vgs-icon hint names,
    // else its application's icon; none when the one-line summary opens
    // with its own icon glyph. A hint name the Lucide set lacks draws no
    // media, and Icon logs it.
    readonly property string mediaKind: showsFaces ? "faces" : iconInSummary ? "" : image.length > 0 ? "thumbnail" : hintAvatar.length > 0 ? "avatar" : hintIcon.length > 0 ? "glyph" : iconSource.length > 0 ? "icon" : ""
    readonly property bool showsSlot: mediaKind !== "" && mediaSlot.drawable
    readonly property real contentLeftInset: showsSlot ? pad : textColumn
    readonly property real contentWidth: Math.max(0, fullWidth - contentLeftInset - textColumn)
    readonly property real contentOffset: contentLeftInset - (fullWidth - contentWidth) / 2
    readonly property real slotLeft: showsSlot ? content.x + mediaSlot.x : -1
    // While the actions show, the text gives way to them: the column ends
    // tray.gap before the first pill, so no line runs under a pill. The
    // card grows with the lines that adds, up to maxHeight, as at rest.
    // The text keeps giving way until the tray's fade out ends, since the
    // pills draw for the whole fade; only then does it take the whole
    // column back.
    readonly property bool trayShown: caption !== "" || (showActions && actions.length > 0)
    readonly property real trayReserve: trayShown || tray.visible ? Math.max(0, tray.width + look.tray.gap + pad - textColumn) : 0
    // The summary as drawn: the rule's title once the workspace's icon
    // stands in for the workspace.
    readonly property string title: showsBadge ? enrichment.title : summary

    // An icon value as an image source: a URL as it is, a path as a file
    // URL, a themed name through the icon theme, and nothing for a name the
    // theme lacks, so no placeholder is drawn.
    function iconPath(icon) {
        const value = String(icon || "");
        if (value.length === 0) return "";
        if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value;
        if (value.charAt(0) === "/") return "file://" + value;
        return Quickshell.iconPath(value, true);
    }

    implicitWidth: fullWidth
    implicitHeight: fullHeight
    clip: true

    HoverHandler { id: hoverTracker }

    // keyboard-path: the inbox panel's KeyNav selects this card, Enter opens it and Delete dismisses it; toasts take no keyboard
    MouseArea {
        anchors.fill: parent
        enabled: !card.captionOnly
        PointerCursor {}
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) card.closeRequested();
            else card.cardClicked();
        }
    }

    RowLayout {
        id: content
        anchors.verticalCenter: parent.verticalCenter
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.horizontalCenterOffset: card.contentOffset
        width: card.contentWidth
        opacity: card.contentOpacity
        spacing: card.showsSlot ? card.look.card.gapIcon : 0

        MediaSlot {
            id: mediaSlot
            objectName: "notificationMediaSlot"
            Layout.preferredWidth: implicitWidth
            Layout.preferredHeight: implicitHeight
            Layout.alignment: Qt.AlignVCenter
            visible: card.showsSlot
            look: card.look
            kind: card.mediaKind
            source: card.iconSource
            names: card.showsFaces ? card.enrichment.faces : []
            more: card.showsFaces ? card.enrichment.more : 0
            images: card.showsFaces ? card.faceImages : []
            carried: card.image
            glyph: card.mediaKind === "avatar" ? card.hintAvatar : card.hintIcon
            badgeGlyph: card.mediaKind === "avatar" ? card.hintIcon : ""
            badgeTone: card.hintTone
            glyphColor: card.hintTone === "" ? card.look.text.foreground : card.look.tone[card.hintTone]
        }

        RowMeasure {
            id: textBlock
            rowCard: card
            Layout.fillWidth: true
            Layout.rightMargin: card.trayReserve
            Layout.alignment: Qt.AlignVCenter
        }
    }

    // The hover actions at the right end, beside the text, the card's pad
    // in from its end, or the caption while there is one.
    Item {
        id: tray
        anchors.right: parent.right
        anchors.rightMargin: card.pad
        anchors.verticalCenter: parent.verticalCenter
        width: card.captionMode ? captionText.implicitWidth : actionRow.width
        height: card.captionMode ? captionText.implicitHeight : actionRow.height
        visible: opacity > 0
        opacity: card.trayShown && card.contentOpacity >= 1 ? 1 : 0
        Behavior on opacity { Anim { duration: card.look.motion.duration.short4; curve: card.look.motion.curve.standard } }
        onOpacityChanged: if (opacity === 0 && card.caption === "") card.heldCaption = ""
        transform: Translate { x: (1 - tray.opacity) * card.look.tray.slide }

        Text {
            id: captionText
            objectName: "notificationCaption"
            anchors.verticalCenter: parent.verticalCenter
            visible: card.captionMode
            textFormat: Text.PlainText
            text: card.caption !== "" ? card.caption : card.heldCaption
            color: card.look.text.subtitle.color
            font.family: card.look.font.family.sans
            font.pixelSize: card.look.text.subtitle.size
        }

        Row {
            id: actionRow
            visible: !card.captionMode
            spacing: card.look.tray.spacing
            Repeater {
                model: card.actions
                PillButton {
                    required property var modelData
                    required property int index
                    look: card.look
                    text: modelData.label
                    emphasized: modelData.id !== "dismiss"
                    focusPreview: card.showActions && card.actionIndex === index
                    tabFocusable: false
                    Tooltip {
                        text: card.keyboardActions ? modelData.label + (modelData.id === "dismiss"
                            ? " (Delete)" : " (Left/Right, then Enter)") : ""
                    }
                    onClicked: card.actionTriggered(modelData.id)
                }
            }
        }
    }
}
