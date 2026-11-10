import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit

// Callout, the notice banner: each state, danger, warning and info, in a
// dark and a light theme, fills with its own background and draws its
// icon, title, text and button label and outline in its own ink, and its
// links, the inline page link and the RowAction, in its own link colour,
// never the accent; the danger and warning states keep their palette
// hue, and the info state takes no hue at all, under a palette whose
// accent and info are both saturated. An unknown state is logged and
// drawn as info. The icon centres on the first line of a notice of
// several lines, the title's or, with no title, the text's, never on the
// block. A title-less, icon-less banner of one line and a button is as
// tall as the button and its padding, the line level with the button's
// label, the button on the banner's right padding and the line clear of
// it. The page link, the RowAction and the button are Tab stops in that
// order, each draws the shared focus ring under keyboard focus, Return
// on each emits its own signal, and `firstStop` names the first shown.
Item {
    id: root
    width: 480
    height: 640

    // A palette whose accent, info, warning and danger are four distinct
    // saturated hues and whose foreground is grey, so a state that draws
    // another's colour, or the info state that takes any hue, shows.
    readonly property var themes: [
        { tag: "dark", tokens: { scheme: { mode: "dark" }, palette: { background: "#101010", foreground: "#c8c8c8", accent: "#00ff00", info: "#0000ff", warning: "#ffaa00", danger: "#ff0000", success: "#00ffff" } } },
        { tag: "light", tokens: { scheme: { mode: "light" }, palette: { background: "#f6f6f6", foreground: "#202020", accent: "#00aa00", info: "#0000cc", warning: "#aa6600", danger: "#cc0000", success: "#008888" } } }
    ]
    readonly property var hues: ({ danger: 0, warning: 40 / 360 })
    readonly property string longText: "This notice runs on for long enough that it has to wrap onto a second line and then a third one at the width the test gives it."

    Component {
        id: made
        Callout { width: 360 }
    }

    TestCase {
        name: "callout"
        when: windowShown

        // Theme's first read builds the stand-in ThemeSource that UnitTheme
        // drives; this file declares no item that reads Theme at load.
        function init() { void Theme.callout; UnitTheme.reset(); }
        function cleanup() { UnitTheme.reset(); }

        function icon(callout) { return callout.children[0]; }
        function lines(callout) { return callout.children[1]; }
        function title(callout) { return lines(callout).children[0]; }
        function body(callout) { return lines(callout).children[1]; }
        function link(callout) { return lines(callout).children[2]; }
        function button(callout) { return callout.children[2]; }
        function colour(value) { return String(Qt.color(value)); }
        function descendants(item) { return Array.from(item.children).reduce((all, child) => all.concat([child], descendants(child)), []); }
        function ringOf(control) { return descendants(control).find(item => item.target === control && item.outside !== undefined) || null; }
        function make(properties) {
            const callout = made.createObject(root, properties);
            verify(callout !== null, "the callout builds");
            return callout;
        }

        function test_each_state_draws_its_own_fill_and_ink_data() {
            const rows = [];
            for (const theme of root.themes)
                for (const tone of ["danger", "warning", "info"])
                    rows.push({ tag: tone + " " + theme.tag, tone: tone, theme: theme.tokens });
            return rows;
        }

        function test_each_state_draws_its_own_fill_and_ink(data) {
            compare(UnitTheme.override(data.theme), "ok");
            const callout = make({ tone: data.tone, iconName: "info", title: "A title", text: "Read the [guide](page:vgs.gallery) first.", linkText: "Open the guide", buttonText: "Try again" });
            const want = Theme.callout.tone[data.tone];
            compare(colour(callout.color), colour(want.background), "the fill");
            compare([icon(callout).color, title(callout).color, body(callout).color, button(callout).foreground, button(callout).borderColor].map(colour),
                Array(5).fill(colour(want.foreground)), "the icon, title, text, button label and outline draw in the state's ink");
            compare([colour(body(callout).linkColor), colour(link(callout).foreground)], [colour(want.link.foreground), colour(want.link.foreground)],
                "the page link and the RowAction draw in the state's link colour");
            verify(!Qt.colorEqual(link(callout).foreground, Theme.color.accent) && !Qt.colorEqual(body(callout).linkColor, Theme.color.accent), "no link draws in the accent");
            compare([colour(button(callout).hoverFill), colour(button(callout).pressedFill)], [colour(want.button.hover), colour(want.button.pressed)], "the button's fills");
            const drawn = [callout.color, want.foreground, want.link.foreground].map(value => Qt.color(value));
            if (data.tone === "info") {
                for (const value of drawn) compare(value.hslSaturation, 0, "the info state takes no hue: " + value);
            } else {
                for (const value of drawn) fuzzyCompare(value.hslHue, root.hues[data.tone], 0.02, "the state keeps its own hue: " + value);
            }
            callout.destroy();
        }

        // expected-log: Callout: no tone named "loud" -- the test names an unknown state on purpose
        function test_an_unknown_state_is_logged_and_drawn_as_info() {
            const callout = make({ tone: "loud", text: "x" });
            compare(colour(callout.color), colour(Theme.callout.tone.info.background));
            callout.destroy();
        }

        // The icon's centre lies in the first line box of the lead line and
        // above the block's centre, with and without a title, and with a
        // button beside the lines.
        function test_the_icon_stays_on_the_first_line_data() {
            return [
                { tag: "a title over wrapped text", title: "A title", button: "" },
                { tag: "wrapped text with no title", title: "", button: "" },
                { tag: "wrapped text with no title beside a button", title: "", button: "Try again" }
            ];
        }

        function test_the_icon_stays_on_the_first_line(data) {
            const callout = make({ iconName: "info", title: data.title, text: root.longText, buttonText: data.button });
            const lead = data.title === "" ? body(callout) : title(callout);
            verify(body(callout).lineCount >= 3, "the text wraps onto three lines: " + body(callout).lineCount);
            const leadTop = lead.mapToItem(callout, 0, 0).y;
            const firstLine = lead.height / lead.lineCount;
            const centre = icon(callout).y + icon(callout).height / 2;
            verify(centre > leadTop && centre < leadTop + firstLine, "the icon centres on the first line: " + [centre, leadTop, firstLine]);
            verify(centre < lines(callout).y + lines(callout).height / 2 - firstLine / 2, "the icon is not on the block's centre");
            callout.destroy();
        }

        // The sheet's banner: no icon, no title, one line and a button.
        function test_a_one_line_banner_beside_its_button() {
            const callout = make({ width: root.width, tone: "danger", text: "VPN dropped: traffic blocked", buttonText: "Turn VPN off" });
            const words = body(callout);
            const control = button(callout);
            compare(icon(callout).visible, false);
            compare(title(callout).visible, false);
            compare(words.lineCount, 1);
            verify(control.height > words.height, "the button is taller than the line");
            compare(callout.height, control.height + 2 * Theme.callout.padding, "the banner is as tall as the button and its padding");
            compare(control.x + control.width, callout.width - Theme.callout.padding, "the button stands on the right padding");
            compare(words.mapToItem(callout, 0, 0).x, Theme.callout.padding, "the line starts on the left padding");
            verify(words.mapToItem(callout, 0, 0).x + words.width <= control.x - Theme.callout.buttonGap, "the line stays clear of the button");
            const lineCentre = words.mapToItem(callout, 0, 0).y + words.height / 2;
            fuzzyCompare(lineCentre, control.y + control.height / 2, 1, "the line is level with the button");
            callout.destroy();
        }

        // Tab walks the page link, the RowAction and the button in order,
        // each under the shared ring; Return emits each one's own signal.
        function test_the_links_and_the_button_take_the_keyboard() {
            const callout = make({ tone: "warning", text: "Choose a [Home folder](page:vgs.jarvis/Settings/home).", linkText: "Open Setup", buttonText: "Try again" });
            const pages = [];
            let links = 0;
            let buttons = 0;
            callout.pageActivated.connect((page, tab) => pages.push([page, tab]));
            callout.activated.connect(() => links++);
            callout.buttonActivated.connect(() => buttons++);
            compare(callout.firstStop, body(callout), "the page link is the first stop");
            callout.firstStop.forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Return);
            compare(JSON.stringify(pages), JSON.stringify([["vgs.jarvis", "Settings/home"]]), "Return on the page link opens its page");
            keyClick(Qt.Key_Tab);
            tryCompare(link(callout), "visualFocus", true);
            verify(ringOf(link(callout)) !== null && ringOf(link(callout)).visible, "the link draws its ring");
            keyClick(Qt.Key_Return);
            compare(links, 1, "Return on the link activates it");
            keyClick(Qt.Key_Tab);
            tryCompare(button(callout), "visualFocus", true);
            verify(ringOf(button(callout)) !== null && ringOf(button(callout)).visible, "the button draws its ring");
            keyClick(Qt.Key_Return);
            keyClick(Qt.Key_Space);
            compare(buttons, 2, "Return and Space press the button");
            const plain = make({ text: "No link here", buttonText: "Try again" });
            compare(plain.firstStop, button(plain), "with no link the button is the first stop");
            const none = make({ text: "Nothing to do" });
            compare(none.firstStop, null, "a banner with no action has no stop");
            plain.destroy();
            none.destroy();
            callout.destroy();
        }
    }
}
