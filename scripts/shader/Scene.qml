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
// at playback level 1, in its full look (jarvis-orb) or its reduced look,
// which nothing selects yet (jarvis-orb-reduced): speaking is the one look
// whose level widens the orb's radius (Appearance.js `driveRadius`), and
// the shader returns at once past 1.3 radii, so it draws the largest area:
// the stress case. The shader's other exits depend on its noise, so it
// bounds no other state's cost. radial-backdrop is qs.Ui's RadialBackdrop
// as its one shipped caller draws it: the disc behind Voice's plasma orb,
// with the plasma's own shader hidden in every scene, since the disc's
// cost is far under the plasma's frame-to-frame spread and a reading
// taken beside it is that spread. glass-lens is qs.Ui's GlassSurface in
// the lens form as the largest plate Jarvis's overlay draws: the card of a
// held request whose payload fills the room this output leaves under the
// orb, in the overlay's look. The pass's cost grows with the plate's area,
// so the largest plate bounds the others.
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
                                    "jarvis-orb-reduced": "particleorb.frag.qsb",
                                    "radial-backdrop": "radialbackdrop.frag.qsb", "glass-lens": "glasslens.frag.qsb" })

    function plant(item) {
        // A GlassSurface builds its lens pass in a Loader.
        const effects = item.children.map(child => child instanceof Loader ? child.item : child).filter(child => child instanceof ShaderEffect);
        const effect = effects.find(child => String(child.fragmentShader).endsWith("/" + root.packs[root.shader]));
        if (root.shader === "radial-backdrop") effects.filter(child => child !== effect).forEach(child => { child.visible = false; });
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
            sourceComponent: root.shader === "plasma" || root.shader === "radial-backdrop" ? plasma
                : root.shader.startsWith("jarvis-orb") ? particle : root.shader === "glass-lens" ? plate : orb
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
    Component {
        id: plate
        GlassSurface {
            readonly property var look: Theme.appearance(JarvisLook.TOKENS, JarvisLook.LIGHT)
            // The request card's width, and the output's height less the
            // overlay's two margins, what the orb draws and the plates' gap.
            // The output is read from Quickshell: inside an Item `layer`
            // names the item's own layer, not the window above. A
            // ShellScreen's height is the screen's
            // (https://quickshell.org/docs/v0.3.1/types/Quickshell/ShellScreen/).
            implicitWidth: look.layout.prompt + 2 * look.plate.card.paddingX
            implicitHeight: Quickshell.screens[0].height - 2 * look.layout.margin - Math.round(look.orb.reach * look.orb.size) - look.plate.gap
            optIn: true
            fill: look.plate.card.fill
            standard: ({ background: look.plate.card.base, border: look.plate.card.border, radius: look.plate.card.radius })
            elevation: "none"
            lens: look.plate.lens
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
