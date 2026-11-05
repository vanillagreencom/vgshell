import QtQuick
import QtTest
import Quickshell.Hyprland
import Quickshell.Io
import qs.Core

// HyprlandState's binds read, which the key capture's hint reads: a failed
// read names its failure and empties the keys, a later read clears it, and
// turning the reads off forgets both. The Process stand-in answers each
// `hyprctl -j binds` by hand.
Item {
    id: root
    HyprlandState { id: state }
    Component { id: resolutionFixture; HyprlandState {} }

    TestCase {
        name: "hyprland-state-binds"

        function binds() {
            return ProcessRegistry.processes.find(process => process.running && process.command.join(" ") === "hyprctl -j binds");
        }

        function devicesText() {
            return JSON.stringify({ mice: [{ name: "fixture-touchpad" }], keyboards: [{ name: "fixture", rules: "evdev", model: "pc105",
                layout: "us,de", variant: "", options: "", active_layout_index: 0, active_keymap: "English (US)", main: true }] });
        }

        function keysText() {
            return [devicesText()].concat(["kb_file", "kb_rules", "kb_model", "kb_layout", "kb_variant", "kb_options"].map(name => JSON.stringify({
                option: "input:" + name, str: name === "kb_layout" ? "us,de" : "[[EMPTY]]"
            }))).join("\n\n\n");
        }

        function reader(owner) { for (const child of owner.data) if (child.label === "devices") return child; }
        function helper(owner) { for (const child of owner.data) if (child.requestText !== undefined) return child; }
        function resolved() {
            const key = { modifiers: ["SUPER"], keycode: 44, keysym: "j", codepoint: 106 };
            return JSON.stringify({ ok: true, keys: [key], translation: [key] });
        }

        function test_key_resolution_lifetime_data() {
            return ["inactive", "ordinary", "ordinary-during-keys", "ordinary-failure-during-keys", "matching", "expired", "older-during-new", "queued", "repeated", "changed-layout", "matching-failure", "policy-refusal", "stale-failure", "reactivated", "old-helper", "busy", "slow-keys", "slow-helper"].map(name => ({ tag: name, kind: name }));
        }

        // expected-log: hyprland: devices=failed status=1 -- matching-failure supplies the real reader failure
        function test_key_resolution_lifetime(data) {
            const owner = resolutionFixture.createObject(root);
            verify(owner !== null);
            const answers = [];
            const start = key => {
                owner.resolveKeys([key || "SUPER+J"], value => answers.push(value));
                return owner.keyResolution === null ? null : owner.keyResolution.token;
            };
            try {
                if (data.kind === "inactive") {
                    start();
                    compare(answers.length, 1);
                    compare(answers[0].error, "refused: keymap=busy");
                    compare(owner.keyResolution, null);
                    return;
                }
                owner.active = true;
                const read = reader(owner);
                verify(read !== undefined);
                if (data.kind === "ordinary") {
                    read.readDone(null, devicesText(), "");
                    compare(owner.devices.keyboards[0].activeLayoutIndex, 0);
                    compare(owner.keyResolution, null);
                    compare(answers.length, 0);
                    return;
                }
                const a = start();
                verify(a !== null);
                compare(read.pendingRequest, a, "the running ordinary read queues the actual key token");
                if (data.kind === "ordinary-during-keys" || data.kind === "ordinary-failure-during-keys") {
                    const failure = data.kind === "ordinary-failure-during-keys" ? "devices=failed status=1" : "";
                    read.readDone(null, devicesText(), failure);
                    compare(owner.keyResolution.token, a, "ordinary devices cannot settle a key request");
                    compare(answers.length, 0);
                    compare(owner.devicesFailure, failure);
                    return;
                }
                if (data.kind === "busy") {
                    owner.resolveKeys(["SUPER+K"], value => answers.push(value));
                    compare(answers.length, 1);
                    compare(answers[0].error, "refused: keymap=busy");
                    compare(owner.keyResolution.token, a);
                    return;
                }
                if (data.kind === "slow-keys") {
                    compare(answers.length, 0, "the KEYS read retains its request until answered");
                    read.readDone(a, keysText(), "");
                    compare(helper(owner).requestToken, a);
                    helper(owner).finish(0, 0, resolved());
                    compare(answers.length, 1);
                    compare(answers[0].ok, true);
                    return;
                }
                if (data.kind === "queued") {
                    read.readDone(a, keysText(), "");
                    helper(owner).finish(2, 0, "");
                    const b = start("SUPER+K");
                    verify(b !== null && b !== a);
                    let process;
                    for (const child of read.data) if (child.running && child.command !== undefined && child.command.join(" ") === "hyprctl -j devices") process = child;
                    verify(process !== undefined);
                    process.finish(0, 0, devicesText());
                    compare(read.currentRequest, b, "the generic reader starts only the newest pending token");
                    compare(owner.keyResolution.token, b);
                    compare(answers.length, 1, "the dropped ordinary reply never settles B");
                    process.finish(0, 0, keysText());
                    compare(helper(owner).requestToken, b);
                    helper(owner).finish(0, 0, resolved());
                    compare(answers.length, 2);
                    compare(answers[1].ok, true);
                    return;
                }
                if (["expired", "older-during-new", "stale-failure", "reactivated"].indexOf(data.kind) !== -1) {
                    if (data.kind === "reactivated") { owner.active = false; owner.active = true; }
                    else { read.readDone(a, keysText(), ""); helper(owner).finish(2, 0, ""); }
                    compare(answers.length, 1);
                    compare(answers[0].error, data.kind === "reactivated" ? "refused: keymap=inactive" : "refused: keymap=resolver-failed");
                    const b = data.kind === "expired" ? null : start("SUPER+K");
                    const before = JSON.stringify(owner.devices);
                    const failure = data.kind === "stale-failure" ? "devices=failed status=1" : "";
                    read.readDone(a, keysText(), failure);
                    compare(JSON.stringify(owner.devices), before, "expired key replies do not mutate devices");
                    compare(owner.devicesFailure, "", "expired key replies never enter device parsing");
                    compare(answers.length, 1, "stale replies cannot settle a newer resolution");
                    compare(owner.keyResolution === null ? null : owner.keyResolution.token, b);
                    compare(helper(owner).running, false);
                    return;
                }
                if (data.kind === "matching-failure") {
                    read.readDone(a, "", "devices=failed status=1");
                    compare(answers.length, 1);
                    compare(answers[0].error, "devices=failed status=1");
                    compare(owner.devicesFailure, "devices=failed status=1");
                    compare(owner.keyResolution, null);
                    return;
                }
                if (data.kind === "policy-refusal") {
                    read.readDone(a, keysText().replace('"str":"[[EMPTY]]"', '"str":"/custom.xkb"'), "");
                    compare(answers.length, 1);
                    compare(answers[0].error, "refused: keymap=custom-file");
                    compare(owner.devicesFailure, "");
                    compare(owner.keyResolution, null);
                    return;
                }
                read.readDone(a, keysText(), "");
                compare(owner.keyResolution.token, a, "record copies retain the opaque token");
                compare(helper(owner).requestToken, a);
                if (data.kind === "slow-helper") {
                    // This is a timer-wiring regression, not a speed budget:
                    // leave the real QML event loop free beyond the former
                    // two-second cancellation while the Process stand-in
                    // withholds completion. No CPU or host load is generated.
                    wait(2100);
                    compare(answers.length, 0, "slow execution or delivery cannot drop an accepted request");
                    compare(owner.keyResolution.token, a);
                    compare(helper(owner).running, true);
                }
                if (data.kind === "repeated") {
                    const wire = helper(owner).requestText;
                    read.readDone(a, keysText(), "");
                    compare(helper(owner).requestText, wire);
                    compare(answers.length, 0, "equal matching facts leave the same helper running");
                }
                if (data.kind === "changed-layout") {
                    read.readDone(a, keysText().replace(/us,de/g, "de"), "");
                    compare(answers.length, 1);
                    compare(answers[0].error, "refused: keymap=layout-changed");
                    compare(owner.keyResolution, null);
                    compare(helper(owner).running, false);
                    return;
                }
                if (data.kind === "old-helper") {
                    helper(owner).finish(2, 0, "");
                    compare(answers.length, 1);
                    const b = start("SUPER+K");
                    verify(b !== null && b !== a);
                    // Deliver A's terminal record at the existing Process
                    // completion boundary while B awaits its own facts.
                    helper(owner).completion = { token: a, code: 0, status: 0 };
                    helper(owner).runningChanged();
                    compare(owner.keyResolution.token, b, "old helper completion cannot finish B");
                    compare(answers.length, 1);
                    return;
                }
                helper(owner).finish(0, 0, resolved());
                compare(owner.keyResolution, null);
                compare(answers.length, 1);
                compare(answers[0].ok, true);
            } finally {
                owner.active = false;
                owner.destroy();
            }
        }

        function test_keymap_revision_events_data() {
            return [
                { tag: "configreloaded", kind: "reload", step: 1 },
                { tag: "activelayout", kind: "layout", step: 0 },
                { tag: "keyboard-layout-switched", kind: "switched", step: 0 },
                { tag: "device-count", kind: "devices", step: 0 }
            ];
        }

        // Only a reload rebuilds Hyprland's bind map, so only it may start a
        // new key resolution; a layout switch or a device change reads the
        // devices alone.
        function test_keymap_revision_events(data) {
            const owner = resolutionFixture.createObject(root);
            verify(owner !== null);
            try {
                owner.active = true;
                const before = owner.keymapRevision;
                if (data.kind === "reload") Hyprland.rawEvent({ name: "configreloaded", data: "" });
                else if (data.kind === "layout") Hyprland.rawEvent({ name: "activelayout", data: "fixture,German" });
                else if (data.kind === "switched") Compositor.keyboardLayoutSwitched();
                else {
                    let devices;
                    for (const child of owner.data) if (child.nameFilters !== undefined && child.files !== undefined) devices = child;
                    verify(devices !== undefined);
                    devices.files = devices.files.concat(["/dev/input/event9"]);
                }
                compare(owner.keymapRevision, before + data.step);
                compare(owner.resolvingKeys, false);
            } finally {
                owner.active = false;
                owner.destroy();
            }
        }

        // expected-log: hyprland: binds=failed -- the failed read this case answers
        // expected-log: hyprland: refused: binds=unparsed -- the reply that is no JSON this case answers
        function test_a_failed_binds_read_is_named() {
            state.active = true;
            let read = binds();
            verify(read !== undefined, "the binds read starts");
            read.finish(1, 0, "", "no socket");
            compare(state.foreignKeys, null);
            verify(state.bindsFailure.indexOf("binds=failed") === 0, state.bindsFailure);
            state.readBinds();
            read = binds();
            read.finish(0, 0, JSON.stringify([{ submap: "", modmask: 64, key: "K", keycode: 0, description: "", dispatcher: "exec" }]), "");
            compare(state.bindsFailure, "");
            compare(JSON.stringify(state.foreignKeys), '["SUPER+K"]');
            state.readBinds();
            binds().finish(0, 0, "not json", "");
            verify(state.bindsFailure.indexOf("refused: binds=unparsed") === 0, state.bindsFailure);
            state.active = false;
            compare(state.bindsFailure, "");
            compare(state.foreignKeys, null);
        }
    }
}
