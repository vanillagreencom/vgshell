import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit

// The notice reads its container's ground in both modes and blends its
// shared fill over it; only its icon takes a tone. Actions stay below the words, the
// opt-out keeps the right edge, and the X centres on the title line.
// Each action has its keyboard path and its own signal. Plain text
// supplied by another program creates no page link.
Item {
    id: root
    width: 480
    height: 640

    // A palette whose accent, info, warning and danger are four distinct
    // saturated hues and whose foreground is grey, so a state that draws
    // another's colour, or the info state that takes any hue, shows.
    readonly property var themes: [
        { tag: "dark", tokens: { scheme: { mode: "dark" }, palette: { background: "#101010", foreground: "#c8c8c8", accent: "#00ff00", info: "#0000ff", warning: "#ffaa00", danger: "#ff0000", success: "#00ffff" } } },
        { tag: "light", tokens: { scheme: { mode: "light" }, palette: { background: "#f6f6f6", foreground: "#202020", accent: "#00aa00", info: "#0000cc", warning: "#aa6600", danger: "#cc0000", success: "#008888" }, color: { text: "#888888", textMuted: "#999999" } } }
    ]
    readonly property var hues: ({ danger: 0, warning: 40 / 360 })
    readonly property string longText: "This notice runs on for long enough that it has to wrap onto a second line and then a third one at the width the test gives it."
    TextMetrics { id: linkMeasure }

    Component {
        id: made
        Callout { width: 360 }
    }

    Component {
        id: panelMade
        Item {
            width: 360; height: 240
            property alias notice: banner
            property alias fill: plate.hintGround
            Surface { id: plate; anchors.fill: parent; level: "raised" }
            Pane {
                anchors.fill: parent
                Callout { id: banner; text: "A power problem" }
            }
        }
    }
    Component {
        id: cardMade
        Card {
            width: 360
            property alias notice: banner
            readonly property color fill: color
            Callout { id: banner; text: "An account problem" }
        }
    }

    TestCase {
        name: "callout"
        when: windowShown

        // Theme's first read builds the stand-in ThemeSource that UnitTheme
        // drives; this file declares no item that reads Theme at load.
        function init() { void Theme.callout; UnitTheme.reset(); }
        function cleanup() { UnitTheme.reset(); }

        function icon(callout) { return callout.children[0].children[0]; }
        function lines(callout) { return callout.children[0].children[1]; }
        function title(callout) { return lines(callout).children[0]; }
        function body(callout) { return lines(callout).children[1]; }
        function plainBody(callout) { return lines(callout).children[2]; }
        function footer(callout) { return lines(callout).children[3]; }
        function linkRow(callout) { return footer(callout).children[0]; }
        function rowLinks(callout) { return Array.from(linkRow(callout).children).filter(child => child instanceof RowAction); }
        function pageActions(callout) { return rowLinks(callout).slice(0, callout.message.actions.length); }
        function link(callout) { return rowLinks(callout)[callout.message.actions.length]; }
        // Each of `links`, in order, past the Repeater that makes them.
        function actions(callout) { return rowLinks(callout).slice(callout.message.actions.length + 1); }
        function dismissal(callout) { return footer(callout).children[1]; }
        function close(callout) { return callout.children[0].children[2]; }
        function colour(value) { return String(Qt.color(value)); }
        function descendants(item) { return Array.from(item.children).reduce((all, child) => all.concat([child], descendants(child)), []); }
        function ringOf(control) { return descendants(control).find(item => item.target === control && item.outside !== undefined) || null; }
        function make(properties) {
            const callout = made.createObject(root, properties);
            verify(callout !== null, "the callout builds");
            return callout;
        }

        function test_only_the_icon_takes_the_tone_data() {
            const rows = [];
            for (const theme of root.themes)
                for (const tone of ["danger", "warning", "info"])
                    rows.push({ tag: tone + " " + theme.tag, tone: tone, theme: theme.tokens });
            return rows;
        }

        function test_the_tone_supplies_its_icon_data() {
            const rows = [];
            for (const theme of root.themes)
                for (const entry of [{ tone: "danger", icon: "circle-alert" }, { tone: "warning", icon: "triangle-alert" }, { tone: "info", icon: "info" }])
                    rows.push({ tag: theme.tag + " " + entry.tone, theme: theme.tokens, tone: entry.tone, icon: entry.icon });
            return rows;
        }

        function test_the_tone_supplies_its_icon(data) {
            compare(UnitTheme.override(data.theme), "ok");
            const callout = make({ tone: data.tone, text: "A notice" });
            compare(icon(callout).visible, true);
            compare(icon(callout).name, data.icon);
            compare(colour(icon(callout).color), colour(Theme.callout.tone[data.tone].foreground));
            callout.iconName = "book-open";
            compare(icon(callout).name, "book-open");
            callout.iconName = "";
            compare(icon(callout).name, data.icon);
            callout.destroy();
        }

        function test_only_the_icon_takes_the_tone(data) {
            compare(UnitTheme.override(data.theme), "ok");
            const callout = make({ tone: data.tone, iconName: "info", title: "A title", text: "Read the [guide](page:vgs.gallery) first.", linkText: "Open the guide", links: ["Show", "Stop"], dismissible: true, showDontShowAgain: true });
            const want = Theme.callout.tone[data.tone];
            compare(colour(callout.color), colour(Qt.tint(callout.ground.fill, Theme.callout.background)), "the fill");
            compare(callout.border.width, 0, "no border");
            compare(colour(icon(callout).color), colour(want.foreground));
            compare(colour(title(callout).color), colour(Theme.callout.title));
            compare(colour(body(callout).color), colour(Theme.callout.text));
            compare([colour(body(callout).linkColor), colour(link(callout).foreground)].concat(actions(callout).map(action => colour(action.foreground))), Array(4).fill(colour(Theme.callout.link.foreground)));
            for (const action of [link(callout)].concat(actions(callout)))
                compare(action.tokens, Theme.callout.link);
            compare([colour(dismissal(callout).color), colour(dismissal(callout).linkColor)], Array(2).fill(colour(Theme.callout.dismiss)));
            compare(dismissal(callout).role, "calloutDismiss");
            compare(Theme.text.calloutDismiss.size, Math.round(Theme.font.size * 0.93));
            const drawn = [callout.color, want.foreground].map(value => Qt.color(value));
            if (data.tone === "info") {
                for (const value of drawn) compare(value.hslSaturation, 0, "the info state takes no hue: " + value);
            } else {
                fuzzyCompare(Qt.color(want.foreground).hslHue, root.hues[data.tone], 0.02, "the icon keeps its hue");
            }
            callout.destroy();
        }

        // expected-log: Callout: no tone named "loud" -- the test names an unknown state on purpose
        function test_an_unknown_state_is_logged_and_drawn_as_info() {
            const callout = make({ tone: "loud", text: "x" });
            compare(colour(callout.tokens.foreground), colour(Theme.callout.tone.info.foreground));
            callout.destroy();
        }

        // The icon's centre lies in the first line box of the lead line and
        // above the block's centre, with and without a title.
        function test_the_icon_stays_on_the_first_line_data() {
            return [
                { tag: "a title over wrapped text", title: "A title" },
                { tag: "wrapped text with no title", title: "" }
            ];
        }

        function test_the_icon_stays_on_the_first_line(data) {
            const callout = make({ iconName: "info", title: data.title, text: root.longText });
            const lead = data.title === "" ? body(callout) : title(callout);
            verify(body(callout).lineCount >= 3, "the text wraps onto three lines: " + body(callout).lineCount);
            const leadTop = lead.mapToItem(callout, 0, 0).y;
            const firstLine = lead.height / lead.lineCount;
            const centre = icon(callout).mapToItem(callout, 0, icon(callout).height / 2).y;
            verify(centre > leadTop && centre < leadTop + firstLine, "the icon centres on the first line: " + [centre, leadTop, firstLine]);
            verify(centre < lines(callout).mapToItem(callout, 0, lines(callout).height / 2).y - firstLine / 2, "the icon is not on the block's centre");
            callout.destroy();
        }

        function test_the_inline_variant_and_bottom_actions() {
            const callout = make({ width: root.width, tone: "danger", text: "VPN dropped. [Open Settings](page:vgs.gallery)." });
            const words = body(callout);
            compare(icon(callout).visible, true);
            compare(title(callout).visible, false);
            compare(words.lineCount, 1);
            compare(footer(callout).visible, false);
            compare(callout.firstStop, words);
            compare(colour(words.color), colour(Theme.callout.text));
            compare(colour(words.linkColor), colour(Theme.callout.link.foreground));
            compare(words.mapToItem(callout, 0, 0).x, Theme.callout.padding + icon(callout).width + Theme.callout.iconGap, "the line clears its tone's icon");
            callout.linkText = "Turn VPN off";
            tryVerify(() => link(callout).mapToItem(callout, 0, 0).y >= words.mapToItem(callout, 0, words.height).y + Theme.callout.gap);
            callout.destroy();
        }

        function test_the_message_is_the_main_line_data() {
            return [{ tag: "linked", plain: false }, { tag: "plain", plain: true }];
        }

        function test_the_message_is_the_main_line(data) {
            const callout = make({ text: "Notice available", plain: data.plain });
            const words = data.plain ? plainBody(callout) : body(callout);
            const drawn = data.plain ? words : words.children[0];
            compare(drawn.font.weight, Theme.text.body.weight, "a message with no title has regular weight");
            const centre = words.mapToItem(callout, 0, (words.height + words.inkAbove - words.inkBelow) / 2).y;
            const ratio = words.Screen.devicePixelRatio;
            const snapped = Math.round((centre - icon(callout).height / 2) * ratio) / ratio + icon(callout).height / 2;
            fuzzyCompare(icon(callout).mapToItem(callout, 0, icon(callout).height / 2).y, snapped, 0.01, "the icon shares the single line's ink centre on a device pixel");
            callout.destroy();
        }

        function test_only_the_title_is_bold() {
            for (const plain of [false, true]) {
                const callout = make({ title: "A title", text: "A problem.\n[Change shortcut](page:vgs.launcher/Settings/Keys)", plain: plain, linkText: "Try again" });
                compare(title(callout).font.weight, Theme.text.bodyStrong.weight);
                const words = plain ? plainBody(callout) : body(callout).children[0];
                compare(words.font.weight, Theme.text.body.weight, "the message and any inline page link are regular");
                compare(link(callout).contentItem.children[1].font.weight, Theme.text.body.weight, "the bottom action is regular");
                callout.destroy();
            }
        }

        function test_the_ground_follows_the_container_data() { return root.themes; }
        function test_the_ground_follows_the_container(data) {
            compare(UnitTheme.override(data.tokens), "ok");
            const original = root.Window.window.color;
            // Keep the window distinct from the panel and card, so an
            // ancestor-only read cannot pass the sibling-panel case.
            root.Window.window.color = Theme.color.background;
            const page = make({ text: "A settings problem" });
            const panel = panelMade.createObject(root);
            const card = cardMade.createObject(root);
            verify(panel !== null && card !== null);
            const cases = [{ notice: page, fill: root.Window.window.color }, panel, card];
            const endpoint = data.tag === "dark" ? 1 : 0;
            for (const item of cases) {
                tryVerify(() => Qt.colorEqual(item.notice.ground.fill, item.fill), 1000, "the banner reads its actual ground: " + [item.notice.ground.fill, item.fill]);
                const ground = Qt.color(item.fill);
                const drawn = Qt.color(item.notice.color);
                // Independent of the token expression and Qt.tint: the
                // approved rule moves each channel 8% toward contrast.
                for (const channel of ["r", "g", "b"])
                    fuzzyCompare(drawn[channel], ground[channel] + (endpoint - ground[channel]) * 0.08, 1 / 255);
                verify(!Qt.colorEqual(drawn, ground), "the Bluetooth arrangement cannot draw its panel's own fill");
            }
            page.destroy(); panel.destroy(); card.destroy();
            root.Window.window.color = original;
        }

        function test_a_page_reference_wraps_before_its_words() {
            const callout = make({ text: "Change the shortcut in [Settings/Keys](page:vgs.launcher/Settings/Keys)." });
            const words = body(callout);
            linkMeasure.font = words.children[0].font;
            const prefix = words.layout.text.slice(0, words.layout.links[0].start);
            linkMeasure.text = prefix + "Settings/";
            const partial = linkMeasure.advanceWidth;
            linkMeasure.text = prefix + "Settings/Keys";
            const narrow = 2 * Theme.callout.padding + icon(callout).width + Theme.callout.iconGap + (partial + linkMeasure.advanceWidth) / 2;
            callout.width = narrow;
            tryVerify(() => words.underlined.length === 1 && words.underlined[0].line > 0);
            compare(words.plain, "Change the shortcut in Settings/Keys.");
            callout.width = 480;
            tryVerify(() => words.underlined.length === 1 && words.underlined[0].line === 0);
            callout.width = narrow;
            tryVerify(() => words.underlined.length === 1 && words.underlined[0].line > 0);
            callout.destroy();
        }

        function test_the_change_link_starts_its_own_line() {
            const message = Reply.line("hyprland: SUPER+SPACE for vgs.launcher:toggle skipped: already bound by acme.other", [], () => ({ kind: "resolved", text: "Super+Space" }));
            const callout = make({ text: message });
            for (const width of [800, 240]) {
                callout.width = width;
                tryVerify(() => pageActions(callout).length === 1 && footer(callout).visible);
                const action = pageActions(callout)[0];
                tryVerify(() => action.mapToItem(callout, 0, 0).y >= body(callout).mapToItem(callout, 0, body(callout).height).y + Theme.callout.gap,
                    1000, "the change action stands below the body, in the action row");
                compare(body(callout).links.length, 0, "the body no longer draws the action");
                compare(action.contentItem.children[1].font.weight, Theme.text.body.weight);
                const pages = [];
                callout.pageActivated.connect((page, tab) => pages.push([page, tab]));
                mouseClick(action, action.width / 2, action.height / 2);
                compare(JSON.stringify(pages), JSON.stringify([["vgs.launcher", "Settings/Keys"]]));
            }
            callout.destroy();
        }

        function test_moved_page_actions_share_the_footer_and_keep_their_routes_data() {
            return [{ tag: "one row", width: 480, wrapped: false }, { tag: "wrapped row", width: 240, wrapped: true }];
        }
        function test_moved_page_actions_share_the_footer_and_keep_their_routes(data) {
            const callout = make({ width: data.width, title: "Speech only", text: "A speech-only route.\n[Set Talk key](page:vgs.jarvis/Settings/Keys)",
                linkText: "Voice settings", links: ["Show", "Stop"] });
            tryVerify(() => pageActions(callout).length === 1 && actions(callout).length === 2);
            const moved = pageActions(callout)[0];
            const primary = link(callout);
            if (data.wrapped) callout.width = 2 * Theme.callout.padding + icon(callout).width + Theme.callout.iconGap
                + moved.width + Theme.rowAction.gap + primary.width + 1;
            compare(body(callout).plain, "A speech-only route.");
            compare(moved.parent, primary.parent, "moved and existing actions share the owner's action row");
            tryVerify(() => moved.y === primary.y, 1000, "both first actions sit on the same row");
            verify(moved.x + moved.width + Theme.rowAction.gap <= primary.x, "the moved action comes before the existing footer");
            compare(linkRow(callout).placed.lines > 1, data.wrapped, "the same action row owns wrapping");
            const pages = [];
            const chosen = [];
            let activated = 0;
            callout.pageActivated.connect((page, tab) => pages.push([page, tab]));
            callout.activated.connect(() => activated++);
            callout.actionActivated.connect(index => chosen.push(index));
            compare(callout.firstStop, moved);
            moved.forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Return);
            keyClick(Qt.Key_Tab);
            tryCompare(primary, "visualFocus", true);
            keyClick(Qt.Key_Return);
            for (const action of actions(callout)) {
                keyClick(Qt.Key_Tab);
                tryCompare(action, "visualFocus", true);
                keyClick(Qt.Key_Return);
            }
            compare(JSON.stringify(pages), JSON.stringify([["vgs.jarvis", "Settings/Keys"]]));
            compare(activated, 1, "the original footer keeps activated");
            compare(JSON.stringify(chosen), JSON.stringify([0, 1]), "listed footer actions keep their original indices");
            callout.destroy();
        }

        function test_dismissal_placement_data() {
            return [{ tag: "wide", width: 480, stacked: false }, { tag: "narrow", width: 240, stacked: true }];
        }
        function test_dismissal_placement(data) {
            const callout = make({ width: data.width, title: "A title", text: root.longText, linkText: "Open Setup", dismissible: true, showDontShowAgain: true });
            tryCompare(footer(callout), "stacked", data.stacked);
            const x = close(callout);
            compare([x.iconName, x.size], ["x", "sm"]);
            compare(x.x + x.width, callout.width - Theme.callout.padding);
            fuzzyCompare(x.y, title(callout).y + title(callout).topForLeadingIcon(x.height, title(callout).y, true), 1);
            verify(title(callout).mapToItem(callout, title(callout).width, 0).x + Theme.callout.iconGap <= x.x, "the title clears the X");
            compare(dismissal(callout).x + dismissal(callout).width, footer(callout).width);
            if (data.stacked) verify(dismissal(callout).y >= linkRow(callout).height + Theme.callout.gap);
            callout.destroy();
        }

        // Tab walks the page link, the RowAction, each of the links and
        // the opt-out and X in order, each under the shared ring; Return emits
        // each one's own signal.
        function test_the_links_and_dismissals_take_the_keyboard() {
            const callout = make({ tone: "warning", title: "A title", text: "Choose a [Home folder](page:vgs.jarvis/Settings/home).", linkText: "Open Setup", links: ["Show", "Stop"], dismissible: true, showDontShowAgain: true });
            const pages = [];
            const chosen = [];
            let links = 0;
            let dismissed = 0;
            let suppressed = 0;
            callout.pageActivated.connect((page, tab) => pages.push([page, tab]));
            callout.activated.connect(() => links++);
            callout.actionActivated.connect(index => chosen.push(index));
            callout.dismissed.connect(() => dismissed++);
            callout.dontShowAgain.connect(() => suppressed++);
            compare(callout.firstStop, body(callout), "the page link is the first stop");
            callout.firstStop.forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Return);
            compare(JSON.stringify(pages), JSON.stringify([["vgs.jarvis", "Settings/home"]]), "Return on the page link opens its page");
            keyClick(Qt.Key_Tab);
            tryCompare(link(callout), "visualFocus", true);
            verify(ringOf(link(callout)) !== null && ringOf(link(callout)).visible, "the link draws its ring");
            keyClick(Qt.Key_Return);
            compare(links, 1, "Return on the link activates it");
            for (const action of actions(callout)) {
                keyClick(Qt.Key_Tab);
                tryCompare(action, "visualFocus", true);
                verify(ringOf(action) !== null && ringOf(action).visible, action.text + " draws its ring");
                keyClick(Qt.Key_Return);
            }
            compare(JSON.stringify(chosen), JSON.stringify([0, 1]), "Return on each of the links names its index");
            keyClick(Qt.Key_Tab);
            tryCompare(dismissal(callout), "visualFocus", true);
            verify(ringOf(dismissal(callout)) !== null && ringOf(dismissal(callout)).visible);
            keyClick(Qt.Key_Return);
            compare(suppressed, 1);
            keyClick(Qt.Key_Tab);
            tryCompare(close(callout), "visualFocus", true);
            verify(ringOf(close(callout)) !== null && ringOf(close(callout)).visible);
            keyClick(Qt.Key_Return);
            keyClick(Qt.Key_Space);
            compare(dismissed, 2, "Return and Space dismiss");
            const plain = make({ text: "No link here", dismissible: true });
            compare(plain.firstStop, close(plain), "with no link the X is the first stop");
            const listed = make({ text: "No link here", links: ["Show"] });
            compare(listed.firstStop, actions(listed)[0], "with only links the first of them is the first stop");
            const none = make({ text: "Nothing to do" });
            compare(none.firstStop, null, "a banner with no action has no stop");
            plain.destroy();
            listed.destroy();
            none.destroy();
            callout.destroy();
        }

        // Words another program supplies: the title's markup and the text's
        // page reference draw as the characters they are, so the banner
        // takes no stop for them.
        function test_a_plain_notice_draws_its_words_as_they_are() {
            compare(UnitTheme.override(root.themes[1].tokens), "ok");
            const words = "Read <b>now</b>.\n[Guide](page:vgs.gallery)";
            const callout = make({ plain: true, iconName: "info", title: "<b>A</b> title", text: words });
            compare(title(callout).textFormat, Text.PlainText, "the title draws its markup as characters");
            compare(body(callout).visible, false, "the linked text is not drawn");
            compare([plainBody(callout).visible, plainBody(callout).text, plainBody(callout).textFormat], [true, words, Text.PlainText], "the text draws as it came");
            compare(colour(plainBody(callout).color), colour(Theme.callout.text));
            compare(callout.firstStop, null, "the page reference is no stop");
            callout.destroy();
        }
    }
}
