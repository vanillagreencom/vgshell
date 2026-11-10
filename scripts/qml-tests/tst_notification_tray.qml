import QtQuick
import QtTest
import qs.Commons
import "../../shell/plugins/vgs.notifications" as Notifications
import "../../shell/plugins/vgs.notifications/Appearance.js" as Appearance

// A notification card's text stays clear of its action pills for as long
// as the pills draw: through the fade in, at rest, and through the whole
// fade out after the pointer leaves, frame by frame. A text pixel is one
// whose colour changes when the summary and body text change colour, read
// from two grabs taken in one step; a pill is its drawn plate in the
// scene, the tray's slide included. The control builds the shipped card
// with the reserve that ends the moment the pointer leaves and expects
// the same reading to see text under a pill during the fade out.
Item {
    id: scene
    readonly property var look: Theme.appearance(Appearance.TOKENS, Appearance.LIGHT)
    // The text column the stack hands its cards, as CardScroll computes it.
    readonly property real textColumn: Math.ceil(Inset.clearing(look.card.pad, look.radius.full, look.card.width, look.card.maxHeight, look.radius.clearance, look.card.pad))
    readonly property var actions: [{ id: "reply", label: "Reply" }, { id: "dismiss", label: "Dismiss" }]

    width: look.card.width
    height: look.card.maxHeight

    Rectangle { anchors.fill: parent; color: scene.look.card.base }

    Component {
        id: shippedCard
        Notifications.NotificationCard {}
    }

    TestCase {
        name: "notification_tray"
        when: windowShown

        // Far from every colour the card's text draws in, so each glyph
        // pixel changes when the text takes it.
        readonly property color marker: "#ff00ff"
        readonly property string fixedReserve: "readonly property real trayReserve: trayShown || tray.visible ?"
        readonly property string leavingReserve: "readonly property real trayReserve: trayShown ?"

        function build(component) {
            const card = component.createObject(scene, {
                look: scene.look,
                textColumn: scene.textColumn,
                summary: "Row 3 notification",
                body: "Body text for row 3, long enough to wrap onto a second line",
                actions: scene.actions
            });
            verify(card !== null, "the card was built");
            card.anchors.centerIn = scene;
            return card;
        }

        // The shipped card with the reserve ending as soon as the pointer
        // leaves. The card's body becomes an inline component of a wrapper
        // placed in the plugin's directory, so its relative imports and
        // the plugin's own types resolve, and its required properties are
        // set as the shipped card's are.
        function alteredCard(needle, replacement) {
            const request = new XMLHttpRequest();
            request.open("GET", Qt.resolvedUrl("../../shell/plugins/vgs.notifications/NotificationCard.qml"), false);
            request.send();
            const source = request.responseText;
            verify(source.split(needle).length === 2, "the control matches the shipped card once");
            const planted = source.replace(needle, replacement);
            verify(planted !== source, "the control changed the card");
            const root = planted.search(/^Item \{$/m);
            verify(root > 0, "the card's root item was found");
            const wrapper = planted.slice(0, root)
                + "Item {\n    component LeavingCard: " + planted.slice(root)
                + "\n    readonly property Component card: Component { LeavingCard {} }\n}\n";
            const holder = Qt.createQmlObject(wrapper, scene, Qt.resolvedUrl("../../shell/plugins/vgs.notifications/ControlCard.qml"));
            verify(holder !== null, "the control card compiled");
            const card = build(holder.card);
            card.Component.onDestruction.connect(holder, holder.destroy);
            return card;
        }

        function parts(card) {
            const caption = findChild(card, "notificationCaption");
            const title = findChild(card, "notificationTitleText");
            const body = findChild(card, "notificationBodyText");
            verify(caption !== null && title !== null && body !== null, "the card's parts were found");
            return { tray: caption.parent, title: title, body: body };
        }

        function descendants(item) {
            const found = [];
            for (const child of item.children) found.push(child, ...descendants(child));
            return found;
        }

        function sceneRect(item, width, height) {
            const mapped = item.mapToItem(scene, 0, 0, width, height);
            return { x: mapped.x, y: mapped.y, width: mapped.width, height: mapped.height };
        }

        function clipped(rect, bound) {
            const left = Math.max(rect.x, bound.x);
            const top = Math.max(rect.y, bound.y);
            const right = Math.min(rect.x + rect.width, bound.x + bound.width);
            const bottom = Math.min(rect.y + rect.height, bound.y + bound.height);
            return { x: left, y: top, width: Math.max(0, right - left), height: Math.max(0, bottom - top) };
        }

        // One frame of the card, read in a single step so no animation
        // advances between the two grabs: the scene as drawn, the scene
        // with the text in the marker colour, and where the pills and the
        // body are drawn. mapToItem applies each ancestor's transform, so a
        // pill's place includes the tray's slide (a probe under this runner
        // mapped an item at x 5 under Translate { x: 10 } to 15). The card
        // clips what it draws, so each pill is read within the card.
        function sample(card) {
            const part = parts(card);
            const plain = grabImage(scene);
            const cardRect = sceneRect(card, card.width, card.height);
            const pills = part.tray.opacity > 0
                ? descendants(part.tray).filter(child => child.emphasized !== undefined && child.visible)
                    .map(pill => clipped(sceneRect(pill.background, pill.background.width, pill.background.height), cardRect))
                : [];
            const body = sceneRect(part.body, part.body.width, part.body.height);
            part.title.color = marker;
            part.body.color = marker;
            const marked = grabImage(scene);
            part.title.color = Qt.binding(() => card.look.text.foreground);
            part.body.color = Qt.binding(() => card.look.text.body.color);
            return { opacity: part.tray.opacity, plain: plain, marked: marked, pills: pills, body: body };
        }

        function textPixel(frame, x, y) {
            return !Qt.colorEqual(frame.plain.pixel(x, y), frame.marked.pixel(x, y));
        }

        // A frame's reading: whether the body draws text, the text pixels
        // inside a drawn pill, and whether the body's text and a pill share
        // a row.
        function judge(frame) {
            let text = false;
            for (let y = Math.floor(frame.body.y); !text && y < Math.ceil(frame.body.y + frame.body.height); y++)
                for (let x = Math.floor(frame.body.x); !text && x < Math.ceil(frame.body.x + frame.body.width); x++)
                    text = textPixel(frame, x, y);
            let overlap = 0;
            let sharedRow = false;
            for (const pill of frame.pills) {
                const top = Math.floor(pill.y), bottom = Math.ceil(pill.y + pill.height);
                for (let y = top; y < bottom; y++) {
                    for (let x = Math.floor(pill.x); x < Math.ceil(pill.x + pill.width); x++)
                        if (textPixel(frame, x, y)) overlap++;
                    for (let x = Math.floor(frame.body.x); !sharedRow && x < Math.ceil(frame.body.x + frame.body.width); x++)
                        if (y >= frame.body.y && y < frame.body.y + frame.body.height && textPixel(frame, x, y)) sharedRow = true;
                }
            }
            return { opacity: frame.opacity, text: text, overlap: overlap, sharedRow: sharedRow };
        }

        // One sample per drawn frame until the tray's opacity reaches
        // `end`: a sample, then a wait until the fade moves on.
        function framesUntil(card, end) {
            const tray = parts(card).tray;
            const limit = 10 * card.look.motion.duration.short4;
            const read = [sample(card)];
            let waited = 0;
            while (tray.opacity !== end) {
                const last = tray.opacity;
                while (tray.opacity === last) {
                    verify(waited < limit, "the tray's fade moved on within " + limit + " ms");
                    wait(1);
                    waited++;
                }
                read.push(sample(card));
            }
            return read;
        }

        // Every frame from the hover to rest, then every frame from the
        // pointer leaving until the tray has gone, judged once the fade
        // has ended so the judging costs no frame.
        function fades(card) {
            compare(parts(card).tray.opacity, 0, "the tray starts hidden");
            card.showActions = true;
            const fadeIn = framesUntil(card, 1);
            card.showActions = false;
            const fadeOut = framesUntil(card, 0);
            return { fadeIn: fadeIn.map(judge), fadeOut: fadeOut.map(judge) };
        }

        // A fade is read part way through often enough to see it, and on
        // a frame where a pill stands level with the body's text, so the
        // reading can show text under a pill.
        function verifyCanSee(frames, fade) {
            const between = frames.filter(frame => frame.opacity > 0 && frame.opacity < 1);
            verify(between.length >= 5, "frames part way through the " + fade + ": " + between.length);
            verify(frames.every(frame => frame.text), "every frame of the " + fade + " draws body text");
            verify(frames.some(frame => frame.sharedRow), "a pill shares a row with the body's text in the " + fade);
        }

        function overlaps(frames) {
            return frames.filter(frame => frame.overlap > 0).map(frame => frame.opacity.toFixed(3) + ":" + frame.overlap);
        }

        function test_text_clears_the_pills_through_both_fades_data() {
            return [
                { tag: "shipped card", leaving: false },
                { tag: "control: the reserve ends when the pointer leaves", leaving: true }
            ];
        }

        function test_text_clears_the_pills_through_both_fades(row) {
            const card = row.leaving ? alteredCard(fixedReserve, leavingReserve) : build(shippedCard);
            const read = fades(card);
            verifyCanSee(read.fadeIn, "fade in");
            verifyCanSee(read.fadeOut, "fade out");
            compare(overlaps(read.fadeIn), [], "text under a pill in the fade in");
            if (row.leaving)
                verify(overlaps(read.fadeOut).length > 0, "the reading saw text under a pill in the fade out");
            else
                compare(overlaps(read.fadeOut), [], "text under a pill in the fade out");
            card.destroy();
        }

        function test_long_actions_leave_the_message_readable_data() {
            return [{ tag: "shipped card", control: false }, { tag: "control: actions consume the message width", control: true }];
        }

        function test_long_actions_leave_the_message_readable(row) {
            const card = row.control ? alteredCard("readonly property bool trayBelow:", "readonly property bool trayBelow: false &&")
                : build(shippedCard);
            card.summary = "Google Drive folder sync stopped";
            card.body = "Sync stopped for Documents and Agent uploads. Two-way sync needs setup.";
            card.actions = [{ id: "setup", label: "Set up two-way sync" }, { id: "dismiss", label: "Dismiss" }];
            card.showActions = true;
            tryCompare(parts(card).tray, "opacity", 1);
            card.settleHeight();
            const part = parts(card);
            if (row.control) {
                verify(part.title.truncated && part.body.truncated, "the control exposes the unreadable notification");
                card.destroy();
                return;
            }
            verify(!part.title.truncated, "the complete title stays readable with the actions shown");
            verify(!part.body.truncated, "both stopped-folder names and their setup explanation remain readable");
            const body = sceneRect(part.body, part.body.width, part.body.height);
            const tray = sceneRect(part.tray, part.tray.width, part.tray.height);
            verify(tray.y >= body.y + body.height, "the actions leave the message its own complete row");
            verify(tray.y + tray.height <= card.y + card.height - card.pad + 0.5,
                "every action stays within the card");
            verify(part.body.width >= card.textWidth - 0.5, "folder names keep the full message column");
            const selected = [];
            card.actionTriggered.connect(id => selected.push(id));
            const setup = descendants(part.tray).find(child => child.emphasized === true);
            verify(setup !== undefined);
            scene.height = card.fullHeight + 2 * card.pad;
            mouseClick(setup);
            compare(selected, ["setup"], "the readable action remains reachable");
            card.destroy();
            scene.height = scene.look.card.maxHeight;
        }
    }
}
