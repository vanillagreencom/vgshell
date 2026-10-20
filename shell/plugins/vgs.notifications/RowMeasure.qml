import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
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
    readonly property real measuredHeight: (rowCard.summary.length > 0 ? Math.max(titleText.implicitHeight,
        rowCard.showsBadge ? rowCard.look.badge.size + Math.max(0, (titleMetrics.height - rowCard.look.badge.size) / 2) : 0) : 0)
        + (rowCard.singleLine ? 0 : bodyText.implicitHeight)
        + (rowCard.summary.length > 0 && !rowCard.singleLine ? spacing : 0)
    // The real card retains its original ColumnLayout height. The hidden
    // scan uses these same text items at the card's layout widths.
    function settleLayout() {
        ensurePolished();
        summaryRow.ensurePolished();
        ensurePolished();
    }
    function fullHeight(mediaHeight) { return Math.max(mediaHeight, measureOnly ? measuredHeight : implicitHeight) + 2 * rowCard.pad; }

    // The model measurer has no layout parent. Set the same widths the
    // card's RowLayout/ColumnLayout give these two text items, then read
    // Qt's actual wrapped text heights synchronously.
    function measure(entry, look, textColumn) {
        const enrichment = Logic.enrich(entry.app || "", entry.desktopEntry || "", entry.appIcon || "", entry.summary || "", entry.body || "");
        const single = Logic.sanitizeBody(entry.body || "", entry.app || "", entry.appIcon || "").length === 0;
        const source = entry.image || iconPath(entry.appIcon || "");
        const faces = enrichment !== null && enrichment.faces.length > 0;
        const glyph = single && Logic.summaryStartsWithGlyph(entry.summary || "");
        let hint = false;
        if ((entry.hintIcon || "").length > 0) {
            hintMeasure.active = true;
            hintMeasure.item.name = entry.hintIcon;
            hint = hintMeasure.item.paths[0] !== "";
        }
        const hasMedia = faces || (!glyph && (entry.hintIcon && !entry.image ? hint : source.length > 0 && imageStatus(source) !== Image.Error));
        const badge = enrichment !== null && (entry.workspace || "").length > 0 && imageStatus(entry.workspaceIcon || "", true) === Image.Ready;
        rowCard = { look: look, pad: look.card.pad, summary: entry.summary || "", title: badge ? enrichment.title : entry.summary || "",
            singleLine: single, showsBadge: badge, enrichment: enrichment, workspace: entry.workspace || "", workspaceIcon: entry.workspaceIcon || "",
            bodySegments: Logic.emojiSegments(Logic.styledBody(entry.body || "", entry.app || "", entry.appIcon || "", entry.hintPage || "", look.text.link), entry.emoji || null) };
        const mediaHeight = hasMedia ? look.media.size : 0;
        const textWidth = look.card.width - (hasMedia ? look.card.pad : textColumn) - textColumn - (hasMedia ? mediaHeight + look.card.gapIcon : 0);
        titleText.width = textWidth - (badge ? look.badge.size + look.badge.gap : 0);
        bodyText.width = textWidth;
        const summaryHeight = Math.max(titleText.implicitHeight, badge ? look.badge.size + Math.max(0, (titleMetrics.height - look.badge.size) / 2) : 0);
        bodyText.maximumLineCount = Math.max(1, Math.floor((look.card.maxHeight - 2 * look.card.pad - (rowCard.summary.length > 0 ? summaryHeight + spacing : 0)) / bodyMetrics.height));
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

        // The workspace's icon, level with the summary's first line.
        // Its image loads while hidden, and the name gives way to it
        // only once it has.
        ClippingRectangle {
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
            // Keep the original Text's font and line box while using Label's
            // shared capital placement. No typography role changes this title.
            font.variableAxes: ({})
            font.letterSpacing: rowCard.look.text.title.letterSpacing
            font.capitalization: Font.MixedCase
            lineHeight: rowCard.look.text.title.lineHeight
            lineHeightMode: Text.ProportionalHeight
            style: Text.Raised
            styleColor: rowCard.look.text.summaryShadow
            wrapMode: Text.WordWrap
            elide: Text.ElideRight
            maximumLineCount: rowCard.look.card.summaryLines
        }

        FontMetrics {
            id: titleMetrics
            font: titleText.font
        }
    }

    ImageText {
        id: bodyText
        objectName: "notificationBodyText"
        // The height left for the body under maxHeight, and so the
        // whole lines it shows; the last one elides.
        // The column's spacing is the one gap under the summary.
        readonly property real room: rowCard.look.card.maxHeight - 2 * rowCard.pad - (rowCard.summary.length > 0 ? summaryRow.implicitHeight + root.spacing : 0)
        Layout.fillWidth: true
        visible: !rowCard.singleLine
        // StyledText, since the server advertises body markup. The
        // body's fade is its colour's alpha, so an emoji draws at
        // full strength.
        segments: rowCard.bodySegments
        // The page hint's words, a link a click on the card opens, so
        // underlined while the pointer is on the card; a measurer draws none.
        underlined: root.measureOnly ? "" : rowCard.linkWords
        underlineColor: rowCard.look.text.link
        hovered: rowCard.hovered === true
        color: rowCard.look.text.body.color
        font: Qt.font({ family: rowCard.look.font.family.sans, pixelSize: rowCard.look.text.body.size })
        maximumLineCount: Math.max(1, Math.floor(room / bodyMetrics.height))
    }

    FontMetrics {
        id: bodyMetrics
        font: bodyText.font
    }
}
