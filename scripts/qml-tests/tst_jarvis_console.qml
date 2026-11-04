import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit
import "../../shell/plugins/vgs.jarvis"
import "../../shell/plugins/vgs.jarvis/Session.js" as Session

// The Jarvis console's state lines under its purpose, over a stand-in
// `shell`: the bar's state, the action a problem names and the AI model
// each draw as a line of their own, and the action's page reference
// reaches a link, never its raw form. Composer replacements retain a visible
// keyboard target and leave another tab or control's focus alone. Each
// History task row offers its own Open and Stop, with no selection.
Item {
    id: root
    width: 760
    height: 900

    property var opened: []
    property var recoveryConsole: null
    property int destroyedRecoveryConsoles: 0

    // Status values over Session's initial record with REGIONS set, the
    // AI model the daemon names beside it.
    function values(regions) {
        const s = Object.assign(JSON.parse(JSON.stringify(Session.initial())), { gate: { kind: "up" } }, regions);
        return { daemon: { tone: "info", text: "Jarvis is ready; microphone is off" }, audio: { tone: "ok", text: "Device list ready" },
            detail: { phase: Session.phaseOf(s), seq: 1, state: s, brain: "Claude Opus 5.5" } };
    }

    function shellWith(values) {
        return {
            screens: { current: null },
            status: { values: values },
            session: { locked: false },
            settings: { mode: "hold", voiceProvider: "gemini", home: "" },
            shortcut: { keys: { talk: "SUPER+code:44", mute: "SUPER+SHIFT+code:44", stop: "SUPER+ALT+PERIOD", confirm: "SUPER+ALT+Y", console: "SUPER+ALT+C" } },
            ipc: { call: (name, arg) => "ok" },
            surfaces: { openPage: (page, tab) => { root.opened = root.opened.concat([[page, tab]]); } }
        };
    }

    Console { id: jarvisConsole; anchors.fill: parent }
    // Component-created objects accept destroy(); the declaration's context
    // outlives both real Console instances.
    // https://doc.qt.io/qt-6/qtqml-javascript-dynamicobjectcreation.html#deleting-objects-dynamically
    Component {
        id: recoveryConsoleComponent
        Console { anchors.fill: parent; Component.onDestruction: root.destroyedRecoveryConsoles++ }
    }
    Button { id: outside; text: "Outside Console" }

    TestCase {
        name: "jarvisConsole"
        when: windowShown

        function init() {
            UnitTheme.reset();
            root.opened = [];
            jarvisConsole.tab = 0;
            jarvisConsole.historyType = 0;
            jarvisConsole.shell = root.shellWith(root.values({}));
            wait(0); // Drain the tab's queued focus before each case chooses its control.
            outside.forceActiveFocus();
        }

        function collect(node, test, out) {
            if (test(node)) out.push(node);
            for (const child of node.children) collect(child, test, out);
            return out;
        }
        function shownText() {
            return collect(jarvisConsole, n => n instanceof Text && n.visible && n.opacity > 0 && n.text !== "", []).map(n => n.text);
        }
        function links() {
            return collect(jarvisConsole, n => n.focusPreview !== undefined && n.linkColor !== undefined && n.visible, []);
        }

        function composerControls() {
            const all = collect(jarvisConsole, n => true, []);
            const stops = all.filter(n => n.label === "Stop Jarvis");
            return {
                entry: all.find(n => n.placeholderText === "Message Jarvis"),
                send: all.find(n => n.text === "Send"),
                info: all.find(n => n.title === "Message length"),
                speechStop: stops[0], typedStop: stops[1],
                speechHint: all.find(n => n.linkColor !== undefined && n.text === jarvisConsole.speechOnlyText),
                tabs: all.find(n => n.model !== undefined && Array.isArray(n.model) && n.model[0] === "Now")
            };
        }

        function cleanup() {
            if (root.recoveryConsole !== null) {
                root.recoveryConsole.destroy();
                root.recoveryConsole = null;
            }
            jarvisConsole.visible = true;
            wait(0);
        }

        function test_ask_recovery_survives_console_recreation_data() {
            return ["first-pending", "unknown", "retry-pending"].map(kind => ({ tag: kind, kind: kind }));
        }
        function test_ask_recovery_survives_console_recreation(data) {
            jarvisConsole.visible = false;
            const request = { action: "reply", id: "ask", requestId: "retained-reply", expectedRevision: "one",
                text: "Keep this answer in the original thread.", until: null };
            const shell = root.shellWith(root.values({}));
            shell.status.values.ownerAsks = null;
            shell.status.values.ownerAskAnswer = { kind: data.kind, home: "", request: request, result: null };
            const sent = [];
            shell.ipc.call = (name, arg) => { if (name === "owner-ask-action") sent.push(JSON.parse(arg)); return "ok"; };
            function createConsole() {
                root.recoveryConsole = recoveryConsoleComponent.createObject(root, { shell: shell });
                verify(root.recoveryConsole !== null);
                root.recoveryConsole.open("{}");
                root.recoveryConsole.tab = 1;
                wait(0);
                return root.recoveryConsole;
            }
            const original = createConsole();
            const recovery = original.askRecoveryText;
            verify(recovery.indexOf(request.text) !== -1, "the retained reply survives: " + recovery);
            const destroyed = root.destroyedRecoveryConsoles;
            original.destroy();
            root.recoveryConsole = null;
            tryCompare(root, "destroyedRecoveryConsoles", destroyed + 1);
            const replacement = createConsole();
            compare(sent.length, 0, "opening and recreating never sends an action");
            compare(replacement.pendingAsk, data.kind === "unknown" ? "" : request.requestId);
            compare(replacement.askRecoveryText, recovery);
            verify(collect(replacement, n => n instanceof Text && n.visible && n.text === replacement.askRecoveryText, []).length > 0,
                "the retained reply is visible with the optional ask page absent");
            shell.status.values = Object.assign({}, shell.status.values,
                { ownerAskAnswer: { kind: "unknown", home: "", request: request, result: null } });
            replacement.shell = null;
            replacement.shell = shell;
            wait(0);
            compare(JSON.stringify(replacement.unconfirmedRequest), JSON.stringify(request));
            const retry = collect(replacement, n => n.text === "Retry previous action" && n.visible, [])[0];
            verify(retry !== undefined);
            compare(retry.disabledReason, "");
            retry.forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Return);
            compare(sent.length, 1);
            compare(JSON.stringify(sent[0]), JSON.stringify(request), "the deliberate retry keeps all six primitives");
            replacement.closeAskEditor();
            compare(JSON.stringify(replacement.unconfirmedRequest), JSON.stringify(request), "Cancel cannot clear canonical recovery");
            shell.settings.home = "another-home";
            replacement.shell = null;
            replacement.shell = shell;
            compare(replacement.unconfirmedRequest, null, "old Home recovery is not offered in another Home");
            compare(sent.length, 1);
        }

        function test_canonical_ask_reorder_retains_focus_and_current_payload() {
            const actions = { reply: { allowed: true, reason: "" }, done: { allowed: true, reason: "" }, later: { allowed: true, reason: "" } };
            const row = id => ({ id: id, revision: "one", kind: "jarvis-ask", what: "Choose " + id,
                askedBy: { id: "jarvis", name: "Jarvis" }, askedAt: new Date().toISOString(),
                link: { label: "Original thread", url: "https://example.invalid/thread" }, state: "open", snoozedUntil: null, actions: actions });
            const first = row("first"), second = row("second");
            function publication(rows) {
                const values = root.values({});
                values.ownerAsks = { kind: "ready", homeId: "home", revision: "two", active: rows, snoozed: [], activeCount: 2, snoozedCount: 0 };
                return root.shellWith(values);
            }
            jarvisConsole.shell = publication([first, second]);
            jarvisConsole.tab = 1;
            wait(0);
            const original = collect(jarvisConsole, n => n.title === "Choose first" && n.actionAt !== undefined, [])[0];
            const button = original.actionAt(0);
            button.forceActiveFocus(Qt.TabFocusReason);
            verify(button.activeFocus);
            const changed = Object.assign({}, first, { what: "Choose the updated voice", actions: Object.assign({}, actions,
                { reply: { allowed: false, reason: "Jarvis is checking this ask." } }) });
            jarvisConsole.shell = publication([second, changed]);
            wait(0);
            const updated = collect(jarvisConsole, n => n.title === changed.what && n.actionAt !== undefined, [])[0];
            compare(updated, original, "the canonical ask id keeps its row across reorder");
            compare(updated.actionAt(0), button);
            verify(button.activeFocus);
            compare(button.disabledReason, changed.actions.reply.reason);
        }

        // Recovery names the ask Retry previous action acts on, for each
        // action, while the ask is on the page.
        function test_ask_recovery_names_its_ask_data() {
            return ["reply", "done", "later"].map(action => ({ tag: action, action: action }));
        }
        function test_ask_recovery_names_its_ask(data) {
            const values = root.values({});
            const ask = { id: "voice", revision: "one", kind: "jarvis-ask", what: "Choose the voice for tomorrow's briefing",
                askedBy: { id: "jarvis", name: "Jarvis" }, askedAt: new Date().toISOString(),
                link: { label: "Original thread", url: "https://example.invalid/thread" }, state: "open", snoozedUntil: null,
                actions: { reply: { allowed: true, reason: "" }, done: { allowed: true, reason: "" }, later: { allowed: true, reason: "" } } };
            values.ownerAsks = { kind: "ready", homeId: "home", revision: "one", active: [ask], snoozed: [], activeCount: 1, snoozedCount: 0 };
            values.ownerAskAnswer = { kind: "unknown", home: "", result: null,
                request: { action: data.action, id: ask.id, requestId: "r", expectedRevision: "one",
                    text: data.action === "reply" ? "Keep the current voice." : "", until: data.action === "later" ? new Date(2026, 9, 1, 9).toISOString() : null } };
            jarvisConsole.shell = root.shellWith(values);
            verify(jarvisConsole.askRecoveryText.indexOf(ask.what) !== -1, jarvisConsole.askRecoveryText);
        }

        // Real Session regions: mute and gate can refuse before duplex, and
        // engine changes arrive while the same Console instance stays open.
        function test_composer_transition_data() {
            const typed = { engine: { kind: "chained" } };
            const speech = { engine: { kind: "duplex" } };
            const rows = [
                { tag: "unmute-duplex", from: Object.assign({}, speech, { mute: { kind: "on" } }), to: speech, focus: "speechStop", expected: "speechStop" },
                { tag: "mute-duplex", from: speech, to: Object.assign({}, speech, { mute: { kind: "on" } }), focus: "speechStop", expected: "speechStop" },
                { tag: "ready-duplex", from: Object.assign({}, speech, { gate: { kind: "down", reason: "unconfigured" } }), to: speech, focus: "speechStop", expected: "speechStop" },
                { tag: "unready-duplex", from: speech, to: Object.assign({}, speech, { gate: { kind: "down", reason: "unconfigured" } }), focus: "speechStop", expected: "speechStop" },
                { tag: "dictation", from: typed, to: { engine: { kind: "dictation" } }, focus: "entry", expected: "entry" }
            ];
            for (const focus of ["entry", "send", "info", "typedStop"])
                rows.push({ tag: "local-to-cloud-" + focus, from: typed, to: speech, focus: focus, expected: "speechStop" });
            for (const focus of ["speechStop", "speechHint"])
                rows.push({ tag: "cloud-to-local-" + focus, from: speech, to: typed, focus: focus, expected: "entry" });
            for (const focus of ["outside", "tabs", "asks", "history"])
                for (const fromSpeech of [false, true])
                    rows.push({ tag: "keep-" + focus + "-" + fromSpeech, from: fromSpeech ? speech : typed,
                        to: fromSpeech ? typed : speech, focus: focus, expected: focus });
            rows.push({ tag: "daemon-arrives", from: null, to: speech, focus: "entry", expected: "speechStop" });
            rows.push({ tag: "daemon-leaves", from: speech, to: null, focus: "speechStop", expected: "entry" });
            return rows;
        }

        function setRegions(regions) {
            const shell = root.shellWith(regions === null ? {} : root.values(regions));
            // With no Talk key the speech hint itself is a focusable link.
            shell.shortcut.keys.talk = "";
            jarvisConsole.shell = shell;
        }

        function test_composer_transition(data) {
            setRegions(data.from);
            let controls = composerControls();
            let focused;
            if (data.focus === "outside") focused = outside;
            else if (data.focus === "asks" || data.focus === "history") {
                jarvisConsole.tab = data.focus === "asks" ? 1 : 2;
                jarvisConsole.focusTab();
                wait(0);
                focused = data.focus === "history"
                    ? collect(jarvisConsole, n => n.placeholderText === "Search conversations, tasks and problems", [])[0]
                    : collect(jarvisConsole, n => n.activeFocus && n.focusPolicy === Qt.StrongFocus && n !== jarvisConsole, []).pop();
            } else focused = controls[data.focus];
            verify(focused !== undefined, "find source " + data.focus);
            focused.forceActiveFocus(Qt.TabFocusReason);
            verify(focused.activeFocus, "source owns focus");
            setRegions(data.to);
            controls = composerControls();
            const expected = data.expected === data.focus ? focused : controls[data.expected];
            tryCompare(expected, "activeFocus", true);
            verify(expected.visible, "focus target is visible");
            compare(jarvisConsole.speechOnly, data.to !== null && data.to.engine.kind === "duplex");
            if (expected !== focused) {
                verify(!focused.activeFocus, "replaced control releases focus");
                compare(expected.focusReason, Qt.TabFocusReason, "replacement keeps the keyboard reason");
            }
        }

        function test_tabs_enter_visible_composer_data() {
            return [{ tag: "typed", kind: "chained", control: "entry" }, { tag: "speech", kind: "duplex", control: "speechStop" }];
        }

        function test_tabs_enter_visible_composer(data) {
            setRegions({ engine: { kind: data.kind } });
            const controls = composerControls();
            controls.tabs.forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Tab);
            tryCompare(controls[data.control], "activeFocus", true);
            keyClick(Qt.Key_Backtab);
            tryCompare(controls.tabs, "activeFocus", true);
        }

        // The History filter's entry click, as the console smoke takes it:
        // a click on an entry of the open list shows only that type, and Tab
        // from the filter reaches the shown body.
        function test_a_clicked_history_filter_entry_shows_its_type_data() {
            return [{ tag: "tasks", index: 2, entry: "Tasks", shown: [false, true, false], heading: "Coding tasks" },
                { tag: "problems", index: 3, entry: "Problems", shown: [false, false, true], heading: "Problems" }];
        }
        function test_a_clicked_history_filter_entry_shows_its_type(data) {
            jarvisConsole.tab = 2;
            wait(0);
            const filter = collect(jarvisConsole, n => n.accessibleLabel === "Filter history results", [])[0];
            verify(filter !== undefined && filter.visible);
            filter.openList();
            tryCompare(filter, "listOpen", true);
            const list = collect(filter.tracker.popup.contentItem, n => n instanceof ListView, [])[0];
            tryVerify(() => list.itemAtIndex(data.index) !== null, 1000, "the list builds its entries");
            const entry = list.itemAtIndex(data.index);
            compare(entry.text, data.entry);
            mouseMove(entry, 4, 4);
            mouseClick(entry);
            compare([filter.listOpen, filter.currentText, jarvisConsole.historyType], [false, data.entry, data.index]);
            compare([jarvisConsole.showConversations, jarvisConsole.showTasks, jarvisConsole.showProblems], data.shown);
            // The stand-in popup is a plain window, which keeps the keys
            // after it hides; Quickshell's grab returns them on close.
            root.Window.window.requestActivate();
            tryVerify(() => root.Window.window.active, 1000, "the console window takes the keys back");
            filter.forceActiveFocus(Qt.TabFocusReason);
            tryCompare(filter, "activeFocus", true);
            keyClick(Qt.Key_Tab);
            const focused = root.Window.window.activeFocusItem;
            verify(collect(focused, n => n instanceof Text && n.text === data.heading, []).length === 1,
                "Tab from the filter reaches the shown list, not the scroll stop: " + focused);
        }

        // History's coding tasks as Tasks.rows publishes them, the console
        // showing only them, its IPC recording each call in CALLS. READY
        // false publishes no daemon detail.
        function task(id, state, endedAt) {
            return { id: id, goal: "Goal " + id, agent: "Codex", state: state, failure: null, createdAt: 1, endedAt: endedAt };
        }
        function showTasks(rows, calls, ready) {
            const values = ready === false ? {} : root.values({});
            values.taskList = rows;
            const shell = root.shellWith(values);
            shell.ipc.call = (name, arg) => { calls.push([name, arg]); return "ok"; };
            jarvisConsole.shell = shell;
            jarvisConsole.tab = 2;
            jarvisConsole.historyType = 2;
            wait(0);
            return shell;
        }
        function taskRow(id) {
            return collect(jarvisConsole, n => n instanceof MessageRow && n.visible && n.title === "Goal " + id, [])[0];
        }
        function tasksList() {
            return collect(jarvisConsole, n => n.focusPolicy === Qt.StrongFocus && n.visible && n.contentItem && n.contentItem.title === "Coding tasks", [])[0];
        }

        // Each task row offers its own task's actions: Open while the
        // process lives, Stop while it runs, and a reason on one it cannot
        // take now. Return on a row's action acts on that row's task alone.
        function test_a_task_row_offers_only_its_own_tasks_actions_data() {
            return [
                { tag: "working", state: "working", endedAt: null, ids: ["open", "stop"], disabled: [false, false] },
                { tag: "waiting", state: "waiting", endedAt: null, ids: ["open", "stop"], disabled: [false, false] },
                { tag: "starting", state: "starting", endedAt: null, ids: ["open", "stop"], disabled: [true, false] },
                { tag: "failed-turn-alive", state: "failed", endedAt: null, ids: ["open"], disabled: [false] },
                { tag: "stopped", state: "stopped", endedAt: 40, ids: [], disabled: [] },
                { tag: "exited", state: "exited", endedAt: 40, ids: [], disabled: [] },
                { tag: "lost", state: "lost", endedAt: 40, ids: [], disabled: [] },
                { tag: "not-ready", state: "working", endedAt: null, ready: false, ids: ["open", "stop"], disabled: [true, true] }
            ];
        }
        function test_a_task_row_offers_only_its_own_tasks_actions(data) {
            const calls = [];
            showTasks([task("other", "working", null), task("row", data.state, data.endedAt)], calls, data.ready);
            const row = taskRow("row");
            verify(row !== undefined, "the task draws its own row");
            compare(JSON.stringify(row.actions.map(action => action.id)), JSON.stringify(data.ids));
            const buttons = row.actions.map((action, index) => row.actionAt(index));
            compare(buttons.map(button => button !== null && button.visible), data.ids.map(() => true), "each action draws in its row");
            compare(buttons.map(button => button.disabledReason !== ""), data.disabled, "an action the task cannot take now names why");
            for (const button of buttons) {
                button.forceActiveFocus(Qt.TabFocusReason);
                keyClick(Qt.Key_Return);
            }
            const sent = data.ids.filter((id, index) => !data.disabled[index]).map(id => [id === "stop" ? "stop-task" : "open-task", "row"]);
            compare(JSON.stringify(calls), JSON.stringify(sent));
        }

        // Tab walks each row's actions in row order from the list, Return
        // acts on that row's task, and the keyboard stays in the list when a
        // stopped task's row drops its actions.
        function test_tab_reaches_each_task_rows_actions_and_acts_on_that_task() {
            const calls = [];
            const rows = [task("first", "working", null), task("second", "working", null), task("third", "failed", 15)];
            const shell = showTasks(rows, calls);
            const list = tasksList();
            verify(list !== undefined, "find the task list");
            list.forceActiveFocus(Qt.TabFocusReason);
            const first = taskRow("first"), second = taskRow("second");
            for (const button of [first.actionAt(0), first.actionAt(1), second.actionAt(0), second.actionAt(1)]) {
                keyClick(Qt.Key_Tab);
                tryCompare(button, "activeFocus", true);
            }
            keyClick(Qt.Key_Return);
            compare(JSON.stringify(calls), '[["stop-task","second"]]');
            const stopped = Object.assign({}, shell.status.values, { taskList: [rows[0], task("second", "stopped", 40), rows[2]] });
            jarvisConsole.shell = Object.assign({}, shell, { status: { values: stopped } });
            wait(0);
            compare(taskRow("second").actions.length, 0, "the stopped task offers no action");
            verify(list.activeFocus, "the keyboard stays in the task list");
            keyClick(Qt.Key_Tab);
            tryCompare(first.actionAt(0), "activeFocus", true);
            keyClick(Qt.Key_Return);
            compare(JSON.stringify(calls), '[["stop-task","second"],["open-task","first"]]');
        }

        // No task action acts out of sight: each one Tab reaches lies inside
        // the console's scrolled view.
        function test_every_task_action_tab_reaches_lies_in_view() {
            const rows = [];
            for (let i = 0; i < 12; i++) rows.push(task("t" + i, "working", null));
            showTasks(rows, []);
            const list = tasksList();
            list.forceActiveFocus(Qt.TabFocusReason);
            let view = null;
            for (let at = list.parent; at !== null && view === null; at = at.parent) if (at instanceof Flickable) view = at;
            verify(view !== null, "find the console's scroll area");
            for (let i = 0; i < rows.length; i++) {
                const row = taskRow("t" + i);
                for (const index of [0, 1]) {
                    keyClick(Qt.Key_Tab);
                    const button = row.actionAt(index);
                    tryCompare(button, "activeFocus", true);
                    tryVerify(() => { const y = button.mapToItem(view, 0, 0).y; return y >= 0 && y + button.height <= view.height; },
                        1000, "the focused action of " + row.title + " lies in view");
                }
            }
            verify(view.contentY > 0, "the tasks overflow the view, so the walk scrolled it");
        }

        // History holds no task selection: no row draws highlighted and no
        // button outside a task's row acts on a task.
        function test_history_tasks_hold_no_selection_and_no_footer_action() {
            showTasks([task("first", "working", null), task("second", "working", null)], []);
            const inRow = node => { for (let at = node; at !== null; at = at.parent) if (at instanceof MessageRow) return true; return false; };
            const loose = collect(jarvisConsole, n => n instanceof Button && n.visible, []).filter(n => !inRow(n));
            compare(loose.length, 0, "every shown button belongs to a task row: " + loose.map(n => n.text));
            compare(collect(jarvisConsole, n => n.highlighted === true && n.visible, []).length, 0, "no row holds a selection");
        }

        // A refused key is a problem whose action links the Voice key field.
        function test_a_problem_draws_its_facts_as_lines_and_its_action_as_a_link() {
            jarvisConsole.shell = root.shellWith(root.values({ fault: { kind: "error", reason: "live=key-refused", retry: 0 } }));
            const reference = "(page:vgs.jarvis/Settings/voiceAccount)";
            const drawn = shownText();
            verify(drawn.length > 0, "the console draws text");
            for (const text of drawn)
                compare(PageReference.parse(text).page, "", "no drawn line shows a page reference's raw form: " + text);
            verify(drawn.indexOf("AI model: Claude Opus 5.5") !== -1, "the AI model is a line of its own: " + JSON.stringify(drawn));
            const link = links().find(n => n.text.indexOf(reference) !== -1);
            verify(link !== undefined, "a link holds the action's page reference");
            verify(link.text.indexOf("AI model: ") === -1, "the action's link holds no other fact");
            link.pageActivated("vgs.jarvis/Settings", "voiceAccount");
            compare(JSON.stringify(root.opened), '[["vgs.jarvis/Settings","voiceAccount"]]');
        }

        // The main Jarvis's reading draws one line on Now alone, in the
        // warning colour while the route cannot forward or the main did not
        // answer, linking where an unavailable route is fixed and nowhere
        // for a package VGS cannot fix; before the first reading none shows.
        function test_main_reach_line_data() {
            const unavailable = cause => ({ kind: "unavailable", host: "cachy", cause: cause });
            return [
                { tag: "unread", reach: undefined, shown: false, warning: false, link: "" },
                { tag: "main", reach: { kind: "main" }, shown: true, warning: false, link: "" },
                { tag: "reachable", reach: { kind: "satellite", host: "cachy", reachable: true, cause: "" }, shown: true, warning: false, link: "" },
                { tag: "uncontacted", reach: { kind: "satellite", host: "cachy", reachable: null, cause: "" }, shown: true, warning: false, link: "" },
                { tag: "unanswered", reach: { kind: "satellite", host: "cachy", reachable: false, cause: "main-unreachable" }, shown: true, warning: true, link: "" },
                { tag: "setting", reach: { kind: "satellite", host: "cachy", reachable: null, cause: "setting-invalid" }, shown: true, warning: true, link: "page:vgs.jarvis/Settings/mainHost" },
                { tag: "old", reach: unavailable("package-old"), shown: true, warning: true, link: "" },
                { tag: "unanswering", reach: unavailable("package-unread"), shown: true, warning: true, link: "" },
                { tag: "package", reach: unavailable("package"), shown: true, warning: true, link: "page:vgs.jarvis/Setup/sessionStart" },
                { tag: "vgs-package", reach: unavailable("vgs-package"), shown: true, warning: true, link: "page:vgs.jarvis/Settings/home" },
                { tag: "home-link", reach: unavailable("home-link"), shown: true, warning: true, link: "page:vgs.jarvis/Settings/home" },
                { tag: "no-home", reach: unavailable("no-home"), shown: true, warning: true, link: "page:vgs.jarvis/Settings/home" }
            ];
        }
        function test_main_reach_line(data) {
            const values = root.values({});
            if (data.reach !== undefined) values.mainReach = data.reach;
            jarvisConsole.shell = root.shellWith(values);
            const line = () => collect(jarvisConsole, n => n.objectName === "mainReachLine", [])[0];
            compare(line().visible, data.shown);
            if (data.shown) compare(Qt.colorEqual(line().color, data.warning ? Theme.color.warning : Theme.color.textMuted), true);
            const links = (line().text.match(/\]\(([^)]*)\)/g) || []).map(link => link.slice(2, -1));
            compare(JSON.stringify(links), JSON.stringify(data.link === "" ? [] : [data.link]), "the line links where its route is fixed");
            jarvisConsole.tab = 2;
            compare(line().visible, false, "the line is Now's alone");
        }
    }
}
