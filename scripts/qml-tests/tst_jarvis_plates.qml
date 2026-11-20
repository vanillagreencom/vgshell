import QtQuick
import QtTest
import Quickshell
import qs.Commons
import qs.Ui
import qs.Unit
import "../../shell/plugins/vgs.jarvis"
import "../../shell/plugins/vgs.jarvis/Appearance.js" as Appearance
import "../../shell/plugins/vgs.jarvis/Session.js" as Session

// Jarvis's overlay stands on plates of glass in the lens form, with
// nothing behind the orb. In each state and both modes every plate draws
// the lens pass with no drop shadow, whole and clear of the others and of
// what the orb draws by the look's gap, and holds its content inside its
// padding, which is no less than its band; the words' card follows the
// lines shown; without
// glass each plate draws the look's own solid. The drawn bubble is read
// over white and over black under scripts/qml-unit.sh's software OpenGL,
// which draws the shaders: a plate's body is its fill over the wallpaper,
// the ground scripts/check-theme-contrast.js judges every ink against, at
// the look's one tint, above the compositor's blur thresholds; its band is
// under them; and the same material draws in both modes. Each orb style's
// motion is continuous across its clocks' wraps, read from drawn frames,
// with a planted wrap the reading must refuse. Each style's disc draws
// whole inside its edge, read over white and over black, so no window
// shows through it. The window is
// transparent, as the shell's layers are, since glass draws only there
// (GlassSurface.drawn). A held request paints no frame before its console
// answer.
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
        property bool callPlaced: true
        property var consoleBox: null
        property string consoleKey: ""
        property string placementKey: ""
        property var effectiveKeys: ({ stop: "SUPER+CTRL+X", confirm: "SUPER+CTRL+Y" })
        property var values: ({})
        property var shell: ({ settings: { voiceProvider: "local", orbStyle: "glass-bead" }, status: { values: service.values }, surfaces: { openPage: () => "ok" } })
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

    // One orb over a mid grey, where a style's light and its shadow both
    // show, shown for the wrap test alone. Its canvas is half the look's,
    // which keeps the software renderer's frames quick; at motion scale 0
    // its clocks stay where the test sets them.
    Item {
        id: wrapStage
        visible: false
        z: 1
        width: wrapOrb.width
        height: wrapOrb.height
        Rectangle { id: wrapGround; anchors.fill: parent; color: "#808080" }
        ParticleOrb { id: wrapOrb; width: 128; height: 128; look: root.look; style: "glass-bead"; phase: "listening" }
    }

    function session(over) {
        const s = Object.assign(JSON.parse(JSON.stringify(Session.initial())), { gen: 1, gate: { kind: "up" } });
        for (const key in over) s[key] = over[key];
        return s;
    }
    function held(text, physical, tool = "files.move") {
        return session({ conversation: { kind: "active", purpose: "conversation" },
            approval: { kind: "held", id: "a", gen: 1, op: 2, digest: "d", purpose: "action", tool: tool, physical: physical, text: text } });
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
            service.callPlaced = true;
            service.consoleBox = null;
            service.consoleKey = "";
            service.placementKey = "";
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
        // Only a successful reading with no visible console places it at bottom centre.
        function test_a_late_console_answer_gates_the_first_painted_frame_data() {
            const rows = [];
            for (const light of [false, true])
                for (const result of ["over-console", "none"])
                    rows.push({ tag: (light ? "light-" : "dark-") + result, light: light, result: result });
            return rows;
        }

        function test_a_late_console_answer_gates_the_first_painted_frame(data) {
            if (data.light) compare(UnitTheme.override({ scheme: { mode: "light" }, motion: { scale: 0 } }), "ok");
            QsWindow.window = presentedHost;
            service.bubbleWanted = false;
            verify(renderedFrame(root));
            const empty = grabImage(root);
            service.placementKey = "1:a";
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
            service.consoleKey = service.placementKey;
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

            service.placementKey = "1:b";
            const next = root.held("Delete notes.txt?\n/home/fixture/notes.txt", true);
            next.approval.id = "b";
            service.sessionState = next;
            verify(renderedFrame(root));
            verify(grabImage(root).equals(empty), "a new hold cannot use the previous hold's placement");
        }

        function test_each_swapped_frame_keeps_its_placement_data() {
            return [
                { tag: "preview", path: ["hidden", "side", "hidden"] },
                { tag: "Talk", path: ["hidden", "side", "top", "side", "centre", "side", "hidden"] },
                { tag: "minimized held call", path: ["hidden", "side", "top", "hidden"] },
                { tag: "open and close Chat while thinking", path: ["hidden", "centre", "side", "centre", "hidden"] }
            ];
        }
        function test_each_swapped_frame_keeps_its_placement(data) {
            const preview = data.tag === "preview", heldExit = data.tag === "minimized held call";
            const thinking = data.tag === "open and close Chat while thinking";
            QsWindow.window = presentedHost;
            service.bubbleWanted = false;
            service.callPlaced = false;
            verify(renderedFrame(root));
            const empty = grabImage(root);
            compare(UnitTheme.override({ motion: { scale: 1 } }), "ok");
            const call = root.session({ conversation: { kind: "active", purpose: preview ? "preview" : "conversation" },
                orbSize: { kind: heldExit ? "small" : "normal" },
                turn: { kind: thinking ? "thinking" : "none" }, playback: { kind: preview ? "playing" : "idle" } });
            const side = { output: "unit", x: root.width / 2, y: 0, width: root.width / 2, height: root.height };
            const win = root.Window.window, disc = orb();
            let polished, synchronized;
            const swapped = [];
            // The unit window stays mapped. Pair each polish with its sync
            // and swap so assertions include intermediate animation frames.
            const polish = () => {
                const pos = disc.mapToItem(root, disc.width / 2, disc.height / 2);
                const location = pos.x < root.width / 2 - 1 ? "side" : pos.y < root.height / 2 ? "top" : "centre";
                polished = !bubble.visible ? "hidden" : heldExit && disc.width !== root.look.orb.smallSize ? "wrong-size" : location;
            };
            const sync = () => { synchronized = polished; };
            const swap = () => { if (synchronized !== undefined) swapped.push(synchronized); };
            const observed = () => swapped.filter((place, index) => index === 0 || place !== swapped[index - 1]);
            win.afterAnimating.connect(polish);
            win.afterSynchronizing.connect(sync);
            win.frameSwapped.connect(swap);
            try {
                service.sessionState = call;
                service.bubbleWanted = true;
                verify(renderedFrame(root));
                verify(grabImage(root).equals(empty), "the opening waits for a readable console");
                service.consoleBox = thinking ? null : side;
                service.callPlaced = true;
                tryCompare(bubble, "rest", 1);
                verify(renderedFrame(root));
                verify(!grabImage(root).equals(empty), "the orb has painted at its first resolved placement");
                if (thinking) {
                    service.consoleBox = side;
                    verify(renderedFrame(root), "Chat opens in front of the thinking orb");
                    service.consoleBox = null;
                    verify(renderedFrame(root), "Chat closes during the same turn");
                } else if (!preview) {
                    const card = root.held("Forward this request?", false, "fleet.forward");
                    card.orbSize = call.orbSize;
                    service.placementKey = "1:a";
                    service.sessionState = card;
                    verify(renderedFrame(root), "the prior orb remains while the card's read is pending");
                    compare(service.acknowledged.length, 0);
                    service.consoleKey = service.placementKey;
                    verify(renderedFrame(root));
                    if (heldExit) tryVerify(() => service.acknowledged.length > 0);
                    else {
                        service.sessionState = call;
                        verify(renderedFrame(root));
                        service.consoleBox = null;
                        verify(renderedFrame(root));
                        service.consoleBox = side;
                        verify(renderedFrame(root));
                    }
                }
                // End the call and clear its live inputs in the same event.
                service.bubbleWanted = false;
                service.callPlaced = false;
                service.sessionState = null;
                service.consoleBox = null;
                verify(renderedFrame(root));
                tryCompare(bubble, "shown", false);
                verify(renderedFrame(root));
                verify(grabImage(root).equals(empty), "the exit finishes off screen");
                compare(JSON.stringify(observed()), JSON.stringify(data.path),
                    "each presented position from the first draw through the exit");
            } finally {
                win.afterAnimating.disconnect(polish);
                win.afterSynchronizing.disconnect(sync);
                win.frameSwapped.disconnect(swap);
            }
        }

        readonly property string caption: "The meeting moved to Thursday at three, and the room is the same as last week. I added it to your calendar and told Dana you will join a few minutes late."
        readonly property var open: ({ conversation: { kind: "active", purpose: "conversation" } })
        // The states the plates are judged in, each with the plates it shows.
        function poses() {
            const widest = "Move 3 files to Documents?\n~/Downloads/invoices-october/\ninvoice-1031.pdf, invoice-1017.pdf, invoice-1003.pdf";
            return [
                { tag: "words", caption: caption, state: root.session(Object.assign({ playback: { kind: "playing" }, voiceMute: { kind: "on" } }, open)),
                  plates: ["wordsCard"] },
                { tag: "one line of words under the pointer", caption: "Done.", hover: true,
                  state: root.session(Object.assign({ playback: { kind: "playing" }, voiceMute: { kind: "on" } }, open)),
                  plates: ["iconPill", "wordsCard"] },
                { tag: "listening under the pointer", hover: true, state: root.session(Object.assign({ capture: { kind: "open", gen: 1, op: 2, mode: "hold" } }, open)),
                  plates: ["iconPill"] },
                { tag: "a fault", state: root.session({ fault: { kind: "error", reason: "brain=stream-error", category: "other" } }), plates: ["textCard"] },
                { tag: "a held request under the pointer", hover: true, state: root.held(widest, true), plates: ["iconPill", "textCard"] }
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
                // On the orb but off its middle, where a resting pointer
                // would show the state's name over the orb.
                const away = (root.look.layout.hit + root.look.name.middle) / 4;
                const point = orb().mapToItem(root, orb().width / 2 + away, orb().height / 2);
                mouseMove(root, point.x, point.y);
                tryCompare(bubble, "iconOpacity", 1, 500);
            } else {
                // The icon row stays the look's hold after the pointer
                // left the orb in an earlier pose.
                tryCompare(bubble, "iconOpacity", 0, root.look.icon.hold + 500);
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
        // The lens pass a plate builds: the item of its fourth child.
        function lensOf(glass) { return glass.children[3].item; }
        // How far apart two boxes stand; negative where they overlap.
        function apart(a, b) {
            return Math.max(a.x - (b.x + b.width), b.x - (a.x + a.width), a.y - (b.y + b.height), b.y - (a.y + a.height));
        }
        // The box that holds what the orb draws: its canvas less the outer
        // share past the look's reach, a whole number of pixels.
        function orbBox() {
            const canvas = orb().mapToItem(root, 0, 0, orb().width, orb().height);
            const inset = Math.round((1 - root.look.orb.reach) * canvas.width / 2);
            return { x: canvas.x + inset, y: canvas.y + inset, width: canvas.width - 2 * inset, height: canvas.height - 2 * inset };
        }
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
                verify(plate.item.lensed && lensOf(plate.item).visible, name + " draws the lens pass");
                compare(plate.item.opacity, 1, name + " shows whole");
                verify(!shadowOf(plate.item).visible, name + " draws no drop shadow");
                verify(apart(plate.box, orbBox()) >= root.look.plate.gap, name + " stands " + apart(plate.box, orbBox()) + " from what the orb draws");
                verify(plate.box.x >= overlay.x && plate.box.x + plate.box.width <= overlay.x + overlay.width
                    && plate.box.y >= overlay.y && plate.box.y + plate.box.height <= overlay.y + overlay.height, name + " stands inside the overlay's box");
                for (const edge of [plate.box.x, plate.box.y, plate.box.width, plate.box.height]) compare(edge, Math.round(edge), name + " stands on whole pixels");
                for (const other in shown) {
                    if (other <= name) continue;
                    const gap = apart(plate.box, shown[other].box);
                    verify(gap >= root.look.plate.gap, name + " and " + other + " stand " + gap + " apart");
                }
            }
        }

        function test_each_plate_holds_its_content_inside_its_padding_data() { return inBothModes(); }
        function test_each_plate_holds_its_content_inside_its_padding(data) {
            put(data);
            const shown = plates();
            const card = root.look.plate.card;
            const lines = bubble.textItems.filter(item => bubble.drawn(item) && item.height > 0);
            if (data.plates.indexOf("textCard") !== -1 || data.plates.indexOf("wordsCard") !== -1)
                verify(lines.length >= 1, "the overlay draws its lines");
            else
                compare(lines.length, 0, "the listening orb needs no text card");
            for (const item of lines) {
                const words = item.shownHeight !== undefined;
                // The words draw their shown lines at the bottom of their item.
                const box = words ? item.mapToItem(root, 0, item.height - item.shownHeight, item.width, item.shownHeight) : painted(item);
                holds(shown[words ? "wordsCard" : "textCard"], box, card.paddingX, card.paddingY, words ? "the words" : String(item.text).slice(0, 24));
            }
            for (const answer of all(bubble, []).filter(item => item.quiet !== undefined && item.form !== undefined && bubble.drawn(item)))
                holds(shown.textCard, answer.mapToItem(root, 0, 0, answer.width, answer.height), card.paddingX, card.paddingY, "the answer " + answer.text);
            if (bubble.iconsShown)
                for (const icon of all(bubble, []).filter(item => item.entry !== undefined && item.visible))
                    holds(shown.iconPill, icon.mapToItem(root, 0, 0, icon.width, icon.height), root.look.plate.pill.paddingX, root.look.plate.pill.paddingY, "the icon " + icon.entry.intent);
            // Inside its band a plate draws its fill alone, so no content
            // stands on the band.
            for (const name in shown) {
                const pad = name === "iconPill" ? root.look.plate.pill : card;
                verify(shown[name].item.bezel > 0 && Math.min(pad.paddingX, pad.paddingY) >= shown[name].item.bezel,
                    name + " pads its content past its band of " + shown[name].item.bezel);
            }
            // Nothing stands behind the orb. The box the plates keep clear
            // holds every state's outermost strand, 1.095 of the state's
            // radius at rest (shaders/glass-bead.frag `rs`), at its
            // loudest.
            const drawn = orbBox();
            const canvas = orb().width;
            for (const name in root.look.state) {
                const strand = 1.095 * root.look.state[name].radius * (1 + root.look.state[name].driveRadius) * canvas / 2;
                verify(drawn.width / 2 >= strand, "the plates stand clear of the " + name + " orb: " + drawn.width / 2 + " against " + strand);
            }
        }

        function test_one_material_draws_in_both_modes_data() {
            const rows = [];
            for (const glass of [true, false])
                for (const ground of ["#ffffff", "#000000", "#2068d0"])
                    rows.push({ tag: (glass ? "glass " : "solid ") + ground, glass: glass, ground: ground });
            return rows;
        }
        function test_one_material_draws_in_both_modes(data) {
            if (!data.glass) Theme.appearanceInput = JSON.stringify({ glass: "off" });
            ground.color = data.ground;
            const pose = poses()[1];
            put(pose);
            const values = JSON.stringify(root.look);
            const dark = grabImage(root);
            put(Object.assign({}, pose, { light: true }));
            compare(JSON.stringify(root.look), values, "the mode selects no other material or ink value");
            verify(grabImage(root).equals(dark), "the plates and their ink draw the same over " + data.ground + " in both modes");
        }

        // The look's one tint sets every plate's fill in both modes, and
        // the ground an ink is judged on is that fill over the wallpaper
        // nearest the ink.
        function test_one_value_sets_the_glass_tint() {
            const tint = root.look.plate.tint;
            const mixed = (fill, wall) => [fill.r, fill.g, fill.b].map(channel => Math.round(255 * (channel * fill.a + wall * (1 - fill.a))));
            const channels = color => [color.r, color.g, color.b].map(channel => Math.round(255 * channel));
            for (const light of [false, true]) {
                if (light) compare(UnitTheme.override({ scheme: { mode: "light" }, motion: { scale: 0 } }), "ok");
                const mode = light ? "light" : "dark";
                compare(root.look.plate.tint, tint, mode + " mode keeps the one tint");
                const fill = Qt.color(root.look.plate.card.fill);
                verify(Math.abs(fill.a - tint) <= 1 / 255, mode + " mode's fill draws at the tint: " + fill.a + " against " + tint);
                const near = channels(Qt.color(root.look.plate.card.nearInk));
                const want = mixed(fill, 1);
                verify(near.every((channel, i) => Math.abs(channel - want[i]) <= 1), mode + " mode judges its inks on " + near + ", its fill over the wallpaper is " + want);
            }
        }

        // What a line stands on is its plate's body: the fill over the
        // wallpaper at the look's tint, read over white and over black in
        // each mode. The same two readings give a pixel's alpha, which
        // decides the compositor's blur: the body's is the tint, above the
        // core rule's threshold, 0.7 (shell/Core/HyprlandLayer.js), and
        // the band's is the tint less the look's clarity, under the
        // manifest rule's, 0.6. Each is read on the plate's left wall at
        // its middle: the body clear of the band and the content, the
        // band on its second pixel, past the glint on the rim and short of
        // the line where it meets the body, and the outer line a pixel
        // outside.
        function test_the_body_takes_the_tint_and_the_band_stays_under_the_blur_data() {
            const rows = [];
            for (const light of [false, true])
                for (const pose of [poses()[1], poses()[3]])
                    rows.push(Object.assign({}, pose, { tag: (light ? "light " : "dark ") + pose.tag, light: light }));
            return rows;
        }
        function test_the_body_takes_the_tint_and_the_band_stays_under_the_blur(data) {
            put(data);
            const shown = plates();
            const tint = root.look.plate.tint;
            const fill = Qt.color(root.look.plate.card.fill);
            const over = wall => {
                ground.color = wall;
                verify(renderedFrame(root), "the plates draw over " + wall);
                return grabImage(root);
            };
            const white = over("#ffffff");
            const black = over("#000000");
            const alpha = (x, y) => 1 - (white.red(x, y) - black.red(x, y)) / 255;
            const reads = (name, image, wall, x, y) => {
                const got = [image.red(x, y), image.green(x, y), image.blue(x, y)];
                const want = [fill.r, fill.g, fill.b].map(channel => 255 * (channel * fill.a + wall * (1 - fill.a)));
                verify(got.every((channel, i) => Math.abs(channel - want[i]) <= 4), name + "'s body reads " + got + " at " + [x, y] + ", its fill over the wallpaper is " + want);
            };
            for (const name of data.plates) {
                verify(shown[name] !== undefined, name + " draws in this pose");
                const box = shown[name].box;
                const y = Math.round(box.y + box.height / 2);
                const inBody = box.x + (name === "iconPill" ? 6 : 8);
                reads(name, white, 1, inBody, y);
                reads(name, black, 0, inBody, y);
                const body = alpha(inBody, y);
                verify(Math.abs(body - tint) <= 0.02, name + "'s body draws at alpha " + body + ", the tint is " + tint);
                verify(body > 0.7, name + "'s body at alpha " + body + " stays above the blur thresholds");
                const band = alpha(box.x + 1, y);
                verify(band <= 0.6, name + "'s band at alpha " + band + " stays under the blur threshold");
                verify(Math.abs(band - tint * (1 - root.look.plate.lens.clarity)) <= 0.04, name + "'s band draws at alpha " + band + ", the tint less the clarity");
            }
        }

        // The wrap orb's frame with its clocks at CLOCKS.
        function frameAt(clocks) {
            const held = wrapOrb.data.find(item => item.reset !== undefined && item.flow !== undefined);
            for (const name in clocks) held[name] = clocks[name];
            verify(renderedFrame(wrapStage), "the wrap orb draws");
            return grabImage(wrapStage);
        }
        // The mean difference of two frames over every second pixel, in
        // 8-bit steps a channel.
        function difference(a, b) {
            let sum = 0;
            let count = 0;
            for (let y = 0; y < wrapOrb.height; y += 2)
                for (let x = 0; x < wrapOrb.width; x += 2) {
                    sum += Math.abs(a.red(x, y) - b.red(x, y)) + Math.abs(a.green(x, y) - b.green(x, y)) + Math.abs(a.blue(x, y) - b.blue(x, y));
                    count += 3;
                }
            return sum / count;
        }
        // Each clock's step between two frames: a little motion that every
        // style draws, under any wrap's jump.
        readonly property var steps: ({ time: 0.02, flow: 0.004, swirl: 0.004 })
        // Whether the frames across the clocks' wraps at TURNS differ no
        // more than the two frames before them, the same step apart: every
        // clock steps from three steps short of its turn to one short, and
        // then past its turn to one step after it.
        function crossing(turns) {
            const at = offset => {
                const clocks = {};
                for (const name in steps) clocks[name] = ((turns[name] + offset * steps[name]) % turns[name] + turns[name]) % turns[name];
                return frameAt(clocks);
            };
            const early = at(-3);
            const late = at(-1);
            const past = at(1);
            const before = difference(early, late);
            const across = difference(late, past);
            return { continuous: across <= 2 * before + 0.25, before: before, across: across };
        }
        // One row per option of the Orb style setting, the one list of
        // styles. A wrap's jump comes from the multiple of a clock a
        // shader reads, which no state changes; acting turns on every part
        // that reads a clock, its sparks' twinkle included.
        function test_each_style_moves_continuously_across_the_wraps_data() {
            const request = new XMLHttpRequest();
            request.open("GET", Qt.resolvedUrl("../../shell/plugins/vgs.jarvis/manifest.json"), false);
            request.send();
            return JSON.parse(request.responseText).schema.orbStyle.options.map(option => ({ tag: option.value, style: option.value }));
        }
        function test_each_style_moves_continuously_across_the_wraps(data) {
            verify(root.look.state.acting.sparks > 0, "acting twinkles");
            wrapStage.visible = true;
            try {
                wrapOrb.style = data.style;
                wrapOrb.phase = "acting";
                const read = crossing({ time: wrapOrb.twinkleTurn, flow: wrapOrb.flowTurn, swirl: wrapOrb.swirlTurn });
                verify(read.continuous, "the frames across the wraps differ by " + read.across + ", the frames before them by " + read.before);
            } finally {
                wrapStage.visible = false;
            }
        }

        // Each style draws its disc whole inside its edge: over white and
        // over black the core reads the same, so its alpha is 1 and no
        // window shows through, which over a half-light window would read
        // as two halves. The core read is the middle fifth of the canvas
        // across, inside every style's disc at the radius of any state.
        function test_each_style_draws_its_disc_whole_data() { return test_each_style_moves_continuously_across_the_wraps_data(); }
        function test_each_style_draws_its_disc_whole(data) {
            wrapStage.visible = true;
            try {
                wrapOrb.style = data.style;
                wrapOrb.phase = "idle";
                const over = wall => {
                    wrapGround.color = wall;
                    verify(renderedFrame(wrapStage), data.style + " draws over " + wall);
                    return grabImage(wrapStage);
                };
                const white = over("#ffffff");
                const black = over("#000000");
                const centre = wrapOrb.width / 2;
                const reach = wrapOrb.width / 10;
                let least = 1;
                let at = null;
                for (let y = Math.ceil(centre - reach); y <= centre + reach; y += 2)
                    for (let x = Math.ceil(centre - reach); x <= centre + reach; x += 2) {
                        if ((x - centre) * (x - centre) + (y - centre) * (y - centre) > reach * reach) continue;
                        const alpha = 1 - Math.max(white.red(x, y) - black.red(x, y), white.green(x, y) - black.green(x, y), white.blue(x, y) - black.blue(x, y)) / 255;
                        if (alpha < least) { least = alpha; at = [x, y]; }
                    }
                verify(least >= 1 - 1 / 255, data.style + "'s disc lets the window through at " + at + ": alpha " + least);
            } finally {
                wrapGround.color = "#808080";
                wrapStage.visible = false;
            }
        }

        // The planted control: Blades read across a swirl wrap at one turn,
        // where its petals, its flare and its rim light, turning at shares
        // of the swirl, jump.
        function test_a_wrap_where_the_motion_jumps_is_refused() {
            wrapStage.visible = true;
            try {
                wrapOrb.style = "blades";
                wrapOrb.phase = "thinking";
                const read = crossing({ time: wrapOrb.twinkleTurn, flow: wrapOrb.flowTurn, swirl: 2 * Math.PI });
                verify(!read.continuous, "the jump reads as one: the frames across the wraps differ by " + read.across + ", the frames before them by " + read.before);
            } finally {
                wrapStage.visible = false;
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
                const values = root.look.plate.card;
                verify(!plate.on, name + " draws no glass");
                verify(!lensOf(plate).visible, name + " draws no lens pass");
                compare(String(bodyOf(plate).color), String(Qt.color(values.base)), name + " draws its base opaque");
                compare(String(edgeOf(plate).border.color), String(Qt.color(values.border)), name + " draws its border");
                verify(!shadowOf(plate).visible, name + " draws no drop shadow");
            }
            verify(bodyOf(shown.iconPill.item).radius >= shown.iconPill.item.width / 2, "the capsule stays round");
        }
    }
}
