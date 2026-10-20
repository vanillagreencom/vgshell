import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit

// CopyText: `copy(text)` puts the text on the clipboard and `confirming`
// holds for `codeLine.confirm` milliseconds after each copy, a later copy
// holding it again from its own start.
// inputs: shell/Ui/* shell/Ui/**/* shell/Commons/*
Item {
    id: root
    width: 400
    height: 120

    CopyText { id: copier }
    // Reads the clipboard back.
    TextEdit { id: paste; width: 360; height: 20 }

    TestCase {
        name: "copytext"
        when: windowShown

        function init() { UnitTheme.reset(); paste.text = ""; }

        function clipboardText() {
            paste.text = "";
            paste.paste();
            return paste.text;
        }

        function test_copy_puts_the_text_on_the_clipboard() {
            copier.copy("100.64.0.1");
            compare(clipboardText(), "100.64.0.1");
            copier.copy("desk.tail-fixture.ts.net");
            compare(clipboardText(), "desk.tail-fixture.ts.net", "a second copy replaces the first");
        }

        function test_confirming_holds_for_its_token() {
            tryCompare(copier, "confirming", false, 3000);
            compare(UnitTheme.override({ codeLine: { confirm: 120 } }), "ok");
            copier.copy("100.64.0.2");
            compare(copier.confirming, true);
            tryCompare(copier, "confirming", false, 1000);
        }

        function test_a_later_copy_holds_confirming_again() {
            tryCompare(copier, "confirming", false, 3000);
            compare(UnitTheme.override({ codeLine: { confirm: 1000 } }), "ok");
            copier.copy("100.64.0.3");
            wait(600);
            copier.copy("100.64.0.4");
            wait(600);
            compare(copier.confirming, true, "the second copy holds it 1000 ms from its own start");
            tryCompare(copier, "confirming", false, 3000);
        }
    }
}
