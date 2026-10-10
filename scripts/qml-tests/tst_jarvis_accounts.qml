import QtQuick
import QtTest
import Quickshell.Io
import "../../shell/plugins/vgs.jarvis"

// The account reader's model and effort writes, over a stand-in of the
// core's write path. That path is synchronous to its end, as
// Config.writeUser, the Config.effective binding and Plugins.refreshRow
// are: a write sets `user`, the `effective` binding derives the settings,
// and its change handler replaces `shell` before the write returns. A write
// made from the change handler of a binding that reads `shell` updates that
// binding inside its own update: Qt logs a binding loop and keeps the old
// value, and the runner fails a file on any warning. The Process stand-in
// runs nothing: a test ends the list read by hand.
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
            readonly property var effective: Object.assign({}, user)
            onEffectiveChanged: shell = build()
            // Whether the Settings window shows the Jarvis page.
            property bool viewed: false
            property var shell: null
            readonly property alias reader: accounts
            // What the reader's own `shell` holds, beside what the file holds.
            readonly property string held: accounts.shell.settings.brain + " " + accounts.shell.settings.model + " " + accounts.shell.settings.effort
            readonly property string stored: user.brain + " " + user.model + " " + user.effort

            function build() {
                return { settings: effective, tui: { state: ({}) }, requirements: { missing: [] },
                    status: { get viewed() { return host.viewed; }, set: (key, value) => "ok" },
                    configure: { set: (key, value) => host.write(key, value) } };
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
