import QtQml

// Unit clock boundary only: Date.now exercises SessionLock's production
// release operations and Qt Timer. It proves no monotonic or suspend
// behavior; the nested capability/lock rows use QS 0.3.1 ElapsedTimer.
QtObject {
    property double started: 0
    function restart() { const previous = elapsedMs(); started = Date.now(); return previous / 1000; }
    function elapsedMs() { return Date.now() - started; }
}
