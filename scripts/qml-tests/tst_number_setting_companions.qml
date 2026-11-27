import QtQuick
import QtTest
import qs.Core
import qs.Ui
import qs.Unit
import "../../shell/plugins/vgs.settings" as Settings

Item {
    id: root
    width: 640
    height: 400
    property var opened: []

    Item {
        id: actionsPanel
        function replyOf() { return ""; }
    }

    Component {
        id: shortcut
        ShortcutField {
            id: field
            width: 360
            keys: ["SUPER+M"]
            property alias addButton: plus
            property var committedKeys: []
            actions: [
                IconButton {
                    id: plus
                    iconName: "plus"
                    label: "Add another key"
                    size: "sm"
                    onClicked: field.add()
                }
            ]
            capture: recorder
            QtObject {
                id: recorder
                property Item holder: null
                property bool failed: false
                property bool passthrough: false
                property var ended: ({ item: null, reason: "" })
                readonly property int timeoutMs: 10000
                function begin(item) { holder = item; return "ok"; }
                function end(item, reason) {
                    if (item !== holder) return;
                    ended = { item: item, reason: reason };
                    holder = null;
                }
                function keyFor(key, modifiers) { return PluginLogic.capturedKey(key, modifiers); }
            }
            onCommitted: (key, index) => committedKeys = committedKeys.concat([[key, index]])
        }
    }

    Component {
        id: status
        Settings.StatusRow {
            width: root.width
            pluginId: "acme.voice"
            panel: actionsPanel
            entry: PluginLogic.statusRows({ status: {
                voices: {
                    type: "state",
                    label: "Voices",
                    hint: "Get a key at Key site, then select it under [Voice key](page:acme.voice/Settings/voiceAccount)",
                    link: { text: "Key site", url: "https://example.com/keys" }
                }
            } }, {})[0]
            onOpenLink: link => root.opened = root.opened.concat([link.url])
            onOpenPage: (page, tab) => root.opened = root.opened.concat([[page, tab]])
        }
    }

    Component {
        id: explicitAndPage
        LinkText {
            width: root.width
            text: "[Guide to setup](page:acme.voice/Setup) and [Voice key](page:acme.voice/Settings/voiceAccount) or Privacy"
            link: ["Privacy", "Guide"]
            onActivated: words => root.opened = root.opened.concat([words])
            onPageActivated: (page, tab) => root.opened = root.opened.concat([[page, tab]])
        }
    }

    UnitCase {
        name: "SettingsControlCompanions"
        when: windowShown

        function init() {
            root.opened = [];
            root.forceActiveFocus();
        }
        function make(component) {
            const made = createTemporaryObject(component, root);
            verify(made !== null);
            verify(waitForPolish(made));
            verify(renderedFrame(made));
            return made;
        }
        function clickLink(hint, index) {
            tryVerify(() => hint.underlined.some(span => span.index === index));
            const span = hint.underlined.find(span => span.index === index);
            mouseClick(hint, (span.left + span.right) / 2, (span.line + 0.5) * hint.linePitch);
        }

        function test_add_button_captures_the_first_chord() {
            const field = make(shortcut);
            mouseClick(field.addButton);
            verify(field.capturing);
            keyClick(Qt.Key_K, Qt.MetaModifier);
            compare(field.committedKeys, [["SUPER+K", 1]]);
            verify(!field.capturing);
        }

        function test_a_settings_status_hint_draws_and_follows_both_links() {
            const row = make(status);
            const hint = displayedTextItems(row).find(item => item instanceof LinkText && item.role === "hint" && item.plain !== "");
            verify(hint !== undefined);
            compare(hint.links.map(link => link.words), ["Key site", "Voice key"]);
            compare((hint.labelItem.text.match(/<font color=/g) || []).length, 2);

            clickLink(hint, 0);
            clickLink(hint, 1);
            compare(root.opened, ["https://example.com/keys", ["acme.voice", "Settings/voiceAccount"]]);

            root.opened = [];
            hint.forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Home);
            keyClick(Qt.Key_Return);
            keyClick(Qt.Key_Right);
            keyClick(Qt.Key_Return);
            compare(root.opened, ["https://example.com/keys", ["acme.voice", "Settings/voiceAccount"]]);
        }

        function test_explicit_link_words_keep_precedence_and_activation() {
            const hint = make(explicitAndPage);
            compare(hint.links.map(link => link.words), ["Guide", "Voice key", "Privacy"]);
            for (const index of [0, 1, 2]) clickLink(hint, index);
            compare(root.opened, ["Guide", ["acme.voice", "Settings/voiceAccount"], "Privacy"]);
        }
    }
}
