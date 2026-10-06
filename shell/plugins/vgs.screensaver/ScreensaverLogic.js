.pragma library

var COLOR_CACHE_MAX = 4096;
var KEEP_COLOR = "__keep__";

function createState() {
    return { rawRows: [], rows: [], colorsIn: [], colorsOut: [], cache: ({}), cacheSize: 0, parsedRows: 0, reusedRows: 0 };
}

function htmlEscape(text) {
    return /[&<> ]/.test(text) ? String(text).replace(/[&<> ]/g, ch => {
        if (ch === "&") return "&amp;";
        if (ch === "<") return "&lt;";
        if (ch === ">") return "&gt;";
        return "\u00a0";
    }) : text;
}

function colorFromRgbParts(parts, start) {
    const r = Number(parts[start]);
    const g = Number(parts[start + 1]);
    const b = Number(parts[start + 2]);
    if (!isFinite(r) || !isFinite(g) || !isFinite(b)) return KEEP_COLOR;
    const rc = Math.max(0, Math.min(255, Math.round(r)));
    const gc = Math.max(0, Math.min(255, Math.round(g)));
    const bc = Math.max(0, Math.min(255, Math.round(b)));
    return "#" + (rc < 16 ? "0" : "") + rc.toString(16)
        + (gc < 16 ? "0" : "") + gc.toString(16)
        + (bc < 16 ? "0" : "") + bc.toString(16);
}

function sgrColor(params, state) {
    const key = params === "" ? "0" : params;
    if (state.cache[key] !== undefined) return state.cache[key];
    let color = KEEP_COLOR;
    const parts = key.split(";");
    for (let i = 0; i < parts.length; i++) {
        const code = parts[i] === "" ? 0 : Number(parts[i]);
        if (code === 0 || code === 39) {
            color = "";
        } else if (code === 38 && parts[i + 1] === "2") {
            color = colorFromRgbParts(parts, i + 2);
            i += 4;
        } else if (code === 48 && parts[i + 1] === "2") {
            i += 4;
        }
    }
    state.cache[key] = color;
    state.cacheSize += 1;
    if (state.cacheSize > COLOR_CACHE_MAX) {
        state.cache = ({});
        state.cacheSize = 0;
    }
    return color;
}

function parseRow(raw, color, state) {
    const pieces = [];
    let open = false;
    let current = color;
    if (current !== "") {
        pieces.push("<font color=\"", current, "\">");
        open = true;
    }
    const pattern = /\u001b\[([0-9;?]*)([A-Za-z])|\u001b.|([^\u001b]+)/g;
    let match;
    while ((match = pattern.exec(raw)) !== null) {
        if (match[3] !== undefined) {
            const text = match[3].replace(/\r/g, "");
            if (text !== "") pieces.push(htmlEscape(text));
            continue;
        }
        if (match[2] !== "m") continue;
        const next = sgrColor(match[1] || "", state);
        if (next === KEEP_COLOR || next === current) continue;
        if (open) pieces.push("</font>");
        current = next;
        open = false;
        if (current !== "") {
            pieces.push("<font color=\"", current, "\">");
            open = true;
        }
    }
    if (open) pieces.push("</font>");
    return { row: pieces.join(""), color: current };
}

function parseFrame(frame, previous) {
    const state = previous || createState();
    const rawRows = String(frame).split("\n");
    const rows = [];
    const colorsIn = [];
    const colorsOut = [];
    let parsedRows = 0;
    let reusedRows = 0;
    let color = "";
    for (let i = 0; i < rawRows.length; i++) {
        const raw = rawRows[i];
        colorsIn[i] = color;
        if (state.rawRows[i] === raw && state.colorsIn[i] === color) {
            rows[i] = state.rows[i];
            color = state.colorsOut[i] || "";
            colorsOut[i] = color;
            reusedRows += 1;
            continue;
        }
        const parsed = parseRow(raw, color, state);
        rows[i] = parsed.row;
        color = parsed.color;
        colorsOut[i] = color;
        parsedRows += 1;
    }
    state.rawRows = rawRows;
    state.rows = rows;
    state.colorsIn = colorsIn;
    state.colorsOut = colorsOut;
    state.parsedRows = parsedRows;
    state.reusedRows = reusedRows;
    return state;
}

function effectChoices(helpText) {
    const choices = [{ label: "Random", value: "random" }];
    const seen = { random: true };
    const lines = String(helpText).split(/\r?\n/);
    let inCommands = false;
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        if (/^Commands:\s*$/.test(line)) {
            inCommands = true;
            continue;
        }
        if (inCommands && /^[A-Z][A-Za-z ]+:\s*$/.test(line)) break;
        if (!inCommands) continue;
        const match = /^\s{2,}([a-z0-9-]+)\s+/.exec(line);
        if (!match) continue;
        const value = match[1];
        if (value === "help" || seen[value]) continue;
        seen[value] = true;
        choices.push({ label: value, value: value });
    }
    return choices;
}

function canvasSize(width, height, cellWidth, cellHeight) {
    return {
        columns: Math.max(1, Math.floor(width / Math.max(1, cellWidth))),
        rows: Math.max(1, Math.floor(height / Math.max(1, cellHeight)))
    };
}

function backgroundHex(qtColor) {
    const text = String(qtColor);
    if (/^#[0-9a-fA-F]{8}$/.test(text)) return "#" + text.slice(3);
    if (/^#[0-9a-fA-F]{6}$/.test(text)) return text;
    return "#" + "000000";
}

function fileUrlPath(url) {
    const text = String(url);
    if (text.indexOf("file://") !== 0) return text;
    return decodeURIComponent(text.slice(7));
}

function command(artPath, effect, frameRate, columns, rows, background) {
    const args = ["ttfx", "-i", artPath].concat([
        "--frame-rate", String(frameRate),
        "--canvas-width", String(columns),
        "--canvas-height", String(rows),
        "--ignore-terminal-dimensions",
        "--reuse-canvas",
        "--anchor-canvas", "c",
        "--anchor-text", "c",
        "--no-eol",
        "--no-restore-cursor",
        "--terminal-background-color", background
    ]);
    if (effect === "random" || effect === "") args.push("--random-effect");
    else args.push(effect);
    return args;
}

function newestFrame(previous, next) {
    return next;
}
