import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit

// Theme reaches a component: a published value is the theme's, a theme
// change re-evaluates a binding without rebuilding the item, the revision
// rises after the groups hold the new theme, and a refused document changes
// nothing. The user's Appearance values, Theme's one input, resolve over the
// theme before the revision rises, an equal text resolves nothing again,
// and no text draws the theme alone. The document revision rises for
// another theme document and never for an Appearance value. The pixel rows
// read colours back from a rendered item.
Item {
    id: root
    width: 200
    height: 100

    Rectangle { id: filled; width: 20; height: 20; color: Theme.color.accent }
    Button { id: button; text: "Go"; y: 40 }
    property int revisionsSeen: 0
    property string accentAtRevision: ""
    property int radiusAtRevision: -1
    Connections {
        target: Theme
        function onRevisionChanged() { root.revisionsSeen += 1; root.accentAtRevision = Theme.color.accent; root.radiusAtRevision = Theme.popover.radius; }
    }

    TestCase {
        name: "theme"
        when: windowShown

        function init() {
            Theme.appearanceInput = "";
            UnitTheme.reset();
        }

        function test_default_values() {
            compare(Theme.name, "vgs");
            compare(Theme.color.accent, "#ffff5a36");
            compare(Theme.text.body.family, "Inter Variable");
            compare(Theme.text.label.family, "JetBrains Mono");
            compare(Theme.bar.height, 28);
            compare(Theme.motion.duration.fast, 100);
        }

        function test_groups_are_frozen() {
            verify(Object.isFrozen(Theme.color));
            verify(Object.isFrozen(Theme.text.body));
            Theme.color.accent = "#ff000000";
            compare(Theme.color.accent, "#ffff5a36");
        }

        function test_change_reaches_a_binding_without_a_rebuild() {
            const before = filled;
            compare(String(filled.color), "#ff5a36");
            compare(UnitTheme.override({ palette: { accent: "#00ff00" } }), "ok");
            compare(String(filled.color), "#00ff00");
            verify(filled === before);
            // The button's fill animates to the new theme.
            tryCompare(button.background, "color", Qt.color("#00ff00"));
        }

        function test_revision_rises_after_the_groups() {
            const seen = root.revisionsSeen;
            const revision = Theme.revision;
            compare(UnitTheme.override({ palette: { accent: "#0000ff" } }), "ok");
            compare(Theme.revision, revision + 1);
            compare(root.revisionsSeen, seen + 1);
            compare(root.accentAtRevision, "#ff0000ff");
        }

        function test_refused_document_changes_nothing() {
            compare(UnitTheme.override({ palette: { accent: "#123456" } }), "ok");
            const revision = Theme.revision;
            compare(UnitTheme.override({ palette: { acent: "#000000" } }), "theme: refused: token=palette.acent reason=unknown-token");
            compare(Theme.color.accent, "#ff123456");
            compare(Theme.revision, revision);
        }

        function test_appearance_values_resolve_before_the_revision() {
            const revision = Theme.revision;
            const text = JSON.stringify({ windowRadius: 12 });
            Theme.appearanceInput = text;
            compare(Theme.revision, revision + 1);
            compare(Theme.popover.radius, 9, "a flyout takes three quarters of the corner radius");
            compare(root.radiusAtRevision, 9, "the groups hold the values before the revision rises");
            compare(Theme.appearanceState.sources.windowRadius, "user");
            verify(Object.isFrozen(Theme.appearanceState));
            Theme.appearanceInput = JSON.stringify({ windowRadius: 12 });
            compare(Theme.revision, revision + 1, "an equal text resolves nothing again");
            compare(UnitTheme.override({ palette: { accent: "#123456" } }), "ok");
            compare(Theme.popover.radius, 9, "a theme change keeps the user's values");
            Theme.appearanceInput = "";
            compare(Theme.popover.radius, 0, "no text draws the theme alone");
            compare(Theme.appearanceState.sources.windowRadius, "theme");
        }

        function test_the_document_revision_follows_the_theme_document_alone() {
            const document = Theme.documentRevision;
            const revision = Theme.revision;
            Theme.appearanceInput = JSON.stringify({ windowRadius: 12 });
            compare(Theme.revision, revision + 1, "the Appearance value is published");
            compare(Theme.documentRevision, document, "an Appearance value is no new theme document");
            compare(UnitTheme.override({ palette: { accent: "#123456" } }), "ok");
            compare(Theme.documentRevision, document + 1, "another theme document raises it once");
            Theme.appearanceInput = "";
            compare(Theme.documentRevision, document + 1);
        }

        // expected-log: appearance: refused: windowRadius=99 -- the refused member the test plants is logged
        function test_a_refused_value_is_logged_and_set_by_theme() {
            Theme.appearanceInput = JSON.stringify({ windowRadius: 99, controlRadius: 4 });
            compare(Theme.popover.radius, 0);
            compare(Theme.button.radius, 4, "the other member still applies");
            compare(Theme.appearanceState.sources.windowRadius, "theme");
        }

        function test_pixels_follow_the_theme() {
            compare(UnitTheme.override({ palette: { accent: "#ff0000" } }), "ok");
            wait(100);
            const img = grabImage(filled);
            verify(img.red(10, 10) > 200 && img.green(10, 10) < 50, "the rectangle draws the accent");
        }
    }
}
