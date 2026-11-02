import QtQuick
import qs.Commons
import qs.Ui

// A single shortcut hint row; a surface draws at most one, and leaves
// obvious keys out. Each `hints` entry is `{ key, text }` or
// `{ keys, text }`; `key: "Left/Right"` draws two caps, while
// `key: "Ctrl+Tab"` draws one chord.
Row {
    id: root

    property var hints: []
    // Row's padding is part of its implicit height, so every action footer
    // gets the same gap without a spacer in its dialog or card.
    // https://doc.qt.io/qt-6/qml-qtquick-row.html#topPadding-prop
    property bool afterActions: false

    spacing: Theme.stack.group
    topPadding: afterActions ? Theme.kbd.actionGap : 0

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
                role: "keyHint"
                // A fractional word width would put the next chord, and
                // a right-aligned row, between device-pixel columns.
                width: Math.ceil(implicitWidth)
                y: topForCapCenter(Math.max(Theme.kbd.height, caps.implicitHeight))
                text: pair.modelData.text
            }
        }
    }
}
