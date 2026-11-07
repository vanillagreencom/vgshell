import QtQuick
import QtTest
import qs.Core
import qs.Ui
import qs.Unit

Item {
    id: root
    width: 480
    height: 320
    property var pages: []
    KeyCaps { id: caps; shortcut: "SUPER+code:30"; onPageActivated: (page, tab) => root.pages.push([page, tab]) }
    Text { id: hint; y: caps.height; text: ShortcutLabels.keyCaps("SUPER+code:30").join("+") }
    KeyHints {
        id: hints
        y: 60
        hints: [{ key: "SUPER+code:30", text: "Talk" }]
        onPageActivated: (page, tab) => root.pages.push([page, tab])
    }
    ShortcutField {
        id: field
        y: 120
        width: parent.width
        keys: ["SUPER+code:30"]
        onPageActivated: (page, tab) => root.pages.push([page, tab])
    }

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
            compare(hint.text, "Choose a key in [Settings](page:vgs.settings)");
            request();
            finish("Cyrillic_ghe", 1075);
            tryCompare(hint, "text", "Super+Г");
        }

        function test_unresolved_name_is_actionable_and_does_not_retry() {
            request();
            Capabilities.hyprland.finishKeys({ ok: false, error: "keycode-unresolved" });
            tryCompare(ShortcutLabels, "pending", false);
            compare(hint.text, "Choose a key in [Settings](page:vgs.settings)");
            verify(caps.linked);
            compare(caps.children.filter(child => child.value !== undefined && child.text !== undefined).length, 0);
            const guidance = caps.children.find(child => child.item !== undefined && child.item !== null).item;
            compare(guidance.plain, "Choose a key in Settings");
            compare(guidance.Accessible.name, "Choose a key in Settings");
            root.pages = [];
            guidance.forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Return);
            compare(JSON.stringify(root.pages), '[["vgs.settings",""]]');
            mouseClick(guidance, guidance.linkBox.x + guidance.linkBox.width / 2, guidance.linkBox.y + guidance.linkBox.height / 2);
            compare(JSON.stringify(root.pages), '[["vgs.settings",""],["vgs.settings",""]]');
            verify(renderedFrame(caps));
            compare(Capabilities.hyprland.pendingKeys, null);
        }

        function findLink(node) {
            if (node.linked === true && node.linkBox !== undefined) return node;
            for (const child of node.children) {
                const found = findLink(child);
                if (found !== null) return found;
            }
            return null;
        }

        function test_hint_and_field_forward_the_shared_fallback() {
            request();
            Capabilities.hyprland.finishKeys({ ok: false, error: "keycode-unresolved" });
            for (const owner of [hints, field]) {
                const link = findLink(owner);
                verify(link !== null);
                compare(link.Accessible.name, "Choose a key in Settings");
                root.pages = [];
                link.forceActiveFocus(Qt.TabFocusReason);
                keyClick(Qt.Key_Return);
                compare(JSON.stringify(root.pages), '[["vgs.settings",""]]');
                verify(renderedFrame(owner));
            }
            compare(field.keys[0], "SUPER+code:30");
        }
    }
}
