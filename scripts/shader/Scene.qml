//@ pragma Env QS_NO_RELOAD_POPUP=1
import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "plugins/vgs.voice" as Voice

// One layer, no shell or plugin services, drawing the shader
// VGS_SHADER_NAME names: VoiceOrb, or Voice's plasma orb fed a steady level
// as the bridge's frames would feed it. The off scene keeps the same
// animation and background; only the shader stops drawing.
ShellRoot {
    id: root
    property int frames: 0
    property real previous: 0
    property var presentation: []
    readonly property string mode: Quickshell.env("VGS_SHADER_MODE")
    readonly property string shader: Quickshell.env("VGS_SHADER_NAME")
    readonly property bool complete: frames >= 730

    function plant(item) {
        const effect = item.children.find(child => child instanceof ShaderEffect);
        if (root.mode === "off") effect.visible = false;
        if (root.mode === "costly") effect.fragmentShader = Qt.resolvedUrl("costly-" + root.shader + ".frag.qsb");
    }

    PanelWindow {
        id: layer
        screen: Quickshell.screens[0]
        implicitWidth: visual.implicitWidth
        implicitHeight: visual.implicitHeight
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "vgs:shader-measure"
        // Both scenes submit a draw, including the off baseline.
        Rectangle { anchors.fill: parent; color: Theme.color.background }
        Loader {
            id: visual
            anchors.fill: parent
            sourceComponent: root.shader === "plasma" ? plasma : orb
            onLoaded: root.plant(item)
        }
        Connections {
            target: visual.Window.window
            function onFrameSwapped() {
                const now = Date.now();
                if (root.previous > 0 && !root.complete)
                    root.presentation.push(now - root.previous);
                root.previous = now;
                root.frames++;
            }
        }
    }
    Component {
        id: orb
        VoiceOrb {
            active: !root.complete
            level: 0.8
            secondaryLevel: 0.5
        }
    }
    Component {
        id: plasma
        Voice.Plasma {
            id: drawn
            active: !root.complete
            Timer {
                interval: 20
                repeat: true
                running: drawn.active
                onTriggered: drawn.push(0.8)
            }
        }
    }
    IpcHandler {
        target: "shader"
        function result(): string {
            return JSON.stringify({
                complete: root.complete, frames: root.frames,
                window: String(visual.Window.window),
                scale: visual.Window.window === null ? 0 : visual.Window.window.devicePixelRatio,
                presentation: root.presentation
            });
        }
    }
}
