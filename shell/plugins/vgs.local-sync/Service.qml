import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "SyncLogic.js" as Logic

// Owns vgs.local-sync's runtime side: the reads that find the sync jobs,
// the watches that tell when one copies, the Remove of a job the user made
// outside VGS, IPC and the one status write. The bar item and the flyout
// read the published `jobs` value only. Local Sync keeps no state of its
// own and writes no file of its own: every reading comes from systemd, the
// jobs' own files and the journal, and its one change to the system is
// Remove, which disables a job the user made outside VGS.
//
// A read of the jobs (`read`) runs these steps, one process at a time:
//   1. the installed services: systemctl --user list-unit-files;
//   2. their properties and every loaded service's: systemctl --user show;
//   3. the scripts their commands name, as data, never run: head, at most
//      SyncLogic.SCRIPT_BYTES of each, one file at a time;
//   4. the Automations store's last reading, for the automations that copy;
//      the store is watched, read only, and a change to its text reads the
//      jobs again;
//   5. which jobs copy now: systemd's GetUnitProcesses through busctl, one
//      unit at a time (the copy check);
//   6. each job's journal: journalctl --user -u <unit>, one job at a time.
// SyncLogic judges each answer. A read starts at start, when the user
// manager reports a change to a listed job or reloads, when a copy ends,
// when the store's text changes, on the flyout's open and on the `refresh`
// IPC. One read or one copy check runs at a time: a read asked for while
// either runs runs once after it, and so does a copy check.
//
// Two processes stay up while the plugin is on, neither of them a poll:
// - inotifywait on the engine programs: running an engine opens its file,
//   which wakes a copy check of every job. An open alone never means a
//   copy, since anything may read the file; the check decides. An
//   upgrade that replaces a program ends the watch on its old file, so
//   any other event finds the programs again and watches the new files.
// - journalctl --follow on the user manager's own lines: a unit started,
//   finished or failed, or the manager reloaded its units.
// Either one that ends while the plugin is on starts again, at most
// `watchRetries` times in a row.
// While a copy runs, the copy check of the copying jobs runs every
// `copyPoll` interval until no engine runs in them, since a script's copy
// ends with no journal line and no file event; with no copy running
// nothing polls.
//
//   vgshell ipc call vgs.local-sync invoke <name> <arg>   with <name>:
//     status    the published values, JSON
//     refresh   reads the jobs again; `ok`
//     remove    with a unit the user made outside VGS as its argument:
//               stops it and turns it and its triggers off, keeping its
//               file; `ok`, or `refused: unit=unknown` for a unit that is
//               not a listed job, `refused: unit=automation` for one
//               Automations owns
Item {
    id: root

    property var shell: null
    property bool registered: false
    // Set as the engine destroys the service, so the ends of its processes
    // that follow are not read as failures.
    property bool disposing: false
    readonly property var missing: shell === null ? null : shell.requirements.missing
    readonly property bool canRead: missing !== null && ["systemctl", "journalctl", "busctl", "head", "realpath"].every(command => missing.indexOf(command) === -1)
    readonly property bool canWatch: canRead && missing.indexOf("inotifywait") === -1
    // The engines this computer lacks, from the core's requirements scan,
    // which the Setup page's install and rescan run again; a job whose
    // engine is missing is unavailable.
    readonly property var missingEngines: missing === null ? [] : Logic.ENGINES.filter(engine => missing.indexOf(engine) !== -1)
    onMissingEnginesChanged: rescanEngines()
    // The engine programs realpath found on PATH, the files the exec watch
    // watches; null before that read.
    property var enginePaths: null
    // The Automations store, the file bin/automations names under
    // $XDG_CONFIG_HOME, else ~/.config, as Paths resolves it.
    readonly property string storeFile: Paths.configDir + "/automations/automations.json"
    // The store's last read text, null while it is absent or unreadable.
    property var storeText: null
    property string storeProblem: ""

    // The last complete reading, published as `jobs`.
    property var jobs: []
    property var facts: ({})
    property var copying: []
    // The control groups' units copying now, and when each began, so a
    // copy's end can tell whether the journal reported an error during it.
    property var copyStarts: ({})
    // Per unit, the end of the last copy this service saw end with no error
    // line: a script's job writes no line when a copy succeeds.
    property var cleanEnds: ({})
    // The copy that ended, waiting for the journal read that judges it.
    property var endedCopies: ({})
    property bool ready: false
    // Why the last read failed, and why the last Remove failed, "" for
    // none; a later read clears only its own.
    property string problem: ""
    property string removeProblem: ""

    // The read in progress: its step and what the earlier steps answered.
    property var pending: null
    property bool readAgain: false
    property var journalQueue: []

    // The long-lived processes start again after an end the service did
    // not ask for, this many times in a row; an event of the watch or a
    // line of the follower resets the count.
    readonly property int watchRetries: 3
    property int execRetries: 0
    property int followRetries: 0
    // The exec watch was stopped to watch the engines' new files.
    property bool rewatch: false
    // A find of the engines was asked for while one ran.
    property bool enginesAgain: false

    onShellChanged: start()
    onCanReadChanged: if (registered && canRead) {
        managerFollow.running = true;
        rescanEngines();
    }
    onCanWatchChanged: if (registered && canWatch) rescanEngines()
    Component.onDestruction: disposing = true

    function start() {
        if (shell === null || registered) return;
        registered = true;
        shell.ipc.handle("status", () => JSON.stringify(shell.status.values));
        shell.ipc.handle("refresh", () => {
            root.read();
            return "ok";
        });
        shell.ipc.handle("remove", unit => root.remove(unit));
        publish();
        // The engines' paths come first: the copy watch reads them, and
        // their end starts the first read.
        if (canRead) {
            rescanEngines();
            managerFollow.running = true;
        }
    }

    // Start a read of the jobs, or mark one to run once the read or the
    // copy check in progress ends: a check that ran beside a read would
    // take the other's answers.
    function read() {
        if (!canRead) {
            problem = "Local Sync needs systemd's tools to read the jobs.";
            publish();
            return;
        }
        if (pending !== null || check !== null) {
            readAgain = true;
            return;
        }
        // The store's folder may not exist yet, and a folder that does not
        // exist is not watched (QFileSystemWatcher::addPath adds only an
        // existing path), so every read reads the store again too.
        store.read();
        pending = { step: "files", names: [], records: [], scripts: {}, automations: {} };
        run(["systemctl", "--user", "list-unit-files", "--type=service", "--no-legend", "--plain"]);
    }

    // The read and the copy check are done: start what was asked for while
    // they ran, a read before a check.
    function settle() {
        if (pending !== null || check !== null) return;
        if (readAgain) {
            readAgain = false;
            read();
        } else if (checkWanted !== "") {
            const scope = checkWanted;
            checkWanted = "";
            checkCopies(scope);
        }
    }

    function run(command) {
        reader.command = command;
        reader.running = true;
    }

    function failed(step, completion, stderr) {
        console.warn("local-sync: read=failed step=" + step + " " + ending(completion, stderr));
        problem = "Local Sync could not read the sync jobs.";
        pending = null;
        publish();
        settle();
    }

    function ending(completion, stderr) {
        const lines = String(stderr || "").trim().split("\n");
        return (completion === null ? "exit=none" : "exit=" + completion.code + " status=" + completion.status) + " stderr=" + JSON.stringify(lines[lines.length - 1]);
    }

    // One step of a read ended with COMPLETION and its output TEXT.
    function readStep(completion, text, stderr) {
        const step = pending === null ? "" : pending.step;
        const ok = completion !== null && completion.status === 0;
        if (step === "files") {
            if (!ok || completion.code !== 0) return failed(step, completion, stderr);
            pending.names = Logic.unitFileNames(text);
            pending.step = "show";
            run(["systemctl", "--user", "show", "--timestamp=unix", "-p", Logic.SHOW_PROPERTIES.join(","), "*.service"].concat(pending.names));
        } else if (step === "show") {
            if (!ok || completion.code !== 0) return failed(step, completion, stderr);
            pending.records = Logic.parseShow(text);
            pending.files = Logic.scriptFiles(pending.records, Paths.home);
            pending.step = "scripts";
            nextScript();
        } else if (step === "scripts") {
            // A file that could not be read, gone or not the user's, holds
            // no lines: the job it names is not listed.
            if (ok && completion.code === 0) pending.scripts[pending.file] = Logic.scriptLines(text);
            else console.warn("local-sync: script=unread path=" + JSON.stringify(pending.file) + " " + ending(completion, stderr));
            nextScript();
        } else if (step === "journal") {
            if (!ok || completion.code !== 0) return failed(step, completion, stderr);
            const unit = pending.unit;
            const job = jobs.find(each => each.unit === unit);
            if (job !== undefined) pending.facts[unit] = Logic.journalFacts(String(text).split("\n").filter(line => line !== "").map(Logic.journalEntry), job);
            nextJournal();
        }
    }

    function nextScript() {
        if (pending.files.length === 0) return readCopies();
        pending.file = pending.files[0];
        pending.files = pending.files.slice(1);
        run(["head", "--bytes=" + Logic.SCRIPT_BYTES, "--", pending.file]);
    }

    function readCopies() {
        const read = Logic.readStore(storeText);
        pending.automations = read.automations;
        storeProblem = Logic.storeProblem(read, pending.records);
        const next = Logic.jobs(pending.records, pending.scripts, pending.automations, Paths.home, missingEngines);
        jobs = next;
        pending.step = "copies";
        startCheck(Logic.checkUnits(next), units => {
            noteCopies(units);
            journalQueue = next.map(job => job.unit);
            pending.step = "journal";
            pending.facts = {};
            nextJournal();
        });
    }

    function nextJournal() {
        if (journalQueue.length === 0) {
            facts = pending.facts;
            judgeEndedCopies();
            pending = null;
            problem = "";
            ready = true;
            publish();
            settle();
            return;
        }
        pending.unit = journalQueue[0];
        journalQueue = journalQueue.slice(1);
        const job = jobs.find(each => each.unit === pending.unit);
        run(["journalctl", "--user", "--no-pager", "-o", "json", "-n", "200"].concat(Logic.journalUnits(job)));
    }

    // UNITS copy now: a unit that starts copying records its start, and one
    // that stops waits for the next journal read to judge its copy.
    function noteCopies(units) {
        const now = Date.now();
        const starts = Object.assign({}, copyStarts);
        const ended = Object.assign({}, endedCopies);
        for (const unit of units)
            if (!(unit in starts)) starts[unit] = now;
        let stopped = false;
        for (const unit of Object.keys(starts)) {
            if (units.indexOf(unit) !== -1) continue;
            ended[unit] = { start: starts[unit], end: now };
            delete starts[unit];
            stopped = true;
        }
        copyStarts = starts;
        endedCopies = ended;
        copying = units;
        if (units.length > 0) copyPoll.restart();
        else copyPoll.stop();
        return stopped;
    }

    // A copy that ended is clean when its job's journal holds no error line
    // since the copy began.
    function judgeEndedCopies() {
        const clean = Object.assign({}, cleanEnds);
        for (const unit of Object.keys(endedCopies)) {
            const fact = facts[unit];
            if (fact !== undefined && fact.failedAt < endedCopies[unit].start) clean[unit] = endedCopies[unit].end;
        }
        cleanEnds = clean;
        endedCopies = ({});
    }

    // The copy check: asks systemd for each of UNITS' processes, one unit
    // at a time, UNITS being SyncLogic.checkUnits' { unit, job }, then calls
    // DONE with the jobs an engine runs in. A unit whose processes could
    // not be read is logged and counts as not copying: nothing confirmed a
    // copy there.
    property var check: null
    // The copy check asked for while a read or a check ran: "copying" for
    // the jobs that copy, "all" for every job, "" for none.
    property string checkWanted: ""

    function startCheck(units, done) {
        check = { units: units, copying: [], done: done };
        nextCheck();
    }

    function nextCheck() {
        if (check.units.length === 0) {
            const finished = check;
            check = null;
            finished.done(finished.copying);
            settle();
            return;
        }
        check.unit = check.units[0];
        check.units = check.units.slice(1);
        copyCheck.command = ["busctl", "--user", "--json=short", "call", "org.freedesktop.systemd1", "/org/freedesktop/systemd1",
            "org.freedesktop.systemd1.Manager", "GetUnitProcesses", "s", check.unit.unit];
        copyCheck.running = true;
    }

    function unitChecked(completion, text) {
        const running = completion !== null && completion.status === 0 && completion.code === 0 ? Logic.engineRunning(text) : null;
        if (running === null) console.warn("local-sync: processes=unread unit=" + check.unit.unit + " " + ending(completion, copyCheckErr.text));
        else if (running && check.copying.indexOf(check.unit.job) === -1) check.copying = check.copying.concat([check.unit.job]);
        nextCheck();
    }

    // The copy check alone: which jobs copy now, of the jobs that copy
    // (SCOPE "copying") or of every job ("all"). A copy that ended reads
    // the jobs again, for its journal lines and its unit's result. A check
    // asked for while a read or a check runs runs once after it, as wide as
    // the widest one asked for.
    function checkCopies(scope) {
        if (!canRead) return;
        if (pending !== null || check !== null) {
            if (checkWanted !== "all") checkWanted = scope;
            return;
        }
        startCheck(Logic.checkUnits(scope === "copying" ? jobs.filter(job => copying.indexOf(job.unit) !== -1) : jobs), units => {
            if (noteCopies(units)) read();
            else publish();
        });
    }

    function remove(unit) {
        const job = jobs.find(each => each.unit === unit);
        if (job === undefined) return "refused: unit=unknown";
        if (job.automation !== "") return "refused: unit=automation";
        if (remover.running) return "refused: remove=busy";
        removeProblem = "";
        remover.command = ["systemctl", "--user", "disable", "--now", "--"].concat(Logic.removeUnits(job));
        remover.running = true;
        return "ok";
    }

    // Find the engine programs again and watch their files: a running watch
    // stops first, and its end starts the find.
    function rescanEngines() {
        if (!registered || !canRead) return;
        if (execWatch.running) {
            rewatch = true;
            execWatch.running = false;
            return;
        }
        if (enginePathsRead.running) enginesAgain = true;
        else enginePathsRead.running = true;
    }

    // The long-lived process NAME ended while the plugin is on, after
    // RETRIES starts in a row, with STDERR: log why, and answer the count
    // for its next start, or -1 once `watchRetries` starts were spent.
    function lost(name, retries, stderr) {
        console.warn("local-sync: " + name + "=exited retry=" + (retries < watchRetries ? retries + 1 : "none") + " stderr=" + JSON.stringify(String(stderr).trim().split("\n").pop()));
        return retries < watchRetries ? retries + 1 : -1;
    }

    function publish() {
        if (shell === null) return;
        const value = {
            ready: ready,
            problem: problem,
            removeProblem: removeProblem,
            storeProblem: storeProblem,
            jobs: jobs,
            facts: facts,
            copying: copying,
            cleanEnds: cleanEnds,
            engines: Logic.ENGINES.filter(engine => missingEngines.indexOf(engine) === -1),
            // The smoke row's reading of the exec watch; no surface draws it.
            watching: execWatch.running
        };
        const reply = shell.status.set("jobs", value);
        if (!shell.status.isOk(reply)) console.error("local-sync: publish=jobs " + reply);
    }

    // Each read step's process, one at a time; the step that ran it reads
    // its answer.
    Process {
        id: reader
        property var completion: null
        stdout: StdioCollector { id: readerOut }
        stderr: StdioCollector { id: readerErr }
        onExited: (code, status) => { completion = { code: code, status: status }; }
        onRunningChanged: {
            if (running) return;
            const done = completion;
            completion = null;
            root.readStep(done, readerOut.text, readerErr.text);
        }
    }

    // The Automations store, watched and read only, never written. A
    // change, such as a sync job Automations saved, or a store that went,
    // reads the jobs again. WatchedFile reports a change it saw while idle
    // only as `changed` (shell/Commons/WatchedFile.qml), and Quickshell's
    // FileView watches the file's folder too, so a store made after the
    // start is seen (src/io/fileview.cpp, onWatchedDirectoryChanged).
    WatchedFile {
        id: store
        path: root.storeFile
        onChanged: store.read()
        onLoaded: content => root.storeRead(content)
        onLoadFailed: error => root.storeRead(null)
    }

    // The store's TEXT, null when it could not be read: a change to it
    // reads the jobs again.
    function storeRead(text) {
        if (text === storeText) return;
        storeText = text;
        if (registered && canRead) readSoon.restart();
    }

    Process {
        id: copyCheck
        property var completion: null
        stdout: StdioCollector { id: copyCheckOut }
        stderr: StdioCollector { id: copyCheckErr }
        onExited: (code, status) => { completion = { code: code, status: status }; }
        onRunningChanged: {
            if (running) return;
            const done = completion;
            completion = null;
            root.unitChecked(done, copyCheckOut.text);
        }
    }

    // While a copy runs: its end has no event of its own. A new copy's start
    // wakes `checkSoon` through the exec watch, so while the watch runs the
    // poll asks only about the jobs that copy.
    Timer {
        id: copyPoll
        interval: 2000
        repeat: true
        onTriggered: root.checkCopies(execWatch.running ? "copying" : "all")
    }

    // Several opens of an engine come together when it starts (inotifywait
    // printed two for one run of a program on cachy, 2026-11-06); one
    // check follows them.
    Timer {
        id: checkSoon
        interval: 200
        onTriggered: root.checkCopies("all")
    }

    Timer {
        id: readSoon
        interval: 500
        onTriggered: root.read()
    }

    // A long-lived process that ended starts again after this.
    Timer {
        id: restartExec
        interval: 5000
        onTriggered: root.rescanEngines()
    }

    Timer {
        id: restartFollow
        interval: 5000
        onTriggered: {
            if (!root.registered || !root.canRead || managerFollow.running) return;
            managerFollow.running = true;
            // Lines the follower missed while it was down.
            root.read();
        }
    }

    // Each engine's program on PATH. realpath exits 1 when a candidate is
    // missing and prints the ones it found; --no-symlinks keeps each
    // engine's own name, and inotifywait follows a link to the program.
    Process {
        id: enginePathsRead
        property var completion: null
        command: ["realpath", "--canonicalize-existing", "--no-symlinks", "--"].concat(String(Quickshell.env("PATH") || "/usr/bin").split(":").filter(dir => dir !== "")
            .reduce((all, dir) => all.concat(Logic.ENGINES.map(engine => dir + "/" + engine)), []))
        stdout: StdioCollector { id: enginePathsOut }
        stderr: StdioCollector {}
        onExited: (code, status) => { completion = { code: code, status: status }; }
        onRunningChanged: {
            if (running) return;
            if (root.enginesAgain) {
                root.enginesAgain = false;
                running = true;
                return;
            }
            const found = [];
            for (const line of enginePathsOut.text.split("\n"))
                if (line !== "" && found.indexOf(line) === -1) found.push(line);
            root.enginePaths = found;
            if (root.registered && root.canRead) readSoon.restart();
            if (found.length === 0 || !root.canWatch || execWatch.running) return;
            execWatch.command = ["inotifywait", "--monitor", "--quiet", "--event", "open,attrib,delete_self,move_self", "--format", "%e %w", "--"].concat(found);
            execWatch.running = true;
        }
    }

    // Running a program opens its file, and inotify reports that open
    // (inotifywait on /usr/bin/true printed OPEN when it ran, cachy,
    // 2026-11-06); `--monitor` keeps the watch, one line an event. A
    // program replaced by a rename over it, as a package upgrade does,
    // reports ATTRIB and DELETE_SELF, after which its new file is not
    // watched and running it reports nothing, while inotifywait keeps
    // running (inotifywait 4.23 on a scratch program and `mv -f`, cachy,
    // 2026-11-07).
    Process {
        id: execWatch
        stdout: SplitParser {
            onRead: line => {
                if (/^OPEN(,|\s)/.test(line)) {
                    root.execRetries = 0;
                    checkSoon.restart();
                } else {
                    root.rescanEngines();
                }
            }
        }
        stderr: StdioCollector { id: execWatchErr }
        onRunningChanged: {
            root.publish();
            if (running || root.disposing) return;
            if (root.rewatch) {
                root.rewatch = false;
                root.rescanEngines();
                return;
            }
            if (!root.registered || !root.canWatch) return;
            const next = root.lost("watch", root.execRetries, execWatchErr.text);
            if (next === -1) return;
            root.execRetries = next;
            restartExec.restart();
        }
    }

    // The user manager's own lines carry USER_UNIT for the unit they are
    // about (journalctl -o json on cachy, 2026-11-06: "Finished …" with
    // USER_UNIT=scribd-brain-sync.service under _SYSTEMD_USER_UNIT=init.scope).
    Process {
        id: managerFollow
        command: ["journalctl", "--user", "--follow", "--lines=0", "--output=json", "_SYSTEMD_USER_UNIT=init.scope"]
        stdout: SplitParser {
            onRead: line => {
                root.followRetries = 0;
                if (Logic.managerLineMatters(Logic.journalEntry(line), root.jobs)) readSoon.restart();
            }
        }
        stderr: StdioCollector { id: managerErr }
        onRunningChanged: {
            if (running || root.disposing || !root.registered || !root.canRead) return;
            const next = root.lost("follow", root.followRetries, managerErr.text);
            if (next === -1) return;
            root.followRetries = next;
            restartFollow.restart();
        }
    }

    Process {
        id: remover
        property var completion: null
        stderr: StdioCollector { id: removerErr }
        onExited: (code, status) => { completion = { code: code, status: status }; }
        onRunningChanged: {
            if (running) return;
            const done = completion;
            completion = null;
            if (done === null || done.status !== 0 || done.code !== 0) {
                console.warn("local-sync: remove=failed " + root.ending(done, removerErr.text));
                root.removeProblem = "Local Sync could not stop the job. Try again.";
                root.publish();
            }
            root.read();
        }
    }
}
