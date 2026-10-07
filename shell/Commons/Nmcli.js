.pragma library
// nmcli's terse table escapes colons and backslashes with a backslash.
// https://networkmanager.dev/docs/api/latest/nmcli.html
function fields(text) {
    const out = [""];
    let escaped = false;
    for (const c of String(text)) {
        if (escaped) { out[out.length - 1] += c; escaped = false; }
        else if (c === "\\") escaped = true;
        else if (c === ":") out.push("");
        else out[out.length - 1] += c;
    }
    if (escaped) return null;
    return out;
}
