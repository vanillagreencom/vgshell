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
// inputs: shell/plugins/vgs.updates/* scripts/qml-tests/stand-ins/Process.qml scripts/qml-tests/stand-ins/FileView.qml
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
        function test_last_run_keeps_title_and_sentence_apart() {
            root.values = { pending: 1, checking: false, lastCheck: Date.now(),
                checkState: { tone: "ok", text: "Updates available" },
                sources: [{ source: "pacman", label: "System", count: 1, error: null, packages: [] }],
                lastRun: { version: 1, ended: "failed", title: "VGS could not restart",
                    text: "Restart the computer when you are ready.", remedy: "computer-restart", endedAt: Date.now() } };
            const labels = displayedTextItems(view);
            const title = labels.find(item => displayedText(item) === root.values.lastRun.title);
            const sentence = labels.find(item => displayedText(item) === root.values.lastRun.text);
            verify(title !== undefined && sentence !== undefined, "the banner renders both stored fields");
            compare(title.role, "bodyStrong");
            compare(sentence.role, "body");
            compare(sentence.textFormat, Text.PlainText);
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
            compare(ProcessRegistry.processes.filter(row => row.running).length, 0);
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
            service.shell = Object.assign({}, root.facade, { tui: { state: { "vgs.updates/update": { running: false, endedAt: endedAt } } } });
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
