import QtQuick
import QtQuick.Templates as T
import qs.Commons

// A progress bar. The template owns `from`, `to`, `value`, `position` and
// `indeterminate`; this file draws the track and the filled part, which
// is `position` long and starts from the right when mirrored. `tone`
// defaults to accent, the theme's progress fill; `neutral`, for a bar
// that measures a quantity at rest, draws `progress.neutral`. Other tones
// use the Badge foreground tokens. An indeterminate bar slides a share of
// the track back and forth on `progress.duration`, and stands still when
// that duration is zero.
T.ProgressBar {
    id: root

    property string tone: "accent"
    property color trackColor: Theme.progress.track
    // Stops are relative to the filled span, which changes with value.
    property Gradient fillGradient: null

    function toneColor(name) {
        if (name === "accent") return Theme.progress.fill;
        if (name === "neutral") return Theme.progress.neutral;
        const found = Theme.badge.tone[name];
        if (found !== undefined) return found.foreground;
        console.error('ProgressBar: no tone named "' + name + '"; drawing accent');
        return Theme.progress.fill;
    }

    implicitWidth: Theme.size.panel.sm / 2
    // Control padding insets only the content, not the background (Qt 6
    // Control Layout: https://doc.qt.io/qt-6/qml-qtquick-controls-control.html).
    // Keep the gradient's track visible on every side without thinning its ink.
    padding: root.fillGradient === null ? 0 : Theme.border.thin
    implicitHeight: Theme.progress.height + topPadding + bottomPadding

    background: Rectangle {
        radius: Theme.progress.radius
        color: root.trackColor
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
            gradient: root.fillGradient
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
