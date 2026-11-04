.pragma library

// How a screen's held frame is cut into the bands FreezeHost writes (D118).
// Each band is one ItemGrabResult.saveToFile on the GUI thread, which has no
// thread of its own: a whole 6016x3384 frame took 29-43 ms and a whole
// 2880x5120 one 23-26 ms there, past a 16.7 ms frame (nested sandbox,
// NVIDIA, Qt 6.12.0, threaded render loop; VGS-2232 run notes, unit
// VGS-2232-measure-1793759881). A band holds at most BAND_PIXELS device
// pixels, so one GUI turn saves at most that much; scripts/smoke/rows/capture.sh
// reads the longest GUI busy span the chain leaves.
var BAND_PIXELS = 2000000;

function gcd(a, b) {
    while (b !== 0) {
        const r = a % b;
        a = b;
        b = r;
    }
    return a;
}

function lcm(a, b) {
    return a / gcd(a, b) * b;
}

// The frame of a WIDTH x HEIGHT logical screen whose window draws at OWN
// 120ths of a device pixel per logical pixel, written at AT 120ths (AT >= OWN):
// { width, height, targetWidth, bands: [{ y, rows, height, targetHeight }] },
// the frame's and each band's `height` in device pixels, a band's `y` and
// `rows` in logical pixels, and a target the grab's size in the window's
// logical pixels. A ratio comes in 120ths because wp-fractional-scale-v1
// sends a scale as numerator over 120, which Qt's Wayland plugin divides
// by 120.0. A grab's image is its target size times the window's ratio,
// each side rounded (Qt 6.12 qquickitemgrabresult.cpp render,
// `d->textureSize * d->devicePixelRatio`, QSize times qreal through
// qRound), so a size here is computed the same way. A band's logical rows
// are a multiple of the step at which every size it spans is whole, so a
// band starts on a device row of both ratios. At a ratio where the
// screen's size is not whole, its frame can be a pixel larger or smaller
// than grim draws that screen at that scale; the helper composes the frame
// it gets.
function frame(width, height, own, at) {
    const ratio = own / 120;
    const targetWidth = Math.round(width * at / own);
    const deviceWidth = Math.round(targetWidth * ratio);
    const step = lcm(lcm(120 / gcd(own, 120), 120 / gcd(at, 120)), own / gcd(own, at));
    const rows = Math.max(step, Math.floor(BAND_PIXELS / deviceWidth * 120 / at / step) * step);
    const bands = [];
    let deviceHeight = 0;
    for (let y = 0; y < height; y += rows) {
        const count = Math.min(rows, height - y);
        const targetHeight = Math.round(count * at / own);
        const band = { y: y, rows: count, height: Math.round(targetHeight * ratio), targetHeight: targetHeight };
        bands.push(band);
        deviceHeight += band.height;
    }
    return { width: deviceWidth, height: deviceHeight, targetWidth: targetWidth, bands: bands };
}
