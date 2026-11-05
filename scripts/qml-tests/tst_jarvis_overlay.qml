import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit
import "../../shell/plugins/vgs.jarvis"
import "../../shell/plugins/vgs.jarvis/Appearance.js" as Appearance
import "../../shell/plugins/vgs.jarvis/Session.js" as Session

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
        property var microphoneMute: ({ kind: "ready", muted: false })
        property bool bubbleWanted: true
        property string focusedOutput: "unit"
        property var consoleBox: null
        property string consoleKey: ""
        property string heldKey: ""
        property var effectiveKeys: ({ stop: "SUPER+CTRL+X", confirm: "SUPER+CTRL+Y" })
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
        const s = Object.assign(JSON.parse(JSON.stringify(Session.initial())), { gen: 1, gate: { kind: "up" } });
        for (const key in over) s[key] = over[key];
        return s;
    }
    readonly property var listening: session({ capture: { kind: "open", gen: 1, op: 2, mode: "hold" }, conversation: { kind: "active", purpose: "conversation" } })

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
            const found = all(bubble, []).filter(item => item.children.some(child => child.entry !== undefined && child.entry.intent === "voice-mute"));
            verify(found.length === 1, "one icon row");
            return found[0];
        }
        function icon(intent) { return iconRow().children.find(child => child.entry !== undefined && child.entry.intent === intent); }
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
            service.microphoneMute = { kind: "ready", muted: false };
            away();
            const open = menu();
            if (open !== null) open.close();
            tryCompare(bubble, "iconOpacity", 0, 2000);
        }

        // An open conversation takes the pointer on the orb even between
        // turns; a closed conversation takes none.
        function test_only_an_active_overlay_takes_the_orb_data() {
            return [
                { tag: "conversation open at rest", state: root.session({ conversation: { kind: "active", purpose: "conversation" } }), takes: true },
                { tag: "getting ready", state: root.session({}), takes: false },
                { tag: "stopping", state: root.session({ gate: { kind: "down" } }), takes: false },
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
            compare(row.x, centre.x + root.look.state.idle.radius * 255 / 2);
        }

        // The icon row shows while the pointer rests on the orb in an
        // active state, and goes the look's hold after the pointer leaves;
        // at motion scale 0 it shows and goes with no fade. A closed
        // conversation shows no icons.
        function test_the_icons_show_only_under_the_pointer_data() {
            return [{ tag: "listening", state: root.listening, shows: true },
                    { tag: "conversation closed", state: root.session({}), shows: false }];
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

        // Each icon of the row reads its Jarvis menu entry's label, which
        // names its next action in every mute state, and sends that entry's
        // intent.
        function test_each_icon_names_and_sends_its_menu_entry_data() {
            return [
                { tag: "the microphone, on", state: {}, microphone: false, intent: "microphone-mute", label: "Mute microphone" },
                { tag: "the microphone, muted", state: {}, microphone: true, intent: "microphone-mute", label: "Unmute microphone" },
                { tag: "the voice, on", state: { voiceMute: { kind: "off" } }, intent: "voice-mute", label: "Mute Jarvis's voice" },
                { tag: "the voice, muted", state: { voiceMute: { kind: "on" } }, intent: "voice-mute", label: "Unmute Jarvis's voice" },
                { tag: "Stop", state: {}, intent: "stop", label: "Stop Jarvis" }
            ];
        }

        function test_each_icon_names_and_sends_its_menu_entry(data) {
            compare(UnitTheme.override({ motion: { scale: 0 } }), "ok");
            const over = { capture: { kind: "open", gen: 1, op: 2, mode: "hold" }, conversation: { kind: "active", purpose: "conversation" } };
            for (const key in data.state) over[key] = data.state[key];
            put(root.session(over));
            const button = icon(data.intent);
            verify(button !== undefined, "the row holds the " + data.intent + " icon");
            if (data.microphone !== undefined) service.microphoneMute = { kind: "ready", muted: data.microphone };
            compare(button.label, data.label);
            compare(button.checked, data.intent === "microphone-mute" ? data.microphone : data.state.voiceMute !== undefined && data.state.voiceMute.kind === "on");
            const centre = orbCentre();
            mouseMove(root, centre.x, centre.y);
            tryCompare(bubble, "iconOpacity", 1, 100);
            mouseClick(button);
            compare(JSON.stringify(root.intents), JSON.stringify([data.intent]));
        }

        // A right click on the orb opens the Jarvis menu: the microphone's
        // and the voice's mute, Stop and Key hints, each sending its key's
        // intent or opening Jarvis's Keys section.
        function test_a_right_click_opens_the_jarvis_menu_data() {
            return [
                { tag: "Mute microphone", index: 1, intents: '["microphone-mute"]', pages: "[]" },
                { tag: "Mute Jarvis's voice", index: 0, intents: '["voice-mute"]', pages: "[]" },
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
            compare(JSON.stringify(bubble.menuTexts), JSON.stringify(["Mute Jarvis's voice", "Mute microphone", "Stop Jarvis", "Key hints"]));
            compare(JSON.stringify(open.items().map(entry => entry.iconName)), JSON.stringify(["volume-x", "mic", "square", "keyboard"]));
            open.items()[data.index].triggered();
            compare(JSON.stringify(root.intents), data.intents);
            compare(JSON.stringify(root.pages), data.pages);
        }

        function test_microphone_unavailable_disables_its_icon() {
            compare(UnitTheme.override({ motion: { scale: 0 } }), "ok");
            put(root.listening);
            service.microphoneMute = { kind: "unavailable" };
            const centre = orbCentre();
            mouseMove(root, centre.x, centre.y);
            tryCompare(bubble, "iconOpacity", 1, 100);
            const mic = icon("microphone-mute");
            compare(JSON.stringify(iconRow().children.filter(item => item.entry !== undefined).map(item => item.entry.intent)),
                '["voice-mute","microphone-mute","stop"]', "voice comes before system microphone");
            verify(mic.disabledReason !== "");
            compare(mic.checked, false);
            mouseClick(mic);
            compare(root.intents.length, 0, "an unavailable source cannot toggle");
            service.microphoneMute = { kind: "ready", muted: true };
            compare(mic.disabledReason, "");
            compare(mic.checked, true);
            compare(bubble.active, true, "system mute leaves an open conversation active");
            compare(bubble.stateText, "Microphone muted");
            const stateLines = all(bubble, []).filter(item => item.text === "Microphone muted" && bubble.drawn(item));
            compare(stateLines.length, 1, "the mute reading appears once");
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

        // A closed conversation opens no orb menu; the bar menu remains
        // available.
        function test_a_still_overlay_opens_no_menu() {
            put(root.session({}));
            const centre = orbCentre();
            mouseClick(root, centre.x, centre.y, Qt.RightButton);
            verify(renderedFrame(root));
            compare(bubble.menuOpened, false);
        }
    }
}
