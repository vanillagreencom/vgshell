import QtQuick
import qs.Commons
import qs.Ui

// A panel background at one level: `base`, `raised` or `sunken` name a
// group of `Theme.surface.level`. A level the theme lacks is logged and
// drawn as base. It is a GlassSurface whose look without glass is that
// level's, so the user's `glass` Appearance value reaches every panel. It
// places nothing: a container lays its content out with `Pane`, which owns
// the inset and clears the rounded corner.
GlassSurface {
    id: root

    property string level: "base"
    readonly property var tokens: levelOf(level)

    function levelOf(name) {
        const found = Theme.surface.level[name];
        if (found !== undefined) return found;
        console.error("Surface: no level named " + JSON.stringify(name));
        return Theme.surface.level.base;
    }

    standard: ({ background: tokens.background, border: tokens.border, radius: Theme.surface.radius })
}
