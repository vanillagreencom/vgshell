import QtQuick
import QtTest
import Quickshell.Io
import qs.Core
import "../../shell/plugins/vgs.jarvis"

// The account reader's model and effort writes, over a stand-in of the
// core's write path. That path is synchronous to its end, as
// Config.writeUser, the Config.effective binding and Plugins.refreshRow
// are: a write sets `user`, the `effective` binding derives the settings,
// and its change handler replaces `shell` before the write returns. A write
// made from the change handler of a binding that reads `shell` updates that
// binding inside its own update: Qt logs a binding loop and keeps the old
// value, and the runner fails a file on any warning. The Process stand-in
// runs nothing: a test ends the list read and the account read by hand.
Item {
    id: top

    readonly property var levels: ["low", "medium", "high", "xhigh", "max"]
    // A Claude Code list as its adapter narrows it: the program's own
    // default first, and Haiku 4.5 takes no effort.
    readonly property var listed: ({ kind: "read", offers: [
        { value: "claude-opus-5-5[1m]", label: "Opus 5.5", efforts: levels, effort: "" },
        { value: "claude-fable-5-1", label: "Fable 5.1", efforts: levels, effort: "" },
        { value: "claude-haiku-4-5", label: "Haiku 4.5", efforts: [], effort: "" }] })

    Component {
        id: world

        Item {
            id: host

            // The plugin's row of the user file, and each key written to it.
            property var user: ({ brain: "claude-a", model: "", effort: "" })
            property var writes: []
            // The core's TUI records and the status values the reader set.
            property var tuiState: ({})
            onTuiStateChanged: shell = build()
            property var published: ({})
            // The manifest's voice defaults under the user's row, as the
            // core merges them.
            readonly property var effective: Object.assign({ voiceProvider: "local", voiceAccount: "", mode: "hold" }, user)
            onEffectiveChanged: shell = build()
            // Whether the Settings window shows the Jarvis page.
            property bool viewed: false
            property var shell: null
            readonly property alias reader: accounts
            // What the reader's own `shell` holds, beside what the file holds.
            readonly property string held: accounts.shell.settings.brain + " " + accounts.shell.settings.model + " " + accounts.shell.settings.effort
            readonly property string stored: user.brain + " " + user.model + " " + user.effort

            function build() {
                return { settings: effective, tui: { state: tuiState }, requirements: { missing: [] },
                    status: { get viewed() { return host.viewed; }, isOk: PluginLogic.statusReplyOk, set: (key, value) => host.publish(key, value) },
                    configure: { set: (key, value) => host.write(key, value) } };
            }
            function publish(key, value) {
                published[key] = value;
                return "ok";
            }
            function write(key, value) {
                writes.push(key + "=" + value);
                user = Object.assign({}, user, { [key]: value });
                return "ok";
            }

            Component.onCompleted: shell = build()
            Accounts { id: accounts; shell: host.shell }
        }
    }

    TestCase {
        name: "jarvisAccounts"

        // The page is open over SAVED, and the reader has seen its sign-in.
        function open(saved) {
            const host = createTemporaryObject(world, top, { user: Object.assign({ brain: "claude-a", model: "", effort: "" }, saved) });
            host.viewed = true;
            wait(0);
            return host;
        }

        function lister() {
            const found = ProcessRegistry.processes.filter(process => process.command.length === 6 && process.command[4] === "models");
            compare(found.length, 1, "one list read process");
            return found[0];
        }

        // The running list read ends with ANSWER on its stdout.
        function end(answer) {
            const process = lister();
            verify(process.running, "a list read runs");
            process.stdout.text = JSON.stringify(answer);
            process.stdout.streamFinished();
            process.running = false;
        }

        // Each account read that runs, a queued one included, ends with
        // VOICE as the stored cloud voice keys.
        function read(host, voice) {
            const found = ProcessRegistry.processes.filter(process => process.command.length === 6 && process.command[4] === "presence");
            compare(found.length, 1, "one account read process");
            verify(found[0].running, "an account read runs");
            while (found[0].running) {
                found[0].stdout.text = JSON.stringify({ accounts: [], brains: [], providers: {}, voiceAccounts: voice, search: { found: 0, partial: "" } });
                found[0].stdout.streamFinished();
                found[0].exited(0, 0);
                found[0].running = false;
                wait(0);
            }
            return host.published.voiceAccounts.map(choice => choice.value);
        }

        readonly property var work: ({ value: "key-work", label: "OpenAI / work", provider: "openai" })
        readonly property var home: ({ value: "key-home", label: "OpenAI / home", provider: "openai" })

        // Remove key ended and the read it starts no longer holds the
        // Voice key: the choices lose it, and the choice goes to the key
        // that is left.
        function test_removed_voice_key_leaves_the_choices_and_the_choice() {
            const host = open({ voiceProvider: "realtime", voiceAccount: "key-work" });
            compare(read(host, [work, home]), ["key-work", "key-home"]);
            compare(host.writes, [], "a stored Voice key is kept");
            host.tuiState = { "remove-key": { endedAt: 1 } };
            compare(read(host, [home]), ["key-home"], "the Voice key choices");
            compare(host.writes, ["voiceAccount=", "voiceAccount=key-home"]);
            compare(host.user.voiceAccount, "key-home");
        }

        // The control: a Remove key screen that ends with the key still
        // stored, as after Cancel, changes neither.
        function test_kept_voice_key_keeps_the_choice() {
            const host = open({ voiceProvider: "realtime", voiceAccount: "key-work" });
            read(host, [work, home]);
            host.tuiState = { "remove-key": { endedAt: 1 } };
            compare(read(host, [work, home]), ["key-work", "key-home"]);
            compare(host.writes, []);
        }

        function test_list_read_saves_its_default() {
            const host = open({});
            compare(lister().command[5], "claude-a");
            end(top.listed);
            tryCompare(host, "stored", "claude-a claude-fable-5-1 high");
            compare(host.held, host.stored, "the reader's shell holds what the file holds");
            compare(host.writes, ["model=claude-fable-5-1", "effort=high"]);
            wait(0);
            compare(host.writes.length, 2, "a saved choice is not written again");
        }

        function test_changed_sign_in_drops_the_saved_choice() {
            const host = open({ model: "claude-fable-5-1", effort: "high" });
            // The page writes the sign-in while the first sign-in's read runs.
            host.write("brain", "codex-a");
            tryCompare(host, "stored", "codex-a  ");
            compare(host.held, host.stored, "the reader's shell holds what the file holds");
            compare(host.writes, ["brain=codex-a", "model=", "effort="]);
            // The running read is not ended: its helper removes its
            // program's folder at its end. That end drops its answer and
            // starts the read of the chosen sign-in.
            verify(lister().running, "the first sign-in's read runs to its end");
            compare(lister().command[5], "claude-a");
            end(top.listed);
            compare([lister().running, lister().command[5]], [true, "codex-a"]);
            wait(0);
            compare(host.stored, "codex-a  ", "an answer for an earlier sign-in saves nothing");
        }

        function test_model_without_the_saved_effort() {
            const host = open({ model: "claude-fable-5-1", effort: "high" });
            end(top.listed);
            wait(0);
            compare(host.writes, [], "a saved choice its list offers is kept");
            host.write("model", "claude-haiku-4-5");
            tryCompare(host, "stored", "claude-a claude-haiku-4-5 ");
            compare(host.held, host.stored, "the reader's shell holds what the file holds");
            compare(host.writes, ["model=claude-haiku-4-5", "effort="]);
        }

        function test_first_entry_choice_saves_its_model() {
            const host = open({ model: "claude-opus-5-5[1m]", effort: "max" });
            end(top.listed);
            wait(0);
            // The page writes "" for the first entry of the Model field.
            host.write("model", "");
            tryCompare(host, "stored", "claude-a claude-fable-5-1 max");
            compare(host.held, host.stored, "the reader's shell holds what the file holds");
            compare(host.writes, ["model=", "model=claude-fable-5-1"]);
        }
    }
}
