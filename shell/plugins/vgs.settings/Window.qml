import QtQuick
import qs.Commons
import qs.Ui

// The Plugins window: every plugin the manager lists, and one page per
// plugin, drawn from its manager row alone. The window host builds it as a
// Hyprland window titled Plugins, which Hyprland floats, centres, frames
// and focuses like any other window. It asks to be `size.window.width`
// wide, or the monitor's width less `size.window.gutter` a side when that
// is less, and as tall as the page it opens on, a plugin page's taller
// tab or the list, up to `size.window.tallHeightShare` of the monitor's
// height, or its height less the gutter a side when that is less, read
// from the screen its `screens` capability gives. The size holds while
// pages change, since Hyprland would move a resized window. The pages fill
// whatever size the window has after that, and a page taller than it
// scrolls. The list page and the plugin page
// sit side by side and slide on `motion.duration.normal`, so a
// `motion.scale` of 0 makes a push or a pop instant; the page not shown is
// hidden once the slide ends, so the keyboard reaches the shown page alone.
// Escape pops a page; on the list it is left to the window host, which
// closes the window. Enabling, disabling, showing a widget in the bar, a
// setting and a key go through the manager capability; the rows come back
// from the core, so the window shows what the configuration holds. Adding,
// updating and removing a plugin open the manager's core TUIs, a floating
// terminal where each question stays a question, a plugin's setup button
// opens its own TUI, and Install shows the core's requirement notice; the
// window stays open behind them, and its rows change once the command
// there ends. Each open asks the manager for
// a scan, so a command installed or a setup run from a terminal while the
// shell ran reads as it now is: each scan raises the requirements revision
// a plugin's service re-reads its own state on.
//
// The payload is a JSON object: `{}` opens the list, `{"plugin":"<id>"}`
// that plugin's page, and an id no plugin has opens the list with a notice
// naming it. Any other key, or a payload that is no object, throws out of
// open(), which refuses the summon. A plugin that leaves the manager's rows
// while its page is shown, as a removal's rescan does, returns the window
// to the list with a notice naming it.
//
// A plugin page that holds an unsaved edit is left only after a prompt:
// the back button, Escape, the title's menu, a deep link to another page,
// the Details tab and a hide by the shell each ask once, Save, Discard or
// Cancel, over a scrim. Save writes every edit and leaves when each was
// accepted, Discard drops them and leaves, and Cancel, Escape and a press
// on the scrim stay. A request that comes while the prompt shows replaces
// the one it waits on, so no second prompt opens. The window host asks
// `holdsHide()` before it hides the window, and the window hides itself
// through its `surfaces` capability once the prompt is answered. A close
// through Hyprland asks nothing: the window is gone, and its edits with it.
//
// Remove my line on a Keys row asks first, over a scrim: the confirmation
// says which line of which file goes, that Hyprland reloads and that Undo
// puts it back. Remove line runs it; Cancel, Escape and a press on the
// scrim keep the line. Either answer returns the keyboard to the row.
FocusScope {
    id: root

    property var shell: null
    readonly property var plugins: shell === null ? [] : shell.manager.plugins
    readonly property string title: shell === null ? "" : shell.manifest.name
    readonly property var screen: shell === null ? null : shell.screens.current
    // The key capture a Keys row's field asks to press a combo.
    readonly property var capture: shell === null ? null : shell.shortcut.capture
    // The last refusal or failure the manager answered, by stepKey: a call
    // for a plugin, shown on its page, a status step (D061), shown under
    // its line, and a setup screen, shown under its buttons, each until a
    // later call there succeeds.
    property var replies: ({})
    // The stepKey of the secret write running, or "".
    property string writing: ""
    // The page shown: "" for the list, else a plugin id.
    property string page: ""
    // The plugin page drawn, kept while it slides out on a pop.
    property string drawn: ""
    // A line the list shows over the search field, such as a deep link to
    // an id no plugin has.
    property string notice: ""
    // False while a summon places the page, so the window opens on it
    // without a slide.
    property bool sliding: false

    // What leaving the page waits on while the prompt asks: a function
    // that leaves, or null while no prompt shows.
    property var pending: null
    // The item that held the keyboard when the prompt opened, and how it
    // took it, so an answer hands the keyboard back with its ring.
    property Item askedFrom: null
    property int askedReason: Qt.OtherFocusReason

    readonly property var current: rowOf(drawn)
    // The Keys row whose user line waits on the removal prompt, and that
    // line, as { field, row }, or null.
    property var removal: null
    property Item initialFocus: pending !== null || removal !== null ? prompt : page === "" ? list.initialFocus : detail.initialFocus

    implicitWidth: Math.floor(Math.min(Theme.size.window.width, OverlayState.room(screen).width))
    // The tallest the window opens.
    readonly property real maxHeight: screen === null ? Theme.size.panel.maxHeight : Math.floor(Math.min(Theme.size.window.tallHeightShare * screen.height, OverlayState.room(screen).height))
    // Only the height as the window shows counts: the window host calls open()
    // before it shows the window, Quickshell 0.3.1 polishes the item tree
    // just before it maps (proxywindow.cpp setVisibleDirect, QTBUG-126704),
    // and a FloatingWindow takes a new implicit size only while hidden
    // (floatingwindow.cpp trySetHeight), so a page reached after the window
    // shows keeps its size and scrolls.
    implicitHeight: Math.min(maxHeight, Math.ceil(page === "" ? list.fitHeight : detail.fitHeight))
    focus: true

    function rowOf(id) { return plugins.find(p => p.id === id) || null; }

    onPluginsChanged: {
        if (page === "" || rowOf(page) !== null) return;
        const gone = page;
        // Its fields went with its row, so nothing is left to ask about.
        pending = null;
        askedFrom = null;
        showList();
        notice = gone + " is no longer listed.";
    }

    // Run `then`, which leaves the shown plugin page: now when the page
    // holds no unsaved edit, else once the prompt is answered Save or
    // Discard. Answers whether it ran now.
    function leave(then) {
        if (!detail.dirty) {
            then();
            return true;
        }
        if (pending === null) {
            askedFrom = root.Window.activeFocusItem;
            askedReason = askedFrom !== null && askedFrom.focusReason !== undefined ? askedFrom.focusReason : Qt.OtherFocusReason;
        }
        pending = then;
        return false;
    }

    // The prompt's answer: `save`, `discard` or `cancel`.
    function answer(choice) {
        const then = pending;
        const left = choice === "save" ? detail.save() : choice === "discard";
        if (choice === "discard") detail.discard();
        // A refused key takes the keyboard to its field; else it returns
        // to the item the prompt took it from.
        const held = prompt.activeFocus;
        pending = null;
        if (held && askedFrom !== null) askedFrom.forceActiveFocus(askedReason);
        askedFrom = null;
        if (left) then();
    }

    // Open ROW, a user line a Keys row cites, at its line in the user's
    // editor.
    function openUserLine(row) {
        const answer = shell.tui.edit(row.config, row.line);
        if (answer !== "ok") console.warn("settings: edit " + answer);
    }

    // FIELD, a Keys row, asks to take ROW, a user line holding its key, out
    // of the user's file.
    function confirmRemoval(field, row) {
        removal = { field: field, row: row };
    }

    function answerRemoval(accepted) {
        const asked = removal;
        removal = null;
        if (asked === null) return;
        asked.field.forceActiveFocus(Qt.OtherFocusReason);
        if (accepted) asked.field.removeLine(asked.row);
    }

    // The window host asks before it hides the window: true keeps it open
    // while the prompt asks about the page's unsaved edit.
    function holdsHide() {
        if (!detail.dirty) return false;
        leave(() => Qt.callLater(() => root.shell.surfaces.hide("window")));
        return true;
    }

    // Where a reply is kept: plugin `id`, then, for a status step, its
    // entry `key` and, for a secret, its `account`, joined by "/".
    function stepKey(id, key, account) {
        return [id].concat(key === undefined ? [] : [key], account === undefined ? [] : [account]).join("/");
    }
    // The reply kept under stepKey(id, key, account), or "".
    function replyOf(id, key, account) {
        return replies[stepKey(id, key, account)] || "";
    }

    // Keep one manager reply under STEP, a stepKey, and answer it.
    function keep(step, reply) {
        const next = Object.assign({}, replies);
        if (Reply.isOk(reply)) delete next[step];
        else {
            next[step] = Reply.line(reply);
            console.warn("settings: " + step + " " + reply);
        }
        replies = next;
        return reply;
    }

    function open(payloadJson) {
        const payload = JSON.parse(payloadJson === "" ? "{}" : payloadJson);
        if (payload === null || typeof payload !== "object" || Array.isArray(payload))
            throw new Error("payload must be a JSON object, got " + payloadJson);
        for (const key of Object.keys(payload))
            if (key !== "plugin") throw new Error("payload key " + JSON.stringify(key) + " unknown, want plugin");
        if (payload.plugin !== undefined && typeof payload.plugin !== "string")
            throw new Error("payload plugin must be a plugin id, got " + JSON.stringify(payload.plugin));
        // Each open reads the system again: a scan asked for while one runs
        // starts when it ends, so `ok` and `busy` both mean a fresh one.
        shell.manager.rescan();
        // A summon of the page already shown leaves nothing.
        if (page !== "" && payload.plugin === page) {
            show(page, Qt.ShortcutFocusReason);
            return;
        }
        leave(() => {
            sliding = false;
            notice = "";
            if (payload.plugin === undefined) showList(Qt.ShortcutFocusReason);
            else if (rowOf(payload.plugin) === null) {
                showList(Qt.ShortcutFocusReason);
                notice = "No plugin named " + payload.plugin + " is available.";
            } else show(payload.plugin, Qt.ShortcutFocusReason);
            Qt.callLater(() => { root.sliding = true; });
        });
    }

    function close() {}

    function showList(reason) {
        page = "";
        list.focusSearch(reason);
    }

    function show(id, reason) {
        notice = "";
        drawn = id;
        page = id;
        detail.open(reason === undefined ? Qt.TabFocusReason : reason);
    }

    // Open the page of plugin `id`, on its Settings page; answers `ok`,
    // `unknown: <id>`, or `refused: unsaved=<page>` while the prompt asks
    // about the shown page's unsaved edit first.
    function openPlugin(id, reason) {
        if (rowOf(id) === null) return "unknown: " + id;
        if (id === page) {
            show(id, reason);
            return "ok";
        }
        const from = page;
        return leave(() => show(id, reason)) ? "ok" : "refused: unsaved=" + from;
    }

    // Pop the plugin page to the list; answers `ok`, or `refused:
    // unsaved=<page>` while the prompt asks first.
    function back() {
        const from = page;
        return leave(() => showList(Qt.TabFocusReason)) ? "ok" : "refused: unsaved=" + from;
    }

    // Enable or disable plugin `id`, the opposite of its state now; answers
    // the manager's reply.
    function toggle(id) {
        const row = rowOf(id);
        if (row === null) return "unknown: " + id;
        return keep(id, shell.manager.setEnabled(id, !row.enabled));
    }

    // Show plugin `id`'s widget in the bar, or hide it, the opposite of its
    // placement now; answers the manager's reply. The page offers it only
    // for a plugin with a kind besides its widget, which stays enabled.
    function togglePlaced(id) {
        const row = rowOf(id);
        if (row === null) return "unknown: " + id;
        return writePlacement(id, !row.placed, id);
    }

    function writePlacement(id, placed, pageId) {
        return keep(pageId, shell.manager.setPlaced(id, placed));
    }

    // Write one setting of plugin `id` through the manager; answers its
    // reply.
    function writeSetting(id, key, value) {
        return keep(id, shell.manager.setSetting(id, key, value));
    }

    // Open the update of installed plugin `id` or its removal in a floating
    // terminal, or the requirement notice for its missing commands, through
    // the manager; each answers the manager's reply. The terminal is a newer
    // window, which Hyprland focuses and stacks over this one, and the
    // notice sits on a layer over every window, so this window stays open
    // behind them and its rows show the command's result once it ends.
    function updatePlugin(id) { return keep(id, shell.manager.update(id)); }
    function removePlugin(id) { return keep(id, shell.manager.remove(id)); }
    function installRequirements(id) { return keep(id, shell.manager.installRequirements(id)); }

    // Run the action of plugin `id`'s status entry `key` through the
    // manager: its floating TUI, which Hyprland focuses over this window,
    // or the requirement notice; answers the manager's reply (D061).
    function act(id, key) {
        return keep(stepKey(id, key), shell.manager.act(id, key));
    }

    // The step key of setup screen `name`, which `replyOf` reads its reply
    // under: a status key holds no colon, so a screen and a status entry of
    // one name keep their replies apart.
    function tuiKey(name) {
        return "tui:" + name;
    }

    // Open plugin `id`'s setup screen `name`, a TUI its manifest lists,
    // through the manager, which opens it as it opens a status step's;
    // answers the manager's reply.
    function openTui(id, name) {
        return keep(stepKey(id, tuiKey(name)), shell.manager.openTui(id, name));
    }

    // Open the plugin's window or panel over this window. This page stays
    // open and shows the reply.
    function openSurface(id) {
        return keep(id, shell.manager.open(id));
    }

    // Open `url`, the address of a setting description's link, which the
    // manager judged https (PluginLogic.linkError), in the default browser
    // through the desktop open route. Plugin `id`'s page shows the reply.
    function openLink(id, url) {
        return keep(id, shell.run.detached(DesktopLaunch.open(url)));
    }

    // Open the plugin's page in the panes holder over this window, as
    // Open does its surface.
    function openPane(id) {
        return keep(id, shell.manager.openPane(id));
    }

    // Store what the user typed as plugin `id`'s secret `account`, listed
    // in its status entry `key`, or clear it, through the manager, which
    // writes libsecret; each answers the manager's reply, and the write's
    // end, a failure included, reads under the line. The secret goes to the
    // manager alone: no reply, log line or property here holds it.
    function storeSecret(id, key, account, secret) {
        return secretStep(stepKey(id, key, account), done => shell.manager.storeSecret(id, key, account, secret, done));
    }
    function clearSecret(id, key, account) {
        return secretStep(stepKey(id, key, account), done => shell.manager.clearSecret(id, key, account, done));
    }

    function secretStep(step, call) {
        const reply = keep(step, call(result => {
            if (root.writing === step) root.writing = "";
            root.keep(step, result.ok ? "ok" : "refused: secret write failed " + result.reason);
        }));
        if (Reply.isOk(reply)) writing = step;
        return reply;
    }

    // One of the list heading's manager steps, VERB, run by CALL: its
    // refusal stays over the list until a later step answers, and the log
    // keeps the machine reply; answers that reply.
    function listStep(verb, call) {
        const reply = call();
        notice = Reply.line(reply);
        if (notice !== "") console.warn("settings: " + verb + " " + reply);
        return reply;
    }

    // Open the add of a plugin from a git URL in a floating terminal through
    // the manager.
    function addPlugin() {
        return listStep("add", () => shell.manager.add());
    }

    // Ask the core's reset question through the manager; the notice sits on
    // a layer over every window, so this window stays open behind it.
    function resetVgs() {
        return listStep("reset", () => shell.manager.reset());
    }

    // Set the key of shortcut `shortcut` of plugin `id`: a key string
    // rebinds, null unbinds, undefined resets to the manifest's key;
    // answers the manager's reply.
    function writeKey(id, shortcut, key) {
        return keep(id, shell.manager.setKey(id, shortcut, key));
    }

    // Escape on a plugin page pops it; on the list it goes on to the window
    // host, which closes the window.
    Keys.onEscapePressed: event => {
        if (page === "") event.accepted = false;
        else back();
    }

    Item {
        anchors.fill: parent
        clip: true

        Item {
            id: pages
            width: 2 * root.width
            height: root.height
            x: root.page === "" ? 0 : -root.width
            Behavior on x {
                enabled: root.sliding
                NumberAnimation { id: slide; duration: Theme.motion.duration.normal; easing.type: Theme.motion.easing.standard }
            }

            // The page not shown is hidden once the slide ends, so Tab,
            // Shift+Tab and the pointer reach the shown page alone; both
            // draw while they slide.
            ListPage {
                id: list
                panel: root
                width: root.width
                height: root.height
                visible: root.page === "" || slide.running
                focus: root.page === ""
            }

            PluginPage {
                id: detail
                panel: root
                row: root.current
                x: root.width
                width: root.width
                height: root.height
                visible: root.page !== "" || slide.running
                focus: root.page !== ""
            }
        }
    }

    Scrim {
        visible: prompt.visible
        onClicked: prompt.removing ? root.answerRemoval(false) : root.answer("cancel")
    }

    // The window's one prompt: the unsaved edit's, or a Keys row's removal
    // while no edit waits.
    Dialog {
        id: prompt
        readonly property var asked: root.removal
        readonly property bool removing: root.pending === null && asked !== null
        anchors.centerIn: parent
        visible: root.pending !== null || root.removal !== null
        availableHeight: root.height
        title: removing ? "Remove your Hyprland shortcut?" : "Save your changes?"
        message: removing && asked !== null ? "VGS deletes line " + asked.row.line + " of " + asked.row.place + " and reloads Hyprland, so " + asked.field.bind.key + " runs only " + asked.field.label + ". Undo puts the line back."
            : root.current === null ? "" : root.current.name + " has unsaved changes."
        actions: removing ? [
            { label: "Remove line", role: "accept" },
            { label: "Cancel", role: "cancel", focused: true }
        ] : [
            { label: "Save", role: "accept" },
            { label: "Cancel", role: "cancel" }
        ]
        tabItems: removing ? [] : [discardChanges]
        onVisibleChanged: if (visible) forceActiveFocus()
        onAccepted: removing ? root.answerRemoval(true) : root.answer("save")
        onRejected: removing ? root.answerRemoval(false) : root.answer("cancel")

        Button {
            id: discardChanges
            visible: !prompt.removing
            text: "Discard"
            variant: "tertiary"
            onClicked: root.answer("discard")
        }
    }
}
