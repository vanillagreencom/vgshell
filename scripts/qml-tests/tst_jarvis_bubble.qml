import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit
import "../../shell/plugins/vgs.jarvis"
import "../../shell/plugins/vgs.jarvis/Session.js" as Session

// The Jarvis overlay's fault card: a fault's action that names a page
// draws the reference's words with no Markdown, and a click on them opens
// the page through `shell.surfaces.openPage` (design-system.md § Copy).
// The overlay beside the Console: its plates, text and pointer regions
// clear the Console's box, and the judgement that moves it reads the
// plates' own extent. The service is a stand-in that hands the card a
// Session record.
Item {
    id: root
    width: 600
    height: 600

    property var opened: []

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
        property var shell: ({
            settings: { voiceProvider: "local" },
            status: { values: service.values },
            surfaces: { openPage: (page, tab) => { root.opened = root.opened.concat([[page, tab]]); } }
        })
        function attachBubble(bubble) {}
        function detachBubble(bubble) {}
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
            // A clicked link keeps the test window's focus; Qt warns when a
            // focused item stops taking Tab as its fault clears.
            bubble.forceActiveFocus();
            service.sessionState = null;
            service.microphoneMute = { kind: "ready", muted: false };
            service.consoleBox = null;
            service.values = {};
            service.focusedOutput = "SMOKE-1";
            bubble.screen = { name: "SMOKE-1" };
            root.width = 600;
            root.height = 600;
            mouseMove(root, 1, 1);
        }

        function collect(node, test, out) {
            if (test(node)) out.push(node);
            for (const child of node.children) collect(child, test, out);
            return out;
        }
        function shownText() {
            return collect(bubble, n => n instanceof Text && n.visible && n.opacity > 0 && n.text !== "", []).map(n => n.text);
        }
        function links() {
            return collect(bubble, n => n.focusPreview !== undefined && n.linkColor !== undefined && n.visible, []);
        }
        function plates() { return collect(bubble, n => n.glassSurface === true && n.visible, []); }

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
                { tag: "wrapped-side-clears-baseline-band", width: 900, height: 600, output: "SMOKE-1", side: "left", wraps: true,
                    box: { x: 300, y: 0, width: 600, height: 600 },
                    clear: { output: "SMOKE-1", x: 300, y: 0, width: 600, height: 280 } },
                { tag: "orb-fits-a-narrow-side", width: 600, height: 600, output: "SMOKE-1", side: "left", wraps: true,
                    box: { x: 120, y: 0, width: 450, height: 600 }, clear: null }
            ];
        }
        function test_fault_placement_tracks_console_without_a_hold(data) {
            root.width = data.width;
            root.height = data.height;
            service.focusedOutput = data.output;
            bubble.screen = { name: data.output };
            service.sessionState = Object.assign(JSON.parse(JSON.stringify(Session.initial())),
                { gate: { kind: "up" }, conversation: { kind: "active", purpose: "conversation" },
                    restart: { kind: "restarted", category: "reply-cut" } },
                data.icons ? { fault: { kind: "error", reason: "jarvis-test=unknown" } } : {});
            compare(bubble.hold, null);
            verify(bubble.shown, "the fault keeps the orb shown without a held request");
            const overlay = findChild(bubble, "overlay");
            verify(overlay !== null);
            verify(renderedFrame(bubble));
            fuzzyCompare(overlay.y + overlay.height, root.height - bubble.look.layout.margin, 0.5);
            fuzzyCompare(overlay.x + overlay.width / 2, root.width / 2, 0.5);

            const box = Object.assign({ output: data.output }, data.box);
            service.consoleBox = box;
            verify(renderedFrame(bubble));
            if (data.icons) {
                const hit = findChild(bubble, "orbHit");
                verify(hit !== null);
                const at = hit.mapToItem(root, hit.width / 2, hit.height / 2);
                mouseMove(root, at.x, at.y);
                tryCompare(bubble, "iconOpacity", 1);
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
                verify(drawn.length >= (data.icons ? 2 : 1), "the side draws the card and the shown capsule: " + drawn.map(plate => plate.objectName));
                for (const plate of drawn) {
                    const rect = plate.mapToItem(bubble, 0, 0, plate.width, plate.height);
                    verify(rect.width > 0 && rect.height > 0, "clearance cannot pass by collapsing " + plate.objectName);
                    verify(rect.x >= 0 && rect.x + rect.width <= root.width, plate.objectName + " stays on this output");
                    verify(left ? rect.x + rect.width <= box.x : rect.x >= box.x + box.width, plate.objectName + " also clears Console");
                }
                fuzzyCompare(overlay.y + overlay.height, root.height - bubble.look.layout.margin, 0.5,
                    "a non-held overlay keeps its bottom edge, not the held prompt's top edge");
                for (const item of bubble.textItems.filter(item => bubble.drawn(item) && item.height > 0)) {
                    const rect = item.mapToItem(bubble, 0, 0, item.width, item.height);
                    verify(rect.x >= overlay.x && rect.x + rect.width <= overlay.x + overlay.width + 0.5,
                        "drawn text fits the side's box");
                    verify(item.height >= item.implicitHeight, "the whole wrapped line remains laid out");
                }
                const orb = collect(overlay, item => item.phase !== undefined && item.capture !== undefined, [])[0];
                verify(orb !== undefined && orb.width > 0);
                verify(orb.x >= 0 && orb.x + orb.width <= overlay.width, "the orb canvas fits even a narrow side");
                for (const item of bubble.inputItems) {
                    const rect = item.mapToItem(bubble, 0, 0, item.width, item.height);
                    verify(left ? rect.x + rect.width <= box.x : rect.x >= box.x + box.width,
                        "the side's pointer regions leave Console reachable");
                }
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

        // The judgement reads the box the overlay draws in at the bottom
        // centre, from the words' card, or from what the orb draws when no
        // words show, down to the text card: a Console that ends just above
        // its top leaves the overlay there, and one that reaches a pixel
        // into it moves the overlay.
        function test_the_console_judgement_reads_the_plates_extent_data() {
            const open = { gate: { kind: "up" }, conversation: { kind: "active", purpose: "conversation" } };
            return [
                { tag: "a state line", state: open },
                { tag: "a fault", state: Object.assign({ fault: { kind: "error", reason: "jarvis-test=unknown" } }, open) },
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
                { tag: "stopped", engine: "chained", reason: "jarvis-test=unknown", words: "Settings > Jarvis", page: "vgs.jarvis", tab: "Settings" },
                { tag: "default device", engine: "dictation", reason: "device-lost target=null from=default microphones=0[]", words: "System > Sound", page: "vgs.sound", tab: "" }
            ];
        }
        function test_a_fault_action_draws_its_page_reference_as_a_link(data) {
            service.sessionState = Object.assign(JSON.parse(JSON.stringify(Session.initial())),
                { gate: { kind: "up" }, engine: { kind: data.engine }, fault: { kind: "error", reason: data.reason } });
            compare(bubble.phase, "error");
            const drawn = shownText();
            verify(drawn.length > 0, "the card draws text");
            for (const text of drawn)
                verify(!/\]\((page|file):/.test(text), "no drawn text shows a reference's raw form: " + text);
            const link = links().find(n => n.plain.indexOf(data.words) !== -1);
            verify(link !== undefined, "a link draws the action's words: " + JSON.stringify(drawn));
            compare(link.words, data.words);
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
