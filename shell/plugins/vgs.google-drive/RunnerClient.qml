import QtQuick
import Quickshell.Io

// The service's one door to bin/google-drive: one subprocess at a time, in
// call order. A call equal to one still waiting joins it, so the runner
// runs once and every caller hears the answer. The runner owns the pair
// list, the pause record, the units and the status record; this owner only
// hands it a verb and reads its answer.
Item {
    id: root

    readonly property string runner: String(Qt.resolvedUrl("bin/google-drive")).replace(/^file:\/\//, "")
    property var queue: []
    property var active: null

    // DONE receives (ok, stdout, firstErrorLine).
    function request(args, done) {
        const key = JSON.stringify(args);
        const waiting = queue.find(q => JSON.stringify(q.args) === key);
        if (waiting !== undefined) {
            if (done !== undefined) waiting.dones.push(done);
            return;
        }
        queue = queue.concat([{ args: args, dones: done === undefined ? [] : [done] }]);
        pump();
    }

    function pump() {
        if (cli.running || queue.length === 0) return;
        active = queue[0];
        queue = queue.slice(1);
        cli.command = [runner].concat(active.args);
        cli.running = true;
    }

    // The runner's refusal line, `google-drive: refused: ...`, or its first
    // line: a log line the caller keeps in the shell's log.
    function firstError(text) {
        const lines = String(text || "").split("\n").filter(line => line.trim() !== "");
        const refused = lines.find(line => line.startsWith("google-drive: refused: "));
        return refused !== undefined ? refused : lines.length > 0 ? lines[0] : "";
    }

    function finish(done, stdoutText, stderrText) {
        const call = active;
        active = null;
        const ok = done !== null && done.code === 0;
        const line = ok ? "" : call.args[0] + " " + (done === null ? "start=failed" : "exit=" + done.code) + " " + firstError(stderrText);
        for (const each of call.dones) each(ok, stdoutText, line);
        pump();
    }

    // Its stdout and stderr parsers are set before it first runs. `exited`
    // records the code, and the call ends when `running` turns false, as
    // the updates service and the automations engine client read theirs.
    // Quickshell kills the process when the shell stops (Process.running,
    // Quickshell 0.3.1 reference); every runner verb writes its files
    // whole under a temporary name, so a cut-off verb leaves none half
    // written.
    Process {
        id: cli
        property var completion: null
        stdout: StdioCollector { id: cliOut }
        stderr: StdioCollector { id: cliErr }
        onExited: (code, status) => { completion = { code: code, status: status }; }
        onRunningChanged: {
            if (running) return;
            const done = completion;
            completion = null;
            root.finish(done, cliOut.text, cliErr.text);
        }
    }
}
