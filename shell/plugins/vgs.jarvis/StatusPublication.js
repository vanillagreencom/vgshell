.pragma library

// The core status writer alone judges the aggregate quota. Ask pages are
// optional: retaining them must never prevent the conversation or device
// state from growing within its own existing bounds.
function write(status, key, value) {
    var values = status.values || {};
    var set = function (name, next) { return status.set(name, next); };
    var reply = set(key, value);
    if (reply !== "refused: status=" + key + " reason=size") return reply;
    if (key === "ownerAsks") return set("ownerAsks", null);
    if (values.ownerAsks !== undefined && values.ownerAsks !== null) {
        var released = set("ownerAsks", null);
        if (released !== "ok") return released;
        reply = set(key, value);
    }
    return reply;
}
