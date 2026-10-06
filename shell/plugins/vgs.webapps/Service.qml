import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "WebApps.js" as WebApps

// The web apps' one owner. It keeps one desktop entry per app of the
// `apps` setting in the user's applications directory, which the launcher
// lists as it lists every installed application, with the site's icon
// under the configuration directory, and removes every entry and icon of
// an app the list no longer holds, at its start too. An entry runs
// `vgshell ipc call vgs.webapps invoke open <name>`: the service focuses
// the app's window when one is open and opens the site in its own window
// of a Chromium-family browser when none is.
//
// One step runs at a time on one Process: the saved records at start, a
// page read, an icon read, then one write of every entry. A change of the
// list while a step runs is taken up when it ends. A site's title and icon
// are read once per address and icon choice and kept beside the icon, so
// a start reads no site again. A read that fails leaves the app with the
// host as its name and the default icon, and is tried again at the next
// start or change of that app.
Item {
    id: root

    property var shell: null

    // How long a launch may take to map its window before a second open
    // launches again: a browser cold start on a loaded machine takes a few
    // seconds.
    readonly property int launchMs: 15000

    readonly property var items: shell === null ? [] : shell.settings.apps
    readonly property string home: Quickshell.env("HOME")
    readonly property string appsDir: (Quickshell.env("XDG_DATA_HOME") || (home + "/.local/share")) + "/applications"
    readonly property string iconsDir: Paths.configDir + "/webapps/icons"
    readonly property string vgshell: Quickshell.shellDir.replace(/\/+$/, "").replace(/\/[^\/]+$/, "") + "/bin/vgshell"
    readonly property string script: decodeURIComponent(String(Qt.resolvedUrl("files.sh")).replace(/^file:\/\//, ""))
    readonly property string fallbackIcon: decodeURIComponent(String(Qt.resolvedUrl("fallback.svg")).replace(/^file:\/\//, ""))

    // App name -> { url, iconSource, title, icon, iconFrom, page }: what the
    // last read for it gave. `page` is `read`, `failed` or `skipped`, the
    // last when both Name and Icon were the user's own; `iconFrom` is
    // `site`, `chosen`, `default` for a site that gave none, `refused` for
    // a chosen icon that is no image, or `unsaved`.
    property var records: ({})
    // Names read in this run, so a failed read is not retried in a loop.
    property var readNow: ({})
    property bool started: false
    property bool loaded: false
    property bool wanted: false
    // The step on the Process: { kind: "read" | "page" | "icon" | "apply",
    // app }, or null.
    property var step: null
    // The page read for the app on the icon step, or null.
    property var pageRead: null
    // The browser the last look found: { id, name, command } or null.
    property var browser: null
    // Names waiting for a browser look to open.
    property var opening: []
    // App name -> the time its launch stops holding back another.
    property var launching: ({})
    readonly property var childEnvironment: ({
        PATH: Quickshell.env("PATH"), HOME: home, LANG: "C.UTF-8",
        XDG_CONFIG_HOME: Quickshell.env("XDG_CONFIG_HOME") || "", XDG_DATA_HOME: Quickshell.env("XDG_DATA_HOME") || "",
        XDG_CONFIG_DIRS: Quickshell.env("XDG_CONFIG_DIRS") || "", XDG_DATA_DIRS: Quickshell.env("XDG_DATA_DIRS") || "",
        XDG_CURRENT_DESKTOP: Quickshell.env("XDG_CURRENT_DESKTOP") || "",
        http_proxy: Quickshell.env("http_proxy") || "", https_proxy: Quickshell.env("https_proxy") || "",
        no_proxy: Quickshell.env("no_proxy") || ""
    })

    onShellChanged: if (shell !== null && !started) Qt.callLater(begin)
    onItemsChanged: reconcile()

    function begin() {
        if (started || shell === null) return;
        started = true;
        shell.ipc.handle("open", name => root.open(String(name)));
        lookForBrowser();
        run({ kind: "read" }, ["read", iconsDir]);
    }

    function run(next, args) {
        step = next;
        worker.command = ["bash", script].concat(args);
        worker.running = true;
    }

    // Start the next step the list needs, if none runs.
    function reconcile() {
        wanted = true;
        if (!loaded || worker.running) return;
        wanted = false;
        const split = current();
        const app = split.good.find(app => needsRead(app));
        if (app !== undefined) {
            readNow = Object.assign({}, readNow, { [app.name]: true });
            pageRead = null;
            if (app.title === "" || app.icon === "") {
                run({ kind: "page", app: app }, ["page", app.url.href]);
                return;
            }
            readIcon(app, false);
            return;
        }
        const words = [];
        const applied = { good: split.good, bad: split.bad };
        for (const good of applied.good) {
            const record = records[good.name];
            const text = WebApps.desktopEntry(good, good.title || record.title, record.icon, vgshell);
            words.push(good.name, text, JSON.stringify(record));
        }
        run({ kind: "apply", applied: applied }, ["apply", appsDir, iconsDir].concat(words));
    }

    // The list's apps, read from the setting each time: a handler of
    // `items` may run before a binding on it holds the new list
    // (docs/architecture/runtime-qml.md).
    function current() {
        return WebApps.apps(shell === null ? [] : shell.settings.apps);
    }

    function needsRead(app) {
        const record = records[app.name];
        if (record === undefined || record.url !== app.url.href || record.iconSource !== app.icon) return true;
        if (record.page === "failed") return readNow[app.name] !== true;
        return app.title === "" && record.page !== "read";
    }

    // PAGE_ASKED: whether a page step ran for this read.
    function readIcon(app, pageAsked) {
        const sources = app.icon !== "" ? WebApps.iconSources(app.icon, home) : (pageRead === null ? [WebApps.resolve(app.url, "/favicon.ico")] : pageRead.icons);
        run({ kind: "icon", app: app, sources: sources, pageAsked: pageAsked }, ["icon", iconsDir + "/" + app.name].concat(sources, [fallbackIcon]));
    }

    function finished(code) {
        const done = step;
        step = null;
        const text = output.text;
        switch (done.kind) {
        case "read":
            if (code !== 0) console.warn("webapps: read=failed exit=" + code);
            records = code === 0 ? readRecords(text) : {};
            loaded = true;
            break;
        case "page":
            pageRead = code === 0 ? readPage(text, done.app.url) : null;
            if (code !== 0) console.warn("webapps: page=failed app=" + done.app.name);
            readIcon(done.app, true);
            return;
        case "icon":
            keepIcon(done, code, text);
            break;
        case "apply": {
            if (code !== 0) console.warn("webapps: apply=failed exit=" + code);
            // A name the list no longer holds goes with its files, and Add
            // gives the next app the lowest free name again.
            const kept = {};
            for (const app of done.applied.good)
                if (records[app.name] !== undefined) kept[app.name] = records[app.name];
            records = kept;
            publishApps(done.applied, code);
            break;
        }
        default:
            throw new Error("webapps: step=" + done.kind + " unknown");
        }
        if (wanted || done.kind !== "apply") reconcile();
    }

    // The page step's answer: the address the page came from after any
    // redirect, one line, then the page, whose links read against it.
    function readPage(text, url) {
        const at = text.indexOf("\n");
        const landed = WebApps.parseUrl(at === -1 ? "" : text.slice(0, at));
        return WebApps.page(at === -1 ? "" : text.slice(at + 1), landed.ok ? landed : url);
    }

    // The records the read step printed whose icon file is still there.
    function readRecords(text) {
        const files = {};
        const read = {};
        for (const line of text.split("\n")) {
            const parts = line.split("\t");
            if (parts[0] === "file") files[parts[1]] = true;
            else if (parts[0] === "record" && parts.length === 3) {
                try { read[parts[1]] = JSON.parse(parts[2]); } catch (error) { console.warn("webapps: record=unreadable app=" + parts[1]); }
            }
        }
        const kept = {};
        for (const name in read) {
            const record = read[name];
            if (record !== null && typeof record === "object" && typeof record.icon === "string" && files[record.icon.slice(record.icon.lastIndexOf("/") + 1)] === true)
                kept[name] = record;
        }
        return kept;
    }

    function keepIcon(done, code, text) {
        const app = done.app;
        const answer = text.trim().split("\t");
        const index = code === 0 && answer.length === 2 ? parseInt(answer[0], 10) : -1;
        if (index < 0) console.warn("webapps: icon=failed app=" + app.name + " exit=" + code);
        const fallback = index === done.sources.length;
        records = Object.assign({}, records, { [app.name]: {
            url: app.url.href,
            iconSource: app.icon,
            title: pageRead === null ? "" : pageRead.title,
            icon: index < 0 ? fallbackIcon : answer[1],
            iconFrom: index < 0 ? "unsaved" : !fallback ? (app.icon === "" ? "site" : "chosen") : (app.icon === "" ? "default" : "refused"),
            page: pageRead !== null ? "read" : done.pageAsked ? "failed" : "skipped"
        } });
        pageRead = null;
    }

    // What the status says of an app's icon, after "Ready.".
    readonly property var iconNotes: ({
        site: "",
        chosen: "",
        default: " The site gave no icon, so it uses the default icon.",
        refused: " The icon you chose is not an image, so it uses the default icon. Give the full path or the web address of an image.",
        unsaved: " Its icon could not be saved, so it uses the default icon."
    })

    // The apps state of APPLIED, the list the last write held, which
    // CODE, the write's exit, says reached the launcher or not.
    function publishApps(applied, code) {
        if (code !== 0) {
            const failed = shell.status.set("apps", { tone: "warning", text: "Web apps could not be added to the launcher." });
            if (failed !== "ok") console.warn("webapps: status=apps " + failed);
            return;
        }
        const lines = [];
        for (const app of applied.good) {
            const record = records[app.name];
            const name = app.title || record.title || app.url.host;
            lines.push(name + ": Ready." + (iconNotes[record.iconFrom] || ""));
        }
        for (const bad of applied.bad)
            lines.push("Web app " + bad.name + ": Enter a web address that starts with https://.");
        const count = applied.good.length;
        const value = lines.length === 0
            ? { tone: "info", text: "No web apps. Add one under Web apps." }
            : { tone: applied.bad.length > 0 ? "warning" : "ok", text: count === 1 ? "1 web app is ready." : count + " web apps are ready.", lines: lines };
        const reply = shell.status.set("apps", value);
        if (reply !== "ok") console.warn("webapps: status=apps " + reply);
    }

    function lookForBrowser() {
        if (!looker.running) looker.running = true;
    }

    // The browser that opens a web app: the default one when it is of the
    // Chromium family, else the first such browser installed, else null.
    function chooseBrowser(answer) {
        const id = WebApps.entryId(answer);
        const preferred = id === "" ? null : DesktopEntries.byId(id);
        if (preferred !== null && WebApps.isChromium(id, preferred.command))
            return { id: id, name: preferred.name, command: Array.from(preferred.command) };
        // Only a browser's own entry: a site shortcut a browser makes is
        // no web browser.
        const others = DesktopEntries.applications.values
            .filter(entry => entry.categories.indexOf("WebBrowser") !== -1 && WebApps.isChromium(entry.id, entry.command))
            .sort((a, b) => a.id < b.id ? -1 : a.id > b.id ? 1 : 0);
        return others.length === 0 ? null : { id: others[0].id, name: others[0].name, command: Array.from(others[0].command) };
    }

    function browserFound(answer) {
        browser = chooseBrowser(answer);
        const value = browser === null
            ? { tone: "warning", text: "No browser here opens a site in its own window. Install Chromium, Google Chrome, Brave, Vivaldi or Microsoft Edge." }
            : { tone: "ok", text: browser.name };
        const reply = shell.status.set("browser", value);
        if (reply !== "ok") console.warn("webapps: status=browser " + reply);
        const waiting = opening;
        opening = [];
        for (const name of waiting) launch(name);
    }

    // The address of an open window of APP among CLIENTS, Hyprland's
    // `j/clients` reply, "0x…", or "".
    function windowOf(clients, app) {
        const found = clients.find(client => WebApps.classMatches(client["class"], app.url));
        return found === undefined ? "" : String(found.address);
    }

    // The IPC `open`: the app's window brought into view, or the site
    // opened once a browser look ends. The windows come from Hyprland's
    // reply: Quickshell's Hyprland.toplevels can keep a closed window
    // (docs/architecture/runtime-hyprland-pads.md § Events).
    function open(name) {
        if (current().good.find(app => app.name === name) === undefined) return "refused: app=" + name + " reason=unknown";
        shell.compositor.readWindows(state => root.windowsRead(name, state));
        return "ok";
    }

    // A launch that has not mapped its window yet holds back another.
    function windowsRead(name, state) {
        const app = current().good.find(app => app.name === name);
        if (app === undefined) return;
        if (!state.ok) {
            console.error("webapps: open=" + name + " " + state.error);
            return;
        }
        const address = windowOf(state.clients, app);
        if (address !== "") {
            const next = Object.assign({}, launching);
            delete next[name];
            launching = next;
            const reply = shell.compositor.reveal([address], false);
            if (reply !== "ok") console.warn("webapps: open=" + name + " " + reply);
            return;
        }
        if (launching[name] !== undefined && launching[name] > Date.now()) return;
        if (opening.indexOf(name) === -1) opening = opening.concat([name]);
        lookForBrowser();
    }

    function launch(name) {
        const app = current().good.find(app => app.name === name);
        if (app === undefined) return;
        if (browser === null) {
            shell.toasts.show({
                title: "Web app did not open",
                message: "No browser here opens a site in its own window. Install Chromium, Google Chrome, Brave, Vivaldi or Microsoft Edge.",
                tone: "warning"
            });
            return;
        }
        const reply = shell.run.detached(WebApps.browserArgv(browser.command, app.url.href));
        if (reply !== "ok") {
            console.warn("webapps: launch=" + name + " " + reply);
            return;
        }
        launching = Object.assign({}, launching, { [name]: Date.now() + launchMs });
    }

    Process {
        id: worker
        clearEnvironment: true
        environment: root.childEnvironment
        property int code: -1
        stdout: StdioCollector { id: output }
        stderr: SplitParser { onRead: line => console.warn(line) }
        onExited: (exitCode, exitStatus) => code = exitStatus === 0 ? exitCode : -1
        onRunningChanged: {
            if (running) return;
            const ended = code;
            code = -1;
            root.finished(ended);
        }
    }

    // A browser installed or removed while the shell runs changes the one
    // a web app opens in.
    Connections {
        target: DesktopEntries.applications
        function onValuesChanged() { root.lookForBrowser(); }
    }

    // The default browser, from xdg-mime: the desktop file that opens
    // https addresses, read again before each launch so a change of
    // default reaches the next one.
    Process {
        id: looker
        clearEnvironment: true
        environment: root.childEnvironment
        command: ["xdg-mime", "query", "default", "x-scheme-handler/https"]
        stdout: StdioCollector { id: lookerOutput }
        onRunningChanged: if (!running) root.browserFound(lookerOutput.text)
    }
}
