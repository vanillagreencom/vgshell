import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit
import "../../shell/plugins/vgs.jarvis"

// The card of a held Reboot or Shut down (vgs.jarvis PowerCard): it shows
// only while a wait is held and only on the focused screen, names the
// action and the seconds left, takes the pointer on its two controls alone,
// and its button asks the wait to proceed once. PowerWait's count of the
// seconds left never passes its wait. PowerWait's other logic is the
// jarvis-session smoke row's; this test reads what the card draws.
Item {
    id: root
    width: 900
    height: 600

    // A stand-in wait with PowerWait's members the card reads.
    QtObject {
        id: wait
        property string verb: "reboot"
        property string focusedOutput: "DP-1"
        property int remaining: 42
        property int proceeded: 0
        function proceedNow() { proceeded++; }
    }

    // A real wait with no shell: it starts nothing and registers nothing.
    PowerWait {
        id: powerWait
    }

    PowerCard {
        id: card
        anchors.fill: parent
        screen: ({ name: "DP-1" })
        wait: wait
    }

    TestCase {
        name: "jarvisPowerCard"
        when: windowShown

        function init() {
            UnitTheme.reset();
            wait.verb = "reboot";
            wait.focusedOutput = "DP-1";
            wait.remaining = 42;
            wait.proceeded = 0;
        }

        function cleanup() {
            powerWait.verb = "";
            powerWait.deadline = 0;
        }

        function find(node, test) {
            if (test(node)) return node;
            for (const child of node.children) {
                const found = find(child, test);
                if (found !== null) return found;
            }
            return null;
        }
        function texts() {
            const out = [];
            const walk = node => {
                if (node.visible !== false && typeof node.text === "string" && node.text !== "" && node.role !== undefined) out.push(node.text);
                for (const child of node.children) walk(child);
            };
            walk(card);
            return out;
        }
        function button() { return find(card, n => n.text === "Restart now" || n.text === "Shut down now"); }

        function test_a_held_reboot_draws_its_words_and_one_button() {
            verify(card.visible, "the card shows on the focused screen");
            const drawn = texts().join("\n");
            verify(drawn.indexOf("Jarvis is saving its work") !== -1, drawn);
            verify(drawn.indexOf("42 seconds") !== -1, drawn);
            compare(button().text, "Restart now");
            compare(card.inputItems.length, 2);
            verify(card.inputItems.indexOf(button()) !== -1, "the button takes the pointer");
            mouseClick(button());
            compare(wait.proceeded, 1);
        }

        function test_a_held_poweroff_names_shut_down() {
            wait.verb = "poweroff";
            wait.remaining = 1;
            compare(button().text, "Shut down now");
            verify(texts().join("\n").indexOf("1 second.") !== -1, texts().join("\n"));
        }

        function test_the_card_hides_without_a_wait_or_on_another_screen() {
            wait.verb = "";
            verify(!card.visible, "no wait, no card");
            compare(card.inputItems.length, 0, "a hidden card takes no pointer");
            wait.verb = "reboot";
            wait.focusedOutput = "HDMI-A-1";
            verify(!card.visible, "another screen's card hides");
        }

        // The shell's clock reads whole seconds and the deadline keeps the
        // fraction: half a second past the wait still counts the wait.
        function test_the_count_never_passes_the_wait() {
            powerWait.verb = "reboot";
            powerWait.deadline = Time.now.getTime() + powerWait.waitMs + 500;
            compare(powerWait.remaining, powerWait.waitMs / 1000);
            powerWait.deadline = Time.now.getTime() + 41500;
            compare(powerWait.remaining, 42);
            powerWait.deadline = Time.now.getTime() - 1000;
            compare(powerWait.remaining, 0);
        }

        function test_the_card_fits_its_screen() {
            const surface = find(card, n => n.glassSurface === true);
            verify(surface.width <= Theme.dialog.width && surface.width > 0);
            verify(surface.height > 0 && surface.height < card.height, "the card is no taller than its screen");
            compare(surface.x + surface.width / 2, card.width / 2, "centred");
        }
    }
}
