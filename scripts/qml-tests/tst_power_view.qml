import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit
import "../../shell/plugins/vgs.power" as Power

// The shipped flyout and System section use the same field-height action.
// The flyout draws exactly one battery-state icon, including without a
// battery. Inputs are the six states UPower publishes through the service.
Item {
    id: root
    width: 800
    height: 1000

    Component {
        id: flyout
        Power.Panel { width: 360; height: implicitHeight }
    }
    Component {
        id: section
        Power.Pane { width: 700; height: implicitHeight }
    }

    UnitCase {
        name: "powerView"
        when: windowShown

        // The views are lazy; the first theme read attaches UnitTheme's source.
        function init() { void Theme.color; UnitTheme.reset(); }
        function descendants(item) {
            let out = [];
            for (const child of item.children) out = out.concat([child], descendants(child));
            return out;
        }
        function shell(battery) {
            return {
                status: { values: { power: { battery: battery, profile: { available: true, active: "balanced", choices: ["power-saver", "balanced", "performance"] } } }, rows: [] },
                idle: { stages: [] }, idleSettings: { fields: [] }, manifest: { id: "vgs.power", schema: {} },
                manager: { plugins: [] }, requirements: { missing: [] },
                hyprland: { displayWake: { keyPress: "enabled", pointerMovement: "enabled" } }
            };
        }
        function battery(state) {
            return { present: true, level: 64, charging: state === "charging", state: state, secondsToEmpty: 7200, secondsToFull: 3600 };
        }
        function test_field_height_in_both_surfaces_data() {
            return [
                { tag: "flyout", component: flyout },
                { tag: "section", component: section }
            ];
        }
        function test_field_height_in_both_surfaces(data) {
            const view = createTemporaryObject(data.component, root, { shell: shell(battery("discharging")) });
            verify(view !== null);
            verify(renderedFrame(view));
            const awake = descendants(view).find(item => item instanceof Power.StayAwake);
            verify(awake !== undefined);
            const select = awake.children.find(item => item instanceof Select);
            const start = awake.children.find(item => item instanceof Button);
            compare(select.height, Theme.textField.height);
            compare(start.height, select.height);
            compare(start.mapToItem(awake, 0, 0).y, select.y);
        }
        function test_battery_state_icon_data() {
            return [
                { tag: "absent", battery: { present: false, level: 0, charging: false, state: "absent", secondsToEmpty: 0, secondsToFull: 0 }, icon: "battery", tone: "textMuted" },
                { tag: "full", battery: battery("fully-charged"), icon: "battery-full", tone: "success" },
                { tag: "charging", battery: battery("charging"), icon: "battery-charging", tone: "accent" },
                { tag: "discharging", battery: battery("discharging"), icon: "battery-medium", tone: "textMuted" },
                { tag: "pending", battery: battery("pending-charge"), icon: "battery-warning", tone: "warning" },
                { tag: "present", battery: battery("unknown"), icon: "battery", tone: "textMuted" }
            ];
        }
        function test_battery_state_icon(data) {
            const view = createTemporaryObject(flyout, root, { shell: shell(data.battery) });
            verify(view !== null);
            verify(renderedFrame(view));
            const field = descendants(view).find(item => item instanceof Field);
            verify(field !== undefined && field.visible);
            const icons = descendants(field).filter(item => item instanceof Icon && item.visible);
            compare(icons.length, 1);
            compare(icons[0].name, data.icon);
            compare(icons[0].color, Qt.color(Theme.color[data.tone]));
            compare(icons[0].size, Theme.icon.size.sm);
            const text = icons[0].parent.children.find(item => item instanceof Label);
            verify(icons[0].x + icons[0].width < text.x);
            compare(icons[0].y, text.topForLeadingIcon(icons[0].height));
            if (data.battery.present) {
                const row = field.children.find(item => item instanceof FormRow);
                const key = row.children.find(item => item.objectName === "fieldLabel");
                const level = field.control[0].children.find(item => item instanceof Label);
                const keyCentre = key.mapToItem(view, 0, (key.baselineOffset + key.capTop()) / 2).y;
                const levelCentre = level.mapToItem(view, 0, (level.baselineOffset + level.capTop()) / 2).y;
                verify(Math.abs(keyCentre - levelCentre) <= 1, "the battery key stays beside the first value line");
            }
        }
        function test_stay_awake_spacing() {
            const view = createTemporaryObject(flyout, root, { shell: shell(battery("charging")) });
            verify(view !== null);
            verify(renderedFrame(view));
            const all = descendants(view);
            const awake = all.find(item => item instanceof Power.StayAwake);
            const field = all.find(item => item instanceof Field && descendants(item).indexOf(awake) !== -1);
            const progress = all.find(item => item instanceof ProgressBar);
            const tiles = all.find(item => item instanceof TileGroup);
            const label = field.children[0].children[0];
            compare(label.mapToItem(view, 0, 0).y - (progress.mapToItem(view, 0, 0).y + progress.height),
                Theme.stack.group + Theme.stack.row);
            compare(tiles.mapToItem(view, 0, 0).y - (field.mapToItem(view, 0, 0).y + field.height - field.bottomPadding),
                Theme.stack.group + Theme.space.md);
        }
    }
}
