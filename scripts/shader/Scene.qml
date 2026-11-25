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
import "plugins/vgs.launcher" as Launcher
import "plugins/vgs.launcher/Appearance.js" as LauncherLook
import "plugins/vgs.notifications" as Notifications
import "plugins/vgs.notifications/Appearance.js" as NotificationLook

// One layer, no shell or plugin services, drawing the shader
// VGS_SHADER_NAME names: VoiceOrb, Voice's plasma orb fed a steady level
// as the bridge's frames would feed it, or Jarvis's orb speaking at
// playback level 1 at its shipped canvas, in the style and look the
// runner hands it as VGS_ORB_STYLE and VGS_ORB_REDUCED: one scene per
// option of the manifest's Orb style setting (jarvis-orb-<value>), and the
// reduced look of the setting's default style, which nothing selects yet
// (jarvis-orb-reduced). scripts/measure-shader.sh reads the list and sets
// both. Speaking is the one look
// whose level widens the orb's radius (Appearance.js `driveRadius`), and
// each style's shader returns at once past its reach, so it draws the
// largest area: the stress case. A style's other exits depend on its
// state, so a scene bounds no other state's cost. radial-backdrop is
// qs.Ui's RadialBackdrop as its one shipped caller draws it: the disc
// behind Voice's plasma orb, with the plasma's own shader hidden in every
// scene, since the disc's cost is far under the plasma's frame-to-frame
// spread and a reading taken beside it is that spread. glass-lens is qs.Ui's GlassSurface in
// the lens form as the largest plate Jarvis's overlay draws: the card of a
// held request whose payload fills the room this output leaves under the
// orb, in the overlay's look. The pass's cost grows with the plate's area,
// so the largest plate bounds the others. launcher and notification-stack
// are the glass each of those plugins draws today: GlassSurface's flat
// form under the plugin's own EdgeLight, at rest, in its look. launcher
// is the launcher's own card at its tallest, the share of the output its
// look allows; a picker a caller sizes wider is not drawn.
// notification-stack is as many toasts at their tallest as fill the
// stack's room on this output, each with its edge light running, as a
// stack draws them while the inbox is closed. The light's pass, like the
// shadow under each card, grows with the cards' area, so the largest
// card and the fullest stack bound the others. The stack's fade at its
// scroll edges is not glass and is not drawn.
// The off scene keeps the same
// animation and background; only the shader stops drawing, in each of
// the scene's effects that draws it. In launcher and notification-stack
// the off scene also hides each GlassSurface, so the reading is the
// whole glass, the flat form and its edge light; these two scenes have
// no costly scene. The scene selects the shader's own effect by its
// pack, so a visual that holds a second effect still measures its own.
ShellRoot {
    id: root
    property int frames: 0
    property real previous: 0
    property var presentation: []
    readonly property string mode: Quickshell.env("VGS_SHADER_MODE")
    readonly property string shader: Quickshell.env("VGS_SHADER_NAME")
    readonly property bool complete: frames >= 730

    readonly property var packs: ({ voiceorb: "voiceorb.frag.qsb", plasma: "plasma.frag.qsb",
                                    "radial-backdrop": "radialbackdrop.frag.qsb", "glass-lens": "glasslens.frag.qsb",
                                    launcher: "edgelight.frag.qsb", "notification-stack": "edgelight.frag.qsb" })
    // The orb style and look a jarvis-orb scene draws, as the runner hands
    // them: empty and "0" for any other scene.
    readonly property string orbStyle: Quickshell.env("VGS_ORB_STYLE")
    readonly property bool orbReduced: Quickshell.env("VGS_ORB_REDUCED") === "1"
    readonly property string pack: orbStyle === "" ? packs[shader] || "" : orbStyle + ".frag.qsb"

    function plant(item) {
        // A GlassSurface builds its lens pass in a Loader.
        const effects = item.children.map(child => child instanceof Loader ? child.item : child).filter(child => child instanceof ShaderEffect);
        const drawn = effects.filter(child => String(child.fragmentShader).endsWith("/" + root.pack));
        if (root.shader === "radial-backdrop") effects.filter(child => !drawn.includes(child)).forEach(child => { child.visible = false; });
        if (root.mode === "off") item.children.filter(child => child.glassSurface === true).forEach(child => { child.visible = false; });
        drawn.forEach(effect => {
            if (root.mode === "off") effect.visible = false;
            if (root.mode === "costly") effect.fragmentShader = Qt.resolvedUrl("costly-" + root.shader + ".frag.qsb");
        });
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
                : root.orbStyle !== "" ? particle : root.shader === "glass-lens" ? plate
                : root.shader === "launcher" ? launcherCard : root.shader === "notification-stack" ? toastStack : orb
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
            style: root.orbStyle
            reduced: root.orbReduced
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
            implicitHeight: Quickshell.screens[0].height - look.layout.margin - look.layout.bottom - Math.round(look.orb.reach * look.orb.size) - look.plate.gap
            optIn: true
            fill: look.plate.card.fill
            standard: ({ background: look.plate.card.base, border: look.plate.card.border, radius: look.plate.card.radius })
            elevation: "none"
            lens: look.plate.lens
        }
    }
    Component {
        id: launcherCard
        Item {
            id: launcher
            readonly property var look: Theme.appearance(LauncherLook.TOKENS, LauncherLook.LIGHT)
            // The room the card's shadow reaches past it on each side, so
            // the layer holds the whole shadow, as the launcher's
            // output-wide layer does. A RectangularShadow reaches `blur`
            // plus `spread` past its item, moved by its offset
            // (https://doc.qt.io/qt-6/qml-qtquick-effects-rectangularshadow.html).
            readonly property real room: card.shadow.blur + Math.max(0, card.shadow.spread) + Math.abs(card.shadow.offsetY)
            implicitWidth: card.width + 2 * room
            implicitHeight: card.height + 2 * room
            // Launcher.qml's card at rest: the look's width, and the
            // tallest share of the output its rows may fill.
            GlassSurface {
                id: card
                x: launcher.room
                y: launcher.room
                width: launcher.look.card.width
                height: Math.round(Quickshell.screens[0].height * launcher.look.card.tallest)
                radius: Math.min(card.height / 2, launcher.look.card.radius)
                optIn: true
                fill: launcher.look.card.fill
                padding: launcher.look.card.padding
                shadowCached: false
            }
            Launcher.EdgeLight {
                look: launcher.look
                follow: card
                visible: card.drawn
            }
        }
    }
    Component {
        id: toastStack
        Item {
            id: stack
            readonly property var look: Theme.appearance(NotificationLook.TOKENS, NotificationLook.LIGHT)
            // Stack.qml's top stack: the first card a slot's gap below the
            // stack's edge gap, each next one a card and a gap below it,
            // and as many whole cards as end above the far gap. Each card
            // is CardFace's glass under a settled toast at the look's
            // tallest card.
            readonly property real pitch: look.card.maxHeight + look.card.gap
            readonly property int cards: Math.floor((implicitHeight - look.stack.edge - look.stack.far) / pitch)
            // The scroll frame's width, whose side room holds the cards'
            // shadows (CardScroll.qml).
            implicitWidth: look.card.width + 2 * look.stack.pad
            implicitHeight: Quickshell.screens[0].height
            Repeater {
                id: plates
                model: stack.cards
                GlassSurface {
                    required property int index
                    x: stack.look.stack.pad
                    y: stack.look.stack.edge + stack.look.card.gap + index * stack.pitch
                    width: stack.look.card.width
                    height: stack.look.card.maxHeight
                    radius: stack.look.radius.full
                    optIn: true
                    fill: stack.look.card.fill
                    elevation: "tight"
                    shadowCached: false
                }
            }
            // The lights are the stack item's own children, as the scene
            // finds its effects; each starts once its card exists.
            Repeater {
                model: plates.count
                Notifications.EdgeLight {
                    required property int index
                    look: stack.look
                    follow: plates.itemAt(index)
                    visible: follow.drawn
                }
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
