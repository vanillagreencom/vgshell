.pragma library

// The view PART belongs to: the `view` its page names, else the nearest
// FirstView it stands in, which it registers with. A part in neither
// builds at once, after one error line naming NOUN, the part's kind.
function join(part, noun) {
    if (part.view !== null) {
        part.view.register(part);
        return;
    }
    for (let at = part.parent; at !== null; at = at.parent)
        if (at.firstViewRoot === true) {
            part.view = at;
            at.register(part);
            return;
        }
    console.error("first-view: " + noun + " outside a FirstView; built at once");
    part.buildAlone();
}
