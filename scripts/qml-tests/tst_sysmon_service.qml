import QtQuick
import QtTest
import qs.Core
import "../../shell/plugins/vgs.sysmon" as Sysmon

// The existing FileView and Process stand-ins complete production callbacks
// by hand. These cases prove ownership and ordering, not kernel I/O.
Item {
    id: root
    width: 400
    height: 200
    property var publications: []
    Component {
        id: serviceComponent
        Sysmon.Service {
            // Override only directory I/O; production discovery and ticks run.
            function list(path, matcher, done) {
                tests.listedPaths.push(path);
                done(tests.directories[path] || []);
            }
        }
    }
    TestCase {
        id: tests
        name: "sysmon_service"
        when: windowShown
        property var service: null
        property var file: null
        property var process: null
        property var paths: []
        property int cpuReads: 0
        property var directories: ({})
        property var fixtureFiles: ({})
        property var listedPaths: []
        function init() {
            root.publications = []; paths = []; cpuReads = 0;
            directories = {}; fixtureFiles = {}; listedPaths = [];
            const scope = { settings: { gpu: "", refreshSeconds: 10 }, requirements: { missing: [] },
                status: { set: function (key, value) { root.publications = root.publications.concat([{ key: key, value: value }]); return "ok"; } } };
            service = createTemporaryObject(serviceComponent, root, { registered: true, shell: scope });
            verify(service !== null);
            file = Array.from(service.resources).find(item => typeof item.finishRead === "function");
            process = Array.from(service.resources).find(item => typeof item.finish === "function");
            verify(file !== undefined); verify(process !== undefined);
        }
        function cleanup() { service.destroy(); service = null; wait(0); }
        function card(driver) {
            return { id: "0000:01:00.0", path: "/fixture/gpu", driver: driver, name: "Fixture GPU",
                temperaturePath: "/fixture/gpu/temp", discoveryComplete: true, inventoryComplete: true, discrete: true, vramTotal: 1000000000 };
        }
        function open(devices) {
            service.devices = devices || [];
            service.discovered = true;
            compare(service.lease(JSON.stringify({ id: "widget", open: true })), "ok");
        }
        function bytes(path, runtime) {
            if (fixtureFiles[path] !== undefined) return fixtureFiles[path];
            if (path === "/proc/stat") {
                cpuReads++;
                return "cpu " + (100 + cpuReads * 10) + " 20 30 " + (400 + cpuReads * 10) + " 50 10 10 0 10 0\ncpu0 1 2 3 4\n";
            }
            if (path === "/proc/meminfo") return "MemTotal: 4000 kB\nMemAvailable: 3000 kB\nSwapTotal: 2000 kB\nSwapFree: 1500 kB\n";
            if (path.endsWith("runtime_status")) return runtime;
            return "25000";
        }
        function drain(runtime) {
            for (let i = 0; i < 40; i++) {
                wait(0);
                if (service.readingJob === null && service.jobs.length === 0) return;
                tryCompare(file, "live", "read");
                const path = service.readingJob.path;
                paths.push(path);
                file.finishRead(bytes(path, runtime));
            }
            fail("the finite read queue did not complete");
        }
        function readingsCount() { return root.publications.filter(row => row.key === "readings").length; }
        function test_graphics_status_copy_data() {
            return [{ tag: "absent", driver: "", text: "Not found", hint: "No supported graphics card found.", tone: "info" },
                { tag: "supported-nvidia", driver: "nvidia", text: "Available", tone: "ok" }];
        }
        function test_graphics_status_copy(data) {
            compare(root.publications.filter(row => row.key === "graphics").length, 0, "discovery pending reports no missing card");
            if (data.driver !== "") {
                directories = { "/sys/class/drm": ["/sys/class/drm/card1"] };
                fixtureFiles["/sys/class/drm/card1/device/uevent"] = "DRIVER=nvidia\nPCI_SLOT_NAME=0000:01:00.0\n";
            }
            service.discover(); drain("suspended");
            const graphics = root.publications.filter(row => row.key === "graphics");
            compare(graphics.length, 1);
            const accepted = PluginLogic.statusWrite({ status: { graphics: { type: "state" } } }, {}, "graphics", graphics[0].value);
            verify(accepted.ok, "the production status judge accepts the graphics payload");
            compare(JSON.stringify(graphics[0].value), JSON.stringify({ text: data.text, hint: data.hint, tone: data.tone }));
        }
        function test_last_lease_stops_timer_and_cancels_pending_reads() {
            open();
            tryCompare(file, "live", "read");
            verify(service.polling);
            verify(service.jobs.length > 0);
            const before = readingsCount();
            compare(service.lease('{"id":"widget","open":false}'), "ok");
            compare(service.leaseCount, 0);
            compare(service.polling, false);
            compare(service.jobs.length, 0);
            file.finishRead(bytes("/proc/stat", "active"));
            wait(0);
            compare(readingsCount(), before);
        }
        function test_stale_read_cannot_publish_into_a_new_lease() {
            open();
            tryCompare(file, "live", "read");
            service.lease('{"id":"widget","open":false}');
            service.lease('{"id":"new-widget","open":true}');
            // The stand-in retains its last armed path across an empty
            // path. Permit the new generation to arm that path again.
            file.armedPath = "";
            file.finishRead("cpu 999999 0 0 0 0 0 0 0\n");
            drain("active");
            compare(readingsCount(), 1);
            compare(service.readings.cpu.use, null);
            compare(service.readings.memory.used, 1024000);
        }
        function test_power_state_gates_sensors_data() {
            return [{ tag: "asleep", runtime: "suspended", expected: "asleep" },
                { tag: "unreadable", runtime: "", expected: "unavailable" }];
        }
        function test_power_state_gates_sensors(data) {
            open([card("amdgpu")]); drain(data.runtime);
            compare(service.readings.gpu.state, data.expected);
            compare(service.readings.gpu.use, null);
            compare(service.readings.gpu.temperature, null);
            compare(JSON.stringify(paths), JSON.stringify(["/proc/stat", "/proc/meminfo", "/fixture/gpu/power/runtime_status"]));
            compare(process.running, false);
        }
        function test_nvidia_does_not_overlap_and_last_lease_cancels_it() {
            open([card("nvidia")]); drain("active");
            compare(process.running, true);
            const query = service.query;
            const command = JSON.stringify(process.command);
            service.tick(); service.tick();
            drain("active");
            compare(readingsCount(), 2);
            compare(service.readings.cpu.use, 50);
            compare(service.query, query);
            compare(JSON.stringify(process.command), command);
            compare(service.jobs.length, 0);
            service.lease('{"id":"widget","open":false}');
            compare(process.running, false);
            compare(service.query, null);
            compare(service.polling, false);
            const before = readingsCount();
            process.finish(0, 0, "0, 00000000:01:00.0, Fixture GPU, 25, 100, 1000, 54\n");
            compare(readingsCount(), before);
        }
        function test_suspended_discovery_completes_after_wake_data() {
            return [{ tag: "amd", driver: "amdgpu", expectedState: "ready", expectedFirst: "0000:01:00.0" },
                { tag: "intel-i915", driver: "i915", expectedState: "unsupported", expectedFirst: "0000:00:02.0" },
                { tag: "intel-xe", driver: "xe", expectedState: "unsupported", expectedFirst: "0000:00:02.0" },
                { tag: "nvidia", driver: "nvidia", expectedState: "ready", expectedFirst: "0000:01:00.0" }];
        }
        function test_suspended_discovery_completes_after_wake(data) {
            const integratedPath = "/sys/class/drm/card0/device";
            const wakePath = "/sys/class/drm/card1/device";
            directories = { "/sys/class/drm": ["/sys/class/drm/card0", "/sys/class/drm/card1"] };
            directories[wakePath + "/hwmon"] = ["/fixture/hwmon"];
            fixtureFiles[integratedPath + "/uevent"] = "DRIVER=i915\nPCI_SLOT_NAME=0000:00:02.0\n";
            fixtureFiles[wakePath + "/uevent"] = "DRIVER=" + data.driver + "\nPCI_SLOT_NAME=0000:01:00.0\n";
            fixtureFiles[wakePath + "/mem_info_vram_total"] = "8589934592";
            fixtureFiles["/fixture/hwmon/temp1_input"] = "54000";
            service.discover(); drain("suspended");
            verify(service.discovered);
            const waking = service.devices.find(row => row.id === "0000:01:00.0");
            compare(waking.temperaturePath, "");
            compare(waking.inventoryComplete, undefined);
            open(service.devices); drain("suspended");
            service.tick(); drain("suspended");
            compare(readingsCount(), 2);
            compare(service.readings.cpu.use, 50);
            compare(service.readings.memory.used, 1024000);
            compare(process.running, false);
            compare(waking.inventoryComplete, undefined);
            compare(listedPaths.indexOf(wakePath + "/hwmon"), -1);
            verify(!paths.some(path => path.endsWith("mem_info_vram_total") || path.endsWith("temp1_input")));
            service.tick(); drain("active");
            if (data.driver === "nvidia") {
                compare(process.running, true);
                compare(service.query.kind, "inventory");
                process.finish(0, 0, "0, 00000000:01:00.0, Awakened GPU, 25, 100, 8192, 54\n");
                compare(waking.inventoryComplete, true);
                compare(waking.name, "Awakened GPU");
                compare(waking.vramTotal, 8589934592);
            } else {
                compare(waking.discoveryComplete, true);
                compare(waking.temperaturePath, "/fixture/hwmon/temp1_input");
                if (data.driver === "amdgpu") {
                    compare(waking.discrete, true);
                    compare(waking.vramTotal, 8589934592);
                }
            }
            compare(service.devices[0].id, data.expectedFirst);
            const choices = root.publications.filter(row => row.key === "gpus").pop().value;
            compare(choices[0].value, data.expectedFirst);
            compare(choices.find(row => row.value === waking.id).label, waking.name);
            service.tick(); drain("active");
            compare(service.readings.gpu.id, data.expectedFirst);
            // Explicit selection must survive discovery's automatic reorder.
            service.shell = Object.assign({}, service.shell, { settings: { gpu: waking.id, refreshSeconds: 10 } });
            service.tick(); drain("active");
            if (data.driver === "nvidia") {
                process.finish(0, 0, "0, 00000000:01:00.0, Awakened GPU, 25, 100, 8192, 54\n");
                service.tick(); drain("active");
            }
            compare(service.readings.gpu.id, waking.id);
            compare(service.readings.gpu.state, data.expectedState);
            compare(service.readings.gpu.temperature, 54);
        }
        function test_nvidia_timeout_invalidates_cache_until_child_exit() {
            open([card("nvidia")]); drain("active");
            process.finish(0, 0, "0, 00000000:01:00.0, Fixture GPU, 25, 100, 1000, 54\n");
            service.tick(); drain("active");
            compare(service.readings.gpu.use, 25);
            compare(service.readings.gpu.temperature, 54);
            verify(process.running);
            service.query.startedAt = Date.now() - 10001;
            const query = service.query;
            const command = JSON.stringify(process.command);
            service.tick();
            compare(process.running, false);
            compare(service.queryEnding, true);
            // Process.running=false requests termination. Model a child
            // that still runs until the explicit exit callback below.
            process.running = true;
            drain("active");
            for (let tick = 0; tick < 3; tick++) {
                service.tick(); drain("active");
                compare(service.query, query);
                compare(process.running, true);
                compare(JSON.stringify(process.command), command);
                compare(service.readings.gpu.state, "unavailable");
                for (const field of ["use", "vramUsed", "vramTotal", "temperature"]) compare(service.readings.gpu[field], null);
            }
            process.finish(0, 0, "0, 00000000:01:00.0, Fixture GPU, 99, 100, 1000, 99\n");
            compare(service.queryEnding, false);
            compare(service.gpuResult.state, "unavailable");
            service.tick(); drain("active");
            verify(process.running);
            compare(service.readings.gpu.state, "unavailable");
        }
        function test_nvidia_failed_start_releases_the_request() {
            open([card("nvidia")]); drain("active");
            verify(process.running);
            process.running = false;
            tryCompare(service, "query", null);
            compare(service.gpuResult.state, "unavailable");
            service.tick(); drain("active");
            compare(process.running, true);
            compare(service.readings.gpu.state, "unavailable");
        }
    }
}
