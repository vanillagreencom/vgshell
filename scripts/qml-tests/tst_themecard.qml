import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit
import "../../shell/plugins/vgs.themes"

// ThemeCard's selected card for an accepted package with no package
// preview: with no wallpaper it names its theme over its background, and
// with a wallpaper the picture takes the card and the name is gone.
Item {
    id: root
    width: 640
    height: 240

    readonly property string imagePath: decodeURIComponent(String(Qt.resolvedUrl("images/red.png")).replace(/^file:\/\//, ""))
    function card(label, image) {
        return {
            name: label.toLowerCase(), label: label, state: "ok", generation: 0, previewImage: null, image: image,
            palette: { background: "#101010ff", foreground: "#eeeeeeff", accent: "#3366ffff", success: "#00aa00ff", warning: "#ccaa00ff", danger: "#aa0000ff", info: "#0066aaff" },
            tokens: { color: { surfaceRaised: "#202020ff" } }
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

    TestCase {
        name: "themeCard"
        when: windowShown

        // Whether a visible item under ITEM draws TEXT.
        function drawsText(item, text) {
            for (const child of item.children) {
                if (child.visible && child.text === text) return true;
                if (drawsText(child, text)) return true;
            }
            return false;
        }

        function test_a_card_without_a_wallpaper_names_its_theme() {
            verify(drawsText(root, "Bare"), "the card with no wallpaper draws its name");
        }

        function test_a_card_with_a_wallpaper_draws_no_name() {
            verify(!drawsText(root, "Walled"), "the wallpaper card draws no name");
        }
    }
}
