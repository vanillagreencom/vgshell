import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "BrowserLogic.js" as BrowserLogic
import "SetupLogic.js" as SetupLogic

// The themes service: one global shortcut per browser view, from the view
// table in BrowserLogic.js, each summoning the plugin's overlay on that
// view, and the Browser theming status row. It draws nothing; each
// registration's disposer is the core's, so disabling the plugin releases
// them. The row asks `vgshell theme setup --json` at start, after each plugin
// requirements scan, after each theme apply result and after each run of the
// `browser-policy` TUI, whoever opened it. It publishes
// SetupLogic.browserTheming's answer and the wired theme files; the Settings
// page offers Install browser theming, that TUI, while the browser row says
// so (D061). Settings asks for a scan each time it opens, so the row also
// reads a setup run from a terminal or a package installed while the shell
// ran.
//   shortcut vgs.themes:themes              SUPER+SHIFT+T from the manifest's
//                                            `hyprland` binds (README)
//   shortcut vgs.themes:wallpapers          SUPER+SHIFT+W, the same way
//   shortcut vgs.themes:panel               SUPER+CTRL+J from the manifest's
//                                            `hyprland` binds
//   shortcut vgs.themes:gaps                SUPER+SHIFT+BACKSPACE from the
//                                            manifest's `hyprland` binds;
//                                            the launcher's Style row runs
//                                            it too (README)
//   vgshell ipc call vgs.themes invoke gaps ''  the same toggle
// The gaps toggle flips the `noWindowGaps` setting through `configure`, so
// it holds across a restart; the Hyprland layer writes the zero gaps.
// A shortcut summons rather than toggles: the overlay's `open` closes it
// when it already shows that view and switches to the view otherwise, so a
// second view's key moves an open browser to it instead of closing it.
Item {
    id: root

    // The core assigns the plugin's scoped shell object after creation.
    property var shell: null
    // The shell this service registered with, so a settings change that
    // hands over a new object registers nothing twice.
    property var registeredWith: null

    // The end of the browser-policy TUI's last run: each new end asks the
    // setup report again.
    readonly property var policyEnd: shell === null || !shell.tui.state["browser-policy"] ? null : shell.tui.state["browser-policy"].endedAt
    readonly property int requirementsRevision: shell === null ? -1 : shell.requirements.revision

    onShellChanged: {
        if (shell === null || registeredWith !== null) return;
        registeredWith = shell;
        for (const view of BrowserLogic.VIEWS)
            shell.shortcut.register(view.name, view.description, () => root.summon(view.name));
        shell.shortcut.register("panel", "Themes panel", () => root.togglePanel());
        shell.shortcut.register("gaps", "Window gaps on or off", () => root.toggleGaps());
        shell.ipc.handle("gaps", () => root.toggleGaps());
        shell.ipc.handle("browser-data", revision => revision === String(root.dataRevision) ? "" : root.dataText);
        shell.ipc.handle("refresh-browser-data", () => { root.refreshData(); return "ok"; });
        refreshData();
        checkSetup();
    }
    onPolicyEndChanged: if (registeredWith !== null) checkSetup()
    onRequirementsRevisionChanged: if (registeredWith !== null) checkSetup()

    // One retained answer per source. Opening a view reads these through
    // the plugin's existing IPC capability and starts no runner command.
    property var catalog: ({ entries: null, reason: null })
    property var images: ({ images: null, reason: null })
    property string listReason: ""
    property int dataRevision: 0
    property var generations: ({})
    readonly property var listing: shell === null ? null : shell.theme.listing
    readonly property var themeLast: shell === null ? null : shell.theme.last
    // The runner replaces last for every apply result, an equal one too.
    // Setup follows apply state. The browser snapshot has no apply state:
    // those notifications only copy it and make open views parse it again.
    readonly property string themeLastText: JSON.stringify(themeLast)
    onThemeLastTextChanged: {
        if (registeredWith !== null) checkSetup();
    }
    property var cards: []
    property var cardKeys: ({})
    property int cardSerial: 0
    readonly property var rawCards: listing === null ? [] : BrowserLogic.cards(listing.packages, catalog.entries, images.images, "")
    onRawCardsChanged: {
        const keys = {};
        const next = rawCards.map(card => {
            const signature = BrowserLogic.cardKey(card);
            const previous = cardKeys[card.name];
            const key = previous !== undefined && previous.signature === signature ? previous.key : ++cardSerial;
            keys[card.name] = { signature: signature, key: key };
            return Object.assign({ contentKey: card.name + ":" + key }, card);
        });
        cardKeys = keys;
        if (JSON.stringify(next) !== JSON.stringify(cards)) cards = next;
    }
    onCardsChanged: dataRevision++
    // Tokens and terminal colours already live in the precomputed cards.
    // Panel and wallpaper clients need only the catalog's row metadata.
    readonly property var catalogRows: catalog.entries === null ? null : catalog.entries.map(entry => {
        const row = Object.assign({}, entry);
        delete row.tokens;
        delete row.terminal;
        return row;
    })
    readonly property string dataText: JSON.stringify({ revision: dataRevision,
        listReason: listReason, catalog: { entries: catalogRows, reason: catalog.reason }, cards: cards, images: images, generations: generations })
    onListingChanged: dataRevision++
    property bool readingData: false
    property bool dataPending: false
    readonly property var download: shell === null ? null : shell.theme.last.downloading
    property string downloadName: ""
    property bool sawDownload: false
    onDownloadChanged: {
        if (sawDownload && download === null) refreshData(downloadName);
        if (download !== null) downloadName = download.name;
        sawDownload = download !== null;
    }

    function refreshData(replacedImages) {
        if (registeredWith === null) return;
        if (typeof replacedImages === "string") {
            const next = Object.assign({}, generations);
            next[replacedImages] = (next[replacedImages] || 0) + 1;
            generations = next;
            dataRevision++;
        }
        if (readingData) { dataPending = true; return; }
        readingData = true;
        let waiting = 3;
        const answered = () => {
            waiting--;
            dataRevision++;
            if (waiting !== 0) return;
            readingData = false;
            if (dataPending) { dataPending = false; refreshData(); }
        };
        shell.theme.list(result => { root.listReason = result.reason === null ? "" : result.reason; answered(); });
        shell.theme.images("all", result => {
            const next = { images: result.state === "ok" ? result.images : root.images.images, reason: result.reason };
            if (JSON.stringify(next) !== JSON.stringify(root.images)) root.images = next;
            answered();
        });
        shell.theme.catalog(result => {
            const next = { entries: result.reason === null ? result.entries : root.catalog.entries, reason: result.reason };
            if (JSON.stringify(next) !== JSON.stringify(root.catalog)) root.catalog = next;
            answered();
        });
    }

    Timer {
        interval: BrowserLogic.CATALOG_REFRESH_MS
        running: root.registeredWith !== null
        repeat: true
        onTriggered: root.refreshData()
    }

    Connections {
        target: Theme
        function onDocumentRevisionChanged() { root.refreshData(); }
    }

    // QFileSystemWatcher observes directory renames as well as removal.
    // These views watch paths only; no directory is read as file content.
    FileView {
        path: Paths.configDir + "/themes"
        preload: false
        watchChanges: true
        printErrors: false
        onFileChanged: root.refreshData()
    }
    FileView {
        path: Quickshell.shellDir + "/../themes/catalog/index.json"
        preload: false
        watchChanges: true
        printErrors: false
        onFileChanged: root.refreshData()
    }
    Variants {
        model: root.listing === null ? [] : root.listing.packages.filter(p => p.state === "ok")
        FileView {
            required property var modelData
            path: modelData.path + "/theme.json"
            preload: false
            watchChanges: true
            printErrors: false
            onFileChanged: root.refreshData(modelData.name)
        }
    }
    Variants {
        model: root.listing === null ? [] : root.listing.packages.filter(p => p.state === "ok")
        FileView {
            required property var modelData
            path: modelData.path + "/backgrounds"
            preload: false
            watchChanges: true
            printErrors: false
            onFileChanged: root.refreshData(modelData.name)
        }
    }

    Variants {
        model: root.images.images === null ? [] : root.images.images
        FileView {
            required property var modelData
            path: modelData.path
            preload: false
            watchChanges: true
            printErrors: false
            onFileChanged: root.refreshData(modelData.theme || "")
        }
    }

    // Ask `vgshell theme setup --json` again; one asked while it runs runs
    // once it ends.
    property bool setupPending: false
    function checkSetup() {
        if (setupReport.running) { setupPending = true; return; }
        setupReport.running = true;
    }

    Process {
        id: setupReport
        command: [Quickshell.shellDir + "/../bin/vgshell", "theme", "setup", "--json"]
        stdout: StdioCollector { id: setupOut }
        stderr: StdioCollector { id: setupErr }
        // The exit code, or null while the process has not exited, as one
        // that never started has not.
        property var exitCode: null
        onExited: code => { exitCode = code; }
        onRunningChanged: {
            if (running) return;
            const code = exitCode;
            const value = SetupLogic.browserTheming(setupOut.text, code);
            exitCode = null;
            if (value.tone === "danger") {
                const why = setupErr.text.split("\n")[0];
                console.warn("themes: setup=unknown " + value.text + (why === "" ? "" : " stderr=" + JSON.stringify(why)));
            }
            if (root.shell !== null) {
                const reply = root.shell.status.set("browserTheming", value);
                if (reply !== "ok") console.error("themes: " + reply);
                const items = SetupLogic.wiring(setupOut.text, code);
                if (items !== null) {
                    const wiringReply = root.shell.status.set("themeWiring", items);
                    if (wiringReply !== "ok") console.error("themes: " + wiringReply);
                }
            }
            if (root.setupPending) {
                root.setupPending = false;
                running = true;
            }
        }
    }

    // The overlay host's reply: `ok`, or its refusal.
    function summon(view) {
        const reply = shell.surfaces.summon("overlay", JSON.stringify({ view: view }));
        if (reply !== "ok") console.warn("themes: summon " + view + " " + reply);
        return reply;
    }

    // The configure capability's reply: `ok`, or its refusal.
    function toggleGaps() {
        const reply = shell.configure.set("noWindowGaps", shell.settings.noWindowGaps !== true);
        if (reply !== "ok") console.warn("themes: gaps " + reply);
        return reply;
    }

    function togglePanel() {
        const reply = shell.surfaces.toggle("panel", "{}");
        if (reply !== "ok") console.warn("themes: panel " + reply);
        return reply;
    }
}
