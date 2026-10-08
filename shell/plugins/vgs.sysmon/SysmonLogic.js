.pragma library

function number(text) {
    if (typeof text !== "string" || !/^\s*\d+(?:\.\d+)?\s*$/.test(text)) return null;
    const value = Number(text);
    return Number.isFinite(value) ? value : null;
}

function temperature(text) {
    if (typeof text !== "string" || !/^\s*-?\d+\s*$/.test(text)) return null;
    const value = Number(text);
    return Number.isSafeInteger(value) ? value / 1000 : null;
}

function cpuCounters(text) {
    if (typeof text !== "string") return null;
    const lines = text.split(/\r?\n/);
    const fields = lines[0].trim().split(/\s+/);
    if (fields[0] !== "cpu" || fields.length < 9) return null;
    // Linux counts guest time in user/nice already. iowait is idle time:
    // https://docs.kernel.org/filesystems/proc.html#miscellaneous-kernel-statistics-in-proc-stat
    const counters = fields.slice(1, 9).map(number);
    if (counters.some(value => !Number.isSafeInteger(value))) return null;
    const total = counters.reduce((sum, value) => sum + value, 0);
    if (!Number.isSafeInteger(total)) return null;
    return { total: total, idle: counters[3] + counters[4],
        cores: lines.filter(line => /^cpu\d+\s/.test(line)).length, counters: counters };
}

function cpuUse(previous, current) {
    if (previous === null || current === null || previous === undefined || current === undefined) return null;
    if (current.counters.some((value, index) => value < previous.counters[index])) return null;
    const total = current.total - previous.total;
    const idle = current.idle - previous.idle;
    return total > 0 && idle >= 0 && idle <= total ? (total - idle) / total * 100 : null;
}

function memory(text) {
    const fields = {};
    String(text || "").split(/\r?\n/).forEach(line => {
        const match = /^(MemTotal|MemAvailable|SwapTotal|SwapFree):\s+(\d+)\s+kB\s*$/.exec(line);
        if (!match) return;
        const value = Number(match[2]) * 1024;
        fields[match[1]] = Object.prototype.hasOwnProperty.call(fields, match[1])
            || !Number.isSafeInteger(value) ? null : value;
    });
    const total = fields.MemTotal === undefined ? null : fields.MemTotal;
    const available = fields.MemAvailable === undefined ? null : fields.MemAvailable;
    const swapTotal = fields.SwapTotal === undefined ? null : fields.SwapTotal;
    const swapFree = fields.SwapFree === undefined ? null : fields.SwapFree;
    const used = total !== null && available !== null && available <= total ? total - available : null;
    const swapUsed = swapTotal !== null && swapFree !== null && swapFree <= swapTotal ? swapTotal - swapFree : null;
    return { total: total, available: available, used: used,
        use: used !== null && total > 0 ? used / total * 100 : null,
        swapTotal: swapTotal, swapUsed: swapUsed,
        swapUse: swapUsed === null ? null : swapTotal === 0 ? 0 : swapUsed / swapTotal * 100 };
}

function chooseCpuTemperature(devices, thermalZones) {
    const labels = [{ name: "k10temp", label: "Tctl" }, { name: "zenpower", label: "Tdie" },
        { name: "coretemp", label: "Package id 0" }];
    for (let i = 0; i < labels.length; i++) {
        for (let j = 0; j < devices.length; j++) {
            if (devices[j].name !== labels[i].name) continue;
            const sensor = devices[j].temperatures.find(row => row.label === labels[i].label);
            if (sensor) return sensor.path;
        }
    }
    const zone = thermalZones.find(row => row.type === "x86_pkg_temp");
    return zone ? zone.path : null;
}

function amdGpu(files) {
    const use = number(files.use);
    return { use: use !== null && use <= 100 ? use : null,
        vramUsed: number(files.vramUsed), vramTotal: number(files.vramTotal),
        temperature: temperature(files.temperature) };
}

function csvFields(line) {
    const fields = [];
    let field = "", quoted = false;
    for (let i = 0; i < line.length; i++) {
        const char = line[i];
        if (char === '"') {
            if (quoted && line[i + 1] === '"') { field += '"'; i++; }
            else quoted = !quoted;
        } else if (char === "," && !quoted) { fields.push(field.trim()); field = ""; }
        else field += char;
    }
    if (quoted) return null;
    fields.push(field.trim());
    return fields;
}

function nvidiaRows(text) {
    const rows = [];
    String(text || "").split(/\r?\n/).forEach(line => {
        const fields = csvFields(line);
        if (fields === null || fields.length !== 7) return;
        const pci = /^(?:0000)?([0-9a-f]{4}:[0-9a-f]{2}:[0-9a-f]{2}\.[0-7])$/i.exec(fields[1]);
        const index = number(fields[0]);
        if (!pci || !Number.isSafeInteger(index) || fields[2] === "") return;
        const use = number(fields[3]), used = number(fields[4]), total = number(fields[5]);
        rows.push({ id: pci[1].toLowerCase(), index: index, name: fields[2],
            use: use !== null && use <= 100 ? use : null,
            vramUsed: used === null ? null : used * 1048576,
            vramTotal: total === null ? null : total * 1048576,
            temperature: number(fields[6]) });
    });
    return rows;
}

function tone(value, warning, danger) {
    return typeof value !== "number" || !Number.isFinite(value) ? "normal"
        : value >= danger ? "danger" : value >= warning ? "warning" : "normal";
}

function orderGpus(rows) {
    return rows.slice().sort((a, b) => Number(!!b.discrete) - Number(!!a.discrete)
        || (b.vramTotal || 0) - (a.vramTotal || 0) || a.id.localeCompare(b.id));
}

function selectedGpu(rows, configured) {
    return configured === "" ? rows[0] || null : rows.find(row => row.id === configured) || null;
}
