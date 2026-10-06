import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
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
    function descendants(item) {
        const all = [item];
        for (let i = 0; i < all.length; i++) {
            const children = Array.from(all[i].children || []).concat(Array.from(all[i].data || []));
            for (const child of children)
                if (typeof child === "object" && child !== null && all.indexOf(child) === -1) all.push(child);
        }
        return all;
    }
    function visibleInTree(item) {
        for (let at = item; at !== null && at !== undefined; at = at.parent)
            if (at.visible === false) return false;
        return true;
    }

    function catalogReady(item) {
        const children = descendants(item);
        const view = children.find(child => typeName(child) === "ThemeView");
        if (view === undefined || view.entries === null || view.packages === null) return false;
        const names = {};
        for (const row of view.packages) if (row.state !== "shadowed") names[row.name] = true;
        for (const row of view.entries) names[row.name] = true;
        if (view.shownCards.length !== Object.keys(names).length) return false;
        for (const card of children.filter(child => typeName(child) === "ThemeCard" && visibleInTree(child))) {
            if (card.picture === "") continue;
            const shown = descendants(card).filter(child => child instanceof Image && visibleInTree(child) && String(child.source) !== "");
            if (!shown.some(image => image.status === Image.Ready)) return false;
        }
        return true;
    }

    function latencyMark(stage) {
        if (themeLatency !== null && themeLatency[stage] === undefined)
            themeLatency[stage] = Date.now() - themeLatency.started;
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
        const children = descendants(item);
        const view = children.find(child => typeName(child) === "WallpaperView");
        return children.find(child => typeName(child) === "ThemeCard" && child.current || typeName(child) === "WallpaperCard" && view !== undefined && view.selected !== null && child.modelData.key === view.selected.key);
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

    function latencyFrame(item, kind) {
        const frameTime = Date.now();
        if (typeName(item) === "Browser") {
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
            const view = descendants(item).find(child => typeName(child) === "ThemeView");
            const card = descendants(item).find(child => typeName(child) === "ThemeCard" && child.current);
            if (view === undefined || card === undefined || !visibleInTree(card) || !view.activeFocus || view.shownCards.length === 0) return;
            if (reading.want === "warm" && !catalogReady(item)) return;
        } else if (reading.kind === "theme") {
            if (Theme.name !== reading.want) return;
            if (kind === "bar") reading.barFrame = frameTime - reading.started;
            if (kind === "background" && descendants(item).some(child => child instanceof Image && child.status === Image.Ready && String(child.source).split("?")[0] === reading.background)) reading.backgroundFrame = frameTime - reading.started;
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
    Connections {
        target: Theme
        function onRevisionChanged() { root.latencyMark("published"); }
    }
    Connections {
        target: Capabilities.themes
        function onJobsChanged() {
            if (root.themeLatency === null) return;
            if (root.themeLatency.kind === "theme" && root.themeLatency.jobs.some(job => job.verb === "apply") && !Capabilities.themes.jobs.some(job => job.verb === "apply")) root.latencyMark("answered");
            for (const job of Capabilities.themes.jobs) {
                if (root.themeLatencyJobs.indexOf(job) !== -1) continue;
                root.themeLatencyJobs.push(job);
                root.themeLatency.jobs.push({ verb: job.verb, queued: Date.now() - root.themeLatency.started });
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
