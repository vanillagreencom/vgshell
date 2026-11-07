import QtQuick
import QtTest
import qs.Core
import qs.Ui
import qs.Unit

Item {
    id: root
    width: 480
    height: 120
    KeyCaps { id: caps; shortcut: "SUPER+code:30" }
    Text { id: hint; y: caps.height; text: ShortcutLabels.keyCaps("SUPER+code:30").join("+") }

    UnitCase {
        name: "shortcutlabels"
        when: windowShown

        function init() {
            const judged = PluginLogic.validateManifest({
                schemaVersion: 1, id: "acme.labels", name: "Keys", version: "1.0.0",
                author: "Test", description: "Layout names", kinds: ["service"],
                entryPoints: { service: "Service.qml" }, capabilities: ["shortcut"],
                settings: {}, schema: {},
                hyprland: { binds: [{ shortcut: "talk", key: "SUPER+code:30" }] }
            }, "/fixture");
            verify(judged.ok, judged.error || "fixture manifest");
            Registry.manifests = { "acme.labels": judged.manifest };
            Capabilities.hyprland.devices = { layout: "us" };
        }

        function cleanup() {
            Registry.manifests = {};
            Capabilities.hyprland.devices = null;
            if (Capabilities.hyprland.pendingKeys !== null)
                Capabilities.hyprland.finishKeys({ ok: false, error: "fixture-end" });
            tryCompare(ShortcutLabels, "pending", false);
        }

        function request() {
            tryVerify(() => Capabilities.hyprland.pendingKeys !== null);
            compare(JSON.stringify(Capabilities.hyprland.pendingKeys.keys), '["code:30"]');
        }

        function finish(keysym, codepoint) {
            Capabilities.hyprland.finishKeys({ ok: true, keys: [{ modifiers: [], keycode: 30, keysym: keysym, codepoint: codepoint }] });
        }

        function test_layout_names_redraw_caps_and_hints_without_rewriting_keys() {
            request();
            finish("u", 117);
            tryCompare(hint, "text", "Super+U");
            compare(JSON.stringify(caps.caps), '["Super","U"]');
            verify(renderedFrame(caps));
            Capabilities.hyprland.devices = { layout: "ru" };
            request();
            finish("Cyrillic_ghe", 1075);
            tryCompare(hint, "text", "Super+Г");
            compare(JSON.stringify(caps.caps), '["Super","Г"]');
            verify(renderedFrame(caps));
            compare(caps.shortcut, "SUPER+code:30");
        }

        function test_stale_layout_reply_never_labels_the_current_layout() {
            request();
            Capabilities.hyprland.devices = { layout: "ru" };
            finish("u", 117);
            compare(hint.text, "Super+[Choose a key](page:vgs.settings)");
            request();
            finish("Cyrillic_ghe", 1075);
            tryCompare(hint, "text", "Super+Г");
        }

        function test_unresolved_name_is_actionable_and_does_not_retry() {
            request();
            Capabilities.hyprland.finishKeys({ ok: false, error: "keycode-unresolved" });
            tryCompare(ShortcutLabels, "pending", false);
            compare(hint.text, "Super+[Choose a key](page:vgs.settings)");
            const labels = caps.children.filter(child => child.text !== undefined && child.value !== undefined);
            compare(JSON.stringify(labels.map(child => child.text)), '["Super","Choose a key"]');
            verify(renderedFrame(caps));
            compare(Capabilities.hyprland.pendingKeys, null);
        }
    }
}
