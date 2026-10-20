import QtQuick
import QtTest
import qs.Commons
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

    TestCase {
        name: "notification_media"
        when: windowShown

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
