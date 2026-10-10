// TTS input boundary for chained consumers. create(language, reply) owns a
// text stream: push(chunk) and finish() return sentence arrays; counts()
// returns detected violations without retaining a transcript. Of a brain's
// reply, the stream create makes with reply, only the sentences leave it: an
// element's content, a JSON value, code, a table row and a sentence that
// names a tool are silent, and the prose around them is spoken. Any other
// text keeps its words: a task's line can hold the command a user is asked
// to allow. violations(text, language) measures a final duplex transcript.
// It never receives audio.
// Limits are allocation bounds in UTF-16 code units, not latency budgets.
// Any overflow throws, clears retained text and makes the stream unusable.
// element is how much text a reply's open element holds back while its
// closing tag may still come: the wait a stray tag costs, kept short.
"use strict";
const { languageCode, expand } = require("./SpeechLanguage.js");
const LIMITS = Object.freeze({ chunk: 16384, token: 4096, sentence: 4096, output: 65536, element: 256 });
const KINDS = ["markdown", "code", "url", "path", "symbol", "number", "unit", "date", "time"];
const URL_START = /^(?:[A-Za-z][A-Za-z0-9+.-]*:\/\/|www\.|mailto:)/u;
// A brain can split any URI scheme across tokens. Hold one possible scheme
// until punctuation/whitespace disproves it, rather than maintain a scheme list.
const SCHEME_PART = /^[A-Za-z][A-Za-z0-9+.-]*(?::\/{0,2})?$/u;
const ABBREVIATIONS = /(?:\b(?:Mr|Mrs|Ms|Dr|Prof|Sr|Sra|Srta|Ud|Uds)|\b[A-Z])\.$/u;
// The first value of a JSON array of bare values, to the "," or "]" that
// ends it, and a prefix of one.
const JSON_SCALAR = /^(?:-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?|true|false|null)\s*([,\]])(.?)/su;
const JSON_SCALAR_PART = /^(?:-?[\d.eE+-]*|t(?:r(?:ue?)?)?|f(?:a(?:l(?:se?)?)?)?|n(?:u(?:ll?)?)?)\s*$/u;
const PROSE = Object.freeze({ kind: "prose" });

