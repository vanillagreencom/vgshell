import QtQuick
import QtTest
import qs.Ui
import qs.Commons
import qs.Unit
import "../../shell/plugins/vgs.themes"

Item {
    id: root
    width: 640
    height: 360

    readonly property var samplePalette: ({
        background: "#101010ff",
        foreground: "#eeeeeeff",
        accent: "#3366ffff",
        success: "#00aa00ff",
        warning: "#ccaa00ff",
        danger: "#aa0000ff",
        info: "#0066aaff"
    })
    function terminalSlots() {
        const out = {};
        for (let i = 0; i < 16; i++) out["color" + i] = i === 1 ? "#aa0000ff" : "#202020ff";
        return out;
    }

    DesktopPreview {
        id: preview
        width: 400
        height: 250
        name: "probe"
        label: "Probe"
        tokens: ({
            palette: root.samplePalette,
            color: {
                surfaceRaised: "#222222ff",
                border: "#444444ff",
                borderSubtle: "#333333ff",
                textMuted: "#888888ff"
            },
            hyprland: {
                border: { size: 4 },
                window: { radius: 8 },
                shadow: { color: "#00000080" }
            }
        })
        terminal: root.terminalSlots()
    }

    TestCase {
        name: "desktopPreview"
        when: windowShown

        function cleanupTestCase() { UnitTheme.reset(); }

        function descendants(item) {
            const out = [item];
            for (let i = 0; i < out.length; i++)
                for (const child of out[i].children || []) out.push(child);
            return out;
        }
        function rects() { return descendants(preview).filter(child => String(child).startsWith("QQuickRectangle(")); }
        function labels() {
            const out = [];
            function walk(item) {
                if (item instanceof Text && item.text !== "") out.push(item.text);
                for (const child of item.children) walk(child);
            }
            walk(preview);
            return out;
        }

        function test_preview_uses_the_package_palette() {
            compare(String(preview.backgroundColor), "#101010");
            compare(String(preview.foregroundColor), "#eeeeee");
            compare(String(preview.accentColor), "#3366ff");
            compare(String(preview.activeBorderColor), "#3366ff");
            compare(String(preview.inactiveBorderColor), "#444444");
            preview.tokens = Object.assign({}, preview.tokens, { palette: Object.assign({}, root.samplePalette, { accent: "#ff0000ff" }) });
            compare(String(preview.accentColor), "#ff0000");
            compare(String(preview.activeBorderColor), "#ff0000");
        }

        function test_preview_uses_terminal_and_hyprland_tokens() {
            compare(preview.borderSize, 4);
            compare(preview.windowRadius, 8);
            compare(String(preview.terminalColor(1)), "#ffaa0000");
            preview.tokens = Object.assign({}, preview.tokens, { hyprland: { border: { size: 7 }, window: { radius: 12 }, shadow: { color: "#00000080" } } });
            compare(preview.borderSize, 7);
            compare(preview.windowRadius, 12);
        }

        // The windows: the Settings window and the terminal, each holding
        // its content first, then the launcher's search.
        function windows() {
            return ["previewWindow", "previewTerminal", "previewLauncher"].map(name => descendants(preview).find(child => child.objectName === name));
        }
        function content(box) { return box.children[0]; }
        function withRadius(radius) {
            preview.tokens = Object.assign({}, preview.tokens, { hyprland: { border: { size: 4 }, window: { radius: radius }, shadow: { color: "#00000080" } } });
        }
        function init() {
            preview.width = 400;
            preview.height = 250;
            preview.footHeight = 0;
            withRadius(8);
        }

        // A 32 px window corner with the content's top 12 in: dy = 32 - 12
        // = 20, reach = 32 - 4 = 28, 32 - sqrt(28^2 - 20^2) = 12.40, so
        // each window's content stands 13 in; an 8 px corner keeps the
        // 12 px padding.
        function test_window_content_clears_the_theme_window_corner() {
            withRadius(32);
            const boxes = windows().slice(0, 2);
            for (const box of boxes) compare([content(box).x, content(box).y], [13, 13], box.objectName);
            withRadius(8);
            for (const box of boxes) compare([content(box).x, content(box).y], [12, 12], box.objectName);
        }

        // 400 by 250: scale = max(400 / 1600, 250 / 900) = 250 / 900, so the
        // card's 28 px lean is 28 * 900 / 250 = 100.8 reference px and the
        // safe inset 24 + 100.8 = 124.8. A 50 px foot is 50 * 900 / 250 =
        // 180 reference px, so the windows end by 900 - 124.8 - 180 =
        // 595.2: the terminal, from 0.5 * 900 = 450 for 0.36 * 900 = 324,
        // ends there, and the Settings window, from 0.14 * 900 = 126 for
        // 0.42 * 900 = 378, ends at 504 above it. The right side's
        // overhang would end the terminal at 515.2, and no foot at 774.
        function test_the_windows_end_above_the_foot_at_the_safe_inset() {
            preview.footHeight = 50;
            const [settings, terminal] = windows();
            fuzzyCompare(terminal.y + terminal.height, 595.2, 1e-6);
            fuzzyCompare(settings.y + settings.height, 504, 1e-6);
        }

        // The windows stand apart, inside the reference display, and leave
        // more than half of it to the wallpaper.
        function test_the_wallpaper_shows_around_the_windows() {
            const boxes = windows();
            let covered = 0;
            for (let i = 0; i < boxes.length; i++) {
                const a = boxes[i];
                verify(a.x >= 0 && a.y >= 0 && a.x + a.width <= 1600 && a.y + a.height <= 900, a.objectName + " lies on the display");
                covered += a.width * a.height;
                for (let j = i + 1; j < boxes.length; j++) {
                    const b = boxes[j];
                    verify(a.x + a.width <= b.x || b.x + b.width <= a.x || a.y + a.height <= b.y || b.y + b.height <= a.y, a.objectName + " and " + b.objectName + " stand apart");
                }
            }
            verify(covered < 1600 * 900 / 2, "the windows cover " + covered + " of the display");
        }

        function test_mock_desktop_covers_different_card_aspects() {
            const aspects = [[400, 250], [520, 250]];
            for (const size of aspects) {
                preview.width = size[0];
                preview.height = size[1];
                verify(preview.mockBounds.x <= 0, "left covers " + size);
                verify(preview.mockBounds.y <= 0, "top covers " + size);
                verify(preview.mockBounds.x + preview.mockBounds.width >= preview.width, "right covers " + size);
                verify(preview.mockBounds.y + preview.mockBounds.height >= preview.height, "bottom covers " + size);
            }
        }
    }
}
