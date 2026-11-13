import QtQuick
import Quickshell
import Quickshell.Io
import "VpnLogic.js" as Logic

// One open picker's discovery and one serialized location change. The
// service retains the shared profile lock, state writer and status reader.
Item {
    id: root
    required property var controller
    property string opened: ""
    property var catalog: ({ kind: "closed" })
    property var value: ({ phase: "closed", problem: "", countries: [] })
    property var operation: null
    readonly property bool changing: operation !== null
    property string step: ""
    readonly property bool wantsStatus: step === "protection" || step === "allowance"
    property bool canceled: false

    function publish(phase, problem) {
        value = { phase: phase, problem: problem || "", countries: catalog.kind === "ready" ? catalog.rows : [] };
        if (controller.report("nordState", value)) return true;
        // The complete public catalog must fit the shared status channel.
        // A refused publication is an error, never a truncated location list
        // or a picker left loading after its request ended.
        catalog = { kind: "refused" };
        value = { phase: "failed", problem: Logic.nordProblem("catalog"), countries: [] };
        controller.report("nordState", value);
        return false;
    }
    function request(request) {
        if (request.kind === "profile") {
            if (changing) return "busy";
            const uuid = request.uuid;
            if (uuid !== "" && !controller.profiles.rows.some(row => row.uuid === uuid && row.type === "wireguard")) return "refused: nord=profile";
            return controller.shell.configure.set("nordProfile", uuid);
        }
        if (request.kind === "close") {
            if (request.id !== opened) return "ok";
            opened = "";
            catalog = { kind: "closed" };
            // Discovery and recommendation may be canceled. Once the write
            // starts the operation must settle its acknowledgement/reconnect.
            if (step === "catalog" || step === "protection" || step === "recommendation" || step === "peer") {
                canceled = true;
                if (worker.running) worker.signal(9);
            }
            publish(changing ? "changing" : "closed", value.problem);
            return "ok";
        }
        if (request.kind === "open") {
            if (changing || worker.running) return "busy";
            if (typeof request.id !== "string" || request.id === "") return "refused: nord=id";
            if (opened === request.id) return "ok";
            if (controller.shell.requirements.missing.indexOf("curl") !== -1) return "refused: nord=curl";
            opened = request.id;
            canceled = false;
            catalog = { kind: "loading" };
            publish("loading", "");
            run("catalog", Logic.nordFetchArgv());
            return "ok";
        }
        if (request.kind !== "city" || opened === "" || catalog.kind !== "ready") return "refused: nord=state";
        if (changing || controller.profileAction !== null || controller.stateWrite !== null || worker.running) return "busy";
        if (controller.killReady && controller.killFile.kind !== "valid" && controller.killFile.kind !== "missing") return "refused: nord=kill-switch";
        const uuid = controller.shell.settings.nordProfile;
        const row = controller.profiles.rows.find(candidate => candidate.uuid === uuid && candidate.type === "wireguard");
        const country = catalog.rows.find(candidate => candidate.id === request.countryId);
        if (!row || ["", "activated"].indexOf(row.state) === -1 || !country || !country.cities.some(city => city.id === request.cityId
            && (country.subdivisions.length === 0 || city.subdivision_id === request.subdivisionId))) return "refused: nord=profile";
        if (controller.shell.requirements.missing.indexOf("curl") !== -1) return "refused: nord=curl";
        operation = { uuid: uuid, name: row.name, type: row.type, state: row.state, cityId: request.cityId, armed: false, server: null, plan: null };
        controller.profileAction = { kind: "nord", uuid: row.uuid, name: row.name };
        controller.profileProblem = null;
        canceled = false;
        if (!publish("changing", "")) { finish(Logic.nordProblem("catalog")); return "ok"; }
        // Setup can need repair while an installed helper still holds the
        // table (checkKillPlan). Observe that protection before any write;
        // killReady alone cannot rule it out.
        if (Logic.checkKillPlan(controller.killStep) === "none") run("recommendation", Logic.nordFetchArgv(request.cityId));
        else {
            step = "protection";
            allowanceDeadline.restart();
            controller.readKillStatus();
        }
        return "ok";
    }
    function run(next, argv) {
        step = next;
        worker.command = argv;
        worker.environment = next === "catalog" || next === "recommendation"
            ? { PATH: Quickshell.env("PATH"), LC_ALL: "C" } : controller.nmcliEnvironment;
        worker.completion = null;
        worker.running = true;
        deadline.restart();
    }
    function finish(problem) {
        retry.stop();
        allowanceDeadline.stop();
        const wasChanging = changing;
        operation = null;
        step = "";
        publish(opened === "" ? "closed" : problem === "" ? "done" : "failed", problem);
        if (wasChanging) {
            controller.profileAction = null;
            controller.refresh("");
        }
    }
    function ended(code, text) {
        deadline.stop();
        if (canceled) { canceled = false; finish(""); return; }
        if (step === "catalog") {
            catalog = Logic.nordCatalog(code, text);
            publish(catalog.kind === "ready" ? "ready" : "failed", catalog.kind === "ready" ? "" : Logic.nordProblem("catalog"));
            step = "";
            return;
        }
        if (step === "recommendation") {
            const server = Logic.nordServer(code, text);
            if (server.kind !== "ready") { finish(Logic.nordProblem("recommendation")); return; }
            operation = Object.assign({}, operation, { server: server });
            run("peer", Logic.nordPeerArgv(operation.uuid));
        } else if (step === "peer") {
            if (code !== 0) { finish(Logic.nordProblem("peer")); return; }
            if (operation.armed && (!controller.killReady || controller.killFile.kind !== "valid" || controller.killFile.mode === "off"
                || controller.killFile.meantOn.toLowerCase() !== operation.uuid)) { finish(Logic.nordProblem("protection")); return; }
            const profile = Object.assign({}, operation, { peers: text });
            const plan = Logic.nordPlan(operation.uuid, profile, operation.server,
                controller.killReady && controller.killFile.kind === "valid" && controller.killFile.mode !== "off"
                && controller.killFile.meantOn.toLowerCase() === operation.uuid);
            if (plan.kind !== "ready") { finish(Logic.nordProblem("peer")); return; }
            operation = Object.assign({}, operation, { plan: plan, endpoint: /(?:^| )endpoint=([^ ]+)/.exec(plan.argv[6])[1] });
            run("modify", plan.argv);
        } else if (code !== 0) finish(Logic.nordProblem(step));
        else if (step === "modify") {
            if (operation.plan.refreshAllowance) {
                step = "allowance";
                const reply = controller.writeState(file => file.kind === "valid" && file.mode !== "off" && file.meantOn.toLowerCase() === operation.uuid ? {} : null,
                    ok => {
                        if (!ok || controller.killFile.kind !== "valid" || controller.killFile.mode === "off" || controller.killFile.meantOn.toLowerCase() !== operation.uuid) finish(Logic.nordProblem("allowance"));
                        else { allowanceDeadline.restart(); controller.readKillStatus(); }
                    }, true);
                if (reply !== "ok") finish(Logic.nordProblem("allowance"));
            } else reconnect();
        } else if (step === "down") run("up", ["nmcli", "connection", "up", "uuid", operation.uuid]);
        else if (step === "up") {
            const uuid = operation.uuid;
            finish("");
            controller.startCheck(uuid, true);
        }
    }
    function reconnect() {
        allowanceDeadline.stop();
        retry.stop();
        if (operation.plan.reconnect) run("down", ["nmcli", "connection", "down", "uuid", operation.uuid]);
        else finish("");
    }
    function statusRead(status) {
        if (step === "protection") {
            if (canceled) { canceled = false; finish(""); return; }
            if (status !== null && status.state === "unavailable" && status.profile === "" && status.reason === "cache-unreadable") { retry.restart(); return; }
            const armed = status !== null && (status.state === "holding" || status.state === "passing") && status.profile === operation.uuid;
            if (status !== null && status.state !== "off" && !(armed && controller.killReady && controller.killFile.kind === "valid"
                && controller.killFile.mode !== "off" && controller.killFile.meantOn.toLowerCase() === operation.uuid)) {
                finish(Logic.nordProblem("protection"));
                return;
            }
            allowanceDeadline.stop();
            retry.stop();
            operation = Object.assign({}, operation, { armed: armed });
            run("recommendation", Logic.nordFetchArgv(operation.cityId));
            return;
        }
        if (step !== "allowance" || controller.stateWrite !== null) return;
        const outcome = Logic.nordRefreshOutcome(status, { uuid: operation.uuid, endpoint: operation.endpoint });
        if (outcome === "armed") reconnect();
        else if (outcome === "failed") finish(Logic.nordProblem("allowance"));
        else retry.restart();
    }
    Timer { id: retry; interval: Logic.ARM_RETRY_MS; onTriggered: root.controller.readKillStatus() }
    Timer { id: allowanceDeadline; interval: Logic.ARM_WAIT_MS; onTriggered: root.finish(root.canceled ? "" : Logic.nordProblem(root.step)) }
    Timer { id: deadline; interval: Logic.ACTION_MS; onTriggered: worker.signal(9) }
    // Process owns the child on destruction; signal(9) bounds cancellation.
    // RunningChanged permits the next launch, and collectors finish first:
    // https://quickshell.org/docs/v0.3.1/types/Quickshell.Io/Process/
    // https://quickshell.org/docs/v0.3.1/types/Quickshell.Io/StdioCollector/
    Process {
        id: worker
        property var completion: null
        clearEnvironment: true
        stdout: StdioCollector { id: output; waitForEnd: true }
        stderr: StdioCollector { waitForEnd: true }
        onExited: (code, status) => { worker.completion = { code: code, status: status }; }
        onRunningChanged: if (!running) root.ended(root.controller.codeOf(completion), output.text)
    }
}
