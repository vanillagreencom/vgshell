.pragma library

// The Remote desktop plugin's pure decisions, shared by Service.qml,
// Widget.qml and Pane.qml. No QML object and no I/O.

// The sessions helper/sessions.py `list` printed, one JSON object a line.
// Throws on a line that is not one, since a bad reading is no idle reading.
function parseSessions(text) {
    return String(text).split("\n").filter(line => line.trim() !== "").map(line => {
        const row = JSON.parse(line);
        if (typeof row.pid !== "number" || typeof row.start !== "string" || typeof row.peer !== "string")
            throw new Error("remote-desktop: session line " + line);
        return row;
    });
}

// The `session` status value: { active, peers }, each peer { address,
// name } once per address, `name` the SSH alias whose own HostName or
// alias is the address, "" for none. HOSTS is hosts.py's list.
function sessionValue(sessions, hosts) {
    const peers = [];
    sessions.forEach(row => {
        if (row.peer === "" || peers.some(peer => peer.address === row.peer)) return;
        const host = hosts.find(h => h.hostname === row.peer || h.alias === row.peer);
        peers.push({ address: row.peer, name: host === undefined ? "" : host.alias });
    });
    return { active: sessions.length > 0, peers: peers };
}

// The indicator's tooltip, { title, details }: Omarchy's "Remote session
// from <addresses>", naming the computer where SSH names it, so the owner
// sees who is connected, with a line per viewer.
function tooltip(session) {
    const peers = session.peers;
    const line = peer => peer.name === "" ? peer.address : peer.name + " · " + peer.address;
    if (peers.length === 0) return { title: "Remote session", details: [] };
    if (peers.length === 1) {
        const only = peers[0];
        return only.name === "" ? { title: "Remote session from " + only.address, details: [] }
            : { title: "Remote session from " + only.name, details: [line(only)] };
    }
    return { title: "Remote session from " + peers.length + " computers", details: peers.map(line) };
}

// TEXT cut to MAX characters with an ellipsis: the core refuses a whole
// status write when one label is longer than its bound (PluginLogic.js
// STATUS_LABEL_MAX, MENU_TEXT_MAX, MENU_DESCRIPTION_MAX).
function fit(text, max) {
    return text.length <= max ? text : text.slice(0, max - 1) + "…";
}

// The `hosts` choices the Computer field offers: every SSH alias, its
// label fit to 60 and its value whole, up to a status text's 200.
function hostChoices(hosts) {
    return hosts.filter(host => host.alias.length <= 200).slice(0, 64).map(host => ({ label: fit(host.alias, 60), value: host.alias }));
}

// The profiles to seed once from SSH: one per alias known_hosts holds,
// except code forges, whose SSH user is `git` or `aur`. Each holds the
// manifest's `defaults` and a name, the lowest free whole number, as the
// Settings list names a new item.
function seedProfiles(hosts, defaults) {
    return hosts.filter(host => host.known && host.user !== "git" && host.user !== "aur")
        .map((host, index) => Object.assign({ name: String(index + 1) }, defaults, { host: host.alias }));
}

// PROFILE's screen and window as the Settings page labels them, from the
// manifest's list ITEMS: "Private screen · Full screen".
function summary(profile, items) {
    const label = field => (items[field].options.find(option => option.value === profile[field]) || { label: profile[field] }).label;
    return label("screen") + " · " + label("window");
}

// A host gliff hands to ssh after `--`: an alias, a name or `user@host`.
const HOST = /^[A-Za-z0-9_][A-Za-z0-9._-]*(@[A-Za-z0-9_][A-Za-z0-9._:-]*)?$/;
const OUTPUT = /^[A-Za-z0-9-]+$/;
const FLAGS = {
    screen: { active: [], private: ["--headless"] },
    video: { auto: [], gpu: ["--video", "gpu"], cpu: ["--video", "cpu"] },
    picture: { auto: [], "low-bandwidth": ["--low-bandwidth"], "full-chroma": ["--full-chroma"] },
    capture: { auto: [], dmabuf: ["--capture", "dmabuf"], shm: ["--capture", "shm"] }
};

