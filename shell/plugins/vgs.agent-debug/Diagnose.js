.pragma library

// One text template for draft and terminal consumers. ARGS are the scalar
// arguments Debug.crashArgs/taskArgs produce, without the agent argument.
// SKILL is the terminal's copied skill path, or empty when skills load by name.
// No file or log content enters this builder.
function prompt(args, skill) {
    var lines;
    if (args[0] === "crash" && args.length === 6) {
        lines = [
            "A program crashed on this computer and I want to know why.",
            "What systemd-coredump recorded:",
            "- Program: " + args[1],
            "- Process ID: " + args[2],
            "- Binary: " + args[5],
            "- Signal: " + args[3],
            "- Time: " + args[4]
        ];
    } else if (args[0] === "task" && args.length === 7) {
        lines = [
            "A VGS setup task failed on this computer and I want to know why.",
            "- Task: " + args[2] + " the tools of the VGS plugin " + args[1],
            "- Package manager: " + args[3],
            "- Packages: " + args[4],
            "- Time: " + args[5],
            "- Run record: " + args[6]
        ];
    } else {
        throw new Error("diagnose: facts=shape");
    }
    lines.push("Use the vgs-diagnose skill." + (skill === "" ? "" : " If you cannot load skills, read " + skill + " and follow it."));
    lines.push("Diagnose only: change nothing on this computer.");
    return lines.join("\n");
}
