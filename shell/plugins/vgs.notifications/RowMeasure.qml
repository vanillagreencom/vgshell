import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.Commons
import qs.Ui
import "NotificationLogic.js" as Logic

// The card's actual title/body layout, also reused by one hidden measurer.
// No offscreen card, glass, media, hover handler or action tray is built.
ColumnLayout {
    required property var rowCard
    property bool measureOnly: false
    property var imageStates: ({})
    signal resourcesChanged(string source)
    Component {
        id: imageState
        Image {
            property bool badge: false
            // Qt Image.sourceSize bounds stored pixels, unlike item width:
            // https://doc.qt.io/qt-6/qml-qtquick-image.html#sourceSize-prop
            // Status probes need no more pixels than the painted owners.
            readonly property real decodeSize: (badge ? root.rowCard.look.badge.size
                : Math.max(root.rowCard.look.media.size, root.rowCard.look.media.icon)) * Screen.devicePixelRatio
            sourceSize: Qt.size(decodeSize, decodeSize)
            visible: false
            asynchronous: true
            cache: false
            onStatusChanged: if (status === Image.Error || badge && status === Image.Ready) root.resourcesChanged(String(source))
        }
    }
    function imageStatus(source, badge) {
        if (source.length === 0) return Image.Null;
        let item = imageStates[source];
        if (item === undefined) {
            item = imageState.createObject(root, { badge: badge === true, source: source });
            imageStates[source] = item;
        }
        if (badge === true) item.badge = true;
        return item.status;
    }
    function trimImages(entries) {
        const limit = 2 * (Logic.HISTORY_MAX + Logic.LIVE_MAX);
        const sources = Object.keys(imageStates);
        if (sources.length <= limit) return;
        const used = new Set();
        for (const entry of entries) {
            used.add(entry.workspaceIcon || "");
            used.add(entry.image || iconPath(entry.appIcon || ""));
        }
        let excess = sources.length - limit;
        for (const source of sources) {
            if (excess <= 0) break;
            if (!used.has(source)) { imageStates[source].destroy(); delete imageStates[source]; --excess; }
        }
    }
    readonly property int badgeStatus: badgeImage.status
    // Both producers use the layout, including its preferred-size rounding
    // and the height it assigns to wrapped text. QQuickLayout uses explicit
    // child visibility, not inherited visibility, so the hidden measurer
    // participates in exactly the same layout without drawing.
    // https://code.qt.io/cgit/qt/qtdeclarative.git/tree/src/quicklayouts/qquicklayout.cpp?h=6.11
    function settleLayout() {
        ensurePolished();
        summaryRow.ensurePolished();
        ensurePolished();
        inset.settle();
    }
    // Ink belongs to this layout's coordinates, including the positions
    // its nested layouts assign. Logical content flags also hold while
    // the shared model measurer inherits visible=false.
    readonly property real inkAbove: {
        let first = Infinity;
        if (rowCard.summary.length > 0) {
            first = summaryRow.y + titleText.y + titleText.inkAbove;
            if (rowCard.showsBadge) first = Math.min(first, summaryRow.y + workspaceBadge.y);
        }
        if (!rowCard.singleLine) first = Math.min(first, bodyText.y + bodyText.inkAbove);
        return first === Infinity ? 0 : first;
    }
    readonly property real inkBelow: {
        let last = -Infinity;
        if (rowCard.summary.length > 0) {
            last = summaryRow.y + titleText.y + titleText.height - titleText.inkBelow;
            if (rowCard.showsBadge) last = Math.max(last, summaryRow.y + workspaceBadge.y + workspaceBadge.height);
        }
        if (!rowCard.singleLine) last = Math.max(last, bodyText.y + bodyText.height - bodyText.inkBelow);
        return last === -Infinity ? 0 : height - last;
    }
    ClearingInset {
        id: inset
        pad: root.rowCard.pad
        content: root
    }
    // Where the text block's top stands in the card: beside media
    // MEDIAHEIGHT tall, which stands `pad` down, a title alone on one line
    // centres on the media (Label.topForLeadingIcon), and other text
    // shorter than the media centres its ink on it. Taller text has its
    // first line's ink `pad` down; the two meet where the ink is as tall
    // as the media, so a growing card keeps its top. The ink edges are the
    // inset's settled ones: the live edges read assigned geometry, a
    // binding loop through the card's placement.
    function textTop(mediaHeight) {
        if (mediaHeight <= 0) return inset.topPadding;
        if (rowCard.singleLine && rowCard.summary.length > 0 && titleText.lineCount === 1)
            return Math.max(inset.topPadding, rowCard.pad - summaryRow.y - titleText.y - titleText.topForLeadingIcon(mediaHeight));
        return Math.max(inset.topPadding, rowCard.pad + (mediaHeight - inset.topInk - implicitHeight + inset.bottomInk) / 2);
    }
    function fullHeight(mediaHeight) { return Math.max(mediaHeight + 2 * rowCard.pad, textTop(mediaHeight) + implicitHeight + inset.bottomPadding); }
    // Centres the ink, not the line boxes, of text without media.
    readonly property real verticalOffset: (inset.topPadding - inset.bottomPadding) / 2
    // The centre of the first line box in this layout: the title's, or
    // the body's when there is no title.
    readonly property real firstLineCentre: rowCard.summary.length > 0
        ? summaryRow.y + titleText.y + bodyText.titleLine / 2
        : bodyText.y + bodyText.implicitHeight / Math.max(1, bodyText.lineCount) / 2
    // Qt Text's own default maximumLineCount, no limit:
    // https://doc.qt.io/qt-6/qml-qtquick-text.html#maximumLineCount-prop
    readonly property int noLimit: 2147483647
    readonly property bool opened: rowCard.open === true

    // The model measurer has no layout parent. Give this same layout the
    // card's text-column width, rather than overwriting its children's
    // width and maximumLineCount bindings and adding their line boxes in
    // a second height implementation.
    function measure(entry, look, textColumn) {
        const enrichment = Logic.enrich(entry.app || "", entry.desktopEntry || "", entry.appIcon || "", entry.summary || "", entry.body || "");
        const single = Logic.sanitizeBody(entry.body || "", entry.app || "", entry.appIcon || "").length === 0;
        const source = entry.image || iconPath(entry.appIcon || "");
        const faces = enrichment !== null && enrichment.faces.length > 0;
        const glyph = single && Logic.summaryStartsWithGlyph(entry.summary || "");
        let hint = false;
        const glyphHint = entry.hintAvatar || entry.hintIcon || "";
        if (glyphHint.length > 0) {
            hintMeasure.active = true;
            hintMeasure.item.name = glyphHint;
            hint = hintMeasure.item.paths[0] !== "";
        }
        const hasMedia = faces || (!glyph && (glyphHint && !entry.image ? hint : source.length > 0 && imageStatus(source) !== Image.Error));
        const badge = enrichment !== null && (entry.workspace || "").length > 0 && imageStatus(entry.workspaceIcon || "", true) === Image.Ready;
        rowCard = { look: look, pad: look.card.pad, summary: entry.summary || "", title: badge ? enrichment.title : entry.summary || "",
            singleLine: single, showsBadge: badge, enrichment: enrichment, workspace: entry.workspace || "", workspaceIcon: entry.workspaceIcon || "",
            bodySegments: Logic.emojiSegments(Logic.styledBody(entry.body || "", entry.app || "", entry.appIcon || "", entry.hintPage || "", look.text.link), entry.emoji || null) };
        const mediaHeight = hasMedia ? look.media.size : 0;
        const textWidth = look.card.width - (hasMedia ? look.card.pad : textColumn) - textColumn - (hasMedia ? mediaHeight + look.card.gapIcon : 0);
        width = textWidth;
        // Both a live card's settleHeight and the synchronous model scan
        // finish the same layout and ink publication before reading size.
        settleLayout();
        return fullHeight(mediaHeight);
    }
    function iconPath(icon) {
        if (icon.length === 0) return "";
        if (icon.startsWith("file://") || icon.startsWith("image://")) return icon;
        if (icon.startsWith("/")) return "file://" + icon;
        return Quickshell.iconPath(icon, true);
    }
    Loader {
        id: hintMeasure
        visible: false
        active: false
        sourceComponent: Icon {}
    }
    id: root
    spacing: rowCard.look.card.lineGap

    RowLayout {
        id: summaryRow
        Layout.fillWidth: true
        visible: rowCard.summary.length > 0
        spacing: rowCard.showsBadge ? rowCard.look.badge.gap : 0

        // Load while hidden so the workspace name stays until its icon is ready.
        ClippingRectangle {
            id: workspaceBadge
            objectName: "notificationBadge"
            Layout.preferredWidth: rowCard.showsBadge ? rowCard.look.badge.size : 0
            Layout.preferredHeight: rowCard.look.badge.size
            Layout.alignment: Qt.AlignTop
            Layout.topMargin: Math.max(0, (titleMetrics.height - rowCard.look.badge.size) / 2)
            visible: rowCard.showsBadge
            radius: rowCard.look.badge.radius
            color: rowCard.look.badge.fill

            Image {
                id: badgeImage
                anchors.fill: parent
                source: !root.measureOnly && rowCard.enrichment !== null && rowCard.workspace.length > 0 ? rowCard.workspaceIcon : ""
                // The helper rewrites the same file when it reads
                // the workspace list again.
                cache: false
                sourceSize.width: rowCard.look.badge.size * Screen.devicePixelRatio
                sourceSize.height: rowCard.look.badge.size * Screen.devicePixelRatio
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                smooth: true
            }
        }

        Label {
            id: titleText
            objectName: "notificationTitleText"
            // The specification makes the summary one line of plain
            // text, so it is never read as markup.
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: rowCard.title
            color: rowCard.look.text.foreground
            font.family: rowCard.look.font.family.sans
            // Qt propagates a hidden parent's visible=false to its children:
            // https://doc.qt.io/qt-6/qml-qtquick-item.html#visible-prop
            // The hidden measurer must select the font from content instead.
            font.pixelSize: rowCard.summary.length > 0 ? rowCard.look.text.title.size : rowCard.look.text.body.size
            font.weight: rowCard.summary.length > 0 ? rowCard.look.text.title.weight : Font.Normal
            // Label's capital placement must preserve this title's font and line box.
            font.variableAxes: ({})
            font.letterSpacing: rowCard.look.text.title.letterSpacing
            font.capitalization: Font.MixedCase
            lineHeight: rowCard.look.text.title.lineHeight
            lineHeightMode: Text.ProportionalHeight
            style: Text.Raised
            styleColor: rowCard.look.text.summaryShadow
            wrapMode: Text.WordWrap
            elide: Text.ElideRight
            maximumLineCount: root.opened ? root.noLimit : rowCard.look.card.summaryLines
        }

        FontMetrics {
            id: titleMetrics
            font: titleText.font
        }
    }

    ImageText {
        id: bodyText
        objectName: "notificationBodyText"
        // The height left for the body under maxHeight beside a closed
        // title, and so the whole lines a closed card shows; the last one
        // elides. The column's spacing is the one gap under the summary.
        readonly property real titleLine: titleText.implicitHeight / Math.max(1, titleText.lineCount)
        readonly property real room: rowCard.look.card.maxHeight - 2 * rowCard.pad - (rowCard.summary.length > 0 ? titleLine * rowCard.look.card.summaryLines + root.spacing : 0)
        readonly property int restLines: Math.min(rowCard.look.card.bodyLines, Math.max(1, Math.floor(room / bodyMetrics.height)))
        Layout.fillWidth: true
        visible: !rowCard.singleLine
        // StyledText, since the server advertises body markup. The
        // body's fade is its colour's alpha, so an emoji draws at
        // full strength.
        segments: rowCard.bodySegments
        // The page hint's words, a link a click on the card opens; words
        // that are the whole body underline while the pointer is on the
        // card alone. A measurer draws none.
        underlined: root.measureOnly ? "" : rowCard.linkWords
        underlineColor: rowCard.look.text.link
        hovered: rowCard.hovered === true
        color: rowCard.look.text.body.color
        font: Qt.font({ family: rowCard.look.font.family.sans, pixelSize: rowCard.look.text.body.size })
        maximumLineCount: root.opened ? root.noLimit : restLines
    }

    FontMetrics {
        id: bodyMetrics
        font: bodyText.font
    }
}
