import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit
import "../../shell/plugins/vgs.themes"
import "../../shell/plugins/vgs.themes/BrowserLogic.js" as BrowserLogic

// The themes browser overlay over a stand-in shell: the theme view asks the
// theme capability for a catalog card's sharpened preview, and the answer
// arrives through a waiter that lives as long as the plugin instance, the
// browser, not the view. The stand-in keeps that callback as the capability
// does and calls it after a view switch destroyed the theme view.
Item {
    id: root
    width: 1280
    height: 800

    readonly property string imagePath: decodeURIComponent(String(Qt.resolvedUrl("images/red.png")).replace(/^file:\/\//, ""))
    readonly property var colors: ({
        background: "#101010ff", foreground: "#eeeeeeff", accent: "#3366ffff",
        success: "#00aa00ff", warning: "#ccaa00ff", danger: "#aa0000ff", info: "#0066aaff"
    })
    function terminal() {
        const out = {};
        for (let i = 0; i < 16; i++) out["color" + i] = "#202020ff";
        return out;
    }
    // A catalog theme, not installed, with a thumbnail and no shipped
    // preview: a card the view asks a preview for.
    function entry(name) {
        return { name: name, installed: false, palette: root.colors, tokens: null, terminal: root.terminal(),
            previewPath: null, thumbnailPath: root.imagePath, imagery: null, imageryInstalled: false };
    }
    function snapshot() {
        const entries = [root.entry("probe"), root.entry("rival")];
        return { revision: 1, listReason: "", catalog: { entries: entries, reason: null },
            cards: BrowserLogic.cards([], entries, [], Theme.name), images: { images: [], reason: null }, generations: {} };
    }

    // The names the view asked previews for, and the last callback.
    property var asked: []
    property var answer: null
    readonly property var shell: ({
        ipc: {
            call: (name, revision) => {
                if (name === "refresh-browser-data") return "ok";
                if (name !== "browser-data") throw new Error("stand-in: ipc " + name);
                return revision === "1" ? "" : JSON.stringify(root.snapshot());
            }
        },
        theme: {
            listing: null,
            last: { applying: null, result: null, downloading: null },
            preview: (name, done) => {
                root.asked = root.asked.concat([name]);
                root.answer = done;
                return "ok";
            }
        },
        screens: { all: [], current: null },
        surfaces: { hide: () => "ok" }
    })

    Browser {
        id: browser
        anchors.fill: parent
        shell: root.shell
    }

    TestCase {
        name: "themesBrowser"
        when: windowShown

        function cleanupTestCase() { UnitTheme.reset(); }

        function page() {
            return browser.children.find(child => child instanceof Loader);
        }

        function carousel(item) {
            if (item instanceof CardCarousel) return item;
            for (const child of item.children) {
                const found = carousel(child);
                if (found !== null) return found;
            }
            return null;
        }

        // The rail's row for theme NAME, as the view hands it to its card.
        function railRow(name) {
            const model = carousel(page().item).model;
            for (let i = 0; i < model.count; i++)
                if (model.get(i).modelData.name === name) return model.get(i).modelData;
            return null;
        }

        function test_a_preview_answer_after_a_view_switch_lands_in_the_browser() {
            browser.open(JSON.stringify({ view: "themes" }));
            tryVerify(() => root.asked.length === 1, 5000, "the theme view asks a preview for the catalog card");
            compare(root.asked[0], "probe");
            const previews = page().item.previews;
            // The rail moves on while the preview runs: the next card is
            // wanted, its preview waits for the running one.
            browser.navigate("right");
            compare([previews.running, previews.wanted], ["probe", "rival"]);

            browser.switchView(1);
            compare(browser.view, "wallpapers");
            wait(0);
            compare(previews.wanted, "", "no theme view rests on a card");
            // The capability calls back after the theme view is gone.
            root.answer({ state: "ok", theme: "probe", path: root.imagePath, reason: null });
            compare(previews.running, "");
            compare(root.asked.length, 1, "no preview starts with no theme view shown");

            browser.switchView(-1);
            compare(browser.view, "themes");
            tryVerify(() => page().item !== null && page().item.shownCards.length === 2, 5000);
            compare(page().item.previews.cache.probe, root.imagePath, "the answer is kept across the switch");
            compare(railRow("probe").sharpenedImage, root.imagePath, "the rail draws the kept preview");
            // The new view rests on the kept card and starts nothing for it.
            compare([previews.wanted, previews.running], ["probe", ""]);
            verify(!previews.want("probe"), "a kept preview needs no start");
            previews.start();
            compare(root.asked.length, 1, "a kept preview is not asked again");
        }
    }
}
