.pragma library

// Arguments from a plugin's manifest or request, and vsys's summary, reach
// the same TUI launcher. Missing arguments mean none to that launcher.
var ARGS_MAX = 16;
var ARG_MAX = 256;
var CONTROL_CHARACTER = /[\u0000-\u001f\u007f-\u009f]/;

function valid(args) {
    if (args === undefined)
        return true;
    if (!Array.isArray(args) || args.length > ARGS_MAX)
        return false;
    return args.every(function (arg) {
        return typeof arg === "string" && arg.length > 0 && Array.from(arg).length <= ARG_MAX && !CONTROL_CHARACTER.test(arg);
    });
}
