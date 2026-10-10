import QtQuick
import QtTest
import qs.Ui

// ImageText: an image segment draws as an image at full strength whatever
// the text's colour, and a line holding one keeps the pitch of a line
// without; text with no image draws through Qt's own right elision; text
// with images cut short ends at a whole word or image with one ellipsis,
// draws no image past the cut and none on a line it does not sit on; an
// image that fails draws its alt text; and ImagePool shares one image per
// URL and size between holders, keeps it for the next holder after the
// last lets it go, up to its ceiling of idle images, and keeps no image
// whose load failed. Pixels are read off grabs; the red of the fixture
// image is never a colour of the text.
Item {
    id: root
    width: 420
    height: 300

    readonly property string red: Qt.resolvedUrl("images/red.png")
    readonly property string missing: Qt.resolvedUrl("images/missing.png")
    readonly property font face: Qt.font({ family: "Liberation Sans", pixelSize: 20 })

    function words(count) {
        const out = [];
        for (let i = 0; i < count; i++) out.push("word" + i);
        return out.join(" ");
    }

    Component {
        id: textComponent
        ImageText {
            width: 400
            font: root.face
            color: "#80000000"
            maximumLineCount: 2
        }
    }

    TestCase {
        name: "imagetext"
        when: windowShown

        function make(segments, lines) {
            const item = createTemporaryObject(textComponent, root, { maximumLineCount: lines || 2 });
            verify(item !== null);
            item.segments = segments;
            return item;
        }

        // The Text the component draws: its one visible child.
        function drawn(item) {
            for (const child of item.children)
                if (child.visible && child.text !== undefined) return child;
            fail("no drawn text");
        }

        // The rows of the item that hold a red pixel of the fixture image.
        function redRows(item) {
            const img = grabImage(item);
            const rows = [];
            for (let y = 0; y < img.height; y++) {
                for (let x = 0; x < img.width; x++) {
                    if (img.red(x, y) > 200 && img.green(x, y) < 60 && img.blue(x, y) < 60 && img.alpha(x, y) > 200) {
                        rows.push(y);
                        break;
                    }
                }
            }
            return rows;
        }

        function redAlpha(item) {
            const img = grabImage(item);
            let best = 0;
            for (let y = 0; y < img.height; y++)
                for (let x = 0; x < img.width; x++)
                    if (img.red(x, y) > 200 && img.green(x, y) < 60 && img.blue(x, y) < 60) best = Math.max(best, img.alpha(x, y));
            return best;
        }

        function test_an_image_segment_draws_as_an_image_at_full_strength() {
            const item = make([{ markup: "a " }, { image: root.red, alt: ":red:" }, { markup: " b" }], 1);
            verify(drawn(item).text.indexOf("<img") !== -1, "the text names the image");
            tryVerify(() => redRows(item).length > 0, 3000, "the image is drawn");
            compare(redAlpha(item), 255, "the image draws at full strength under a half-alpha text colour");
            verify(redRows(item).length <= item.imageSize, "the image is one line's height");
        }

        function test_a_url_value_image_segment_draws_as_an_image() {
            const item = make([{ image: Qt.resolvedUrl("images/red.png"), alt: ":red:" }], 1);
            verify(drawn(item).text.indexOf("<img") !== -1, "the text names the image");
            tryVerify(() => redRows(item).length > 0, 3000, "the image is drawn");
            compare(item.failed.length, 0);
        }

        function test_a_line_with_an_image_keeps_its_pitch() {
            const plain = make([{ markup: "a b" }], 1);
            const imaged = make([{ markup: "a " }, { image: root.red, alt: ":red:" }, { markup: " b" }], 1);
            compare(imaged.implicitHeight, plain.implicitHeight);
        }

        function test_text_without_images_uses_qt_elision() {
            const item = make([{ markup: words(80) }], 2);
            compare(drawn(item).elide, Text.ElideRight);
            compare(drawn(item).text, words(80));
            verify(item.truncated);
            compare(item.lineCount, 2);
        }

        function test_a_cut_body_ends_at_a_whole_token_with_no_image_misplaced() {
            const full = "one " + words(80);
            const item = make([{ markup: "one " }, { image: root.red, alt: ":red:" }, { markup: " " + words(80) }], 2);
            const text = drawn(item).text;
            verify(text.endsWith("\u2026"), "one ellipsis ends the text: " + text);
            compare(text.split("\u2026").length, 2);
            const kept = text.slice(0, -1).replace(/<img[^>]*>/, "").trim().split(/\s+/);
            compare(kept, full.split(" ").slice(0, kept.length), "the cut keeps whole words from the start: " + text);
            verify(item.truncated);
            compare(item.lineCount, 2);
            tryVerify(() => redRows(item).length > 0, 3000, "the image is drawn");
            const lineHeight = item.implicitHeight / 2;
            const rows = redRows(item);
            verify(rows[rows.length - 1] < lineHeight, "the image stays on the first line, last red row " + rows[rows.length - 1] + " line height " + lineHeight);
        }

        // A word wider than the body, such as a long link, breaks inside
        // itself and stays inside the width, with the image whole on its
        // own line, as Qt keeps a plain body inside its width.
        function test_a_word_wider_than_the_body_stays_inside_it() {
            const long = "x".repeat(60);
            const item = make([{ markup: "one " }, { image: root.red, alt: ":red:" }, { markup: " " + long }], 3);
            const text = drawn(item);
            verify(text.text.indexOf(long) !== -1, "the word is kept: " + text.text);
            verify(text.contentWidth <= item.width, "the text is " + text.contentWidth + " wide in " + item.width);
            compare(item.lineCount, 3);
            tryVerify(() => redRows(item).length > 0, 3000, "the image is drawn");
            const cut = make([{ markup: "one " }, { image: root.red, alt: ":red:" }, { markup: " " + long + " " + long }], 2);
            verify(drawn(cut).contentWidth <= cut.width, "the cut text is " + drawn(cut).contentWidth + " wide in " + cut.width);
            verify(cut.truncated);
            // The cut was measured as it draws: it ends on the ellipsis, and
            // no line of it falls past the line count.
            verify(drawn(cut).text.endsWith("\u2026"), "the cut ends on the ellipsis: " + drawn(cut).text);
            verify(!drawn(cut).truncated, "the drawn cut loses no line");
        }

        function test_an_image_past_the_cut_is_not_drawn() {
            const item = make([{ markup: words(80) + " " }, { image: root.red, alt: ":red:" }], 2);
            verify(drawn(item).text.indexOf("<img") === -1, "the image past the cut is not in the text");
            wait(200);
            compare(redRows(item).length, 0);
        }

        // expected-log: Cannot open: -- the missing fixture image fails to load on purpose
        function test_a_failed_image_draws_its_alt_text() {
            const item = make([{ markup: "x " }, { image: root.missing, alt: ":gone:" }], 1);
            tryVerify(() => drawn(item).text.indexOf(":gone:") !== -1, 3000, "the alt text replaces the image");
            verify(drawn(item).text.indexOf("<img") === -1);
        }

        // A body emptied while its image loads, with another holder keeping
        // the load, outlives that load's finish and draws nothing. Only a
        // crash fails it, and only on Qt 6.12.0: with all of ImageText's
        // plain-mode spaces reverted it crashes, but with one removed it
        // crashes only when freed memory is poisoned. On Qt 6.11.2 no
        // ImageText edit reddens it.
        // expected-log: Cannot open: -- the missing fixture image fails to load on purpose
        function test_a_text_emptied_while_its_image_loads_draws_nothing() {
            const segments = [{ markup: "x " }, { image: root.missing, alt: ":gone:" }];
            const keeper = make(segments, 1);
            const item = make(segments, 1);
            verify(drawn(item).text.indexOf("<img") !== -1, "the text names the image while it loads");
            item.segments = [];
            tryVerify(() => drawn(keeper).text.indexOf(":gone:") !== -1, 3000, "the load finished");
            compare(drawn(item).text, "");
        }

        function test_the_pool_shares_an_image_and_keeps_it_after_its_last_holder() {
            const segments = [{ image: root.red, alt: ":red:" }];
            const first = make(segments, 1);
            const size = first.deviceSize;
            const held = () => ImagePool.entries[size + "@" + root.red];
            compare(held().holders, 1);
            const second = make(segments, 1);
            compare(held().holders, 2, "two holders share one entry");
            const image = held().image;
            tryCompare(image, "status", Image.Ready, 3000);
            second.segments = [{ markup: "none" }];
            compare(held().holders, 1, "a holder that stops naming the image releases it");
            first.segments = [{ markup: "none" }];
            verify(held() !== undefined, "the last release keeps the entry");
            compare(held().holders, 0);
            verify(held().image === image, "the kept entry keeps its image");
            const third = make(segments, 1);
            verify(held().image === image, "a new holder reuses the kept image");
            compare(held().holders, 1);
            compare(image.status, Image.Ready, "the reused image does not load again");

            // Past the ceiling the oldest idle image goes; a held one never.
            const ceiling = ImagePool.idleCeiling;
            const keys = [];
            const images = [];
            for (let i = 0; i <= ceiling; i++) {
                const url = root.red + "?v=" + i;
                keys.push(size + "@" + url);
                images.push(ImagePool.acquire(url, size));
            }
            tryVerify(() => images.every(each => each.status === Image.Ready), 5000, "every image loads");
            for (const each of images) ImagePool.release(each);
            compare(ImagePool.entries[keys[0]], undefined, "the oldest idle image goes past the ceiling");
            for (let i = 1; i <= ceiling; i++) {
                const entry = ImagePool.entries[keys[i]];
                verify(entry !== undefined && entry.image === images[i] && entry.holders === 0, "idle image " + i + " is kept");
            }
            verify(held() !== undefined && held().image === image && held().holders === 1, "the held image is not evicted");
        }

        // expected-log: Cannot open: -- the missing fixture image fails to load on purpose
        function test_the_pool_keeps_no_failed_image() {
            const item = make([{ image: root.missing, alt: ":gone:" }], 1);
            const key = item.deviceSize + "@" + root.missing;
            tryCompare(ImagePool.entries[key].image, "status", Image.Error, 3000);
            item.segments = [{ markup: "none" }];
            compare(ImagePool.entries[key], undefined, "a failed image is not kept once released");
        }

        // expected-log: release of an image no holder holds -- the second release is refused on purpose
        function test_the_pool_refuses_a_release_no_holder_holds() {
            const url = root.red + "?twice";
            const image = ImagePool.acquire(url, 16);
            tryCompare(image, "status", Image.Ready, 3000);
            ImagePool.release(image);
            ImagePool.release(image);
            compare(ImagePool.entries["16@" + url].holders, 0, "a release of an idle image is refused");
        }

        // An image released while it loads and failing after is loaded
        // again by its next holder.
        // expected-log: Cannot open: -- the missing fixture image fails to load on purpose
        function test_the_pool_loads_again_an_image_that_failed_while_idle() {
            const url = root.missing + "?idle";
            const image = ImagePool.acquire(url, 16);
            compare(image.status, Image.Loading, "the release comes while the image loads");
            ImagePool.release(image);
            tryCompare(image, "status", Image.Error, 3000);
            const again = ImagePool.acquire(url, 16);
            verify(again !== image, "the next holder gets a new load");
            tryCompare(again, "status", Image.Error, 3000);
            ImagePool.release(again);
        }
    }
}
