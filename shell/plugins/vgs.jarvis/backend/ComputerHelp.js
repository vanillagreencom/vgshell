// One on-demand owner for help: the computer-family files VGS installs, one
// regular Markdown file per family, a shared skill file of the VGS tree read
// in place, and the skills of the user's Jarvis home folder, read through
// Home.js. Browser readiness adds
// its provider to this same owner. As the one executor that holds the home,
// it also hands a request to the Jarvis session's mailbox there, through
// the mail tool kendex installs in the home (Home.mailTool), or to the
// overseer mailbox of a project kendex lists, through that project's own
// copy of the same tool. Its answer states what was read back, the row in
// the mailbox: nothing here shows that a session reads that mailbox now.
"use strict";
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const Child = require("./Child.js");
const Tools = require("./Tools.js");
const Home = require("./Home.js");
const ROOT = path.join(__dirname, "skills/computer");
const LIMIT = 8192;
// The key a failed call's cause follows, by row; a help read's otherwise.
const FAILED = { "fleet.request": "fleet-request:" };
// Each lane-mail run, the count read, the send and the read-back, ends by
// this bound: a recovery bound for a tool that hangs, not a measured
// latency.
const MAIL_MS = 3000;
// The output one run may print: a receipt and its notices, or the
// envelopes a read-back lists, the request's own text among them.
const MAIL_BYTES = 1024 * 1024;
// Past every logical line a mailbox holds, so `events` prints its header
// alone, `count=<lines> first=<id>`.
const PAST_EVERY_LINE = String(Number.MAX_SAFE_INTEGER);
// The lines lane-mail prints (its usage, Header and Receipt): the count
// header, the receipt of an appended envelope on stdout, a refusal's first
// stderr line, `lane-mail: <key>=<value> ...`, and the one refusal whose
// value follows ` id=`: `duplicate`, the identical envelope that already
// landed in the last minute, named by its id.
const HEADER = /^count=(\d+) first=/;
const RECEIPT = /^lane-mail: sent item=overseer id=([A-Za-z0-9._-]+) /m;
const DUPLICATE = /^lane-mail: duplicate id=([A-Za-z0-9._-]+)$/;
const REFUSAL = /^lane-mail: ([a-z][a-z0-9-]{0,59})=/;
// The variables lane-mail reads beside a fixed locale: its tools on PATH,
// and HOME, which git and workflow-state read. No key or other daemon
// variable reaches it.
const MAIL_ENVIRONMENT = ["PATH", "HOME"];
// What `kendex project list --json` reads beside a fixed locale: its tools
// and git on PATH, and its settings in the config folder, XDG_CONFIG_HOME or
// else HOME/.config (dirs::config_dir). No key reaches it.
const PROJECTS_ENVIRONMENT = ["PATH", "HOME", "XDG_CONFIG_HOME"];
// The states a listed project's entry takes (the producer below).
const PROJECT_STATES = ["ok", "folder-not-found", "not-a-folder", "unreadable"];
// Whether ENTRY has the shape of a listed project's entry (the producer below).
const shaped = entry => typeof entry?.folder === "string" && PROJECT_STATES.includes(entry.state)
    && (entry.worktree === null || typeof entry.worktree === "object" && !Array.isArray(entry.worktree)
        && (entry.worktree.main === null || typeof entry.worktree.main === "string"));
// Chosen read interval while an unanswered voice request exists, not a latency budget.
const ANSWER_MS = 5000;
// Recovery bound for requests a session never answers, and lane-mail's
// one-minute duplicate-send window (lane-mail usage, Receipt).
const REQUESTS = 128;
const DUPLICATE_MS = 60000;
const CLOCK = { now: Date.now, set: (fn, ms) => setTimeout(fn, ms), clear: timer => clearTimeout(timer) };

// lane-mail usage, Events and Envelope: logical numbers survive compaction.
// Read the entire snapshot before advancing any request's cursor.
function events(result) {
    if (result.kind !== "exited" || result.code !== 0) throw new Error("events-unread");
    const lines = result.stdout.trimEnd().split("\n");
    const header = /^count=(\d+) first=([A-Za-z0-9._-]*)$/.exec(lines.shift());
    if (header === null || !Number.isSafeInteger(Number(header[1]))) throw new Error("events-header");
    const count = Number(header[1]);
    let previous = 0;
    const rows = lines.map(line => {
        const row = JSON.parse(line);
        if (row === null || typeof row !== "object" || row.box !== "to-overseer" || row.count !== count
                || !Number.isSafeInteger(row.line) || row.line <= previous || row.line > count)
            throw new Error("events-row");
        previous = row.line;
        return row;
    });
    return { count, first: header[2], rows };
}
/**
 * create(root, browser, home, environment, main) builds the guidance executor.
 * home() answers the home folder's path, or null while none is usable;
 * environment is the daemon's, MAIL_ENVIRONMENT picks from it; main()
 * answers whether this computer runs the main Jarvis, Main Jarvis host
 * empty, whose session alone takes a fleet request (a satellite forwards
 * instead, Satellite.js, or not at all while its forward is unavailable).
 * answer(item), when provided, receives the first final owner notice for
 * each request, labelled as agent output. shared maps a topic of
 * Tools.HELP_TOPICS to the absolute file it is read from in place of
 * ROOT's. Browser owns sync and close;
 * neither a conversation end nor a new generation abandons a request.
 */
