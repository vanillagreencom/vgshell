pragma Singleton
import QtQuick

// How far under the baseline the ink of a font's descender letters, g, j,
// p, q and y, reaches, in pixels of the size asked: their outline's depth,
// read unhinted once per family, weight and style at `probeSize` and
// scaled. A link's underline stands under it (Inset.underlineTop). Hinted
// metrics round the depth to a whole pixel of the size they read:
// FontMetrics.tightBoundingRect("gjpqy") in Inter Variable reads 3 at
// 13 px and 4 at 15 px, and unhinted at 64 times the size 2.8125 and 3.25
// (scripts/qml-unit.sh, 2026-10-19), and a place in device pixels needs
// the fraction.
QtObject {
    id: ink

    readonly property int probeSize: 256
    // family|weight|italic -> depth per pixel of size. A plain object: no
    // binding reads it.
    readonly property var known: ({})
    readonly property FontMetrics probe: FontMetrics {}

    function depth(font) {
        const key = font.family + "|" + font.weight + "|" + font.italic;
        let perPixel = known[key];
        if (perPixel === undefined) {
            probe.font = Qt.font({ family: font.family, weight: font.weight, italic: font.italic, pixelSize: probeSize, hintingPreference: Font.PreferNoHinting });
            const box = probe.tightBoundingRect("gjpqy");
            perPixel = (box.y + box.height) / probeSize;
            known[key] = perPixel;
        }
        return perPixel * font.pixelSize;
    }
}
