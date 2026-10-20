import QtQuick

// Stands in for Quickshell's Region, whose plugin does not load outside
// the shell: a window's input mask, which a plain Qt window under the unit
// tests never applies. The nested sandbox proves what a mask takes.
QtObject {}
