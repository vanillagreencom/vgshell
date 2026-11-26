import QtQuick
import QtTest
import Quickshell.Io
import "../../shell/plugins/vgs.jarvis"

// KeyEditor's key transport, over a stand-in of the core's status and the
// Process stand-in, which runs nothing: a test starts and ends the
// `keys.js add-key` run by hand. A save hands the typed key to the run's
// stdin alone: its argv names the mode, the provider and the name and never
// the key, stdin takes the key once as the run starts and then closes, and
// the save's end reports `ok` only for exit 0, never for a nonzero exit or a
// run that never started, and leaves no save held. An Add runs `new` and an
// Edit `replace`. A save waits for a running Check and for a read of the
// keys. Every key here is a stand-in.
Item {
    id: top

    readonly property string standIn: "stand-in-key-not-a-secret"

    Component {
        id: world

        Item {
            id: host
            property var published: ({})
            property int rereads: 0
            readonly property alias editor: keyEditor
            readonly property alias reader: accounts
            property var shell: ({
                settings: { brain: "", fallbacks: [], voiceAccount: "", voiceProvider: "local" },
                status: { isOk: reply => reply === "ok", set: (key, value) => { host.published[key] = value; return "ok"; },
                    handleActions: () => "ok", openEditor: () => "ok" },
                configure: { set: () => "ok" }
            })
            Item {
                id: accounts
                // The stored key is written here, since this list's first
                // evaluation under qmltestrunner reads a root property of
                // the file as undefined.
                property var keyList: [{ id: "key-a", label: "OpenAI", name: "OpenAI", provider: "openai", providerLabel: "OpenAI", own: true,
                    presence: "present", model: "gpt-4.1-nano", checkable: true, check: { kind: "none" } }]
                property bool voiceCleared: false
                function keysChanged() { host.rereads += 1; }
            }
            Item {
                id: keys
                function refresh() {}
            }
            KeyEditor { id: keyEditor; shell: host.shell; accounts: accounts; keys: keys }
        }
    }

    TestCase {
        name: "jarvisKeyEditor"

        function writer() {
            const found = ProcessRegistry.processes.filter(process => process.command.indexOf("add-key") !== -1);
            return found.length === 1 ? found[0] : null;
        }

        // A save of PRESS over HOST, its reply and each end it reported.
        function save(host, press) {
            const ends = [];
            const reply = host.editor.handle(Object.assign({ key: "providerKeys", action: "save", row: "", choice: "openai", name: "Work",
                target: "", secret: top.standIn }, press), end => ends.push(end));
            return { reply: reply, ends: ends };
        }

        function test_an_add_hands_the_key_to_stdin_alone() {
            const host = createTemporaryObject(world, top);
            const run = save(host, {});
            compare(run.reply, "ok");
            const process = writer();
            verify(process !== null, "one add-key run");
            compare(process.command.slice(2), ["add-key", "new", "openai", "Work"], "the argv names the mode, provider and name");
            verify(process.command.every(arg => String(arg).indexOf(top.standIn) === -1), "no argument holds the key");
            verify(process.stdinEnabled, "stdin opens for the run");
            compare(process.written, [], "nothing is written before the run starts");
            process.started();
            compare(process.written, [top.standIn], "the key is written once as the run starts");
            verify(!process.stdinEnabled, "stdin closes after the key");
            process.started();
            compare(process.written.length + process.writtenClosed.length, 1, "a second start writes nothing");
            compare(run.ends, [], "the save ends only with its run");
            process.finish(0, 0);
            compare(run.ends, [{ ok: true, text: "" }]);
            compare(host.editor.storing, null, "no save is held after its end");
            compare(host.rereads, 1, "the keys are read again");
        }

        function test_an_edit_replaces_its_own_key() {
            const host = createTemporaryObject(world, top);
            save(host, { row: "key-a", choice: "openai", name: "ignored" });
            compare(writer().command.slice(2), ["add-key", "replace", "openai", "OpenAI"], "an Edit names its row's own key");
        }

        function test_a_failed_run_never_reports_success_data() {
            return [{ tag: "a refused store", end: process => process.finish(1, 0) },
                { tag: "an Add of a stored key", end: process => process.finish(8, 0) },
                { tag: "a run that never started", end: process => process.failStart() }];
        }
        // expected-log: jarvis-keys: store= -- each failed run logs its keyed cause, never the key
        function test_a_failed_run_never_reports_success(data) {
            const host = createTemporaryObject(world, top);
            const run = save(host, {});
            data.end(writer());
            compare(run.ends.length, 1);
            compare(run.ends[0].ok, false, data.tag + " reads failed");
            verify(run.ends[0].text !== "" && run.ends[0].text.indexOf(top.standIn) === -1, data.tag + " says what failed, without the key");
            compare(host.editor.storing, null, "no save is held after its end");
        }

        // One key operation at a time, and none over an unread list: a
        // refused save starts no run and holds no key.
        function test_a_save_waits_data() {
            return [{ tag: "a running Check", plant: host => { host.editor.checking = "key-a"; } },
                { tag: "an unread list", plant: host => { host.reader.keyList = undefined; } }];
        }
        function test_a_save_waits(data) {
            const host = createTemporaryObject(world, top);
            data.plant(host);
            const run = save(host, {});
            compare(run.ends.length, 1);
            compare(run.ends[0].ok, false);
            compare(writer(), null, data.tag + ": no run starts");
            compare(host.editor.storing, null);
        }
    }
}
