import QtQuick
import QtTest
import "../../shell/plugins/vgs.sysmon" as Sysmon

// The existing FileView and Process stand-ins complete production callbacks
// by hand. These cases prove ownership and ordering, not kernel I/O.
Item {
    id: root
    width: 400
    height: 200
    property var publications: []
    Component { id: serviceComponent; Sysmon.Service {} }
    TestCase {
        id: tests
        name: "sysmon_service"
        when: windowShown
        property var service: null
        property var file: null
        property var process: null
        property var paths: []
        property int cpuReads: 0
        function init() {
            root.publications = []; paths = []; cpuReads = 0;
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
                temperaturePath: "/fixture/gpu/temp", inventoryComplete: true, discrete: true, vramTotal: 1000000000 };
        }
        function open(devices) {
            service.devices = devices || [];
            service.discovered = true;
            compare(service.lease(JSON.stringify({ id: "widget", open: true })), "ok");
        }
        function bytes(path, runtime) {
            if (path === "/proc/stat") {
                cpuReads++;
                return "cpu " + (100 + cpuReads * 10) + " 20 30 " + (400 + cpuReads * 10) + " 50 10 10 0 10 0\ncpu0 1 2 3 4\n";
            }
            if (path === "/proc/meminfo") return "MemTotal: 4000 kB\nMemAvailable: 3000 kB\nSwapTotal: 2000 kB\nSwapFree: 1500 kB\n";
            if (path.endsWith("runtime_status")) return runtime;
            return "25000";
        }
        function drain(runtime) {
            for (let i = 0; i < 20; i++) {
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
        function test_nvidia_timeout_uses_the_existing_timer_tick() {
            open([card("nvidia")]); drain("active");
            verify(process.running);
            service.query.startedAt = Date.now() - 10001;
            service.tick();
            compare(process.running, false);
            compare(service.queryEnding, true);
            const query = service.query;
            service.tick();
            compare(service.query, query);
            process.finish(15, 0, "");
            compare(service.queryEnding, false);
            compare(service.gpuResult.state, "unavailable");
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
