import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit
import "../../shell/plugins/vgs.themes"

// WallpaperCard's name box: the name's capitals start
// `carousel.namePadding` under the box's top, its baseline sits that far
// over the box's bottom and its start that far in from the box's side, and
// the box's corners follow the Corner radius a user sets for controls,
// square at 0 and that radius above it.
Item {
    id: root
    width: 400
    height: 300

    readonly property string imagePath: decodeURIComponent(String(Qt.resolvedUrl("images/red.png")).replace(/^file:\/\//, ""))

    Item {
        width: 400
        height: 300
        WallpaperCard {
            id: card
            modelData: ({ kind: "image", key: "ember", name: "Ember Forest", path: root.imagePath, generation: 0 })
            decodeSize: Qt.size(400, 300)
            current: true
        }
    }

    TestCase {
        name: "wallpaperCard"
        when: windowShown

        // The visible item under ITEM that draws TEXT, or null.
        function textItem(item, text) {
            for (const child of item.children) {
                if (child.visible && child.text === text) return child;
                const found = textItem(child, text);
                if (found !== null) return found;
            }
            return null;
        }

        function nameLabel() {
            const label = textItem(card, "Ember Forest");
            verify(label !== null, "the card draws its image's name");
            return label;
        }

        // The box's fill, the one item beside the name.
        function nameFill() {
            const label = nameLabel();
            const others = label.parent.children.filter(child => child !== label);
            compare(others.length, 1, "the name box holds its fill and its name");
            return others[0];
        }

        function cleanup() {
            Theme.appearanceInput = "";
        }

        function test_the_name_sits_its_padding_from_the_box_edges() {
            const label = nameLabel();
            const box = label.parent;
            const pad = Theme.carousel.namePadding;
            verify(Math.abs(label.y + label.capTop() - pad) <= 0.5, "the capitals start the padding under the box's top: " + (label.y + label.capTop()));
            verify(Math.abs(box.height - label.y - label.lastBaseline() - pad) <= 0.5, "the baseline sits the padding over the box's bottom: " + (box.height - label.y - label.lastBaseline()));
            compare(label.x, pad, "the name starts the padding in from the box's side");
        }

        function test_square_controls_draw_a_square_name_box() {
            Theme.appearanceInput = JSON.stringify({ controlRadius: 0 });
            compare(nameFill().radius, 0);
        }

        function test_rounded_controls_round_the_name_box_by_their_radius() {
            Theme.appearanceInput = JSON.stringify({ controlRadius: 6 });
            compare(nameFill().radius, 6);
        }
    }
}
