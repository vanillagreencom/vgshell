.pragma library

// What the Passwordless Sudo widget shows and says: its tooltip and the
// notification after a grant or a revoke the user pressed, from the state
// capability `sudo` lends, { state, until }. No QML objects and no I/O, so
// scripts/test-sudo-view.js runs it under node; TIME_OF turns an ISO time
// into the clock text the shell shows.

// MINUTES as words: 1 day, hours, then minutes.
function durationText(minutes) {
    if (minutes === 1440)
        return "1 day";
    var hours = Math.floor(minutes / 60);
    var rest = minutes % 60;
    var parts = [];
    if (hours > 0)
        parts.push(hours === 1 ? "1 hour" : hours + " hours");
    if (rest > 0 || hours === 0)
        parts.push(rest === 1 ? "1 minute" : rest + " minutes");
    return parts.join(" ");
}

// Whether STATE, the lent state or null before the core read it, is an
// active grant.
function active(state) {
    return state !== null && state.state === "active";
}

function tooltip(state, timeOf) {
    if (!active(state))
        return "Passwordless sudo is off";
    if (state.until === "indefinite")
        return "Passwordless sudo is on until you turn it off";
    return "Passwordless sudo is on until " + timeOf(state.until);
}

// The notification for one ended run of ACTION, `grant` or `revoke`,
// pressed while the grant read BEFORE, RESULT being what the run's `done`
// received, { state, until }; NOW_MS the time of the read. null when the
// run changed nothing, as a declined or cancelled grant does. A revoke
// that leaves the grant on says so.
function notice(action, before, result, nowMs, timeOf) {
    var on = result.state === "active";
    if (action === "revoke" && on)
        return { title: "Passwordless sudo is still on", message: "It could not be turned off. Click the lock to try again.", tone: "danger", icon: "lock-open" };
    if (before === "active" && !on)
        return { title: "Passwordless sudo is off", message: "Sudo asks for your password again.", tone: "success", icon: "lock" };
    if (before === "active" || !on)
        return null;
    if (result.until === "indefinite")
        return { title: "Passwordless sudo is on", message: "Until you turn it off. It stays on after a restart.", tone: "warning", icon: "lock-open" };
    var minutes = Math.max(1, Math.round((Date.parse(result.until) - nowMs) / 60000));
    return { title: "Passwordless sudo is on", message: "For " + durationText(minutes) + ", until " + timeOf(result.until) + ".", tone: "warning", icon: "lock-open" };
}
