//@ pragma UseQApplication
//@ pragma AppId org.vgs.greeter
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "Core" as Core
import "Core/MonitorLogic.js" as Monitors

// The login screen's host: a second root beside shell.qml, which the
// greeter's compositor runs as `qs -p <install>/shell/greeter.qml` before
// any user logs in (D101). It has no registry, no plugin scan, no
// capability and no runner guard, and it names no plugin: it loads the one
// view VGS_GREETER_VIEW names, which the greetd configuration
// `vgshell system apply greeter` writes sets. It exists because a plugin may
// not build a window, and Quickshell resolves qs.Ui and qs.Commons only
// under this directory.
//
// The view must be a regular file inside <shellDir>/plugins once `..` and
// links are resolved. Any other value is refused with one line,
// `greeter: refused: view=<unset|missing|outside|not-a-file> path=<value>`,
// no surface is built, and qs exits 1, so the compositor ends and greetd
// starts the greeter again. A view that fails to load is refused the same
// way, as `view=unloadable`: the host draws nothing of its own. Every
// refusal comes from an event after the root loaded, the resolver's exit
// for an unset view too, since Qt.exit does nothing while the root loads
// (docs/architecture/runtime.md).
//
// An accepted view prints `greeter: view=<path> screens=<n>`. It is built
// on one overlay layer surface per screen, each covering its output, with
// the screen and whether it is the interactive one: the saved primary, which
// alone takes the keyboard and talks to greetd. The surface is the
// theme's background colour, as the lock host's is.
ShellRoot {
    id: root

    readonly property string asked: Quickshell.env("VGS_GREETER_VIEW") ?? ""
    readonly property string pluginsDir: Quickshell.shellDir + "/plugins"
    // The resolved view, "" until it is accepted.
    property string view: ""
    property var layout: ({ outputs: {}, primaryOutput: "" })
    property bool layoutRead: false
    property bool outputsRead: false
    property var outputs: null
    readonly property string loginOutput: Monitors.loginOutput(outputs, layout.outputs, layout.primaryOutput, Quickshell.screens.map(s => s.name))
    readonly property var interactiveScreen: !layoutRead || !outputsRead ? null : Quickshell.screens.find(s => s.name === loginOutput) ?? null
    onInteractiveScreenChanged: if (interactiveScreen !== null) console.info("greeter: interactive=" + interactiveScreen.name)

    function readOutputs() { outputReader.read(Monitors.OUTPUTS_REQUEST, null); }

    function refuse(reason) {
        console.error("greeter: refused: view=" + reason + " path=" + asked);
        Qt.exit(1);
    }

    Component.onCompleted: {
        resolver.running = true;
        layoutReader.running = true;
        readOutputs();
    }

    // The helper has already judged the envelope through MonitorLogic.
    // A refusal is explicit but never removes the ability to sign in.
    Process {
        id: layoutReader
        property var completion: null
        command: [Quickshell.shellDir + "/../bin/vgshell-greeter-layout", "read"]
        stdout: StdioCollector { id: layoutOut; waitForEnd: true }
        stderr: StdioCollector { id: layoutErr; waitForEnd: true }
        onExited: code => { completion = code; }
        onRunningChanged: {
            if (running) return;
            if (completion === 0) {
                try { root.layout = JSON.parse(layoutOut.text); }
                catch (error) { console.error("greeter: layout=unparsed"); }
            } else console.error("greeter: layout=" + (completion === null ? "start-failed" : "failed exit=" + completion) + " " + layoutErr.text.trim());
            root.layoutRead = true;
        }
    }

    Core.HyprctlReader {
        id: outputReader
        label: "greeter-outputs"
        onReadDone: (request, text, failure) => {
            const read = failure === "" ? Monitors.parseOutputs(text) : { ok: false, error: failure };
            root.outputs = read.ok ? read.outputs : null;
            if (!read.ok) console.error("greeter: " + read.error);
            root.outputsRead = true;
        }
    }

    Connections {
        target: Quickshell
        function onScreensChanged() { root.readOutputs(); }
    }
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (["monitoradded", "monitoraddedv2", "monitorremoved", "monitorremovedv2", "configreloaded"].indexOf(event.name) !== -1) root.readOutputs();
        }
    }

    // Resolves the plugin directory and the view in one run; a view that
    // does not exist, and an unset one, make realpath fail.
    Process {
        id: resolver
        command: ["realpath", "-e", "--", root.pluginsDir, root.asked]
        stdout: StdioCollector { id: resolved; waitForEnd: true }
        onExited: code => {
            if (root.asked === "") {
                root.refuse("unset");
                return;
            }
            const lines = resolved.text.split("\n");
            if (code !== 0 || lines.length < 2) {
                root.refuse("missing");
                return;
            }
            if (!lines[1].startsWith(lines[0] + "/") || !lines[1].endsWith(".qml")) {
                root.refuse("outside");
                return;
            }
            fileCheck.command = ["test", "-f", lines[1]];
            fileCheck.running = true;
        }
    }

    Process {
        id: fileCheck
        onExited: code => {
            if (code !== 0) {
                root.refuse("not-a-file");
                return;
            }
            root.view = fileCheck.command[2];
            console.info("greeter: view=" + root.view + " screens=" + Quickshell.screens.length);
        }
    }

    // Exactly one login view and greetd owner, even across hotplug. Moving
    // its window keeps the in-progress login and field alive.
    GreeterSurface {
        output: root.interactiveScreen
        view: root.view
        interactive: true
        onUnloadable: root.refuse("unloadable")
    }

    Variants {
        model: root.view === "" || root.interactiveScreen === null ? [] : Quickshell.screens.filter(s => s !== root.interactiveScreen)
        GreeterSurface {
            required property var modelData
            output: modelData
            view: root.view
            onUnloadable: root.refuse("unloadable")
        }
    }
}
