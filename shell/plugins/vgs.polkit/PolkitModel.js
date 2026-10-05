.pragma library

// Pure decisions for vgs.polkit: what the prompt draws from the polkit
// agent's authentication flow, which process is another agent, and the
// agent status the service publishes. QML owns the agent, the surfaces and
// the password text; the password never passes through here. bin/agents
// runs this file under node for the agent rule and the name.

var DEFAULT_TITLE = "Administrator access";
var DEFAULT_PROMPT = "Password";
var FAILED_NOTE = "The password was not accepted. Try again.";

// pkexec's message, `Authentication is needed to run `<program>' as the
// super user`, names the program; the title names it too. Any other
// action's message stands as it is under the default title.
var PKEXEC_MESSAGE = /^Authentication is (?:needed|required) to run [`']([^`']+)[`'] as /i;

function titleOf(message) {
    var match = PKEXEC_MESSAGE.exec(String(message || ""));
    return match ? "Allow " + match[1] + " to run" : DEFAULT_TITLE;
}

// The PAM prompt without its trailing colon, `Password: ` reading
// `Password`; the default when PAM asked with no text.
function promptOf(inputPrompt) {
    var text = String(inputPrompt || "").replace(/[\s:]+$/, "");
    return text === "" ? DEFAULT_PROMPT : text;
}

// The identity the flow authenticates as: a user's display name, else its
// login name, or `Group <name>` for a group; "" for none.
function identityOf(identity) {
    if (identity === null || identity === undefined) return "";
    var name = String(identity.string || "");
    if (identity.isGroup === true) return name === "" ? "" : "Group " + name;
    var display = String(identity.displayName || "");
    return display !== "" ? display : name;
}

// Every identity FLOW offers, labelled as identityOf labels one, in the
// flow's order; the prompt offers a choice when there are several.
function identitiesOf(flow) {
    var list = flow.identities;
    if (list === null || list === undefined || typeof list.length !== "number") return [];
    var out = [];
    for (var i = 0; i < list.length; i++) out.push(identityOf(list[i]));
    return out;
}

// The index of FLOW's selected identity among its identities, -1 for none.
function identityIndexOf(flow) {
    var list = flow.identities;
    if (list === null || list === undefined || typeof list.length !== "number") return -1;
    for (var i = 0; i < list.length; i++) if (list[i] === flow.selectedIdentity) return i;
    return -1;
}

// The line under the field: PAM's own message, an error or not, else the
// failed note once an attempt failed, else null.
function noteOf(flow) {
    var text = String(flow.supplementaryMessage || "");
    if (text !== "") return { text: text, tone: flow.supplementaryIsError === true ? "danger" : "info" };
    if (flow.failed === true) return { text: FAILED_NOTE, tone: "danger" };
    return null;
}

// What the prompt draws for FLOW, the agent's AuthFlow or a plain object
// with its properties; null while no flow is live. `inputEnabled` holds
// while PAM waits for a response, `waiting` while PAM works on one or has
// not asked yet, so the accept action and the field answer only when a
// response is wanted.
function viewOf(flow) {
    if (flow === null || flow === undefined) return null;
    var required = flow.isResponseRequired === true;
    return {
        title: titleOf(flow.message),
        message: String(flow.message || ""),
        action: String(flow.actionId || ""),
        identity: identityOf(flow.selectedIdentity),
        identities: identitiesOf(flow),
        identityIndex: identityIndexOf(flow),
        prompt: promptOf(flow.inputPrompt),
        echo: flow.responseVisible === true,
        inputEnabled: required,
        waiting: !required,
        note: noteOf(flow)
    };
}

// Whether COMM, a process's name as /proc/<pid>/comm holds it, cut to 15
// bytes, is another polkit agent's: each agent the suite pins names polkit
// or policykit in its program (hyprpolkitagent, polkit-gnome-authentication-
// agent-1, polkit-kde-authentication-agent-1, lxqt-policykit-agent, lxpolkit,
// polkit-mate-authentication-agent-1). polkitd is the daemon and
// polkit-agent-helper-1 the helper every agent runs to check a password.
var AGENT_NAME = /polkit|policykit/i;
var NOT_AGENTS = ["polkitd", "polkit-agent-he"];

