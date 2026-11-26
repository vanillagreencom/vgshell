import QtQuick
import QtTest
import qs.Commons
import qs.Core
import qs.Ui
import qs.Unit
import "../../shell/plugins/vgs.settings"

// A `rows` list on Setup that the plugin edits in place, on the actual
// Settings window over a stand-in manager: the list draws on the Setup tab;
// an editor the plugin asked for opens there once per serial, with its
// choice fixed, a name and an empty masked field, and the choice's link;
// Save hands the manager the form and the typed secret, clears the field
// and closes the form once the save ends, a failed save keeps the form
// with the plugin's words, and Cancel tells the manager; a row action that
// declares `confirm` asks in the window's prompt before it acts. Every key
// here is a stand-in.
Item {
    id: root
    width: 1200
    height: 1200
    readonly property var screen: ({ name: "DP-1", x: 0, y: 0, width: 1920, height: 1080 })
    readonly property var keysEntry: ({ type: "rows", label: "Providers and keys", tab: "setup", icon: "key-round",
        action: { label: "Add API key", handler: true },
        rowActions: { edit: { label: "Edit", handler: true }, remove: { label: "Remove", handler: true, tone: "danger", confirm: true } },
        editor: { choices: "kinds", choice: "Provider", name: "Key name", secret: "API key" } })
    readonly property var kinds: [{ value: "alpha", label: "Alpha", link: { text: "Alpha key page", url: "https://alpha.invalid/keys" } }, { value: "beta", label: "Beta" }]
    readonly property var keys: [{ id: "key-a", label: "Alpha", secondary: "Used by Target", state: { tone: "info", text: "Not checked yet" },
        actions: ["edit", "remove"], choice: "alpha", confirm: { remove: "The key is deleted from your keyring." } }]
    readonly property string standIn: "stand-in-key-not-a-secret"
    function pluginRow() {
        const manifest = { requirements: [], tui: {}, schema: { target: { type: "string", label: "Target" } },
            status: { keys: keysEntry, kinds: { type: "choices", label: "Kinds", hidden: true } } };
        const row = { id: "acme.keys", name: "Keys", version: "1", description: "", author: "VGS", license: "", icon: "package", source: "bundled",
            enabled: true, alwaysOn: false, placed: false, kinds: ["service"], capabilities: [], schema: manifest.schema, settings: { target: "" }, settingChoices: {},
            status: PluginLogic.statusRows(manifest, { keys: keys, kinds: kinds }), secretLabel: "", readme: "", guide: null, tuis: [], builtins: [], opens: "",
            paneHolder: "", binds: [], requirements: [], errors: [], withheldFields: [], fieldProblems: {} };
        row.fieldRows = PluginLogic.fieldRows(row.schema, manifest.status);
        return row;
    }
    QtObject {
        id: fakeManager
        property var plugins: [root.pluginRow()]
        property var installFailures: ({})
        property var acts: []
        property var saves: []
        property var cancels: []
        // The last editor open the plugin asked for, or null.
        property var editor: null
        // The save that waits for its end, { done }, or null.
        property var pending: null
        function rescan() { return "ok"; }
        function viewPage(id) {}
        function setEnabled(id, enabled) { return "ok"; }
        function act(id, key, row, rowAction) { acts = acts.concat([[id, key, row, rowAction]]); return "ok"; }
        function editorOf(id) { return id === "acme.keys" ? editor : null; }
        function saveEditor(id, key, form, secret, done) {
            saves = saves.concat([[id, key, form.row, form.choice, form.name, form.target, secret]]);
            pending = { done: done };
            return "ok";
        }
        function cancelEditor(id, key, form) { cancels = cancels.concat([[id, key, form.row, form.target]]); return "ok"; }
    }
    QtObject { id: fakeCompositor; function readWindows(done) {} }
    QtObject { id: fakeTui; function edit(path) { return "ok"; } }
    QtObject {
        id: fakeShell
        readonly property var manager: fakeManager
        readonly property var compositor: fakeCompositor
        readonly property var manifest: ({ id: "vgs.settings", name: "Plugins" })
        readonly property var screens: ({ current: root.screen, all: [root.screen] })
        readonly property var shortcut: ({ capture: null })
        readonly property var tui: fakeTui
    }
    Component { id: windowComponent; Window { shell: fakeShell } }
    UnitCase {
        name: "settingsRowsEditor"
        when: windowShown
        function descendants(item) {
            const found = [item];
            for (let i = 0; i < found.length; i++) for (const child of found[i].children || []) found.push(child);
            return found;
        }
        function init() {
            fakeManager.plugins = [root.pluginRow()];
            fakeManager.acts = []; fakeManager.saves = []; fakeManager.cancels = [];
            fakeManager.editor = null; fakeManager.pending = null;
        }
        function opened(tab) {
            const window = createTemporaryObject(windowComponent, root);
            verify(window !== null, "the window builds");
            window.width = window.implicitWidth; window.height = 900; window.open("{}"); renderedFrame(window);
            window.openPlugin("acme.keys", Qt.OtherFocusReason, tab);
            tryVerify(() => pageOf(window).parent.x === -window.width, 2000, "the page has slid in");
            renderedFrame(window);
            return window;
        }
        function pageOf(window) { return descendants(window).find(item => item.fitHeight !== undefined && item.row !== undefined); }
        function tabsOf(window) { return descendants(pageOf(window)).find(item => item instanceof TabPages); }
        function onTab(window, type) { return descendants(tabsOf(window).currentPage).filter(item => item instanceof type && item.visible); }
        function editorOf(window) { return onTab(window, RowsEditor)[0]; }
        function secretOf(editor) { return descendants(editor).find(item => item instanceof TextField && item.password && item.visible); }
        function buttonOf(editor, text) { return descendants(editor).find(item => item instanceof Button && item.visible && item.text === text); }
        // Press an editor button through its own click route once it holds
        // no disabled reason: a pointer press on the newly opened form did
        // not reach its buttons under qmltestrunner.
        function press(button) {
            verify(button !== undefined, "the button stands in the form");
            compare(button.disabledReason, "", button.text + " takes a press");
            button.clicked();
        }
        function ask(form) { fakeManager.editor = { serial: (fakeManager.editor === null ? 0 : fakeManager.editor.serial) + 1, form: form }; }
        readonly property var voiceForm: ({ key: "keys", row: "", choice: "alpha", fixed: true, name: "Alpha", target: "target", title: "Add API key for Alpha" })

        function test_a_setup_list_draws_on_setup() {
            const window = opened("Setup");
            compare(tabsOf(window).model[tabsOf(window).currentIndex], "Setup");
            const lists = onTab(window, RowsList);
            compare(lists.map(list => list.title), ["Providers and keys"], "the list is a Setup section");
            compare(onTab(window, RowsEditor).length, 0, "no form stands open unasked");
        }

        // A request opens once: a save's end, which leaves the request as
        // it was, opens no second form.
        function test_an_answered_request_opens_once() {
            const window = opened("Settings");
            ask(voiceForm);
            tryVerify(() => editorOf(window) !== undefined, 2000);
            press(buttonOf(editorOf(window), "Cancel"));
            tryCompare(onTab(window, RowsEditor), "length", 0);
            fakeManager.editor = Object.assign({}, fakeManager.editor);
            wait(0);
            compare(onTab(window, RowsEditor).length, 0, "the same serial opens nothing");
        }

        function test_an_asked_editor_opens_on_setup_with_its_choice_fixed() {
            const window = opened("Settings");
            ask(voiceForm);
            tryVerify(() => editorOf(window) !== undefined, 2000, "the form opens");
            compare(tabsOf(window).model[tabsOf(window).currentIndex], "Setup", "the form shows on Setup");
            const editor = editorOf(window);
            const texts = displayedTextItems(editor).map(item => displayedText(item));
            verify(texts.indexOf("Add API key for Alpha") !== -1, "the form's heading");
            verify(texts.indexOf("Open Alpha key page") !== -1, "the choice's key page link");
            compare(descendants(editor).filter(item => item instanceof Select && item.visible).length, 0, "a fixed choice draws no Select");
            const secret = secretOf(editor);
            compare([secret.text, secret.echoMode], ["", TextInput.Password], "the masked field opens empty");
            verify(buttonOf(editor, "Save and use") !== undefined, "a save for a field says it uses the key");
        }

        function test_save_hands_the_secret_once_and_closes_on_its_end() {
            const window = opened("Settings");
            ask(voiceForm);
            tryVerify(() => editorOf(window) !== undefined, 2000);
            const editor = editorOf(window);
            secretOf(editor).text = root.standIn;
            press(buttonOf(editor, "Save and use"));
            compare(fakeManager.saves, [["acme.keys", "keys", "", "alpha", "Alpha", "target", root.standIn]]);
            compare(secretOf(editor).text, "", "the typed key leaves the field as the save starts");
            fakeManager.pending.done({ ok: true, text: "" });
            tryVerify(() => onTab(window, RowsEditor).length === 0 || tabsOf(window).model[tabsOf(window).currentIndex] === "Settings", 2000,
                "the form closes and the page returns to its field");
            compare(onTab(window, RowsEditor).length, 0);
        }

        function test_a_failed_save_keeps_the_form_with_its_words() {
            const window = opened("Setup");
            ask({ key: "keys", row: "", choice: "", fixed: false, name: "", target: "", title: "" });
            tryVerify(() => editorOf(window) !== undefined, 2000);
            const editor = editorOf(window);
            const picker = descendants(editor).find(item => item instanceof Select && item.visible);
            picker.activated(1);
            secretOf(editor).text = root.standIn;
            press(buttonOf(editor, "Save"));
            compare(fakeManager.saves, [["acme.keys", "keys", "", "beta", "Beta", "", root.standIn]], "the name follows the choice");
            fakeManager.pending.done({ ok: false, text: "The key list is full." });
            tryVerify(() => displayedTextItems(editorOf(window)).some(item => displayedText(item) === "The key list is full."), 2000);
            compare(secretOf(editorOf(window)).text, "", "a failed save leaves no key in the field");
        }

        function test_cancel_tells_the_plugin() {
            const window = opened("Settings");
            ask(voiceForm);
            tryVerify(() => editorOf(window) !== undefined, 2000);
            press(buttonOf(editorOf(window), "Cancel"));
            compare(fakeManager.cancels, [["acme.keys", "keys", "", "target"]]);
            compare(fakeManager.saves, []);
            tryCompare(onTab(window, RowsEditor), "length", 0);
        }

        // Remove asks in the window's prompt first; only its yes acts.
        function test_a_confirm_action_asks_first() {
            const window = opened("Setup");
            const list = onTab(window, RowsList)[0];
            const line = descendants(list).find(item => item instanceof ContentRow && item.visible);
            const menu = descendants(line).find(item => item instanceof Menu);
            mouseClick(descendants(line).find(item => item instanceof IconButton && item.visible));
            tryCompare(menu, "opened", true);
            menu.items()[0].triggered();
            menu.close();
            compare(fakeManager.acts, [], "nothing acts before the answer");
            const prompt = descendants(window).find(item => item instanceof Dialog && item.visible);
            verify(prompt !== undefined, "the prompt asks");
            compare([prompt.title, prompt.message], ["Remove Alpha?", "The key is deleted from your keyring."]);
            prompt.rejected();
            compare(fakeManager.acts, [], "Cancel acts on nothing");
            mouseClick(descendants(line).find(item => item instanceof IconButton && item.visible));
            tryCompare(menu, "opened", true);
            menu.items()[0].triggered();
            menu.close();
            descendants(window).find(item => item instanceof Dialog && item.visible).accepted();
            compare(fakeManager.acts, [["acme.keys", "keys", "key-a", "remove"]], "yes acts on its row");
        }
    }
}
