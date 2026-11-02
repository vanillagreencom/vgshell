.pragma library

// Where the Jarvis overlay's dark field lies (Appearance.js `field`): the
// boxes qs.Ui's RadialBackdrop draws, and the rectangle that holds their
// reach. Bubble.qml binds through it, and scripts/shader/Scene.qml draws
// its largest field through it.

// The field's boxes in a layer WIDTH wide: the orb's disc round CENTRE,
// `field.orb.disc` times the orb's ring RING, then one box for each of
// RECTS, `{ rect: { x, y, w, h }, values, recede }`, each the box a column
// of content lays out in, with VALUES its look group, `field.icons` or
// `field.content`. Each content box's fade is cut to end before the
// layer's top or side edge; RECEDE grows its inset by fade × `field.join`
// times it, so a fading box shrinks into the rest.
function boxes(field, centre, ring, rects, width) {
    const disc = field.orb.disc * ring;
    const list = [{ x: centre.x - disc, y: centre.y - disc, w: 2 * disc, h: 2 * disc, corner: disc,
                    peak: field.orb.peak, fade: field.orb.fade, inset: field.orb.inset, ink: field.orb.ink }];
    let room = Infinity;
    for (const { rect } of rects) room = Math.min(room, rect.y, rect.x, width - rect.x - rect.w);
    for (const { rect, values, recede } of rects) {
        const fade = Math.max(1, Math.min(values.fade, values.inset + room));
        list.push({ x: rect.x, y: rect.y, w: rect.w, h: rect.h, corner: Math.min(values.corner, rect.w / 2, rect.h / 2),
                    peak: values.peak, fade: fade, inset: values.inset + fade * field.join * recede, ink: values.ink });
    }
    return list;
}

// The whole-pixel rectangle that holds every box of BOXES with its reach,
// `fade - inset` past its edge, cut to a layer WIDTH by HEIGHT.
function extent(boxes, width, height) {
    let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
    for (const b of boxes) {
        const reach = b.fade - b.inset;
        x0 = Math.min(x0, b.x - reach);
        y0 = Math.min(y0, b.y - reach);
        x1 = Math.max(x1, b.x + b.w + reach);
        y1 = Math.max(y1, b.y + b.h + reach);
    }
    x0 = Math.max(0, Math.floor(x0));
    y0 = Math.max(0, Math.floor(y0));
    return { x: x0, y: y0, w: Math.max(0, Math.min(width, Math.ceil(x1)) - x0), h: Math.max(0, Math.min(height, Math.ceil(y1)) - y0) };
}
