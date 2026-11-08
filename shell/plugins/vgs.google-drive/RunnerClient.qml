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

    // DONE receives (ok, stdout, firstErrorLine, exitCode), exitCode null
    // when the runner did not start.
    function request(args, done, before) {
        const key = JSON.stringify(args);
        const waiting = queue.find(q => JSON.stringify(q.args) === key);
        if (waiting !== undefined) {
            if (done !== undefined) waiting.dones.push(done);
            return;
        }
        queue = queue.concat([{ args: args, dones: done === undefined ? [] : [done], before: before }]);
        pump();
    }

    function pump() {
        if (cli.running || queue.length === 0) return;
        const next = queue[0];
        queue = queue.slice(1);
        // A Settings change can land while earlier status/probe calls
        // hold the queue. Service re-admits Sync now at this boundary,
        // after its latest mode mirror, not when the request was queued.
        if (next.before !== undefined && !next.before()) {
            pump();
            return;
        }
        active = next;
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
        // exited carries exitCode and exitStatus:
        // https://quickshell.org/docs/v0.3.1/types/Quickshell.Io/Process
        // Qt's exitCode is invalid after a crash; NormalExit is 0:
        // https://doc.qt.io/qt-6/qprocess.html#exitCode
        // https://code.qt.io/cgit/qt/qtbase.git/plain/src/corelib/io/qprocess.h?h=6.11
        const ok = done !== null && done.status === 0 && done.code === 0;
        const line = ok ? "" : call.args[0] + " " + (done === null ? "start=failed" : "exit=" + done.code + (done.status === 0 ? "" : " status=" + done.status)) + " " + firstError(stderrText);
        const code = done === null || done.status !== 0 ? null : done.code;
        for (const each of call.dones) each(ok, stdoutText, line, code);
        pump();
    }

    // Its stdout and stderr parsers are set before it first runs. `exited`
    // records the code, and the call ends when `running` turns false, as
    // the updates service and the automations engine client read theirs.
    // Quickshell kills the process when the shell stops (Process.running,
    // Quickshell 0.3.1 reference); every runner verb writes its files
    // https://quickshell.org/docs/v0.3.1/types/Quickshell.Io/Process
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
