.pragma library

// What a hold's still writes (D118): each screen's frames and how each is
// cut into the bands FreezeHost writes.
// Each band is one ItemGrabResult.saveToFile on the GUI thread, which has no
// thread of its own: a whole 6016x3384 frame took 29-43 ms and a whole
// 2880x5120 one 23-26 ms there, past a 16.7 ms frame (nested sandbox,
// NVIDIA, Qt 6.12.0, threaded render loop; VGS-2232 run notes, unit
// VGS-2232-measure-1793759881). A band holds at most BAND_PIXELS device
// pixels, save the one case `frame` names, so one GUI turn saves at most
// that much; scripts/smoke/rows/capture.sh reads the longest GUI busy span
// the chain leaves.
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
// qRound), so a size here is computed the same way.
//
// Bands are cut on device rows of the written frame, in multiples of the
// unit at which a band's rows are whole logical rows of the screen
// (unit * 120 / AT) and its target is whole window pixels (unit * 120 /
// OWN), so every band but the last is exactly its device rows and starts
// on a whole logical row. The unit is at most 112 device rows over the
// ratios of 1, 1.0667, 1.25, 1.3333, 1.5, 1.6, 1.75, 2, 2.5 and 3, so a band
// holds at most BAND_PIXELS unless a frame is wider than BAND_PIXELS over
// its unit (17857 device pixels at 112); such a band is one unit. At a
// ratio where the screen's size is not whole, the last band and with it
// the frame can be a pixel larger or smaller than grim draws that screen
// at that scale; the helper composes the frame it gets.
function frame(width, height, own, at) {
    const ratio = own / 120;
    const targetWidth = Math.round(width * at / own);
    const deviceWidth = Math.round(targetWidth * ratio);
    const unit = lcm(own / gcd(own, 120), at / gcd(at, 120));
    const rows = Math.max(unit, Math.floor(BAND_PIXELS / deviceWidth / unit) * unit) * 120 / at;
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

// The still a hold writes into DIR for SCREENS, [{ name, x, y, width,
// height, ratio }] with each screen's logical rectangle and the ratio its
// surface draws at in 120ths: { screens, jobs }. `screens` is the still's
// answer, sorted by name, each with its frames and their band files;
// `jobs` is every band in the order FreezeHost grabs and saves them,
// { screen, own, logical, targetWidth, frame, band, path }, `frame` the
// answer's frame it belongs to. A screen writes a frame at its own ratio
// and at every greater one in the layout, keyed by the ratio, so a box
// over screens of mixed scales is cropped at the greatest scale it meets,
// as `grim -g` renders one.
function plan(screens, dir) {
    const shown = screens.slice().sort((a, b) => a.name < b.name ? -1 : a.name > b.name ? 1 : 0);
    const ratios = shown.map(screen => screen.ratio).filter((ratio, i, all) => all.indexOf(ratio) === i).sort((a, b) => a - b);
    const answer = [];
    const jobs = [];
    shown.forEach((screen, i) => {
        const entry = { name: screen.name, x: screen.x, y: screen.y, width: screen.width, height: screen.height, frames: [] };
        answer.push(entry);
        for (const at of ratios.filter(ratio => ratio >= screen.ratio)) {
            const cut = frame(screen.width, screen.height, screen.ratio, at);
            const written = { ratio: at, width: cut.width, height: cut.height, bands: [] };
            entry.frames.push(written);
            cut.bands.forEach((band, k) => {
                const path = dir + "/" + i + "-" + at + "-" + k + ".ppm";
                written.bands.push({ path: path, rows: band.height });
                jobs.push({ screen: screen.name, own: screen.ratio, logical: [screen.width, screen.height], targetWidth: cut.targetWidth,
                    frame: written, band: band, path: path });
            });
        }
    });
    return { screens: answer, jobs: jobs };
}
