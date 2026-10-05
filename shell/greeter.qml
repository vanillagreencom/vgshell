//@ pragma UseQApplication
//@ pragma AppId org.vgs.greeter
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

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
// the screen and whether it is the interactive one: the first screen, which
// alone takes the keyboard and talks to greetd. The surface is the
// theme's background colour, as the lock host's is.
ShellRoot {
    id: root

    readonly property string asked: Quickshell.env("VGS_GREETER_VIEW") ?? ""
    readonly property string pluginsDir: Quickshell.shellDir + "/plugins"
    // The resolved view, "" until it is accepted.
    property string view: ""

    function refuse(reason) {
        console.error("greeter: refused: view=" + reason + " path=" + asked);
        Qt.exit(1);
    }

    Component.onCompleted: resolver.running = true

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

    Variants {
        model: root.view === "" ? [] : Quickshell.screens

        PanelWindow {
            id: surface

            required property var modelData
            readonly property bool interactive: modelData === Quickshell.screens[0]

            screen: modelData
            // The theme's background under the view, as the lock host
            // draws under the lock screen, so nothing behind the surface shows.
            color: Theme.color.background
            anchors.left: true
            anchors.right: true
            anchors.top: true
            anchors.bottom: true
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "vgs:greeter"
            WlrLayershell.keyboardFocus: interactive ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            Loader {
                anchors.fill: parent
                source: "file://" + root.view
                onLoaded: {
                    item.screen = surface.modelData;
                    item.interactive = Qt.binding(() => surface.interactive);
                }
                onStatusChanged: if (status === Loader.Error) root.refuse("unloadable")
            }
        }
    }
}
