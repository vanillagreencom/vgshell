pragma Singleton
import QtQuick
import Quickshell

// The directories the shell reads user files from. Derived once here;
// Config reads shell.json and ThemeSource reads theme.json under configDir,
// stateDir is where `vgshell theme` keeps what it applied, and configHome
// is where other applications keep theirs.
Singleton {
    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
    readonly property string configDir: configHome + "/vgshell"
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/vgshell"
}
