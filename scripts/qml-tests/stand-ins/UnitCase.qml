import QtQuick
import QtTest
import qs.Ui

// The TestCase of a unit test that waits for the window to draw. QtTest's
// waitForRendering waits for the window's next frame swap, and a window
// whose requested state is already drawn schedules none, so the bare wait
// fails on a settled window under host load with no product change.
// renderedFrame asks the window for the frame first, so the wait answers on
// whether the window draws. scripts/qml-unit.sh refuses a test file that
// calls waitForRendering itself.
TestCase {
    // LinkText owns plain words; its styled Label and hidden layout twin
    // are not additional readings. Item.children contains visual children:
    // https://doc.qt.io/qt-6/qml-qtquick-item.html#children-prop
    // includeHidden is only for component contracts that assert hiding.
    function displayedTextItems(item, includeHidden) {
        const found = [];
        function visit(node) {
            if (!includeHidden && !node.visible) return;
            if (node instanceof LinkText || node instanceof Text) {
                found.push(node);
                return;
            }
            for (const child of node.children) visit(child);
        }
        visit(item);
        return found;
    }
    function displayedText(item) {
        verify(item instanceof LinkText || item instanceof Text, "a displayed text owner is required");
        return item instanceof LinkText ? item.plain : item.text;
    }
    // Typography assertions need the actual renderer, not Control.font.
    // LinkText publishes labelItem for this; discovery still returns its
    // owner once and never interprets the renderer's StyledText as words.
    function displayedTextRenderer(item) {
        verify(item instanceof LinkText || item instanceof Text, "a displayed text owner is required");
        return item instanceof LinkText ? item.labelItem : item;
    }
    function semanticLabelItems(item, includeHidden) {
        return displayedTextItems(item, includeHidden).filter(child => child instanceof InfoButton);
    }
    function semanticLabelText(item) {
        const labels = semanticLabelItems(item);
        compare(labels.length, 1, "one current semantic label is displayed");
        return displayedText(labels[0]);
    }
    function helpDialog(label) {
        verify(label instanceof InfoButton, "help belongs to an InfoButton label");
        const dialogs = label.children.filter(child => child instanceof ModalDialog);
        compare(dialogs.length, 1, "the label owns one modal");
        return dialogs[0];
    }
    function helpParagraphs(label, parent) {
        // The modal stand-in owns the production body Component, not a
        // window. QtTest owns this body's cleanup after each test:
        // https://doc.qt.io/qt-6/qml-qttest-testcase.html#createTemporaryObject-method
        const body = createTemporaryObject(helpDialog(label).body, parent, { width: 420 });
        verify(body !== null, "the shared modal body is created");
        verify(waitForPolish(body));
        return displayedTextItems(body).filter(child => child instanceof LinkText && !(child instanceof InfoButton));
    }

    // True when ITEM's window drew a frame within TIMEOUT milliseconds
    // (QtTest's default when omitted).
    function renderedFrame(item, timeout) {
        const window = item.Window.window;
        if (window)
            window.update();
        return waitForRendering(item, timeout);
    }
}
