.pragma library

function htmlEscape(text) {
    return String(text).replace(/[&<> "]/g, ch => {
        if (ch === "&") return "&amp;";
        if (ch === "<") return "&lt;";
        if (ch === ">") return "&gt;";
        if (ch === " ") return "\u00a0";
        return "&quot;";
    });
}

function colorFromRgb(parts, start) {
    const r = Number(parts[start]);
    const g = Number(parts[start + 1]);
    const b = Number(parts[start + 2]);
    if (!isFinite(r) || !isFinite(g) || !isFinite(b)) return null;
    return "#" + [r, g, b].map(v => {
        const channel = Math.max(0, Math.min(255, Math.round(v)));
        return channel.toString(16).padStart(2, "0");
    }).join("");
}

function newestFrame(previous, next) {
    return next;
}

function closeSpan(style) {
    return style.open ? "</font>" : "";
}

function openSpan(style) {
    if (style.fg === "") return "";
    style.open = true;
    return "<font color=\"" + style.fg + "\">";
}

function sameStyle(a, b) {
    return a.fg === b.fg;
}

function parseSgr(sequence, style) {
    const parts = sequence.length === 0 ? ["0"] : sequence.split(";");
    const next = { fg: style.fg };
    for (let i = 0; i < parts.length; i++) {
        const code = parts[i] === "" ? 0 : Number(parts[i]);
        if (code === 0) {
            next.fg = "";
        } else if (code === 39) {
            next.fg = "";
        } else if ((code === 38 || code === 48) && parts[i + 1] === "2") {
            const color = colorFromRgb(parts, i + 2);
            if (color !== null && code === 38) next.fg = color;
            i += 4;
        }
    }
    return next;
}

function parseFrame(frame) {
    const rows = [];
    let current = "";
    let style = { fg: "", open: false };
    let wanted = { fg: "" };
    const escapePattern = /\u001b(?:\[([0-9;?]*)([A-Za-z~])|.)/g;

    function applyStyle(next) {
        if (sameStyle(style, next)) return;
        current += closeSpan(style);
        style = { fg: next.fg, open: false };
        current += openSpan(style);
    }

    function finishRow() {
        current += closeSpan(style);
        rows.push(current);
        current = "";
        style = { fg: wanted.fg, open: false };
        current += openSpan(style);
    }

    function addText(text) {
        const parts = text.replace(/\r/g, "").split("\n");
        for (let i = 0; i < parts.length; i++) {
            current += htmlEscape(parts[i]);
            if (i !== parts.length - 1) finishRow();
        }
    }

    let last = 0;
    let match;
    while ((match = escapePattern.exec(frame)) !== null) {
        addText(frame.slice(last, match.index));
        if (match[2] === "m") {
            wanted = parseSgr(match[1] || "", wanted);
            applyStyle(wanted);
        }
        last = escapePattern.lastIndex;
    }
    addText(frame.slice(last));
    if (current !== "" || rows.length === 0) finishRow();
    return rows;
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
