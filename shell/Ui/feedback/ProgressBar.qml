import QtQuick
import QtQuick.Templates as T
import qs.Commons

// A progress bar. The template owns `from`, `to`, `value`, `position` and
// `indeterminate`; this file draws the track and the filled part, which
// is `position` long and starts from the right when mirrored. An
// `tone` defaults to accent, the theme's progress fill. Other tones use
// the Badge foreground tokens. An
// indeterminate bar slides a share of the track back and forth on
// `progress.duration`, and stands still when that duration is zero.
T.ProgressBar {
    id: root

    property string tone: "accent"

    function toneColor(name) {
        if (name === "accent") return Theme.progress.fill;
        const found = Theme.badge.tone[name];
        if (found !== undefined) return found.foreground;
        console.error('ProgressBar: no tone named "' + name + '"; drawing accent');
        return Theme.progress.fill;
    }

    implicitWidth: Theme.size.panel.sm / 2
    implicitHeight: Theme.progress.height

    background: Rectangle {
        radius: Theme.progress.radius
        color: Theme.progress.track
    }

    contentItem: Item {
        clip: true
        Rectangle {
            id: fill
            readonly property int span: parent.width * Theme.progress.indeterminateShare
            x: root.mirrored && !root.indeterminate ? parent.width - width : 0
            width: root.indeterminate ? span : root.position * parent.width
            height: parent.height
            radius: Theme.progress.radius
            color: root.toneColor(root.tone)
            SequentialAnimation on x {
                running: root.indeterminate && Theme.progress.duration > 0
                loops: Animation.Infinite
                onStopped: fill.x = Qt.binding(() => root.mirrored && !root.indeterminate ? fill.parent.width - fill.width : 0)
                NumberAnimation { from: 0; to: fill.parent.width - fill.span; duration: Theme.progress.duration; easing.type: Theme.motion.easing.standard }
                NumberAnimation { from: fill.parent.width - fill.span; to: 0; duration: Theme.progress.duration; easing.type: Theme.motion.easing.standard }
            }
        }
    }
}
