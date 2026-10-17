// The selection edit bin/vgshell-theme-judge keeps in an application's own
// settings file: each key a target's `select` names, set to its value,
// with every other byte of the file kept. Nothing here reads or writes a
// file. docs/architecture/themes.md § Targets holds the rules.
//
// TEXT and VALUE are strings in one encoding: the judge reads the file as
// latin1, one character per byte, and hands over VALUE's UTF-8 bytes the
// same way, so every byte the edit keeps is kept.
//
// A refusal is { ok: false, reason, detail }, as bin/lib/theme-render.js
// answers one: `selection-file-absent` for an absent file, which is never
// created, or `selection-refused` with the detail
// `format=<format> cause=<cause> key=<dotted key>` for a file whose key
// cannot be set without reading it wrong, the first such key named.
"use strict";
const path = require("path");
const render = require(path.join(__dirname, "theme-render.js"));

const ABSENT = "selection-file-absent";
const REFUSED = "selection-refused";

// A YAML value written plain: a word no YAML reader takes for a boolean,
// a null or a number. Any other value is written double-quoted.
const YAML_PLAIN = /^[A-Za-z][A-Za-z0-9_./-]*$/;
const YAML_RESERVED = /^(y|n|yes|no|true|false|on|off|null)$/i;

// The text after a value on its line: nothing, or a comment.
const LINE_TAIL = /^(\s+#[^\n]*|\s*)$/;

// The line break TEXT uses, so a line the edit adds matches the file's.
function lineBreak(text) {
    return text.includes("\r\n") ? "\r\n" : "\n";
}

// TEXT ending in a line break: LINE_END is added when it has none.
function terminated(text, lineEnd) {
    return text === "" || text.endsWith("\n") ? text : text + lineEnd;
}

// The text a settings file holding TEXT, or undefined when it is absent,
// takes so that each of KEYS, a list of paths of bare names, holds VALUE in
// FORMAT, `json`, `jsonc`, `toml` or `yaml`: the new text, null when every key
// already holds VALUE, or a refusal. Each key is set in order in the text
// the key before it left, and any key refused refuses the whole edit.
function selectedText(format, text, keys, value) {
    if (text === undefined) return { ok: false, reason: ABSENT, detail: "" };
    let changed = null;
    for (const key of keys) {
        const verdict = keySelected(format, changed === null ? text : changed, key, value);
        if (verdict !== null && typeof verdict !== "string") return verdict;
        if (verdict !== null) changed = verdict;
    }
    return changed;
}

// The text TEXT takes so that KEY holds VALUE in FORMAT: the new text, null
// when KEY already holds VALUE, or a refusal.
function keySelected(format, text, key, value) {
    const refuse = cause => ({ ok: false, reason: REFUSED, detail: "format=" + format + " cause=" + cause + " key=" + key.join(".") });
    switch (format) {
    case "json": return jsonSelected(text, text, key, value, refuse);
    case "jsonc": return jsonSelected(text, jsoncBlanked(text), key, value, refuse);
    case "toml": return tomlSelected(text, key, value, refuse);
    case "yaml": return yamlSelected(text, key, value, refuse);
    default: throw new Error("theme-select: selectedText: format " + format + " is none of json, jsonc, toml, yaml");
    }
}

// --- json

function skipSpace(text, at) {
    while (at < text.length && " \t\n\r".includes(text[at])) at++;
    return at;
}

// The offset just past the JSON string that opens at AT.
function stringEnd(text, at) {
    let i = at + 1;
    while (text[i] !== "\"") i += text[i] === "\\" ? 2 : 1;
    return i + 1;
}

// The span of the value at AT in TEXT, which JSON.parse accepted: its
// `kind`, `start` and `end`, and for an object its `members` in order, each
// { key, start, value }, `start` the offset of the member's key.
function jsonSpan(text, at) {
    at = skipSpace(text, at);
    const open = text[at];
    if (open === "\"") return { kind: "string", start: at, end: stringEnd(text, at), members: [] };
    if (open === "{" || open === "[") {
        const close = open === "{" ? "}" : "]";
        const members = [];
        let i = skipSpace(text, at + 1);
        while (text[i] !== close) {
            const start = i;
            let name;
            if (open === "{") {
                const keyEnd = stringEnd(text, i);
                name = JSON.parse(text.slice(i, keyEnd));
                i = skipSpace(text, keyEnd) + 1;
            }
            const value = jsonSpan(text, i);
            members.push({ key: open === "{" ? name : String(members.length), start, value });
            i = skipSpace(text, value.end);
            if (text[i] === ",") i = skipSpace(text, i + 1);
        }
        return { kind: open === "{" ? "object" : "array", start: at, end: i + 1, members };
    }
    let end = at;
    while (end < text.length && !",]} \t\n\r".includes(text[end])) end++;
    return { kind: "literal", start: at, end, members: [] };
}

// The member text that gives SEGMENTS, outermost first, VALUE: each
// missing intermediate object written on the member's line.
function memberText(segments, value) {
    const [first, ...rest] = segments;
    return JSON.stringify(first) + ": " + (rest.length === 0 ? JSON.stringify(value) : "{ " + memberText(rest, value) + " }");
}

// TEXT with MEMBER first in OBJECT. A multi-line object takes it on its own
// line at the indentation of its first member; a single-line one takes it
// on that line, ahead of its first member; an empty one takes it two spaces
// deeper than the line the object opens on, ahead of any comment it holds.
function withMember(text, object, member) {
    const lineEnd = lineBreak(text);
    if (object.members.length === 0) {
        const indent = /^[ \t]*/.exec(text.slice(text.lastIndexOf("\n", object.start) + 1))[0];
        const inside = text.slice(object.start + 1, object.end - 1);
        if (inside.trim() !== "") return text.slice(0, object.start + 1) + lineEnd + indent + "  " + member + inside + text.slice(object.end - 1);
        return text.slice(0, object.start + 1) + lineEnd + indent + "  " + member + lineEnd + indent + text.slice(object.end - 1);
    }
    const first = object.members[0].start;
    const between = text.slice(object.start + 1, first);
    const newline = between.lastIndexOf("\n");
    if (newline === -1) return text.slice(0, first) + member + ", " + text.slice(first);
    return text.slice(0, object.start + 1) + lineEnd + between.slice(newline + 1) + member + "," + text.slice(object.start + 1);
}

// TEXT, JSON with comments and trailing commas, with each comment and each
// trailing comma written as spaces, its line breaks kept: plain JSON whose
// every offset is TEXT's, so a span read from it is TEXT's span.
function jsoncBlanked(text) {
    const out = text.split("");
    const blank = (from, to) => { for (let i = from; i < to; i++) if (out[i] !== "\n" && out[i] !== "\r") out[i] = " "; };
    // The offset past the string opening at AT, or the text's end for one
    // left open, which JSON.parse then refuses.
    const pastString = (source, at) => {
        let i = at + 1;
        while (i < source.length && source[i] !== "\"") i += source[i] === "\\" ? 2 : 1;
        return Math.min(i + 1, source.length);
    };
    let i = 0;
    while (i < text.length) {
        if (text[i] === "\"") {
            i = pastString(text, i);
        } else if (text.startsWith("//", i)) {
            const end = text.indexOf("\n", i);
            blank(i, end === -1 ? text.length : end);
            i = end === -1 ? text.length : end;
        } else if (text.startsWith("/*", i)) {
            const end = text.indexOf("*/", i + 2);
            blank(i, end === -1 ? text.length : end + 2);
            i = end === -1 ? text.length : end + 2;
        } else {
            i++;
        }
    }
    // A comma blanked inside a string changes no offset and no structure.
    const plain = out.join("");
    for (i = 0; i < plain.length; i++)
        if (plain[i] === "," && "}]".includes(plain[skipSpace(plain, i + 1)])) out[i] = " ";
    return out.join("");
}

// JSON: the whole file must parse as an object; PLAIN is TEXT, or for
// `jsonc` TEXT blanked by jsoncBlanked, and every byte outside the edit is
// TEXT's. The key's string token is replaced; a missing key is added, with
// the objects missing on its path, as the first member of the deepest
// object that exists.
function jsonSelected(text, plain, key, value, refuse) {
    let document;
    try {
        document = JSON.parse(plain);
    } catch (e) {
        return refuse("unparseable");
    }
    if (document === null || typeof document !== "object" || Array.isArray(document)) return refuse("unparseable");
    let object = jsonSpan(plain, 0);
    for (let depth = 0; depth < key.length; depth++) {
        const found = object.members.filter(member => member.key === key[depth]);
        if (found.length > 1) return refuse("duplicate-key");
        if (found.length === 0) return withMember(text, object, memberText(key.slice(depth), value));
        const span = found[0].value;
        if (depth < key.length - 1) {
            if (span.kind !== "object") return refuse("not-a-table");
            object = span;
            continue;
        }
        if (span.kind !== "string") return refuse("not-a-string");
        if (JSON.parse(text.slice(span.start, span.end)) === value) return null;
        return text.slice(0, span.start) + JSON.stringify(value) + text.slice(span.end);
    }
    throw new Error("theme-select: jsonSelected: key " + key.join(".") + " walked past its last segment");
}

// --- toml and yaml

// NAME without the one pair of double or single quotes around it.
function unquoted(name) {
    const m = /^"(.*)"$|^'(.*)'$/.exec(name);
    return m === null ? name : m[1] !== undefined ? m[1] : m[2];
}

// Whether PATH, a list of names, starts with PREFIX.
function startsWith(path, prefix) {
    return prefix.length <= path.length && prefix.every((name, at) => path[at] === name);
}

// The dotted path a TOML header line names, each part trimmed and
// unquoted, or null for a line that opens none. `[[a]]` names `a` too.
function headerPath(line) {
    if (!render.opensSection(line)) return null;
    const m = /^\s*\[\[?([^\]]*)\]/.exec(line);
    return m === null ? [] : m[1].split(".").map(part => unquoted(part.trim()));
}

// The offset just past the TOML string that opens at AT in LINE, or -1
// when none does: an unterminated string or any other value. A multi-line
// string's delimiter reads as an empty string with text after it.
function tomlStringEnd(line, at) {
    if (line[at] === "'") {
        const end = line.indexOf("'", at + 1);
        return end === -1 ? -1 : end + 1;
    }
    if (line[at] !== "\"") return -1;
    let i = at + 1;
    while (i < line.length && line[i] !== "\"") i += line[i] === "\\" ? 2 : 1;
    return i < line.length ? i + 1 : -1;
}

// The value of the TOML string TOKEN, or undefined for a basic string JSON
// cannot read, which is then taken as another value.
function tomlString(token) {
    if (token[0] === "'") return token.slice(1, -1);
    try {
        return JSON.parse(token);
    } catch (e) {
        return undefined;
    }
}

// TOML, line-exact: `[table, key]` edits the lines under the one `[table]`
// header, up to the next header of any kind, and `[key]` the lines ahead of
// the first header. A line is read on its own.
function tomlSelected(text, key, value, refuse) {
    const lines = text.split("\n");
    const cr = lineBreak(text) === "\r\n" ? "\r" : "";
    const table = key.length === 2 ? key[0] : null;
    const name = key[key.length - 1];
    const firstHeader = lines.findIndex(render.opensSection);
    const rootEnd = firstHeader === -1 ? lines.length : firstHeader;
    const headers = [];
    for (let at = 0; at < lines.length; at++) {
        const header = headerPath(lines[at]);
        if (header === null) continue;
        if (table !== null && render.isSectionHeader(lines[at], table)) headers.push(at);
        else if (table !== null && header.length === 1 && header[0] === table) return refuse("not-a-table");
        else if (startsWith(header, key)) return refuse("not-a-string");
    }
    if (headers.length > 1) return refuse("duplicate-table");
    const assigned = at => {
        const assignedKey = render.assignedKey(lines[at]);
        return assignedKey === null ? null : unquoted(assignedKey);
    };
    if (table !== null) {
        for (let at = 0; at < rootEnd; at++) {
            const assignedKey = assigned(at);
            if (assignedKey !== null && (assignedKey === table || assignedKey.startsWith(table + "."))) return refuse("not-a-table");
        }
        if (headers.length === 0)
            return terminated(text, cr + "\n") + "[" + table + "]" + cr + "\n" + name + " = " + JSON.stringify(value) + cr + "\n";
    }
    const start = table === null ? 0 : headers[0] + 1;
    const next = lines.findIndex((line, at) => at >= start && render.opensSection(line));
    const end = next === -1 ? lines.length : next;
    const found = [];
    for (let at = start; at < end; at++) {
        const assignedKey = assigned(at);
        if (assignedKey === name) found.push(at);
        else if (assignedKey !== null && assignedKey.startsWith(name + ".")) return refuse("not-a-string");
    }
    if (found.length > 1) return refuse("duplicate-key");
    if (found.length === 0) {
        lines.splice(start, 0, name + " = " + JSON.stringify(value) + cr);
        return lines.join("\n");
    }
    const line = lines[found[0]];
    const tokenStart = line.indexOf("=") + 1 + /^[ \t]*/.exec(line.slice(line.indexOf("=") + 1))[0].length;
    const tokenEnd = tomlStringEnd(line, tokenStart);
    if (tokenEnd === -1 || !LINE_TAIL.test(line.slice(tokenEnd))) return refuse("not-a-string");
    if (tomlString(line.slice(tokenStart, tokenEnd)) === value) return null;
    lines[found[0]] = line.slice(0, tokenStart) + JSON.stringify(value) + line.slice(tokenEnd);
    return lines.join("\n");
}

function isBlankOrComment(line) {
    return /^\s*(#|$)/.test(line);
}

function indentOf(line) {
    return /^ */.exec(line)[0].length;
}

// Whether LINE is a document marker, `---` or `...`.
function isMarker(line) {
    return /^(---|\.\.\.)(\s|$)/.test(line);
}

// Whether LINE is a mapping key line of NAME at exactly INDENT spaces,
// quoted or bare.
function isKeyLine(line, indent, name) {
    return new RegExp("^ {" + indent + "}([\"']?)" + name + "\\1[ \\t]*:(\\s|$)").test(line);
}

// The length of the single-line scalar TEXT opens with, or -1 when it
// opens with none: an empty value, a block, flow, anchor, alias or tag, an
// unterminated quote, or a plain scalar holding `: `.
function yamlScalarEnd(text) {
    if (text[0] === "\"") {
        let i = 1;
        while (i < text.length && text[i] !== "\"") i += text[i] === "\\" ? 2 : 1;
        return i < text.length ? i + 1 : -1;
    }
    if (text[0] === "'") {
        for (let i = 1; i < text.length; i++) {
            if (text[i] !== "'") continue;
            if (text[i + 1] === "'") i++;
            else return i + 1;
        }
        return -1;
    }
    if (text === "" || /^\s/.test(text) || "-?:,[]{}#&*!|>'\"%@`".includes(text[0])) return -1;
    const comment = /\s+#/.exec(text);
    const token = (comment === null ? text : text.slice(0, comment.index)).replace(/\s+$/, "");
    return token.includes(": ") || token.endsWith(":") ? -1 : token.length;
}

// The value of the YAML scalar TOKEN, or undefined for a double-quoted one
// JSON cannot read, which is then taken as another value.
function yamlScalar(token) {
    if (token[0] === "'") return token.slice(1, -1).replace(/''/g, "'");
    if (token[0] !== "\"") return token;
    try {
        return JSON.parse(token);
    } catch (e) {
        return undefined;
    }
}

function yamlValue(value) {
    return YAML_PLAIN.test(value) && !YAML_RESERVED.test(value) ? value : JSON.stringify(value);
}

// YAML, line-exact and block style only: `[map, key]` edits the block of
// the one column-0 `map:` line, `[key]` the column-0 lines.
function yamlSelected(text, key, value, refuse) {
    const lines = text.split("\n");
    const cr = lineBreak(text) === "\r\n" ? "\r" : "";
    if (lines.some(line => /^[ \t]*\t/.test(line))) return refuse("tab");
    let content = false;
    for (const line of lines) {
        if (isMarker(line) && content) return refuse("multi-document");
        if (!isMarker(line) && !isBlankOrComment(line)) content = true;
    }
    const isTop = line => !isMarker(line) && !isBlankOrComment(line) && indentOf(line) === 0;
    const firstTop = lines.find(isTop);
    const rootIsMap = firstTop === undefined || !"-[{".includes(firstTop[0]);
    const name = key[key.length - 1];
    const appended = entry => rootIsMap ? terminated(text, cr + "\n") + entry + cr + "\n" : refuse("not-a-map");
    let start = 0;
    let end = lines.length;
    let indent = 0;
    if (key.length === 2) {
        const map = key[0];
        const maps = lines.map((line, at) => at).filter(at => isKeyLine(lines[at], 0, map));
        if (maps.length > 1) return refuse("duplicate-key");
        if (maps.length === 0) return appended(map + ":" + cr + "\n  " + name + ": " + yamlValue(value));
        if (!new RegExp("^" + map + "[ \\t]*:(\\s+#[^\\n]*|\\s*)$").test(lines[maps[0]])) return refuse("not-a-map");
        start = maps[0] + 1;
        const next = lines.findIndex((line, at) => at >= start && (isTop(line) || isMarker(line)));
        end = next === -1 ? lines.length : next;
        if (next !== -1 && /^-(\s|$)/.test(lines[next])) return refuse("not-a-map");
        const first = lines.slice(start, end).find(line => !isBlankOrComment(line));
        if (first !== undefined && /^\s*-(\s|$)/.test(first)) return refuse("not-a-map");
        indent = first === undefined ? 0 : indentOf(first);
    }
    const found = [];
    for (let at = start; at < end; at++) if (isKeyLine(lines[at], indent, name)) found.push(at);
    if (found.length > 1) return refuse("duplicate-key");
    const entry = " ".repeat(key.length === 2 && indent === 0 ? 2 : indent) + name + ": " + yamlValue(value);
    if (found.length === 0) {
        if (key.length === 1) return appended(entry);
        lines.splice(start, 0, entry + cr);
        return lines.join("\n");
    }
    const at = found[0];
    const line = lines[at];
    const tokenStart = line.indexOf(":", indent) + 1 + /^[ \t]*/.exec(line.slice(line.indexOf(":", indent) + 1))[0].length;
    const tokenEnd = yamlScalarEnd(line.slice(tokenStart));
    if (tokenEnd === -1 || !LINE_TAIL.test(line.slice(tokenStart + tokenEnd))) return refuse("not-a-string");
    const after = lines.slice(at + 1, end).find(following => !isBlankOrComment(following));
    if (after !== undefined && indentOf(after) > indent) return refuse("not-a-string");
    if (yamlScalar(line.slice(tokenStart, tokenStart + tokenEnd)) === value) return null;
    lines[at] = line.slice(0, tokenStart) + yamlValue(value) + line.slice(tokenStart + tokenEnd);
    return lines.join("\n");
}

// TOML colour edits need spans inside inline tables and arrays (Yazi's icon
// rules), and multiline strings (Starship's format). Keep those spans in
// the existing selection owner instead of serialising the user's document.
function tomlSpans(text) {
    let at = 0;
    const records = [];
    const headers = [];
    const invalid = () => { throw new SyntaxError("toml"); };
    const space = multiline => {
        while (at < text.length) {
            if ((multiline ? /\s/ : /[ \t\r]/).test(text[at])) at++;
            else if (multiline && text[at] === "#") {
                while (at < text.length && text[at] !== "\n") at++;
            } else break;
        }
    };
    const string = () => {
        const start = at;
        const quote = text[at];
        const delimiter = text.startsWith(quote.repeat(3), at) ? quote.repeat(3) : quote;
        at += delimiter.length;
        const contentStart = at;
        while (at < text.length) {
            if (text.startsWith(delimiter, at)) {
                const contentEnd = at;
                at += delimiter.length;
                return { kind: "string", start, end: at, contentStart, contentEnd };
            }
            if (delimiter.length === 1 && text[at] === "\n") invalid();
            at += quote === '"' && text[at] === "\\" ? 2 : 1;
        }
        invalid();
    };
    const key = () => {
        const names = [];
        while (true) {
            space(false);
            if (text[at] === '"' || text[at] === "'") {
                const token = string();
                const name = tomlString(text.slice(token.start, token.end));
                if (name === undefined || token.contentStart !== token.start + 1) invalid();
                names.push(name);
            } else {
                const match = /^[A-Za-z0-9_-]+/.exec(text.slice(at));
                if (match === null) invalid();
                names.push(match[0]);
                at += match[0].length;
            }
            space(false);
            if (text[at] !== ".") return names;
            at++;
        }
    };
    const value = names => {
        space(false);
        const start = at;
        let node;
        if (text[at] === '"' || text[at] === "'") node = string();
        else if (text[at] === "[" || text[at] === "{") {
            const object = text[at++] === "{";
            const close = object ? "}" : "]";
            let index = 0;
            space(true);
            while (text[at] !== close) {
                if (at >= text.length) invalid();
                let child = [String(index++)];
                if (object) {
                    child = key();
                    if (text[at++] !== "=") invalid();
                }
                value(names.concat(child));
                space(true);
                if (text[at] === close) break;
                if (text[at++] !== ",") invalid();
                space(true);
            }
            at++;
            node = { kind: object ? "object" : "array", start, end: at };
        } else {
            while (at < text.length && !"\n\r,]}#".includes(text[at])) at++;
            if (text.slice(start, at).trim() === "") invalid();
            node = { kind: "literal", start, end: at };
        }
        records.push({ key: names, ...node });
    };
    let table = [];
    const arrayTables = new Map();
    while (at < text.length) {
        space(true);
        if (at === text.length) break;
        if (text[at] === "[") {
            const start = at++;
            const array = text[at] === "[";
            if (array) at++;
            const names = key();
            if (text[at++] !== "]" || (array && text[at++] !== "]")) invalid();
            table = names;
            if (array) {
                const name = names.join(".");
                const index = arrayTables.get(name) || 0;
                arrayTables.set(name, index + 1);
                table = names.concat(String(index));
            }
            if (!array && headers.some(header => !header.array && header.key.length === table.length && header.key.every((name, i) => name === table[i]))) invalid();
            headers.push({ key: table, start, end: at, array });
        } else {
            const names = key();
            if (text[at++] !== "=") invalid();
            value(table.concat(names));
        }
        space(false);
        if (text[at] === "#") while (at < text.length && text[at] !== "\n") at++;
        if (at < text.length && text[at++] !== "\n") invalid();
    }
    const seen = new Set();
    for (const record of records) {
        const name = JSON.stringify(record.key);
        if (seen.has(name)) invalid();
        seen.add(name);
    }
    return { records, headers };
}

function replaceSpans(text, edits) {
    let out = text;
    for (const { start, end, value } of edits.sort((a, b) => b.start - a.start))
        out = out.slice(0, start) + value + out.slice(end);
    return out === text ? null : out;
}

function tomlColorKey(text, key, value) {
    const { records, headers } = tomlSpans(text);
    const same = names => names.length === key.length && names.every((name, i) => name === key[i]);
    const record = records.find(record => same(record.key));
    if (record !== undefined) {
        if (record.kind !== "string") throw new SyntaxError("not-a-string");
        if (tomlString(text.slice(record.start, record.end)) === value) return text;
        return text.slice(0, record.start) + JSON.stringify(value) + text.slice(record.end);
    }
    const parent = key.slice(0, -1);
    if (headers.some(header => startsWith(header.key, key))) throw new SyntaxError("not-a-string");
    if (records.some(record => record.kind !== "object" && startsWith(key, record.key) && record.key.length < key.length)) throw new SyntaxError("not-a-table");
    // An inline table has no header at which an independent assignment can
    // be inserted. Add its member inside its own braces.
    const inline = records.filter(record => record.kind === "object" && startsWith(parent, record.key)).sort((a, b) => b.key.length - a.key.length)[0];
    if (inline !== undefined) {
        const inside = text.slice(inline.start + 1, inline.end - 1);
        let member = JSON.stringify(value);
        for (let i = key.length - 1; i > inline.key.length; i--) member = "{ " + key[i] + " = " + member + " }";
        member = key[inline.key.length] + " = " + member;
        return text.slice(0, inline.start + 1) + " " + member + (inside.trim() === "" ? " " : ",") + inside + text.slice(inline.end - 1);
    }
    if (records.some(record => startsWith(key, record.key) && record.key.length < key.length)) throw new SyntaxError("not-a-table");
    const lineEnd = lineBreak(text);
    const assignment = key.at(-1) + " = " + JSON.stringify(value) + lineEnd;
    const header = headers.find(header => !header.array && header.key.length === parent.length && header.key.every((name, i) => name === parent[i]));
    if (parent.length === 0) return assignment + text;
    if (header === undefined) return terminated(text, lineEnd) + "[" + parent.join(".") + "]" + lineEnd + assignment;
    const newline = text.indexOf("\n", header.end);
    const insert = newline === -1 ? text.length : newline + 1;
    return terminated(text.slice(0, insert), lineEnd) + assignment + text.slice(insert);
}

const STARSHIP_ANSI = /^(?:bright-)?(?:black|red|green|yellow|blue|purple|magenta|cyan|white)$/;
const STARSHIP_ATTRIBUTE = /^(?:none|bold|italic|underline|dimmed|inverted|blink|hidden|strikethrough|overline)$/;

// Starship styles are space-separated attributes and colours. Its named
// ANSI colours remain names; the VGS palette supplies their values. Literal
// and custom-palette colours need an explicit VGS colour to override them.
// https://starship.rs/advanced-config/#style-strings
function starshipStyle(style, values) {
    return style.replace(/\S+/g, atom => {
        const match = /^(fg:|bg:)?(.*)$/.exec(atom);
        const prefix = match[1] || "";
        const color = match[2];
        if (color.includes("$") || STARSHIP_ATTRIBUTE.test(color) || STARSHIP_ANSI.test(color)) return atom;
        return prefix + values[prefix === "bg:" ? "bg" : "fg"];
    });
}

function tomlAppSelected(format, text, values) {
    const { records } = tomlSpans(text);
    const edits = [];
    for (const record of records) {
        const key = record.key.filter(name => !/^\d+$/.test(name));
        const name = key.at(-1);
        if (format === "yazi" && (name === "fg" || name === "bg")) {
            if (record.kind !== "string") throw new SyntaxError("not-a-string");
            edits.push({ ...record, value: JSON.stringify(values[key.join(".")] ?? values[name]) });
        } else if (format === "television" && key[0] === "ui" && key[1] === "theme_overrides") {
            if (record.kind === "object") continue;
            if (record.kind !== "string" || values[name] === undefined) throw new SyntaxError("unsupported-colour");
            edits.push({ ...record, value: JSON.stringify(values[name]) });
        } else if (format === "starship" && record.kind === "string" && key[0] !== "palettes" &&
            (/(?:^style(?:_|$)|_style$|(?:^|_)format$|(?:^|_)symbol$)/.test(name) || name === "continuation_prompt")) {
            const raw = text.slice(record.contentStart, record.contentEnd);
            const changed = /(?:^style(?:_|$)|_style$)/.test(name) ? starshipStyle(raw, values)
                : raw.replace(/\]\(([^()]*)\)/g, (whole, style) => "](" + starshipStyle(style, values) + ")");
            if (changed !== raw) edits.push({ start: record.contentStart, end: record.contentEnd, value: changed });
        }
    }
    let out = replaceSpans(text, edits) ?? text;
    switch (format) {
    case "starship":
        out = tomlColorKey(out, ["palette"], "vgs");
        for (const [name, value] of Object.entries(values))
            if (name !== "fg" && name !== "bg") out = tomlColorKey(out, ["palettes", "vgs", name], value);
        break;
    case "yazi":
        for (const scheme of ["dark", "light"]) out = tomlColorKey(out, ["flavor", scheme], "vgs");
        break;
    case "television":
        out = tomlColorKey(out, ["ui", "theme"], "vgs");
        break;
    default: throw new Error("theme-select: unknown TOML app " + format);
    }
    return out === text ? null : out;
}

function batSelected(text, values) {
    const edits = [];
    // bat's config is one shell-like option per line. Change only the
    // option's argument; comments and unrelated options stay in place.
    // https://github.com/sharkdp/bat#configuration-file
    const pattern = /^([ \t]*--theme(?:=|[ \t]+))((?:"[^"\r\n]*"|'[^'\r\n]*'|[^\s#"']+))(?=[ \t]*(?:#|\r?$))/gm;
    for (const match of text.matchAll(pattern)) edits.push({ start: match.index + match[1].length, end: match.index + match[0].length, value: values.theme });
    const unknown = text.split("\n").some(line => /^\s*--theme(?:\s|=|$)/.test(line) && !new RegExp(pattern.source, "m").test(line));
    if (unknown) throw new SyntaxError("unsupported-option");
    if (edits.length !== 0) return replaceSpans(text, edits);
    return terminated(text, lineBreak(text)) + "--theme=" + values.theme + lineBreak(text);
}

function ansiColor(value, background) {
    const hex = /^#([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i.exec(value);
    if (hex !== null) return (background ? "48" : "38") + ";2;" + hex.slice(1).map(part => parseInt(part, 16)).join(";");
    const names = ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"];
    const match = /^(light_)?(black|red|green|yellow|blue|magenta|cyan|white)$/.exec(value);
    if (match === null) throw new SyntaxError("unsupported-colour");
    return String((match[1] ? 90 : 30) + (background ? 10 : 0) + names.indexOf(match[2]));
}

function themedSgr(code, foreground, background) {
    const parts = code.split(";");
    const out = [];
    for (let i = 0; i < parts.length; i++) {
        const n = Number(parts[i]);
        if (n === 38 || n === 48) {
            const count = parts[i + 1] === "2" ? 4 : parts[i + 1] === "5" ? 2 : 0;
            if (count === 0 || i + count >= parts.length) throw new SyntaxError("unsupported-colour");
            out.push(ansiColor(n === 48 ? background : foreground, n === 48));
            i += count;
        } else if ((n >= 30 && n <= 37) || (n >= 90 && n <= 97)) out.push(ansiColor(foreground, false));
        else if ((n >= 40 && n <= 47) || (n >= 100 && n <= 107)) out.push(ansiColor(background, true));
        else out.push(parts[i]);
    }
    return out.join(";");
}

function fastfetchSelected(text, values) {
    const plain = jsoncBlanked(text);
    const document = JSON.parse(plain);
    if (document === null || typeof document !== "object" || Array.isArray(document)) throw new SyntaxError("unparseable");
    const edits = [];
    const walk = (node, key) => {
        const seen = new Set();
        for (const member of node.members) {
            if (seen.has(member.key)) throw new SyntaxError("duplicate-key");
            seen.add(member.key);
            walk(member.value, key.concat(member.key));
        }
        const name = key.at(-1);
        if (key.length === 2 && key[0] === "display" && name === "color" && node.kind !== "object") {
            if (node.kind !== "string" && plain.slice(node.start, node.end) !== "null") throw new SyntaxError("unsupported-colour");
            edits.push({ ...node, value: JSON.stringify(Object.fromEntries(["keys", "title", "output", "separator"].map(role => [role, values[role]]))) });
            return;
        }
        const role = name === "keyColor" ? "keys" : name === "outputColor" ? "output"
            : key[0] === "logo" && key[1] === "color" ? "logo"
            : key[0] === "display" && key[1] === "color" ? name : undefined;
        if (role !== undefined && values[role] !== undefined && node.kind !== "object" && node.kind !== "array") {
            if (node.kind !== "string" && plain.slice(node.start, node.end) !== "null") throw new SyntaxError("not-a-string");
            edits.push({ ...node, value: JSON.stringify(values[role]) });
        } else if (node.kind === "string" && key[0] === "modules" && (name === "key" || name === "format")) {
            const raw = text.slice(node.start + 1, node.end - 1);
            const color = values[name === "key" ? "keys" : "output"];
            // Keep reset and text attributes; replace only SGR colour codes.
            // fastfetch accepts RGB or ANSI names in {#...} placeholders.
            const changed = raw.replace(/\{#([^{}]+)\}/g, (whole, code) => {
                if (["keys", "title", "output", "separator"].includes(code)) return whole;
                if (/^[0-9;]+$/.test(code)) {
                    return "{#" + themedSgr(code, color, values.bg) + "}";
                }
                const attributes = { reset: 0, bold: 1, bright: 1, dim: 2, italic: 3, underline: 4, blink: 5, inverse: 7, hidden: 8, strike: 9 };
                const kept = code.split("_").filter(part => Object.hasOwn(attributes, part)).map(part => attributes[part]);
                return "{#" + kept.concat(ansiColor(color, false)).join(";") + "}";
            }).replace(/(?<!\\)((?:\\\\)*)(\\u001[bB]\[)([0-9;]*)(m)/g,
                (_, literal, open, code, close) => literal + open + themedSgr(code, color, values.bg) + close);
            if (changed !== raw) edits.push({ start: node.start + 1, end: node.end - 1, value: changed });
        }
    };
    walk(jsonSpan(plain, 0), []);
    let out = replaceSpans(text, edits) ?? text;
    for (const role of ["keys", "title", "output", "separator"]) {
        const result = jsonSelected(out, jsoncBlanked(out), ["display", "color", role], values[role], cause => { throw new SyntaxError(cause); });
        if (result !== null) out = result;
    }
    return out === text ? null : out;
}

function appSelectedText(format, text, values) {
    if (text === undefined) return { ok: false, reason: ABSENT, detail: "" };
    try {
        switch (format) {
        case "starship": case "yazi": case "television": return tomlAppSelected(format, text, values);
        case "fastfetch": return fastfetchSelected(text, values);
        case "bat": return batSelected(text, values);
        default: throw new Error("theme-select: unknown app " + format);
        }
    } catch (e) {
        if (!(e instanceof SyntaxError)) throw e;
        return { ok: false, reason: REFUSED, detail: "format=" + format + " cause=" + e.message };
    }
}

module.exports = { selectedText, appSelectedText };