function create(root = ROOT, browser = null, home = () => null, environment = {}, main = () => true,
    { answer = null, log = () => {}, clock = CLOCK, run = Child.run, shared = {} } = {}) {
    let closed = false;
    let timer = null;
    let reading = null;
    let folderRead = null;
    let reader = new AbortController();
    const lifetime = new AbortController();
    // Answered ids remain only for the mail tool's duplicate window. Their
    // text is never retained here. Waiting requests own the one reader.
    const requests = new Map();
    const waiting = () => [...requests.values()].filter(item => item.kind === "waiting");
    function sync() {
        if (folderRead === null || main() && home() === folderRead) return;
        if (timer !== null) clock.clear(timer);
        timer = null;
        requests.clear();
        folderRead = null;
        reader.abort();
        reader = new AbortController();
    }
    // A shipped topic's file: ROOT's <topic>.md, or the file SHARED names
    // for it, a skill of the VGS tree read in place, as Agent Debug's
    // vgs-diagnose that its Diagnose hands over by name (D126: nothing
    // writes it into a home).
    const file = topic => Object.hasOwn(shared, topic) ? shared[topic] : path.join(root, topic + ".md");
    const shipped = Tools.HELP_TOPICS.filter(topic => {
        try { return fs.lstatSync(file(topic)).isFile(); }
        catch (error) { if (error.code === "ENOENT") return false; throw error; }
    });
    // A home whose skills cannot be listed offers none; Guidance.compose
    // reports that home to the setup view.
    function skills(folder) {
        if (folder === null) return [];
        try { return Home.skills(folder).skills.map(skill => skill.topic); }
        catch (error) {
            if (/^jarvis: home=/.test(error.message)) return [];
            throw error;
        }
    }
    // One lane-mail run on the Jarvis session's mailbox in the home FOLDER:
    // argv alone, no shell, in the home, where lane-mail finds its
    // repository. The git ceiling keeps that search in the home, whatever
    // repository holds the folder above it.
    function mail(tool, folder, args, signal = lifetime.signal) {
        const env = { LC_ALL: "C.UTF-8", GIT_CEILING_DIRECTORIES: path.dirname(folder) };
        for (const name of MAIL_ENVIRONMENT) if (environment[name] !== undefined) env[name] = environment[name];
        return run("setpriv", ["--pdeathsig", "KILL", "--", tool, ...args, "--item", "overseer", "--root", folder],
            { env, cwd: folder, limit: MAIL_BYTES, deadline: MAIL_MS, group: true, signal });
    }
    function later() {
        if (!closed && timer === null && waiting().length !== 0)
            timer = clock.set(() => { timer = null; void readAnswers(); }, ANSWER_MS);
    }
    async function readAnswers() {
        sync();
        if (closed || reading !== null || waiting().length === 0) return;
        const own = reader;
        const pending = waiting();
        const folder = folderRead;
        reading = (async () => {
            const tool = Home.mailTool(folder);
            if (tool === null) throw new Error("mail-tool-absent");
            const snapshot = events(await mail(tool, folder, ["events", "--box", "to-overseer", "--after",
                String(Math.min(...pending.map(item => item.after)))], own.signal));
            sync();
            if (closed || own !== reader) return;
            if (pending.some(item => item.first !== snapshot.first && !(item.after === 0 && item.first === "")
                    || item.after > snapshot.count)) {
                requests.clear();
                throw new Error("mailbox-replaced");
            }
            for (const row of snapshot.rows) {
                const item = pending.find(item => item.id === row.ref && row.line > item.after);
                // --progress is not the final answer. The first final owner
                // notice closes this request, not another request's notice.
                if (item === undefined || item.kind !== "waiting" || row.kind !== "notice" || row.to !== "owner"
                        || row.progress === true || typeof row.text !== "string" || row.text.trim() === "") continue;
                item.kind = "answered";
                item.until = clock.now() + DUPLICATE_MS;
                answer({ content: row.text, labels: ["agent"] });
            }
            for (const item of pending) if (item.kind === "waiting") {
                item.after = snapshot.count;
                item.first = snapshot.first;
            }
        })().catch(error => {
            if (!closed && own === reader) log("jarvis: request-answer=" + (error.message.startsWith("events-")
                || ["mail-tool-absent", "mailbox-replaced"].includes(error.message) ? error.message : "read-failed"));
        }).finally(() => { reading = null; later(); });
        await reading;
    }
    function watch(id, checkpoint, folder) {
        sync();
        if (closed || !main() || home() !== folder) return;
        folderRead = folder;
        const existing = requests.get(id);
        if (existing === undefined)
            requests.set(id, { kind: "waiting", id, after: checkpoint.count, first: checkpoint.first });
        else if (existing.kind === "answered") existing.until = clock.now() + DUPLICATE_MS;
        later();
    }
    // The exact folders of the overseer mailboxes kendex lists, or null while
    // the list is unread. The producer is `kendex project list --json`,
    // crates/cli/src/commands/project.rs (list, listed_entry) at kendex
    // v1.21.0: one array, an entry per registered project, {folder, state,
    // worktree: null | {main: path | null}}, and a non-zero exit where git
    // cannot answer. A worktree entry stands for its main checkout, where
    // the overseer mailbox is (KEN-3734): its own folder is no destination,
    // nor is one whose main git could not name. Any entry of another shape
    // leaves the whole list unread, since a set read in part decides nothing.
    async function projects() {
        const env = { LC_ALL: "C.UTF-8" };
        for (const name of PROJECTS_ENVIRONMENT) if (environment[name] !== undefined) env[name] = environment[name];
        const listed = await run("setpriv", ["--pdeathsig", "KILL", "--", "kendex", "project", "list", "--json"],
            { env, cwd: "/", limit: MAIL_BYTES, deadline: MAIL_MS, group: true, signal: lifetime.signal });
        if (listed.kind !== "exited" || listed.code !== 0) return null;
        let entries;
        try { entries = JSON.parse(listed.stdout); } catch { return null; }
        if (!Array.isArray(entries)) return null;
        const found = new Set();
        for (const entry of entries) {
            if (!shaped(entry)) return null;
            const destination = entry.worktree === null ? entry.folder : entry.worktree.main;
            if (entry.state === "ok" && destination !== null) found.add(destination);
        }
        return found;
    }
    // The cause of a run that refused before it appended anything: its
    // keyed first stderr line, else OTHER.
    const refusal = (result, other) =>
        (result.kind === "exited" && REFUSAL.exec(result.stderr.split("\n")[0])?.[1]) || other;
    const failed = cause => ({ outcome: "failed", content: FAILED["fleet.request"] + cause });
    // Hand TEXT to the Jarvis session's mailbox with the home's mail tool,
    // or, where PROJECT names one kendex lists now, to that project's
    // overseer mailbox with its own (write only: no answer is watched for
    // there), found again here: the mailbox's count, then the send, its
    // text in a private file, then the rows past that count read back; for a send
    // lane-mail refuses as a duplicate, the whole mailbox, where the row it
    // names landed before the count. A run that ended before it could
    // append is failed; one that may have appended and did not read back is
    // unknown.
    async function request(text, project) {
        if (closed) return failed("closed");
        sync();
        // A request held while the user named a main goes nowhere: the
        // satellite's route is fleet.forward.
        if (!main()) return failed("satellite");
        if (project !== undefined) {
            const listed = await projects();
            if (listed === null) return failed("projects-unread");
            if (!listed.has(project)) return failed("project-unlisted");
        }
        const folder = project === undefined ? home() : project;
        if (folder === null) return failed("home-unchosen");
        const tool = Home.mailTool(folder, project !== undefined);
        if (tool === null) return failed("mail-tool-absent");
        const counted = await mail(tool, folder, ["events", "--box", "to-lane", "--after", PAST_EVERY_LINE]);
        const header = counted.kind === "exited" && counted.code === 0 ? HEADER.exec(counted.stdout) : null;
        if (header === null) return failed(refusal(counted, "mailbox-unread"));
        let checkpoint = null;
        if (answer !== null && project === undefined) {
            for (const [id, item] of requests) if (item.kind === "answered" && item.until <= clock.now()) requests.delete(id);
            if (requests.size >= REQUESTS) return failed("requests-full");
            try { checkpoint = events(await mail(tool, folder, ["events", "--box", "to-overseer", "--after", PAST_EVERY_LINE])); }
            catch { return failed("answers-unread"); }
        }
        // A project request names its own folder: only the home's can change.
        if (closed || !main() || project === undefined && home() !== folder)
            return failed(project === undefined ? "home-changed" : closed ? "closed" : "satellite");
        const box = project === undefined ? "the Jarvis session's mailbox" : "the mailbox of " + project;
        const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "vgs-jarvis-request-"));
        let sent;
        try {
            const file = path.join(scratch, "request.txt");
            fs.writeFileSync(file, text, { mode: 0o600, flag: "wx" });
            sent = await mail(tool, folder, ["send", "--directive", "--file", file]);
        } finally { fs.rmSync(scratch, { recursive: true, force: true }); }
        if (sent.kind === "error") return failed("mail-tool-" + sent.reason);
        let id = sent.kind === "exited" ? RECEIPT.exec(sent.stdout)?.[1] : undefined;
        let after = header[1];
        const refused = sent.kind === "exited" && sent.code !== null && sent.code !== 0 && id === undefined;
        const duplicate = refused ? DUPLICATE.exec(sent.stderr.split("\n")[0])?.[1] : undefined;
        if (duplicate !== undefined) {
            id = duplicate;
            after = "0";
        // Any other refusal exits with a code and prints no receipt: nothing was appended.
        } else if (refused) return failed(refusal(sent, "send-refused"));
        // A run the bound or a signal ended, or a receipt beside a failed
        // exit, or an exit 0 with none, may have appended.
        else if (sent.kind !== "exited" || sent.code !== 0 || id === undefined)
            return { outcome: "unknown", content: "Unknown: lane-mail ended without a receipt, so the request may be in " + box + " or not." };
        // A duplicate may already have its answer before this checkpoint.
        if (checkpoint !== null) watch(id, duplicate === undefined ? checkpoint : { ...checkpoint, count: 0 }, folder);
        const back = await mail(tool, folder, ["events", "--box", "to-lane", "--after", after]);
        const rows = back.kind === "exited" && back.code === 0 ? back.stdout.split("\n").slice(1) : [];
        const found = rows.some(line => {
            try { return JSON.parse(line).id === id; } catch { return false; }
        });
        return found
            ? { outcome: "completed", content: "Completed: the request is in " + box + " as row " + id + ". The session acts on it when it next reads its mail." }
            : { outcome: "unknown", content: "Unknown: lane-mail sent the request as row " + id + ", but the row did not read back from " + box + "." };
    }
    return { commands: [], timeoutMs: Math.max(browser === null ? 2000 : browser.timeoutMs, 4 * MAIL_MS + 1000), cancellable: false,
        sync,
        close() {
            closed = true;
            if (timer !== null) clock.clear(timer);
            timer = null;
            requests.clear();
            reader.abort();
            lifetime.abort();
            return reading;
        },
        // Read at each offer: the user adds a skill without a restart.
        topics: () => shipped.concat(skills(home())),
        // And the mail tool and the Jarvis session's mailbox at each offer:
        // the user installs the tool from Setup, and the Jarvis session
        // makes its mailbox when it first reads this folder's mail.
        fleet() {
            if (!main()) return false;
            const folder = home();
            return folder !== null && Home.mailTool(folder) !== null && Home.mailbox(folder);
        },
        // Verified readiness extends the offer once.
        enableBrowser() {
            if (browser === null) throw new Error("help-browser-unavailable");
            if (!shipped.includes("browser")) shipped.push("browser");
        },
        start(call, done) {
            let fd;
            try {
                if (call.id === "fleet.request") {
                    request(call.args.text, call.args.project).then(done, error => done(failed(error.code || error.message)));
                    return;
                }
                const topic = call.args.topic;
                if (Tools.homeTopic(topic) !== null) {
                    const folder = home();
                    if (folder === null) throw new Error("help-topic-unavailable");
                    const text = Home.skill(folder, topic).trim();
                    if (text === "") throw new Error("help-file-empty");
                    done({ outcome: "completed", content: text });
                    return;
                }
                if (!shipped.includes(topic)) throw new Error("help-topic-unavailable");
                if (topic === "browser" && browser !== null) { browser.start(call, done); return; }
                fd = fs.openSync(file(topic), fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW);
                if (!fs.fstatSync(fd).isFile()) throw new Error("help-file-invalid");
                const buffer = Buffer.alloc(LIMIT + 1);
                const size = fs.readSync(fd, buffer);
                if (size > LIMIT) throw new Error("help-file-too-large");
                const content = new TextDecoder("utf-8", { fatal: true }).decode(buffer.subarray(0, size)).trim();
                if (content === "") throw new Error("help-file-empty");
                done({ outcome: "completed", content });
            } catch (error) { done({ outcome: "failed", content: (FAILED[call.id] ?? "help-read:") + (error.code || error.message) }); }
            finally { if (fd !== undefined) fs.closeSync(fd); }
        } };
}
module.exports = { create };
