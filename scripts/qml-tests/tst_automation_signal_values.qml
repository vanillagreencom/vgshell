import QtQuick
import QtTest
import qs.Ui
import qs.Unit
import "../../shell/plugins/vgs.automations" as Automations
import "../../shell/plugins/vgs.automations/AutomationsLogic.js" as Engine
import "../../shell/plugins/vgs.automations/AutomationsViewLogic.js" as View

// inputs: shell/plugins/vgs.automations/* shell/Ui/* shell/Ui/**/* shell/Commons/*
// Real editor controls send their edits through RecurrenceSection.change,
// AutomationEditorPage.change and Window.updateDraft. The draft and the
// definition handed to the engine must retain arrays across those signals.
Item {
    id: root
    width: 1000
    height: 1400

    Component { id: windowComponent; Automations.Window { width: 900; height: 1300 } }

    UnitCase {
        name: "automation_signal_values"
        when: windowShown

        function descendants(item) {
            const found = [item];
            for (let i = 0; i < found.length; i++)
                for (const child of found[i].children || []) found.push(child);
            return found;
        }

        function opened() {
            const window = createTemporaryObject(windowComponent, root);
            verify(window !== null);
            const draft = View.blankDraft(Date.now(), Engine);
            draft.name = "Signal edit";
            draft.command = "true";
            draft.preset = "custom";
            draft.frequency = "weekly";
            draft.weekdays = ["wed"];
            draft.times = ["17:30"];
            window.loadDraft(draft);
            window.editorOpen = true;
            renderedFrame(window);
            return window;
        }

        function cleanup() { UnitTheme.reset(); }

        function test_a_detached_list_delegate_keeps_its_owning_column_width() {
            failOnWarning(/.*/);
            const window = opened();
            const definition = View.definitionFromDraft(window.draft, Engine);
            definition.id = "waiting";
            window.automations = [Object.assign({}, definition, { pending: null, nextRun: null, lastRun: null, summary: "" })];
            window.editorOpen = false;
            const row = descendants(window).find(item => item instanceof Automations.AutomationRow);
            verify(row !== undefined);
            const owner = row.parent;
            verify(owner !== null);
            verify(renderedFrame(window));
            compare(row.width, owner.width);
            // Repeater/window teardown can detach this real delegate before
            // it dies, as the VGS-2077 nested cleanup warning demonstrates.
            row.parent = null;
            const previousWidth = owner.width;
            window.width += 80;
            tryVerify(() => owner.width !== previousWidth && row.width === owner.width);
            row.parent = owner;
            window.automations = [];
            tryVerify(() => !descendants(window).some(item => item instanceof Automations.AutomationRow));
        }

        function test_weekday_edit_reaches_the_draft_and_engine_definition() {
            const window = opened();
            const weekdays = descendants(window).find(item => item instanceof WeekdayChipGroup && !item.exclusive);
            verify(weekdays !== undefined);
            weekdays.chipAt(4).clicked();
            compare(JSON.stringify(window.draft.weekdays), JSON.stringify(["wed", "fri"]));
            compare(window.validationResult.ok, true);
            const definition = View.definitionFromDraft(window.draft, Engine);
            compare(definition.schedule.weekdays, ["wed", "fri"]);
            verify(Array.isArray(definition.schedule.weekdays));
            weekdays.chipAt(2).clicked();
            compare(JSON.stringify(window.draft.weekdays), JSON.stringify(["fri"]));
            compare(window.validationResult.ok, true);
            verify(Array.isArray(window.draft.weekdays), "the draft owns a plain weekday array");
        }

        function test_time_edit_reaches_the_draft_validation_and_engine_definition() {
            const window = opened();
            const times = descendants(window).find(item => item instanceof TimeChipList);
            verify(times !== undefined);
            compare(times.addTime("09:00"), true);
            compare(JSON.stringify(window.draft.times), JSON.stringify(["09:00", "17:30"]));
            compare(window.validationResult.errors.times, undefined);
            compare(window.validationResult.ok, true);
            verify(Array.isArray(window.draft.times), "the draft owns a plain time array");
            const definition = View.definitionFromDraft(window.draft, Engine);
            compare(definition.schedule.times, ["09:00", "17:30"]);
            verify(Array.isArray(definition.schedule.times));
            times.removeTime("17:30");
            compare(JSON.stringify(window.draft.times), JSON.stringify(["09:00"]));
            compare(window.validationResult.ok, true);
        }

        function test_change_keeps_primitive_field_types() {
            const window = opened();
            const editor = descendants(window).find(item => item instanceof Automations.AutomationEditorPage);
            const command = descendants(editor).find(item => item instanceof TextArea);
            command.text = "printf hello";
            compare(window.draft.command, "printf hello");
            compare(typeof window.draft.command, "string");
            const paused = descendants(editor).find(item => item instanceof Switch && item.text === "Pause this automation");
            paused.toggled();
            compare(window.draft.enabled, false);
            compare(typeof window.draft.enabled, "boolean");
            const network = descendants(editor).find(item => item instanceof Switch && item.text === "Needs internet");
            verify(network !== undefined);
            compare(network.checked, false);
            network.toggled();
            compare(window.draft.requiresNetwork, true);
            compare(typeof window.draft.requiresNetwork, "boolean");
            compare(View.definitionFromDraft(window.draft, Engine).requiresNetwork, true);
            compare(window.validationResult.ok, true);
        }

        function test_waiting_manual_run_has_keyboard_cancel_without_claiming_a_start() {
            const window = opened();
            const definition = View.definitionFromDraft(window.draft, Engine);
            definition.id = "waiting";
            definition.requiresNetwork = true;
            const pending = { kind: "network", dueAt: Date.now(), trigger: "manual", diagnostic: "unavailable" };
            window.automations = [Object.assign({}, definition, { pending: null, nextRun: null, lastRun: null, summary: Engine.summaryText(definition.schedule) })];
            compare(window.selectAutomation("waiting"), "ok");
            compare(window.runNow("waiting"), "ok");
            compare(window.testRun, null);
            window.automations = [Object.assign({}, window.automations[0], { pending: pending })];
            compare(window.draftPending.trigger, "manual");
            window.historyAnswer = [{ automation: "waiting", startedAt: window.testStartedAt, outcome: "skipped", transcript: "", exitCode: null }];
            window.followTestRun();
            compare(window.testRun, null);
            const editor = descendants(window).find(item => item instanceof Automations.AutomationEditorPage);
            const cancel = descendants(editor).find(item => item instanceof RowAction && item.text === "Cancel waiting run");
            verify(cancel !== undefined);
            verify(cancel.visible);
            cancel.forceActiveFocus();
            keyClick(Qt.Key_Return);
            const client = descendants(window).find(item => item instanceof Automations.EngineClient);
            verify(client.queue.some(request => request.args[0] === "cancel" && request.args[1] === "waiting"));
        }
    }
}
