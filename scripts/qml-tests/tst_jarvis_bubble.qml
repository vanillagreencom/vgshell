import QtQuick
import QtTest
import Quickshell
import qs.Commons
import qs.Ui
import qs.Unit
import "../../shell/plugins/vgs.jarvis"
import "../../shell/plugins/vgs.jarvis/Session.js" as Session
import "../../shell/plugins/vgs.jarvis/WidgetView.js" as View

// The Jarvis overlay's fault card: a fault's action that names a page
// draws the reference's words with no Markdown, and a click on them opens
// the page through `shell.surfaces.openPage` (design-system.md § Copy).
// The overlay beside the Console: its plates, text and pointer regions
// clear the Console's box, and the judgement that moves it reads the
// plates' own extent. The orb alone shows the state: no state name draws
// at rest, a name shows only after the pointer rests on the orb's middle,
// and the orb keeps one place in every state, so the open and the close
// each move it once, drawn whole, the close as one move down before the
// overlay hides.
// The Orb style setting reaches the orb at once. The service is a
// stand-in that hands the card a Session record.
Item {
    id: root
    width: 600
    height: 600

    property var opened: []
    property var intents: []

    QtObject { id: presentedHost; property bool presented: true; property bool visible: true }
    // Measures a word in a drawn label's font.
    TextMetrics { id: wordMetrics }

    QtObject {
        id: service
        property var sessionState: null
        property var microphoneMute: ({ kind: "ready", muted: false })
        property bool bubbleWanted: true
        property string focusedOutput: "SMOKE-1"
        property var consoleBox: null
        property var consoleKey: null
        property var heldKey: null
        property var effectiveKeys: null
        property var values: ({})
        property string orbStyle: "glass-bead"
        // A setting's change reaches the overlay as a new shell, as the
        // core hands one.
        property var shell: ({
            settings: { voiceProvider: "local", orbStyle: service.orbStyle },
            status: { values: service.values },
            surfaces: { openPage: (page, tab) => { root.opened = root.opened.concat([[page, tab]]); } }
        })
        function attachBubble(bubble) {}
        function detachBubble(bubble) {}
        function intent(value) { root.intents = root.intents.concat([value]); }
    }

    Bubble {
        id: bubble
        anchors.fill: parent
        screen: ({ name: "SMOKE-1" })
        service: service
    }

    UnitCase {
        name: "jarvisBubble"
        when: windowShown

        function init() {
            UnitTheme.reset();
            compare(UnitTheme.override({ motion: { scale: 0 } }), "ok");
            root.opened = [];
            root.intents = [];
            // A clicked link keeps the test window's focus; Qt warns when a
            // focused item stops taking Tab as its fault clears.
            bubble.forceActiveFocus();
            service.sessionState = null;
            service.microphoneMute = { kind: "ready", muted: false };
            service.consoleBox = null;
            service.values = {};
            service.orbStyle = "glass-bead";
            service.bubbleWanted = true;
            service.focusedOutput = "SMOKE-1";
            bubble.screen = { name: "SMOKE-1" };
            root.width = 600;
            root.height = 600;
            mouseMove(root, 1, 1);
        }
        function cleanup() { QsWindow.window = null; }

        function collect(node, test, out) {
            if (test(node)) out.push(node);
            for (const child of node.children) collect(child, test, out);
            return out;
        }
        function shownText() {
            return displayedTextItems(bubble).filter(n => n.opacity > 0 && displayedText(n) !== "").map(n => displayedText(n));
        }
        function links() {
            return displayedTextItems(bubble).filter(n => n instanceof LinkText);
        }
        function plates() { return collect(bubble, n => n.glassSurface === true && n.visible, []); }

        // ITEM's opacity as drawn: its own times each item's over it.
        function drawnOpacity(item) {
            let opacity = 1;
            for (let at = item; at !== null; at = at.parent) opacity *= at.opacity;
            return opacity;
        }
        function orbOf() { return collect(bubble, item => item.phase !== undefined && item.capture !== undefined, [])[0]; }
        // Every name a state ever drew under the orb or on its hover.
        readonly property var stateWords: ["Ready to talk", "Ready", "Listening", "Thinking", "Working", "Speaking", "Waiting for you", "Stopping"]
        function drawnStateWords() { return shownText().filter(text => stateWords.indexOf(text) !== -1); }
        function test_open_conversation_shows_the_forwarded_wait() {
            service.sessionState = conversation({});
            service.values = { forwardWait: true };
            tryVerify(() => shownText().includes("Waiting for Jarvis main"));
            service.values = { forwardWait: false };
            tryVerify(() => !shownText().includes("Waiting for Jarvis main"));
        }
        function conversation(over) {
            return Object.assign(JSON.parse(JSON.stringify(Session.initial())),
                { gate: { kind: "up" }, conversation: { kind: "active", purpose: "conversation" } }, over);
        }

        // Each state the orb alone shows, with the name a deliberate hover
        // over its middle shows, or none.
        function stateRows() {
            return [
                { tag: "ready", over: {}, name: "Ready" },
                { tag: "listening", over: { capture: { kind: "open", gen: 1, op: 2, mode: "hold" } }, name: "Listening" },
                { tag: "thinking", over: { turn: { kind: "thinking" } }, name: "Thinking" },
                { tag: "acting", over: { action: { kind: "running" } }, name: "Thinking" },
                { tag: "speaking", over: { playback: { kind: "playing" } }, name: "Speaking" },
                { tag: "stopping", over: { gate: { kind: "down" } }, name: "" }
            ];
        }

        // At rest no state name draws, no card stands under the orb and
        // the orb keeps the place it has while listening.
        function test_the_orb_alone_shows_the_state_data() { return stateRows(); }
        function test_the_orb_alone_shows_the_state(data) {
            listeningConversation();
            verify(renderedFrame(bubble));
            const orb = orbOf();
            const resting = orb.mapToItem(bubble, 0, 0);
            service.sessionState = conversation(data.over);
            verify(renderedFrame(bubble));
            compare(JSON.stringify(drawnStateWords()), "[]", "no state name draws at rest");
            compare(findChild(bubble, "textCard").visible, false, "no card stands under the orb");
            const at = orb.mapToItem(bubble, 0, 0);
            compare([at.x, at.y], [resting.x, resting.y], "the orb rests where it rests while listening");
        }

        // One rested hover over the orb's middle, a real wait of the look's
        // delay, names each state the overlay then shows, with no further
        // wait: the name stands centred across the orb, clear of the middle
        // square the pointer rests on, and moves nothing. The pointer may
        // move onto the shown name, where it lies over the icon row's
        // bridge, and keep it. The middle and the shown name are on the
        // orb, so the icon row shows with the name and stays past its hold.
        function test_a_rested_hover_names_each_state() {
            listeningConversation();
            verify(renderedFrame(bubble));
            const orb = orbOf();
            const overlay = findChild(bubble, "overlay");
            const resting = orb.mapToItem(bubble, 0, 0);
            const box = [overlay.x, overlay.y, overlay.width, overlay.height];
            const middle = findChild(bubble, "orbMiddle");
            const centre = middle.mapToItem(root, middle.width / 2, middle.height / 2);
            const plate = findChild(bubble, "stateName");
            const pill = findChild(bubble, "iconPill");
            const rowShown = () => pill.visible && pill.opacity === 1;
            mouseMove(root, centre.x, centre.y);
            tryVerify(() => plate.visible && plate.opacity === 1, bubble.look.name.delay + 1000, "the name shows on a rested hover");
            verify(rowShown(), "the icon row shows with the name");
            for (const row of stateRows()) {
                service.sessionState = conversation(row.over);
                verify(renderedFrame(bubble));
                compare(JSON.stringify(drawnStateWords()), JSON.stringify(row.name === "" ? [] : [row.name]), row.tag + " draws its name alone");
                compare(plate.visible, row.name !== "", row.tag + (row.name === "" ? " shows no name" : " shows its name"));
                if (row.name === "") continue;
                const plateCentre = plate.mapToItem(bubble, plate.width / 2, plate.height / 2);
                const orbCentre = orb.mapToItem(bubble, orb.width / 2, orb.height / 2);
                verify(Math.abs(plateCentre.x - orbCentre.x) <= 0.5, row.tag + "'s name stands centred across the orb");
                const plateTop = plate.mapToItem(bubble, 0, 0).y;
                const middleBottom = middle.mapToItem(bubble, 0, middle.height).y;
                verify(plateTop >= middleBottom - 0.5, row.tag + "'s name stands below the middle, clear of the pointer");
                const radius = bubble.look.state[bubble.orbPhase].radius * orb.width / 2;
                const half = plate.height / 2;
                // The capsule's farthest outline point, a semicircle on
                // either end of its centre line, stays inside the disc.
                const reach = Math.hypot(plate.width / 2 - half, plateCentre.y - orbCentre.y) + half;
                verify(reach <= radius, row.tag + "'s whole capsule stays inside the disc");
                compare([overlay.x, overlay.y, overlay.width, overlay.height], box, row.tag + "'s name takes no room");
                const after = orb.mapToItem(bubble, 0, 0);
                compare([after.x, after.y], [resting.x, resting.y], row.tag + "'s name moves nothing");
            }
            service.sessionState = conversation({ capture: { kind: "open", gen: 1, op: 2, mode: "hold" } });
            verify(renderedFrame(bubble));
            verify(plate.visible, "the name shows again");
            // Where the capsule lies over the bridge, laid under it.
            const bridge = findChild(bubble, "iconBridge");
            const plateBox = plate.mapToItem(root, 0, 0, plate.width, plate.height);
            const bridgeBox = bridge.mapToItem(root, 0, 0, bridge.width, bridge.height);
            const left = Math.max(plateBox.x, bridgeBox.x);
            const right = Math.min(plateBox.x + plateBox.width, bridgeBox.x + bridgeBox.width);
            const top = Math.max(plateBox.y, bridgeBox.y);
            const bottom = Math.min(plateBox.y + plateBox.height, bridgeBox.y + bridgeBox.height);
            verify(bridge.visible && right - left >= 2 && bottom - top >= 2, "the capsule lies over the bridge: " + JSON.stringify([left, top, right, bottom]));
            const end = Qt.point((left + right) / 2, (top + bottom) / 2);
            mouseMove(root, end.x, end.y);
            verify(renderedFrame(bubble));
            verify(plate.visible, "the name stays while the pointer is on it");
            wait(bubble.look.icon.hold + 100);
            verify(rowShown(), "the icon row stays past its hold while the pointer is on the name");
            mouseMove(root, 1, 1);
            tryCompare(plate, "visible", false, 100, "the name goes as the pointer leaves, with no fade at motion scale 0");
            compare(JSON.stringify(drawnStateWords()), "[]");
        }

        // After the open's move the layer's input region over the orb is
        // where the orb draws. The layer computes each region from the
        // item's box as its window maps it, again whenever the item or one
        // of its parents moves or resizes (OverlaySurface's regions); the
        // test takes that reading on the same signals and on each change
        // of the overlay's input items.
        function test_the_input_region_follows_the_open() {
            QsWindow.window = presentedHost;
            listeningConversation();
            verify(renderedFrame(bubble));
            const hit = findChild(bubble, "orbHit");
            service.bubbleWanted = false;
            tryCompare(bubble, "shown", false, 100);
            compare(UnitTheme.override({ motion: { scale: 1 } }), "ok");
            let region = null;
            const read = () => { region = hit.mapToItem(bubble, 0, 0, hit.width, hit.height); };
            const lineage = [];
            for (let item = hit; item !== null; item = item.parent) lineage.push(item);
            const signals = [];
            for (const item of lineage)
                for (const name of ["xChanged", "yChanged", "widthChanged", "heightChanged"]) signals.push(item[name]);
            signals.push(bubble.inputItemsChanged);
            for (const changed of signals) changed.connect(read);
            try {
                service.bubbleWanted = true;
                read();
                tryCompare(bubble, "rest", 1, 2000, "the open's move ends");
                verify(renderedFrame(bubble));
                verify(bubble.inputItems.indexOf(hit) !== -1, "the orb takes the pointer");
                const drawn = hit.mapToItem(bubble, 0, 0, hit.width, hit.height);
                compare(JSON.stringify([region.x, region.y, region.width, region.height]), JSON.stringify([drawn.x, drawn.y, drawn.width, drawn.height]),
                    "the region stands where the orb's hit square draws");
            } finally {
                for (const changed of signals) changed.disconnect(read);
            }
        }

        // A pass over the orb away from its middle shows no name, however
        // long the pointer stays.
        function test_a_pass_over_the_orb_shows_no_name() {
            listeningConversation();
            verify(renderedFrame(bubble));
            const hit = findChild(bubble, "orbHit");
            const middle = findChild(bubble, "orbMiddle");
            verify(middle.width < hit.width, "the middle lies inside the hit square");
            const edge = hit.mapToItem(root, (hit.width - middle.width) / 4, hit.height / 2);
            mouseMove(root, edge.x, edge.y);
            tryCompare(bubble, "iconOpacity", 1, 1000, "the pointer is on the orb");
            wait(bubble.look.name.delay + 100);
            compare(findChild(bubble, "stateName").visible, false);
        }

        // The open and the close each move the overlay once, one way, with
        // no state name on the way, even from a name a rested hover shows at
        // its full fade. The close keeps it drawn while it moves down,
        // presenting nothing and taking no pointer, and then hides it. Both
        // draw the orb whole on every frame, so no window shows through
        // its disc.
        function test_the_open_and_the_close_move_the_overlay_once() {
            QsWindow.window = presentedHost;
            listeningConversation();
            compare(UnitTheme.override({ motion: { scale: 1 } }), "ok");
            verify(renderedFrame(bubble));
            const middle = findChild(bubble, "orbMiddle");
            const centre = middle.mapToItem(root, middle.width / 2, middle.height / 2);
            const plate = findChild(bubble, "stateName");
            mouseMove(root, centre.x, centre.y);
            tryVerify(() => plate.visible && plate.opacity === 1, bubble.look.name.delay + 1000, "the name shows before the close");
            const overlay = findChild(bubble, "overlay");
            const restY = overlay.y;
            // How far under its rest the overlay stands.
            const lowered = () => overlay.y - restY;
            verify(bubble.presented, "the open overlay presents");
            for (const opening of [false, true]) {
                service.bubbleWanted = opening;
                compare(bubble.presented, opening, "only a wanted overlay presents");
                if (!opening) compare(bubble.inputItems.length, 0, "a closing overlay takes no pointer");
                let last = lowered();
                let frames = 0;
                do {
                    verify(bubble.visible, "the overlay draws through its move");
                    verify(opening ? lowered() <= last : lowered() >= last, "one move, one way: " + last + " to " + lowered());
                    compare(drawnOpacity(orbOf()), 1, (opening ? "the open" : "the close") + " draws the orb whole");
                    compare(JSON.stringify(drawnStateWords()), "[]", "no state name on the way");
                    last = lowered();
                    frames++;
                    verify(renderedFrame(bubble));
                } while (opening ? bubble.rest < 1 : bubble.rest > 0);
                verify(frames > 2, "the move takes frames: " + frames);
                fuzzyCompare(lowered(), opening ? 0 : bubble.look.orb.rise, 0.001);
                compare(bubble.visible, opening, opening ? "the open overlay rests" : "the closed overlay hides");
                compare(bubble.shown, opening, "the layer maps only a wanted or closing overlay");
            }
        }

        // A changed Orb style reaches the orb with the shell it comes in.
        function test_the_orb_style_setting_applies_at_once() {
            listeningConversation();
            const orb = orbOf();
            const effect = orb.data.find(item => item.fragmentShader !== undefined);
            for (const style of ["blades", "glass-bead"]) {
                service.orbStyle = style;
                compare(orb.style, style);
                verify(String(effect.fragmentShader).endsWith("/shaders/" + style + ".frag.qsb"), "the orb draws " + style + ": " + effect.fragmentShader);
            }
        }

        function listeningConversation() {
            service.sessionState = Object.assign(JSON.parse(JSON.stringify(Session.initial())), {
                gate: { kind: "up" }, conversation: { kind: "active", purpose: "conversation" },
                capture: { kind: "open", gen: 1, op: 2, mode: "hold" }
            });
        }

        function test_listening_uses_the_orb_and_bar_without_a_card() {
            listeningConversation();
            verify(renderedFrame(bubble));
            const orb = collect(bubble, item => item.phase !== undefined && item.capture !== undefined, [])[0];
            compare(orb.phase, "listening");
            verify(orb.visible && orb.active);
            const bar = View.view({ detail: { phase: bubble.phase, state: service.sessionState } }, null);
            compare(bar.state, "listening");
            compare(bar.icon, "vgs-letter-j");
            compare(bar.stateDot, "success");
            compare(findChild(bubble, "textCard").visible, false);
            compare(shownText().length, 0);
        }

        function test_the_control_pill_fades_as_one_piece() {
            listeningConversation();
            verify(renderedFrame(bubble));
            const pill = findChild(bubble, "iconPill");
            const bridge = findChild(bubble, "iconBridge");
            const icons = collect(bubble, item => item.children.some(child => child.entry !== undefined), [])[0];
            const hit = findChild(bubble, "orbHit");
            tryCompare(bubble, "iconOpacity", 0);
            compare(UnitTheme.override({ motion: { scale: 1 } }), "ok");
            const at = hit.mapToItem(root, hit.width / 2, hit.height / 2);
            for (const entering of [true, false]) {
                mouseMove(root, entering ? at.x : 1, entering ? at.y : 1);
                tryVerify(() => bubble.iconOpacity > 0 && bubble.iconOpacity < 1,
                    2000, "the real hover and hold path reaches a partial fade");
                // Sample consecutive animation frames, including the endpoint.
                let frames = 0;
                do {
                    compare(pill.opacity, icons.opacity);
                    compare(bridge.opacity, icons.opacity);
                    verify(pill.visible && bridge.visible && icons.visible);
                    frames++;
                    verify(renderedFrame(bubble));
                } while (bubble.iconOpacity > 0 && bubble.iconOpacity < 1);
                verify(frames > 0);
                tryCompare(bubble, "iconOpacity", entering ? 1 : 0);
                compare(pill.opacity, icons.opacity);
                compare(bridge.opacity, icons.opacity);
            }
        }

        function test_fault_placement_tracks_console_without_a_hold_data() {
            return [
                { tag: "posed-close", width: 1920, height: 1052, output: "SMOKE-1", side: "either",
                    box: { x: 448, y: 132, width: 1024, height: 824 }, clear: null },
                { tag: "default-above", width: 1920, height: 1052, output: "SMOKE-1", side: "either",
                    box: { x: 660, y: 188, width: 600, height: 648 },
                    clear: { output: "SMOKE-1", x: 0, y: -300, width: 1920, height: 300 } },
                { tag: "more-room-right-other-screen", width: 1200, height: 600, output: "SMOKE-3", side: "right", icons: true,
                    box: { x: 100, y: 100, width: 600, height: 500 },
                    clear: { output: "SMOKE-1", x: 100, y: 100, width: 600, height: 500 } },
                { tag: "more-room-left-move-beside", width: 1200, height: 600, output: "SMOKE-1", side: "left",
                    box: { x: 500, y: 100, width: 600, height: 500 },
                    clear: { output: "SMOKE-1", x: 1200, y: 0, width: 600, height: 600 } },
                // Use a production audio restart title to exercise reflow
                // without making the other placements depend on its length.
                { tag: "wrapped-side-clears-baseline-band", width: 900, height: 600, output: "SMOKE-1", side: "left", wraps: true, icons: true, restartCategory: "audio",
                    box: { x: 300, y: 0, width: 600, height: 600 },
                    clear: { output: "SMOKE-1", x: 300, y: 0, width: 600, height: 280 } },
                { tag: "orb-fits-a-narrow-side", width: 600, height: 600, output: "SMOKE-1", side: "left", wraps: true, icons: true,
                    box: { x: 120, y: 0, width: 450, height: 600 }, clear: null },
                { tag: "orb-and-capsule-fit-a-narrow-right-side", width: 600, height: 600, output: "SMOKE-1", side: "right", wraps: true, icons: true,
                    box: { x: 30, y: 0, width: 450, height: 600 }, clear: null },
                // Service.readConsoleBox can report these resized mapped
                // windows. The old capsule reservation consumed all 50 px
                // at the boundary, and all 44 px on the tighter side.
                { tag: "active-at-reservation-left", width: 600, height: 600, output: "SMOKE-1", side: "left", tight: true, icons: true,
                    box: { x: 86, y: 0, width: 500, height: 600 }, clear: null },
                { tag: "active-at-reservation-right", width: 600, height: 600, output: "SMOKE-1", side: "right", tight: true, icons: true,
                    box: { x: 14, y: 0, width: 500, height: 600 }, clear: null },
                { tag: "active-below-reservation-left", width: 600, height: 600, output: "SMOKE-1", side: "left", tight: true, icons: true,
                    box: { x: 80, y: 0, width: 500, height: 600 }, clear: null },
                { tag: "active-below-reservation-right", width: 600, height: 600, output: "SMOKE-1", side: "right", tight: true, icons: true,
                    box: { x: 20, y: 0, width: 500, height: 600 }, clear: null }
            ];
        }
        function test_fault_placement_tracks_console_without_a_hold(data) {
            root.width = data.width;
            root.height = data.height;
            service.focusedOutput = data.output;
            bubble.screen = { name: data.output };
            service.sessionState = Object.assign(JSON.parse(JSON.stringify(Session.initial())),
                { gate: { kind: "up" }, conversation: { kind: "active", purpose: "conversation" },
                    restart: data.tight ? { kind: "none" } : { kind: "restarted",
                        category: data.restartCategory !== undefined ? data.restartCategory : "reply-cut" } });
            compare(bubble.hold, null);
            verify(bubble.shown, "the active conversation keeps the orb shown without a held request");
            const overlay = findChild(bubble, "overlay");
            verify(overlay !== null);
            verify(renderedFrame(bubble));
            fuzzyCompare(overlay.y + overlay.height, root.height - bubble.look.layout.margin, 0.5);
            fuzzyCompare(overlay.x + overlay.width / 2, root.width / 2, 0.5);

            const box = Object.assign({ output: data.output }, data.box);
            service.consoleBox = box;
            verify(renderedFrame(bubble));
            const orb = collect(overlay, item => item.phase !== undefined && item.capture !== undefined, [])[0];
            const hit = findChild(bubble, "orbHit");
            verify(orb !== undefined && orb.visible && orb.width > 0 && orb.height > 0,
                "the orb draws before a pointer can reveal the capsule");
            verify(hit !== null && hit.visible && hit.width > 0 && hit.height > 0,
                "the active orb has a pointer entry before the capsule shows");
            if (data.icons) {
                mouseMove(root, root.width - 1, 1);
                tryCompare(bubble, "iconOpacity", 0);
                const restingOrb = Qt.rect(orb.x, orb.y, orb.width, orb.height);
                const at = hit.mapToItem(root, hit.width / 2, hit.height / 2);
                verify(at.x > 0 && at.x < root.width && at.y > 0 && at.y < root.height,
                    "the hover entry lies on the rendered output: " + JSON.stringify({
                        at: [at.x, at.y], overlay: [overlay.x, overlay.y, overlay.width, overlay.height],
                        capsuleBelow: overlay.capsuleBelow, belowExtent: overlay.belowExtent,
                        rowRoom: overlay.rowRoom, layerRoom: overlay.layerRoom }));
                mouseMove(root, at.x, at.y);
                tryCompare(bubble, "iconOpacity", 1);
                compare(Qt.rect(orb.x, orb.y, orb.width, orb.height), restingOrb,
                    "revealing the capsule keeps the orb under the pointer");
            }
            // A second frame must keep the same answer after the fitted
            // width reflows the text and the overlay no longer intersects.
            for (let frame = 0; frame < 2; frame++) {
                verify(renderedFrame(bubble));
                verify(bubble.overConsole, "the decision keeps judging the centred bottom band");
                verify(overlay.width > 0 && overlay.height > 0, "clearance cannot pass by collapsing the overlay");
                const left = overlay.x + overlay.width <= box.x;
                const right = overlay.x >= box.x + box.width;
                verify(left || right, "the whole overlay stands beside Console");
                if (data.side !== "either") compare(left ? "left" : "right", data.side, "use the side with more measured room");
                const drawn = plates();
                const required = (data.tight ? [] : ["textCard"]).concat(data.icons ? ["iconPill"] : []);
                for (const name of required)
                    verify(drawn.some(plate => plate.objectName === name), "the side draws its required " + name);
                for (const plate of drawn) {
                    const rect = plate.mapToItem(bubble, 0, 0, plate.width, plate.height);
                    verify(rect.width > 0 && rect.height > 0, "clearance cannot pass by collapsing " + plate.objectName);
                    verify(rect.x >= 0 && rect.x + rect.width <= root.width, plate.objectName + " stays on this output");
                    verify(rect.y >= overlay.y && rect.y + rect.height <= overlay.y + overlay.height + 0.5,
                        plate.objectName + " stays whole inside the clipped overlay");
                    verify(left ? rect.x + rect.width <= box.x : rect.x >= box.x + box.width, plate.objectName + " also clears Console");
                }
                fuzzyCompare(overlay.y + overlay.height, root.height - bubble.look.layout.margin, 0.5,
                    "a non-held overlay keeps its bottom edge, not the held prompt's top edge");
                for (const item of bubble.textItems.filter(item => bubble.drawn(item) && item.height > 0)) {
                    const rect = item.mapToItem(bubble, 0, 0, item.width, item.height);
                    verify(rect.x >= overlay.x && rect.x + rect.width <= overlay.x + overlay.width + 0.5,
                        "drawn text fits the side's box");
                    verify(item.height >= item.implicitHeight, "the whole wrapped line remains laid out");
                    if (!(item instanceof Text)) continue;
                    // The card's text keeps inside its band, and the card
                    // gives up its full padding before a word breaks.
                    const card = findChild(bubble, "textCard");
                    const gap = (card.width - item.contentWidth) / 2;
                    verify(gap >= bubble.look.plate.lens.bezel - 0.5, "the text keeps inside the card's band: " + gap);
                    wordMetrics.font = item.font;
                    const broken = (item.plain !== undefined ? item.plain : item.text).split(/\s+/)
                        .filter(word => { wordMetrics.text = word; return word !== "" && wordMetrics.advanceWidth > item.width + 0.5; });
                    verify(broken.length === 0 || gap < bubble.look.plate.card.paddingX,
                        "the card gives up its padding before a word breaks: " + JSON.stringify({ broken: broken, gap: gap, column: item.width }));
                }
                verify(orb.x >= 0 && orb.x + orb.width <= overlay.width, "the orb canvas fits even a narrow side");
                if (data.icons) {
                    const capsule = findChild(bubble, "iconPill");
                    const inset = Math.round((1 - bubble.look.orb.reach) * orb.width / 2);
                    verify(capsule.x >= orb.x + orb.width - inset + bubble.look.plate.gap - 0.5
                        || capsule.y >= orb.y + orb.height - inset + bubble.look.plate.gap - 0.5,
                        "the capsule leaves the plates' gap on a clear edge of the orb");
                    verify(capsule.x >= 0 && capsule.x + capsule.width <= overlay.width,
                        "the whole capsule fits the same side as the orb");
                    for (const plate of drawn.filter(plate => plate !== capsule))
                        verify(plate.x + plate.width <= capsule.x || plate.x >= capsule.x + capsule.width
                            || plate.y + plate.height <= capsule.y || plate.y >= capsule.y + capsule.height,
                            plate.objectName + " stays clear of the capsule");
                    const bridge = findChild(bubble, "iconBridge");
                    verify(bridge.x < hit.x + hit.width && bridge.x + bridge.width > hit.x
                        && bridge.y < hit.y + hit.height && bridge.y + bridge.height > hit.y,
                        "the bridge overlaps the fitted hit square");
                    verify(bridge.x < capsule.x + capsule.width && bridge.x + bridge.width > capsule.x
                        && bridge.y < capsule.y + capsule.height && bridge.y + bridge.height > capsule.y,
                        "the bridge overlaps the capsule");
                }
                for (const item of bubble.inputItems) {
                    const rect = item.mapToItem(bubble, 0, 0, item.width, item.height);
                    verify(left ? rect.x + rect.width <= box.x : rect.x >= box.x + box.width,
                        "the side's pointer regions leave Console reachable");
                }
            }
            if (data.icons) {
                const bridge = findChild(bubble, "iconBridge");
                const at = bridge.mapToItem(root, bridge.width / 2, bridge.height / 2);
                mouseMove(root, at.x, at.y);
                // The real hold timer must not hide the controls while
                // the pointer rests on the connected route to them.
                wait(bubble.look.icon.hold + 1);
                compare(bubble.iconOpacity, 1);
                const controls = collect(overlay, item => item.entry !== undefined, []);
                for (const intent of ["voice-mute", "microphone-mute", "stop"]) {
                    const control = controls.find(item => item.entry.intent === intent);
                    verify(control !== undefined && control.visible && control.enabled);
                    const point = control.mapToItem(root, control.width / 2, control.height / 2);
                    verify(point.x > 0 && point.x < root.width && point.y > 0 && point.y < root.height,
                        intent + " stays reachable on the rendered output");
                    mouseMove(root, point.x, point.y);
                    compare(bubble.iconOpacity, 1);
                    mouseClick(root, point.x, point.y);
                }
                compare(root.intents, ["voice-mute", "microphone-mute", "stop"],
                    "the revealed controls deliver their real pointer actions");
            }
            if (data.wraps) {
                const title = bubble.textItems.find(item => item.text === bubble.stateText);
                verify(title !== undefined && title.lineCount > 1, "the narrow side wraps the actual fault title");
            }

            service.consoleBox = data.clear;
            verify(renderedFrame(bubble));
            compare(bubble.overConsole, false);
            fuzzyCompare(overlay.y + overlay.height, root.height - bubble.look.layout.margin, 0.5,
                "closing or clearing the Console returns the fault orb to the bottom");
            fuzzyCompare(overlay.x + overlay.width / 2, root.width / 2, 0.5,
                "closing or clearing Console restores centred placement");
        }

        // Beside Console at x 87 on a 600 px layer the overlay is 51 px and
        // a side row would leave its orb 1 px. Once the layer is one pixel
        // shorter than the stacked group, only that row would still fit:
        // the overlay claims a capture only on an orb as wide as one of its
        // icon buttons.
        function test_a_capture_shows_only_on_a_usable_orb() {
            QsWindow.window = presentedHost;
            service.sessionState = Object.assign(JSON.parse(JSON.stringify(Session.initial())),
                { gate: { kind: "up" }, conversation: { kind: "active", purpose: "conversation" } });
            service.consoleBox = { output: "SMOKE-1", x: 87, y: 0, width: 513, height: 600 };
            verify(renderedFrame(bubble));
            const overlay = findChild(bubble, "overlay");
            const orb = collect(overlay, item => item.phase !== undefined && item.capture !== undefined, [])[0];
            const hit = findChild(bubble, "orbHit");
            const button = collect(overlay, item => item.entry !== undefined, [])[0];
            const usable = () => JSON.stringify({ presented: bubble.capturePresented, orb: orb.width, hit: hit.width, button: button.width });
            verify(bubble.besideConsole && bubble.capturePresented && orb.width >= button.width && hit.width >= button.width,
                "the whole layer presents the group with a usable orb: " + usable());
            root.height = overlay.height + bubble.look.layout.margin - 1;
            verify(renderedFrame(bubble));
            verify(bubble.besideConsole, "the shorter layer keeps the overlay beside Console");
            verify(!bubble.capturePresented || orb.width >= button.width && hit.width >= button.width,
                "a capture shows only on an orb as wide as its icon button: " + usable());
        }

        // The judgement reads the box the overlay draws in at the bottom
        // centre, from the words' card, or from what the orb draws when no
        // words show, down to the text card: a Console that ends just above
        // its top leaves the overlay there, and one that reaches a pixel
        // into it moves the overlay.
        function test_the_console_judgement_reads_the_plates_extent_data() {
            const open = { gate: { kind: "up" }, conversation: { kind: "active", purpose: "conversation" } };
            return [
                { tag: "the orb at rest", state: open },
                { tag: "a fault", state: Object.assign({ fault: { kind: "error", reason: "jarvis-test=unknown", category: "other" } }, open) },
                { tag: "words over the orb", state: Object.assign({ playback: { kind: "playing" }, voiceMute: { kind: "on" } }, open),
                  caption: "The meeting moved to Thursday at three, and the room is the same as last week. I added it to your calendar and told Dana you will join a few minutes late." }
            ];
        }
        function test_the_console_judgement_reads_the_plates_extent(data) {
            root.width = 1200;
            if (data.caption) service.values = { transcript: { role: "assistant", gen: 0, text: data.caption } };
            service.sessionState = Object.assign(JSON.parse(JSON.stringify(Session.initial())), data.state);
            verify(renderedFrame(bubble));
            const overlay = findChild(bubble, "overlay");
            const orb = collect(overlay, item => item.phase !== undefined && item.capture !== undefined, [])[0];
            verify(orb !== undefined, "the overlay draws its orb");
            // The orb draws nothing in the outer share of its canvas past
            // the look's reach, a whole number of pixels.
            const inset = Math.round((1 - bubble.look.orb.reach) * orb.width / 2);
            if (data.caption) verify(plates().some(plate => plate.objectName === "wordsCard"), "the words draw on their card");
            const top = data.caption ? Math.min(...plates().map(plate => plate.mapToItem(bubble, 0, 0).y)) : orb.mapToItem(bubble, 0, inset).y;
            fuzzyCompare(top, overlay.y, 0.5, "what the overlay draws starts at its box's top");
            const over = bottom => ({ output: "SMOKE-1", x: 0, y: 0, width: root.width, height: bottom });
            service.consoleBox = over(top - 1);
            verify(renderedFrame(bubble));
            compare(bubble.overConsole, false, "a Console that ends above the plates leaves them");
            service.consoleBox = over(top + 1);
            verify(renderedFrame(bubble));
            compare(bubble.overConsole, true, "a Console a pixel into the plates moves them");
        }

        function test_digital_silence_is_a_reading_with_a_microphone_link() {
            const state = Object.assign(JSON.parse(JSON.stringify(Session.initial())), {
                gate: { kind: "up" }, conversation: { kind: "active", purpose: "conversation" },
                capture: { kind: "open", gen: 1, op: 2, mode: "conversation" },
                sound: { kind: "silent", device: "fixture microphone" }
            });
            service.sessionState = state;
            verify(renderedFrame(bubble));
            compare(bubble.fault, null, "digital silence does not draw a fault");
            const line = links().find(item => item.plain.indexOf("fixture microphone") !== -1);
            verify(line !== undefined && line.linked, "the silent source has a useful setting link");
            verify(bubble.inputItems.indexOf(line) !== -1, "the setting link takes the pointer");
            const span = line.underlined[0];
            verify(span !== undefined, "the setting link lays out");
            mouseClick(line, (span.left + span.right) / 2, (span.line + 0.5) * line.linePitch);
            compare(JSON.stringify(root.opened), '[["vgs.jarvis","Settings/microphone"]]');
            root.forceActiveFocus();
            verify(root.activeFocus, "the test releases the link before removing its text");
            service.microphoneMute = { kind: "ready", muted: true };
            compare(bubble.stateText, "Microphone muted");
            compare(line.visible, false, "system mute replaces the silent-source reading");
            compare(bubble.active, true, "the conversation remains open");
        }

        // Faults whose action names a page, each with the reference's words
        // and the page and tab it names.
        function test_a_fault_action_draws_its_page_reference_as_a_link_data() {
            return [
                { tag: "stopped", engine: "chained", reason: "jarvis-test=unknown", page: "vgs.jarvis", tab: "Settings" },
                { tag: "default device", engine: "dictation", reason: "device-lost target=null from=default microphones=0[]", page: "vgs.sound", tab: "" }
            ];
        }
        function test_a_fault_action_draws_its_page_reference_as_a_link(data) {
            service.sessionState = Object.assign(JSON.parse(JSON.stringify(Session.initial())),
                { gate: { kind: "up" }, engine: { kind: data.engine }, fault: { kind: "error", reason: data.reason, category: "other" } });
            compare(bubble.phase, "error");
            const drawn = shownText();
            verify(drawn.length > 0, "the card draws text");
            for (const text of drawn)
                verify(!/\]\((page|file):/.test(text), "no drawn text shows a reference's raw form: " + text);
            const link = links().find(n => n.reference.page === data.page && n.reference.tab === data.tab);
            verify(link !== undefined, "a link carries the fault's Settings route: " + JSON.stringify(drawn));
            verify(link.words.length > 0);
            verify(bubble.inputItems.indexOf(link) !== -1, "the passive layer takes clicks on the link");
            // The layout gives the link its width at the next polish.
            verify(renderedFrame(bubble));
            verify(link.underlined.length > 0, "the link's words are laid out");
            const span = link.underlined[0];
            mouseClick(link, (span.left + span.right) / 2, (span.line + 0.5) * link.linePitch);
            compare(JSON.stringify(root.opened), JSON.stringify([[data.page, data.tab]]));
        }
    }
}
