.pragma library

// Which workspace pills one bar draws: the workspaces Hyprland holds, as
// qs.Commons Workspaces lists them, and, with "Show empty workspaces", the
// numbered workspaces the user's workspace rules name (capability
// `hyprland`'s `workspaceRules`). Widget.qml binds the result.

// The output a rule's MONITOR names among MONITORS, Workspaces.monitors:
// a `desc:` monitor is the first whose description starts with the rest,
// trimmed; any other monitor is its output name. "" for a rule with no
// monitor or none that matches. The description is the short one Hyprland
// lists, make, model and serial; Hyprland binds the rule against the full
// description, which adds " (<connector>)" (Hyprland 0.57.2
// src/output/Monitor.cpp, src/ipc/s1/Commands.cpp,
// src/config/shared/workspace/WorkspaceRuleManager.cpp
// getBoundMonitorForWS, src/state/MonitorQueryCore.cpp). So every rule this
// finds binds there too, and a rule whose text runs into that suffix binds
// in Hyprland and shows on no bar here.
function ruleOutput(monitor, monitors) {
    if (monitor.indexOf("desc:") !== 0) return monitor;
    var start = monitor.slice(5).trim();
    for (var i = 0; i < monitors.length; i++)
        if (monitors[i].description.indexOf(start) === 0) return monitors[i].name;
    return "";
}

// The pills, [{ id, active }] in id order. ITEMS is Workspaces.items;
// RULES the workspace rules, or null to show none of them; MONITORS
// Workspaces.monitors; SCREEN the output this bar draws on with "Split by
// display" on, else "". With SCREEN, a bar shows only the
// workspaces its monitor holds, an empty one by the monitor its first rule
// names, none for a rule with no monitor, and lights the workspace its
// monitor shows; without it every bar shows every workspace and lights the
// focused one, FOCUSED_ID.
function pills(items, rules, monitors, screen, focusedId) {
    var out = [];
    var held = {};
    for (var i = 0; i < items.length; i++) {
        held[items[i].id] = true;
        if (screen === "" || items[i].output === screen)
            out.push({ id: items[i].id, active: screen === "" ? items[i].id === focusedId : items[i].active });
    }
    var named = {};
    for (var r = 0; rules !== null && r < rules.length; r++) {
        var rule = rules[r];
        if (rule.id === null || held[rule.id] === true || named[rule.id] === true) continue;
        named[rule.id] = true;
        if (screen === "" || ruleOutput(rule.monitor, monitors) === screen)
            out.push({ id: rule.id, active: false });
    }
    out.sort(function (a, b) { return a.id - b.id; });
    return out;
}
