import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit

// IdleTimeField over NumberSettingField, from fields as the core lends
// them (PluginLogic.idleSettingFields). While the stage it starts with
// runs, the list offers Immediately (<time>) after Never, in place of a
// preset of that time; choosing it writes that time, which then reads as
// Immediately with its hint, and the info dialog explains the snapshot. A
// time no preset holds reads Custom… with its slider row; Never writes 0;
// the time held writes nothing. With no Immediately the list is the
// owner's presets. On another plugin's page an owner that is off locks the
// list with its reason, and the hint holds a page reference to the owner's
// Settings, which asks for that page; with no owner the list is empty and
// locked under the stage's own label. The owner's own page shows neither.
// A warning reads in the hint's place in the warning colour. A field a
// view's model hands on, as a Repeater's modelData, keeps its list. A
// number editor turned read-only drops its typed draft. Only the user's
// Custom… choice scrolls its row into view: a custom value it loads with
// scrolls nothing.
Item {
    id: root
    width: 640
    height: 900

    // Reading the theme here loads it before the first init resets it.
    readonly property color surface: Theme.color.surface
    property var written: []
    property var pages: []
    readonly property var lockSpec: ({ type: "number", label: "Lock after", min: 0, max: 86400, step: 30, unit: "seconds", allowCustom: true,
        presets: [{ value: 0, label: "Never" }, { value: 60 }, { value: 150 }, { value: 300 }] })
    function fieldOf(changes) {
        return Object.assign({ stage: "lock", plugin: "acme.lock", name: "Lock", setting: "after", spec: lockSpec, value: 300, reason: "", immediately: 150, identity: "id" }, changes);
    }

    Component {
        id: idleComponent
        IdleTimeField {
            id: made
            width: 600
            field: root.fieldOf({})
            onApply: value => { root.written.push(value); made.field = Object.assign({}, made.field, { value: value }); }
            onPageActivated: (page, tab) => root.pages.push(page + "/" + tab)
        }
    }

    // A model's modelData holds the field's presets as a list that
    // Array.isArray refuses, as Power's timeline hands its editor one.
    property var modelFields: []
    Column {
        id: fromModel
        y: 700
        width: 600
        Repeater {
            model: root.modelFields
            IdleTimeField {
                required property var modelData
                width: 600
                field: modelData
            }
        }
    }

    NumberSettingField {
        id: typedNumber
        y: 800
        width: 600
        spec: ({ type: "number", label: "Gap" })
        value: 4
        onApply: value => root.written.push(value)
    }

    // A scroll area's reveal, recorded.
    Item {
        id: scroller
        property var revealed: []
        function reveal(item) { revealed = revealed.concat([item]); }
        y: 860
        width: 600
        height: 40
        Component {
            id: scrolledField
            NumberSettingField {
                width: 600
                spec: ({ type: "number", label: "Lock after", min: 0, max: 3600, allowCustom: true, presets: [{ value: 60 }, { value: 300 }] })
            }
        }
    }

    UnitCase {
        name: "idletimefield"
        when: windowShown

        function init() {
            UnitTheme.reset();
            root.written = [];
            root.pages = [];
        }

        function descendants(item) {
            const found = [item];
            for (let i = 0; i < found.length; i++)
                for (const child of found[i].children || []) found.push(child);
            return found;
        }
        function selectOf(item) { return descendants(item).find(child => String(child).indexOf("Select") === 0); }
        function hintOf(item) { return descendants(item).find(child => child.role === "hint" && child.visible && child.text !== "" && String(child).indexOf("LinkText") === 0); }
        function labels(select) {
            const out = [];
            for (let i = 0; i < select.count; i++) out.push(select.textAt(i));
            return out;
        }
        // The field is assigned, not handed to createObject, whose property
        // map would turn its lists into sequences Array.isArray refuses, as
        // no binding from the core's record does.
        function make(changes, props) {
            const made = createTemporaryObject(idleComponent, root, props || {});
            verify(made !== null);
            made.field = root.fieldOf(changes);
            tryVerify(() => selectOf(made) !== undefined);
            return made;
        }

        function test_immediately_follows_never_in_place_of_its_time() {
            const made = make({});
            compare(labels(selectOf(made)), ["Never", "Immediately (150 seconds)", "1 minute", "5 minutes", "Custom…"]);
            compare(selectOf(made).currentText, "5 minutes");
            const minutes = make({ immediately: 300, value: 60 });
            compare(labels(selectOf(minutes)), ["Never", "Immediately (5 minutes)", "1 minute", "150 seconds", "Custom…"], "a time in minutes reads as one");
        }

        function test_choosing_immediately_writes_the_time_it_holds() {
            const made = make({});
            selectOf(made).choose(1);
            compare(root.written, [150], "Immediately writes the screensaver's time, never 0 or a mode");
            compare(selectOf(made).currentText, "Immediately (150 seconds)");
            compare(hintOf(made).text, SettingValues.IDLE_STAGE_TEXT.lock.immediately, "the hint says what the time means");
            compare(made.info, SettingValues.IDLE_STAGE_TEXT.lock.snapshot, "the info dialog explains the snapshot");
            selectOf(made).choose(1);
            compare(root.written, [150], "the time held writes nothing");
        }

        function test_a_saved_time_equal_to_the_screensaver_reads_immediately() {
            const made = make({ value: 450, immediately: 450 });
            compare(selectOf(made).currentText, "Immediately (450 seconds)");
            made.field = root.fieldOf({ value: 450, immediately: 600 });
            compare(selectOf(made).currentText, "Custom…", "a later screensaver time leaves the lock at its own time");
            verify(made.customVisible, "the snapshot reads as the custom time it is");
            compare(root.written, [], "a changed screensaver time writes nothing");
        }

        function test_never_and_custom_write_their_values() {
            const made = make({ value: 450 });
            compare(selectOf(made).currentText, "Custom…", "a time no preset holds reads Custom…");
            verify(made.customVisible);
            verify(descendants(made).some(child => String(child).indexOf("Slider") === 0 && child.visible), "the custom row is the bounded slider");
            selectOf(made).choose(0);
            compare(root.written, [0], "Never writes 0");
            verify(!made.customVisible);
        }

        function test_with_no_immediately_the_list_is_the_owners() {
            const made = make({ immediately: 0 });
            compare(labels(selectOf(made)), ["Never", "1 minute", "150 seconds", "5 minutes", "Custom…"]);
            compare(made.info, "");
        }

        function test_an_owner_that_is_off_locks_the_list_with_its_reason() {
            const made = make({ reason: "off" });
            const select = selectOf(made);
            verify(select.lock.locked, "the list is locked, not plain disabled");
            compare(select.disabledReason, "Turn on Lock to change this time.");
            select.forceActiveFocus();
            keyClick(Qt.Key_Space);
            verify(!select.listOpen, "a locked list opens on no key");
            mouseClick(select);
            verify(!select.listOpen, "nor on a click");
            compare(root.written, []);
            const hint = hintOf(made);
            compare(hint.text, "[Turn on Lock](page:acme.lock/Settings) to change this time");
            hint.pageActivated("acme.lock", "Settings");
            compare(root.pages, ["acme.lock/Settings"], "the hint's reference asks for the owner's page");
            const own = make({ reason: "off" }, { reference: false, editable: false });
            compare(selectOf(own).disabledReason, "", "the owner's own page draws its own Turn on line");
            verify(!selectOf(own).enabled);
        }

        function test_no_owner_draws_an_empty_locked_list_under_the_stage_label() {
            const made = make({ plugin: "", name: "", setting: "", spec: null, value: null, reason: "none", immediately: 0, identity: "" });
            compare(made.label, "Lock after");
            compare(selectOf(made).count, 0);
            compare(selectOf(made).disabledReason, "No plugin that locks the screen is installed.");
        }

        function test_a_warning_reads_in_the_hints_place() {
            const made = make({ value: 60 }, { warning: "Locks before the screensaver starts" });
            const hint = hintOf(made);
            compare(hint.text, "Locks before the screensaver starts");
            verify(Qt.colorEqual(hint.color, Theme.color.warning), "the warning colour: " + hint.color);
        }

        function test_a_field_from_a_views_model_keeps_its_list() {
            root.modelFields = [root.fieldOf({ immediately: 0 }), root.fieldOf({})];
            tryCompare(fromModel.children.filter(child => child.field !== undefined), "length", 2);
            const made = fromModel.children.filter(child => child.field !== undefined);
            compare(labels(selectOf(made[0])), ["Never", "1 minute", "150 seconds", "5 minutes", "Custom…"], "the owner's presets, not a slider");
            compare(labels(selectOf(made[1])), ["Never", "Immediately (150 seconds)", "1 minute", "5 minutes", "Custom…"]);
            root.modelFields = [];
        }

        function test_a_read_only_number_drops_its_draft() {
            typedNumber.editable = true;
            const input = descendants(typedNumber).find(child => child instanceof TextInput && child.visible);
            verify(input !== undefined, "a number with no presets or bounds is a text field");
            input.text = "73";
            verify(typedNumber.edited);
            typedNumber.editable = false;
            compare(input.text, "4", "the draft goes back to the held value");
            verify(!typedNumber.edited);
            compare(root.written, [], "and nothing is written");
            typedNumber.editable = true;
        }

        function test_only_the_custom_choice_scrolls_its_row_into_view() {
            scroller.revealed = [];
            const loaded = createTemporaryObject(scrolledField, scroller, { value: 450 });
            verify(loaded.customVisible);
            verify(renderedFrame(loaded));
            wait(0);
            compare(scroller.revealed.length, 0, "a custom value it loads with moves no page");
            const chosen = createTemporaryObject(scrolledField, scroller, { value: 300 });
            selectOf(chosen).choose(selectOf(chosen).count - 1);
            tryVerify(() => scroller.revealed.length === 1, 1000, "Custom… brings its row into view");
        }

        function test_keys_choose_from_the_list() {
            const made = make({});
            const select = selectOf(made);
            select.forceActiveFocus();
            keyClick(Qt.Key_Space);
            tryVerify(() => select.listOpen);
            keyClick(Qt.Key_Up);
            keyClick(Qt.Key_Up);
            keyClick(Qt.Key_Return);
            compare(root.written, [150], "Up twice from 5 minutes reaches Immediately, and Return writes it");
        }
    }
}
