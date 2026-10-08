import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Ui

// A single shortcut hint row; a surface draws at most one, and leaves
// obvious keys out. Each `hints` entry is `{ key, text }` or
// `{ keys, text }`; `key: "Left/Right"` draws two caps, while
// `key: "Ctrl+Tab"` draws one chord.
Row {
    id: root

    property var hints: []

    spacing: Theme.stack.group

    function alternatives(entry) {
        if (entry.keys !== undefined) return entry.keys;
        const key = entry.key === undefined ? "" : String(entry.key);
        return key.indexOf("/") === -1 ? [key] : key.split("/").map(part => part.trim()).filter(part => part !== "");
    }

    Repeater {
        model: root.hints

        Row {
            id: pair

            required property var modelData
            readonly property var keys: root.alternatives(modelData)

            spacing: Theme.stack.inline

            Row {
                id: caps
                spacing: Theme.space.xs
                visible: pair.keys.length > 0 && !(pair.keys.length === 1 && pair.keys[0] === "")
                Repeater {
                    model: pair.keys
                    KeyCaps { shortcut: String(modelData) }
                }
            }

            Label {
                id: hintLabel
                role: "hint"
                y: topForCapCenter(Math.max(Theme.kbd.height, caps.implicitHeight))
                text: pair.modelData.text
                layer.enabled: visible
                layer.smooth: true
                // MultiEffect pads its text shadow in the label's layer.
                // The token's contrast() uses the actual hint colour's
                // luminance, so custom text colours keep the opposite tone.
                // doc.qt.io/qt-6/qml-qtquick-effects-multieffect.html
                layer.effect: MultiEffect {
                    objectName: "keyHintShadow"
                    readonly property real padding: Math.ceil(blurMax + Theme.keyHints.shadowOffset)
                    shadowEnabled: true
                    shadowColor: Theme.keyHints.shadow
                    shadowOpacity: Theme.keyHints.shadowOpacity
                    blurMax: Theme.keyHints.blur
                    shadowBlur: 1
                    shadowHorizontalOffset: Theme.keyHints.shadowOffset
                    shadowVerticalOffset: Theme.keyHints.shadowOffset
                    autoPaddingEnabled: false
                    paddingRect: Qt.rect(padding, padding, padding, padding)
                }
            }
        }
    }
}
