import QtQuick
import QtTest
import "../../shell/plugins/vgs.scratchpads" as Scratchpads

// The scratchpads service's pad shortcuts. The Keys row names each pad by
// the word its Settings list item shows for its App, never by the pad's
// storage name, and follows an App change under the same shortcut name.
// The service is created started, so no Hyprland reply is read; the fake
// shell records each registration, each disposal and each app start.
Item {
    id: root

    Component {
        id: serviceComponent
        Scratchpads.Service { started: true }
    }

    TestCase {
        id: tests
        name: "scratchpadsService"

        property var service: null
        property var log: []
        property var starts: []

        readonly property var manifest: ({ schema: { pads: { items: { command: { presets: [
            { value: "term --app-id=one", label: "Terminal" },
            { value: "term --app-id=two", label: "Second terminal" }
        ] } } } } })

        function pad(name, command, preload) {
            return { name: name, command: command, "class": "class-" + name, screen: "focused", preload: preload };
        }

        // A settings change reaches the service as a new shell.
        function fakeShell(pads) {
            return {
                manifest: manifest,
                settings: { pads: pads },
                screens: { all: [] },
                status: { set: (key, value) => "ok" },
                run: { detached: argv => { tests.starts = tests.starts.concat([argv[2]]); return "ok"; } },
                shortcut: {
                    register: (name, description, onPressed) => {
                        tests.log = tests.log.concat([["register", name, description]]);
                        return () => { tests.log = tests.log.concat([["dispose", name]]); };
                    }
                }
            };
        }

        function init() {
            log = [];
            starts = [];
            service = createTemporaryObject(serviceComponent, root);
            verify(service !== null);
        }

        function test_keys_row_names_each_pad_by_its_app() {
            service.shell = fakeShell([pad("1", "term --app-id=two", false), pad("2", "kitty --class=pad", false)]);
            compare(log, [["register", "pad-1", "Show or hide Second terminal"], ["register", "pad-2", "Show or hide kitty --class=pad"]]);
        }

        function test_an_app_change_registers_that_pad_again() {
            service.shell = fakeShell([pad("1", "term --app-id=one", true), pad("2", "term --app-id=two", false)]);
            // Hyprland's windows, read with every reply in, hold no pad's
            // window, so the preloaded pad started.
            verify(service.preloaded);
            compare(starts, ["term --app-id=one"]);
            log = [];
            starts = [];
            // Start at login turned on for a listed pad starts nothing,
            // in the same write as its App change too.
            service.shell = fakeShell([pad("1", "term --app-id=one", true), pad("2", "kitty", true)]);
            compare(log, [["dispose", "pad-2"], ["register", "pad-2", "Show or hide kitty"]]);
            compare(starts, [], "a pad registered again starts no app");
        }

        function test_a_removed_pad_disposes_its_shortcut() {
            service.shell = fakeShell([pad("1", "term --app-id=one", false), pad("2", "term --app-id=two", false)]);
            log = [];
            service.shell = fakeShell([pad("1", "term --app-id=one", false)]);
            compare(log, [["dispose", "pad-2"]]);
        }
    }
}
