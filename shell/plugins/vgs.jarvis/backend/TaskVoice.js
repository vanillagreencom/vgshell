// What Jarvis says about a coding task, and where it says it. The judges
// turn a held hook prompt, a change in a task's derived state and the
// user's spoken answer into fixed sentences and typed answers; no model
// writes them, and the brain never sees a held prompt or its answer. The
// owner delivers each sentence once: spoken in an open chained conversation
// at its next idle moment, else as a desktop notification (plan § 4.4).
// A turn end is never a finished task: "done" is only the agent's report.
"use strict";

const TITLE = "Coding task";
// TaskRelay's bound on a reply's text.
const MAX_REPLY = 4096;
const CONTROL = /[\x00-\x09\x0b-\x1f\x7f]/g;
const ALLOW = ["allow", "yes", "yes allow"];
const DENY = ["deny", "no", "no deny"];
const REPORTED = { "reported-ok": "the task done", "reported-failed": "the task failed" };
const WAITING = "The coding agent stopped and is waiting.";
// How often one conversation asks one prompt. A second ask follows a
// release of the first; after it the prompt is left to the console.
const ASKS = 2;

function fail(reason) { throw new Error("jarvis: task-voice=" + reason); }

// The agent's text as one sentence of Jarvis's line.
function quoted(text) {
    const flat = String(text).replace(/\s+/g, " ").trim();
    return /[.!?…]$/.test(flat) ? flat : flat + ".";
}

// How a prompt line ends on each channel. A spoken line takes the user's
// next words; a notification card cannot hear them, so it sends the user
// to Jarvis.
const ENDINGS = Object.freeze({
    voice: Object.freeze({ question: "Your next words are its answer.", permission: "Say allow or deny." }),
    notification: Object.freeze({ question: "Talk to Jarvis to answer.", permission: "Talk to Jarvis to answer." })
});

/** The line that asks the user one held prompt on channel "voice" or "notification". */
function promptLine(prompt, channel) {
    if (!Object.hasOwn(ENDINGS, channel)) fail("channel value=" + channel);
    const text = String(prompt.text).trim();
    switch (prompt.kind) {
    case "question":
        return (text === "" ? "The coding agent asks a question." : "The coding agent asks: " + quoted(text))
            + " " + ENDINGS[channel].question;
    case "permission":
        return "The coding agent asks to use " + prompt.tool + (text === "" ? "." : ": " + quoted(text))
            + " " + ENDINGS[channel].permission;
    default:
        fail("prompt-kind");
    }
}

function reported(view) {
    if (view.outcome.kind === "none") return null;
    if (!Object.hasOwn(REPORTED, view.outcome.kind)) fail("outcome value=" + view.outcome.kind);
    return REPORTED[view.outcome.kind];
}

// The sentence a derived view stands for, or null. A held prompt is asked
// from the relay index, not from its wait fact.
function stateLine(view) {
    const report = reported(view);
    switch (view.state) {
    case "starting":
    case "working":
    case "noisy":
        return null;
    case "waiting":
        return view.wait.kind === "none" || view.wait.kind === "idle" ? WAITING : null;
    case "reported-ok": return "The coding agent reports the task done.";
    case "reported-failed": return "The coding agent reports the task failed.";
    case "failed":
        return report === null ? "The coding agent failed without reporting an outcome."
            : "The coding agent failed after it reported " + report + ".";
    case "exited": return "The coding agent exited without reporting an outcome.";
    case "lost":
        return report === null ? "The coding agent's process was lost without an outcome."
            : "The coding agent's process was lost after it reported " + report + ".";
    case "stopped": return "The coding task was stopped.";
    default:
        fail("state value=" + view.state);
    }
}

/**
 * The one sentence for one task's change between two Tasks.derive views, or
 * null. before is null for a task first seen.
 */
function outcomeLine(before, after) {
    const line = stateLine(after);
    return line !== null && (before === null || stateLine(before) !== line) ? line : null;
}

