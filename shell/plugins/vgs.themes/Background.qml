import QtQuick
import "Files.js" as Files

// The applied theme's background: the image WallpaperState names for this
// screen, cropped to fill it. A screen whose own image cannot be read draws
// `current` in its place. An unreadable current falls back to the applied
// package's remembered or first image. No image means no mapped surface.
Item {
    id: root

    property var shell: null
    property var screen: null
    // Read by the background host: whether this instance has an image to
    // draw, so the host maps the screen's surface.
    readonly property bool shown: drawn

    // Whether the image drew its source; it stays true while a new source
    // loads, since the old image stays on screen until the new one is ready.
    property bool drawn: false
    // The source WallpaperState names for this screen, its own or `current`.
    readonly property string wanted: wallpaper.sourceFor(root.screen === null ? "" : root.screen.name)
    readonly property string current: wallpaper.source
    readonly property string currentTheme: shell === null ? "" : shell.theme.current
    // At most the wanted image, current, remembered and first are tried.
    // A new published URL starts a new selection, including an explicit
    // set of the same file after a failed decode.
    property var selection: ({ kind: "wanted" })
    property int generation: 0
    onWantedChanged: resetSelection()
    onCurrentChanged: resetSelection()
    onCurrentThemeChanged: resetSelection()

    function resetSelection() {
        generation++;
        selection = { kind: "wanted" };
    }

    function packageImage() {
        const started = generation;
        selection = { kind: "waiting", source: "" };
        if (shell === null) return;
        shell.theme.images("applied", result => {
            if (started !== root.generation) return;
            if (result.state !== "ok") {
                console.error("background: fallback unavailable reason=" + result.reason);
                return;
            }
            const ownPath = wallpaper.screenPaths[root.screen === null ? "" : root.screen.name];
            const images = result.images.filter(image => image.path !== wallpaper.path && image.path !== ownPath);
            if (images.length === 0) return;
            const first = Files.stampedUrl(images[0].path, root.current);
            const remembered = images.find(image => image.background === wallpaper.themes[root.shell.theme.current]);
            root.selection = { kind: "package", source: remembered ? Files.stampedUrl(remembered.path, root.current) : first, first: first };
        });
    }

    WallpaperState { id: wallpaper }

    Image {
        anchors.fill: parent
        source: root.selection.kind === "wanted" ? root.wanted : root.selection.source
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        retainWhileLoading: true
        // Decode at device pixels, sized from the screen because the item
        // has no size while the host maps no surface.
        sourceSize.width: root.screen === null ? 0 : Math.ceil(root.screen.width * root.screen.devicePixelRatio)
        sourceSize.height: root.screen === null ? 0 : Math.ceil(root.screen.height * root.screen.devicePixelRatio)
        // Each screen holds its own decode.
        cache: false
        onStatusChanged: {
            if (status === Image.Ready) root.drawn = true;
            else if (status !== Image.Loading) root.drawn = false;
            if (status !== Image.Error) return;
            console.error("background: " + source + " unreadable");
            switch (root.selection.kind) {
            case "wanted":
                if (root.wanted !== root.current && root.current !== "") {
                    root.selection = { kind: "current", source: root.current };
                    break;
                }
                root.packageImage();
                break;
            case "current": root.packageImage(); break;
            case "package":
                root.selection = source.toString() === root.selection.first
                    ? { kind: "none", source: "" }
                    : { kind: "first", source: root.selection.first };
                break;
            case "first": root.selection = { kind: "none", source: "" }; break;
            }
        }
    }
}
