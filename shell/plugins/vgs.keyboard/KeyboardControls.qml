import QtQuick
import QtQuick.Templates as T
import qs.Commons
import qs.Ui
import "KeyboardLogic.js" as Logic

Column {
    id: root
    property var shell: null
    property string problem: ""
    property bool customOptions: false
    property int layoutChoice: 0
    property int variantChoice: 0
    readonly property int statusRevision: shell === null ? 0 : shell.status.revision
    property var catalogStatus: ({ state: "pending", layouts: [] })
    property string catalogKey: ""
    readonly property var catalog: catalogStatus.layouts
    readonly property var sources: shell === null ? [] : Logic.sources(layoutSource.shownValue || "", variantSource.shownValue || "", shell.hyprland.devices)
    readonly property var variants: catalog.length === 0 ? [] : [{ code: "", name: "Default" }].concat(catalog[Math.min(layoutChoice, catalog.length - 1)].variants)
    readonly property Item firstFocus: sourceList.count > 0 ? sourceList : layoutPicker
    spacing: Theme.stack.group
    onStatusRevisionChanged: refreshStatus()
    onShellChanged: refreshStatus()
    Keys.onPressed: event => {
        if (sourceList.activeFocus && (event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_Up || event.key === Qt.Key_Down)) {
            root.editSource(sourceList.currentKey, event.key === Qt.Key_Up ? "up" : "down");
            event.accepted = true;
        }
    }

    function refreshStatus() {
        const values = shell === null ? {} : shell.status.values;
        const next = values.catalog === undefined ? ({ state: "pending", layouts: [] }) : values.catalog;
        const key = JSON.stringify(next);
        // Active-layout writes must retain the catalog and its list models.
        if (key === catalogKey) return;
        catalogKey = key;
        catalogStatus = next;
    }

    function addSource() {
        const result = Logic.addSource(sources, catalog[layoutChoice].code, variants[variantChoice].code);
        if (!result.ok) { problem = "Use up to four input sources."; return; }
        saveSources(result.rows);
    }

    function setValue(key, value) {
        const reply = shell.configure.set(key, value);
        problem = reply === "ok" ? "" : "VGS could not save this setting.";
        if (reply !== "ok") console.warn("keyboard: configure " + reply);
        return reply;
    }

    function saveSources(rows) {
        const values = Logic.serialize(rows);
        if (setValue("variants", values.variants) !== "ok") return;
        setValue("layouts", values.layouts);
    }

    function editSource(key, action) {
        const index = Number(key);
        if (action === "remove") saveSources(Logic.removeSource(sources, index));
        else {
            const delta = action === "up" ? -1 : 1;
            saveSources(Logic.moveSource(sources, index, delta));
            sourceList.current = Math.max(0, Math.min(sources.length - 1, index + delta));
        }
    }

    function useHyprlandValue(key) {
        // Variants share the source-list editor, outside this read-only row.
        if (key === "variants") sourceList.forceActiveFocus();
        const reply = shell.configure.unset(key);
        problem = reply === "ok" ? "" : "VGS could not save this setting.";
        if (reply !== "ok") console.warn("keyboard: configure " + reply);
    }

    function openHyprlandConfig() {
        const reply = shell.tui.edit("hypr/hyprland.lua");
        if (reply !== "ok") console.warn("keyboard: edit " + reply);
    }

    component KeyboardRow: ValueSourceRow {
        property string setting: ""

        width: parent.width
        hyprland: root.shell === null ? null : root.shell.hyprland
        path: root.shell === null ? "" : root.shell.manifest.hyprland.options[setting] || ""
        source: hyprlandValue !== undefined ? "hyprland" : "user"
        userValue: root.shell === null ? undefined : root.shell.settings[setting]
        onUseHyprlandValue: root.useHyprlandValue(setting)
        onOpenHyprlandConfig: root.openHyprlandConfig()
    }

    SectionHeader { width: parent.width; text: "Input Sources"; description: "Add a layout and choose its variant. The list sets the switch order." }

    Column {
        width: parent.width
        spacing: Theme.stack.row
        KeyboardRow {
            id: layoutSource
            setting: "layouts"
            label: "Input sources"
            labelColumn: false
            DeviceList {
                id: sourceList
                objectName: "inputSources"
                width: parent.width
                rows: Logic.sourceRows(root.sources, root.catalog)
                removable: root.sources.length > 1
                menuOf: row => [
                    { key: "up", text: "Move up", iconName: "arrow-up" },
                    { key: "down", text: "Move down", iconName: "arrow-down" },
                    { key: "remove", text: "Remove", iconName: "trash" }
                ].filter(entry => (entry.key !== "up" || Number(row.key) > 0)
                    && (entry.key !== "down" || Number(row.key) < root.sources.length - 1)
                    && (entry.key !== "remove" || root.sources.length > 1))
                onChose: (key, entry) => root.editSource(key, entry)
                onRemoved: key => root.editSource(key, "remove")
            }
        }
        KeyboardRow {
            id: variantSource
            setting: "variants"
            label: "Variants"
            Label {
                width: parent.width
                role: "value"
                text: Logic.sourceRows(root.sources, root.catalog).map(row => row.secondary).join(", ")
                wrapMode: Text.Wrap
            }
        }

        Label {
            visible: root.catalogStatus.state !== "ready"
            width: parent.width
            role: "hint"
            text: root.catalogStatus.state === "failed" ? "The system layout list could not be read." : "Reading the system layout list…"
            wrapMode: Text.Wrap
        }
        Card {
            SectionHeader { width: parent.width; text: "Add input source" }
            FormRow {
                width: parent.width
                label: "Layout"
                Select {
                    id: layoutPicker
                    objectName: "layoutPicker"
                    enabled: root.catalog.length > 0
                    model: root.catalog
                    textRole: "name"
                    currentIndex: root.layoutChoice
                    onActivated: index => { root.layoutChoice = index; root.variantChoice = 0; }
                }
            }
            FormRow {
                width: parent.width
                label: "Variant"
                Select {
                    objectName: "variantPicker"
                    enabled: root.variants.length > 0
                    model: root.variants
                    textRole: "name"
                    currentIndex: root.variantChoice
                    onActivated: index => root.variantChoice = index
                }
            }
            Button {
                objectName: "addSource"
                text: "Add input source"
                iconName: "plus"
                enabled: root.catalog.length > 0
                onClicked: root.addSource()
            }
        }
        RowAction {
            objectName: "systemLayout"
            text: "Use system layout"
            onClicked: {
                const reply = root.shell.configure.unset("variants");
                if (reply === "ok") root.shell.configure.unset("layouts");
                else root.problem = "VGS could not save this setting.";
            }
        }
    }

    SectionHeader { width: parent.width; text: "Key Repeat"; description: "Set how a held key repeats." }
    // Reserve the widest supported value so both slider tracks stay aligned.
    Label { id: repeatColumn; visible: false; role: "value"; text: "2000 ms" }
    Column {
        width: parent.width
        spacing: Theme.stack.row
        Repeater {
            model: [{ key: "repeatRate", label: "Repeat rate", maximum: 200, unit: "/s" }, { key: "repeatDelay", label: "Repeat delay", maximum: 2000, unit: "ms" }]
            KeyboardRow {
                id: repeatRow
                required property var modelData
                width: root.width
                label: modelData.label
                setting: modelData.key
                formatValue: value => value + " " + modelData.unit
                Item {
                    width: parent.width
                    implicitHeight: repeatSlider.implicitHeight
                    function commit() {
                        const wanted = Math.round(repeatSlider.value);
                        repeatSlider.value = Qt.binding(() => root.shell === null ? 0 : repeatRow.shownValue);
                        if (root.shell !== null && wanted !== repeatSlider.value) root.setValue(repeatRow.modelData.key, wanted);
                    }
                    Slider {
                        id: repeatSlider
                        objectName: repeatRow.modelData.key
                        width: parent.width - repeatValue.width - Theme.field.labelGap
                        from: 0
                        to: repeatRow.modelData.maximum
                        stepSize: 1
                        snapMode: T.Slider.SnapAlways
                        value: root.shell === null ? 0 : repeatRow.shownValue
                        onMoved: if (!pressed) parent.commit()
                        onPressedChanged: if (!pressed) parent.commit()
                    }
                    Label { id: repeatValue; width: repeatColumn.implicitWidth; horizontalAlignment: Text.AlignRight; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; role: "value"; text: Math.round(repeatSlider.value) + " " + repeatRow.modelData.unit }
                }
            }
        }
        TextField { objectName: "repeatTest"; width: parent.width; placeholderText: "Hold a key here to try repeat"; Accessible.name: "Test key repeat" }
    }

    SectionHeader { width: parent.width; text: "Modifier Options"; description: "Change modifier keys and the startup number pad." }
    Column {
        width: parent.width
        spacing: Theme.stack.row
        KeyboardRow {
            id: optionsSource
            setting: "options"
            label: "Modifier keys"
            Select {
                objectName: "modifierPicker"
                readonly property var presets: root.shell === null ? [] : root.shell.manifest.schema.options.presets
                model: presets.concat([{ label: "Custom…", value: null }])
                textRole: "label"
                currentIndex: {
                    const found = presets.findIndex(row => root.shell !== null && row.value === optionsSource.shownValue);
                    return found < 0 ? presets.length : found;
                }
                onActivated: index => {
                    root.customOptions = index === presets.length;
                    if (!root.customOptions) root.setValue("options", presets[index].value);
                }
            }
        }
        Field {
            visible: root.customOptions || (root.shell !== null && !root.shell.manifest.schema.options.presets.some(row => row.value === optionsSource.shownValue))
            width: parent.width
            label: "Custom options"
            hint: "Separate XKB option names with commas."
            TextField {
                objectName: "customOptions"
                width: parent.width
                text: root.shell === null ? "" : optionsSource.shownValue
                onEditingFinished: root.setValue("options", text)
            }
        }
        KeyboardRow {
            id: numlockSource
            setting: "numlockByDefault"
            label: "Startup Num Lock"
            formatValue: value => value ? "On" : "Off"
            Switch {
                checked: root.shell !== null && numlockSource.shownValue === true
                onToggled: {
                    const wanted = checked;
                    checked = Qt.binding(() => root.shell !== null && numlockSource.shownValue === true);
                    root.setValue("numlockByDefault", wanted);
                }
            }
        }
        Button {
            text: "Keyboard Shortcuts…"
            iconName: "keyboard"
            variant: "tertiary"
            onClicked: {
                const reply = root.shell.run.detached(["vgshell", "ipc", "call", "shell", "summon", "window", "vgs.keyhints", "{}"]);
                if (reply !== "ok") root.problem = "VGS could not open Keyboard Shortcuts.";
            }
        }
    }
    Label { visible: root.problem !== ""; width: parent.width; role: "hint"; color: Theme.color.danger; text: root.problem; wrapMode: Text.Wrap }
}
