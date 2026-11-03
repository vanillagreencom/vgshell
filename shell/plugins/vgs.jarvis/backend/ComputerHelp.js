// One on-demand owner for help: the computer-family files VGS installs, one
// regular Markdown file per family, and the skills of the user's Jarvis home
// folder, read through Home.js. Browser readiness adds
// its provider to this same owner. As the one executor that holds the home,
// it also hands a request to the Jarvis session's mailbox there, through
// the mail tool kendex installs in the home (Home.mailTool). Its answer
// states what was read back, the row in the mailbox: nothing here shows that
// a session reads that mailbox now.
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
/**
 * create(root, browser, home, environment, main) builds the guidance executor.
 * home() answers the home folder's path, or null while none is usable;
 * environment is the daemon's, MAIL_ENVIRONMENT picks from it; main()
 * answers whether this machine runs the main Jarvis, whose session alone
 * takes a fleet request (a satellite forwards instead, Satellite.js).
 */
function create(root = ROOT, browser = null, home = () => null, environment = {}, main = () => true) {
    const shipped = Tools.HELP_TOPICS.filter(topic => {
        try { return fs.lstatSync(path.join(root, topic + ".md")).isFile(); }
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
    function mail(tool, folder, args) {
        const env = { LC_ALL: "C.UTF-8", GIT_CEILING_DIRECTORIES: path.dirname(folder) };
        for (const name of MAIL_ENVIRONMENT) if (environment[name] !== undefined) env[name] = environment[name];
        return Child.run("setpriv", ["--pdeathsig", "KILL", "--", tool, ...args, "--item", "overseer", "--root", folder],
            { env, cwd: folder, limit: MAIL_BYTES, deadline: MAIL_MS, group: true });
    }
    // The cause of a run that refused before it appended anything: its
    // keyed first stderr line, else OTHER.
    const refusal = (result, other) =>
        (result.kind === "exited" && REFUSAL.exec(result.stderr.split("\n")[0])?.[1]) || other;
    const failed = cause => ({ outcome: "failed", content: FAILED["fleet.request"] + cause });
    // Hand TEXT to the Jarvis session's mailbox with the home's mail tool,
    // found again here: the mailbox's count, then the send, its text in a
    // private file, then the rows past that count read back; for a send
    // lane-mail refuses as a duplicate, the whole mailbox, where the row it
    // names landed before the count. A run that ended before it could
    // append is failed; one that may have appended and did not read back is
    // unknown.
    async function request(text) {
        // A request held while the user named another main goes nowhere:
        // the satellite's route is fleet.forward.
        if (!main()) return failed("satellite");
        const folder = home();
        if (folder === null) return failed("home-unchosen");
        const tool = Home.mailTool(folder);
        if (tool === null) return failed("mail-tool-absent");
        const counted = await mail(tool, folder, ["events", "--box", "to-lane", "--after", PAST_EVERY_LINE]);
        const header = counted.kind === "exited" && counted.code === 0 ? HEADER.exec(counted.stdout) : null;
        if (header === null) return failed(refusal(counted, "mailbox-unread"));
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
            return { outcome: "unknown", content: "Unknown: lane-mail ended without a receipt, so the request may be in the Jarvis session's mailbox or not." };
        const back = await mail(tool, folder, ["events", "--box", "to-lane", "--after", after]);
        const rows = back.kind === "exited" && back.code === 0 ? back.stdout.split("\n").slice(1) : [];
        const found = rows.some(line => {
            try { return JSON.parse(line).id === id; } catch { return false; }
        });
        return found
            ? { outcome: "completed", content: "Completed: the request is in the Jarvis session's mailbox as row " + id + ". The session acts on it when it next reads its mail." }
            : { outcome: "unknown", content: "Unknown: lane-mail sent the request as row " + id + ", but the row did not read back from the Jarvis session's mailbox." };
    }
    return { commands: [], timeoutMs: Math.max(browser === null ? 2000 : browser.timeoutMs, 3 * MAIL_MS + 1000), cancellable: false,
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
                    request(call.args.text).then(done, error => done(failed(error.code || error.message)));
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
                fd = fs.openSync(path.join(root, topic + ".md"), fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW);
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
