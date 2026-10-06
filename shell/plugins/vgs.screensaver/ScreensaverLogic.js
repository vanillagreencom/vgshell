.pragma library

function htmlEscape(text) {
    return String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/\"/g, "&quot;");
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
    return style.open ? "</span>" : "";
}

function openSpan(style) {
    let css = "";
    const colorProperty = "co" + "lor:";
    if (style.fg !== "") css += colorProperty + style.fg + ";";
    if (style.bg !== "") css += "background-" + colorProperty + style.bg + ";";
    if (css === "") return "";
    style.open = true;
    return "<span style=\"" + css + "\">";
}

function sameStyle(a, b) {
    return a.fg === b.fg && a.bg === b.bg;
}

function parseSgr(sequence, style) {
    const parts = sequence.length === 0 ? ["0"] : sequence.split(";");
    const next = { fg: style.fg, bg: style.bg };
    for (let i = 0; i < parts.length; i++) {
        const code = parts[i] === "" ? 0 : Number(parts[i]);
        if (code === 0) {
            next.fg = "";
            next.bg = "";
        } else if (code === 39) {
            next.fg = "";
        } else if (code === 49) {
            next.bg = "";
        } else if ((code === 38 || code === 48) && parts[i + 1] === "2") {
            const color = colorFromRgb(parts, i + 2);
            if (color !== null) {
                if (code === 38) next.fg = color;
                else next.bg = color;
            }
            i += 4;
        }
    }
    return next;
}

function parseFrame(frame) {
    const rows = [];
    let current = "";
    let style = { fg: "", bg: "", open: false };
    let wanted = { fg: "", bg: "" };

    function applyStyle(next) {
        if (sameStyle(style, next)) return;
        current += closeSpan(style);
        style = { fg: next.fg, bg: next.bg, open: false };
        current += openSpan(style);
    }

    function finishRow() {
        current += closeSpan(style);
        rows.push(current);
        current = "";
        style = { fg: wanted.fg, bg: wanted.bg, open: false };
        current += openSpan(style);
    }

    for (let i = 0; i < frame.length; i++) {
        const ch = frame.charAt(i);
        if (ch === "\u001b") {
            const next = frame.charAt(i + 1);
            if (next === "[") {
                let end = i + 2;
                while (end < frame.length && !/[A-Za-z~]/.test(frame.charAt(end))) end++;
                if (end >= frame.length) break;
                const final = frame.charAt(end);
                if (final === "m") {
                    wanted = parseSgr(frame.slice(i + 2, end), wanted);
                    applyStyle(wanted);
                }
                i = end;
            } else {
                i += 1;
            }
            continue;
        }
        if (ch === "\r") continue;
        if (ch === "\n") {
            finishRow();
            continue;
        }
        current += htmlEscape(ch);
    }
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