// { argv } for PROFILE, or { field } naming the field that keeps it from
// connecting: `host`, or `output` for One screen with no screen name.
// gliff passes the host to ssh and the remote shell parses the
// --server-bin value, so both hold only judged words, and the server flags
// only enum values and a number. gliff 0.4.1's options: omacom/gliff
// crates/gliff/src/main.rs struct Cli, and the server's
// crates/gliff-server/src/main.rs struct Cli, which the client reaches
// only through --server-bin.
function argv(profile) {
    if (!HOST.test(profile.host)) return { field: "host" };
    if (profile.screen === "one" && !OUTPUT.test(profile.output)) return { field: "output" };
    const screen = profile.screen === "one" ? ["--output", profile.output] : FLAGS.screen[profile.screen];
    const server = FLAGS.picture[profile.picture].concat(FLAGS.capture[profile.capture],
        profile.bitrate > 0 ? ["--bitrate", String(Math.round(profile.bitrate * 1000000))] : []);
    return { argv: ["gliff", "--release-hotkey", profile.releaseKey]
        .concat(profile.clipboard ? [] : ["--no-clipboard"], FLAGS.video[profile.video], screen,
            server.length === 0 ? [] : ["--server-bin", ["gliff-server"].concat(server).join(" ")], ["--", profile.host]) };
}

// The `connectRows` launcher rows: one Connect entry per profile with a
// host, its id the profile's name, which the `connect` shortcut takes, and
// its screen and window beside the host, so two profiles of one computer
// read apart.
function launcherRows(profiles, items) {
    return profiles.filter(profile => profile.host !== "").map(profile => ({
        id: profile.name, label: fit("Connect to " + profile.host, 60), icon: "screen-share",
        description: fit(profile.host + " · " + summary(profile, items), 120), aliases: ["remote desktop", "gliff"]
    }));
}

// Each reading of the core's `service-sshd` probe: the optional Setup step
// `ssh` and what Hosting says under its switch while hosting is on.
const OFF = "Other computers cannot connect: SSH is off. [Turn on SSH](page:vgs.remote-desktop/Setup/ssh).";
const SSH = {
    ready: { step: { tone: "ok", text: "On" }, line: "" },
    needed: { step: { tone: "warning", text: "Off", hint: "Other computers cannot connect while SSH is off", action: true }, line: OFF },
    nixos: { step: { tone: "warning", text: "Off", hint: "Other computers cannot connect while SSH is off", action: true }, line: OFF },
    absent: { step: { tone: "info", text: "Not installed", hint: "Install SSH to let other computers connect", action: "tools" },
        line: "Other computers cannot connect: SSH is not installed. [Install it](page:vgs.remote-desktop/Setup)." },
    denied: { step: { tone: "info", text: "Blocked", available: false, hint: "The SSH server is masked, which keeps it from starting, and VGS never unmasks it" },
        line: "Other computers cannot connect: the SSH server is masked, which keeps it from starting." },
    unknown: { step: { tone: "info", text: "Not checked", available: false, hint: "VGS could not read whether the SSH server runs" },
        line: "Other computers may not connect: VGS could not read whether SSH runs." }
};

// The `ssh` step, null before the core's first probe, hidden while
// hosting is off.
function sshStep(hosting, ssh) {
    if (!hosting) return { hidden: true };
    return ssh === "" ? null : (SSH[ssh] || SSH.unknown).step;
}

// What the Hosting setting says under its switch, "" for nothing. While
// hosting is on: why other computers cannot connect. While it is off and
// the core reports `pending-restart`, that the change takes full effect at
// the next sign-in, since Hyprland reads permission rules only when it
// starts. SERVER is whether gliff-server is installed. One line of at most
// 200 characters, a status text's bound.
function hostingText(hosting, ssh, server, permission) {
    if (hosting && !server)
        return "Other computers cannot connect: remote desktop is not installed here. [Install it](page:vgs.remote-desktop/Setup).";
    if (hosting)
        return ssh === "" ? "" : (SSH[ssh] || SSH.unknown).line;
    if (permission === "pending-restart")
        return "Hosting off takes full effect after you sign in again. Until then, VGS ends each session it finds.";
    if (permission === "withheld" || permission === "withheld-loaded" || permission === "unwired")
        return "Your Hyprland settings keep VGS from refusing screen capture, so VGS ends each session it finds.";
    return "";
}
