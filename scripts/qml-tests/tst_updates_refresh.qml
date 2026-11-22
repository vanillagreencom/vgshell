import QtQuick
import QtTest
import Quickshell.Io
import qs.Core
import qs.Commons
import qs.Ui
import qs.Unit
import "../../shell/plugins/vgs.updates" as Updates
import "../../shell/plugins/vgs.updates/UpdatesLogic.js" as Logic

// Drive the production service, window and each separately observed status
// write. Processes and startup reads finish only when the case answers them.
// inputs: shell/plugins/vgs.updates/* shell/Hosts/SummonHost.qml shell/Core/Dispatch.js scripts/qml-tests/stand-ins/Process.qml scripts/qml-tests/stand-ins/FileView.qml
Item {
    id: root
    width: 900
    height: 900
    property var values: ({})
    property var handlers: ({})
    property var observed: []
    property string refuseKey: ""
    property var facade: ({
        settings: {}, screens: { current: null }, system: { state: {} }, tui: { state: {} },
        shortcut: { register: () => "ok" }, surfaces: { hide: () => "ok" },
        ipc: { handle: (name, run) => { root.handlers[name] = run; return "ok"; },
            call: (name, arg) => root.handlers[name] === undefined ? "unknown: " + name : root.handlers[name](arg) },
        status: { viewed: false, handleChoice: () => "ok", isOk: PluginLogic.statusReplyOk,
            get values() { return root.values; },
            set: (key, value) => {
                if (key === root.refuseKey) return "refused: status=test-unavailable";
                root.values = Object.assign({}, root.values, { [key]: value });
                root.observed = root.observed.concat([JSON.parse(JSON.stringify(root.values))]);
                return "ok";
            } }
    })
    Component { id: serviceComponent; Updates.Service {} }
    Component { id: windowComponent; Updates.Window {} }
    UnitCase {
        id: tests
        name: "updates_refresh"
        when: windowShown
        property var service: null
        property var view: null
        function snapshot(count) {
            return JSON.stringify({ checkedAt: Date.now(), error: null,
                sources: [{ source: "pacman", label: "System", count: count, error: null,
                    packages: [{ name: "old-package", old: "1", new: "2" }], checkedAt: Date.now() }] });
        }
        function reader(path) {
            const found = Array.from(service.data).filter(row => row.path === path);
            compare(found.length, 1);
            return found[0];
        }
        function process(name) {
            const found = ProcessRegistry.processes.filter(row => row.running && row.command.some(arg => String(arg).endsWith(name)));
            compare(found.length, 1, name + " has one owner");
            return found[0];
        }
        function checks() {
            return ProcessRegistry.processes.filter(row => row.running && row.command[0].endsWith("bin/check"));
        }
        function admission(value) { process("connectivity.js").finish(0, 0, JSON.stringify({ connectivity: value }), ""); }
        function startup() {
            reader(service.statusPath).finishRead(snapshot(97));
            reader(service.bootPath).finishRead("btime 1\n");
            process("outcome").finish(0, 0, "null", "");
        }
        function init() {
            ProcessRegistry.clear(); root.values = {}; root.observed = []; root.handlers = {}; root.refuseKey = "";
            service = createTemporaryObject(serviceComponent, root);
            service.shell = root.facade;
            view = createTemporaryObject(windowComponent, root);
            // Match the core's post-creation facade assignment: the
            // constructor map turns arrays into QVariant sequences
            // (tst_settingfield's constructor fixture), not native arrays.
            view.shell = root.facade;
        }
        function cleanup() { view.destroy(); service.destroy(); wait(0); }
        function descendants(item) {
            let found = [];
            for (const child of item.children) found = found.concat([child], descendants(child));
            return found;
        }
        function sourceRows() {
            return descendants(view).filter(item => item.expandable !== undefined && item.focusItem !== undefined);
        }
        // The production host's read-then-act phase over Hyprland client
        // fixtures: Updates floats; another floating window above it covers
        // it, and a tiled one holding the keyboard does not. The control
        // judges by keyboard activation, which a tiled window's focus
        // leaves false, so it raises where one click must close.
        function test_toggle_raises_only_a_covered_window_data() {
            const updates = (focus) => ({ address: "0xa1", mapped: true, hidden: false, floating: true, pinned: false, at: [400, 200], size: [800, 600], workspace: { id: 1, name: "1" }, focusHistoryID: focus });
            const terminal = { address: "0xb2", mapped: true, hidden: false, floating: true, pinned: false, at: [500, 300], size: [600, 400], workspace: { id: 1, name: "1" }, focusHistoryID: 0 };
            const tiled = { address: "0xc3", mapped: true, hidden: false, floating: false, pinned: false, at: [0, 40], size: [1920, 1040], workspace: { id: 1, name: "1" }, focusHistoryID: 0 };
            return [
                { tag: "held task terminal above", clients: [updates(1), terminal], raised: true, control: false },
                { tag: "tiled window holds the keyboard", clients: [tiled, updates(1)], raised: false, control: false },
                { tag: "focus-check-control", clients: [tiled, updates(1)], raised: false, control: true }
            ];
        }
        function test_toggle_raises_only_a_covered_window(data) {
            const request = new XMLHttpRequest();
            request.open("GET", Qt.resolvedUrl("../../shell/Hosts/SummonHost.qml"), false);
            request.send();
            verify(request.responseText.length > 0, "read the production host");
            // Mount the shipped owner methods, as tst_polkit_prompt does;
            // the live stacking read is covered by the Updates smoke row.
            const parts = request.responseText.split("\n    Variants {");
            compare(parts.length, 2);
            let methods = parts[0];
            const registration = "    Component.onCompleted: Plugins.registerHost(kind, host)";
            compare(methods.split(registration).length, 2);
            methods = methods.replace(registration, "");
            const judge = "const cover = state.ok ? Dispatch.windowCovered(state.clients, address) : state;";
            compare(methods.split(judge).length, 2, "the control reaches the stacking judge");
            if (data.control) methods = methods.replace(judge, "const cover = { ok: true, covered: !instance.Window.window.active };");
            const host = Qt.createQmlObject(methods.replace("required property string kind", 'property string kind: "window"') + "\n}", root,
                Qt.resolvedUrl("../../shell/Hosts/SummonHost.qml"));
            // A hidden native window supplies Qt's real inactive attached
            // Window, as a tiled window's keyboard focus leaves Updates.
            // https://doc.qt.io/qt-6/qml-qtquick-window.html#active-prop
            const inactive = createTemporaryQmlObject('import QtQuick; import QtQuick.Window; Window { visible: false }', root);
            try {
                view.parent = inactive.contentItem;
                compare(view.Window.window.active, false);
                view.problem = "Keep the current refusal visible.";
                host.requests = { "vgs.updates": { payloadJson: "{}", anchored: false } };
                host.instances = { "vgs.updates": view };
                host.openIds = ["vgs.updates"];
                let focused = 0;
                host.rememberFocuser("vgs.updates", () => { focused += 1; });
                host.toggleRead("vgs.updates", view, "0xa1", { ok: true, clients: data.clients });
                if (data.control) expectFailContinue("", "a focus-only judge raises a window no floating window covers");
                compare([focused, host.openIds.indexOf("vgs.updates") !== -1], data.raised ? [1, true] : [0, false],
                    data.raised ? "a covered window is raised and kept" : "a window in front closes");
                if (data.raised) {
                    compare(host.instances["vgs.updates"], view);
                    compare([view.problem, view.requestState], ["Keep the current refusal visible.", "idle"], "raising keeps the open page's state");
                }
            } finally {
                host.destroy();
                view.parent = root;
            }
        }
        function test_last_run_keeps_title_and_sentence_apart() {
            root.values = { pending: 1, checking: false, lastCheck: Date.now(),
                checkState: { tone: "ok", text: "Updates available" },
                sources: [{ source: "pacman", label: "System", count: 1, error: null, packages: [] }],
                lastRun: { version: 1, ended: "failed", title: "VGS could not restart",
                    text: "Restart the computer when you are ready.", remedy: "computer-restart", endedAt: Date.now() } };
            // Columns apply child visibility and size changes during polish.
            // Wait for all nested positioners before measuring their gap:
            // https://doc.qt.io/qt-6/qml-qttest-testcase.html#waitForPolish-method
            verify(waitForPolish(view.Window.window));
            const labels = displayedTextItems(view);
            const title = labels.find(item => displayedText(item) === root.values.lastRun.title);
            const sentence = labels.find(item => displayedText(item) === root.values.lastRun.text);
            verify(title !== undefined && sentence !== undefined, "the banner renders both stored fields");
            compare(title.role, "bodyStrong");
            compare(sentence.textFormat, Text.PlainText);
            verify(title.mapToItem(view, 0, 0).y < sentence.mapToItem(view, 0, 0).y, "the title stands above its sentence");
            const banner = descendants(view).find(item => item.title === root.values.lastRun.title && item.plain === true);
            verify(banner !== undefined);
            const count = labels.find(item => displayedText(item) === "1 update");
            verify(count !== undefined);
            const countBottom = count.mapToItem(banner.parent, 0, count.height).y;
            verify(banner.y - countBottom >= Theme.stack.page, "the banner keeps the window's block spacing above it");
        }
        // VGS-2622's product result: a short failed-check count beside an
        // upright time in the shared muted ink.
        function test_failed_check_summary_data() {
            return [{ tag: "one", count: 1, summary: "1 check failed" },
                { tag: "several", count: 2, summary: "2 checks failed" }];
        }
        function test_failed_check_summary(data) {
            const now = Time.now.getTime();
            root.values = { lastCheck: now, checking: false, admission: "online",
                checkState: { tone: "warning", text: "Check failed" },
                sources: Array.from({ length: data.count }, (unused, index) =>
                    ({ source: "source-" + index, count: null, error: "exit=1", packages: [] })) };
            const labels = displayedTextItems(view).filter(item => item.role === "hint");
            const time = labels.find(item => displayedText(item).startsWith(" · "));
            verify(time !== undefined, "the summary keeps its time beside it");
            compare(time.text, " · just now");
            verify(Qt.colorEqual(time.color, Theme.color.textMuted));
            compare(time.font.italic, false);
            const summary = labels.find(item => item !== time && item.parent === time.parent);
            compare(displayedText(summary), data.summary);
            compare(summary.lineCount, 1);
        }
        // The production footer stays one keyboard path; checking replaces
        // a source badge with a bare spinner, not a spinner inside a badge.
        function test_flyout_footer_and_checking_row() {
            startup();
            view.width = 700; view.height = 700;
            view.forceActiveFocus();
            wait(0);
            const controls = descendants(view);
            const all = controls.find(item => item.text === "Update all" && item.iconName === "download");
            const refresh = controls.find(item => item.label === "Refresh" && item.iconName === "refresh-cw");
            const log = controls.find(item => item.label === "Open last log" && item.iconName === "scroll-text");
            verify(all !== undefined && refresh !== undefined && log !== undefined);
            compare(all.parent, refresh.parent); compare(refresh.parent, log.parent);
            compare(Math.round(all.y + all.height / 2), Math.round(refresh.y + refresh.height / 2));
            compare(Math.round(refresh.y + refresh.height / 2), Math.round(log.y + log.height / 2));
            compare(refresh.tooltip, "Refresh"); compare(log.tooltip, "Open last log");
            compare(refresh.text, ""); compare(log.text, "");
            verify(all.width > refresh.width);
            let reachedRefresh = false, reachedLog = false;
            for (let step = 0; step < 24 && !(reachedRefresh && reachedLog); step++) {
                keyClick(Qt.Key_Tab);
                reachedRefresh = reachedRefresh || refresh.activeFocus;
                reachedLog = reachedLog || log.activeFocus;
            }
            verify(reachedRefresh && reachedLog, "both icon actions take keyboard focus");
            view.open("{}"); admission(4);
            compare(refresh.lock.locked, true);
            verify(refresh.disabledReason !== "");
            wait(0);
            tryVerify(() => view.rows.length === 1 && sourceRows().length === 1, 1000,
                "the checking view constructs its one cached source row");
            const source = sourceRows()[0];
            const accessories = descendants(source.focusItem);
            const badge = accessories.find(item => item.displayedText !== undefined && item.tone !== undefined);
            const spinner = accessories.find(item => item.running !== undefined && item.size !== undefined);
            verify(badge !== undefined && spinner !== undefined);
            compare(badge.visible, false); compare(spinner.visible, true);
            compare(spinner.parent, badge.parent);
        }
        // Source diagnostics come from bin/check. Their rendered detail
        // adds a known cause alone, or stays absent when none is known.
        function test_failed_source_detail_data() {
            return [
                { tag: "unknown", error: "exit=1 network down", detail: "" },
                { tag: "absent", error: null, detail: "" },
                { tag: "timeout", error: "timeout=120", detail: "The update check took too long." },
                { tag: "missing tool", error: "helper-missing=checkupdates", detail: "A tool needed for this check is missing." }
            ];
        }
        function test_failed_source_detail(data) {
            view.width = 700;
            root.values = { checking: false, checkState: { tone: "warning", text: "System failed" },
                sources: [{ source: "pacman", label: "System", count: null, error: data.error, packages: [] }] };
            tryVerify(() => view.rows.length === 1 && sourceRows().length === 1, 1000);
            const row = sourceRows()[0];
            compare(view.rows[0].detail, data.detail);
            compare(row.expandable, data.detail !== "");
            compare(row.expanded, data.detail !== "");
            const details = displayedTextItems(row).filter(item => item.role === "hint");
            compare(details.map(item => displayedText(item)), data.detail === "" ? [] : [data.detail]);
        }
        function test_flyout_fits_content_up_to_cap() {
            startup();
            view.width = 700;
            view.height = Qt.binding(() => view.implicitHeight);
            tryVerify(() => sourceRows().length === 1, 1000);
            const cap = Math.floor(Math.min(Theme.size.panel.maxHeight, OverlayState.windowRoom(view.screen).height));
            const footer = descendants(view).find(item => item.text === "Update all" && item.iconName === "download").parent;
            const compact = view.implicitHeight;
            verify(compact > 0 && compact < cap, "one collapsed source fits below the cap");
            sourceRows()[0].expanded = true;
            tryVerify(() => view.implicitHeight > compact, 1000, "expanded package content grows the fitted window");
            const packages = Array.from({ length: 100 }, (unused, index) => ({ name: "package-" + index, old: "1", new: "2" }));
            // The service limits each published package list. Several
            // expanded package sources reach the real overflowing state.
            const now = Date.now();
            const sources = ["pacman", "aur", "flatpak"].map(source => Logic.sourceRow(source, packages.length, packages, now, null));
            root.values = Logic.publishValues({ checkedAt: now, error: null, sources: sources }, false, now, 0, "", "", "online");
            tryVerify(() => sourceRows().length === sources.length && view.rows.every(row => row.lines.length > 0), 1000);
            for (const row of sourceRows()) row.expanded = true;
            tryCompare(view, "implicitHeight", cap);
            const pane = descendants(view).find(item => item.scrollArea !== undefined && item.footerHeight !== undefined);
            verify(pane.scrollArea.contentHeight > pane.scrollArea.height, "overflow stays scrollable");
            const footerTop = footer.mapToItem(view, 0, 0).y;
            verify(footerTop >= 0 && footerTop + footer.height <= view.height, "the footer stays inside the capped window");
        }
        function test_open_waits_for_startup_and_never_unmasks_a_mixed_result() {
            view.open("{}");
            compare(view.view.state, "checking", "the opening frame is masked before startup reads answer");
            // The independent last-run read may run while refresh admission waits.
            compare(checks().length, 0, "startup reads precede every check");
            compare(ProcessRegistry.processes.filter(row => row.running && row.command.some(arg => String(arg).endsWith("connectivity.js"))).length,
                0, "startup reads precede connectivity admission");
            startup();
            compare(checks().length, 0, "admission precedes every check");
            admission(4);
            compare(service.requestCheck("ipc"), "queued", "open/manual requests join this refresh");
            const during = Logic.windowRows(root.values)[0];
            compare([during.spinning, during.badge, during.lines.length, during.detail, during.more, during.updatable], [true, "", 0, "", "", false]);
            compare(Logic.widgetView(root.values, false).badge, "");
            process("bin/check").finish(0, 0, snapshot(3), "");
            compare(service.checking, false);
            compare(root.values.pending, 3);
            compare(Logic.windowRows(root.values)[0].badge, "3");
            for (const values of root.observed) {
                if (values.checking === true) {
                    compare(Logic.widgetView(values, false).badge, "");
                    for (const row of Logic.windowRows(values))
                        compare([row.spinning, row.badge, row.lines.length, row.updatable], [true, "", 0, false]);
                } else if (values.admission === "online") {
                    compare(values.pending, 3, "no publication exposes an old total as the new answer");
                    compare(values.sources[0].count, 3);
                }
            }
            compare(checks().length, 0, "joining did not queue a duplicate");
        }
        function test_offline_and_unavailable_never_start_a_check_data() {
            return [{ tag: "none", value: 1, state: "offline" }, { tag: "portal", value: 2, state: "offline" },
                { tag: "limited", value: 3, state: "offline" }, { tag: "unknown", value: 0, state: "unavailable" },
                { tag: "unread", value: null, state: "unavailable" }];
        }
        function test_offline_and_unavailable_never_start_a_check(data) {
            startup(); view.open("{}"); admission(data.value);
            compare(root.values.admission, data.state);
            compare(service.checking, false); compare(checks().length, 0);
            compare(root.values.pending, 97);
            verify(Logic.lastKnown(root.values));
            compare(Logic.windowRows(root.values)[0].updatable, false);
            verify(Logic.updateDisabledReason(root.values) !== "");
            view.refresh(); admission(4);
            compare(checks().length, 1, "Refresh retries the same admission path");
        }
        // A TUI run ends: the service reads its outcome, and starts the
        // run's check unless the run asked it.
        function endRun(endedAt) {
            service.shell = Object.assign({}, root.facade, { tui: { state: { update: { running: false, endedAt: endedAt } } } });
        }
        function test_a_run_that_checked_starts_no_second_check() {
            startup(); view.open("{}"); admission(4);
            compare(root.facade.ipc.call("check", "run"), "queued", "the run's own check joins the open's refresh");
            process("bin/check").finish(0, 0, snapshot(3), "");
            compare(root.values.checking, true);
            compare(root.values.pending, 97, "a refresh the run's check joined is replaced, never published");
            admission(4); process("bin/check").finish(0, 0, snapshot(2), "");
            compare(root.values.pending, 2);
            endRun(1);
            compare(service.checking, false, "the run's end starts no third check");
            compare(checks().length, 0);
            const outcome = { version: 1, ended: "failed", title: "Flatpak failed", text: "Update again.", remedy: "", endedAt: 1000 };
            process("outcome").finish(0, 0, JSON.stringify(outcome), "");
            compare(root.values.lastRun, outcome, "the run's outcome is published");
            endRun(2);
            admission(4);
            compare(checks().length, 1, "a run that asked no check gets one at its end");
        }
        // The package log's two views: the watch keeps its path, and the
        // reader holds it only while a read is out.
        function packageLogView(watching) {
            const found = Array.from(service.data).filter(row => row.path === service.packageLogPath && row.watchChanges === watching);
            compare(found.length, 1);
            return found[0];
        }
        function readPackageLog(text) {
            const file = packageLogView(false);
            if (text === null) file.failRead(FileViewError.FileNotFound);
            else file.finishRead(text);
        }
        // The settle wait ends at once; `changed` requires a change to have
        // started it.
        function settle(changed) {
            const timer = Array.from(service.data).find(row => row.objectName === "packageLogSettle");
            if (changed) verify(timer.running, "a log change waits for the log to settle");
            timer.stop();
            timer.triggered();
        }
        function requests() {
            return ProcessRegistry.processes.filter(row => row.running && row.command.some(arg => String(arg).endsWith("connectivity.js"))).length;
        }
        function completed(second) { return "[2026-11-21T05:50:" + second + "-0800] [ALPM] transaction completed\n"; }
        function startTui(name) {
            service.shell = Object.assign({}, root.facade, { tui: { state: { [name]: { running: true, endedAt: null } } } });
        }
        // An install outside the window reaches the count; the log's
        // content at the first read is history and starts nothing.
        function test_package_log_transaction_requests_one_check_data() {
            const history = "[2026-11-21T05:50:20-0800] [ALPM] transaction started\n" + completed(21)
                + "[2026-11-21T05:50:22-0800] [ALPM] running 'a.hook'...\n";
            return [
                { tag: "completed line appended", first: history, next: history + "[2026-11-21T05:50:30-0800] [ALPM] transaction started\n" + completed(31), checks: 1 },
                { tag: "other lines appended", first: history, next: history + "[2026-11-21T05:50:30-0800] [PACMAN] synchronizing package lists\n", checks: 0 },
                { tag: "second commit in the same second", first: history, next: history + completed(21), checks: 1 },
                { tag: "log replaced", first: history, next: completed(40), checks: 1 },
                { tag: "log emptied", first: history, next: "", checks: 0 },
                { tag: "log created", first: null, next: completed(40), checks: 1 }
            ];
        }
        function test_package_log_transaction_requests_one_check(data) {
            startup();
            readPackageLog(data.first);
            compare(requests(), 0, "the log's history starts no check");
            packageLogView(true).change();
            settle(true);
            readPackageLog(data.next);
            compare(requests(), data.checks);
        }
        // An update run's own check covers its transactions: they start no
        // other check, before it or after it, and a burst after the run is
        // one check.
        function test_package_log_window_job_and_burst() {
            startup();
            let log = completed(21);
            readPackageLog(log);
            startTui("update");
            log += completed(30);
            packageLogView(true).change();
            settle(false);
            readPackageLog(log);
            compare(requests(), 0, "a transaction before the run's check starts no check");
            log += completed(31);
            compare(root.facade.ipc.call("check", "run"), "started");
            readPackageLog(log);
            admission(4); process("bin/check").finish(0, 0, snapshot(1), "");
            compare(service.checking, false, "the run's transactions start no second check");
            endRun(1);
            compare(requests(), 0, "the run's end starts no check");
            for (const second of [40, 41, 42]) {
                log += completed(second);
                packageLogView(true).change();
            }
            settle(true);
            readPackageLog(log);
            compare(requests(), 1, "a burst of transactions is one check");
        }
        // A run stopped before its own check gets one at its TUI's end, which
        // covers the run's transactions.
        function test_package_log_run_stopped_before_its_check() {
            startup();
            let log = completed(21);
            readPackageLog(log);
            startTui("update");
            log += completed(30);
            endRun(1);
            readPackageLog(log);
            compare(requests(), 1, "the TUI's end checks once");
            admission(4); process("bin/check").finish(0, 0, snapshot(1), "");
            log += "[2026-11-21T05:50:40-0800] [PACMAN] synchronizing package lists\n";
            packageLogView(true).change();
            settle(true);
            readPackageLog(log);
            compare(requests(), 0, "the run's transactions start no second check");
        }
        // An outside install while a TUI stays open is checked: after the
        // run's own check, at its close prompt, or while the log viewer is
        // open.
        function test_package_log_outside_transaction_while_a_tui_is_open_data() {
            return [
                { tag: "after the run's own check", tui: "update", ranCheck: true },
                { tag: "after a source run's own check", tui: "update-source", ranCheck: true },
                { tag: "log viewer open", tui: "log", ranCheck: false }
            ];
        }
        function test_package_log_outside_transaction_while_a_tui_is_open(data) {
            startup();
            let log = completed(21);
            readPackageLog(log);
            startTui(data.tui);
            if (data.ranCheck) {
                compare(root.facade.ipc.call("check", "run"), "started");
                readPackageLog(log);
                admission(4); process("bin/check").finish(0, 0, snapshot(1), "");
                compare(service.checking, false);
            }
            log += completed(40);
            packageLogView(true).change();
            settle(true);
            readPackageLog(log);
            compare(requests(), 1);
        }
        // A check already out may have read the packages before the
        // transaction: it is replaced once.
        function test_package_log_transaction_during_a_check_replaces_it() {
            startup();
            let log = completed(21);
            readPackageLog(log);
            compare(root.facade.ipc.call("check", ""), "started");
            log += completed(30);
            packageLogView(true).change();
            settle(true);
            readPackageLog(log);
            admission(4); process("bin/check").finish(0, 0, snapshot(3), "");
            compare(root.values.pending, 97, "the replaced result is never published");
            compare(requests(), 1, "the replacement starts");
        }
        // expected-log: updates: refused: status=test-unavailable -- planted publication failure
        function test_refused_publication_never_clears_the_mask() {
            startup(); view.open("{}"); admission(4);
            root.refuseKey = "sources";
            process("bin/check").finish(0, 0, snapshot(3), "");
            compare(root.values.checking, true); compare(service.checking, true);
            compare(Logic.windowRows(root.values)[0].badge, "");
        }
    }
}
