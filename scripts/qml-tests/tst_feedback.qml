import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit

// Spinner, ProgressBar, Badge and Kbd: the spinner turns only while the
// theme's duration is above zero, the bar's fill follows its position and
// slides while indeterminate, a badge draws its tone and logs an unknown
// one, a verbatim badge keeps its text's case on the same box, and a key
// cap sizes to its text and draws it in the kbd role.
Item {
    id: root
    width: 300
    height: 200

    Spinner { id: spinner }
    ProgressBar { id: progress; value: 0.25; width: 200; y: 30 }
    ProgressBar { id: busy; indeterminate: true; width: 200; y: 50 }
    ProgressBar { id: mirroredBar; value: 0.25; width: 200; y: 60; LayoutMirroring.enabled: true }
    Badge { id: badge; text: "Verified"; tone: "success"; y: 70 }
    Badge { id: badgeIcon; text: "Verified"; tone: "success"; iconName: "check"; y: 100 }
    Badge { id: badgeMd; text: "Verified"; tone: "success"; size: "md"; y: 130 }
    Badge { id: badgeVerbatim; text: "voxtype-bin"; verbatim: true; x: 150; y: 70 }
    Kbd { id: kbd; text: "Ctrl"; y: 160 }
    Kbd { id: key; text: "K"; y: 190; x: 100 }

    TestCase {
        name: "feedback"
        when: windowShown

        function init() { UnitTheme.reset(); }

        function fill(bar) { return bar.contentItem.children[0]; }
        function instrumentedSpinner() {
            const request = new XMLHttpRequest();
            request.open("GET", UnitPaths.UI_DIR + "/feedback/Spinner.qml", false);
            request.send();
            let source = request.responseText;
            verify(source.indexOf("Shape {") !== -1, "the spinner source has a Shape");
            verify(source.indexOf("RotationAnimation on rotation {") !== -1, "the spinner source has a rotation animation");
            source = source.replace("Shape {", "Shape { property alias spin: spin");
            source = source.replace("RotationAnimation on rotation {", "RotationAnimation on rotation { id: spin");
            return Qt.createQmlObject(source, root, "InstrumentedSpinner");
        }
        function badgeLabel(item) { return item.children.find(child => child.role === "label"); }
        function badgeIconItem(item) { return item.children.find(child => child.name === item.iconName); }
        function kbdLabel(item) { return item.children[0]; }

        function test_spinner_turns_and_reduced_motion_stops_it() {
            const checked = instrumentedSpinner();
            compare(checked.width, Theme.spinner.size);
            const shape = checked.children[0];
            const spin = shape.spin;
            const angle = shape.rotation;
            tryVerify(() => shape.rotation !== angle, 1000, "the arc turned");
            compare(UnitTheme.override({ motion: { scale: 0 } }), "ok");
            compare(Theme.spinner.duration, 0);
            compare(spin.running, false);
            checked.destroy();
        }

        function test_progress_fill_follows_the_value() {
            fuzzyCompare(fill(progress).width, progress.contentItem.width / 4, 1);
            compare(progress.height, Theme.progress.height);
            compare(String(fill(progress).color), String(Qt.color(Theme.progress.fill)));
            const slide = fill(busy).x;
            fuzzyCompare(fill(busy).width, busy.contentItem.width * Theme.progress.indeterminateShare, 1);
            tryVerify(() => fill(busy).x !== slide, 1000, "the indeterminate fill moved");
            // Leaving the indeterminate state returns the fill to the origin.
            busy.indeterminate = false;
            busy.value = 1;
            tryCompare(fill(busy), "x", 0);
            fuzzyCompare(fill(busy).width, busy.contentItem.width, 1);
            busy.indeterminate = true;
        }

        function test_mirrored_progress_fills_from_the_right() {
            fuzzyCompare(fill(mirroredBar).width, mirroredBar.contentItem.width / 4, 1);
            fuzzyCompare(fill(mirroredBar).x + fill(mirroredBar).width, mirroredBar.contentItem.width, 1);
            mirroredBar.value = 0;
            fuzzyCompare(fill(mirroredBar).width, 0, 1);
            mirroredBar.value = 0.25;
        }

        // expected-log: ProgressBar: no tone named "loud"; drawing accent -- the test names an unknown tone on purpose
        function test_progress_draws_its_tone() {
            const bar = Qt.createQmlObject("import qs.Ui\nProgressBar { value: 0.5 }", root);
            compare(bar.tone, "accent");
            compare(String(fill(bar).color), String(Qt.color(Theme.progress.fill)));
            for (const tone of ["neutral", "info", "success", "warning", "danger"]) {
                bar.tone = tone;
                compare(String(fill(bar).color), String(Qt.color(Theme.badge.tone[tone].foreground)), tone);
            }
            bar.tone = "loud";
            compare(String(fill(bar).color), String(Qt.color(Theme.progress.fill)));
            bar.destroy();
        }

        // expected-log: Badge: no tone named "loud" -- the test names an unknown tone on purpose
        function test_badge_draws_its_tone() {
            compare(String(badge.color), String(Qt.color(Theme.badge.tone.success.background)));
            compare(badge.height, Theme.badge.size.sm.height);
            compare(badgeMd.height, Theme.badge.size.md.height);
            const odd = Qt.createQmlObject("import qs.Ui\nBadge { tone: \"loud\"; text: \"x\" }", root);
            compare(String(odd.color), String(Qt.color(Theme.badge.tone.neutral.background)));
            odd.destroy();
        }

        function test_badge_centres_text_and_uses_optical_width() {
            // The capital centre sits on the box centre on a whole-pixel
            // baseline: within half a pixel of it.
            const label = badgeLabel(badge);
            compare(label.y + label.baselineOffset, Math.round(label.y + label.baselineOffset), "a whole-pixel baseline");
            fuzzyCompare(label.y + label.capCentre, badge.height / 2, 0.5);
            fuzzyCompare(label.x, Theme.badge.size.sm.paddingX, 0.5);
            fuzzyCompare(badge.width - (label.x + label.opticalWidth), Theme.badge.size.sm.paddingX, 0.5);
            const icon = badgeIconItem(badgeIcon);
            const iconLabel = badgeLabel(badgeIcon);
            fuzzyCompare(icon.y + icon.height / 2, badgeIcon.height / 2, 1);
            compare(iconLabel.y + iconLabel.baselineOffset, Math.round(iconLabel.y + iconLabel.baselineOffset), "a whole-pixel baseline");
            fuzzyCompare(iconLabel.y + iconLabel.capCentre, badgeIcon.height / 2, 0.5);
            fuzzyCompare(badgeIcon.width, 2 * Theme.badge.size.sm.paddingX + icon.width + Theme.badge.gap + iconLabel.opticalWidth, 0.5);
        }

        // A package name keeps its case: the default badge draws capitals,
        // a verbatim one the text as written, on the same height with its
        // capital centre on the box centre.
        function test_badge_verbatim_keeps_case() {
            const plain = badge.children.find(child => child.text === badge.text);
            const label = badgeVerbatim.children.find(child => child.text === badgeVerbatim.text);
            compare(plain.font.capitalization, Font.AllUppercase, "a default badge draws capitals");
            compare(label.font.capitalization, Font.MixedCase, "a verbatim badge keeps the case");
            compare(label.text, "voxtype-bin");
            compare(badgeVerbatim.height, Theme.badge.size.sm.height);
            compare(label.y + label.baselineOffset, Math.round(label.y + label.baselineOffset), "a whole-pixel baseline");
            fuzzyCompare(label.y + label.capCentre, badgeVerbatim.height / 2, 0.5);
            fuzzyCompare(badgeVerbatim.width - (label.x + label.opticalWidth), Theme.badge.size.sm.paddingX, 0.5);
        }

        function test_kbd_sizes_to_its_text() {
            verify(kbd.width > 2 * Theme.kbd.paddingX, "the cap is wider than its padding");
            compare(kbd.border.width, Theme.kbd.border);
            const label = kbdLabel(kbd);
            compare(kbd.height, Theme.kbd.height);
            compare(kbd.height, 20);
            verify(kbd.width >= kbd.height, "the cap is never narrower than it is tall");
            compare(key.width, key.height, "a one-letter cap is square");
            fuzzyCompare(kbdLabel(key).x + kbdLabel(key).opticalWidth / 2, key.width / 2, 0.5);
            compare(kbd.width, Math.round(kbd.width));
            fuzzyCompare(label.x, Theme.kbd.paddingX, 0.5);
            fuzzyCompare(kbd.width - (label.x + label.opticalWidth), Theme.kbd.paddingX, 0.5);
            fuzzyCompare(label.y + label.capCentre, kbd.height / 2, 0.5);
            compare(UnitTheme.override({ kbd: { paddingX: 12, height: 24, background: "#00ff00" } }), "ok");
            compare(String(kbd.color), "#00ff00");
            verify(kbd.width > 24, "wider padding widens the cap");
            compare(kbd.height, 24);
        }

        function test_kbd_draws_the_kbd_role() {
            const label = kbd.children[0];
            compare(label.font.pixelSize, Theme.text.kbd.size);
            compare(label.font.weight, Theme.text.kbd.weight);
            compare(label.lineHeight, label.lineBox);
        }
    }
}
