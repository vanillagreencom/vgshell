"use strict";
// The selected home's package is the sole owner of asks and their state.
// This owner retains only two bounded pages and one cancellable operation.
const Child = require("./Child.js");
const SessionCommand = require("./SessionCommand.js");

const COMMAND_MS = 15000;
const OUTPUT_BYTES = 128 * 1024;
// Periodic reads pick up cross-machine changes; they are not a latency
// claim. With the console open a read is at most a minute old, the package's
// own reuse window for an unchanged list (COLLECTION_SECONDS, 60 s, in
// .agents/skills/jarvis/references/owner-asks.md § Pages), so a shorter
// period would only rerun the package to answer the same collection. With it
// closed the list is not on screen, so the read slows to five minutes. A Chat
// open and Refresh read at once either way.
const CLOSED_REFRESH_MS = 300000;
const OPEN_REFRESH_MS = 60000;
const CLOCK = { set: (fn, ms) => setTimeout(fn, ms), clear: handle => clearTimeout(handle) };

function create({ Protocol, environment, publish, answer, log, clock = CLOCK, run = Child.run, place = SessionCommand.place }) {
    let home = null;
    let generation = 0;
    let controller = null;
    let timer = null;
    let closed = false;
    let activeRequest = null;
    let consoleShown = false;
    // The last list failure logged for this home, so a failing periodic
    // read logs once per cause rather than at every poll.
    let listCause = null;
    let snapshot = { kind: "unavailable", cause: "Choose a Jarvis home folder to read your asks." };
    let cursors = { active: null, snoozed: null };
    // A refresh the shell asked for republishes its result even when
    // unchanged: the shell may have dropped its copy for room
    // (StatusPublication.js) while this one stayed ready.
    let republish = false;
    const pending = new Set();

    function show(value) {
        Protocol.ownerAsksSnapshot(value);
        // A periodic read must not flash canonical counts or remove the
        // focused row merely to publish a later observation timestamp.
        const unchanged = snapshot.kind === "ready" && value.kind === "ready"
            && JSON.stringify({ ...snapshot, observedAt: "" }) === JSON.stringify({ ...value, observedAt: "" });
        snapshot = value;
        if (!unchanged || republish) publish(value);
        republish = false;
    }

    function begin() {
        generation++;
        if (timer !== null) clock.clear(timer);
        timer = null;
        if (controller !== null) controller.abort();
        controller = new AbortController();
        return { home, generation, signal: controller.signal };
    }

    const live = token => !closed && token.home === home && token.generation === generation && !token.signal.aborted;
    function schedule() {
        timer = clock.set(() => { timer = null; refresh(false); }, consoleShown ? OPEN_REFRESH_MS : CLOSED_REFRESH_MS);
    }
    function later(token) {
        if (!live(token) || home === null) return;
        schedule();
    }
    // A list failure logs on a change of cause and once at the next complete
    // read (cause null). Actions are the user's own presses, so each failed
    // action logs.
    function report(token, verb, cause) {
        if (verb !== "list") { log("jarvis: owner-asks=" + verb + " cause=" + cause); return; }
        if (!live(token) || cause === listCause) return;
        listCause = cause;
        log("jarvis: owner-asks=list " + (cause === null ? "recovered" : "cause=" + cause));
    }
    function track(work, token, completed) {
        const settled = work.catch(error => {
            if (!live(token)) return;
            log("jarvis: owner-asks=failed cause=" + (error.code || "unexpected"));
            show({ kind: "unavailable", cause: "Your asks could not be read. Press Refresh to try again." });
        }).finally(() => {
            if (completed !== undefined) completed();
            pending.delete(settled);
            later(token);
        });
        pending.add(settled);
        return settled;
    }

    async function command(token, verb, args, input) {
        let location;
        try { location = place(token.home, environment.HOME); }
        catch (error) {
            report(token, verb, "home-unreadable");
            return { kind: "unavailable" };
        }
        if (location.kind === "blocked") return { kind: "unavailable" };
        let result;
        const childEnvironment = SessionCommand.callEnvironment(environment);
        try {
            result = await run("setpriv", ["--pdeathsig", "KILL", "--", location.command,
                "owner-asks", verb, "--home", location.folder, ...args], {
                env: childEnvironment, cwd: location.folder,
                input, deadline: COMMAND_MS, limit: OUTPUT_BYTES, group: true, signal: token.signal
            });
        } catch (error) {
            report(token, verb, "child-error");
            return { kind: verb === "list" ? "unavailable" : "unknown" };
        }
        if (!live(token)) return { kind: "stale" };
        if (result.kind !== "exited" || result.code !== 0) {
            // An older package has no owner-asks command and answers its
            // ordinary argument refusal. That is unavailable, not a fault
            // in the otherwise usable voice session.
            if (!(verb === "list" && result.kind === "exited" && result.code === 2))
                report(token, verb, result.kind === "exited" ? "exit-" + result.code : result.reason);
            return { kind: verb === "list" ? "unavailable" : "unknown" };
        }
        try {
            const text = result.stdout.trim();
            if (text.indexOf("\n") !== -1) return { kind: verb === "list" ? "unavailable" : "unknown" };
            return { kind: "value", value: JSON.parse(text) };
        } catch (error) { return { kind: verb === "list" ? "unavailable" : "unknown" }; }
    }

    async function read(token, expectedRevision) {
        const pages = {};
        for (const view of ["active", "snoozed"]) {
            const cursor = cursors[view];
            const result = await command(token, "list", ["--view", view, ...(cursor === null ? [] : ["--cursor", cursor])]);
            if (!live(token)) return;
            if (result.kind !== "value") {
                show({ kind: "unavailable", cause: "The selected Jarvis package cannot provide asks." });
                return;
            }
            try { pages[view] = Protocol.ownerAsksPage(result.value, view, cursor); }
            catch (error) {
                report(token, "list", "unaccepted");
                show({ kind: "unavailable", cause: "The ask list could not be read. Press Refresh to start again." });
                return;
            }
        }
        report(token, "list", null);
        const a = pages.active, s = pages.snoozed;
        if (a.homeId !== s.homeId || a.revision !== s.revision || a.activeCount !== s.activeCount || a.snoozedCount !== s.snoozedCount
                || expectedRevision !== null && a.revision !== expectedRevision) {
            show({ kind: "unavailable", cause: "Your asks changed while the page was read. Press Refresh to start again." });
            return;
        }
        show({ kind: "ready", homeId: a.homeId, revision: a.revision, observedAt: a.observedAt,
            activeCount: a.activeCount, snoozedCount: a.snoozedCount, active: a.rows, snoozed: s.rows,
            activeCursor: cursors.active, activeNextCursor: a.nextCursor,
            snoozedCursor: cursors.snoozed, snoozedNextCursor: s.nextCursor });
    }

    function refresh(first = true) {
        if (closed || activeRequest !== null) return;
        if (first) cursors = { active: null, snoozed: null };
        republish = first;
        const token = begin();
        if (home === null) {
            show({ kind: "unavailable", cause: "Choose a Jarvis home folder to read your asks." });
            return;
        }
        // Every Chat open asks for a first-page read. A ready first page
        // stays published while it runs, so the open's first frame draws the
        // counts it settles on; only a paged view or another home's page
        // gives way to reading.
        if (first && !(snapshot.kind === "ready" && snapshot.activeCursor === null && snapshot.snoozedCursor === null))
            show({ kind: "reading" });
        return track(read(token, null), token);
    }

    function page(view, cursor, expectedRevision) {
        if (closed || activeRequest !== null || snapshot.kind !== "ready" || snapshot.revision !== expectedRevision
                || cursor !== null && cursor !== snapshot[view + "NextCursor"]) return false;
        cursors[view] = cursor;
        const token = begin();
        show({ kind: "reading" });
        return track(read(token, expectedRevision), token);
    }

    function act(request) {
        Protocol.ownerAskAction(request);
        if (closed) return;
        request = Object.freeze({ ...request });
        if (activeRequest !== null) {
            answer({ v: 1, requestId: request.requestId, kind: "not-sent", state: null,
                cause: "Wait for the current ask action to finish." });
            return;
        }
        if (home === null) {
            answer({ v: 1, requestId: request.requestId, kind: "not-sent", state: null,
                cause: "Choose a Jarvis home folder before answering an ask." });
            return;
        }
        // The package checks requestId before revision/action availability.
        // A replay must reach it even after this child lost its old page.
        const token = begin();
        activeRequest = request.requestId;
        const work = (async () => {
            const body = { requestId: request.requestId, expectedRevision: request.expectedRevision };
            if (request.action === "later") body.until = request.until;
            else body.text = request.text;
            const result = await command(token, request.action, ["--id", request.id], JSON.stringify(body) + "\n");
            if (!live(token)) return;
            let receipt;
            try {
                if (result.kind !== "value") throw new Error("unavailable");
                receipt = Protocol.ownerAskAnswer(result.value, request.action);
                if (receipt.requestId !== request.requestId) throw new Error("identity");
            } catch (error) {
                receipt = { v: 1, requestId: request.requestId, kind: "unknown", state: null,
                    cause: "The action was not confirmed. Refresh and review the original ask before trying again." };
            }
            answer(receipt);
            cursors = { active: null, snoozed: null };
            await read(token, null);
        })();
        return track(work, token, () => { if (live(token)) activeRequest = null; });
    }

    function setHome(value) {
        if (closed || value === home && generation > 0) return;
        if (value !== home) { snapshot = { kind: "reading" }; listCause = null; }
        home = value;
        activeRequest = null;
        return refresh();
    }
    // A change of state moves the pending periodic read to the new period
    // from now; a read in flight schedules its successor when it ends.
    function setConsole(shown) {
        if (closed || shown === consoleShown) return;
        consoleShown = shown;
        if (timer === null) return;
        clock.clear(timer);
        schedule();
    }
    function close() {
        if (!closed) { closed = true; begin(); }
        return Promise.allSettled(Array.from(pending));
    }
    return { setHome, setConsole, refresh, page, act, close };
}

module.exports = { create, COMMAND_MS, OUTPUT_BYTES, CLOSED_REFRESH_MS, OPEN_REFRESH_MS };
