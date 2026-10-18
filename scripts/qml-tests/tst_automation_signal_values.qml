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

    TestCase {
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
            waitForRendering(window);
            return window;
        }

        function cleanup() { UnitTheme.reset(); }

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
            compare(window.validationResult.ok, true);
        }
    }
}
