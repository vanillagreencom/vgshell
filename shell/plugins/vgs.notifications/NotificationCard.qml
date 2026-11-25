import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import qs.Commons
import qs.Ui
import "NotificationLogic.js" as Logic

// The card holds plain display values, never a live notification object.
// Every title stays on one line and every body on at most two; no input expands it.
// Media and up to three full-label pills centre on its height.
// Pills overlay the unchanged text column over a soft horizontal gradient.
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
    // At most three right-side pills; overflow keeps every remaining action in Menu.
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
    readonly property bool menuOpened: overflowMenu.opened
    readonly property real radius: look.radius.full
    signal actionTriggered(string id)
    signal closeRequested()
    signal cardClicked()

    readonly property real fullWidth: captionOnly ? Math.ceil(captionText.implicitWidth) + 2 * pad : look.card.width
    // Finish the shared text layout before its virtual slot reads height.
    function settleHeight() {
        content.ensurePolished();
        textBlock.settleLayout();
    }
    readonly property real fullHeight: captionOnly ? Math.ceil(captionText.implicitHeight) + captionInset.topPadding + captionInset.bottomPadding : textBlock.fullHeight(showsSlot ? mediaSlot.implicitHeight : 0)
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
    readonly property bool trayShown: caption !== "" || (showActions && actions.length > 0) || overflowMenu.opened
    readonly property int buttonCount: Math.min(3, actions.length)
    // A mask reads alpha alone, so the native gradient never paints a
    // second ground over either glass or the standard card material.
    function maskColor(alpha) {
        const color = Qt.color(look.tray.fadeInk);
        color.a = alpha;
        return color;
    }
    function activateAction(index, opener) {
        if (index < 0 || index >= buttonCount) return false;
        if (actions.length > 3 && index === 2) overflowMenu.open(opener);
        else actionTriggered(actions[index].id);
        return true;
    }
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

    ClearingInset {
        id: captionInset
        pad: card.pad
        content: captionText
    }

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

    // Text ink, media and actions centre on the card at every content length.
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
            // Layouts fill height by default. Keep the text's preferred
            // line boxes instead of stretching its summary row to media,
            // which adds a second, rounded centring inside the ink offset.
            // https://doc.qt.io/qt-6/qml-qtquick-layouts-layout.html#fillHeight-attached-prop
            Layout.fillHeight: false
            Layout.alignment: Qt.AlignVCenter
            transform: Translate { y: textBlock.verticalOffset }
            // As CardScroll does, texture the text alone while its alpha
            // mask is needed; its layout and the media remain unchanged.
            // https://doc.qt.io/qt-6/qml-qtquick-effects-multieffect.html
            layer.enabled: card.visible && tray.visible && !card.captionOnly && width > 0 && height > 0
            layer.smooth: true
            layer.effect: MultiEffect {
                // ImageText's underline and styled ink extend outside the
                // layout box. MultiEffect pads both source and output in
                // its updateSourcePadding; it owns layer sourceRect too.
                // https://doc.qt.io/qt-6/qml-qtquick-effects-multieffect.html#paddingRect-prop
                paddingRect: Qt.rect(card.pad, card.pad, card.pad, card.pad)
                maskEnabled: true
                maskSource: actionMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1
            }
        }
    }

    Item {
        id: tray
        anchors.right: parent.right
        anchors.rightMargin: card.pad
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: card.captionOnly ? (captionInset.topPadding - captionInset.bottomPadding) / 2 : 0
        width: card.captionMode ? captionText.implicitWidth : actionRow.width
        height: card.captionMode ? captionText.implicitHeight : actionRow.height
        visible: opacity > 0
        opacity: card.trayShown && card.contentOpacity >= 1 ? 1 : 0
        Behavior on opacity { Anim { duration: card.look.motion.duration.short4; curve: card.look.motion.curve.standard } }
        onOpacityChanged: if (opacity === 0 && card.caption === "") card.heldCaption = ""
        transform: Translate { x: (1 - tray.opacity) * card.look.tray.slide }

        // The hidden gradient is texture alpha for the text's own layer,
        // mapped to the row's drawn start, including its slide and fade.
        // https://doc.qt.io/qt-6/qml-qtquick-gradient.html#orientation-prop
        Rectangle {
            id: actionMask
            objectName: "notificationActionMask"
            width: textBlock.width + 2 * card.pad
            height: textBlock.height + 2 * card.pad
            readonly property real rowStart: tray.x + (1 - tray.opacity) * card.look.tray.slide - content.x - textBlock.x + card.pad
            readonly property real fadeStart: Math.max(0, Math.min(1, (rowStart - card.look.tray.fadeWidth) / Math.max(1, width)))
            readonly property real fadeEnd: Math.max(0, Math.min(1, rowStart / Math.max(1, width)))
            readonly property real textAlpha: 1 - tray.opacity * (1 - card.look.tray.fadeAlpha)
            readonly property real rowTop: tray.y - content.y - textBlock.y - textBlock.verticalOffset + card.pad
            // The line box of the row's words, the labels' or the caption's,
            // centred in the row as each draws it.
            readonly property real wordsHeight: card.captionMode ? captionText.height
                : actionRepeater.count > 0 ? actionRepeater.itemAt(0).contentItem.contentHeight : 0
            readonly property real wordsTop: rowTop - card.pad + (tray.height - wordsHeight) / 2
            // The text lines fade whole: a line whose ink meets the words'
            // box fades, every other line keeps its ink, so the fade's
            // edges fall between two lines' ink and never cross a glyph.
            // Each edge sits one pixel past the kept line's ink, short of
            // the words and of the next line's ink, so the words read over
            // faded text alone. The band is in this mask's coordinates.
            readonly property var band: {
                // Each line's ink, top to bottom. The body's lines share
                // one font and line box, so each sits one pitch from the
                // next, with the first line's ink top and the last's bottom.
                const lines = [];
                if (card.summary.length > 0) lines.push({ inkTop: textBlock.inkAbove, inkBottom: textBlock.titleInkBottom });
                const count = textBlock.bodyLineCount;
                for (let i = 0; i < count; i++)
                    lines.push({
                        inkTop: textBlock.bodyInkTop + i * textBlock.bodyPitch,
                        inkBottom: textBlock.bodyInkBottom - (count - 1 - i) * textBlock.bodyPitch
                    });
                const wordsBottom = wordsTop + wordsHeight;
                let top = 0;
                let bottom = height;
                for (let i = 0; i < lines.length; i++)
                    if (lines[i].inkBottom < wordsTop)
                        top = card.pad + Math.min(lines[i].inkBottom + 1, wordsTop, i + 1 < lines.length ? lines[i + 1].inkTop : Infinity);
                for (let i = lines.length - 1; i >= 0; i--)
                    if (lines[i].inkTop > wordsBottom)
                        bottom = card.pad + Math.max(lines[i].inkTop - 1, wordsBottom, i > 0 ? lines[i - 1].inkBottom : -Infinity);
                return { top: top, bottom: bottom };
            }
            visible: false
            layer.enabled: textBlock.layer.enabled
            layer.smooth: true
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: card.look.tray.fadeInk }
                GradientStop { position: actionMask.fadeStart; color: card.look.tray.fadeInk }
                GradientStop { position: actionMask.fadeEnd; color: card.maskColor(actionMask.textAlpha) }
                GradientStop { position: 1; color: card.maskColor(actionMask.textAlpha) }
            }
            // Compose only texture alpha: these keep the ink of the lines
            // above and below the band within this same mask layer.
            // Qt layers capture the subtree, and child rectangles blend
            // above the parent's horizontal gradient, not above the card.
            // https://doc.qt.io/qt-6/qml-qtquick-item.html#item-layers
            Rectangle {
                width: parent.width
                height: actionMask.band.top
                color: card.look.tray.fadeInk
            }
            Rectangle {
                y: actionMask.band.bottom
                width: parent.width
                height: parent.height - y
                color: card.look.tray.fadeInk
            }
        }

        Label {
            id: captionText
            objectName: "notificationCaption"
            anchors.verticalCenter: parent.verticalCenter
            visible: card.captionMode
            textFormat: Text.PlainText
            text: card.caption !== "" ? card.caption : card.heldCaption
            color: card.look.text.subtitle.color
            font.family: card.look.font.family.sans
            font.pixelSize: card.look.text.subtitle.size
            lineHeight: card.look.text.title.lineHeight
            lineHeightMode: Text.ProportionalHeight
        }

        Row {
            id: actionRow
            visible: !card.captionMode
            spacing: card.look.tray.spacing
            Repeater {
                id: actionRepeater
                model: card.buttonCount
                PillButton {
                    id: actionPill
                    required property int index
                    look: card.look
                    readonly property bool overflow: card.actions.length > 3 && index === 2
                    readonly property var senderAction: card.actions[index]
                    objectName: "notificationAction" + index
                    text: overflow ? "…" : senderAction.label
                    emphasized: overflow || senderAction.id !== "dismiss"
                    focusPreview: card.showActions && card.actionIndex === index
                    tabFocusable: false
                    Tooltip {
                        text: actionPill.overflow ? "More actions"
                            : card.keyboardActions ? (actionPill.senderAction.id === "dismiss" ? "Delete" : "Left/Right, Enter") : ""
                    }
                    onClicked: card.activateAction(index, "pointer")
                }
            }
        }
    }
    Menu {
        id: overflowMenu
        objectName: "notificationOverflowMenu"
        // Repeater publishes its count after creating the delegates:
        // https://doc.qt.io/qt-6/qml-qtquick-repeater.html#count-prop
        parent: actionRepeater.count > 2 ? (actionRepeater.itemAt(2) || card) : card
        Repeater {
            model: card.actions.length > 3 ? card.actions.slice(2) : []
            MenuItem {
                required property var modelData
                text: modelData.label
                onTriggered: card.actionTriggered(modelData.id)
            }
        }
    }

}
