// A voice connection's expiry timers. The adapter owns its safe boundary and
// replacement socket; this owner never retries an unrelated transport fault.
"use strict";

// Chosen renewal headroom, not a measured connection latency. Forced renewal
// leaves the adapter's existing handshake allowance before provider expiry.
const RENEW_BEFORE_MS = 60000;
const DEADLINE_MARGIN_MS = 1000;
const REPEAT_LINE = "The voice connection restarted. Please repeat your last sentence.";

// REVISIT(D121): Provider expiry must not decide brain history's lifetime;
// revisit that separation only if the owner changes history semantics.
function create({ clock, connectWait, idle, reconnect }) {
    let expires = null;
    let due = false;
    let closed = false;
    let soft = null;
    let hard = null;
    function clear() {
        if (soft !== null) clock.clear(soft);
        if (hard !== null) clock.clear(hard);
        soft = null;
        hard = null;
    }
    function renew(forced) {
        if (closed) return;
        closed = true;
        clear();
        reconnect(forced);
    }
    function boundary() {
        if (!closed && due && idle()) renew(false);
    }
    return Object.freeze({
        arm(deadline) {
            // A later status cannot extend this connection's original cap.
            if (closed || expires !== null && deadline >= expires) return;
            expires = deadline;
            clear();
            const remaining = deadline - clock.now();
            due = remaining <= RENEW_BEFORE_MS;
            if (!due) soft = clock.set(() => {
                soft = null;
                due = true;
                boundary();
            }, remaining - RENEW_BEFORE_MS);
            hard = clock.set(() => {
                hard = null;
                renew(true);
            }, Math.max(0, remaining - connectWait - DEADLINE_MARGIN_MS));
            boundary();
        },
        boundary,
        close() { closed = true; clear(); }
    });
}

module.exports = { create, REPEAT_LINE };
