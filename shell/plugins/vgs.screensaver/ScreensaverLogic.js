.pragma library

var COLOR_CACHE_MAX = 4096;
var KEEP_COLOR = "__keep__";
var QUICK_EXIT_MS = 1000;
var QUICK_EXIT_LIMIT = 3;
var CONVERT_LIMIT_MS = 20000;

var ART_PROBLEMS = {
    image: "Cannot read the art image",
    file: "Cannot read the art file",
    type: "Art must be a PNG or SVG image or a text file",
    slow: "The art image took too long to convert",
    magick: "Image art needs ImageMagick",
    awk: "Image art needs awk"
};

function createState() {
    return { rawRows: [], rows: [], colorsIn: [], colorsOut: [], cache: ({}), cacheSize: 0, parsedRows: 0, reusedRows: 0 };
}

function appendText(pieces, text) {
    if (text === "") return;
    if (text.indexOf("\u001b") === -1 && text.indexOf("\r") === -1 && text.indexOf("&") === -1 && text.indexOf("<") === -1 && text.indexOf(">") === -1 && text.indexOf(" ") === -1) {
        pieces.push(text);
        return;
    }
    let out = "";
    for (let i = 0; i < text.length; i++) {
        const ch = text.charAt(i);
        if (ch === "\u001b") {
            i += 1;
        } else if (ch === "\r") {
            continue;
        } else if (ch === "&") {
            out += "&amp;";
        } else if (ch === "<") {
            out += "&lt;";
        } else if (ch === ">") {
            out += "&gt;";
        } else if (ch === " ") {
            // StyledText collapses literal NBSP runs; entities retain cells.
            out += "&nbsp;";
        } else {
            out += ch;
        }
    }
    if (out !== "") pieces.push(out);
}

function colorFromChannels(r, g, b) {
    const rn = Number(r);
    const gn = Number(g);
    const bn = Number(b);
    if (!isFinite(rn) || !isFinite(gn) || !isFinite(bn)) return KEEP_COLOR;
    const rc = Math.max(0, Math.min(255, Math.round(rn)));
    const gc = Math.max(0, Math.min(255, Math.round(gn)));
    const bc = Math.max(0, Math.min(255, Math.round(bn)));
    return "#" + (rc < 16 ? "0" : "") + rc.toString(16)
        + (gc < 16 ? "0" : "") + gc.toString(16)
        + (bc < 16 ? "0" : "") + bc.toString(16);
}

function sgrColor(params, state) {
    const key = params === "" ? "0" : params;
    const cached = state.cache[key];
    if (cached !== undefined) return cached;
    let color = KEEP_COLOR;
    let tokenStart = 0;
    while (tokenStart <= key.length) {
        let tokenEnd = key.indexOf(";", tokenStart);
        if (tokenEnd === -1) tokenEnd = key.length;
        const codeText = key.slice(tokenStart, tokenEnd);
        const code = codeText === "" ? 0 : Number(codeText);
        tokenStart = tokenEnd + 1;
        if (code === 0 || code === 39) {
            color = "";
        } else if (code === 38 || code === 48) {
            let modeEnd = key.indexOf(";", tokenStart);
            if (modeEnd === -1) modeEnd = key.length;
            const mode = key.slice(tokenStart, modeEnd);
            tokenStart = modeEnd + 1;
            if (mode !== "2") continue;
            const rEnd = key.indexOf(";", tokenStart);
            if (rEnd === -1) break;
            const r = key.slice(tokenStart, rEnd);
            const gStart = rEnd + 1;
            const gEnd = key.indexOf(";", gStart);
            if (gEnd === -1) break;
            const g = key.slice(gStart, gEnd);
            const bStart = gEnd + 1;
            let bEnd = key.indexOf(";", bStart);
            if (bEnd === -1) bEnd = key.length;
            if (code === 38) color = colorFromChannels(r, g, key.slice(bStart, bEnd));
            tokenStart = bEnd + 1;
        }
        if (tokenEnd === key.length) break;
    }
    state.cache[key] = color;
    state.cacheSize += 1;
    if (state.cacheSize > COLOR_CACHE_MAX) {
        state.cache = ({});
        state.cacheSize = 0;
    }
    return color;
}

function csiFinalIndex(piece) {
    for (let i = 0; i < piece.length; i++) {
        const code = piece.charCodeAt(i);
        if ((code >= 65 && code <= 90) || (code >= 97 && code <= 122)) return i;
    }
    return -1;
}

function parseRow(raw, color, state) {
    const out = [];
    let open = false;
    let current = color;
    if (current !== "") {
        out.push("<font color=\"", current, "\">");
        open = true;
    }
    const pieces = raw.split("\u001b[");
    appendText(out, pieces[0]);
    for (let i = 1; i < pieces.length; i++) {
        const piece = pieces[i];
        const finalIndex = csiFinalIndex(piece);
        if (finalIndex === -1) continue;
        if (piece.charAt(finalIndex) === "m") {
            const next = sgrColor(piece.slice(0, finalIndex), state);
            if (next !== KEEP_COLOR && next !== current) {
                if (open) out.push("</font>");
                current = next;
                open = false;
                if (current !== "") {
                    out.push("<font color=\"", current, "\">");
                    open = true;
                }
            }
        }
        appendText(out, piece.slice(finalIndex + 1));
    }
    if (open) out.push("</font>");
    return { row: out.join(""), color: current };
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

function fileUrlPath(url) {
    const text = String(url);
    if (text.indexOf("file://") !== 0) return text;
    return decodeURIComponent(text.slice(7));
}

function isArtImage(art) {
    return /\.(png|svg)$/i.test(String(art || ""));
}

function artResult(inUse, next, problem) {
    return { inUse: problem === "" ? next : inUse, problem: problem };
}

function artStatus(problem) {
    if (problem === "") return null;
    return { tone: "warning", text: ART_PROBLEMS[problem] || ART_PROBLEMS.file };
}

function textArtProblem(text) {
    return String(text).indexOf("\u0000") === -1 ? "" : "type";
}

function imageRequirementProblem(missing) {
    const values = missing || [];
    if (values.indexOf("magick") !== -1) return "magick";
    if (values.indexOf("awk") !== -1) return "awk";
    return "";
}

function conversionProblem(code, timedOut) {
    if (timedOut) return "slow";
    return code === 0 ? "" : "image";
}

function retryArtAfterScan(art, problem) {
    return isArtImage(art) && problem !== "" && problem !== "slow";
}

function ttfxReady(missing) {
    return (missing || []).indexOf("ttfx") === -1;
}

function command(artPath, effect, frameRate, columns, rows, background) {
    // The opaque QML canvas color stringifies to ttfx's RGB form;
    // tst_screensaver.qml runs that color-to-command conversion.
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
        "--terminal-background-color", String(background)
    ]);
    if (effect === "random" || effect === "") args.push("--random-effect");
    else args.push(effect);
    return args;
}

function newestFrame(previous, next) {
    return next;
}

function createExitState() {
    return { quickExits: 0 };
}

function effectExitAction(startedAt, endedAt, state) {
    const quick = endedAt - startedAt < QUICK_EXIT_MS;
    state.quickExits = quick ? state.quickExits + 1 : 0;
    if (state.quickExits >= QUICK_EXIT_LIMIT) {
        state.quickExits = 0;
        return "fail";
    }
    return "restart";
}
