import QtQuick
import Qt.labs.folderlistmodel
import Quickshell.Io
import "SysmonLogic.js" as Logic

// The service owns discovery, reads and the NVIDIA child. Views hold leases.
Item {
    id: root
    property var shell: null
    property bool registered: false
    property var leases: ({})
    readonly property int leaseCount: Object.keys(leases).length
    readonly property bool polling: poller.running
    property bool discovered: false
    property var devices: []
    property string cpuTemperaturePath: ""
    property var previousCpu: null
    property var readings: ({ cpu: {}, memory: {}, gpu: null })
    property bool cycleBusy: false
    property var cycle: null
    property var jobs: []
    property var readingJob: null
    property int generation: 0
    property var query: null
    property bool queryEnding: false
    property var gpuResult: null
    readonly property string chosenGpu: shell === null ? "" : shell.settings.gpu
    readonly property bool nvidiaPresent: shell !== null && shell.requirements.missing.indexOf("nvidia-smi") === -1

    function read(path, done) {
        jobs.push({ path: path, done: done });
        if (readingJob === null) Qt.callLater(nextRead);
    }
    function nextRead() {
        if (readingJob !== null || jobs.length === 0) return;
        readingJob = jobs.shift();
        if (readingJob.path === "") { readFinished(""); return; }
        file.path = readingJob.path;
    }
    function readFinished(text) {
        const job = readingJob;
        readingJob = null;
        file.path = "";
        if (job !== null) job.done(text);
        // FileView holds its active load during loaded(); a later turn can
        // start another load. https://quickshell.org/docs/v0.3.1/types/Quickshell.Io/FileView
        Qt.callLater(nextRead);
    }
    FileView {
        id: file
        printErrors: false
        onLoaded: root.readFinished(text())
        onLoadFailed: root.readFinished("")
    }
    Component {
        id: directory
        FolderListModel {
            property var finish
            property var matcher
            showDotAndDotDot: false
            // FolderListModel's nameFilters do not filter directories.
            // https://doc.qt.io/qt-6/qml-qt-labs-folderlistmodel-folderlistmodel.html
            onStatusChanged: {
                if (status !== FolderListModel.Ready) return;
                const paths = [];
                for (let i = 0; i < count; i++) if (matcher.test(get(i, "fileName"))) paths.push(get(i, "filePath"));
                const done = finish;
                finish = null;
                if (done !== null) done(paths);
                destroy();
            }
        }
    }
    function list(path, matcher, done) {
        directory.createObject(root, { folder: "file://" + path, matcher: matcher, finish: done });
    }
    function each(paths, visit, done) {
        let pending = paths.length;
        if (pending === 0) { done(); return; }
        paths.forEach(path => visit(path, () => { if (--pending === 0) done(); }));
    }
    function discover() {
        const hwmon = [], thermal = [], cards = [];
        let pending = 3;
        function finish() {
            if (--pending !== 0) return;
            cpuTemperaturePath = Logic.chooseCpuTemperature(hwmon, thermal) || "";
            devices = Logic.orderGpus(cards);
            publishChoices();
            if (!nvidiaPresent && devices.some(card => card.driver === "nvidia")) shell.requirements.offer(["nvidia-smi"]);
            shell.status.set("graphics", { text: devices.length ? "Available" : "No supported graphics card found.", tone: devices.length ? "ok" : "info" });
            discovered = true;
            if (leaseCount > 0) tick();
        }
        list("/sys/class/hwmon", /^hwmon\d+$/, paths => each(paths, (path, done) => {
            read(path + "/name", name => {
                const device = { name: name.trim(), path: path, temperatures: [] };
                hwmon.push(device);
                if (["k10temp", "zenpower", "coretemp"].indexOf(device.name) === -1) { done(); return; }
                list(path, /^temp\d+_input$/, temps => each(temps, (input, next) => {
                    read(input.replace(/_input$/, "_label"), label => { device.temperatures.push({ path: input, label: label.trim() }); next(); });
                }, done));
            });
        }, finish));
        list("/sys/class/thermal", /^thermal_zone\d+$/, paths => each(paths, (path, done) => {
            read(path + "/type", type => { thermal.push({ type: type.trim(), path: path + "/temp" }); done(); });
        }, finish));
        list("/sys/class/drm", /^card\d+$/, paths => each(paths, (path, done) => {
            const device = path + "/device";
            read(device + "/uevent", text => {
                const driver = (text.match(/^DRIVER=(.+)$/m) || [])[1];
                const pci = (text.match(/^PCI_SLOT_NAME=(.+)$/m) || [])[1];
                if (["amdgpu", "nvidia", "i915", "xe"].indexOf(driver) === -1 || !pci || cards.some(card => card.id === pci)) { done(); return; }
                const card = { id: pci.toLowerCase(), path: device, driver: driver, name: driver === "amdgpu" ? "AMD graphics" : driver === "nvidia" ? "NVIDIA graphics" : "Intel graphics", discrete: driver === "nvidia", vramTotal: null, temperaturePath: "", discoveryComplete: driver === "nvidia" };
                cards.push(card);
                read(device + "/power/runtime_status", state => {
                    if (state.trim() !== "active") { done(); return; }
                    if (card.discoveryComplete) done();
                    else completeGpuDiscovery(card, done);
                });
            });
        }, finish));
    }
    function completeGpuDiscovery(card, done) {
        function sensors() {
            list(card.path + "/hwmon", /^hwmon\d+$/, monitors => {
                if (monitors.length) card.temperaturePath = monitors[0] + "/temp1_input";
                card.discoveryComplete = true;
                done();
            });
        }
        if (card.driver === "amdgpu") read(card.path + "/mem_info_vram_total", total => {
            card.vramTotal = Logic.number(total);
            card.discrete = card.vramTotal !== null && card.vramTotal > 1073741824;
            sensors();
        });
        else sensors();
    }
    function publishChoices() {
        devices = Logic.orderGpus(devices);
        shell.status.set("gpus", devices.map(card => ({ value: card.id, label: card.name })));
    }
    function lease(arg) {
        const request = JSON.parse(arg);
        if (typeof request.id !== "string" || request.id === "" || typeof request.open !== "boolean") return "refused: lease=value";
        const next = Object.assign({}, leases);
        if (request.open) next[request.id] = true;
        else delete next[request.id];
        leases = next;
        return "ok";
    }
    onLeaseCountChanged: {
        if (leaseCount > 0) { if (discovered) tick(); }
        else {
            generation++;
            cycleBusy = false;
            cycle = null;
            previousCpu = null;
            gpuResult = null;
            if (discovered) jobs = [];
            if (query !== null) queryEnding = true;
            query = null;
            nvidia.running = false;
        }
    }
    function tick() {
        if (query !== null && !queryEnding && Date.now() - query.startedAt >= 10000) {
            gpuResult = { id: query.card.id, state: "unavailable", use: null, vramUsed: null, vramTotal: null, temperature: null };
            queryEnding = true;
            // running=false sends SIGTERM; the child can still be running.
            // Keep the request barrier until exited confirms completion.
            // https://quickshell.org/docs/v0.3.1/types/Quickshell.Io/Process
            nvidia.running = false;
        }
        if (!discovered || leaseCount === 0 || cycleBusy) return;
        cycleBusy = true;
        const token = generation;
        const sample = { cpu: {}, memory: {}, gpu: null, sampledAt: Date.now() };
        cycle = sample;
        function live() { return generation === token && leaseCount > 0; }
        read("/proc/stat", text => {
            if (!live()) return;
            const counters = Logic.cpuCounters(text);
            sample.cpu = { use: Logic.cpuUse(previousCpu, counters), temperature: null, cores: counters === null ? null : counters.cores };
            previousCpu = counters;
        });
        read("/proc/meminfo", text => { if (live()) sample.memory = Logic.memory(text); });
        if (cpuTemperaturePath !== "") read(cpuTemperaturePath, text => { if (live()) sample.cpu.temperature = Logic.temperature(text); });
        // A card skipped while asleep stays pending. CPU and memory reads
        // precede this cold discovery, and an inactive card waits for the
        // next timer tick instead of recursively starting another cycle.
        const pendingCards = devices.filter(card => card.driver === "nvidia" ? nvidiaPresent && !card.inventoryComplete : !card.discoveryComplete);
        each(pendingCards, (card, done) => {
            read(card.path + "/power/runtime_status", state => {
                if (!live()) return;
                if (state.trim() !== "active") { done(); return; }
                if (card.driver !== "nvidia") { completeGpuDiscovery(card, done); return; }
                if (!nvidia.running && !queryEnding) startQuery("inventory", card);
                done();
            });
        }, () => {
            if (!live()) return;
            if (pendingCards.length) publishChoices();
            sampleGpu(sample, live);
        });
    }
    function sampleGpu(sample, live) {
        const selected = chosenGpu === "" ? devices[0] : devices.find(card => card.id === chosenGpu);
        if (!selected) {
            if (chosenGpu !== "") sample.gpu = { id: chosenGpu, name: "Graphics card unavailable", state: "unavailable", use: null };
            read("", () => { if (live()) publish(sample); });
            return;
        }
        sample.gpu = { id: selected.id, name: selected.name, state: "ready", use: null, vramUsed: null, vramTotal: null, temperature: null };
        read(selected.path + "/power/runtime_status", state => {
            if (!live()) return;
            // Read runtime_status before sensors or nvidia-smi. A suspended
            // device must stay asleep instead of waking for the bar.
            if (state.trim() === "suspended") { gpuResult = null; sample.gpu.state = "asleep"; publish(sample); return; }
            if (state.trim() !== "active") { gpuResult = null; sample.gpu.state = "unavailable"; publish(sample); return; }
            if (selected.driver === "nvidia") {
                if (!nvidiaPresent) { sample.gpu.state = "unavailable"; publish(sample); return; }
                if (gpuResult !== null && gpuResult.id === selected.id) Object.assign(sample.gpu, gpuResult);
                if (!nvidia.running && !queryEnding) startQuery("readings", selected);
                // NVIDIA completion updates the next tick's snapshot. CPU
                // and memory still publish while a GPU query is outstanding.
                publish(sample);
                return;
            }
            const files = {};
            if (selected.driver === "amdgpu") {
                read(selected.path + "/gpu_busy_percent", text => { files.use = text; });
                read(selected.path + "/mem_info_vram_used", text => { files.vramUsed = text; });
                read(selected.path + "/mem_info_vram_total", text => { files.vramTotal = text; });
            } else sample.gpu.state = "unsupported";
            if (selected.temperaturePath !== "") read(selected.temperaturePath, text => { files.temperature = text; });
            read("", () => { if (live()) { Object.assign(sample.gpu, Logic.amdGpu(files)); publish(sample); } });
        });
    }
    function startQuery(kind, card) {
        query = { kind: kind, card: card, startedAt: Date.now(), generation: generation };
        nvidia.command = ["nvidia-smi", "--id=" + card.id, "--query-gpu=index,pci.bus_id,name,utilization.gpu,memory.used,memory.total,temperature.gpu", "--format=csv,noheader,nounits"];
        nvidia.running = true;
    }
    function publish(sample) {
        readings = sample;
        cycleBusy = false;
        cycle = null;
        const reply = shell.status.set("readings", sample);
        if (reply !== "ok") console.warn("sysmon status: " + reply);
    }
    function finishQuery(code) {
        const pending = query;
        const timedOut = queryEnding;
        query = null;
        queryEnding = false;
        if (leaseCount === 0 || pending === null || pending.generation !== generation) return;
        const row = code === 0 && !timedOut ? Logic.nvidiaRows(gpuText.text).find(card => card.id === pending.card.id) : null;
        if (pending.kind === "inventory") {
            pending.card.inventoryComplete = true;
            if (row) { pending.card.name = row.name; pending.card.vramTotal = row.vramTotal; }
            publishChoices();
            return;
        }
        gpuResult = row ? Object.assign({ state: "ready" }, row) : { id: pending.card.id, state: "unavailable", use: null, vramUsed: null, vramTotal: null, temperature: null };
    }
    Timer {
        id: poller
        objectName: "sysmon-poller"
        interval: (root.shell === null ? 2 : root.shell.settings.refreshSeconds) * 1000
        repeat: true
        running: root.discovered && root.leaseCount > 0
        onTriggered: root.tick()
    }
    Process {
        id: nvidia
        // Process applies explicit variables after clearing inherited ones.
        // https://quickshell.org/docs/v0.3.1/types/Quickshell.Io/Process
        clearEnvironment: true
        environment: ({ PATH: null, LC_ALL: "C" })
        stdout: StdioCollector { id: gpuText; waitForEnd: true }
        onExited: code => root.finishQuery(code)
        onRunningChanged: {
            if (running || root.query === null || root.queryEnding) return;
            const pending = root.query;
            // A failed start has no exited signal. Let a normal exit finish
            // first, then release only the same failed request.
            Qt.callLater(() => { if (root.query === pending && !running && !root.queryEnding) root.finishQuery(1); });
        }
    }
    onShellChanged: {
        if (shell === null || registered) return;
        registered = true;
        shell.ipc.handle("lease", root.lease);
        shell.status.set("readings", readings);
        discover();
    }
}
