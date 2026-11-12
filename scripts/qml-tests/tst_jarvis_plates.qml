import QtQuick
import QtTest
import Quickshell
import qs.Commons
import qs.Ui
import qs.Unit
import "../../shell/plugins/vgs.jarvis"
import "../../shell/plugins/vgs.jarvis/Appearance.js" as Appearance
import "../../shell/plugins/vgs.jarvis/Session.js" as Session

// Jarvis's overlay stands on plates of glass. In each state and both
// modes every plate draws as glass with no drop shadow, whole and clear of
// the others by the look's gap, and holds its content inside its padding;
// the disc shares the orb's centre and holds all the orb draws; the words'
// card follows the lines shown; a plate keeps its opacity while its
// content fades; without glass each plate draws the look's own solid. The
// ground a line stands on is its plate's fill over the wallpaper, read
// from the drawn bubble over white and over black under
// scripts/qml-unit.sh's software OpenGL: the ground scripts/check-theme-contrast.js
// judges every ink against. The window is transparent, as the shell's
// layers are, since glass draws only there (GlassSurface.drawn). A held
// request paints no frame before its console answer.
Item {
    id: root
    width: 1180
    height: 740

    readonly property var look: Theme.appearance(Appearance.TOKENS, Appearance.LIGHT)

    QtObject {
        id: service
        property var sessionState: null
        property var microphoneMute: ({ kind: "ready", muted: false })
        property bool bubbleWanted: true
        property string focusedOutput: "unit"
        property var consoleBox: null
        property string consoleKey: ""
        property string heldKey: ""
        property var effectiveKeys: ({ stop: "SUPER+CTRL+X", confirm: "SUPER+CTRL+Y" })
        property var values: ({})
        property var shell: ({ settings: { voiceProvider: "local" }, status: { values: service.values }, surfaces: { openPage: () => "ok" } })
        function attachBubble(item) {}
        function detachBubble(item) {}
        function intent(name) {}
        property var acknowledged: []
        function shownApproval(item, hold) { acknowledged = acknowledged.concat([hold]); }
        function cancelApproval(hold) {}
        function confirmApproval(hold, how) {}
    }

    Rectangle { id: ground; anchors.fill: parent; color: "#ffffff" }
    // The layer's width: a narrow one puts the screen's edges near the
    // content.
    property real layerWidth: width
    Bubble { id: bubble; width: root.layerWidth; height: root.height; screen: ({ name: "unit" }); service: service }
    QtObject { id: presentedHost; property bool presented: true; property bool visible: true }

    function session(over) {
        const s = Object.assign(JSON.parse(JSON.stringify(Session.initial())), { gen: 1, gate: { kind: "up" } });
        for (const key in over) s[key] = over[key];
        return s;
    }
    function held(text, physical) {
        return session({ approval: { kind: "held", id: "a", gen: 1, digest: "d", purpose: "action", tool: "files.move", physical: physical, text: text } });
    }

    UnitCase {
        name: "jarvis-plates"
        when: windowShown

        function init() {
            root.Window.window.color = "transparent";
            UnitTheme.reset();
            Theme.appearanceInput = "";
            compare(UnitTheme.override({ motion: { scale: 0 } }), "ok");
            root.layerWidth = root.width;
            ground.color = "#ffffff";
            service.bubbleWanted = true;
            service.consoleBox = null;
            service.consoleKey = "";
            service.heldKey = "";
            service.acknowledged = [];
            service.values = {};
            service.sessionState = null;
            mouseMove(root, 1, 1);
        }
        function cleanup() { QsWindow.window = null; }
        function all(item, out) {
            for (const child of item.children) {
                out.push(child);
                all(child, out);
            }
            return out;
        }
        function named(name) { return all(bubble, []).find(item => item.objectName === name); }

        // Service publishes the existing asynchronous console answer after
        // the hold arrives. Pixels from the window must stay empty until
        // then; this file's software OpenGL paints the real shadow layers.
        // A failed read and no console both publish null in Service.
        function test_a_late_console_answer_gates_the_first_painted_frame_data() {
            const rows = [];
            for (const light of [false, true])
                for (const result of ["over-console", "none-or-failed"])
                    rows.push({ tag: (light ? "light-" : "dark-") + result, light: light, result: result });
            return rows;
        }

        function test_a_late_console_answer_gates_the_first_painted_frame(data) {
            if (data.light) compare(UnitTheme.override({ scheme: { mode: "light" } }), "ok");
            QsWindow.window = presentedHost;
            service.bubbleWanted = false;
            verify(renderedFrame(root));
            const empty = grabImage(root);
            service.heldKey = "1:a";
            service.sessionState = root.held("Delete draft.txt?\n/home/fixture/draft.txt", true);
            service.bubbleWanted = true;
            const overlay = named("overlay");
            verify(overlay !== undefined);
            for (let frame = 0; frame < 2; frame++) {
                verify(renderedFrame(root), "the window paints while the console answer is pending");
                verify(grabImage(root).equals(empty), "no bottom frame paints before the current hold's console answer");
                compare(service.acknowledged.length, 0, "an unplaced hold is not acknowledged");
            }
            const over = { output: "unit", x: 0, y: 0, width: root.width, height: root.height };
            service.consoleBox = data.result === "over-console" ? over : null;
            service.consoleKey = service.heldKey;
            verify(renderedFrame(root), "the first ready frame paints");
            verify(!grabImage(root).equals(empty), "the answered hold paints its prompt");
            const top = () => fuzzyCompare(overlay.y, root.look.layout.margin, 0.5);
            const bottom = () => fuzzyCompare(overlay.y + overlay.height, root.height - root.look.layout.margin, 0.5);
            if (data.result === "over-console") top(); else bottom();
            tryVerify(() => service.acknowledged.some(hold => hold.id === "a"), 2000, "the placed frame acknowledges the hold");

            // A later window event retains this hold's consoleKey, so its
            // read keeps the card painted and re-places it on completion.
            verify(renderedFrame(root));
            verify(!grabImage(root).equals(empty), "a same-hold read keeps the card painted");
            service.consoleBox = data.result === "over-console" ? null : over;
            verify(renderedFrame(root));
            verify(!grabImage(root).equals(empty), "a moved console does not hide the card");
            if (data.result === "over-console") bottom(); else top();

            service.heldKey = "1:b";
            const next = root.held("Delete notes.txt?\n/home/fixture/notes.txt", true);
            next.approval.id = "b";
            service.sessionState = next;
            verify(renderedFrame(root));
            verify(grabImage(root).equals(empty), "a new hold cannot use the previous hold's placement");
        }

        readonly property string caption: "The meeting moved to Thursday at three, and the room is the same as last week. I added it to your calendar and told Dana you will join a few minutes late."
        readonly property var open: ({ conversation: { kind: "active", purpose: "conversation" } })
        // The states the plates are judged in, each with the plates it shows.
        function poses() {
            const widest = "Move 3 files to Documents?\n~/Downloads/invoices-october/\ninvoice-1031.pdf, invoice-1017.pdf, invoice-1003.pdf";
            return [
                { tag: "words", caption: caption, state: root.session(Object.assign({ playback: { kind: "playing" }, voiceMute: { kind: "on" } }, open)),
                  plates: ["orbPlate", "textCard", "wordsCard"] },
                { tag: "one line of words under the pointer", caption: "Done.", hover: true,
                  state: root.session(Object.assign({ playback: { kind: "playing" }, voiceMute: { kind: "on" } }, open)),
                  plates: ["iconPill", "orbPlate", "textCard", "wordsCard"] },
                { tag: "listening under the pointer", hover: true, state: root.session(Object.assign({ capture: { kind: "open", gen: 1, op: 2, mode: "hold" } }, open)),
                  plates: ["iconPill", "orbPlate", "textCard"] },
                { tag: "a fault", state: root.session({ fault: { kind: "error", reason: "brain=stream-error", retry: 0 } }), plates: ["orbPlate", "textCard"] },
                { tag: "a held request under the pointer", hover: true, state: root.held(widest, true), plates: ["iconPill", "orbPlate", "textCard"] }
            ];
        }
        function inBothModes() {
            const rows = [];
            for (const light of [false, true])
                for (const pose of poses()) rows.push(Object.assign({}, pose, { tag: pose.tag + (light ? ", light" : ", dark"), light: light }));
            return rows;
        }
        function orb() { return all(bubble, []).find(item => item.phase !== undefined && item.capture !== undefined); }
        function put(data) {
            if (data.light) compare(UnitTheme.override({ scheme: { mode: "light" }, motion: { scale: 0 } }), "ok");
            QsWindow.window = presentedHost;
            service.values = data.caption ? { transcript: { role: "assistant", gen: 1, text: data.caption } } : {};
            service.sessionState = data.state;
            if (data.hover) {
                verify(renderedFrame(root), "the orb lays out");
                const centre = orb().mapToItem(root, orb().width / 2, orb().height / 2);
                mouseMove(root, centre.x, centre.y);
                tryCompare(bubble, "iconOpacity", 1, 500);
            }
            verify(renderedFrame(root), "the overlay lays out");
        }
        // The shown plates by name, each with its box in the root.
        function plates() {
            const found = {};
            for (const plate of all(bubble, []).filter(item => item.glassSurface === true && item.visible))
                found[plate.objectName] = { item: plate, box: plate.mapToItem(root, 0, 0, plate.width, plate.height) };
            return found;
        }
        function shadowOf(glass) { return glass.children[0]; }
        function bodyOf(glass) { return glass.children[1]; }
        function edgeOf(glass) { return glass.children[2]; }
        // A line's painted box in the root: a centred line draws its
        // glyphs inside its item's width.
        function painted(item) {
            const wide = item.contentWidth !== undefined ? item.contentWidth : Math.min(item.width, item.implicitWidth);
            return item.mapToItem(root, (item.width - wide) / 2, 0, wide, item.height);
        }
        function holds(plate, box, padX, padY, what) {
            verify(box.x >= plate.box.x + padX - 0.5 && box.x + box.width <= plate.box.x + plate.box.width - padX + 0.5
                && box.y >= plate.box.y + padY - 0.5 && box.y + box.height <= plate.box.y + plate.box.height - padY + 0.5,
                what + " at " + JSON.stringify([box.x, box.y, box.width, box.height]) + " stands inside the padding of its plate at "
                + JSON.stringify([plate.box.x, plate.box.y, plate.box.width, plate.box.height]));
        }

        function test_every_plate_draws_as_glass_clear_of_the_others_data() { return inBothModes(); }
        function test_every_plate_draws_as_glass_clear_of_the_others(data) {
            put(data);
            const shown = plates();
            compare(JSON.stringify(Object.keys(shown).sort()), JSON.stringify(data.plates));
            const overlay = named("overlay").mapToItem(root, 0, 0, named("overlay").width, named("overlay").height);
            for (const name in shown) {
                const plate = shown[name];
                verify(plate.item.drawn, name + " draws as glass");
                compare(plate.item.opacity, 1, name + " shows whole");
                verify(!shadowOf(plate.item).visible, name + " draws no drop shadow");
                verify(plate.box.x >= overlay.x && plate.box.x + plate.box.width <= overlay.x + overlay.width
                    && plate.box.y >= overlay.y && plate.box.y + plate.box.height <= overlay.y + overlay.height, name + " stands inside the overlay's box");
                for (const edge of [plate.box.x, plate.box.y, plate.box.width, plate.box.height]) compare(edge, Math.round(edge), name + " stands on whole pixels");
                for (const other in shown) {
                    if (other <= name) continue;
                    const b = shown[other].box;
                    const apart = Math.max(plate.box.x - (b.x + b.width), b.x - (plate.box.x + plate.box.width),
                        plate.box.y - (b.y + b.height), b.y - (plate.box.y + plate.box.height));
                    verify(apart >= root.look.plate.gap, name + " and " + other + " stand " + apart + " apart");
                }
            }
        }

        function test_each_plate_holds_its_content_inside_its_padding_data() { return inBothModes(); }
        function test_each_plate_holds_its_content_inside_its_padding(data) {
            put(data);
            const shown = plates();
            const card = root.look.plate.card;
            const lines = bubble.textItems.filter(item => bubble.drawn(item) && item.height > 0);
            verify(lines.length >= 1, "the overlay draws its lines");
            for (const item of lines) {
                const words = item.shownHeight !== undefined;
                // The words draw their shown lines at the bottom of their item.
                const box = words ? item.mapToItem(root, 0, item.height - item.shownHeight, item.width, item.shownHeight) : painted(item);
                holds(shown[words ? "wordsCard" : "textCard"], box, card.paddingX, card.paddingY, words ? "the words" : String(item.text).slice(0, 24));
            }
            for (const answer of all(bubble, []).filter(item => item.shimmer !== undefined && item.entry === undefined && bubble.drawn(item)))
                holds(shown.textCard, answer.mapToItem(root, 0, 0, answer.width, answer.height), card.paddingX, card.paddingY, "the answer " + answer.text);
            if (bubble.iconsShown)
                for (const icon of all(bubble, []).filter(item => item.entry !== undefined))
                    holds(shown.iconPill, icon.mapToItem(root, 0, 0, icon.width, icon.height), root.look.plate.pill.paddingX, root.look.plate.pill.paddingY, "the icon " + icon.entry.intent);
            // The disc shares the orb's centre and holds what the shader
            // draws: nothing past 1.3 of a state's radius, at its loudest.
            const canvas = orb().mapToItem(root, 0, 0, orb().width, orb().height);
            const disc = shown.orbPlate.box;
            compare([disc.x + disc.width / 2, disc.y + disc.height / 2], [canvas.x + canvas.width / 2, canvas.y + canvas.height / 2], "the disc shares the orb's centre");
            compare(disc.width, disc.height);
            verify(disc.width <= canvas.width, "the disc stands inside the canvas");
            for (const name in root.look.state) {
                const drawn = 1.3 * root.look.state[name].radius * (1 + root.look.state[name].driveRadius) * canvas.width / 2;
                verify(disc.width / 2 >= drawn, "the disc holds the " + name + " orb: " + disc.width / 2 + " against " + drawn);
            }
        }

        // What a line stands on is its plate's fill over the wallpaper: over
        // white under dark mode's plates and over black under light mode's,
        // the worst ground for each one's ink. Read a little inside each
        // plate's edge, clear of its content, its hairline and the orb.
        function test_a_plates_ground_is_its_fill_over_the_wallpaper_data() {
            const pose = poses()[1];
            return [{ tag: "dark plates over white", light: false, wall: "#ffffff", extreme: 255, orb: [2, 3, 8], card: [16, 16, 16], orbAlpha: 0.9, cardAlpha: 0.8 },
                    { tag: "light plates over black", light: true, wall: "#000000", extreme: 0, orb: [242, 242, 242], card: [242, 242, 242], orbAlpha: 0.9, cardAlpha: 0.85 }]
                .map(row => Object.assign({}, pose, row));
        }
        function test_a_plates_ground_is_its_fill_over_the_wallpaper(data) {
            put(data);
            ground.color = data.wall;
            verify(renderedFrame(root), "the plates draw over the wallpaper");
            const image = grabImage(root);
            const shown = plates();
            const mixed = (base, alpha) => base.map(channel => channel * alpha + data.extreme * (1 - alpha));
            const reads = (name, x, y, want) => {
                const got = [image.red(x, y), image.green(x, y), image.blue(x, y)];
                verify(got.every((channel, i) => Math.abs(channel - want[i]) <= 3), name + " reads " + got + " at " + [x, y] + ", its fill over the wallpaper is " + want);
            };
            for (const name of ["wordsCard", "textCard", "iconPill"]) {
                const box = shown[name].box;
                reads(name, Math.round(box.x + box.width / 2), Math.round(box.y + 4), mixed(data.card, data.cardAlpha));
            }
            const disc = shown.orbPlate.box;
            reads("orbPlate", Math.round(disc.x + disc.width / 2), Math.round(disc.y + 3), mixed(data.orb, data.orbAlpha));
        }

        // A plate's fill fading through the compositor's blur threshold
        // would gain or lose its blur mid-fade, so the capsule keeps its
        // opacity while its icons fade.
        function test_the_capsule_shows_whole_while_its_icons_fade() {
            put(poses()[2]);
            const icons = all(bubble, []).find(item => item.children.some(child => child.entry !== undefined));
            icons.opacity = 0.5;
            try {
                const capsule = plates().iconPill;
                verify(capsule !== undefined, "the capsule shows with its fading icons");
                compare(capsule.item.opacity, 1);
            } finally {
                // The bubble is shared: hand the row its binding back.
                icons.opacity = Qt.binding(() => bubble.iconOpacity);
            }
        }

        // The words' card is as tall as the lines shown and as wide as
        // the caption's column, whatever the words.
        function test_the_words_card_follows_the_lines_shown_data() {
            return [{ tag: "one line", caption: "Done.", lines: 1 }, { tag: "three lines", caption: caption, lines: 3 }];
        }
        function test_the_words_card_follows_the_lines_shown(data) {
            put(Object.assign({}, poses()[0], { caption: data.caption }));
            const words = bubble.textItems.find(item => item.shownHeight !== undefined);
            tryCompare(words, "shownLines", data.lines);
            const card = plates().wordsCard.item;
            const pad = root.look.plate.card;
            tryCompare(card, "height", data.lines * words.lineBox + 2 * pad.paddingY);
            compare(card.y + card.height, words.y + words.height + pad.paddingY, "the newest line stands at the card's bottom");
            compare(card.width, words.width + 2 * pad.paddingX);
        }

        // With the user's glass off each plate draws the look's own solid,
        // not the theme's surface: its base opaque inside its border.
        function test_without_glass_each_plate_draws_the_looks_own_solid() {
            put(poses()[1]);
            Theme.appearanceInput = JSON.stringify({ glass: "off" });
            const shown = plates();
            for (const name in shown) {
                const plate = shown[name].item;
                const values = name === "orbPlate" ? root.look.plate.orb : root.look.plate.card;
                verify(!plate.on, name + " draws no glass");
                compare(String(bodyOf(plate).color), String(Qt.color(values.base)), name + " draws its base opaque");
                compare(String(edgeOf(plate).border.color), String(Qt.color(values.border)), name + " draws its border");
                verify(!shadowOf(plate).visible, name + " draws no drop shadow");
            }
            verify(bodyOf(shown.orbPlate.item).radius >= shown.orbPlate.item.width / 2, "the disc stays round");
        }
    }
}