// Judge both complete tags and prefixes of the tag grammar. An impossible
// prefix is prose immediately; only an unfinished valid token stays pending.
// With xml, a brain's reply, a tag name is an XML name: letters, digits, "_",
// "-" and ":", with "." between them; without it, an HTML name. element is
// the name of a tag that opens an element, null for a closing tag, a
// self-closing one and a comment.
function htmlCandidate(text, xml) {
    if ("<!--".startsWith(text)) return { kind: "pending" };
    if (text.startsWith("<!--")) {
        const end = text.indexOf("-->", 4);
        return end < 0 ? { kind: "pending" } : { kind: "tag", length: end + 3, element: null };
    }
    const head = (xml ? /^<\/?[A-Za-z_:][A-Za-z0-9_:-]*(?:\.[A-Za-z0-9_:-]+)*/u : /^<\/?[A-Za-z][A-Za-z0-9:-]*/u).exec(text);
    if (head === null) return { kind: text === "<" || text === "</" ? "pending" : "prose" };
    let at = head[0].length;
    while (at < text.length) {
        const end = /^\/?>/u.exec(text.slice(at));
        if (end !== null) return { kind: "tag", length: at + end[0].length,
            element: end[0] === ">" && !text.startsWith("</") ? head[0].slice(1) : null };
        if (text.slice(at) === "/" || xml && text.slice(at) === ".") return { kind: "pending" };
        const space = /^\s+/u.exec(text.slice(at));
        if (space === null) return { kind: "prose" };
        at += space[0].length;
        if (at === text.length) break;
        if (text[at] === ">" || text[at] === "/") continue;
        if (text.startsWith("</")) return { kind: "prose" };
        const name = /^[A-Za-z_:][A-Za-z0-9_:-]*/u.exec(text.slice(at));
        if (name === null) return { kind: "prose" };
        at += name[0].length;
        const assign = /^\s*=\s*/u.exec(text.slice(at));
        if (assign === null) continue;
        at += assign[0].length;
        if (at === text.length) break;
        const quote = text[at];
        if (quote === '"' || quote === "'") {
            const close = text.indexOf(quote, at + 1);
            if (close < 0) return { kind: "pending" };
            at = close + 1;
        } else {
            const value = /^[^\s"'=<>`]+/u.exec(text.slice(at));
            if (value === null) return { kind: "prose" };
            at += value[0].length;
        }
    }
    return { kind: "pending" };
}

// Whether text, which starts with "{" or "[", opens a JSON value: "json",
// "prose", or "pending" while its first token is unfinished. Prose holds
// neither `{"` nor `[{`, so that token decides an object and an array of
// objects, strings or arrays. An array of bare values is judged at its first
// value's end, and one a "(" follows is a Markdown link's label.
function jsonCandidate(text, final) {
    const rest = text.slice(1).replace(text[0] === "{" ? /^\s+/u : /^[\[\s]+/u, "");
    if (rest === "") return final ? "prose" : "pending";
    if (rest[0] === '"' || rest[0] === (text[0] === "{" ? "}" : "]")) return "json";
    if (text[0] === "{") return "prose";
    if (rest[0] === "{") return "json";
    const scalar = JSON_SCALAR.exec(rest);
    if (scalar === null) return !final && JSON_SCALAR_PART.test(rest) ? "pending" : "prose";
    if (scalar[1] === "," || scalar[2] !== "") return scalar[2] === "(" && scalar[1] === "]" ? "prose" : "json";
    return final ? "json" : "pending";
}

function siteName(raw) {
    try {
        const parsed = new URL(raw.startsWith("www.") ? "https://" + raw : raw);
        const host = parsed.protocol === "mailto:" ? parsed.pathname.split("@").at(-1) : parsed.hostname;
        // A spoken site label, not an authority or a public-suffix judge.
        const parts = host.replace(/^www\./, "").split(".");
        return parts.length > 1 ? parts.slice(0, -1).join(" ") : host;
    } catch {
        // A model can emit a malformed URL. Never send its address to TTS.
        return "";
    }
}

/**
 * Own one text stream. The engine sends only returned strings to TTS.
 * reply is null, or {tools} for a brain's reply, the one text the element,
 * JSON, table and tool rules read. tools is every name a brain may know a
 * tool by. A one-word name, as help is, reads as an ordinary word, so only a
 * name with "." or "_" marks a sentence as a status line.
 */
function create(language, reply = null) {
    const code = languageCode(language);
    const names = reply === null ? [] : reply.tools.filter(name => /[._]/u.test(name));
    let pending = "";
    let sentence = "";
    // prose; code to its fence; element to its closing tag; json to the end
    // of its value; row to the end of its line; status to the end of its
    // sentence or line.
    let mode = PROSE;
    let lifecycle = "open";
    const counts = Object.fromEntries(KINDS.map(kind => [kind, 0]));

    function note(kind) {
        if (!Object.hasOwn(counts, kind)) throw new Error("jarvis: speakable=violation-kind");
        if (counts[kind] === Number.MAX_SAFE_INTEGER) throw new Error("jarvis: speakable=count-overflow");
        counts[kind]++;
    }
    function bound(text, size, name) {
        if (text.length > size) throw new Error("jarvis: speakable=" + name + "-overflow");
    }
    function emit(raw, output) {
        let text = expand(raw, code, note);
        text = text.replace(/[^\p{L}\p{M}\p{N}\s.,!?¿¡;:'’"()-]/gu, () => { note("symbol"); return " "; })
            .replace(/\s+/gu, " ").replace(/\s+([.,!?;:])/gu, "$1").trim();
        // Do not offer a punctuation-only "sentence" to the speech adapter.
        if (!/[\p{L}\p{N}]/u.test(text)) return;
        output.push(text);
        if (output.reduce((size, item) => size + item.length, 0) > LIMITS.output)
            throw new Error("jarvis: speakable=output-overflow");
    }
    function plain(text, output) {
        sentence += text;
        bound(sentence, LIMITS.sentence, "sentence");
        // Lookahead keeps a fragmented decimal point or final punctuation
        // pending until whitespace arrives. Code and URLs never enter here.
        let from = 0;
        for (;;) {
            const cut = /[.!?]+(?=\s)/u.exec(sentence.slice(from));
            if (cut === null) break;
            const end = from + cut.index + cut[0].length;
            if (cut[0] === "." && ABBREVIATIONS.test(sentence.slice(0, end))) { from = end; continue; }
            emit(sentence.slice(0, end), output);
            sentence = sentence.slice(end).trimStart();
            from = 0;
        }
    }
    // Whether the spoken text so far ends outside a word, so the next
    // character starts one.
    const wordStart = () => !/[\p{L}\p{N}]$/u.test(sentence);
    // Whether pending starts with a tool's name: "tool", "none", or "pending"
    // while more text could finish one. A caller asks only at a word's
    // start, after a character that is no letter and no digit, so the prefix
    // a harness gives a name, which ends in "_" or "-", hides none.
    function toolAt(final) {
        let open = false;
        for (const name of names) {
            if (!pending.startsWith(name)) open ||= name.startsWith(pending);
            else if (pending.length === name.length ? final : !/[\p{L}\p{N}_]/u.test(pending[name.length])) return "tool";
            else open ||= pending.length === name.length;
        }
        return open && !final ? "pending" : "none";
    }
    // A sentence that names a tool says what Jarvis does, not what the user
    // asked for. The words of its line not yet spoken go with it.
    function status() {
        note("code");
        sentence = sentence.slice(0, sentence.lastIndexOf("\n") + 1);
        mode = { kind: "status" };
    }
    function drain(final, output) {
        while (pending !== "") {
            switch (mode.kind) {
            case "prose": break;
            case "code":
                // A name in a code span marks a status line as a bare one
                // does. A fenced block is no line of the reply: it stays
                // code to its fence.
                if (mode.span && !mode.word) {
                    const named = toolAt(final);
                    if (named === "pending") return;
                    if (named === "tool") { status(); continue; }
                }
                if (pending.startsWith(mode.fence)) { pending = pending.slice(mode.fence.length); mode = PROSE; plain(" ", output); }
                else if (!final && mode.fence.startsWith(pending)) return;
                else { mode.word = /[\p{L}\p{N}]/u.test(pending[0]); pending = pending.slice(1); }
                continue;
            case "element": {
                // The first closing tag of the name, in any letter case, ends
                // the element, and its content is never spoken. A tag with
                // no closing tag within the bound, or by the reply's end
                // (run), opened no element: the text kept since it is read
                // again as prose, by every other rule, so a stray tag costs
                // a short wait and no words, and a tool call's JSON stays
                // silent by its own rule.
                const rest = pending.slice(mode.closer.length);
                if (pending.toLowerCase().startsWith(mode.closer)) {
                    const end = /^\s*>/u.exec(rest);
                    if (end !== null) { pending = rest.slice(end[0].length); mode = PROSE; plain(" ", output); continue; }
                    if (!final && rest.trim() === "") return;
                } else if (!final && mode.closer.startsWith(pending.toLowerCase())) return;
                if (mode.held.length === LIMITS.element) { pending = mode.held + pending; mode = PROSE; continue; }
                mode.held += pending[0];
                pending = pending.slice(1);
                continue;
            }
            case "json": {
                // Only strings and brackets are read: a value that never
                // balances stays silent to the end of the reply.
                const char = pending[0];
                pending = pending.slice(1);
                if (mode.quoted) {
                    if (mode.escaped) mode.escaped = false;
                    else if (char === "\\") mode.escaped = true;
                    else if (char === '"') mode.quoted = false;
                } else if (char === '"') mode.quoted = true;
                else if (char === "{" || char === "[") mode.depth++;
                else if ((char === "}" || char === "]") && --mode.depth === 0) { mode = PROSE; plain(" ", output); }
                continue;
            }
            case "row":
                if (pending[0] !== "\n") pending = pending.slice(1);
                else mode = PROSE;
                continue;
            case "status": {
                const stop = /^(?:\n|[.!?]+(?=\s))/u.exec(pending);
                if (stop !== null) { pending = pending.slice(stop[0] === "\n" ? 0 : stop[0].length); mode = PROSE; continue; }
                if (!final && /^[.!?]+$/u.test(pending)) return;
                pending = pending.slice(1);
                continue;
            }
            default: throw new Error("jarvis: speakable=mode");
            }
            const first = pending[0];
            // A chunk may end inside a UTF-16 pair. Preserve it for the next.
            if (!final && pending.length === 1 && /[\uD800-\uDBFF]/u.test(first)) return;
            if (names.length !== 0 && wordStart()) {
                const named = toolAt(final);
                if (named === "pending") return;
                if (named === "tool") { status(); continue; }
            }
            const ticks = /^(`+|~{3,})/.exec(pending);
            if (ticks) {
                if (!final && ticks[0].length === pending.length) return;
                pending = pending.slice(ticks[0].length);
                mode = { kind: "code", fence: ticks[0], span: /^`{1,2}$/u.test(ticks[0]), word: false };
                note("code");
                continue;
            }
            if (!final && /^~{1,2}$/.test(pending)) return;
            if (first === "<") {
                // Angle-wrapped URLs are still URLs, not HTML.
                if (!final && pending === "<") return;
                if (URL_START.test(pending.slice(1))) { pending = pending.slice(1); continue; }
                if (!final && SCHEME_PART.test(pending.slice(1))) return;
                const tag = htmlCandidate(pending, reply !== null);
                if (tag.kind === "tag") {
                    note("markdown"); pending = pending.slice(tag.length); plain(" ", output);
                    if (reply !== null && tag.element !== null) mode = { kind: "element", closer: "</" + tag.element.toLowerCase(), held: "" };
                    continue;
                }
                if (!final && tag.kind === "pending") return;
                plain("<", output); pending = pending.slice(1); continue;
            }
            const url = URL_START.test(pending);
            if (url) {
                const end = pending.search(/[\s<>()\[\]]/u);
                if (end === -1 && !final) return;
                const length = end === -1 ? pending.length : end;
                const token = pending.slice(0, length);
                const trailing = /[.,!?;:]+$/.exec(token)?.[0] || "";
                const address = trailing ? token.slice(0, -trailing.length) : token;
                note("url");
                plain(siteName(address) + trailing, output);
                pending = pending.slice(length);
                continue;
            }
            if (!final && SCHEME_PART.test(pending)) return;
            if (reply !== null && (first === "{" || first === "[")) {
                const judged = jsonCandidate(pending, final);
                if (judged === "pending") return;
                if (judged === "json") {
                    note("code");
                    mode = { kind: "json", depth: 0, quoted: false, escaped: false };
                    continue;
                }
            }
            const image = pending.startsWith("![");
            if (first === "[" || image) {
                const start = image ? 2 : 1;
                const close = pending.indexOf("]", start);
                if (!final && (close === -1 || close === pending.length - 1)) return;
                if (close !== -1 && pending[close + 1] === "(") {
                    const end = pending.indexOf(")", close + 2);
                    if (!final && end === -1) return;
                    // Unfinished link targets are discarded on finish.
                    const label = image ? "" : pending.slice(start, close);
                    note("markdown");
                    pending = label + " " + (end === -1 ? "" : pending.slice(end + 1));
                    continue;
                }
                note("markdown"); pending = pending.slice(start); continue;
            }
            if (!final && pending === "!") return;
            const pathBoundary = wordStart();
            const path = pathBoundary && /^(?:\/[\p{L}\p{N}_.]|~\/|[A-Za-z]:\\)/u.test(pending);
            if (path) {
                const end = pending.search(/\s/u);
                if (end === -1 && !final) return;
                const length = end === -1 ? pending.length : end;
                const trailing = /[.,!?;:]+$/.exec(pending.slice(0, length))?.[0] || "";
                note("path"); plain(" " + trailing, output); pending = pending.slice(length); continue;
            }
            if (!final && (pending === "/" || pending === "~" || /^[A-Za-z]:?\\?$/.test(pending))) return;
            // A line that starts with "|" is a table's row.
            if (reply !== null && first === "|" && /(?:^|\n)[ \t]*$/u.test(sentence)) {
                note("markdown"); mode = { kind: "row" }; continue;
            }
            if (/^[*_~#>|\\\[\]]/u.test(first)) {
                note("markdown"); pending = pending.slice(1); plain(" ", output); continue;
            }
            // Markdown list bullets and ordered markers are layout, not speech.
            if ((sentence === "" || sentence.endsWith("\n")) && /^[-+]\s/u.test(pending)) {
                note("markdown"); pending = pending.slice(1); continue;
            }
            if (!final && (first === "-" || first === "+") && pending.length === 1) return;
            const ordered = /^\d+[.)]\s/u.exec(pending);
            if ((sentence === "" || sentence.endsWith("\n")) && ordered) {
                if (!final && ordered[0].length === pending.length) return;
                if (/^\p{L}/u.test(pending.slice(ordered[0].length))) {
                    note("markdown"); pending = pending.slice(ordered[0].length); continue;
                }
            }
            if (!final && (sentence === "" || sentence.endsWith("\n")) && /^\d+[.)]?\s*$/u.test(pending)) return;
            const char = pending.codePointAt(0);
            const width = char > 0xffff ? 2 : 1;
            plain(pending.slice(0, width), output);
            pending = pending.slice(width);
        }
    }
    function run(chunk, final) {
        if (lifecycle !== "open") throw new Error("jarvis: speakable=stream-" + lifecycle);
        try {
            if (typeof chunk !== "string") throw new Error("jarvis: speakable=chunk-type");
            bound(chunk, LIMITS.chunk, "chunk");
            const output = [];
            // Feed bounded pieces before retaining them. No combined chunk
            // allocation grows beyond the pending token ceiling.
            for (const char of chunk) {
                pending += char;
                bound(pending, LIMITS.token, "token");
                drain(false, output);
            }
            if (final) {
                drain(true, output);
                while (mode.kind === "element") {
                    pending = mode.held;
                    mode = PROSE;
                    drain(true, output);
                }
                emit(sentence, output);
                sentence = ""; mode = PROSE;
                lifecycle = "closed";
            }
            return output;
        } catch (error) {
            pending = ""; sentence = ""; mode = PROSE; lifecycle = "failed";
            throw error;
        }
    }
    return Object.freeze({
        /** Consume an arbitrary text chunk; return completed spoken sentences. */
        push(chunk) { return run(chunk, false); },
        /** Close the text stream and return its final fragment, if any. */
        finish() { return run("", true); },
        /** Snapshot machine-detectable violations, with no transcript or audio. */
        counts() { return Object.freeze({ ...counts }); }
    });
}

/** Count final transcript violations. Call once per non-overlapping text window. */
function violations(text, language) {
    const stream = create(language);
    stream.push(text);
    stream.finish();
    return stream.counts();
}

module.exports = { create, violations, limits: LIMITS };
