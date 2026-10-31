import QtQuick
import QtTest
import qs.Commons
import qs.Unit
import "../../shell/plugins/vgs.notifications" as Notifications
import "../../shell/plugins/vgs.notifications/Appearance.js" as Appearance

// A notification's icon draws in one place whatever it is. A symbol icon,
// the x-vgs-icon hint's Lucide name (the automation failure mark, the
// passwordless sudo locks), has the box size and the vertical centre of an
// application icon, on a card of one body line and on a card of two, and
// both stand on the card's own centre, as an image does. A control for each
// of the size and the two centres lives in scripts/test-qml-unit.sh.
Item {
    id: scene
    readonly property var look: Theme.appearance(Appearance.TOKENS, Appearance.LIGHT)
    readonly property real textColumn: Math.ceil(Inset.clearing(look.card.pad, look.radius.full, look.card.width, look.card.maxHeight, look.radius.clearance, look.card.pad))
    readonly property var oneLine: "Until you turn it off."
    readonly property var twoLines: "Failed 2 times since 7:00 pm\nThe automation failed. Open Automations to read its output."

    width: look.card.width
    height: look.card.maxHeight

    Rectangle { anchors.fill: parent; color: scene.look.card.base }

    Component {
        id: shippedCard
        Notifications.NotificationCard {}
    }

    UnitCase {
        name: "notification_media"
        when: windowShown

        function cleanup() { UnitTheme.reset(); }

        readonly property var symbols: [
            { summary: "Shot failure failed", icon: "circle-x", tone: "danger" },
            { summary: "Passwordless sudo is off", icon: "lock", tone: "success" },
            { summary: "Passwordless sudo is on", icon: "lock-open", tone: "warning" }
        ]

        function build(values) {
            const card = createTemporaryObject(shippedCard, scene, Object.assign({ look: scene.look, textColumn: scene.textColumn }, values));
            verify(card !== null, "the card was built");
            card.anchors.centerIn = scene;
            tryVerify(() => card.showsSlot, 5000, "the card draws its media");
            return card;
        }

        // The box the slot's one visible icon draws in, in the card's own
        // coordinates: [width, height, vertical centre].
        function iconBox(card) {
            const slot = findChild(card, "notificationMediaSlot");
            verify(slot !== null, "the card's media slot was found");
            const drawn = Array.from(slot.children).filter(child => child.visible && (child.fillMode !== undefined || child.name !== undefined));
            compare(drawn.length, 1, "the slot draws one icon");
            const box = drawn[0].mapToItem(card, 0, 0, drawn[0].width, drawn[0].height);
            return [box.width, box.height, box.y + box.height / 2];
        }

        function appCard(body) {
            return build({ summary: "App icon", body: body, appIcon: Qt.resolvedUrl("images/red.png") });
        }

        function symbolCard(symbol, body) {
            return build({ summary: symbol.summary, body: body, hintIcon: symbol.icon, hintTone: symbol.tone });
        }

        function test_avatarAndOutcome_data() {
            const rows = [];
            for (const mode of ["dark", "light"])
                for (const mark of [
                    { icon: "circle-check", glyph: "check", tone: "success" },
                    { icon: "circle-x", glyph: "x", tone: "danger" }
                ])
                    for (const avatar of ["calendar-clock", "cloud"])
                        rows.push({ tag: mode + "/" + avatar + "/" + mark.icon, mode: mode, avatar: avatar, mark: mark });
            return rows;
        }

        function test_avatarAndOutcome(data) {
            compare(UnitTheme.override({ scheme: { mode: data.mode } }), "ok");
            const card = build({ summary: "Outcome", body: scene.oneLine, hintAvatar: data.avatar, hintIcon: data.mark.icon, hintTone: data.mark.tone });
            compare(card.mediaKind, "avatar");
            const slot = findChild(card, "notificationMediaSlot");
            const plates = Array.from(slot.children).filter(child => child.visible && child.radius !== undefined && child.color !== undefined);
            compare(plates.length, 2, "the shared slot draws an avatar and a badge");
            const avatar = plates.find(child => child.width > scene.look.media.outcome.size);
            const badge = plates.find(child => child.width === scene.look.media.outcome.size);
            verify(avatar !== undefined && badge !== undefined);
            verify(avatar.width > badge.width, "the avatar is larger than its outcome");
            verify(badge.x > avatar.x && badge.y < avatar.y, "the badge is staggered to the top right");
            verify(badge.x < avatar.x + avatar.width && badge.y + badge.height > avatar.y, "the badge overlaps the avatar");
            verify(badge.x + badge.width <= slot.width && badge.y >= 0, "the badge stays in the shared media square");
            const plugin = Array.from(avatar.children).find(child => child.name !== undefined);
            const mark = Array.from(badge.children).find(child => child.name !== undefined);
            compare(plugin.name, data.avatar, "the avatar uses the sender's plugin glyph");
            compare(mark.name, data.mark.glyph, "the filled badge draws only the inner outcome mark");
            verify(Qt.colorEqual(badge.color, scene.look.tone[data.mark.tone]));
            verify(Theme.contrastRatio(mark.color, badge.color) >= 4.5, "badge ink holds the text floor in both themes");
            verify(waitForPolish(card));
            verify(renderedFrame(card));
            const image = grabImage(scene);
            const at = badge.mapToItem(scene, 0, 0);
            const fill = image.pixel(Math.round(at.x + 3), Math.round(at.y + 10));
            verify(Math.abs(fill.r - badge.color.r) < 1 / 255 && Math.abs(fill.g - badge.color.g) < 1 / 255 && Math.abs(fill.b - badge.color.b) < 1 / 255, "the badge paints its tone fill: " + fill + " expected " + badge.color + " at " + at + " scene " + image.width + "/" + image.height);
            const strokes = [];
            for (let y = 5; y < badge.height - 5; y++)
                for (let x = 5; x < badge.width - 5; x++)
                    if (Theme.contrastRatio(image.pixel(Math.round(at.x + x), Math.round(at.y + y)), badge.color) >= 3) strokes.push([x, y]);
            verify(strokes.length >= 6, "the rendered inner mark contains readable stroke pixels");
            fuzzyCompare(slot.mapToItem(card, 0, slot.height / 2).y, card.height / 2, 0.5, "the shared media square stays centred");
        }

        function test_symbolMatchesApplicationIcon_data() {
            const rows = [];
            for (const [lines, body] of [["one line", scene.oneLine], ["two lines", scene.twoLines]])
                for (const symbol of symbols) rows.push({ tag: symbol.icon + " on " + lines, symbol: symbol, body: body });
            return rows;
        }

        function test_symbolMatchesApplicationIcon(data) {
            const app = iconBox(appCard(data.body));
            const symbol = iconBox(symbolCard(data.symbol, data.body));
            compare(app[0], scene.look.media.icon, "the application icon's width");
            compare(app[1], scene.look.media.icon, "the application icon's height");
            compare(symbol[0], app[0], "the symbol's width is the application icon's");
            compare(symbol[1], app[1], "the symbol's height is the application icon's");
            fuzzyCompare(symbol[2], app[2], 0.5, "the symbol's vertical centre is the application icon's");
        }

        function test_iconStandsOnTheCardCentre_data() {
            return [
                { tag: "application icon, one line", make: () => appCard(scene.oneLine) },
                { tag: "application icon, two lines", make: () => appCard(scene.twoLines) },
                { tag: "failure mark, two lines", make: () => symbolCard(symbols[0], scene.twoLines) },
                { tag: "sudo lock, one line", make: () => symbolCard(symbols[1], scene.oneLine) }
            ];
        }

        function test_iconStandsOnTheCardCentre(data) {
            const card = data.make();
            fuzzyCompare(iconBox(card)[2], card.height / 2, 0.5, "the icon's vertical centre is the card's");
        }
    }
}
