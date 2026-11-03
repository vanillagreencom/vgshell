//@ pragma Env QS_NO_RELOAD_POPUP=1
import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "plugins/vgs.voice" as Voice
import "plugins/vgs.jarvis" as Jarvis
import "plugins/vgs.jarvis/Appearance.js" as JarvisLook

// One layer, no shell or plugin services, drawing the shader
// VGS_SHADER_NAME names: VoiceOrb, Voice's plasma orb fed a steady level
// as the bridge's frames would feed it, or Jarvis's particle orb speaking
// at playback level 1, in its full look (jarvis-orb) or its reduced look
// for an integrated GPU (jarvis-orb-reduced): speaking is the one look
// whose level widens the orb's radius (Appearance.js `driveRadius`), and
// the shader returns at once past 1.3 radii, so it gives the most pixels
// the shader's full work.
// The off scene keeps the same
// animation and background; only the shader stops drawing. The scene
// selects the shader's own effect by its pack, so a visual that holds a
// second effect still measures its own.
ShellRoot {
    id: root
    property int frames: 0
    property real previous: 0
    property var presentation: []
    readonly property string mode: Quickshell.env("VGS_SHADER_MODE")
    readonly property string shader: Quickshell.env("VGS_SHADER_NAME")
    readonly property bool complete: frames >= 730

    readonly property var packs: ({ voiceorb: "voiceorb.frag.qsb", plasma: "plasma.frag.qsb", "jarvis-orb": "particleorb.frag.qsb",
                                    "jarvis-orb-reduced": "particleorb.frag.qsb" })

    function plant(item) {
        const effect = item.children.find(child => child instanceof ShaderEffect && String(child.fragmentShader).endsWith("/" + root.packs[root.shader]));
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
            sourceComponent: root.shader === "plasma" ? plasma
                : root.shader === "jarvis-orb" || root.shader === "jarvis-orb-reduced" ? particle : orb
            onLoaded: root.plant(item)
        }
        // QQuickWindow.update requests rendering even without scene changes:
        // https://doc.qt.io/qt-6/qquickwindow.html#update
        // Keep the same frame requests in every scene, including the hidden shader.
        FrameAnimation {
            running: !root.complete && visual.Window.window !== null
            onTriggered: visual.Window.window.update()
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
    Component {
        id: particle
        Jarvis.ParticleOrb {
            active: !root.complete
            look: Theme.appearance(JarvisLook.TOKENS, JarvisLook.LIGHT)
            phase: "speaking"
            playback: 1
            reduced: root.shader === "jarvis-orb-reduced"
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
