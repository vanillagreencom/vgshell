import QtQuick
import QtQuick.Window
import qs.Commons
import qs.Ui
import "ImageTextLogic.js" as Logic

// StyledText with local images inline, such as a chat's custom emoji:
// `segments` is a list of { markup } runs of StyledText the caller has
// made safe and { image, alt } images, a file URL and the plain text drawn
// in its place. Each image draws as a square the height of a line of
// `font`, the font's own line height rounded down, aligned to the line's
// middle, so a line with an image keeps the pitch of one without.
//
// Text with no image draws as a plain Text with Qt's own right elision.
// Text with images elides itself: Qt's multi-line elision draws an image
// from an earlier line over the elided line's text. The cut keeps the longest run of
// whole words and whole images that fits `maximumLineCount` lines with one
// ellipsis after it, measured on a hidden copy of the text, so an image is
// never split. That text wraps at word boundaries, and breaks a word only
// when the word alone is wider than a line, so it stays inside its width,
// as the plain text's does; an image, narrower than a line, never breaks.
//
// Every image loads through ImagePool, which puts an asynchronous load in
// Qt's pixmap cache before the text names the image, so no image decodes
// on the GUI thread. An image whose load fails draws its alt text.
//
// `underlined` names plain words of the text whose first occurrence is a
// link: while `hovered`, the owner's reading of the pointer on what the
// words open, they draw over an underline in `underlineColor`, as
// LinkText's hovered link does, and at rest over none. Its top is
// Inset.underlineTop under each line's baseline, not at the font's
// underline position, where Qt draws a `<u>` and a descender meets it. A
// hidden RichText twin of the drawn text gives the words' x and line,
// since a Text reports no character position; it is made only while
// there are words, and only for text with no image, which the twin would
// load once more.
Item {
    id: root

    property var segments: []
    property font font: Qt.font({ family: Theme.text.body.family, pixelSize: Theme.text.body.size, weight: Theme.text.body.weight })
    property color color: Theme.text.body.color
    property int maximumLineCount: 1
    property string underlined: ""
    property color underlineColor: color
    property bool hovered: false
    // Whether the text drawn is cut short, and the lines it draws.
    readonly property bool truncated: imageMode ? cutShort : drawn.truncated
    readonly property int lineCount: drawn.lineCount
    // The side of an image in pixels, and in device pixels.
    readonly property int imageSize: Math.floor(metrics.height)
    readonly property int deviceSize: Math.round(imageSize * Screen.devicePixelRatio)
    // The underlined words' span on each drawn line, as { line, left,
    // right }. The arguments name what the twin's layout depends on, since
    // its positions are a function a binding cannot follow.
    readonly property var underlineSpans: twinLoader.item !== null ? wordSpans(twinLoader.item.text, twinLoader.item.width, twinLoader.item.lineCount, drawn.lineCount) : []

    // url -> the pool's image, for every image the text names; the URLs
    // among them that failed, drawn as their alt text; whether the text
    // holds an image and elides itself, and whether it was cut.
    property var held: ({})
    property var failed: []
    property bool imageMode: false
    property bool cutShort: false
    property bool ready: false

    implicitWidth: drawn.implicitWidth
    implicitHeight: drawn.implicitHeight

    onSegmentsChanged: rebuild()
    onFontChanged: rebuild()
    onWidthChanged: if (imageMode) rebuild()
    onMaximumLineCountChanged: rebuild()
    onDeviceSizeChanged: rebuild()
    Component.onCompleted: {
        ready = true;
        rebuild();
    }
    Component.onDestruction: {
        for (const url of Object.keys(held)) {
            held[url].statusChanged.disconnect(root.imageStatusChanged);
            ImagePool.release(held[url]);
        }
        held = ({});
    }

    // A held image finished: a failure draws its alt text. A loaded image
    // needs nothing, since the text waited on the same load.
    function imageStatusChanged() {
        for (const url of Object.keys(held))
            if (held[url].status === Image.Error && failed.indexOf(url) === -1) {
                rebuild();
                return;
            }
    }

    // In order: acquire every image, give the measurer its text, give the
    // drawn text its text, then release the images neither names.
    function rebuild() {
        if (!ready) return;
        const next = {};
        for (const url of Logic.imageUrls(segments)) {
            const kept = held[url];
            if (kept !== undefined && kept.sourceSize.width === deviceSize) {
                next[url] = kept;
                continue;
            }
            const image = ImagePool.acquire(url, deviceSize);
            if (image === null) continue;
            image.statusChanged.connect(root.imageStatusChanged);
            next[url] = image;
        }
        const failing = Object.keys(next).filter(url => next[url].status === Image.Error);
        const tokens = Logic.tokens(segments, imageSize, failing.concat(Logic.imageUrls(segments).filter(url => next[url] === undefined)));
        const drewImages = imageMode;
        imageMode = Logic.hasImage(tokens);
        if (imageMode) {
            drawn.wrapMode = Text.Wrap;
            drawn.elide = Text.ElideNone;
            const result = width > 0 ? Logic.elide(tokens, markup => {
                measurer.text = markup;
                return !measurer.truncated;
            }) : { markup: Logic.join(tokens, tokens.length), cut: false };
            measurer.text = result.markup;
            drawn.text = result.markup;
            cutShort = result.cut;
        } else {
            // Qt 6.12.0 (qquicktext.cpp: QQuickText::setText and
            // QQuickTextPrivate::setupTextLayout) frees a Text's inline
            // images when its text changes, but drops them from its list
            // of drawn images only in a layout that positions images,
            // which an empty text never reaches. The finish of an image
            // still loading, such as the failure that runs this rebuild,
            // or a device-pixel-ratio change then reads the freed images.
            // So a Text that held images first takes a space, which draws
            // nothing; the measurer is hidden and unread here, and the
            // drawn text's elision is still image mode's none.
            measurer.text = " ";
            if (drewImages) drawn.text = " ";
            drawn.wrapMode = Text.WordWrap;
            drawn.elide = Text.ElideRight;
            drawn.text = Logic.join(tokens, tokens.length);
            cutShort = false;
        }
        for (const url of Object.keys(held)) {
            if (next[url] === held[url]) continue;
            held[url].statusChanged.disconnect(root.imageStatusChanged);
            ImagePool.release(held[url]);
        }
        held = next;
        failed = failing;
    }

    function wordSpans(twinText, twinWidth, twinLines, drawnLines) {
        const twin = twinLoader.item;
        const plain = twin.getText(0, twin.length);
        const at = plain.indexOf(underlined);
        if (at === -1) return [];
        const pitch = twin.contentHeight / Math.max(1, twinLines);
        const lineOf = r => Math.floor((r.y + r.height / 2) / pitch);
        const spans = [];
        let span = null;
        for (let i = at; i < at + underlined.length; i++) {
            const glyph = twin.positionToRectangle(i);
            const line = lineOf(glyph);
            if (line >= drawnLines) break;
            const next = twin.positionToRectangle(i + 1);
            const right = lineOf(next) === line ? next.x : glyph.x + metrics.advanceWidth(plain.charAt(i));
            if (span !== null && span.line === line) {
                span.right = right;
            } else {
                span = { line: line, left: glyph.x, right: right };
                spans.push(span);
            }
        }
        return spans;
    }

    FontMetrics {
        id: metrics
        font: root.font
    }

    Text {
        id: measurer
        visible: false
        width: root.width
        textFormat: Text.StyledText
        font: root.font
        wrapMode: Text.Wrap
        maximumLineCount: root.maximumLineCount
        elide: Text.ElideNone
    }

    Text {
        id: drawn
        width: root.width
        textFormat: Text.StyledText
        font: root.font
        color: root.color
        maximumLineCount: root.maximumLineCount
    }

    Repeater {
        model: root.underlineSpans
        Rectangle {
            required property var modelData
            x: modelData.left
            y: drawn.baselineOffset + modelData.line * drawn.contentHeight / Math.max(1, drawn.lineCount) + Inset.underlineTop(DescenderInk.depth(root.font), Screen.devicePixelRatio)
            width: modelData.right - modelData.left
            height: Inset.underlineWidth(metrics.lineWidth)
            color: root.underlineColor
            visible: root.hovered
        }
    }

    Loader {
        id: twinLoader
        active: root.underlined !== "" && !root.imageMode
        visible: false
        sourceComponent: TextEdit {
            readOnly: true
            width: root.width
            text: drawn.text
            textFormat: TextEdit.RichText
            font: root.font
            wrapMode: drawn.wrapMode
        }
    }
}
