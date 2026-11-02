import QtQuick
import QtTest
import qs.Commons
import qs.Unit
import Quickshell
import "../../shell/plugins/vgs.themes" as Themes
import "../../shell/plugins/vgs.themes/BrowserLogic.js" as BrowserLogic

// The themes service's hand-over notice and its reads of the browsers'
// data. The theme browser closes on the publish of an apply it ran and
// hands the answer to the service through `report-apply`; the next apply
// result is that apply's, and a failed or partial one becomes one notice.
// The browsers' data, the theme list, every image and the catalog, is read
// on no timer: a round of the three reads runs at registration and once per
// opened view, and, only while a view is open, once per watched change,
// once per change fired in one turn and once per theme document. A watched
// change is the line or lines helper/watch.py prints for it, said on the
// stdout of the service's one watch Process, which runs from registration
// and starts again after an exit a bounded number of times. The fake
// shell lists an installed package with its images, a refused installed
// package and a shipped package the first shadows, counts and answers each
// read, records each IPC handler and each notice, and publishes `last`
// through a getter over a QtObject property, as ThemeRunner's provider
// does. A view's fake shell routes its IPC calls to the recorded handlers
// and answers `unknown:` once a test ends, as the core does for a service
// that is gone.
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

    Component {
        id: dataComponent
        Themes.BrowserData {}
    }

    TestCase {
        id: tests
        name: "themesService"

        property var service: null
        property var handlers: ({})
        property var notices: []
        property int listCalls: 0
        property int imagesCalls: 0
        property int catalogCalls: 0
        property var imageList: []

        readonly property string packageDir: Paths.configDir + "/themes/dusk"
        readonly property string refusedDir: Paths.configDir + "/themes/broken"
        readonly property string shadowedDir: Quickshell.shellDir + "/../themes/dusk"

        function fakeShell() {
            return {
                settings: {},
                tui: { state: {} },
                requirements: { revision: 0 },
                shortcut: { register: (name, description, run) => "ok" },
                ipc: { handle: (name, handler) => { tests.handlers[name] = handler; return "ok"; } },
                theme: {
                    get last() { return store.last; },
                    listing: { file: null, packages: [
                        { name: "broken", displayName: null, source: "installed", state: "refused", reason: "package-theme", path: tests.refusedDir },
                        { name: "dusk", displayName: null, source: "installed", state: "ok", reason: null, path: tests.packageDir },
                        { name: "dusk", displayName: null, source: "shipped", state: "shadowed", reason: null, path: tests.shadowedDir }
                    ] },
                    list: done => { tests.listCalls++; done({ reason: null }); },
                    images: (scope, done) => {
                        tests.imagesCalls++;
                        done({ state: "ok", images: tests.imageList, reason: null });
                        return "ok";
                    },
                    catalog: done => { tests.catalogCalls++; done({ entries: [], reason: null }); }
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

        // Wait for `count` rounds to end, then give a further round time to
        // start, and require exactly `count` of each read.
        function expectRounds(count, why) {
            tryVerify(() => listCalls >= count && imagesCalls >= count && catalogCalls >= count, 1000, why);
            wait(50);
            compare(listCalls, count, why + ": theme list reads");
            compare(imagesCalls, count, why + ": image list reads");
            compare(catalogCalls, count, why + ": catalog reads");
        }

        function image(file) {
            return { background: file, theme: "dusk", name: file, path: packageDir + "/backgrounds/" + file };
        }

        // A view's shell, whose calls reach the handlers the service
        // recorded while this test runs.
        function viewShell() {
            return { ipc: { call: (name, argument) => handlers[name] === undefined ? "unknown: handler=" + name : handlers[name](argument) } };
        }

        // A view that opened, with its opening read done and counted out.
        function openView() {
            const view = createTemporaryObject(dataComponent, root, { shell: viewShell() });
            verify(view !== null);
            expectRounds(1, "an opened view");
            clearCalls();
            return view;
        }

        // The watch helper's lines: a list change, and a change naming the
        // packages in `names`, "" for the user images.
        readonly property var listed: ({ list: true, names: [] })
        function named(names) { return { list: false, names: names }; }

        // Say `lines` on the watch helper's stdout in one turn, and raise
        // the theme document when `document` is set, as an apply's writes
        // do.
        function fire(lines, document) {
            const parser = watchProcess().stdout;
            for (const line of lines) parser.read(JSON.stringify(line));
            if (document) compare(UnitTheme.override({ palette: { accent: "#123456" } }), "ok");
        }

        function clearCalls() {
            listCalls = 0;
            imagesCalls = 0;
            catalogCalls = 0;
        }

        // Every object in `top`'s tree: its lists, Variants instances
        // included, and its object-valued properties, such as a Process's
        // stdout. `parent` leads out of the tree and Connections' `target`
        // to a singleton, so neither is followed.
        function treeOf(top) {
            const seen = new Set();
            const stack = [top];
            while (stack.length > 0) {
                const object = stack.pop();
                if (object === null || typeof object !== "object" || seen.has(object)) continue;
                if (!("objectName" in object)) {
                    if (typeof object.length === "number") for (let i = 0; i < object.length; i++) stack.push(object[i]);
                    continue;
                }
                seen.add(object);
                for (const key of Object.keys(object)) {
                    if (key === "parent" || key === "target") continue;
                    const value = object[key];
                    if (value !== null && typeof value === "object") stack.push(value);
                }
            }
            return Array.from(seen);
        }

        // Why `object` reads on its own, or "" when it does not: a running
        // or repeating object with a positive interval, a Timer among them,
        // or a set polling flag.
        function pollsOnItsOwn(object) {
            if (typeof object.interval === "number" && object.interval > 0
                && (object.running === true || object.repeat === true || object.active === true))
                return "interval=" + object.interval + " running=" + object.running + " repeat=" + object.repeat;
            for (const key of Object.keys(object))
                if (/poll/i.test(key) && typeof object[key] !== "function" && object[key])
                    return key + "=" + object[key];
            return "";
        }

        // The service's one Process running helper/watch.py.
        function watchProcess() {
            const found = treeOf(service).filter(object => Array.isArray(object.command)
                && object.command.some(word => String(word).endsWith("/helper/watch.py")));
            compare(found.length, 1, "one watch helper Process");
            return found[0];
        }

        function init() {
            store.last = Object.freeze({ applying: null, result: null, downloading: null });
            imageList = [image("dawn.png")];
            handlers = {};
            notices = [];
            clearCalls();
            service = createTemporaryObject(serviceComponent, root);
            verify(service !== null);
            // The core assigns the scoped shell after creation.
            service.shell = fakeShell();
            verify(typeof handlers["report-apply"] === "function", "the service registers report-apply");
            expectRounds(1, "registration");
            clearCalls();
        }

        function cleanup() {
            handlers = {};
            UnitTheme.reset();
        }

        // Nothing in the service reads on its own: no Timer or other object
        // runs or repeats on an interval, and no object polls. No FileView
        // watches a path, as each held an inotify instance of its own: the
        // one watch is the helper, which runs from registration on the
        // config folder and the catalog. The walk must reach the helper
        // Process and its stdout, or it proves nothing. With nothing
        // changed and no view open, a second then passes with no read.
        function test_nothing_reads_while_nothing_changes() {
            const tree = treeOf(service);
            for (const object of tree) {
                const why = pollsOnItsOwn(object);
                compare(why, "", "an object reads on its own: " + String(object));
            }
            compare(tree.filter(object => object.watchChanges === true).map(object => object.path), [], "no FileView watches a path");
            const helper = watchProcess();
            compare(helper.command.slice(2), [Paths.configDir, Quickshell.shellDir + "/../themes/catalog"], "the helper watches the config folder and the catalog");
            compare(helper.command[0], "python3");
            verify(helper.running, "the helper runs from registration");
            verify(tree.indexOf(helper.stdout) !== -1, "the walk reaches the helper's stdout");
            wait(1000);
            compare(listCalls + imagesCalls + catalogCalls, 0, "no read while nothing changes");
        }

        // The ready line reads nothing, a view open or not: registration
        // and the view's opening already read.
        function test_the_ready_line_reads_nothing_data() {
            return [
                { tag: "a view open", open: true },
                { tag: "no view open", open: false }
            ];
        }

        function test_the_ready_line_reads_nothing(data) {
            if (data.open) openView();
            fire([{ ready: true }]);
            expectRounds(0, "the ready line");
        }

        // A name marks that package's images replaced, "" the user images',
        // once per line naming it, with no view open too, where it reads
        // nothing; a list line marks none.
        function test_a_name_marks_its_images_replaced_data() {
            return [
                { tag: "a package", lines: [named(["dusk"])], want: { dusk: 1 } },
                { tag: "the user images", lines: [named([""])], want: { "": 1 } },
                { tag: "two packages in one line", lines: [named(["broken", "dusk"])], want: { broken: 1, dusk: 1 } },
                { tag: "a package in two lines", lines: [named(["dusk"]), named(["dusk"])], want: { dusk: 2 } },
                { tag: "a list change", lines: [listed], want: {} }
            ];
        }

        function test_a_name_marks_its_images_replaced(data) {
            fire(data.lines);
            compare(JSON.stringify(service.generations), JSON.stringify(data.want), "the generations");
            expectRounds(0, data.tag + " with no view open");
        }

        // A helper that ends, by an exit or a failed start, is logged and
        // started again, watchRestartLimit times per registration, and no
        // more: then it stays down.
        // expected-log: themes: watch=ended exit=1 status=0 stderr="watch.py: watch=failed reason=init: Too many open files" restart=1/3 -- the helper's setup failure, logged with its line
        // expected-log: themes: watch=ended exit=not-started restart=2/3 -- a start that failed
        // expected-log: themes: watch=ended exit=-1 status=1 stderr="" restart=3/3 -- a helper killed
        // expected-log: themes: watch=stopped exit=1 status=0 stderr="watch.py: watch=failed reason=init: Too many open files" restarts=3 -- the bound spent
        function test_a_helper_that_ends_starts_again_a_bounded_number_of_times() {
            const helper = watchProcess();
            compare(service.watchRestartLimit, 3, "the bound these lines name");
            const failure = "watch.py: watch=failed reason=init: Too many open files\n";
            helper.finish(1, 0, "", failure);
            verify(helper.running, "the first exit starts the helper again");
            helper.failStart();
            verify(helper.running, "a failed start starts the helper again");
            helper.finish(-1, 1, "", "");
            verify(helper.running, "the third end starts the helper again");
            helper.finish(1, 0, "", failure);
            verify(!helper.running, "the fourth end leaves the helper down");
            compare(service.watchRestarts, 3, "three restarts");
        }

        // Each source's change as the helper prints it: one line for a
        // write in place, one per kernel read for a file replaced by
        // rename or a package copied in; a shell.json save, two list lines,
        // and an apply, which renames the theme file into Paths.configDir,
        // two list lines and a new theme document revision. Each reads
        // once while a view is open and not at all while none is.
        function test_a_watched_change_data() {
            const changes = [
                { tag: "the installed themes folder", lines: [listed, named(["new"])] },
                { tag: "the user images folder", lines: [named([""])] },
                { tag: "the catalog index", lines: [listed] },
                { tag: "a package's theme.json", lines: [named(["dusk"]), named(["dusk"])] },
                { tag: "a package's terminal.json", lines: [named(["dusk"])] },
                { tag: "a package's preview", lines: [named(["dusk"]), named(["dusk"])] },
                { tag: "a package's backgrounds", lines: [named(["dusk"])] },
                { tag: "a refused package's theme.json", lines: [named(["broken"])] },
                { tag: "a refused package's terminal.json", lines: [named(["broken"])] },
                { tag: "an image", lines: [named(["dusk"]), named(["dusk"])] },
                { tag: "a save under the config folder", lines: [listed, listed] },
                { tag: "a new theme document", lines: [], document: true },
                { tag: "a theme apply", lines: [listed, listed], document: true }
            ];
            const rows = [];
            for (const change of changes) {
                rows.push(Object.assign({}, change, { tag: change.tag + ", a view open", open: true, rounds: 1 }));
                rows.push(Object.assign({}, change, { tag: change.tag + ", no view open", open: false, rounds: 0 }));
            }
            return rows;
        }

        function test_a_watched_change(data) {
            if (data.open) openView();
            fire(data.lines, data.document === true);
            expectRounds(data.rounds, data.tag);
        }

        // A view that opens after changes made while none was open reads
        // once and shows them.
        function test_a_view_opened_after_a_change_shows_it() {
            imageList = [image("dawn.png"), image("noon.png")];
            fire([named(["dusk"]), listed], true);
            expectRounds(0, "changes with no view open");
            const view = openView();
            const want = JSON.stringify(imageList);
            tryVerify(() => view.snapshot !== null && JSON.stringify(view.snapshot.images.images) === want, 1000, "the opened view shows the changed images");
        }

        // A view's destruction closes it: a change after the last view
        // closed reads nothing, and one view's close leaves another open,
        // as when the overlay switches from one view to the other.
        function test_a_closed_view_reads_nothing_data() {
            return [
                { tag: "the only view closed", views: 1, closed: 1, rounds: 0 },
                { tag: "one of two views closed", views: 2, closed: 1, rounds: 1 },
                { tag: "both views closed", views: 2, closed: 2, rounds: 0 }
            ];
        }

        function test_a_closed_view_reads_nothing(data) {
            const views = [];
            for (let i = 0; i < data.views; i++) views.push(openView());
            for (let i = 0; i < data.closed; i++) views[i].destroy();
            tryVerify(() => Object.keys(service.openViews).length === data.views - data.closed, 1000, "the closed views leave the service");
            fire([listed]);
            expectRounds(data.rounds, data.tag);
        }

        // A view that started before the service registered opens on a
        // later poll, so a change then reads for it.
        function test_a_view_started_before_registration_opens_later() {
            let registered = false;
            const call = (name, argument) => !registered || handlers[name] === undefined ? "unknown: handler=" + name : handlers[name](argument);
            const view = createTemporaryObject(dataComponent, root, { shell: { ipc: { call: call } } });
            verify(view !== null);
            registered = true;
            tryVerify(() => view.opened, 1000, "the view opens once the service answers");
            expectRounds(1, "the late opening");
            clearCalls();
            fire([listed]);
            expectRounds(1, "a change with the late view open");
        }

        function test_opening_a_view_reads_once_data() {
            return [
                { tag: "registered", registered: true, rounds: 1 },
                { tag: "not registered", registered: false, rounds: 0 }
            ];
        }

        // An opened view asks once, a later read and a new shell ask
        // nothing, and a view opened before the service registered reads
        // nothing and logs nothing.
        function test_opening_a_view_reads_once(data) {
            const call = (name, argument) => !data.registered || handlers[name] === undefined
                ? "unknown: handler=" + name : handlers[name](argument);
            const view = createTemporaryObject(dataComponent, root, { shell: { ipc: { call: call } } });
            verify(view !== null);
            expectRounds(data.rounds, "an opened view");
            compare(view.snapshot !== null, data.registered, "the view reads the retained answer");
            view.read();
            view.shell = { ipc: { call: call } };
            wait(300);
            compare(listCalls + imagesCalls + catalogCalls, 3 * data.rounds, "a later read asks no new round");
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
            compare(JSON.stringify(notices[0]), JSON.stringify(BrowserLogic.applyNotice("nord", data.result, null)));
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
            compare(JSON.stringify(notices[0]), JSON.stringify(BrowserLogic.applyNotice("nord", answer, null)));
            compare(service.reported, "");
        }
    }
}
