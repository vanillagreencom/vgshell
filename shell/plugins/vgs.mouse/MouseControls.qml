import QtQuick
import QtQuick.Templates as T
import qs.Commons
import qs.Ui
import "MouseLogic.js" as Logic

Column {
    id: root

    property var shell: null
    property bool compact: false
    property string problem: ""
    readonly property var devices: shell === null ? null : shell.hyprland.devices
    readonly property var optionPaths: shell === null ? ({}) : shell.manifest.hyprland.options
    readonly property bool hasTouchpad: Logic.hasTouchpad(devices)
    readonly property Item firstFocus: pointerSpeed

    width: parent ? parent.width : implicitWidth
    spacing: Theme.stack.group

    function setValue(key, value) {
        const reply = shell.configure.set(key, value);
        problem = reply === "ok" ? "" : "VGS could not save this setting.";
        if (reply !== "ok") console.warn("mouse: configure " + reply);
        return reply;
    }

    // Stop setting KEY, so the user's own Hyprland value applies again.
    function useHyprlandValue(key) {
        const reply = shell.configure.unset(key);
        problem = reply === "ok" ? "" : "VGS could not save this setting.";
        if (reply !== "ok") console.warn("mouse: configure " + reply);
    }

    function openHyprlandConfig() {
        const answer = shell.tui.edit("hypr/hyprland.lua");
        if (answer !== "ok") console.warn("mouse: edit " + answer);
    }

    // The row of one setting: Hyprland's own value while VGS sets none, so
    // the row reads the user's own after Use my Hyprland value, else the
    // setting's.
    component MouseRow: ValueSourceRow {
        property string setting: ""

        width: parent.width
        hyprland: root.shell === null ? null : root.shell.hyprland
        path: root.optionPaths[setting] || ""
        source: hyprlandValue !== undefined ? "hyprland" : "user"
        userValue: root.shell === null ? undefined : root.shell.settings[setting]
        formatValue: value => Logic.valueText(setting, value)
        onUseHyprlandValue: root.useHyprlandValue(setting)
        onOpenHyprlandConfig: root.openHyprlandConfig()
    }

    SectionHeader {
        width: parent.width
        text: "Pointer"
        description: "Set mouse movement and scrolling."
    }

    Column {
        width: parent.width
        spacing: Theme.stack.row

        MouseRow {
            id: sensitivitySource
            setting: "sensitivity"
            label: "Pointer speed"
            Item {
                id: pointerSpeedRow
                width: parent.width
                implicitHeight: Math.max(pointerSpeed.implicitHeight, pointerSpeedValue.implicitHeight)

                // The rebound slider holds the shown value within its range,
                // as Slider clamps value, so a press that moved nothing saves
                // nothing, even over a user value past the range.
                function commit() {
                    const wanted = pointerSpeed.value;
                    pointerSpeed.value = Qt.binding(() => root.shell === null ? 0 : sensitivitySource.shownValue);
                    if (wanted !== pointerSpeed.value) root.setValue("sensitivity", wanted);
                }

                Slider {
                    id: pointerSpeed
                    width: parent.width - pointerSpeedValue.width - Theme.field.labelGap
                    anchors.verticalCenter: parent.verticalCenter
                    from: -1
                    to: 1
                    stepSize: 0.05
                    snapMode: T.Slider.SnapAlways
                    value: root.shell === null ? 0 : sensitivitySource.shownValue
                    onPressedChanged: if (!pressed) pointerSpeedRow.commit()
                    onMoved: if (!pressed) pointerSpeedRow.commit()
                }

                Label {
                    id: pointerSpeedValue
                    role: "label"
                    text: Logic.pointerSpeedText(pointerSpeed.value)
                    width: Math.max(implicitWidth, Theme.size.control.md)
                    horizontalAlignment: Text.AlignRight
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        MouseRow {
            id: accelProfileSource
            setting: "accelProfile"
            label: "Acceleration"
            SegmentedControl {
                model: ["Adaptive", "Flat"]
                currentIndex: root.shell === null ? 0 : Logic.profileIndex(accelProfileSource.shownValue)
                onActivated: index => root.setValue("accelProfile", Logic.profileAt(index))
            }
        }

        MouseRow {
            id: naturalScrollSource
            setting: "naturalScroll"
            label: "Natural scroll"
            Switch {
                size: "sm"
                Accessible.name: "Natural scroll"
                checked: root.shell !== null && naturalScrollSource.shownValue === true
                onToggled: {
                    const wanted = checked;
                    checked = Qt.binding(() => root.shell !== null && naturalScrollSource.shownValue === true);
                    root.setValue("naturalScroll", wanted);
                }
            }
        }

        MouseRow {
            id: leftHandedSource
            visible: !root.compact
            setting: "leftHanded"
            label: "Left-handed"
            Switch {
                size: "sm"
                Accessible.name: "Left-handed"
                checked: root.shell !== null && leftHandedSource.shownValue === true
                onToggled: {
                    const wanted = checked;
                    checked = Qt.binding(() => root.shell !== null && leftHandedSource.shownValue === true);
                    root.setValue("leftHanded", wanted);
                }
            }
        }

        MouseRow {
            id: scrollFactorSource
            visible: !root.compact
            setting: "scrollFactor"
            label: "Scroll speed"
            Item {
                id: scrollSpeedRow
                width: parent.width
                implicitHeight: Math.max(scrollSpeed.implicitHeight, scrollSpeedValue.implicitHeight)

                function commit() {
                    const wanted = scrollSpeed.value;
                    scrollSpeed.value = Qt.binding(() => root.shell === null ? 1 : scrollFactorSource.shownValue);
                    if (wanted !== scrollSpeed.value) root.setValue("scrollFactor", wanted);
                }

                Slider {
                    id: scrollSpeed
                    width: parent.width - scrollSpeedValue.width - Theme.field.labelGap
                    anchors.verticalCenter: parent.verticalCenter
                    from: 0
                    to: 2
                    stepSize: 0.05
                    snapMode: T.Slider.SnapAlways
                    value: root.shell === null ? 1 : scrollFactorSource.shownValue
                    onPressedChanged: if (!pressed) scrollSpeedRow.commit()
                    onMoved: if (!pressed) scrollSpeedRow.commit()
                }

                Label {
                    id: scrollSpeedValue
                    role: "label"
                    text: Logic.factorText(scrollSpeed.value)
                    width: Math.max(implicitWidth, Theme.size.control.md)
                    horizontalAlignment: Text.AlignRight
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    SectionHeader {
        visible: root.hasTouchpad && !root.compact
        width: parent.width
        text: "Touchpad"
        description: "Set taps, clicks and touchpad scrolling."
    }

    Column {
        visible: root.hasTouchpad
        width: parent.width
        spacing: Theme.stack.row

        MouseRow {
            visible: root.compact
            setting: "touchpadEnabled"
            label: "Touchpad"
            Switch {
                size: "sm"
                Accessible.name: "Touchpad"
                checked: root.shell !== null && root.shell.settings.touchpadEnabled === true
                onToggled: {
                    const wanted = checked;
                    checked = Qt.binding(() => root.shell !== null && root.shell.settings.touchpadEnabled === true);
                    root.setValue("touchpadEnabled", wanted);
                }
            }
        }

        MouseRow {
            visible: !root.compact
            setting: "touchpadEnabled"
            label: "Touchpad"
            Switch {
                size: "sm"
                Accessible.name: "Touchpad"
                checked: root.shell !== null && root.shell.settings.touchpadEnabled === true
                onToggled: {
                    const wanted = checked;
                    checked = Qt.binding(() => root.shell !== null && root.shell.settings.touchpadEnabled === true);
                    root.setValue("touchpadEnabled", wanted);
                }
            }
        }

        MouseRow {
            id: tapToClickSource
            visible: !root.compact
            setting: "tapToClick"
            label: "Tap to click"
            Switch {
                size: "sm"
                Accessible.name: "Tap to click"
                checked: root.shell !== null && tapToClickSource.shownValue === true
                onToggled: {
                    const wanted = checked;
                    checked = Qt.binding(() => root.shell !== null && tapToClickSource.shownValue === true);
                    root.setValue("tapToClick", wanted);
                }
            }
        }

        MouseRow {
            id: touchpadNaturalScrollSource
            visible: !root.compact
            setting: "touchpadNaturalScroll"
            label: "Natural scroll"
            Switch {
                size: "sm"
                Accessible.name: "Touchpad natural scroll"
                checked: root.shell !== null && touchpadNaturalScrollSource.shownValue === true
                onToggled: {
                    const wanted = checked;
                    checked = Qt.binding(() => root.shell !== null && touchpadNaturalScrollSource.shownValue === true);
                    root.setValue("touchpadNaturalScroll", wanted);
                }
            }
        }

        MouseRow {
            id: disableWhileTypingSource
            visible: !root.compact
            setting: "disableWhileTyping"
            label: "Disable while typing"
            Switch {
                size: "sm"
                Accessible.name: "Disable while typing"
                checked: root.shell !== null && disableWhileTypingSource.shownValue === true
                onToggled: {
                    const wanted = checked;
                    checked = Qt.binding(() => root.shell !== null && disableWhileTypingSource.shownValue === true);
                    root.setValue("disableWhileTyping", wanted);
                }
            }
        }

        MouseRow {
            id: clickMethodSource
            visible: !root.compact
            setting: "clickMethod"
            label: "Two-finger right-click"
            Switch {
                size: "sm"
                Accessible.name: "Two-finger right-click"
                checked: root.shell !== null && clickMethodSource.shownValue === true
                onToggled: {
                    const wanted = checked;
                    checked = Qt.binding(() => root.shell !== null && clickMethodSource.shownValue === true);
                    root.setValue("clickMethod", wanted);
                }
            }
        }

        MouseRow {
            id: touchpadScrollFactorSource
            visible: !root.compact
            setting: "touchpadScrollFactor"
            label: "Touchpad scroll speed"
            Item {
                id: touchpadScrollSpeedRow
                width: parent.width
                implicitHeight: Math.max(touchpadScrollSpeed.implicitHeight, touchpadScrollSpeedValue.implicitHeight)

                function commit() {
                    const wanted = touchpadScrollSpeed.value;
                    touchpadScrollSpeed.value = Qt.binding(() => root.shell === null ? 1 : touchpadScrollFactorSource.shownValue);
                    if (wanted !== touchpadScrollSpeed.value) root.setValue("touchpadScrollFactor", wanted);
                }

                Slider {
                    id: touchpadScrollSpeed
                    width: parent.width - touchpadScrollSpeedValue.width - Theme.field.labelGap
                    anchors.verticalCenter: parent.verticalCenter
                    from: 0
                    to: 2
                    stepSize: 0.05
                    snapMode: T.Slider.SnapAlways
                    value: root.shell === null ? 1 : touchpadScrollFactorSource.shownValue
                    onPressedChanged: if (!pressed) touchpadScrollSpeedRow.commit()
                    onMoved: if (!pressed) touchpadScrollSpeedRow.commit()
                }

                Label {
                    id: touchpadScrollSpeedValue
                    role: "label"
                    text: Logic.factorText(touchpadScrollSpeed.value)
                    width: Math.max(implicitWidth, Theme.size.control.md)
                    horizontalAlignment: Text.AlignRight
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    Label {
        visible: root.problem !== ""
        width: parent.width
        role: "hint"
        color: Theme.color.danger
        text: root.problem
        wrapMode: Text.Wrap
    }
}