function otherAgent(comm) {
    return typeof comm === "string" && AGENT_NAME.test(comm) && NOT_AGENTS.indexOf(comm) === -1;
}

// The name the status row gives a found agent: its PACKAGE, the one the
// Uninstall step removes, else its PROGRAM's file name. Printable ASCII
// alone, at most 64 characters, so the row's line stays one line.
function agentName(pkg, program) {
    var name = String(pkg === null ? program : pkg).replace(/[^!-~]/g, "?").slice(0, 64);
    return name === "" ? "?" : name;
}

// What `bin/agents check` answered, from its exit CODE, null for a run that
// did not start, and its STDOUT: { ok: true, agents, stopped }, each agent
// { name, removable }, or { ok: false } for a run that failed or printed
// anything but its one JSON line.
function readCheck(code, stdout) {
    if (code !== 0) return { ok: false };
    var answer;
    try {
        answer = JSON.parse(stdout);
    } catch (e) {
        return { ok: false };
    }
    if (answer === null || typeof answer !== "object" || !Array.isArray(answer.agents) || typeof answer.stopped !== "number") return { ok: false };
    for (var i = 0; i < answer.agents.length; i++) {
        var agent = answer.agents[i];
        if (agent === null || typeof agent !== "object" || typeof agent.name !== "string" || typeof agent.removable !== "boolean") return { ok: false };
    }
    return { ok: true, agents: answer.agents, stopped: answer.stopped };
}

var READY = "Ready to show password prompts";
// The further lines a state value may carry (PluginLogic.STATUS_LIST_MAX).
var LINES_MAX = 32;

// The `agent` status value, null while there is nothing to say yet.
// polkitd takes one agent per session, so REGISTERED is false while another
// agent holds the session or no polkitd answers. CHECK is readCheck's
// answer for the session, null before one ended, and POLKIT_MISSING whether
// the requirement scan found no polkit. The value names each other agent,
// one line each, and offers the step that makes room: `uninstall` when the
// package manager removes every one of them alone, else `stop`, so the row
// never offers to remove a package another installed package requires;
// with no other agent and no polkit, `install`.
function agentStatus(registered, check, polkitMissing) {
    if (registered === true) return { tone: "ok", text: READY };
    if (check === null) return null;
    if (!check.ok) return { tone: "warning", text: "Password prompts are unavailable. VGS could not look for another app." };
    if (check.agents.length > 0) {
        var lines = check.agents.slice(0, LINES_MAX + 1).map(function (agent) { return "Another app is showing password prompts: " + agent.name + "."; });
        var value = { tone: "warning", text: lines[0], action: check.agents.every(function (agent) { return agent.removable; }) ? "uninstall" : "stop" };
        if (lines.length > 1) value.lines = lines.slice(1);
        return value;
    }
    if (polkitMissing === true) return { tone: "warning", text: "Polkit is not installed.", action: "install" };
    return { tone: "warning", text: "Password prompts are unavailable. No other app is showing them." };
}

// Whether NEXT, an agentStatus value or null, differs from PREVIOUS, the
// value last published or null; a new shell object or a rebuilt binding
// that yields the same state publishes nothing.
function statusChanged(previous, next) {
    if (next === null) return false;
    return previous === null || JSON.stringify(previous) !== JSON.stringify(next);
}

// The end times of the plugin's uninstall and stop TUIs in STATE,
// `shell.tui.state`, as one string: it changes when a run of either ends.
function stepEnds(state) {
    return ["uninstall", "stop"].map(function (name) { return state[name].endedAt; }).join(" ");
}

// Whether closing the prompt must cancel FLOW: a live flow that neither
// completed nor was cancelled. A second cancel of one request is refused.
function cancellable(flow) {
    return flow !== null && flow !== undefined && flow.isCompleted !== true && flow.isCancelled !== true;
}
