import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit
import "../../shell/plugins/vgs.jarvis"
import "../../shell/plugins/vgs.jarvis/Appearance.js" as Appearance

// Jarvis's overlay and the pointer: the passive layer's input region holds
// the orb's hit square only while the overlay is active, the icon row
// shows only while the pointer rests on the orb in an active state and
// stays on the way to an icon, a right click opens the Jarvis menu, whose
// entries send their keys' intents or open the Keys section, and the orb
// draws at the look's 255 px canvas. The region on a real layer and the
// menu in a real popup are scripts/smoke/rows/jarvis-bubble.sh's.
Item {
    id: root
    width: 640
    height: 720

    readonly property var look: Theme.appearance(Appearance.TOKENS, Appearance.LIGHT)
    property var intents: []
    property var pages: []

    QtObject {
        id: service
        property var sessionState: null
        property bool bubbleWanted: true
        property string focusedOutput: "unit"
        property var consoleBox: null
        property string consoleKey: ""
        property string heldKey: ""
        property var effectiveKeys: ({ stop: "SUPER+ALT+PERIOD", confirm: "SUPER+ALT+Y" })
        property var shell: ({ status: { values: {} }, surfaces: { openPage: (page, tab) => { root.pages = root.pages.concat([page + "/" + tab]); return "ok"; } } })
        function attachBubble(item) {}
        function detachBubble(item) {}
        function intent(name) { root.intents = root.intents.concat([name]); }
        function shownApproval(item, hold) {}
        function cancelApproval(hold) {}
        function confirmApproval(hold, how) {}
    }

    Bubble { id: bubble; width: root.width; height: root.height; screen: ({ name: "unit" }); service: service }

    function session(over) {
        const s = { gen: 1, check: { kind: "none" }, gate: { kind: "up" }, fault: { kind: "none" }, approval: { kind: "none" },
            action: { kind: "none" }, playback: { kind: "none" }, speech: { kind: "none" }, turn: { kind: "none" },
            capture: { kind: "closed" }, mute: { kind: "off" }, voiceMute: { kind: "off" }, engine: { kind: "chained" } };
        for (const key in over) s[key] = over[key];
        return s;
    }
    readonly property var listening: session({ capture: { kind: "open", mode: "hold" } })

    UnitCase {
        name: "jarvis-overlay"
        when: windowShown

        function all(item, out) {
            for (const child of item.children) {
                out.push(child);
                all(child, out);
            }
            return out;
        }
        function named(name) {
            const found = all(bubble, []).filter(item => item.objectName === name);
            verify(found.length === 1, "one item named " + name);
            return found[0];
        }
        function iconRow() {
            const found = all(bubble, []).filter(item => item.children.some(child => child.intentName === "voice-mute"));
            verify(found.length === 1, "one icon row");
            return found[0];
        }
        function icon(intent) { return iconRow().children.find(child => child.intentName === intent); }
        function orb() {
            const found = all(bubble, []).filter(item => item.phase !== undefined && item.capture !== undefined && item.playback !== undefined);
            verify(found.length === 1, "one orb");
            return found[0];
        }
        function menu() {
            const found = all(bubble, []).filter(item => item.triggerCurrent !== undefined && item.items !== undefined);
            return found.length === 1 ? found[0] : null;
        }
        function holdsOrb() { return bubble.inputItems.some(item => item.objectName === "orbHit"); }
        function orbCentre() { const o = orb(); return o.mapToItem(root, o.width / 2, o.height / 2); }
        function away() { mouseMove(root, root.width - 1, 0); }
        // The overlay in STATE once its lines are laid out, which Qt does
        // on the next frame.
        function put(state) {
            service.sessionState = state;
            verify(renderedFrame(root), "the window draws the overlay");
        }

        function init() {
            UnitTheme.reset();
            root.intents = [];
            root.pages = [];
            service.sessionState = null;
            away();
            const open = menu();
            if (open !== null) open.close();
            tryCompare(bubble, "iconOpacity", 0, 2000);
        }

        // The idle and the other still states take no pointer on the orb;
        // every active state takes it on the hit square over the orb's
        // centre.
        function test_only_an_active_overlay_takes_the_orb_data() {
            return [
                { tag: "waiting for the word", state: root.session({ capture: { kind: "open", mode: "armed" } }), takes: false },
                { tag: "getting ready", state: root.session({}), takes: false },
                { tag: "stopping", state: root.session({ gate: { kind: "down" } }), takes: false },
                { tag: "muted while listening", state: root.session({ capture: { kind: "open", mode: "hold" }, mute: { kind: "on" } }), takes: false },
                { tag: "listening", state: root.listening, takes: true },
                { tag: "thinking", state: root.session({ turn: { kind: "thinking" } }), takes: true },
                { tag: "acting", state: root.session({ action: { kind: "running" } }), takes: true },
                { tag: "speaking", state: root.session({ playback: { kind: "playing" } }), takes: true },
                { tag: "a fault", state: root.session({ fault: { kind: "error", reason: "device-lost" } }), takes: true }
            ];
        }

        function test_only_an_active_overlay_takes_the_orb(data) {
            put(data.state);
            compare(holdsOrb(), data.takes);
            if (!data.takes) {
                verify(bubble.inputItems.every(item => item.objectName !== "iconBridge"), "no icon row's input");
                return;
            }
            const hit = named("orbHit");
            compare(hit.width, root.look.layout.hit);
            compare(hit.height, root.look.layout.hit);
            const centre = orbCentre();
            const box = hit.mapToItem(root, 0, 0);
            compare(box.x + hit.width / 2, centre.x);
            compare(box.y + hit.height / 2, centre.y);
        }

        // The orb draws at the look's canvas, 15% under the first build's
        // 300 px, and the icon row stands at its ring.
        function test_the_orb_draws_at_255_px() {
            put(root.listening);
            compare(orb().width, 255);
            compare(orb().height, 255);
            const centre = orbCentre();
            const row = iconRow().mapToItem(root, 0, 0);
            compare(row.x, centre.x + root.look.state.armed.radius * 255 / 2);
        }

        // The icon row shows while the pointer rests on the orb in an
        // active state, and goes the look's hold after the pointer leaves;
        // at motion scale 0 it shows and goes with no fade. Waiting for
        // the word, a pointer on the orb shows nothing.
        function test_the_icons_show_only_under_the_pointer_data() {
            return [{ tag: "listening", state: root.listening, shows: true },
                    { tag: "waiting for the word", state: root.session({ capture: { kind: "open", mode: "armed" } }), shows: false }];
        }

        function test_the_icons_show_only_under_the_pointer(data) {
            compare(UnitTheme.override({ motion: { scale: 0 } }), "ok");
            put(data.state);
            compare(iconRow().visible, false);
            const centre = orbCentre();
            mouseMove(root, centre.x, centre.y);
            if (!data.shows) {
                wait(100);
                compare(iconRow().visible, false);
                compare(bubble.iconOpacity, 0);
                return;
            }
            tryCompare(bubble, "iconOpacity", 1, 100, "no fade at motion scale 0");
            compare(iconRow().visible, true);
            verify(bubble.inputItems.some(item => item.objectName === "iconBridge"), "the icon row takes input while it shows");
            away();
            compare(bubble.iconOpacity, 1, "the hold keeps the row");
            tryCompare(bubble, "iconOpacity", 0, root.look.icon.hold + 200);
            compare(iconRow().visible, false);
        }

        // At motion scale 1 the row fades in over the look's fade.
        function test_the_icons_fade_in() {
            put(root.listening);
            const centre = orbCentre();
            mouseMove(root, centre.x, centre.y);
            tryVerify(() => bubble.iconOpacity > 0 && bubble.iconOpacity < 1, root.look.icon.fade, "the row is mid-fade");
            tryCompare(bubble, "iconOpacity", 1, root.look.icon.fade + 200);
        }

        // The way from the orb to an icon keeps the row: the bridge holds
        // the pointer, and a path that cuts the corner past both the hit
        // square and the bridge keeps it for the look's hold.
        function test_the_way_to_an_icon_keeps_the_row() {
            compare(UnitTheme.override({ motion: { scale: 0 } }), "ok");
            put(root.listening);
            const centre = orbCentre();
            mouseMove(root, centre.x, centre.y);
            tryCompare(bubble, "iconOpacity", 1, 100);
            const bridge = named("iconBridge");
            const over = bridge.mapToItem(root, bridge.width / 2, bridge.height / 2);
            verify(over.x > centre.x + root.look.layout.hit / 2 || over.y < centre.y - root.look.layout.hit / 2, "the bridge's middle lies past the hit square");
            mouseMove(root, over.x, over.y);
            wait(root.look.icon.hold + 100);
            compare(bubble.iconOpacity, 1, "the bridge holds the row");
            // Right of the hit square and under the bridge: neither holds it.
            mouseMove(root, centre.x + root.look.layout.hit / 2 + 10, centre.y - root.look.layout.bridge + 10);
            compare(bubble.iconOpacity, 1, "the corner keeps the row for the hold");
            const voice = icon("voice-mute");
            mouseMove(voice, voice.width / 2, voice.height / 2);
            tryCompare(voice, "hovered", true);
            wait(root.look.icon.hold + 100);
            compare(bubble.iconOpacity, 1, "an icon holds the row");
            mouseClick(voice);
            compare(JSON.stringify(root.intents), '["voice-mute"]');
        }

        // A right click on the orb opens the Jarvis menu: the microphone's
        // and the voice's mute, Stop and Key hints, each sending its key's
        // intent or opening Jarvis's Keys section.
        function test_a_right_click_opens_the_jarvis_menu_data() {
            return [
                { tag: "Mute microphone", index: 0, intents: '["mute"]', pages: "[]" },
                { tag: "Mute Jarvis's voice", index: 1, intents: '["voice-mute"]', pages: "[]" },
                { tag: "Stop Jarvis", index: 2, intents: '["stop"]', pages: "[]" },
                { tag: "Key hints", index: 3, intents: "[]", pages: '["vgs.jarvis/Settings/Keys"]' }
            ];
        }

        function test_a_right_click_opens_the_jarvis_menu(data) {
            put(root.listening);
            const centre = orbCentre();
            mouseClick(root, centre.x, centre.y, Qt.RightButton);
            const open = menu();
            verify(open !== null, "the menu is built");
            tryCompare(open, "opened", true);
            compare(bubble.menuOpened, true);
            compare(JSON.stringify(bubble.menuTexts), JSON.stringify(["Mute microphone", "Mute Jarvis's voice", "Stop Jarvis", "Key hints"]));
            compare(JSON.stringify(open.items().map(entry => entry.iconName)), JSON.stringify(["mic-off", "volume-x", "square", "keyboard"]));
            open.items()[data.index].triggered();
            compare(JSON.stringify(root.intents), data.intents);
            compare(JSON.stringify(root.pages), data.pages);
        }

        // A right click on a line of text opens it too, and the menu keeps
        // the overlay shown after the service stops wanting it.
        function test_the_menu_keeps_the_overlay_shown() {
            put(root.session({ fault: { kind: "error", reason: "device-lost" } }));
            const line = all(bubble, []).find(item => item.role !== undefined && item.text === bubble.fault.title);
            verify(line !== undefined, "the fault's title draws");
            mouseClick(line, line.width / 2, line.height / 2, Qt.RightButton);
            tryCompare(bubble, "menuOpened", true);
            service.bubbleWanted = false;
            compare(bubble.shown, true);
            menu().close();
            tryCompare(bubble, "menuOpened", false);
            compare(bubble.shown, false);
            service.bubbleWanted = true;
        }

        // Waiting for the word, a right click on the orb opens nothing: the
        // bar widget's menu holds the entries then.
        function test_a_still_overlay_opens_no_menu() {
            put(root.session({ capture: { kind: "open", mode: "armed" } }));
            const centre = orbCentre();
            mouseClick(root, centre.x, centre.y, Qt.RightButton);
            wait(50);
            compare(bubble.menuOpened, false);
        }
    }
}
