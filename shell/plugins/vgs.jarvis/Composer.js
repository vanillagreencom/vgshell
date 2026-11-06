.pragma library
.import "Session.js" as Session

// Shared by the console and its service's text offer. These are the existing
// typed-turn admission causes, not a second readiness judge.
function refusalText(key) {
    if (key === null) return "";
    if (key === "muted") return "Jarvis is muted. Unmute Jarvis before typing.";
    if (key === "speaking") return "Jarvis is speaking. Wait for it to finish, or press Stop.";
    if (key === "busy") return "Jarvis is working. Wait, or press Stop.";
    if (key === "held") return "Jarvis is waiting for your answer. Confirm or cancel the request first.";
    if (key === "duplex") return "This voice provider takes speech only. Change the voice provider to type to Jarvis.";
    return "Jarvis is not ready. Check its Setup tab.";
}

function draft(current, text, state) {
    // Whitespace is the user's text too; trim only tests the incoming message.
    if (current !== "") return { ok: false, reason: "The Jarvis console already holds your draft. Send it or clear it before retrying Diagnose." };
    const refusal = Session.sayRefusal(state);
    if (refusal !== null) return { ok: false, reason: refusalText(refusal) };
    if (typeof text !== "string" || text.trim() === "" || text.length > Session.TRANSCRIPT_CHARS
            || /[\x00-\x08\x0b-\x1f\x7f]/.test(text))
        return { ok: false, reason: "This message does not fit the Jarvis console. Shorten it before retrying." };
    return { ok: true, reason: "" };
}
