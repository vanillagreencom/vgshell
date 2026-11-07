import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit
import "../../shell/plugins/vgs.local-sync" as Sync
import "../../shell/plugins/vgs.local-sync/SyncLogic.js" as Logic

// The Local Sync flyout over a stub `jobs` value: a watching wrapper, a
// copy that failed with an error the card cannot name, and one whose To
// folder is unreachable. Each card is the one SyncLogic.card makes; each
// action asks the stub shell what the panel promises: a chip opens its
// folder through the core folder route, View log opens the job's log TUI
// and closes the flyout, Send to agent hands the job's facts to Agent
// Debug's receiver and Add and an Automations job's Remove to Automations',
// each stub receiver recording its own key, Details replaces the cards,
// and Remove asks first and only then asks the service to stop the job.
Item {
    id: root
    width: 800
    height: 900

    // Each request the panel makes of the stub shell, in order.
    property var calls: []
    // What each stub receiver was handed: [its key, the text].
    property var handed: []

    // The stub receiver of KEY: it records what it was handed.
    function receiver(key, label, kind) {
        return { key: key, label: label, kind: kind, available: true, reason: "",
            open: text => { root.handed = root.handed.concat([[key, text]]); return { ok: true, reason: "" }; } };
    }

    function record(call) {
        root.calls = root.calls.concat([call]);
        return "ok";
    }

    Component {
        id: panelComponent
        Sync.Panel { width: implicitWidth; height: implicitHeight }
    }

    UnitCase {
        name: "local_sync_panel"
        when: windowShown

        property Item panel: null

        function job(unit, changes) {
            return Object.assign({
                unit: unit, name: unit, description: "", automation: "", engine: "rsync", available: true,
                from: "/home/u/" + unit + "/", to: "/mnt/backup/" + unit + "/", via: "script", continuous: true,
                active: "active", sub: "running", result: "success", resident: false, triggers: [],
                fileState: "static", mainStatus: 0, startedAt: 0, exitedAt: 0, runs: [], runPattern: "", notRuns: []
            }, changes || {});
        }

        function value() {
            const now = Time.now.getTime();
            return {
                ready: true, problem: "", removeProblem: "", storeProblem: "", copying: [], cleanEnds: {}, watching: true, engines: ["rsync"],
                jobs: [job("mirror.service"), job("photos.service"), job("notes.service"), job("vgs-automation-backup.service", { automation: "backup" })],
                facts: {
                    "mirror.service": { tried: now - 60000, failedAt: 0, error: "", problem: "" },
                    "photos.service": { tried: now - 60000, failedAt: now - 60000, error: "rsync error: error in file IO (code 11)", problem: "" },
                    "notes.service": { tried: now - 60000, failedAt: now - 60000, error: "x", problem: "to" }
                }
            };
        }

        function shell() {
            return {
                manifest: { id: "vgs.local-sync" },
                status: { values: { jobs: value() } },
                ipc: { call: (name, arg) => root.record(["ipc", name, arg]) },
                tui: { edit: (path, line, done) => root.record(["edit", path]), run: (name, args) => root.record(["tui", name].concat(args)) },
                surfaces: { hide: kind => root.record(["hide", kind]), openPage: (page, tab) => root.record(["openPage", page, tab]) },
                handoff: { targets: [root.receiver(Logic.AGENT_TARGET, "Agent Debug", "action"), root.receiver(Logic.AUTOMATIONS_TARGET, "Automations", "action")] }
            };
        }

        function init() {
            root.calls = [];
            root.handed = [];
            panel = createTemporaryObject(panelComponent, root, { shell: shell() });
            verify(panel !== null);
            panel.open("{}");
            renderedFrame(panel);
            root.calls = [];
        }

        function cleanup() { panel = null; }

        function find(item, wanted) {
            for (const child of item.children) {
                if (child.visible && wanted(child)) return child;
                const found = find(child, wanted);
                if (found !== null) return found;
            }
            return null;
        }

        function all(item, wanted) {
            let found = [];
            for (const child of item.children) {
                if (child.visible && wanted(child)) found.push(child);
                found = found.concat(all(child, wanted));
            }
            return found;
        }

        // The card of UNIT, found by its job.
        function card(unit) {
            const found = find(panel, item => item.modelData !== undefined && item.modelData !== null && item.modelData.unit === unit && "contentInset" in item);
            verify(found !== null, "a card shows " + unit);
            return found;
        }

        // The link of CARD whose action is ACTION, as the panel words it.
        function link(cardItem, action) {
            const found = find(cardItem, item => "removesItem" in item && item.text === panel.linkText(action));
            verify(found !== null, "the card offers " + action);
            return found;
        }

        function test_cards_follow_the_logic() {
            compare(all(panel, item => item.modelData !== undefined && item.modelData !== null && "contentInset" in item).length, 4);
            for (const [unit, state, actions] of [["mirror.service", "watching", []], ["photos.service", "failed", ["log", "agent"]], ["notes.service", "attention", ["log"]]]) {
                const shown = card(unit).modelData;
                compare([shown.state, JSON.stringify(shown.actions)], [state, JSON.stringify(actions)], unit);
            }
        }

        function test_a_chip_opens_its_folder() {
            const chip = find(card("mirror.service"), item => "lineHeight" in item && item.text === "/home/u/mirror.service/");
            verify(chip !== null);
            mouseClick(chip);
            compare(JSON.stringify(root.calls), JSON.stringify([["edit", "/home/u/mirror.service/"]]));
        }

        function test_view_log_opens_the_log_and_closes() {
            mouseClick(link(card("photos.service"), "log"));
            compare(JSON.stringify(root.calls), JSON.stringify([["tui", "log", "photos.service"], ["hide", "panel"]]));
        }

        function test_send_to_agent_hands_the_facts() {
            mouseClick(link(card("photos.service"), "agent"));
            compare(root.handed.length, 1);
            compare(root.handed[0][0], Logic.AGENT_TARGET, "Send to agent hands the facts to Agent Debug");
            const facts = JSON.parse(root.handed[0][1]);
            compare([facts.kind, facts.unit, facts.error], ["sync", "photos.service", "rsync error: error in file IO (code 11)"]);
            compare(JSON.stringify(root.calls), JSON.stringify([["hide", "panel"]]));
        }

        function test_remove_asks_first() {
            panel.remove(panel.jobs[0]);
            renderedFrame(panel);
            compare(root.calls.length, 0, "Remove asks before it stops anything");
            const accept = find(panel, item => "focusPolicy" in item && item.text === Logic.removal(panel.jobs[0]).action);
            verify(accept !== null, "the question offers its action");
            mouseClick(accept);
            compare(JSON.stringify(root.calls), JSON.stringify([["ipc", "remove", "mirror.service"]]));
            compare(panel.confirmUnit, "");
        }

        // Add, and Remove of a job Automations runs, open Automations on
        // that job and stop nothing here.
        function test_automations_owns_add_and_its_remove() {
            panel.add();
            panel.remove(panel.jobs.find(job => job.automation === "backup"));
            compare(JSON.stringify(root.handed.map(([key, text]) => [key, JSON.parse(text)])),
                JSON.stringify([[Logic.AUTOMATIONS_TARGET, { action: "new", available: ["rsync"] }], [Logic.AUTOMATIONS_TARGET, { action: "remove", id: "backup" }]]));
            compare(panel.confirmUnit, "", "Local Sync asks nothing for a job Automations runs");
            compare(JSON.stringify(root.calls), JSON.stringify([["hide", "panel"], ["hide", "panel"]]));
        }

        function test_details_replace_the_cards() {
            panel.detailsUnit = "photos.service";
            renderedFrame(panel);
            verify(all(panel, item => "keyValueRow" in item).length > 0, "Details shows its rows");
            compare(all(panel, item => item.modelData !== undefined && item.modelData !== null && "contentInset" in item).length, 0, "Details replaces the cards");
        }
    }
}