/** The phrase a spoken approval is judged by: case, edge space and end punctuation dropped. */
function phrase(text) {
    return String(text).trim().toLowerCase().replace(/[.!?]+$/, "");
}

/** The user's words as an answer TaskRelay takes for prompt, or null. */
function answerOf(prompt, text) {
    switch (prompt.kind) {
    case "permission": {
        const said = phrase(text);
        return ALLOW.includes(said) ? { v: 1, kind: "allow" } : DENY.includes(said) ? { v: 1, kind: "deny" } : null;
    }
    case "question": {
        const reply = String(text).replace(CONTROL, " ").trim().slice(0, MAX_REPLY);
        return reply === "" ? null : { v: 1, kind: "reply", text: reply };
    }
    default:
        fail("prompt-kind");
    }
}

// keep: the conversation still holds the prompt, so the next words answer it.
const line = (text, labels, keep) => ({ text, labels, keep });

/** What Jarvis says when the user's words answer no prompt: ask again. */
function retry(prompt) {
    return prompt.kind === "permission" ? line("Say allow or deny.", ["desktop"], true) : line(promptLine(prompt, "voice"), ["agent"], true);
}

/** What Jarvis says after the relay judged the answer to prompt. */
function answered(prompt, result) {
    switch (result) {
    case "answered": return line("I sent your answer to the coding agent.", ["desktop"], false);
    case "prompt-unknown":
    case "prompt-expired":
    case "answered-already":
        return line("The coding agent no longer waits for that answer.", ["desktop"], false);
    case "answer-invalid": return retry(prompt);
    case "session-locked":
    case "daemon-ending":
        return line("I could not send your answer to the coding agent.", ["desktop"], true);
    default:
        fail("answer-result value=" + result);
    }
}

const key = prompt => prompt.task + "/" + prompt.id;

/**
 * create({session, state, dispatch, notify, log, defer}) delivers the task
 * lines of one daemon. session is the Session judge, state() its current
 * record and dispatch its event entry. notify(title, body, signal) runs one
 * desktop notification and answers a Promise of a Child.run result, or null
 * when notify-send is absent. log takes one keyed line. defer runs a function
 * after the current dispatch, so a relay event meets the state it was judged on.
 *
 * observe(views) takes TaskRunner's derived tasks; the first call only
 * seeds, so a restart says nothing about old states. prompts(list) takes the
 * held prompts, session(s) every published state. A conversation asks one
 * prompt at a time: an asked prompt holds its next words until the prompt
 * leaves the held list, so a second prompt cannot take an answer meant for
 * the first. A prompt counts as asked once its line is dispatched, so no
 * path that ends a relay turn early can ask it again and again. The engine
 * reports a prompt line cut off before its end with interrupted(gen, ask),
 * which asks it again or, once the conversation ended, notifies it; a prompt
 * whose words went to the brain after one re-ask with released(gen, ask);
 * and a line kept from speech or cut off with withheld(gen, text, ask), which
 * notifies it: a prompt's card is its notification line, any other line's
 * card is its text.
 */
