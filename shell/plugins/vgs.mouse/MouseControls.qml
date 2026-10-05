import QtQuick
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
            warning: Logic.overriddenText(root.overridden, "sensitivity")
            Slider {
                id: pointerSpeed
                width: parent.width
                from: -1
                to: 1
                stepSize: 0.05
                value: root.shell === null ? 0 : root.shell.settings.sensitivity
                onMoved: root.setValue("sensitivity", pointerSpeed.value)
            }
        }

        FormRow {
            width: parent.width
            label: "Acceleration"
            warning: Logic.overriddenText(root.overridden, "accelProfile")
            SegmentedControl {
                model: ["Adaptive", "Flat"]
                currentIndex: root.shell === null ? 0 : Logic.profileIndex(root.shell.settings.accelProfile)
                onActivated: index => root.setValue("accelProfile", Logic.profileAt(index))
            }
        }

        FormRow {
            width: parent.width
            label: "Natural scroll"
            warning: Logic.overriddenText(root.overridden, "naturalScroll")
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
            warning: Logic.overriddenText(root.overridden, "leftHanded")
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
            warning: Logic.overriddenText(root.overridden, "scrollFactor")
            Slider {
                id: scrollSpeed
                width: parent.width
                from: 0
                to: 2
                stepSize: 0.05
                value: root.shell === null ? 1 : root.shell.settings.scrollFactor
                onMoved: root.setValue("scrollFactor", scrollSpeed.value)
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
            warning: Logic.overriddenText(root.overridden, "touchpadEnabled")
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
            warning: Logic.overriddenText(root.overridden, "touchpadEnabled")
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
            warning: Logic.overriddenText(root.overridden, "tapToClick")
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
            warning: Logic.overriddenText(root.overridden, "touchpadNaturalScroll")
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
            warning: Logic.overriddenText(root.overridden, "disableWhileTyping")
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
            warning: Logic.overriddenText(root.overridden, "clickMethod")
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
            warning: Logic.overriddenText(root.overridden, "touchpadScrollFactor")
            Slider {
                id: touchpadScrollSpeed
                width: parent.width
                from: 0
                to: 2
                stepSize: 0.05
                value: root.shell === null ? 1 : root.shell.settings.touchpadScrollFactor
                onMoved: root.setValue("touchpadScrollFactor", touchpadScrollSpeed.value)
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
