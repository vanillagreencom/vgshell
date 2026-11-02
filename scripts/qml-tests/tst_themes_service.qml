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
// once per change fired in one turn and once per theme document. The fake
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
        readonly property string imagePath: packageDir + "/backgrounds/dawn.png"
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

        // Fire `paths`' watches in one turn, and the theme document when
        // `document` is set, as an apply's writes do.
        function fire(paths, document) {
            for (const view of paths.map(path => viewAt(path))) view.change();
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

        function viewAt(path) {
            const views = treeOf(service).filter(object => object.path === path && typeof object.change === "function");
            compare(views.length, 1, "one watch on " + path);
            return views[0];
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
        // runs or repeats on an interval, and no object polls. The walk
        // must reach every watch, a Variants instance and a Process's
        // stdout, or it proves nothing. A shadowed package is never read, so
        // nothing watches it. With nothing changed and no view open, a
        // second then passes with no read.
        function test_nothing_reads_while_nothing_changes() {
            const tree = treeOf(service);
            for (const object of tree) {
                const why = pollsOnItsOwn(object);
                compare(why, "", "an object reads on its own: " + String(object));
            }
            const paths = tree.map(object => object.path).filter(path => typeof path === "string");
            for (const path of [Paths.configDir + "/themes", Paths.configDir + "/backgrounds", packageDir + "/theme.json", packageDir + "/backgrounds", imagePath])
                verify(paths.indexOf(path) !== -1, "the walk reaches the watch on " + path);
            compare(paths.filter(path => path.startsWith(shadowedDir)).length, 0, "no watch on a shadowed package");
            verify(paths.some(path => path.endsWith("/themes/catalog/index.json")), "the walk reaches the catalog index watch");
            verify(tree.some(object => object.stdout !== undefined && object.stdout !== null && tree.indexOf(object.stdout) !== -1),
                   "the walk reaches a Process's stdout");
            wait(1000);
            compare(listCalls + imagesCalls + catalogCalls, 0, "no read while nothing changes");
        }

        // Each source's watch, the two folder views under Paths.configDir
        // that one change there fires (a shell.json save), and an apply,
        // which renames the theme file into Paths.configDir, firing both
        // folder views for each of its two entry events, and raises the
        // theme document revision. Each reads once while a view is open and
        // not at all while none is.
        function test_a_watched_change_data() {
            const dir = Paths.configDir;
            const changes = [
                { tag: "the installed themes folder", paths: [dir + "/themes"] },
                { tag: "the user images folder", paths: [dir + "/backgrounds"] },
                { tag: "the catalog index", paths: [Quickshell.shellDir + "/../themes/catalog/index.json"] },
                { tag: "a package's theme.json", paths: [packageDir + "/theme.json"] },
                { tag: "a package's terminal.json", paths: [packageDir + "/terminal.json"] },
                { tag: "a package's preview", paths: [packageDir + "/preview.jpg"] },
                { tag: "a package's backgrounds", paths: [packageDir + "/backgrounds"] },
                { tag: "a refused package's theme.json", paths: [refusedDir + "/theme.json"] },
                { tag: "a refused package's terminal.json", paths: [refusedDir + "/terminal.json"] },
                { tag: "an image", paths: [imagePath] },
                { tag: "a save under the config folder", paths: [dir + "/themes", dir + "/backgrounds"] },
                { tag: "a new theme document", paths: [], document: true },
                { tag: "a theme apply", paths: [dir + "/themes", dir + "/backgrounds", dir + "/themes", dir + "/backgrounds"], document: true }
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
            fire(data.paths, data.document === true);
            expectRounds(data.rounds, data.tag);
        }

        // A view that opens after changes made while none was open reads
        // once and shows them.
        function test_a_view_opened_after_a_change_shows_it() {
            const dir = Paths.configDir;
            imageList = [image("dawn.png"), image("noon.png")];
            fire([dir + "/backgrounds", dir + "/themes"], true);
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
            fire([Paths.configDir + "/themes"]);
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
            fire([Paths.configDir + "/themes"]);
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