function create({ session, state, dispatch, notify, log, defer = queueMicrotask }) {
    // Per task, the facts of the view last seen; null before the first observation.
    let seen = null;
    let held = [];
    // Lines waiting for an idle moment of the conversation gen they were made in.
    let queue = [];
    // Per prompt this conversation asked: how often, and whether it holds
    // the conversation's next words.
    let asked = { gen: null, prompts: new Map() };
    // Prompts the user was told about, by voice or by notification.
    const told = new Set();
    let scheduled = false;
    let missing = false;
    let closed = false;
    let notifying = Promise.resolve();
    const abort = new AbortController();

    function send(text) {
        notifying = notifying.then(async () => {
            if (closed) return;
            const run = notify(TITLE, text, abort.signal);
            if (run === null) {
                if (!missing) log("jarvis: task-voice=notify-missing");
                missing = true;
                return;
            }
            const result = await run;
            if (!closed && (result.kind !== "exited" || result.code !== 0))
                log("jarvis: task-voice=notify-failed result=" + result.kind + (result.kind === "exited" ? " code=" + result.code : ""));
        }).catch(error => {
            if (!closed) log("jarvis: task-voice=notify-failed cause=" + (error.code || "error"));
        });
    }

    const open = refusal => refusal === null || refusal === "busy";
    const entry = name => asked.prompts.get(name) ?? { count: 0, open: false };
    function unasked() {
        if (held.some(prompt => entry(key(prompt)).open)) return null;
        return held.find(prompt => entry(key(prompt)).count < ASKS) ?? null;
    }

    function pump() {
        if (closed) return;
        const s = state();
        const refusal = session.relayRefusal(s);
        if (!open(refusal)) {
            for (const item of queue.splice(0)) send(item.text);
            for (const prompt of held) {
                if (told.has(key(prompt))) continue;
                told.add(key(prompt));
                send(promptLine(prompt, "notification"));
            }
            return;
        }
        // A line whose conversation ended unspoken is told the other way.
        for (const item of queue) if (item.gen !== s.gen) send(item.text);
        queue = queue.filter(item => item.gen === s.gen);
        if (asked.gen !== s.gen) asked = { gen: s.gen, prompts: new Map() };
        if (refusal === null && !scheduled && (queue.length > 0 || unasked() !== null)) {
            scheduled = true;
            defer(speak);
        }
    }

    // Runs outside the runner's drain: the relay event is judged against
    // the state read here, so Session takes it.
    function speak() {
        scheduled = false;
        if (closed) return;
        const s = state();
        if (session.relayRefusal(s) !== null || asked.gen !== s.gen) return;
        if (queue.length > 0) {
            dispatch({ type: "relay", text: queue.shift().text, ask: null });
            return;
        }
        const prompt = unasked();
        if (prompt === null) return;
        asked.prompts.set(key(prompt), { count: entry(key(prompt)).count + 1, open: true });
        told.add(key(prompt));
        dispatch({ type: "relay", text: promptLine(prompt, "voice"), ask: { task: prompt.task, prompt: prompt.id, kind: prompt.kind } });
    }

    return Object.freeze({
        observe(views) {
            if (closed) return;
            const facts = new Map(views.map(view => [view.id, { state: view.state, wait: view.wait, outcome: view.outcome }]));
            if (seen !== null) {
                const gen = state().gen;
                for (const [id, view] of facts) {
                    const text = outcomeLine(seen.get(id) ?? null, view);
                    if (text !== null) queue.push({ text, gen });
                }
            }
            seen = facts;
            pump();
        },
        prompts(list) {
            if (closed) return;
            held = list;
            const live = new Set(list.map(key));
            for (const name of told) if (!live.has(name)) told.delete(name);
            pump();
        },
        session: pump,
        interrupted(gen, ask) {
            const name = ask.task + "/" + ask.prompt;
            if (closed || gen !== asked.gen || !asked.prompts.has(name)) return;
            asked.prompts.set(name, { count: entry(name).count - 1, open: false });
            told.delete(name);
        },
        released(gen, ask) {
            const name = ask.task + "/" + ask.prompt;
            if (closed || gen !== asked.gen || !asked.prompts.has(name)) return;
            asked.prompts.set(name, { count: entry(name).count, open: false });
        },
        withheld(gen, text, ask) {
            if (closed) return;
            // A prompt the release gate keeps from this conversation is not asked in it again.
            if (ask === null) {
                send(text);
                return;
            }
            const name = ask.task + "/" + ask.prompt;
            if (gen === asked.gen) asked.prompts.set(name, { count: ASKS, open: false });
            const prompt = held.find(item => key(item) === name);
            // A prompt that left the relay index needs no answer.
            if (prompt !== undefined) send(promptLine(prompt, "notification"));
        },
        close() {
            closed = true;
            queue = [];
            abort.abort();
        }
    });
}

module.exports = { promptLine, outcomeLine, answerOf, phrase, retry, answered, create, TITLE };
