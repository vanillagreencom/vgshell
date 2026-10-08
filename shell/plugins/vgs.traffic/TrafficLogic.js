// One formatter for the bar, its tooltip and the per-app view.
function formatRate(rate) {
    if (rate === null || rate === undefined || !Number.isFinite(rate) || rate < 0) return "--";
    const units = ["B/s", "KB/s", "MB/s", "GB/s"];
    let value = rate;
    let unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
        value /= 1024;
        unit++;
    }
    return value.toFixed(unit === 0 ? 0 : 1) + " " + units[unit];
}
