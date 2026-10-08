.pragma library

function formatRate(rate) {
    if (rate === null || rate === undefined || !Number.isFinite(rate) || rate < 0) return "--";
    const units = ["B/s", "KB/s", "MB/s", "GB/s"];
    let value = rate;
    let unit = 0;
    while (value >= 1024 && unit < units.length - 1) { value /= 1024; unit++; }
    return value.toFixed(unit === 0 ? 0 : 1) + " " + units[unit];
}

function parseNetDev(text) {
    const rows = Object.create(null);
    for (const line of text.split("\n")) {
        const match = /^\s*([^\s:]+):\s*(.+)$/.exec(line);
        if (!match) continue;
        const fields = match[2].trim().split(/\s+/);
        if (fields.length < 16 || !/^\d+$/.test(fields[0]) || !/^\d+$/.test(fields[8])) return null;
        const down = Number(fields[0]), up = Number(fields[8]);
        if (!Number.isSafeInteger(down) || !Number.isSafeInteger(up)) return null;
        rows[match[1]] = { down: down, up: up };
    }
    // Linux always emits the two headers, including with no interfaces.
    return text.indexOf("Inter-") >= 0 && text.indexOf("face") >= 0 ? rows : null;
}

function physicalInterfaces(names, resolved) {
    if (names.length !== resolved.length) return null;
    return names.filter((name, i) => resolved[i].startsWith("/sys/devices/")
        && !resolved[i].startsWith("/sys/devices/virtual/"));
}

function delta(current, previous, seconds) {
    if (current === null || previous === null || current < previous || seconds <= 0 || !Number.isFinite(seconds)) return null;
    return (current - previous) / seconds;
}

function totals(sample, previous, names, at, previousAt) {
    const seconds = (at - previousAt) / 1000;
    const interfaces = names.map(name => {
        const now = sample[name], before = previous === null ? null : previous[name];
        return { name: name, down: now && before ? delta(now.down, before.down, seconds) : null,
            up: now && before ? delta(now.up, before.up, seconds) : null };
    });
    return { interfaces: interfaces,
        down: interfaces.some(row => row.down === null) ? null : interfaces.reduce((sum, row) => sum + row.down, 0),
        up: interfaces.some(row => row.up === null) ? null : interfaces.reduce((sum, row) => sum + row.up, 0) };
}

function loopback(endpoint) {
    const host = endpoint.startsWith("[") ? endpoint.slice(1, endpoint.indexOf("]")) : endpoint.slice(0, endpoint.lastIndexOf(":"));
    return /^127\./.test(host) || host === "::1" || /^::ffff:127\./i.test(host);
}

// ss prints a socket header followed by an indented tcp_info line.
// bytes_acked excludes retransmissions; bytes_sent does not.
// https://man7.org/linux/man-pages/man8/ss.8.html
function parseSockets(text) {
    const sockets = {};
    let count = 0;
    let header = null;
    for (const line of text.split("\n")) {
        if (!/^\s/.test(line) && line.trim() !== "") {
            const fields = line.trim().split(/\s+/);
            const inode = /\bino:(\d+)/.exec(line);
            const user = /users:\(\(\"((?:[^\"\\]|\\.)+)\",pid=\d+/.exec(line);
            header = fields.length >= 5 && inode && inode[1] !== "0" ? {
                inode: inode[1], name: user ? user[1].replace(/\\([\\"])/g, "$1") : "",
                local: fields[3], peer: fields[4]
            } : null;
        } else if (header !== null) {
            const down = /\bbytes_received:(\d+)/.exec(line), up = /\bbytes_acked:(\d+)/.exec(line);
            if (loopback(header.local) || loopback(header.peer)) { header = null; continue; }
            if (!Object.prototype.hasOwnProperty.call(sockets, header.inode) && count >= 4096) { header = null; continue; }
            // ss tcp_stats_print omits zero byte fields; this is not a missing
            // counter: https://github.com/iproute2/iproute2/blob/main/misc/ss.c
            // TIME-WAIT has inode zero and is skipped above.
            const received = down ? Number(down[1]) : 0, acked = up ? Number(up[1]) : 0;
            if (Number.isSafeInteger(received) && Number.isSafeInteger(acked)) {
                if (!Object.prototype.hasOwnProperty.call(sockets, header.inode)) count++;
                sockets[header.inode] = { name: header.name, down: received, up: acked };
            }
            header = null;
        }
    }
    return sockets;
}

function apps(sample, previous, at, previousAt, total) {
    if (previous === null) return { state: "measuring", apps: [], other: { down: null, up: null } };
    const merged = Object.create(null);
    const seconds = (at - previousAt) / 1000;
    for (const inode of Object.keys(sample)) {
        const socket = sample[inode];
        if (socket.name === "") continue;
        const before = previous[inode] || { down: 0, up: 0 };
        const down = delta(socket.down, before.down, seconds), up = delta(socket.up, before.up, seconds);
        const row = merged[socket.name] || { name: socket.name, down: 0, up: 0, connections: 0 };
        row.down = down === null || row.down === null ? null : row.down + down;
        row.up = up === null || row.up === null ? null : row.up + up;
        row.connections++;
        merged[socket.name] = row;
    }
    const rows = Object.keys(merged).map(name => merged[name]).sort((a, b) =>
        (b.down || 0) + (b.up || 0) - (a.down || 0) - (a.up || 0) || a.name.localeCompare(b.name)).slice(0, 50);
    const unknownDown = rows.some(row => row.down === null), unknownUp = rows.some(row => row.up === null);
    const other = {
        down: total.down === null || unknownDown ? null : Math.max(0, total.down - rows.reduce((sum, row) => sum + row.down, 0)),
        up: total.up === null || unknownUp ? null : Math.max(0, total.up - rows.reduce((sum, row) => sum + row.up, 0))
    };
    const active = total.down !== 0 || total.up !== 0 || rows.some(row => row.down !== 0 || row.up !== 0);
    return { state: active ? "ready" : "idle", apps: rows, other: other };
}

function capture(step) {
    const state = step ? step.state : "unknown";
    const text = { ready: "Ready", needed: "Access needed", nixos: "Access needed", absent: "bandwhich is not installed",
        denied: "Installed tool is not trusted", unknown: "Capture access could not be checked" };
    return { tone: state === "ready" ? "ok" : state === "absent" ? "info" : "warning",
        text: text[state] || text.unknown, action: state === "needed" || state === "nixos" };
}
