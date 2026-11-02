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
// SetupLogic.browserTheming's answer and the wired theme files; the Details
// tab offers Install browser theming, that TUI, while the browser row says
// so (D061). Settings asks for a scan each time it opens, so the row also
// reads a setup run from a terminal or a package installed while the shell
// ran. The theme browser closes on the publish of an apply it ran, before
// the answer, and hands the answer here through `report-apply`; the next
// apply result, as the queue runs one job at a time, is that apply's, and a
// failure or a partial apply becomes one notice. The browsers' data, the
// theme list, every image and the catalog, is read once at registration,
// when a browser view opens and on a view's own request; a watched source
// change and an apply read it again only while a view is open, since the
// next view to open reads it then. Nothing reads it on a timer. One
// helper process, helper/watch.py, watches every source with one inotify
// instance while the service is registered.
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
        shell.ipc.handle("open-browser-view", key => { root.openView(key); return "ok"; });
        shell.ipc.handle("close-browser-view", key => { root.closeView(key); return "ok"; });
        shell.ipc.handle("refresh-browser-data", () => { Qt.callLater(root.readData); return "ok"; });
        shell.ipc.handle("report-apply", name => { root.reported = name; return "ok"; });
        // The first view to open draws the retained answer at once, its
        // pictures and catalog rows included, rather than waiting on a read.
        Qt.callLater(root.readData);
        watch.running = true;
        checkSetup();
    }
    onPolicyEndChanged: if (registeredWith !== null) checkSetup()
    onRequirementsRevisionChanged: if (registeredWith !== null) checkSetup()

    // One retained answer per source. A view reads these through the
    // plugin's existing IPC capability, and its opening asks for one new
    // read through `open-browser-view`.
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
    readonly property var applyResult: themeLast === null ? null : themeLast.result
    // The package of the apply the browser handed over, "" when none waits.
    // The hand-over comes while that apply runs, and the result current
    // then does not change applyResult again, so the next change is its
    // answer.
    property string reported: ""
    onApplyResultChanged: {
        if (reported === "") return;
        const notice = BrowserLogic.applyNotice(reported, applyResult, listing === null ? null : listing.packages);
        reported = "";
        if (notice === null) return;
        const reply = shell.notify.send(notice);
        if (reply !== "ok") console.error("themes: notice " + reply);
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

    // One change can print several watch lines, one per kernel read the
    // helper makes, such as a file's creation and its finished write, and
    // one line can name a list change and packages at once. A call
    // Qt.callLater already queued and not yet run takes no second place
    // (qtdeclarative 6.12 qqmldelayedcallqueue.cpp addUniqueCall, keyed by
    // object and method), so the lines of one turn cost one read, and the
    // queue skips the call once this service is deleted or queued for
    // deletion. With no view open a change only marks a package's images
    // replaced, so the next view loads them anew, and reads nothing: that
    // view's opening reads.
    function refreshData(replacedImages) {
        if (registeredWith === null) return;
        if (typeof replacedImages === "string") {
            const next = Object.assign({}, generations);
            next[replacedImages] = (next[replacedImages] || 0) + 1;
            generations = next;
            dataRevision++;
        }
        if (Object.keys(openViews).length > 0) Qt.callLater(root.readData);
    }

    // The browser views open now, keyed by each view's own key: the theme
    // view, the wallpaper view and the Themes panel each hold a
    // BrowserData, which opens here once it starts and closes on its
    // destruction, and the summon host destroys a view's surface once it
    // is hidden (shell/Hosts/SummonHost.qml). A key closes only its own
    // entry, so a view torn down after another opened leaves the new one
    // open: a view switch in the overlay's Loader builds the new view before
    // the old one's deferred deletion (QQuickLoaderPrivate::clear calls
    // deleteLater, qtdeclarative src/quick/items/qquickloader.cpp).
    property var openViews: ({})
    function openView(key) {
        const next = Object.assign({}, openViews);
        next[key] = true;
        openViews = next;
        Qt.callLater(root.readData);
    }
    function closeView(key) {
        if (!Object.prototype.hasOwnProperty.call(openViews, key)) return;
        const next = Object.assign({}, openViews);
        delete next[key];
        openViews = next;
    }

    function readData() {
        if (readingData) { dataPending = true; return; }
        readingData = true;
        let waiting = 3;
        const answered = () => {
            waiting--;
            dataRevision++;
            if (waiting !== 0) return;
            readingData = false;
            if (dataPending) { dataPending = false; readData(); }
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

    // The after-apply read: every apply that lands writes the shell's theme
    // file last (docs/architecture/themes.md § Applying), and a read queued
    // behind a running apply waits for it in ThemeRunner.enqueue, so the
    // round reads the applied state. An apply result adds no second read.
    Connections {
        target: Theme
        function onDocumentRevisionChanged() { root.refreshData(); }
    }

    // Every source the reads list is watched by one helper,
    // helper/watch.py, whose header states what it watches and prints: the
    // config folder, where a shell.json save and an apply's theme file
    // land; the installed packages, each package folder, refused ones
    // included, and its backgrounds; the user images folder; and the
    // catalog index. It holds one inotify instance of directory watches
    // however many packages and images there are; a FileView per path
    // would hold one each (Quickshell 0.3.1 src/io/fileview.cpp
    // updateWatchedFiles makes one QFileSystemWatcher per FileView, and
    // each opens its own inotify instance). The shipped themes change only
    // with a VGS update, which needs a restart, so none is watched. A list
    // line asks for a read; a name marks that package's images replaced,
    // "" the user images', and asks for a read. The ready line asks for
    // nothing, as registration already did.
    function watchLine(line) {
        const change = JSON.parse(line);
        if (change.ready === true) return;
        if (change.list) refreshData();
        for (const name of change.names) refreshData(name);
    }

    // The helper runs while the service is registered: registration starts
    // it, and the engine ends it with the service (Quickshell 0.3.1
    // src/io/process.cpp ~Process kills a running process and emits
    // nothing). It exits on its own when a folder it must watch cannot be
    // watched, at start or at a later reconcile, and a failed start or an
    // exit loses changes. Each is logged, an exit with the helper's last
    // stderr line, its `watch.py: watch=failed ...` line on a setup
    // failure, and starts the helper again from the running change, the
    // reference's restart pattern
    // (https://quickshell.org/docs/v0.3.1/types/Quickshell.Io/Process,
    // running), at most watchRestartLimit times per registration, so a
    // helper that cannot run stops after that many tries. A running change
    // follows exited and the drained stderr collector (process.cpp
    // onFinished), and a failed start emits only the running change, so its
    // completion stays null.
    readonly property int watchRestartLimit: 3
    property int watchRestarts: 0
    Process {
        id: watch
        command: ["python3", decodeURIComponent(String(Qt.resolvedUrl("helper/watch.py")).replace(/^file:\/\//, "")),
            Paths.configDir, Quickshell.shellDir + "/../themes/catalog"]
        stdout: SplitParser { onRead: line => root.watchLine(line) }
        stderr: StdioCollector { id: watchErrors }
        property var completion: null
        onExited: (code, status) => { completion = { code: code, status: status }; }
        onRunningChanged: {
            if (running) return;
            const lines = watchErrors.text.trim().split("\n");
            const ended = completion === null ? "exit=not-started"
                : "exit=" + completion.code + " status=" + completion.status + " stderr=" + JSON.stringify(lines[lines.length - 1]);
            completion = null;
            if (root.watchRestarts >= root.watchRestartLimit) {
                console.error("themes: watch=stopped " + ended + " restarts=" + root.watchRestarts);
                return;
            }
            root.watchRestarts++;
            console.error("themes: watch=ended " + ended + " restart=" + root.watchRestarts + "/" + root.watchRestartLimit);
            running = true;
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
            if (value.text === SetupLogic.UNKNOWN_TEXT) {
                const why = setupErr.text.split("\n")[0];
                console.warn("themes: setup=unknown " + value.text + (why === "" ? "" : " stderr=" + JSON.stringify(why)));
            }
            if (root.shell !== null) {
                const reply = root.shell.status.set("browserTheming", value);
                if (!root.shell.status.isOk(reply)) console.error("themes: " + reply);
                const items = SetupLogic.wiring(setupOut.text, code);
                if (items !== null) {
                    const wiringReply = root.shell.status.set("themeWiring", items);
                    if (!root.shell.status.isOk(wiringReply)) console.error("themes: " + wiringReply);
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
