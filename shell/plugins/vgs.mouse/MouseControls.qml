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
    readonly property var overridden: shell === null ? [] : shell.hyprland.overridden
    readonly property var userValues: shell === null ? [] : shell.hyprland.userValues
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

    // The action beside a row's line that names the user's own value.
    component UserValueButton: Button {
        property string setting: ""

        objectName: "useHyprlandValue"
        visible: Logic.hasUserValue(root.userValues, root.optionPaths, setting)
        variant: "secondary"
        size: "sm"
        text: "Use my Hyprland value"
        onClicked: root.useHyprlandValue(setting)
    }

    SectionHeader {
        width: parent.width
        text: "Pointer"
        description: "Set mouse movement and scrolling."
    }

    Column {
        width: parent.width
        spacing: Theme.stack.row

        FormRow {
            width: parent.width
            label: "Pointer speed"
            warning: Logic.warningText(root.overridden, root.userValues, root.optionPaths, "sensitivity")
            action: UserValueButton { setting: "sensitivity" }
            Item {
                id: pointerSpeedRow
                width: parent.width
                implicitHeight: Math.max(pointerSpeed.implicitHeight, pointerSpeedValue.implicitHeight)

                function commit() {
                    const wanted = pointerSpeed.value;
                    pointerSpeed.value = Qt.binding(() => root.shell === null ? 0 : root.shell.settings.sensitivity);
                    if (wanted !== (root.shell === null ? 0 : root.shell.settings.sensitivity)) root.setValue("sensitivity", wanted);
                }

                Slider {
                    id: pointerSpeed
                    width: parent.width - pointerSpeedValue.width - Theme.field.labelGap
                    anchors.verticalCenter: parent.verticalCenter
                    from: -1
                    to: 1
                    stepSize: 0.05
                    snapMode: T.Slider.SnapAlways
                    value: root.shell === null ? 0 : root.shell.settings.sensitivity
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

        FormRow {
            width: parent.width
            label: "Acceleration"
            warning: Logic.warningText(root.overridden, root.userValues, root.optionPaths, "accelProfile")
            action: UserValueButton { setting: "accelProfile" }
            SegmentedControl {
                model: ["Adaptive", "Flat"]
                currentIndex: root.shell === null ? 0 : Logic.profileIndex(root.shell.settings.accelProfile)
                onActivated: index => root.setValue("accelProfile", Logic.profileAt(index))
            }
        }

        FormRow {
            width: parent.width
            label: "Natural scroll"
            warning: Logic.warningText(root.overridden, root.userValues, root.optionPaths, "naturalScroll")
            action: UserValueButton { setting: "naturalScroll" }
            Switch {
                size: "sm"
                Accessible.name: "Natural scroll"
                checked: root.shell !== null && root.shell.settings.naturalScroll === true
                onToggled: {
                    const wanted = checked;
                    checked = Qt.binding(() => root.shell !== null && root.shell.settings.naturalScroll === true);
                    root.setValue("naturalScroll", wanted);
                }
            }
        }

        FormRow {
            visible: !root.compact
            width: parent.width
            label: "Left-handed"
            warning: Logic.warningText(root.overridden, root.userValues, root.optionPaths, "leftHanded")
            action: UserValueButton { setting: "leftHanded" }
            Switch {
                size: "sm"
                Accessible.name: "Left-handed"
                checked: root.shell !== null && root.shell.settings.leftHanded === true
                onToggled: {
                    const wanted = checked;
                    checked = Qt.binding(() => root.shell !== null && root.shell.settings.leftHanded === true);
                    root.setValue("leftHanded", wanted);
                }
            }
        }

        FormRow {
            visible: !root.compact
            width: parent.width
            label: "Scroll speed"
            warning: Logic.warningText(root.overridden, root.userValues, root.optionPaths, "scrollFactor")
            action: UserValueButton { setting: "scrollFactor" }
            Item {
                id: scrollSpeedRow
                width: parent.width
                implicitHeight: Math.max(scrollSpeed.implicitHeight, scrollSpeedValue.implicitHeight)

                function commit() {
                    const wanted = scrollSpeed.value;
                    scrollSpeed.value = Qt.binding(() => root.shell === null ? 1 : root.shell.settings.scrollFactor);
                    if (wanted !== (root.shell === null ? 1 : root.shell.settings.scrollFactor)) root.setValue("scrollFactor", wanted);
                }

                Slider {
                    id: scrollSpeed
                    width: parent.width - scrollSpeedValue.width - Theme.field.labelGap
                    anchors.verticalCenter: parent.verticalCenter
                    from: 0
                    to: 2
                    stepSize: 0.05
                    snapMode: T.Slider.SnapAlways
                    value: root.shell === null ? 1 : root.shell.settings.scrollFactor
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

        FormRow {
            visible: root.compact
            width: parent.width
            label: "Touchpad"
            warning: Logic.warningText(root.overridden, root.userValues, root.optionPaths, "touchpadEnabled")
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

        FormRow {
            visible: !root.compact
            width: parent.width
            label: "Touchpad"
            warning: Logic.warningText(root.overridden, root.userValues, root.optionPaths, "touchpadEnabled")
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

        FormRow {
            visible: !root.compact
            width: parent.width
            label: "Tap to click"
            warning: Logic.warningText(root.overridden, root.userValues, root.optionPaths, "tapToClick")
            action: UserValueButton { setting: "tapToClick" }
            Switch {
                size: "sm"
                Accessible.name: "Tap to click"
                checked: root.shell !== null && root.shell.settings.tapToClick === true
                onToggled: {
                    const wanted = checked;
                    checked = Qt.binding(() => root.shell !== null && root.shell.settings.tapToClick === true);
                    root.setValue("tapToClick", wanted);
                }
            }
        }

        FormRow {
            visible: !root.compact
            width: parent.width
            label: "Natural scroll"
            warning: Logic.warningText(root.overridden, root.userValues, root.optionPaths, "touchpadNaturalScroll")
            action: UserValueButton { setting: "touchpadNaturalScroll" }
            Switch {
                size: "sm"
                Accessible.name: "Touchpad natural scroll"
                checked: root.shell !== null && root.shell.settings.touchpadNaturalScroll === true
                onToggled: {
                    const wanted = checked;
                    checked = Qt.binding(() => root.shell !== null && root.shell.settings.touchpadNaturalScroll === true);
                    root.setValue("touchpadNaturalScroll", wanted);
                }
            }
        }

        FormRow {
            visible: !root.compact
            width: parent.width
            label: "Disable while typing"
            warning: Logic.warningText(root.overridden, root.userValues, root.optionPaths, "disableWhileTyping")
            action: UserValueButton { setting: "disableWhileTyping" }
            Switch {
                size: "sm"
                Accessible.name: "Disable while typing"
                checked: root.shell !== null && root.shell.settings.disableWhileTyping === true
                onToggled: {
                    const wanted = checked;
                    checked = Qt.binding(() => root.shell !== null && root.shell.settings.disableWhileTyping === true);
                    root.setValue("disableWhileTyping", wanted);
                }
            }
        }

        FormRow {
            visible: !root.compact
            width: parent.width
            label: "Two-finger right-click"
            warning: Logic.warningText(root.overridden, root.userValues, root.optionPaths, "clickMethod")
            action: UserValueButton { setting: "clickMethod" }
            Switch {
                size: "sm"
                Accessible.name: "Two-finger right-click"
                checked: root.shell !== null && root.shell.settings.clickMethod === true
                onToggled: {
                    const wanted = checked;
                    checked = Qt.binding(() => root.shell !== null && root.shell.settings.clickMethod === true);
                    root.setValue("clickMethod", wanted);
                }
            }
        }

        FormRow {
            visible: !root.compact
            width: parent.width
            label: "Touchpad scroll speed"
            warning: Logic.warningText(root.overridden, root.userValues, root.optionPaths, "touchpadScrollFactor")
            action: UserValueButton { setting: "touchpadScrollFactor" }
            Item {
                id: touchpadScrollSpeedRow
                width: parent.width
                implicitHeight: Math.max(touchpadScrollSpeed.implicitHeight, touchpadScrollSpeedValue.implicitHeight)

                function commit() {
                    const wanted = touchpadScrollSpeed.value;
                    touchpadScrollSpeed.value = Qt.binding(() => root.shell === null ? 1 : root.shell.settings.touchpadScrollFactor);
                    if (wanted !== (root.shell === null ? 1 : root.shell.settings.touchpadScrollFactor)) root.setValue("touchpadScrollFactor", wanted);
                }

                Slider {
                    id: touchpadScrollSpeed
                    width: parent.width - touchpadScrollSpeedValue.width - Theme.field.labelGap
                    anchors.verticalCenter: parent.verticalCenter
                    from: 0
                    to: 2
                    stepSize: 0.05
                    snapMode: T.Slider.SnapAlways
                    value: root.shell === null ? 1 : root.shell.settings.touchpadScrollFactor
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
