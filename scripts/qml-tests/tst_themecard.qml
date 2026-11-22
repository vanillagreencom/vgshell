import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit
import "../../shell/plugins/vgs.themes"

// ThemeCard for an accepted package with no package preview. The selected
// card with no wallpaper names its theme over its background, and with a
// wallpaper the picture takes the card and the name is gone. A side card
// draws its wallpaper as a wallpaper card does, and with or without one
// draws no name and no palette.
Item {
    id: root
    width: 1000
    height: 240

    readonly property string imagePath: decodeURIComponent(String(Qt.resolvedUrl("images/red.png")).replace(/^file:\/\//, ""))
    readonly property var terminal: {
        const slots = {};
        for (let index = 0; index < 16; index++) slots["color" + index] = "#202020ff";
        return slots;
    }
    function card(label, image) {
        return {
            name: label.toLowerCase(), label: label, state: "ok", generation: 0, previewImage: null, image: image,
            palette: { background: "#101010ff", foreground: "#eeeeeeff", accent: "#3366ffff", success: "#00aa00ff", warning: "#ccaa00ff", danger: "#aa0000ff", info: "#0066aaff" },
            terminal: root.terminal
        };
    }

    Item {
        x: 0; width: 300; height: 200
        ThemeCard {
            modelData: root.card("Bare", null)
            decodeSize: Qt.size(300, 200)
            current: true
        }
    }
    Item {
        x: 320; width: 300; height: 200
        ThemeCard {
            modelData: root.card("Walled", root.imagePath)
            decodeSize: Qt.size(300, 200)
            current: true
        }
    }
    Item {
        id: sides
        x: 640; width: 240; height: 200
        Item {
            width: 100; height: 200
            ThemeCard {
                id: pictureSide
                modelData: root.card("Pictured", root.imagePath)
                decodeSize: Qt.size(100, 200)
            }
        }
        Item {
            x: 120; width: 100; height: 200
            ThemeCard {
                modelData: root.card("Plain", null)
                decodeSize: Qt.size(100, 200)
            }
        }
    }

    UnitCase {
        name: "themeCard"
        when: windowShown

        // Whether a visible item under ITEM draws TEXT.
        function drawsText(item, text) {
            return displayedTextItems(item).some(child => displayedText(child) === text);
        }
        // The visible items under ITEM, ITEM included, that pass TEST.
        function shown(item, test) {
            const out = [];
            const walk = node => {
                if (!node.visible) return;
                if (test(node)) out.push(node);
                for (const child of node.children) walk(child);
            };
            walk(item);
            return out;
        }

        function test_a_card_without_a_wallpaper_names_its_theme() {
            verify(drawsText(root, "Bare"), "the card with no wallpaper draws its name");
        }

        function test_a_card_with_a_wallpaper_draws_no_name() {
            verify(!drawsText(root, "Walled"), "the wallpaper card draws no name");
        }

        function test_a_side_card_draws_its_wallpaper() {
            tryVerify(() => pictureSide.pictureShown, 2000, "the side card's wallpaper is ready");
            compare(shown(pictureSide, item => item instanceof Image).length, 1, "the side card draws its wallpaper");
        }

        function test_a_side_card_draws_no_name_and_no_palette() {
            tryVerify(() => pictureSide.pictureShown, 2000, "the side card's wallpaper is ready");
            compare(displayedTextItems(sides).map(item => displayedText(item)), [], "no side card draws text");
            compare(shown(sides, item => item instanceof Grid).length, 0, "no side card draws a palette");
        }
    }
}
