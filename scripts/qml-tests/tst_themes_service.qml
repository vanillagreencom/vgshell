import QtQuick
import QtTest
import "../../shell/plugins/vgs.themes" as Themes
import "../../shell/plugins/vgs.themes/BrowserLogic.js" as BrowserLogic

// The themes service's hand-over notice. The theme browser closes on the
// publish of an apply it ran and hands the answer to the service through
// `report-apply`; the next apply result is that apply's, and a failed or
// partial one becomes one notice. The fake shell answers the calls the
// service makes at registration inertly, records each IPC handler and each
// notice, and publishes `last` through a getter over a QtObject property,
// as ThemeRunner's provider does.
Item {
    id: root

    QtObject {
        id: store
        property var last: Object.freeze({ applying: null, result: null, downloading: null })
    }

    Component {
        id: serviceComponent
        Themes.Service {}
    }

    TestCase {
        id: tests
        name: "themesService"

        property var service: null
        property var handlers: ({})
        property var notices: []

        function fakeShell() {
            return {
                settings: {},
                tui: { state: {} },
                requirements: { revision: 0 },
                shortcut: { register: (name, description, run) => "ok" },
                ipc: { handle: (name, handler) => { tests.handlers[name] = handler; return "ok"; } },
                theme: {
                    get last() { return store.last; },
                    listing: null,
                    list: done => {},
                    images: (scope, done) => {},
                    catalog: done => {}
                },
                notify: { send: options => { tests.notices = tests.notices.concat([options]); return "ok"; } },
                status: { set: (key, value) => "ok" }
            };
        }

        // A new `last`, as ThemeRunner publishes one when the running apply
        // or the result changes.
        function publish(result, applying) {
            store.last = Object.freeze({ applying: applying === undefined ? null : applying, result: result, downloading: null });
        }

        function handOver(name) {
            compare(handlers["report-apply"](name), "ok");
            compare(service.reported, name);
        }

        function init() {
            store.last = Object.freeze({ applying: null, result: null, downloading: null });
            handlers = {};
            notices = [];
            service = createTemporaryObject(serviceComponent, root);
            verify(service !== null);
            // The core assigns the scoped shell after creation.
            service.shell = fakeShell();
            verify(typeof handlers["report-apply"] === "function", "the service registers report-apply");
        }

        function test_handed_over_result_data() {
            return [
                { tag: "partial after a hand-over", handOver: true, result: { state: "partial", theme: "nord", reason: null }, tone: "warning" },
                { tag: "failed after a hand-over", handOver: true, result: { state: "failed", theme: "nord", reason: "busy" }, tone: "danger" },
                { tag: "clean after a hand-over", handOver: true, result: { state: "applied", theme: "nord", reason: null }, tone: null },
                { tag: "partial with no hand-over", handOver: false, result: { state: "partial", theme: "nord", reason: null }, tone: null }
            ];
        }

        function test_handed_over_result(data) {
            publish(null, "nord");
            if (data.handOver) handOver("nord");
            publish(data.result);
            compare(service.reported, "", "no hand-over waits once the result came");
            if (data.tone === null) {
                compare(notices.length, 0, "no notice");
                return;
            }
            compare(notices.length, 1, "one notice");
            compare(notices[0].tone, data.tone);
            compare(notices[0].icon, "palette");
            compare(JSON.stringify(notices[0]), JSON.stringify(BrowserLogic.applyNotice("nord", data.result)));
        }

        // The result current at the hand-over is an earlier apply's: a new
        // `last` that carries it again, the running apply changed or not,
        // is no answer, and the hand-over waits for the next result: a
        // binding that evaluates to the identical object emits no change.
        function test_result_current_at_hand_over_is_not_the_answer() {
            const earlier = { state: "partial", theme: "akane", reason: null };
            publish(earlier);
            compare(notices.length, 0, "a result with no hand-over sends nothing");
            handOver("nord");
            publish(earlier, "nord");
            publish(earlier);
            compare(notices.length, 0, "the earlier result sends nothing");
            compare(service.reported, "nord", "the hand-over still waits");
            const answer = { state: "partial", theme: "nord", reason: null };
            publish(answer);
            compare(notices.length, 1, "the next result is the answer");
            compare(JSON.stringify(notices[0]), JSON.stringify(BrowserLogic.applyNotice("nord", answer)));
            compare(service.reported, "");
        }
    }
}
