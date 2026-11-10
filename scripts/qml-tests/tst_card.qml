import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit

// Card: its children stand in one column `card.gap`, 4, apart and
// `card.padding`, 12, inside its edges; it takes its parent's width, draws
// `card.background` inside a 1 px `card.border` outline, rounds by
// `card.radius`, square by default, and moves its content in past a
// rounded corner. A floating card draws no fill or outline of its own: a
// GlassSurface under it draws the popover's, solid while glass is on, and
// its content keeps the card's padding. Expected values are worked by hand
// from the defaults in Tokens.js, never read from Theme.
Item {
    id: root
    width: 400
    height: 400

    Item {
        width: 300
        height: 300
        Card {
            id: card
            Item { id: first; width: 40; height: 20 }
            Item { id: second; width: parent.width; height: 30 }
        }
    }
    Item {
        y: 320
        width: 300
        height: 60
        Card {
            id: floatingCard
            floating: true
            Item { id: floatingFirst; width: 40; height: 20 }
        }
    }

    function glassUnder(card) {
        return card.children.map(child => child.item).find(item => item !== undefined && item !== null && item.glassSurface === true);
    }

    TestCase {
        name: "card"
        when: windowShown

        function init() { UnitTheme.reset(); }

        function test_children_stand_padded_and_apart() {
            compare(card.width, 300);
            const at = first.mapToItem(card, 0, 0);
            compare(at.x, 12);
            compare(at.y, 12);
            compare(second.mapToItem(card, 0, 0).y, 12 + 20 + 4);
            compare(second.width, 300 - 24);
            compare(card.implicitHeight, 12 + 20 + 4 + 30 + 12);
        }

        function test_draws_the_card_colours() {
            compare(String(card.color), String(Qt.color(Theme.color.surfaceRaised)));
            compare(String(card.border.color), String(Qt.color(Theme.color.borderSubtle)));
            compare(card.border.width, 1);
            compare(card.radius, 0);
            compare(UnitTheme.override({ card: { background: "#112233ff", border: "#445566ff" } }), "ok");
            compare(String(card.color), String(Qt.color("#112233")));
            compare(String(card.border.color), String(Qt.color("#445566")));
        }

        function test_a_floating_card_draws_through_the_popovers_glass() {
            compare(String(floatingCard.color), String(Qt.rgba(0, 0, 0, 0)), "the card's own fill is clear");
            compare(floatingCard.border.width, 0, "the card draws no outline of its own");
            const glass = root.glassUnder(floatingCard);
            verify(glass !== undefined, "a GlassSurface draws the floating card's ground");
            compare(glass.standard, Theme.popover, "the ground is the popover's floating group");
            compare(glass.solidOnly, true, "text reads over any backdrop");
            compare(glass.width, floatingCard.width);
            compare(glass.height, floatingCard.height);
            compare(floatingFirst.mapToItem(floatingCard, 0, 0).x, 12, "the floating card keeps the card's padding");
            compare(root.glassUnder(card), undefined, "a card in a panel builds no glass");
        }

        // A 4 px pad under a 20 px corner: content 4 in from the top stands
        // 16 below the corner's centre, so it clears the curve by one 4 px
        // step only at 20 in, as tst_pane reads for Pane.
        function test_a_rounded_corner_moves_the_content_in() {
            compare(UnitTheme.override({ card: { radius: 20, padding: 4 } }), "ok");
            compare(card.radius, 20);
            tryCompare(card, "contentInset", 20);
            compare(first.mapToItem(card, 0, 0).x, 20);
        }
    }
}
