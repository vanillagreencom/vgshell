import QtQuick
import QtTest
import Quickshell.Hyprland
import qs.Core
import "../../shell/plugins/vgs.settings"

// The key capture owner, KeyCapture.qml, through the `capture` member the
// shortcut capability hands a plugin: which control holds the keyboard,
// the pass-through requests it sends Compositor (a stand-in that records
// them and takes their answers by hand), every end that leaves the submap,
// the submap Hyprland reports, a failed enter, a timeout, the user's
// binds it reads from HyprlandState (a stand-in source here) for the
// conflict hint, and the removal and undo of a user's bind line, whose
// edits the stand-in records and answers by hand. A removal's undo record
// is released by its Settings key field's destruction, by a removal that
// answers after that field or its instance is gone, and by
// releaseUserBind.
Item {
    id: root
    // HyprlandState's binds members, set by hand.
    QtObject {
        id: source
        property var foreignKeys: null
        property string bindsFailure: ""
        property int reads: 0
        // userBindsFor's rows by key, and each edit asked: { args, done }.
        property var userRows: ({})
        property var edits: []
        function readBinds() { reads += 1; }
        function userBindsFor(key) { return userRows[key] || []; }
        function editBinds(args, done) { edits = edits.concat([{ args: args, done: done }]); }
    }
    ShortcutRegistry { id: registry; bindsSource: source }
    property var disposers: []
    // An answer per removal or undo, in the order they came.
    property var answers: []
    function answered(value) { answers = answers.concat([value]); }
    property var capture: registry.provider(context("acme.keys")).capture
    property var other: registry.provider(context("acme.other")).capture

    function context(id) {
        return { id: id, active: true, onDispose: fn => {
            let pending = true;
            const dispose = () => { if (pending) { pending = false; fn(); } };
            root.disposers = root.disposers.concat([dispose]);
            return dispose;
        } };
    }

    Item { id: first }
    Item { id: second }
    Component { id: transient; Item {} }
    Component { id: fresh; ShortcutRegistry {} }
    Component {
        id: keyField
        KeyField {
            pluginId: "acme.keys"
            bind: ({ shortcut: "open", key: "SUPER+SPACE", default: "SUPER+SPACE", description: "Open" })
        }
    }

    TestCase {
        name: "key-capture"

        function init() {
            Registry.hyprlandSections = [{ id: "acme.keys", binds: [{ shortcut: "open", key: "SUPER+SPACE" }] }];
            Compositor.reset();
        }

        function cleanup() {
            root.capture.end(first, "cancel");
            root.capture.end(second, "cancel");
            Compositor.answerAll();
            Compositor.reset();
            source.foreignKeys = null;
            source.bindsFailure = "";
            source.reads = 0;
            source.userRows = {};
            source.edits = [];
            owner().removedBinds.rows = {};
        }

        function sentEdits() { return JSON.stringify(source.edits.map(edit => edit.args)); }
        function userLine(removable) {
            return { file: "/h/.config/hypr/binds.lua", line: 12, text: 'hl.bind("SUPER + SPACE", f)', removable: removable, place: "~/.config/hypr/binds.lua" };
        }

        // Answer edit INDEX as a removal of line 12 that printed its undo.
        function removedOk(index) {
            source.edits[index].done({ ok: true, said: 'ok hypr=bind-removed path=/h/.config/hypr/binds.lua line=12 undo={"text":"x","before":null,"after":null}' });
        }
        // The tokens whose undo records the capture holds.
        function heldTokens() { return JSON.stringify(Object.keys(owner().removedBinds.rows)); }

        function submap(name) { Hyprland.rawEvent({ name: "submap", data: name }); }
        function sent() { return JSON.stringify(Compositor.requests); }
        // The registry's KeyCapture, whose start time the timeout case moves back.
        function owner() { return registry.data.find(child => child.began !== undefined); }

        function test_begin_enters_and_commit_leaves() {
            compare(root.capture.begin(first), "ok");
            compare(root.capture.holder, first);
            compare(root.capture.passthrough, false);
            compare(sent(), '["enter"]');
            Compositor.answer(0, "ok");
            submap("vgs:passthrough");
            compare(root.capture.passthrough, true);
            compare(root.capture.failed, false);
            root.capture.end(first, "commit");
            compare(root.capture.holder, null);
            compare(root.capture.passthrough, false);
            compare(sent(), '["enter","leave"]');
            compare(JSON.stringify([root.capture.ended.item === first, root.capture.ended.reason]), '[true,"commit"]');
        }

        function test_window_free_begin_uses_the_window_free_verb() {
            const ctx = root.context("acme.core");
            compare(owner().begin(ctx, first, { anyWindow: true }), "ok");
            compare(root.capture.holder, first);
            compare(sent(), '["enterAnyWindow"]');
            root.capture.end(first, "commit");
            compare(sent(), '["enterAnyWindow","leave"]');
        }

        function test_a_waiting_begin_uses_its_own_window_option() {
            const ctx = root.context("acme.core");
            root.capture.begin(first);
            root.capture.end(first, "cancel");
            compare(owner().begin(ctx, second, { anyWindow: true }), "ok");
            compare(sent(), '["enter","leave"]');
            Compositor.answer(1, "ok");
            compare(sent(), '["enter","leave","enterAnyWindow"]');
        }

        function test_cancel_leaves_before_hyprland_answers() {
            root.capture.begin(first);
            root.capture.end(first, "cancel");
            compare(root.capture.holder, null);
            compare(sent(), '["enter","leave"]');
            submap("vgs:passthrough");
            compare(root.capture.passthrough, false);
        }

        function test_only_the_holder_ends_it() {
            root.capture.begin(first);
            root.capture.end(second, "commit");
            compare(root.capture.holder, first);
            compare(sent(), '["enter"]');
        }

        function test_a_second_begin_by_the_holder_sends_nothing() {
            root.capture.begin(first);
            root.capture.begin(first);
            compare(sent(), '["enter"]');
        }

        function test_a_newer_holder_ends_the_first() {
            root.capture.begin(first);
            root.other.begin(second);
            compare(root.capture.holder, second);
            compare(sent(), '["enter","leave"]');
            Compositor.answer(0, "ok");
            Compositor.answer(1, "ok");
            compare(sent(), '["enter","leave","enter"]');
        }

        // The quick re-arm: the first capture's enter and leave are still
        // queued when the second begins, so their submap events come after
        // its begin and belong to the first.
        function test_an_earlier_captures_events_leave_a_newer_one() {
            root.capture.begin(first);
            root.capture.end(first, "cancel");
            root.capture.begin(second);
            compare(sent(), '["enter","leave"]');
            Compositor.answer(0, "ok");
            submap("vgs:passthrough");
            submap("");
            compare(root.capture.holder, second);
            Compositor.answer(1, "ok");
            compare(sent(), '["enter","leave","enter"]');
            submap("vgs:passthrough");
            compare(root.capture.holder, second);
            compare(root.capture.passthrough, true);
        }

        function test_a_destroyed_holder_leaves() {
            const item = transient.createObject(root);
            root.capture.begin(item);
            submap("vgs:passthrough");
            item.destroy();
            wait(0); // QObject.destroy() completes after the current event turn.
            compare(root.capture.holder, null);
            compare(sent(), '["enter","leave"]');
        }

        function test_instance_teardown_leaves() {
            const ctx = root.context("acme.gone");
            const capture = registry.provider(ctx).capture;
            capture.begin(first);
            const pending = root.disposers;
            root.disposers = [];
            for (const dispose of pending) dispose();
            compare(capture.holder, null);
            compare(sent(), '["enter","leave"]');
        }

        function test_hyprland_leaving_ends_the_capture() {
            root.capture.begin(first);
            submap("vgs:passthrough");
            submap("");
            compare(root.capture.holder, null);
            compare(sent(), '["enter"]');
            compare(root.capture.ended.reason, "compositor");
        }

        function test_another_submap_ends_the_capture() {
            root.capture.begin(first);
            submap("vgs:passthrough");
            submap("vgs:capture");
            compare(root.capture.holder, null);
            compare(sent(), '["enter"]');
        }

        function test_a_submap_change_before_the_enter_keeps_it() {
            root.capture.begin(first);
            submap("");
            compare(root.capture.holder, first);
            compare(root.capture.passthrough, false);
        }

        function test_a_failed_enter_is_reported_and_keeps_capturing() {
            root.capture.begin(first);
            Compositor.answer(0, "hl.dispatch: vgs:passthrough: the focused window is not a vgs window");
            compare(root.capture.failed, true);
            compare(root.capture.holder, first);
            root.capture.end(first, "cancel");
            compare(root.capture.failed, false);
            Compositor.answerAll();
            Compositor.refuse = "refused: passthrough=enter session=classic";
            root.capture.begin(second);
            compare(root.capture.failed, true);
        }

        function test_an_enter_answer_for_an_earlier_capture_is_dropped() {
            root.capture.begin(first);
            root.capture.end(first, "cancel");
            Compositor.answer(1, "ok");
            root.capture.begin(second);
            Compositor.answer(0, "exit=1");
            compare(root.capture.failed, false);
        }

        function test_an_end_after_the_timeout_is_a_timeout() {
            root.capture.begin(first);
            submap("vgs:passthrough");
            owner().began = Date.now() - root.capture.timeoutMs;
            submap("");
            compare(JSON.stringify([root.capture.ended.item === first, root.capture.ended.reason]), '[true,"timeout"]');
            compare(sent(), '["enter"]');
        }

        function test_keys_are_named_by_the_judge() {
            compare(JSON.stringify(root.capture.keyFor(Qt.Key_Space, Qt.MetaModifier)), '{"kind":"key","key":"SUPER+SPACE"}');
        }

        function test_configured_conflicts_share_one_answer_until_the_snapshot_changes() {
            const first = root.capture.conflicts("SUPER+SPACE", "acme.keys", "open");
            compare(root.capture.conflicts("super+space", "acme.keys", "open"), first);
            verify(root.capture.conflicts("SUPER+SPACE", "acme.keys", "open") === first);
            source.foreignKeys = ["SUPER+SPACE"];
            const changed = root.capture.conflicts("SUPER+SPACE", "acme.keys", "open");
            verify(changed !== first);
            compare(changed.user, true);
            source.userRows = { "SUPER+SPACE": [userLine(true)] };
            compare(root.capture.conflicts("SUPER+SPACE", "acme.keys", "open").userBinds.length, 1);
            Registry.hyprlandSections = [];
            compare(Object.keys(owner().conflictAnswers).length, 0);
        }

        function test_a_deferred_question_registers_no_disposed_instance() {
            const ctx = root.context("acme.gone");
            const cap = registry.provider(ctx).capture;
            const count = owner().askers;
            cap.conflicts("SUPER+SPACE", "acme.keys", "open");
            ctx.active = false;
            wait(0);
            compare(owner().askers, count);
        }

        function test_conflicts_read_the_user_binds() {
            source.foreignKeys = ["SUPER+SPACE"];
            compare(JSON.stringify(root.capture.conflicts("super+space", "acme.other", "x")), '{"plugins":[{"id":"acme.keys","shortcut":"open"}],"user":true,"binds":"read","userBinds":[],"hint":"Also used by acme.keys (open), your other shortcuts."}');
            source.userRows = { "SUPER+SPACE": [userLine(true)] };
            compare(JSON.stringify(root.capture.conflicts("super+space", "acme.other", "x").userBinds), JSON.stringify([userLine(true)]));
            source.foreignKeys = [];
            compare(JSON.stringify(root.capture.conflicts("SUPER+SPACE", "acme.other", "x")), '{"plugins":[{"id":"acme.keys","shortcut":"open"}],"user":false,"binds":"read","userBinds":[],"hint":"Also used by acme.keys (open)."}');
            const before = Registry.manifests;
            Registry.manifests = { "acme.keys": { name: "Keys" } };
            try {
                compare(JSON.stringify(root.capture.conflicts("SUPER+SPACE", "acme.other", "x")), '{"plugins":[{"id":"acme.keys","shortcut":"open"}],"user":false,"binds":"read","userBinds":[],"hint":"Also used by Keys (open)."}');
            } finally {
                Registry.manifests = before;
            }
        }

        function test_a_removal_takes_the_one_whole_user_line_of_a_plugin_key() {
            root.answers = [];
            source.userRows = { "SUPER+SPACE": [userLine(true)], "SUPER+N": [userLine(true)] };
            root.capture.removeUserBind("SUPER+N", root.answered);
            compare(root.answers[0].error.split(" ")[1], "user-bind=no-plugin-key");
            source.userRows = { "SUPER+SPACE": [userLine(false)] };
            root.capture.removeUserBind("SUPER+SPACE", root.answered);
            compare(root.answers[1].error.split(" ")[1], "user-bind=lines");
            source.userRows = { "SUPER+SPACE": [userLine(true), userLine(true)] };
            root.capture.removeUserBind("SUPER+SPACE", root.answered);
            compare(root.answers[2].error.split(" ")[1], "user-bind=lines");
            compare(sentEdits(), "[]");
            source.userRows = { "SUPER+SPACE": [userLine(true)] };
            root.capture.removeUserBind("super+space", root.answered);
            compare(sentEdits(), '[["remove-bind","/h/.config/hypr/binds.lua","12","SUPER+SPACE"]]');
            const undo = '{"text":"hl.bind(\\"SUPER + SPACE\\", f)\\n","before":"a = 1\\n","after":null}';
            source.edits[0].done({ ok: true, said: "ok hypr=bind-removed path=/h/.config/hypr/binds.lua line=12 undo=" + undo });
            const removed = root.answers[3];
            compare(JSON.stringify([removed.ok, removed.file, removed.line]), '[true,"/h/.config/hypr/binds.lua",12]');
            root.capture.restoreUserBind(removed.token, root.answered);
            compare(JSON.stringify(source.edits[1].args), JSON.stringify(["restore-bind", "/h/.config/hypr/binds.lua", "12", undo]));
            source.edits[1].done({ ok: true, said: "ok hypr=bind-restored path=/h/.config/hypr/binds.lua line=12" });
            compare(root.answers[4].ok, true);
            root.capture.restoreUserBind(removed.token, root.answered);
            compare(root.answers[5].error.split(" ")[1], "user-bind=no-undo");
            root.capture.restoreUserBind("1' or '1", root.answered);
            compare(root.answers[6].error.split(" ")[1], "user-bind=no-undo");
            compare(source.edits.length, 2);
        }

        // Two removals in one file: the later lines move up a line, and each
        // undo moves the lines after it down again, so every token names
        // the line its neighbours expect.
        function test_removals_move_the_lines_after_them() {
            root.answers = [];
            const at = (line, key) => ({ file: "/h/.config/hypr/binds.lua", line: line, text: "", removable: true, place: "" });
            const removed = line => "ok hypr=bind-removed path=/h/.config/hypr/binds.lua line=" + line + ' undo={"text":"x","before":null,"after":null}';
            Registry.hyprlandSections = [{ id: "acme.keys", binds: [{ shortcut: "q", key: "SUPER+Q" }, { shortcut: "w", key: "SUPER+W" }] }];
            source.userRows = { "SUPER+Q": [at(2)], "SUPER+W": [at(9)] };
            root.capture.removeUserBind("SUPER+W", root.answered);
            source.edits[0].done({ ok: true, said: removed(9) });
            root.capture.removeUserBind("SUPER+Q", root.answered);
            source.edits[1].done({ ok: true, said: removed(2) });
            root.capture.restoreUserBind(root.answers[1].token, root.answered);
            compare(source.edits[2].args[2], "2");
            source.edits[2].done({ ok: true, said: "ok hypr=bind-restored path=/h/.config/hypr/binds.lua line=2" });
            root.capture.restoreUserBind(root.answers[0].token, root.answered);
            compare(source.edits[3].args[2], "9");
        }

        function test_a_failed_edit_is_answered_and_keeps_no_undo() {
            root.answers = [];
            source.userRows = { "SUPER+SPACE": [userLine(true)] };
            root.capture.removeUserBind("SUPER+SPACE", root.answered);
            source.edits[0].done({ ok: false, error: "refused: hypr=user-bind path=/h/b.lua not-whole" });
            compare(root.answers[0].error, "refused: hypr=user-bind path=/h/b.lua not-whole");
            root.capture.removeUserBind("SUPER+SPACE", root.answered);
            source.edits[1].done({ ok: true, said: "ok hypr=bind-removed path=/h/b.lua line=12" });
            compare(root.answers[1].error.split(" ")[1], "user-bind=unread");
            compare(source.edits.length, 2);
        }

        function test_a_destroyed_key_field_releases_its_undo() {
            source.userRows = { "SUPER+SPACE": [userLine(true)] };
            const field = keyField.createObject(root, { capture: root.capture });
            field.removeLine(userLine(true));
            compare(sentEdits(), '[["remove-bind","/h/.config/hypr/binds.lua","12","SUPER+SPACE"]]');
            removedOk(0);
            const token = field.removed.token;
            compare(heldTokens(), JSON.stringify([token]));
            field.destroy();
            wait(0); // QObject.destroy() completes after the current event turn.
            compare(heldTokens(), "[]");
            root.answers = [];
            root.capture.restoreUserBind(token, root.answered);
            compare(root.answers[0].error.split(" ")[1], "user-bind=no-undo");
            compare(source.edits.length, 1);
        }

        function test_a_removal_answered_after_its_field_is_gone_is_released() {
            source.userRows = { "SUPER+SPACE": [userLine(true)] };
            const field = keyField.createObject(root, { capture: root.capture });
            field.removeLine(userLine(true));
            field.destroy();
            wait(0); // QObject.destroy() completes after the current event turn.
            removedOk(0);
            compare(heldTokens(), "[]");
            compare(source.edits.length, 1);
        }

        function test_an_undo_answered_after_its_field_is_gone_touches_nothing() {
            source.userRows = { "SUPER+SPACE": [userLine(true)] };
            const field = keyField.createObject(root, { capture: root.capture });
            field.removeLine(userLine(true));
            removedOk(0);
            field.undoRemoval();
            compare(source.edits.length, 2);
            field.destroy();
            wait(0); // QObject.destroy() completes after the current event turn.
            source.edits[1].done({ ok: false, error: "refused: hypr=changed path=/h/.config/hypr/binds.lua" });
            compare(heldTokens(), "[]");
        }

        function test_a_released_or_orphaned_removal_keeps_no_undo() {
            root.answers = [];
            source.userRows = { "SUPER+SPACE": [userLine(true)] };
            root.capture.removeUserBind("SUPER+SPACE", root.answered);
            removedOk(0);
            const token = root.answers[0].token;
            compare(heldTokens(), JSON.stringify([token]));
            root.capture.releaseUserBind(token);
            compare(heldTokens(), "[]");
            root.capture.restoreUserBind(token, root.answered);
            compare(root.answers[1].error.split(" ")[1], "user-bind=no-undo");
            // An instance torn down while its removal is in flight never
            // hears the answer, so the capture releases it.
            const ctx = root.context("acme.gone");
            registry.provider(ctx).capture.removeUserBind("SUPER+SPACE", root.answered);
            ctx.active = false;
            removedOk(1);
            compare(root.answers.length, 2);
            compare(heldTokens(), "[]");
            compare(source.edits.length, 2);
        }

        function test_a_question_and_a_capture_want_the_binds() {
            const made = fresh.createObject(root, { bindsSource: source });
            compare(made.keyCapture.wantsBinds, false);
            const asked = root.context("acme.fresh");
            const asker = made.provider(asked).capture;
            compare(asker.conflicts("SUPER+SPACE", "acme.other", "x").binds, "unread");
            wait(0); // the want is recorded after the question returns, Qt.callLater.
            compare(made.keyCapture.wantsBinds, true);
            const pending = root.disposers;
            root.disposers = [];
            for (const dispose of pending) dispose();
            compare(made.keyCapture.wantsBinds, false);
            asker.begin(first);
            compare(made.keyCapture.wantsBinds, true);
            asker.end(first, "cancel");
            compare(made.keyCapture.wantsBinds, false);
            made.destroy();
        }

        function test_a_failed_read_is_named_and_asked_again_once() {
            source.bindsFailure = "refused: binds=unparsed";
            compare(root.capture.conflicts("SUPER+SPACE", "acme.other", "x").binds, "failed");
            wait(0);
            compare(source.reads, 1);
            compare(root.capture.conflicts("SUPER+SPACE", "acme.other", "x").binds, "failed");
            wait(0);
            compare(source.reads, 1);
            source.bindsFailure = "";
            source.foreignKeys = [];
            compare(root.capture.conflicts("SUPER+SPACE", "acme.other", "x").binds, "read");
            source.bindsFailure = "refused: binds=unparsed";
            root.capture.conflicts("SUPER+SPACE", "acme.other", "x");
            wait(0);
            compare(source.reads, 2);
        }
    }
}
