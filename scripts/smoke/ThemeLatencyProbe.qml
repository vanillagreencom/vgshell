import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Core
import qs.Commons

// Loaded only for the latency row through the smoke probe's component
// loader. Frame timestamps come from the same windows the user sees.
Scope {
    id: root
    property var themeLatency: null
    property var themeLatencyJobs: []
    property var selectedFrameItem: null
    property bool selectedFrameReady: false

    function typeName(item) { return String(item).split("(")[0].replace(/(_QML(TYPE)?_\d+)+$/, ""); }
    // The engine hands one wrapper per object, so a Set finds each object
    // once; an indexOf walk made a browser frame's reader quadratic.
    function descendants(item) {
        const all = [item];
        const seen = new Set(all);
        for (let i = 0; i < all.length; i++) {
            const children = Array.from(all[i].children || []).concat(Array.from(all[i].data || []));
            for (const child of children)
                if (typeof child === "object" && child !== null && !seen.has(child)) {
                    seen.add(child);
                    all.push(child);
                }
        }
        return all;
    }
    // The browser ITEM's views and cards, found in one walk that does not
    // enter a card and names only an object with a model or with cards, as
    // both views have. Naming an object builds a string: while the reader
    // named every object of the browser, its frames took 67 to 107 ms of a
    // warm open (probeMs, theme-latency row on cachy, 2026-10-08).
    function browserParts(item) {
        const parts = { themeView: undefined, wallpaperView: undefined, cards: [] };
        const all = [item];
        const seen = new Set(all);
        for (let i = 0; i < all.length; i++) {
            const node = all[i];
            if (node.modelData !== undefined || node.cards !== undefined) {
                const type = typeName(node);
                if (type === "ThemeView") parts.themeView = node;
                else if (type === "WallpaperView") parts.wallpaperView = node;
                else if (type === "ThemeCard" || type === "WallpaperCard") {
                    parts.cards.push(node);
                    continue;
                }
            }
            const children = Array.from(node.children || []).concat(Array.from(node.data || []));
            for (const child of children)
                if (typeof child === "object" && child !== null && !seen.has(child)) {
                    seen.add(child);
                    all.push(child);
                }
        }
        return parts;
    }
    function visibleInTree(item) {
        for (let at = item; at !== null && at !== undefined; at = at.parent)
            if (at.visible === false) return false;
        return true;
    }

    // What the browser's complete catalog still waits for, from its
    // browserParts PARTS: `view` before its answers, `cards` before every
    // package and catalog entry has a card, `pictures=N` while N visible
    // cards have no ready picture, else "".
    function catalogWaiting(parts) {
        const view = parts.themeView;
        if (view === undefined || view.entries === null || view.packages === null) return "view";
        const names = {};
        for (const row of view.packages) if (row.state !== "shadowed") names[row.name] = true;
        for (const row of view.entries) names[row.name] = true;
        if (view.shownCards.length !== Object.keys(names).length) return "cards";
        let pending = 0;
        for (const card of parts.cards.filter(child => typeName(child) === "ThemeCard" && visibleInTree(child))) {
            if (card.picture === "") continue;
            const shown = descendants(card).filter(child => child instanceof Image && visibleInTree(child) && String(child.source) !== "");
            if (!shown.some(image => image.status === Image.Ready)) pending++;
        }
        return pending === 0 ? "" : "pictures=" + pending;
    }
    function catalogReady(item) { return catalogWaiting(browserParts(item)) === ""; }

    function latencyMark(stage) {
        if (themeLatency !== null && themeLatency[stage] === undefined)
            themeLatency[stage] = Date.now() - themeLatency.started;
    }

    // A GUI-thread gap of beatMs plus stallMs or longer between two beats
    // while a reading waits for its frame: [ms from the reading's start to
    // the gap's start, its length]. A blocked thread and a busy one read
    // alike, and a shorter gap is not seen.
    readonly property int beatMs: 4
    readonly property int stallMs: 12
    property double lastBeat: 0
    Timer {
        interval: root.beatMs
        repeat: true
        running: root.themeLatency !== null && root.themeLatency.kind !== "step" && root.themeLatency.drawn === undefined
        onRunningChanged: root.lastBeat = Date.now()
        onTriggered: {
            const now = Date.now();
            const reading = root.themeLatency;
            if (reading !== null && now - root.lastBeat >= root.beatMs + root.stallMs) {
                if (reading.stalls === undefined) reading.stalls = [];
                reading.stalls.push([root.lastBeat - reading.started, now - root.lastBeat]);
            }
            root.lastBeat = now;
        }
    }

    // The theme file's change as the shell's own watcher sees it, beside
    // ThemeSource's watcher of the same file.
    FileView {
        path: Paths.configDir + "/theme.json"
        preload: false
        watchChanges: true
        printErrors: false
        onFileChanged: if (root.themeLatency !== null && root.themeLatency.kind === "theme") root.latencyMark("seen")
    }

    // A theme change rewrites the shell's Hyprland layer and reloads
    // Hyprland's configuration: `layerWritten` when the layer file changes,
    // `hyprReloaded` when Hyprland reports the reload on its event socket.
    FileView {
        path: Paths.stateDir + "/hypr/vgs.lua"
        preload: false
        watchChanges: true
        printErrors: false
        onFileChanged: if (root.themeLatency !== null && root.themeLatency.kind === "theme") root.latencyMark("layerWritten")
    }
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "configreloaded" && root.themeLatency !== null && root.themeLatency.kind === "theme") root.latencyMark("hyprReloaded");
        }
    }

    function desktopExposed() {
        return !(Plugins.built.overlay || []).some(row => row.id === "vgs.themes");
    }

    function backgroundReady(source) {
        for (const key of Object.keys(Plugins.built))
            for (const row of Plugins.built[key])
                if (row.kind === "background" && visibleInTree(row.instance)
                    && descendants(row.instance).some(child => child instanceof Image && child.status === Image.Ready && String(child.source).split("?")[0] === source)) return true;
        return false;
    }

    // Removing the browser exposes retained buffers without changing them.
    // Request a probe frame so a static desktop still has a native endpoint.
    function requestDesktopFrame() {
        const windows = [];
        for (const key of Object.keys(Plugins.built))
            for (const row of Plugins.built[key]) {
                if (["bar", "background"].indexOf(row.kind) === -1) continue;
                const window = row.instance.Window.window;
                if (window !== null && windows.indexOf(window) === -1) {
                    windows.push(window);
                    window.update();
                }
            }
    }

    function selectedCard(item) {
        const parts = browserParts(item);
        const view = parts.wallpaperView;
        return parts.cards.find(child => typeName(child) === "ThemeCard" && child.current || typeName(child) === "WallpaperCard" && view !== undefined && view.selected !== null && child.modelData.key === view.selected.key);
    }

    // CARD's picture: null when the card draws none, else whether it is
    // ready, the size it decodes at, which the carousel sets to the card's
    // drawn size in device pixels once a glide ends, and with SIZES, each
    // source file's [width, height] in pixels by path, whether it is low:
    // its file smaller than that size on both sides, so the card shows it
    // stretched. Qt scales a cropped decode up to the requested size, so
    // the decoded size cannot tell, and a gliding card is still narrower
    // than it settles. A file SIZES lacks reads as low, so an unmeasured
    // source fails.
    function cardPicture(card, sizes) {
        const path = typeName(card) === "ThemeCard" ? card.picture : card.modelData.path;
        if (typeof path !== "string" || path === "") return null;
        const image = descendants(card).find(child => child instanceof Image && visibleInTree(child) && String(child.source) !== "" && child.status === Image.Ready);
        if (image === undefined) return { ready: false, low: false };
        const drawn = [image.sourceSize.width, image.sourceSize.height];
        if (sizes === null) return { ready: true, low: false, drawn: drawn };
        const size = sizes[decodeURIComponent(String(image.source).replace(/^file:\/\//, "").split("?")[0])];
        return { ready: true, low: size === undefined || size[0] < drawn[0] && size[1] < drawn[1], drawn: drawn };
    }

    function selectedPictureReady(item) {
        const card = selectedCard(item);
        if (card === undefined || !visibleInTree(card)) return false;
        const picture = cardPicture(card, null);
        return picture === null || picture.ready;
    }

    // While a timed reading waits, the ms from its start at which the GUI
    // thread starts a frame of a window of KEY's kind (`started`, its
    // afterAnimating) and handles the frameSwapped the render thread sends
    // after the frame's swap (`swapped`), up to 24 of each. The compositor
    // paces the swap: each overlay swap blocked 31 to 35 ms in the sandbox
    // (qt.scenegraph.time.renderloop, theme-latency row on cachy,
    // 2026-10-08).
    function frameLog(key) {
        const reading = root.themeLatency;
        if (reading === null || reading.kind === "step" || reading.drawn !== undefined) return;
        if (reading.frames === undefined) reading.frames = {};
        if (reading.frames[key] === undefined) reading.frames[key] = [];
        if (reading.frames[key].length < 24) reading.frames[key].push(Date.now() - reading.started);
    }

    // A frame's reader, with the GUI-thread ms it took while its reading
    // waits added to the reading's `probeMs`, so a reading names what the
    // probe itself cost the frames it times.
    function latencyFrame(item, kind) {
        const frameTime = Date.now();
        const reading = root.themeLatency;
        const pending = reading !== null && reading.kind !== "step" && reading.drawn === undefined;
        frameLog(kind + ".swapped");
        readFrame(item, kind, frameTime);
        if (pending) reading.probeMs = (reading.probeMs || 0) + Date.now() - frameTime;
    }

    function readFrame(item, kind, frameTime) {
        // The selected picture is read for a step reading and the arming
        // checks between readings, never inside a pending timed one.
        const timed = root.themeLatency !== null && root.themeLatency.kind !== "step" && root.themeLatency.drawn === undefined;
        if (typeName(item) === "Browser" && !timed) {
            root.selectedFrameItem = item;
            root.selectedFrameReady = root.selectedPictureReady(item);
        }
        if (root.themeLatency === null || (root.themeLatency.kind !== "step" && root.themeLatency.drawn !== undefined)) return;
        const reading = root.themeLatency;
        if (reading.kind === "step") {
            if (typeName(item) !== "Browser") return;
            const card = selectedCard(item);
            if (card === undefined || !visibleInTree(card)) { reading.late = (reading.late || 0) + 1; return; }
            const key = card.modelData.name || card.modelData.path || card.modelData.key;
            if (reading.last !== key) {
                reading.steps = (reading.steps || 0) + 1;
                reading.last = key;
            }
            const picture = cardPicture(card, reading.sizes === undefined ? null : reading.sizes);
            if (picture !== null && !picture.ready) reading.late = (reading.late || 0) + 1;
            if (picture !== null && picture.ready) reading.cardSize = picture.drawn;
            if (picture !== null && picture.low) reading.low = (reading.low || 0) + 1;
            // The epoch time of the first frame drawing each selection's
            // full picture, against which the row reads its key press.
            if (reading.full === undefined) reading.full = {};
            if (picture !== null && picture.ready && !picture.low && reading.full[key] === undefined) reading.full[key] = frameTime;
            return;
        }
        if (reading.kind === "open") {
            if (typeName(item) !== "Browser") return;
            if (reading.firstFrame === undefined) reading.firstFrame = frameTime - reading.started;
            const parts = browserParts(item);
            const view = parts.themeView;
            const card = parts.cards.find(child => typeName(child) === "ThemeCard" && child.current);
            if (view === undefined || card === undefined || !visibleInTree(card) || !view.activeFocus || view.shownCards.length === 0) return;
            if (reading.focusFrame === undefined) reading.focusFrame = frameTime - reading.started;
            const waiting = reading.want === "warm" ? catalogWaiting(parts) : "";
            if (waiting !== "") {
                // Each frame whose wait differs from the last frame's:
                // [ms from the start, what the catalog waits for].
                if (reading.waits === undefined) reading.waits = [];
                if (reading.waits.length === 0 || reading.waits[reading.waits.length - 1][1] !== waiting) reading.waits.push([frameTime - reading.started, waiting]);
                return;
            }
        } else if (reading.kind === "theme") {
            // The wallpaper covers the background's window, so its frame
            // counts from the reading's start; the bar draws the theme, so
            // its frame counts once the theme has published.
            if (kind === "background" && descendants(item).some(child => child instanceof Image && child.status === Image.Ready && String(child.source).split("?")[0] === reading.background)) reading.backgroundFrame = frameTime - reading.started;
            if (Theme.name !== reading.want) return;
            if (kind === "bar") reading.barFrame = frameTime - reading.started;
            // The empty background is an explicit theme without wallpaper.
            if (reading.barFrame === undefined || (reading.background !== "" && reading.backgroundFrame === undefined)) return;
        } else if (reading.kind === "wallpaper") {
            if (kind === "background" && descendants(item).some(child => child instanceof Image && child.status === Image.Ready && String(child.source).split("?")[0] === reading.want)) reading.backgroundFrame = frameTime - reading.started;
            if (reading.backgroundFrame === undefined) return;
        }
        if (["theme", "wallpaper"].indexOf(reading.kind) !== -1) {
            if (["bar", "background"].indexOf(kind) === -1 || !desktopExposed()) return;
            const background = reading.kind === "wallpaper" ? reading.want : reading.background;
            if (background !== "" && !backgroundReady(background)) return;
        }
        root.themeLatency.drawn = frameTime - reading.started;
    }

    Variants {
        model: {
            const items = [];
            for (const key of Object.keys(Plugins.built))
                for (const row of Plugins.built[key])
                    if (row.origin === "core" && ["bar", "overlay", "background"].indexOf(row.kind) !== -1) items.push({ instance: row.instance, kind: row.kind });
            return items;
        }
        Connections {
            required property var modelData
            target: modelData.instance.Window.window
            function onFrameSwapped() { root.latencyFrame(modelData.instance, modelData.kind); }
            function onAfterAnimating() { root.frameLog(modelData.kind + ".started"); }
        }
    }
    function wallpaperWanted(image) {
        const reading = root.themeLatency;
        return reading !== null && reading.background !== "" && String(image.source).split("?")[0] === reading.background;
    }

    // When a background image takes the reading's wallpaper (`wallSet`)
    // and when its decode is ready (`wallReady`).
    Variants {
        model: {
            const images = [];
            for (const key of Object.keys(Plugins.built))
                for (const row of Plugins.built[key])
                    if (row.kind === "background")
                        for (const child of root.descendants(row.instance))
                            if (child instanceof Image) images.push({ image: child });
            return images;
        }
        Connections {
            required property var modelData
            target: modelData.image
            function onSourceChanged() { if (root.wallpaperWanted(modelData.image)) root.latencyMark("wallSet"); }
            function onStatusChanged() { if (root.wallpaperWanted(modelData.image) && modelData.image.status === Image.Ready) root.latencyMark("wallReady"); }
        }
    }
    Connections {
        target: Plugins
        function onBuiltChanged() {
            if (root.themeLatency !== null && root.themeLatency.kind === "open" && (Plugins.built.overlay || []).some(row => row.id === "vgs.themes")) root.latencyMark("built");
            if (root.themeLatency !== null && root.themeLatency.drawn === undefined && ["theme", "wallpaper"].indexOf(root.themeLatency.kind) !== -1 && root.desktopExposed()) {
                root.latencyMark("uncovered");
                root.requestDesktopFrame();
            }
        }
    }
    // ThemeSource sets the name, then the values every token binding reads,
    // then the revision, so named to published is the binding of tokens.
    Connections {
        target: Theme
        function onNameChanged() { root.latencyMark("named"); }
        function onRevisionChanged() { root.latencyMark("published"); }
    }
    Connections {
        target: Capabilities.themes
        function onJobsChanged() {
            if (root.themeLatency === null) return;
            if (root.themeLatency.kind === "theme" && root.themeLatency.jobs.some(job => job.verb === "apply") && !Capabilities.themes.jobs.some(job => job.verb === "apply")) root.latencyMark("answered");
            const now = Date.now() - root.themeLatency.started;
            root.themeLatencyJobs.forEach((job, i) => {
                const row = root.themeLatency.jobs[i];
                if (row.left === undefined && Capabilities.themes.jobs.indexOf(job) === -1) row.left = now;
            });
            for (const job of Capabilities.themes.jobs) {
                if (root.themeLatencyJobs.indexOf(job) !== -1) continue;
                root.themeLatencyJobs.push(job);
                root.themeLatency.jobs.push({ verb: job.verb, queued: now });
            }
        }
    }
    IpcHandler {
        target: "theme-latency"
        function themeLatencyBegin(kind: string, want: string, background: string): string {
            root.themeLatencyJobs = [];
            root.themeLatency = { kind: kind, want: want, background: background, started: Date.now(), jobs: [] };
            return "ok";
        }
        // Each picture file's [width, height] by path, for a step reading
        // to judge the pictures it draws by.
        function themeLatencySizes(sizes: string): string {
            if (root.themeLatency === null || root.themeLatency.kind !== "step") return "no-step";
            root.themeLatency.sizes = JSON.parse(sizes);
            return "ok";
        }
        function themeLatencyRead(): string { return JSON.stringify(Object.assign({}, root.themeLatency, { sizes: undefined })); }
        function themeCatalogReady(): string {
            const row = (Plugins.built.overlay || []).find(row => row.id === "vgs.themes");
            return row !== undefined && catalogReady(row.instance) ? "ready" : "pending";
        }
        function selectedPictureReady(): string {
            const row = (Plugins.built.overlay || []).find(row => row.id === "vgs.themes");
            return row !== undefined && root.selectedFrameItem === row.instance && root.selectedFrameReady && root.selectedPictureReady(row.instance) ? "ready" : "pending";
        }
        function readOnlyThemeJob(): string {
            const row = (Plugins.built.service || []).find(row => row.id === "vgs.themes");
            if (row === undefined) return "absent";
            row.instance.shell.theme.list(() => {});
            return "ok";
        }
        function serviceTimer(): string {
            const row = (Plugins.built.service || []).find(row => row.id === "vgs.themes");
            if (row === undefined) return "absent";
            const timer = descendants(row.instance).find(child => child.interval === 60000 && child.repeat === true && child.running === true);
            if (timer === undefined) return "absent";
            timer.triggered();
            return "ok";
        }
    }
}
