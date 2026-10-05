.pragma library

// TouchpadScroll's decisions, with no QML objects, so scripts/test-touchpad-
// scroll-logic.js runs them under node: how far a view moves for a finger's
// scroll delta, how far it coasts once the fingers lift, and the velocity
// that makes a Flickable's flick travel that far. A delta is the distance
// the content moves, positive toward its end.

// GTK's numbers (docs/architecture/runtime-pointer.md), so a swipe moves a
// VGS view as far as a GTK list: each pixel of delta moves the content GAIN
// pixels, a coast starts at the mean velocity of the deltas of the last
// VELOCITY_WINDOW_MS and loses FRICTION of its velocity per second.
var GAIN = 2.5;
var FRICTION = 4;
var VELOCITY_WINDOW_MS = 150;

// One delta's move in whole pixels, so text stays on the pixel grid, and
// the fraction it leaves for the next delta: `carry` is the fraction the
// delta before left.
function step(delta, carry) {
    const exact = delta * GAIN + carry;
    const move = Math.round(exact);
    return { move: move, carry: exact - move };
}

// `value` held inside `low` to `high`; a range with no room is `low`.
function clamp(value, low, high) {
    return Math.max(low, Math.min(high, value));
}

// The deltas a coast is read from: `history` without the entries older
// than the window before `at`, a time in ms, and with this delta.
function remember(history, at, dx, dy) {
    const kept = history.filter(entry => entry.at >= at - VELOCITY_WINDOW_MS);
    kept.push({ at: at, dx: dx, dy: dy });
    return kept;
}

// How far the content coasts on each axis once the fingers lift at `at`:
// the velocity of the remembered deltas over GTK's friction. A lift that
// comes a window after the last delta is fingers that rested first, and
// deltas of one moment have no velocity: neither coasts.
function coast(history, at) {
    if (history.length === 0) return { x: 0, y: 0 };
    const first = history[0], last = history[history.length - 1];
    const span = last.at - first.at;
    if (span <= 0 || at - last.at > VELOCITY_WINDOW_MS) return { x: 0, y: 0 };
    let dx = 0, dy = 0;
    for (const entry of history) { dx += entry.dx; dy += entry.dy; }
    const scale = 1000 / span * GAIN / FRICTION;
    return { x: dx * scale, y: dy * scale };
}

// The velocity, in pixels per second, that makes a Flickable whose
// flickDeceleration is `deceleration` flick `distance` pixels: it stops a
// flick of velocity v after v * v / (2 * deceleration). The sign is the
// distance's.
function flickVelocity(distance, deceleration) {
    return Math.sign(distance) * Math.sqrt(2 * deceleration * Math.abs(distance));
}
