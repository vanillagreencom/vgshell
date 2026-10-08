import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import qs.Commons
import qs.Ui
import "../foundation/KeyNavLogic.js" as KeyNavLogic

// A key combo entry the user presses instead of typing. The box shows
// `keys`, the shortcut's alternative keys in effect, each as its own key
// caps with "or" between them, so alternatives never read as one chord,
// and the border and focus ring surround them all, wrapping onto more
// lines when they need the room. One alternative is the one edited,
// `editing`, and `key` is its combo: a click on an alternative edits it,
// Left and Right move to the next one, Delete removes it, and while the
// box has the focus a selection mark shows which one it is. `add()` edits
// a new alternative after the last. A click, Enter, Return or Space starts
// a capture for the alternative edited, and the box then takes every key:
// held modifiers show as caps, the first other key commits the combo, and
// Escape or a focus loss cancels. `capture` is the core's key capture member,
// `shell.shortcut.capture`, which owns the capture and the Hyprland
// pass-through that lets a combo a bind holds reach the box; the field asks
// it to begin and end and asks it what each key names, and never reaches
// Hyprland itself. A held key's repeats do nothing; a key that types or
// edits text with no modifier but Shift would stop typing everywhere, so it
// shows a notice and the capture goes on; Tab and Shift+Tab end the capture
// and move the focus, as everywhere else. A combo equal to the key in
// effect ends the capture and changes nothing. A capture whose
// pass-through Hyprland refused says Hyprland's own shortcuts still run, and
// one Hyprland ended after its timeout says so. With no `capture` the box
// only types. The keyboard
// button swaps the box for a text field that takes the combo as `MOD+KEY`,
// for a key the capture cannot name, the key in effect selected so typing
// replaces it; Enter there types it, and Escape first restores the key in
// effect, as a text field's `escapeReverts` does, then goes back to the box.
// A loss of focus leaves the entry open on its text and sends nothing:
// `edited` says the entry holds a text other than the key in effect,
// `acceptTyped()` sends it as Enter does, `startTyping(text)` opens the
// entry on a text its owner hands back, such as a key it refused, and
// `stopTyping()` drops it. Each edit names the index of the alternative it
// changes: `committed(key, index)` reports a captured combo, written as the
// text field's judge writes it, `typed(text, index)` a typed one as
// entered, and `cleared(index)` the clear button or Delete, which removes
// that alternative. `conflict` is a hint drawn under the box in
// the warning colour; it never blocks a combo. With `pluginId` and
// `shortcut` naming the plugin bind the keys belong to, `found` is the
// capture's `conflicts` answer for the first alternative another holder
// asks for, else for the first alternative, with `key` naming that
// alternative, and `conflict` its `hint`, so every field that shows a
// bind's keys shows the same line.
// `hintLink`, when set, names the substring of that conflict line that
// opens a cited file through `hintLinkActivated`. The
// `hintActions` are controls for the hint, such as the ways out of a
// conflict it names, RowActions: they draw on a line of their own under
// it, `rowAction.gap` apart, wrapping within the field's width, and take
// no room while none shows. The
// field is one focus scope whose focus starts on the box, one tab stop
// whose arrows move among the alternatives through KeyNav; Enter, Return
// and keypad Enter activate the alternative edited through it, or the box
// through KeyNavLogic.activate while none is there, as every button-like
// control does (docs/architecture/design-system.md § Keyboard), and `focusPreview` draws its focus ring for the
// gallery.
FocusScope {
    id: root

    readonly property real minimumWidth: Theme.field.minWidth
    readonly property real maximumWidth: Theme.control.maxWidth
    Layout.minimumWidth: minimumWidth
    Layout.maximumWidth: maximumWidth
    width: Math.max(minimumWidth, Math.min(maximumWidth, implicitWidth))
    InputWidth { target: root }

    property var keys: []
    property var capture: null
    property bool editable: true
    property string placeholder: "Unbound"
    // The plugin id and shortcut name of the bind the key belongs to, ""
    // for a key that is no plugin bind's.
    property string pluginId: ""
    property string shortcut: ""
    // The alternative the box edits, kept as the last one picked; `adding`
    // edits a new one after the last until the field leaves the focus, an
    // Escape cancels the capture or the edit is sent.
    property int current: 0
    property bool adding: false
    readonly property int editing: adding ? keys.length : Math.max(0, Math.min(current, keys.length - 1))
    readonly property string key: editing < keys.length ? String(keys[editing]) : ""
    // Who else asks for the keys, as the capture's `conflicts` answers, or
    // null with no capture, no bind or no key.
    readonly property var found: {
        if (capture === null || pluginId === "") return null;
        let first = null;
        for (const each of keys) {
            const answer = Object.assign({ key: String(each) }, capture.conflicts(String(each), pluginId, shortcut));
            if (answer.hint !== "") return answer;
            if (first === null) first = answer;
        }
        return first;
    }
    property string conflict: found === null ? "" : found.hint
    property string hintLink: ""
    property bool focusPreview: false
    property alias actions: actionRow.data
    property alias hintActions: hintActionRow.data
    readonly property bool capturing: capture !== null && capture.holder === root
    // Whether the text entry is open: stored, since the entry's own
    // `visible` reads false under a hidden ancestor, and a typed key is
    // an edit there too.
    readonly property alias typing: entry.open
    readonly property bool edited: typing && entry.text.trim() !== key
    // The modifiers held while capturing, in the order a key writes them.
    property var held: []
    property string notice: ""
    // What the line under the box says: the notice, else the failed
    // pass-through while it captures, else the conflict.
    readonly property string hint: notice !== "" ? notice
        : capturing && capture.failed ? "Hyprland's own shortcuts still run, so a combo they hold does not reach this field. Type it with the keyboard button instead."
        : conflict
    readonly property bool hintIsNotice: notice !== "" || (capturing && capture.failed)
    // The gap a medium field leaves above a key cap centred in it. The
    // caps keep it on every side, so their left edge stands as far from the
    // border as their top, on one line or several.
    readonly property real inset: (Theme.textField.height - Theme.kbd.height) / 2
    readonly property real sidePadding: Theme.controlPadding(inset, Theme.textField.radius, Math.max(Theme.textField.height, box.height), box.implicitContentHeight)
    // The box's share of the line beside the buttons, which a prompt
    // elides to; the box takes more when an alternative's caps need it.
    readonly property real room: Math.max(0, line.width - tools.width - line.spacing)
    readonly property var caps: capturing ? held : key === "" ? [] : key.split("+")
    // What the box draws, one group per alternative: the combo its caps
    // spell and the text that stands in while it has none. A new
    // alternative draws while its capture runs.
    readonly property var groups: {
        const live = capturing ? editing : -1;
        const count = Math.max(1, keys.length, live + 1);
        const out = [];
        for (let i = 0; i < count; i++) {
            const combo = i === live ? held.join("+") : i < keys.length ? String(keys[i]) : "";
            const text = i === live ? (held.length === 0 ? "Press keys, Escape to cancel" : "") : keys.length === 0 ? placeholder : "";
            out.push({ combo: combo, text: text });
        }
        return out;
    }
    signal committed(string key, int index)
    signal typed(string text, int index)
    signal cleared(int index)
    signal hintLinkActivated()

    implicitWidth: box.implicitWidth + line.spacing + tools.implicitWidth
    implicitHeight: column.implicitHeight

    function start() {
        if (capture === null) return;
        held = [];
        notice = "";
        capture.begin(root);
    }

    function stop(reason) {
        if (capturing) capture.end(root, reason);
    }

    // Escape drops a new alternative with its capture.
    function cancel() {
        adding = false;
        stop("cancel");
    }

    // Edit alternative INDEX, a new one past the last, and listen for it.
    function edit(index) {
        adding = index >= keys.length;
        current = index;
        start();
    }

    function add() {
        root.forceActiveFocus(Qt.TabFocusReason);
        edit(keys.length);
    }

    // After an edit sent for alternative AT, the box edits it, unless the
    // entry reopened on a refused key, which stays the one edited.
    function sent(at) {
        if (typing) return;
        current = at;
        adding = false;
    }

    // The alternative drawn at X in the box, else the one edited.
    function groupAt(x) {
        for (let i = 0; i < groupRepeater.count; i++) {
            const group = groupRepeater.itemAt(i).chips;
            const left = group.mapToItem(box, 0, 0).x;
            if (x >= left && x < left + group.width) return i;
        }
        return editing;
    }

    function pressed(event) {
        if ((event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) && (event.modifiers & ~Qt.ShiftModifier) === Qt.NoModifier) {
            stop("tab");
            event.accepted = false;
            return;
        }
        event.accepted = true;
        if (event.isAutoRepeat) return;
        if (event.key === Qt.Key_Escape) {
            cancel();
            return;
        }
        const read = capture.keyFor(event.key, event.modifiers);
        switch (read.kind) {
        case "held":
            held = read.modifiers;
            notice = "";
            return;
        case "unnamed":
            notice = "This key has no name here; type it with the keyboard button.";
            return;
        case "text":
            notice = "Hold Super, Ctrl or Alt with this key: alone it types text, so a shortcut on it would stop typing everywhere.";
            return;
        case "key": {
            const at = editing;
            stop("commit");
            if (read.key !== key) committed(read.key, at);
            sent(at);
            return;
        }
        }
        throw new Error("ShortcutField: key kind " + JSON.stringify(read.kind) + " is not one of held, unnamed, text, key");
    }

    // Enter and Return have handlers of their own, which run before
    // `Keys.onPressed`.
    function enterPressed(event) {
        if (capturing) pressed(event);
        else if (!nav.handle(event)) KeyNavLogic.activate(box);
    }

    function released(event) {
        event.accepted = true;
        const gone = capture.keyFor(event.key, Qt.NoModifier);
        if (gone.kind === "held") held = held.filter(mod => gone.modifiers.indexOf(mod) === -1);
    }

    // No capture outlives the opening: the box ends one when it commits
    // a key and when it loses the focus, which the entry takes here. The
    // entry opens on `text`, the key in effect when none is given.
    function startTyping(text) {
        entry.text = text === undefined ? key : text;
        entry.selectAll();
        entry.open = true;
        entry.forceActiveFocus(Qt.TabFocusReason);
    }

    // The box takes the keyboard when the field holds it; when a caller
    // ends the typing from elsewhere, such as a page's Save, the keyboard
    // stays where it is and the box is the field's focus for a later Tab.
    function stopTyping() {
        closeEntry();
        adding = false;
    }

    function closeEntry() {
        entry.open = false;
        if (root.activeFocus) box.forceActiveFocus(Qt.TabFocusReason);
        else box.focus = true;
    }

    function acceptTyped() {
        const text = entry.text.trim();
        const at = root.editing;
        root.closeEntry();
        if (text !== root.key) root.typed(text, at);
        root.sent(at);
    }

    // Escape the text entry leaves unaccepted, with the key in effect
    // already back, ends the typing; any other Escape goes on up.
    Keys.onEscapePressed: event => {
        if (!typing) {
            event.accepted = false;
            return;
        }
        stopTyping();
    }

    onActiveFocusChanged: if (!activeFocus && !typing) adding = false

    onCapturingChanged: {
        if (capturing) return;
        held = [];
        if (capture !== null && capture.ended.item === root && capture.ended.reason === "timeout")
            notice = "Listening stopped after " + Math.round(capture.timeoutMs / 1000) + " s. Press Return or click the field to listen again.";
    }

    // Idle rows need the glyph and its reserved space, not a button's
    // focus ring, pointer handlers and tooltip. A pointer over the tools
    // or keyboard focus in the field builds the real IconButtons before
    // use. The slot itself enters the Tab chain while unloaded, so reverse
    // Tab can reach its button too; the Loader then owns its destruction.
    // https://doc.qt.io/qt-6.8/qml-qtquick-loader.html
    component ToolSlot: FocusScope {
        id: tool
        required property string iconName
        required property string label
        property bool inUse: false
        readonly property alias button: control.item
        signal clicked()

        width: Math.max(Theme.control.minWidth, Math.min(Theme.control.maxWidth, Theme.size.control.sm))
        height: Theme.size.control.sm
        activeFocusOnTab: !control.active
        onActiveFocusChanged: if (activeFocus && control.item) control.item.forceActiveFocus(Qt.TabFocusReason)

        Icon {
            name: tool.iconName
            size: Theme.button.size.sm.icon
            color: Theme.color.textMuted
            x: Math.floor((tool.width - size) / 2)
            y: Math.floor((tool.height - size) / 2)
            visible: !control.active
        }
        Loader {
            id: control
            anchors.fill: parent
            active: tool.visible && tool.enabled && (tool.inUse || tool.activeFocus)
            focus: true
            onLoaded: if (tool.activeFocus) item.forceActiveFocus(Qt.TabFocusReason)
            sourceComponent: IconButton {
                iconName: tool.iconName
                label: tool.label
                size: "sm"
                focus: true
                onClicked: tool.clicked()
            }
        }
    }

    Column {
        id: column
        width: parent.width
        spacing: Theme.field.gap

        Row {
            id: line
            width: parent.width
            spacing: Theme.textField.gap

            T.AbstractButton {
                id: box
                readonly property bool focusPreview: root.focusPreview
                visible: !root.typing
                focus: true
                // The room beside the buttons, never less than the widest
                // alternative: a combo's caps do not wrap, and a narrower
                // box would leave them outside its border and ring, under
                // the buttons. Unsized, the box is a text field's width.
                width: Math.max(implicitContentWidth + leftPadding + rightPadding, root.room)
                implicitWidth: Math.max(Theme.size.panel.sm / 2, implicitContentWidth + leftPadding + rightPadding)
                implicitHeight: Math.max(Theme.textField.height, groupFlow.implicitHeight + 2 * root.inset)
                leftPadding: root.sidePadding
                rightPadding: root.sidePadding
                enabled: root.editable
                focusPolicy: root.editable ? Qt.StrongFocus : Qt.NoFocus
                hoverEnabled: true
                opacity: enabled ? 1 : Theme.opacity.disabled
                Accessible.role: Accessible.Button
                Accessible.name: root.capturing ? "Press keys" : root.keys.length === 0 ? root.placeholder : root.keys.join(" or ")
                PointerCursor {}
                // A key click lands mid-box, so only the pointer picks an
                // alternative; a new one keeps being the one edited.
                onClicked: root.edit(root.adding ? root.editing : root.groupAt(box.pressX))
                onActiveFocusChanged: if (!activeFocus) root.stop("focus")
                // The navigator takes the arrows that move among the
                // alternatives, Delete and Space; Page Up, Page Down, Home
                // and End go on to the page around the field. Space, like
                // Enter and Return, reaches the button while no alternative
                // is there for the navigator to activate.
                Keys.onPressed: event => {
                    if (root.capturing) root.pressed(event);
                    else event.accepted = [Qt.Key_Left, Qt.Key_Right, Qt.Key_Delete, Qt.Key_Space].indexOf(event.key) !== -1 && nav.handle(event);
                }
                Keys.onReturnPressed: event => root.enterPressed(event)
                Keys.onEnterPressed: event => root.enterPressed(event)
                Keys.onReleased: event => { if (root.capturing) root.released(event); }

                KeyNav {
                    id: nav
                    count: root.keys.length
                    currentIndex: root.editing
                    orientation: "horizontal"
                    wrap: false
                    onMoved: index => {
                        root.current = index;
                        root.adding = false;
                    }
                    onActivated: index => root.edit(index)
                    onRemoved: index => { if (root.editable) root.cleared(index); }
                }

                background: Rectangle {
                    radius: Theme.textField.radius
                    color: Theme.textField.background
                    border.width: Theme.textField.border
                    border.color: root.capturing || box.activeFocus ? Theme.textField.focus : box.hovered ? Theme.textField.hover : Theme.textField.borderColor
                    Behavior on border.color { ColorAnimation { duration: Theme.motion.duration.fast; easing.type: Theme.motion.easing.standard } }
                    FocusRing { target: box }
                }

                // The flow's implicit width is its widest line, which is
                // the widest alternative when one is wider than the box.
                contentItem: Item {
                    implicitWidth: groupFlow.implicitWidth
                    implicitHeight: groupFlow.implicitHeight

                    Flow {
                        id: groupFlow
                        width: parent.width
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.space.sm

                        Repeater {
                            id: groupRepeater
                            model: root.groups

                            Row {
                                id: group
                                required property var modelData
                                required property int index
                                readonly property alias chips: chips
                                spacing: Theme.space.sm

                                Label {
                                    objectName: "alternativeSeparator"
                                    role: "item"
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: Theme.textField.placeholder
                                    text: "or"
                                    visible: group.index > 0
                                }

                                Item {
                                    id: chips
                                    anchors.verticalCenter: parent.verticalCenter
                                    implicitWidth: chipRow.implicitWidth
                                    implicitHeight: chipRow.implicitHeight

                                    Rectangle {
                                        anchors.fill: parent
                                        anchors.margins: -Theme.space.xxs
                                        radius: Theme.kbd.radius
                                        color: Theme.color.selection
                                        visible: root.groups.length > 1 && group.index === root.editing && (box.activeFocus || root.capturing)
                                    }

                                    Row {
                                        id: chipRow
                                        spacing: comboCaps.visible && prompt.visible ? Theme.space.sm : 0
                                        KeyCaps {
                                            id: comboCaps
                                            anchors.verticalCenter: parent.verticalCenter
                                            shortcut: group.modelData.combo
                                        }
                                        Label {
                                            id: prompt
                                            role: root.capturing ? "item" : "kbd"
                                            width: Math.min(implicitWidth, Math.max(0, root.room - box.leftPadding - box.rightPadding))
                                            anchors.verticalCenter: parent.verticalCenter
                                            elide: Text.ElideRight
                                            color: Theme.textField.placeholder
                                            text: group.modelData.text
                                            visible: text !== ""
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            TextField {
                id: entry
                property bool open: false
                visible: open
                width: box.width
                placeholderText: "MOD+KEY, such as SUPER+SPACE"
                escapeReverts: true
                committedText: root.key
                onAccepted: root.acceptTyped()
            }

            Row {
                id: tools
                spacing: Theme.textField.gap
                anchors.verticalCenter: parent.verticalCenter
                HoverHandler { id: toolsHover }
                ToolSlot {
                    iconName: "keyboard"
                    label: "Type the keys"
                    inUse: root.visible && (root.activeFocus || toolsHover.hovered)
                    visible: root.editable && !root.typing
                    onClicked: root.startTyping()
                }
                ToolSlot {
                    iconName: "x"
                    label: root.keys.length > 1 ? "Remove " + KeyNavLogic.keyCaps(root.key).join("+") : "Unbind"
                    inUse: root.visible && (root.activeFocus || toolsHover.hovered)
                    visible: root.editable; enabled: root.editable && root.key !== ""
                    opacity: root.key === "" ? 0 : 1
                    onClicked: root.cleared(root.editing)
                }
                Row {
                    id: actionRow
                    spacing: Theme.textField.gap
                    // Reserve caller actions even when their current state
                    // hides them, so all bind rows keep one input width.
                    width: children.reduce((sum, child) => sum + child.width, 0)
                        + Math.max(0, children.length - 1) * spacing
                }
            }
        }

        LinkText {
            role: "hint"
            width: parent.width
            wrapMode: Text.Wrap
            color: root.hintIsNotice ? Theme.color.danger : Theme.color.warning
            text: root.hint
            link: root.hintIsNotice ? "" : root.hintLink
            visible: text !== ""
            onActivated: root.hintLinkActivated()
        }

        // Always visible, since a hidden parent would hide the controls it
        // waits on; a Column lays out no item of zero height, so an empty
        // line takes no room.
        Flow {
            id: hintActionRow
            width: parent.width
            spacing: Theme.rowAction.gap
        }
    }
}
