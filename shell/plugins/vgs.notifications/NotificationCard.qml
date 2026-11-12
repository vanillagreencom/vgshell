import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.Ui
import "NotificationLogic.js" as Logic

// The card holds plain display values, never a live notification object.
// Its slot owns size, content fade and lifetime; GlassSurface owns the fill.
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
    property string hintPage: ""
    // The workspace the card belongs to: the one `enrichment` names, or the
    // one the service resolved for it (NotificationLogic.slackWorkspaceFor),
    // or "".
    property string workspace: ""
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
    // [{ id, label }] shown while `showActions` as pills at the right edge,
    // beside the text where they fit, else in a row under it that ends
    // where the text ends.
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
    // A tray releasing the text width must finish the same real layouts
    // before its virtual slot can retain the collapsed card height.
    function settleHeight() {
        content.ensurePolished();
        textBlock.settleLayout();
    }
    readonly property real fullHeight: captionOnly ? Math.ceil(captionText.implicitHeight) + 2 * pad : textBlock.fullHeight(showsSlot ? mediaSlot.implicitHeight : 0) + trayBottomReserve
    readonly property real pad: look.card.pad
    // The stack's text column: text without media starts this far in from
    // either end, and every text ends this far from the right end.
    required property real textColumn
    readonly property string iconSource: image.length > 0 ? image : iconPath(appIcon)
    readonly property string sanitizedBody: Logic.sanitizeBody(body, app, appIcon)
    readonly property var bodySegments: Logic.emojiSegments(Logic.styledBody(body, app, appIcon, hintPage, look.text.link), emoji)
    readonly property string linkWords: Logic.pageWords(hintPage)
    readonly property bool singleLine: sanitizedBody.length === 0
    readonly property bool iconInSummary: singleLine && Logic.summaryStartsWithGlyph(summary)
    readonly property var enrichment: Logic.enrich(app, desktopEntry, appIcon, summary, body)
    readonly property bool showsFaces: enrichment !== null && enrichment.faces.length > 0
    readonly property bool showsBadge: enrichment !== null && workspace.length > 0 && workspaceIcon.length > 0 && textBlock.badgeStatus === Image.Ready
    readonly property string mediaKind: showsFaces ? "faces" : iconInSummary ? "" : image.length > 0 ? "thumbnail" : hintAvatar.length > 0 ? "avatar" : hintIcon.length > 0 ? "glyph" : iconSource.length > 0 ? "icon" : ""
    readonly property bool showsSlot: mediaKind !== "" && mediaSlot.drawable
    readonly property real contentLeftInset: showsSlot ? pad : textColumn
    readonly property real contentWidth: Math.max(0, fullWidth - contentLeftInset - textColumn)
    readonly property real contentOffset: contentLeftInset - (fullWidth - contentWidth) / 2
    readonly property real slotLeft: showsSlot ? content.x + mediaSlot.x : -1
    // Keep at least as much room for the message as for its actions.
    // A wider tray uses its own row instead of hiding the message.
    // Both reservations last until the last frame of the tray's fade.
    readonly property real textWidth: contentWidth - (showsSlot ? mediaSlot.implicitWidth + look.card.gapIcon : 0)
    readonly property bool trayBelow: !captionMode && tray.width + look.tray.gap > textWidth - tray.width
    readonly property bool trayShown: caption !== "" || (showActions && actions.length > 0)
    // Holders use a nonzero reserve to retain the card through its fade,
    // regardless of whether the tray takes horizontal or vertical space.
    readonly property real trayReserve: trayShown || tray.visible ? Math.max(0, tray.width + look.tray.gap + pad - textColumn) : 0
    readonly property real trayBottomReserve: trayBelow && (trayShown || tray.visible) ? tray.height + look.tray.gap : 0
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
        anchors.verticalCenterOffset: -card.trayBottomReserve / 2
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
            Layout.rightMargin: card.trayBelow ? 0 : card.trayReserve
            Layout.alignment: Qt.AlignVCenter
        }
    }

    Item {
        id: tray
        anchors.right: parent.right
        anchors.rightMargin: card.trayBelow ? card.textColumn : card.pad
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: card.trayBelow ? (card.fullHeight - 2 * card.pad - height) / 2 : 0
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
