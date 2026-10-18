// The selection edit bin/vgshell-theme-judge keeps in an application's own
// settings file: stable native selectors and the migration of local colours.
// The generated Yazi flavor retains the migrated customization. Nothing
// here reads or writes a file. docs/architecture/themes.md holds the rules.
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
    case "zed": return jsonSelected(text, jsoncBlanked(text), key, value, refuse, "modes");
    case "posh": return poshSelected(text, value);
    case "toml": return tomlSelected(text, key, value, refuse);
    case "yaml": return yamlSelected(text, key, value, refuse);
    case "qtct": return iniSelected(text, [[key, JSON.stringify(value)], [["Appearance", "custom_palette"], "true"]], refuse);
    case "json-array": return jsonSelected(text, text, key, value, refuse, "array");
    case "userjs": return userJsSelected(text, key[0]);
    default: throw new Error("theme-select: selectedText: format " + format + " is none of json, jsonc, toml, yaml");
    }
}

// Only the documented literal bash/zsh eval form is edited. Shell code is
// never evaluated here; variable expansion and compound forms are refused.
function poshSelected(text, value) {
    const lines = text.split("\n");
    let found = false;
    for (let at = 0; at < lines.length; at++) {
        const line = lines[at];
        if (/^\s*#/.test(line) || !/\boh-my-posh\s+init\b/.test(line)) continue;
        found = true;
        const match = /^(\s*eval\s+"\$\(oh-my-posh\s+init\s+(?:bash|zsh))([ \t]+[^\r]*?)?(\)"[ \t]*(?:#[^\r]*)?\r?)$/.exec(line);
        if (match === null) return { ok: false, reason: "posh-complex", detail: "" };
        const args = match[2] || "";
        const words = [...args.matchAll(/\s+(?:--[A-Za-z-]+=)?(?:'[^']*'|"[^"$`\\]*"|[A-Za-z0-9_./~:@%+=,-]+)/g)];
        if (words.map(word => word[0]).join("") !== args || /[$`]/.test(args))
            return { ok: false, reason: /[$`]/.test(args) ? "posh-dynamic" : "posh-complex", detail: "" };
        const configs = words.map((word, index) => ({ word, index })).filter(({ word }) => /^\s+--config(?:=|$)/.test(word[0]));
        if (configs.length > 1) return { ok: false, reason: "posh-complex", detail: "" };
        let next = args;
        const quoted = "'" + value.replace(/'/g, "'\\''") + "'";
        if (configs.length === 0) next += " --config " + quoted;
        else {
            const { word, index } = configs[0];
            const equal = word[0].indexOf("=");
            const token = equal === -1 ? words[index + 1] : word;
            if (token === undefined || (equal === -1 && token[0].trim().startsWith("-")))
                return { ok: false, reason: "posh-complex", detail: "" };
            const start = token.index + (equal === -1 ? /^\s*/.exec(token[0])[0].length : equal + 1);
            const end = token.index + token[0].length;
            const held = args.slice(start, end).replace(/^(['"])(.*)\1$/, "$2");
            if (held !== value) next = args.slice(0, start) + quoted + args.slice(end);
        }
        lines[at] = match[1] + next + match[3];
    }
    if (!found) return { ok: false, reason: "no-posh-init", detail: "" };
    const changed = lines.join("\n");
    return changed === text ? null : changed;
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
    const indent = /^[ \t]*/.exec(between.slice(newline + 1))[0];
    return text.slice(0, object.start + 1) + lineEnd + indent + member + "," + text.slice(object.start + 1);
}

// TEXT, JSON with comments and trailing commas, with each comment and each
// trailing comma written as spaces, its line breaks kept: plain JSON whose
// every offset is TEXT's, so a span read from it is TEXT's span.
function jsoncBlanked(text, preferences = false) {
    const out = text.split("");
    const blank = (from, to) => { for (let i = from; i < to; i++) if (out[i] !== "\n" && out[i] !== "\r") out[i] = " "; };
    // The offset past the string opening at AT, or the text's end for one
    // left open, which JSON.parse then refuses.
    const pastString = (source, at) => {
        const quote = source[at];
        let i = at + 1;
        while (i < source.length && source[i] !== quote) i += source[i] === "\\" ? 2 : 1;
        return Math.min(i + 1, source.length);
    };
    let i = 0;
    while (i < text.length) {
        if (text[i] === "\"") {
            i = pastString(text, i);
        } else if (preferences && text[i] === "'") {
            i = pastString(text, i);
        } else if (preferences && text[i] === "#") {
            const end = text.indexOf("\n", i);
            blank(i, end === -1 ? text.length : end);
            i = end === -1 ? text.length : end;
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
function jsonSelected(text, plain, key, value, refuse, selection = "string") {
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
        if (found.length === 0) return withMember(text, object, memberText(key.slice(depth), selection === "array" ? [value] : value));
        const span = found[0].value;
        if (depth < key.length - 1) {
            if (span.kind !== "object") return refuse("not-a-table");
            object = span;
            continue;
        }
        if (selection === "array") {
            if (span.kind !== "array" || span.members.some(member => member.value.kind !== "string")) return refuse("not-an-array");
            if (span.members.some(member => JSON.parse(text.slice(member.value.start, member.value.end)) === value)) return null;
            const end = span.end - 1;
            return text.slice(0, end) + (span.members.length ? ", " : "") + JSON.stringify(value) + text.slice(end);
        }
        // Zed's native selector can keep a mode plus separate light and dark
        // names. Preserve that mode and edit only the two theme names.
        if (selection === "modes" && span.kind === "object")
            return selectedText("jsonc", text, [key.concat("light"), key.concat("dark")], value);
        if (span.kind !== "string") return refuse("not-a-string");
        if (JSON.parse(text.slice(span.start, span.end)) === value) return null;
        return text.slice(0, span.start) + JSON.stringify(value) + text.slice(span.end);
    }
    throw new Error("theme-select: jsonSelected: key " + key.join(".") + " walked past its last segment");
}

// Qt's QSettings reads Appearance/color_scheme_path only while
// custom_palette is true. Keep both selectors stable across palettes.
// https://github.com/trialuser02/qt6ct/blob/master/src/qt6ct-qtplugin/qt6ctplatformtheme.cpp
function iniSelected(text, entries, refuse) {
    let out = text;
    const eol = lineBreak(text);
    for (const [[section, key], value] of entries) {
        const lines = out.split("\n");
        const sectionRows = lines.flatMap((line, at) => render.isSectionHeader(line, section) ? [at] : []);
        if (sectionRows.length > 1) return refuse("duplicate-table");
        if (sectionRows.length === 0) {
            out = terminated(out, eol) + "[" + section + "]" + eol + key + "=" + value + eol;
            continue;
        }
        const start = sectionRows[0] + 1;
        let end = lines.findIndex((line, at) => at >= start && render.opensSection(line));
        if (end === -1) end = lines.length;
        const found = [];
        for (let at = start; at < end; at++) if (render.assignedKey(lines[at]) === key) found.push(at);
        if (found.length > 1) return refuse("duplicate-key");
        if (found.length === 0) {
            lines.splice(start, 0, key + "=" + value + (eol === "\r\n" ? "\r" : ""));
        } else {
            const at = found[0];
            const match = /^(\s*[^=]+=[ \t]*)(.*?)(\r?)$/.exec(lines[at]);
            if (match[2] === value) continue;
            lines[at] = match[1] + value + match[3];
        }
        out = lines.join("\n");
    }
    return out === text ? null : out;
}

// Mozilla reads user.js at profile startup. Its preference parser permits
// comments and multiline user_pref calls; it does not execute JavaScript.
// https://github.com/mozilla-firefox/firefox/blob/main/modules/libpref/parser/src/lib.rs
function userJsSelected(text, key) {
    const plain = jsoncBlanked(text, true);
    const calls = /user_pref\s*\(\s*("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')\s*,\s*(true|false)\s*\)\s*;/y;
    const replacements = [];
    let found = false;
    for (let at = 0; at < plain.length;) {
        calls.lastIndex = at;
        const match = calls.exec(plain);
        if (match !== null && (at === 0 || !/[\w$]/.test(plain[at - 1]))) {
            const name = match[1].slice(1, -1).replace(/\\(?:x([\da-fA-F]{2})|u([\da-fA-F]{4})|(["'\\nr]))/g,
                (_, byte, unit, escaped) => byte !== undefined || unit !== undefined ? String.fromCharCode(parseInt(byte ?? unit, 16))
                    : escaped === "n" ? "\n" : escaped === "r" ? "\r" : escaped);
            if (name === key) {
                found = true;
                if (match[2] === "false") {
                    const start = at + match[0].lastIndexOf("false");
                    replacements.push([start, start + 5]);
                }
            }
            at = calls.lastIndex;
        } else if (plain[at] === '"' || plain[at] === "'") {
            const quote = plain[at++];
            while (at < plain.length && plain[at] !== quote) at += plain[at] === "\\" ? 2 : 1;
            at++;
        } else {
            at++;
        }
    }
    if (!found) return terminated(text, lineBreak(text)) + "user_pref(" + JSON.stringify(key) + ", true);" + lineBreak(text);
    let out = text;
    for (const [start, end] of replacements.reverse()) out = out.slice(0, start) + "true" + out.slice(end);
    return out === text ? null : out;
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
    const value = (names, entryStart, root = false) => {
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
                const memberStart = at;
                let child = [String(index++)];
                if (object) {
                    child = key();
                    if (text[at++] !== "=") invalid();
                }
                value(names.concat(child), object ? memberStart : undefined);
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
        records.push({ key: names, entryStart, root, ...node });
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
            const entryStart = at;
            const names = key();
            if (text[at++] !== "=") invalid();
            value(table.concat(names), entryStart, true);
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

// Fixed xterm defaults, not the applied theme: migrating a literal must not
// write different names when the theme changes. XTerm-col.ad's named X11
// colours and explicit color12: https://github.com/ThomasDickey/xterm-snapshots/blob/master/XTerm-col.ad
const ANSI_REFERENCE = [
    "000000", "cd0000", "00cd00", "cdcd00", "0000ee", "cd00cd", "00cdcd", "e5e5e5",
    "7f7f7f", "ff0000", "00ff00", "ffff00", "5c5cff", "ff00ff", "00ffff", "ffffff"
].map(hex => hex.match(/../g).map(part => parseInt(part, 16)));
const ANSI_NAMES = ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"];

function indexedRgb(index) {
    if (!Number.isInteger(index) || index < 0 || index > 255) throw new SyntaxError("unsupported-colour");
    if (index < 16) return ANSI_REFERENCE[index];
    if (index >= 232) return Array(3).fill(8 + (index - 232) * 10);
    const cube = [0, 95, 135, 175, 215, 255];
    return [Math.floor((index - 16) / 36), Math.floor((index - 16) / 6) % 6, (index - 16) % 6].map(n => cube[n]);
}

// Squared Euclidean distance in 8-bit sRGB; equal distances keep the lowest
// ANSI slot. Existing ANSI references bypass this conversion.
function nearestAnsi(rgb) {
    let chosen = 0, distance = Infinity;
    ANSI_REFERENCE.forEach((candidate, index) => {
        const next = candidate.reduce((sum, value, at) => sum + (value - rgb[at]) ** 2, 0);
        if (next < distance) { chosen = index; distance = next; }
    });
    return chosen;
}

function literalAnsi(value) {
    if (/^\d+$/.test(value)) return Number(value) < 16 ? Number(value) : nearestAnsi(indexedRgb(Number(value)));
    const hex = /^#([0-9a-f]{3}|[0-9a-f]{6})$/i.exec(value);
    if (hex === null) throw new SyntaxError("unsupported-colour");
    const full = hex[1].length === 3 ? [...hex[1]].map(c => c + c).join("") : hex[1];
    return nearestAnsi(full.match(/../g).map(part => parseInt(part, 16)));
}

function ansiName(slot, bright = "bright-") {
    return (slot >= 8 ? bright : "") + ANSI_NAMES[slot % 8];
}

// Remove a declared selection/override, including its inline-table form.
// The span reader still owns parsing; unrelated settings keep their bytes.
function tomlWithout(text, prefix) {
    const { records, headers } = tomlSpans(text);
    const edits = [];
    headers.forEach((header, index) => {
        if (startsWith(header.key, prefix)) edits.push({ start: header.start, end: headers[index + 1]?.start ?? text.length, value: "" });
    });
    for (const record of records.filter(record => record.root && startsWith(record.key, prefix))) {
        if (edits.some(edit => record.start >= edit.start && record.end <= edit.end)) continue;
        const end = text.indexOf("\n", record.end);
        edits.push({ start: record.entryStart, end: end === -1 ? text.length : end + 1, value: "" });
    }
    const node = records.find(record => !record.root && record.key.length === prefix.length && startsWith(record.key, prefix));
    if (node !== undefined && !edits.some(edit => node.start >= edit.start && node.end <= edit.end)) {
        const parent = records.find(record => record.kind === "object" && record.key.length === prefix.length - 1 && startsWith(prefix, record.key));
        if (parent === undefined) throw new SyntaxError("not-a-table");
        const siblings = records.filter(record => record.key.length === prefix.length && startsWith(record.key, parent.key)).sort((a, b) => a.start - b.start);
        const at = siblings.indexOf(node);
        edits.push({ start: at === siblings.length - 1 && at > 0 ? siblings[at - 1].end : node.entryStart,
            end: at < siblings.length - 1 ? siblings[at + 1].entryStart : node.end, value: "" });
    }
    return replaceSpans(text, edits) ?? text;
}

// Starship has no palette include. ANSI styles follow the generated
// terminal palette, as Omarchy's prompt does. Resolve custom names before
// removing the palette selector so glyphs and text attributes stay intact.
function starshipStyle(style, palette) {
    return style.replace(/\S+/g, atom => {
        const match = /^(fg:|bg:)?(.*)$/.exec(atom);
        const prefix = match[1] || "";
        const color = match[2];
        if (color.includes("$") || STARSHIP_ATTRIBUTE.test(color) || STARSHIP_ANSI.test(color) || /^\d+$/.test(color) && Number(color) < 16) return atom;
        const resolved = palette.get(color) ?? color;
        return prefix + (STARSHIP_ANSI.test(resolved) ? resolved : ansiName(literalAnsi(resolved)));
    });
}

function tomlAppSelected(format, text) {
    const { records } = tomlSpans(text);
    if (format === "yazi") {
        const selected = '[flavor]' + lineBreak(text) + 'dark = "vgs"' + lineBreak(text) + 'light = "vgs"' + lineBreak(text);
        return selected === text ? null : selected;
    }
    if (format === "television") {
        const out = tomlColorKey(tomlWithout(text, ["ui", "theme_overrides"]), ["ui", "theme"], "vgs");
        return out === text ? null : out;
    }
    const paletteName = records.find(record => record.key.length === 1 && record.key[0] === "palette");
    const name = paletteName === undefined ? undefined : tomlString(text.slice(paletteName.start, paletteName.end));
    const palette = new Map(records.filter(record => record.key.length === 3 && record.key[0] === "palettes" && record.key[1] === name)
        .map(record => [record.key[2], tomlString(text.slice(record.start, record.end))]));
    const edits = [];
    for (const record of records) {
        const key = record.key.filter(name => !/^\d+$/.test(name));
        const name = key.at(-1);
        if (format === "starship" && record.kind === "string" && key[0] !== "palettes" &&
            (/(?:^style(?:_|$)|_style$|(?:^|_)format$|(?:^|_)symbol$)/.test(name) || name === "continuation_prompt")) {
            const raw = text.slice(record.contentStart, record.contentEnd);
            const changed = /(?:^style(?:_|$)|_style$)/.test(name) ? starshipStyle(raw, palette)
                : raw.replace(/\]\(([^()]*)\)/g, (whole, style) => "](" + starshipStyle(style, palette) + ")");
            if (changed !== raw) edits.push({ start: record.contentStart, end: record.contentEnd, value: changed });
        }
    }
    const out = tomlWithout(tomlWithout(replaceSpans(text, edits) ?? text, ["palette"]), ["palettes", "vgs"]);
    return out === text ? null : out;
}

// Generated Yazi flavors retain custom glyphs, matching rules and attributes
// separately for each configuration. Their colours are regenerated after
// merging, so last apply's colours cannot override the new theme.
function yaziFlavorText(base, previous, user, values) {
    const tree = text => {
        const result = new Map();
        const { records, headers } = tomlSpans(text);
        const containers = records.filter(record => record.kind === "array");
        for (const record of records) {
            if (record.kind === "object" || record.key[0] === "flavor" || containers.some(parent => parent.start < record.start && parent.end > record.end)) continue;
            let node = result;
            record.key.forEach((name, index) => {
                if (index === record.key.length - 1) { node.set(name, { raw: text.slice(record.start, record.end).trimEnd() }); return; }
                if (!node.has(name)) node.set(name, new Map());
                node = node.get(name);
                if (!(node instanceof Map)) throw new SyntaxError("not-a-table");
            });
        }
        // Array-of-table indices are parser paths, not TOML member names.
        const arrays = new Set(headers.filter(header => header.array).map(header => JSON.stringify(header.key.slice(0, -1))));
        return { result, arrays };
    };
    const merged = new Map(), arrays = new Set();
    const overlay = (into, from) => {
        for (const [key, value] of from) {
            if (value instanceof Map && into.get(key) instanceof Map) overlay(into.get(key), value);
            else into.set(key, value);
        }
    };
    for (const text of [base, previous ?? "", user ?? ""]) {
        const parsed = tree(text);
        overlay(merged, parsed.result);
        for (const key of parsed.arrays) arrays.add(key);
    }
    const encode = (node, key) => {
        if (!(node instanceof Map)) return node.raw;
        if (arrays.has(JSON.stringify(key))) return "[" + [...node.values()].map((value, i) => encode(value, key.concat(String(i)))).join(", ") + "]";
        return "{ " + [...node].map(([name, value]) => JSON.stringify(name) + " = " + encode(value, key.concat(name))).join(", ") + " }";
    };
    const text = [...merged].map(([name, value]) => JSON.stringify(name) + " = " + encode(value, [name])).join("\n") + "\n";
    const { records } = tomlSpans(text);
    return replaceSpans(text, records.filter(record => ["fg", "bg"].includes(record.key.at(-1))).map(record => {
        if (record.kind !== "string") throw new SyntaxError("not-a-string");
        const key = record.key.filter(name => !/^\d+$/.test(name));
        return { ...record, value: JSON.stringify(values[key.join(".")] ?? values[key.at(-1)]) };
    })) ?? text;
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

function themedSgr(code) {
    const parts = code.split(";");
    const out = [];
    for (let i = 0; i < parts.length; i++) {
        const n = Number(parts[i]);
        if (n === 38 || n === 48) {
            const count = parts[i + 1] === "2" ? 4 : parts[i + 1] === "5" ? 2 : 0;
            if (count === 0 || i + count >= parts.length) throw new SyntaxError("unsupported-colour");
            if (parts[i + 1] === "5" && Number(parts[i + 2]) < 16) {
                indexedRgb(Number(parts[i + 2]));
                out.push(...parts.slice(i, i + count + 1));
                i += count;
                continue;
            }
            const rgb = parts[i + 1] === "5" ? indexedRgb(Number(parts[i + 2])) : parts.slice(i + 2, i + 5).map(Number);
            if (rgb.some(value => !Number.isInteger(value) || value < 0 || value > 255)) throw new SyntaxError("unsupported-colour");
            const slot = parts[i + 1] === "5" && Number(parts[i + 2]) < 16 ? Number(parts[i + 2]) : nearestAnsi(rgb);
            out.push(String((slot >= 8 ? 90 : 30) + (n === 48 ? 10 : 0) + slot % 8));
            i += count;
        } else out.push(parts[i]);
    }
    return out.join(";");
}

function fastfetchColor(value) {
    if (/^\u001b\[/.test(value)) return value.replace(/^(\u001b\[)([0-9;]*)(m?)$/, (_, open, code, close) => open + themedSgr(code) + close);
    if (/^[0-9;]+$/.test(value)) return themedSgr(value);
    // Named colours and attribute prefixes stay as written. Only a trailing
    // RGB/index literal needs conversion; fastfetch accepts both forms.
    return value.replace(/(?:#[0-9a-f]{3}(?:[0-9a-f]{3})?|@\d+)$/i, color => color[0] === "@" && Number(color.slice(1)) < 16 ? color
        : ansiName(color[0] === "@" ? nearestAnsi(indexedRgb(Number(color.slice(1)))) : literalAnsi(color), "light_"));
}

function fastfetchSelected(text) {
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
        const color = name === "keyColor" || name === "outputColor" || name === "color" || key.includes("color");
        if (color && node.kind !== "object" && node.kind !== "array") {
            if (node.kind !== "string" && plain.slice(node.start, node.end) !== "null") throw new SyntaxError("not-a-string");
            if (node.kind === "string") {
                const current = JSON.parse(text.slice(node.start, node.end));
                const changed = fastfetchColor(current);
                if (changed !== current) edits.push({ ...node, value: JSON.stringify(changed) });
            }
        } else if (node.kind === "string" && key[0] === "modules" && (name === "key" || name === "format")) {
            const raw = text.slice(node.start + 1, node.end - 1);
            // Keep reset and text attributes; replace only SGR colour codes.
            // fastfetch accepts RGB or ANSI names in {#...} placeholders.
            const changed = raw.replace(/\{#([^{}]+)\}/g, (whole, code) => {
                if (["keys", "title", "output", "separator"].includes(code)) return whole;
                if (/^[0-9;]+$/.test(code)) {
                    return "{#" + themedSgr(code) + "}";
                }
                return "{#" + fastfetchColor(code) + "}";
            }).replace(/(?<!\\)((?:\\\\)*)(\\u001[bB]\[)([0-9;]*)(m)/g,
                (_, literal, open, code, close) => literal + open + themedSgr(code) + close);
            if (changed !== raw) edits.push({ start: node.start + 1, end: node.end - 1, value: changed });
        }
    };
    walk(jsonSpan(plain, 0), []);
    return replaceSpans(text, edits);
}

function appSelectedText(format, text, values) {
    if (text === undefined) return { ok: false, reason: ABSENT, detail: "" };
    try {
        switch (format) {
        case "starship": case "yazi": case "television": return tomlAppSelected(format, text);
        case "fastfetch": return fastfetchSelected(text);
        case "bat": return batSelected(text, values);
        default: throw new Error("theme-select: unknown app " + format);
        }
    } catch (e) {
        if (!(e instanceof SyntaxError)) throw e;
        return { ok: false, reason: REFUSED, detail: "format=" + format + " cause=" + e.message };
    }
}

// Migrate literal calls to the former VGS helper without reading strings or
// comments as Lisp. A computed reference to that helper must stay intact.
function emacsStartupText(text, previous, line) {
    if (text === undefined) return text;
    const edits = [];
    const literal = JSON.stringify(previous);
    const space = start => {
        let at = start;
        while (at < text.length) {
            if (/\s/.test(text[at])) at++;
            else if (text[at] === ";") {
                const end = text.indexOf("\n", at);
                at = end === -1 ? text.length : end + 1;
            } else break;
        }
        return at;
    };
    const conflict = () => { throw new SyntaxError("computed-emacs-loader"); };
    // Lisp quote and vectors are data. Backquote's comma forms can execute,
    // so retain the data and refuse a helper reference in an unquote.
    const form = (start, mode) => {
        let at = space(start);
        if (at === text.length) return at;
        if (text[at] === "'") return form(at + 1, mode === "backquote" ? mode : "data");
        if (text[at] === "`") return form(at + 1, mode === "data" ? "data" : "backquote");
        if (text[at] === "," && mode === "backquote") return form(at + (text[at + 1] === "@" ? 2 : 1), "unsafe");
        if (text.startsWith("#'", at)) return form(at + 2, mode === "data" || mode === "backquote" ? mode : "unsafe");
        if (text[at] === '"') {
            let end = at + 1;
            while (end < text.length && text[end] !== '"') end += text[end] === "\\" ? 2 : 1;
            end = Math.min(end + 1, text.length);
            if (mode !== "data" && mode !== "backquote" && text.slice(at, end) === literal) conflict();
            return end;
        }
        if (text[at] === "(" || text[at] === "[") {
            const close = text[at] === "(" ? ")" : "]";
            const call = text[at] === "(" ? /^\((load|load-file|load-theme)\s+("(?:\\.|[^"\\])*"|'vgs)(?:\s+(?:nil|t))*\s*\)/.exec(text.slice(at)) : null;
            if (call !== null && (call[1] === "load-theme" ? call[2] === "'vgs" : call[2] === literal)) {
                if (mode === "unsafe") conflict();
                if (mode === "code") edits.push({ start: at, end: at + call[0].length, value: line });
                return at + call[0].length;
            }
            const head = space(at + 1);
            const quoted = mode !== "backquote" && (text[at] === "[" || /^quote(?=[\s();])/.test(text.slice(head)));
            const childMode = quoted ? "data" : mode;
            at++;
            while ((at = space(at)) < text.length && text[at] !== close) at = form(at, childMode);
            return Math.min(at + 1, text.length);
        }
        // Escaped symbol characters and character literals do not delimit a
        // form; in particular ?\( must not start a loader-looking list.
        if (text[at] === "?") return Math.min(at + (text[at + 1] === "\\" ? 3 : 2), text.length);
        do { at += text[at] === "\\" ? 2 : 1; }
        while (at < text.length && !/[\s()[\]'"`,;]/.test(text[at]));
        return at;
    };
    try {
        for (let at = 0; at < text.length;) at = form(at, "code");
        return replaceSpans(text, edits) ?? text;
    } catch (e) {
        if (!(e instanceof SyntaxError)) throw e;
        return { ok: false, reason: "wiring-conflict", detail: "form=" + e.message };
    }
}

module.exports = { selectedText, appSelectedText, yaziFlavorText, emacsStartupText };
