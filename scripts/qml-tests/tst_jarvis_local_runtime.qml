import QtQuick
import QtTest
import qs.Core
import "../../shell/plugins/vgs.jarvis"
import "../../shell/plugins/vgs.jarvis/SetupGate.js" as Gate

// A setup reader's publication of a finished check, over a stand-in of the
// core's status write that answers each write with the next queued reply.
// The core refuses every write of an instance a disable or a rescan
// retired (PluginStatus.set), and a probe that ends after that retirement
// still publishes. Each case calls `publish`, the function the probe's end
// calls, so a thrown error reaches the case instead of the shell log.
Item {
    id: top

    Component {
        id: world

        LocalRuntime {
            id: runtime

            property var replies: []
            property var writes: []

            statusKey: "setupFleet"
            tuiName: "setup-fleet"
            shell: ({ manifest: { status: { setupFleet: entry } }, requirements: { missing: [], revision: 0 },
                tui: { state: {} }, status: { set: (key, value) => runtime.write(key, value) } })

            // The Agent fleet row: the key whose retired write reached the
            // shell log.
            readonly property var entry: ({ type: "state", label: "Agent fleet", action: { label: "Install mail tool", tui: "setup-fleet" } })

            function write(key, value) {
                writes = writes.concat([{ key: key, value: value }]);
                const reply = replies[0];
                replies = replies.slice(1);
                return reply;
            }
        }
    }

    TestCase {
        name: "jarvisLocalRuntime"

        // Each row: the replies the core gives in order, the check
        // failure kind of each value the reader writes, and the key of the
        // error it throws, or "" for none. The probe stand-in runs nothing,
        // so every check reads as `failed`.
        function test_publish_data() {
            const retired = PluginLogic.statusRefusal("setupFleet", "retired");
            const typeRefused = PluginLogic.statusRefusal("setupFleet", "type");
            return [
                { tag: "accepted", replies: ["ok"], written: ["failed"], thrown: "" },
                { tag: "retired instance", replies: [retired], written: ["failed"], thrown: "" },
                { tag: "refused value falls back", replies: [typeRefused, "ok"], written: ["failed", "unreadable"], thrown: "" },
                { tag: "refused fallback", replies: [typeRefused, typeRefused], written: ["failed", "unreadable"], thrown: "jarvis-setup: " + typeRefused }
            ];
        }

        function test_publish(data) {
            const runtime = createTemporaryObject(world, top, { replies: data.replies });
            verify(runtime !== null, "the reader is built");
            let thrown = "";
            try {
                runtime.publish();
            } catch (error) {
                thrown = error.message;
            }
            compare(thrown, data.thrown);
            compare(runtime.writes.map(row => row.key), data.written.map(() => "setupFleet"));
            compare(runtime.writes.map(row => row.value), data.written.map(kind => Gate.checkFailure(kind, runtime.entry)));
            compare(runtime.replies.length, 0, "every queued reply was read");
        }
    }
}
