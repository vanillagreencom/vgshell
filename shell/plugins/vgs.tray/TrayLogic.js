.pragma library
// Pure decisions for the tray: which bucket each tray item takes, the edits
// the pin and hide toggles make to the two setting lists, the Settings
// choices the service publishes, and the names, tooltips and menu rows the
// widget draws. Widget.qml and Service.qml both decide through here, so the
// bar, the manage popup and the Settings page agree. Each tray item reaches
// these functions as a plain { id, title, tooltipTitle, passive } record.

// The longest status choice label and value the core accepts
// (PluginLogic.STATUS_LABEL_MAX, STATUS_TEXT_MAX) and the most choices one
// list holds (STATUS_LIST_MAX); a longer label is cut, a longer id is left
// out of the choices, and items past the last are left out.
var LABEL_MAX = 60;
var VALUE_MAX = 200;
var CHOICES_MAX = 32;

// A character a status line may not hold, as the core's judge reads it.
var CONTROL_OR_SEPARATOR = /[\u0000-\u001f\u007f-\u009f\u2028\u2029]/g;

// The id a list item names. An empty `item` is the Settings page's first
// offered choice, `firstOffer` here, or no id while nothing is offered.
function itemId(entry, firstOffer) {
    var id = entry !== null && typeof entry === "object" && typeof entry.item === "string" ? entry.item : "";
    return id !== "" ? id : (firstOffer || "");
}

// The ids a `pinned` or `hidden` setting names, in its order; a value that
// is no list names none.
function ids(list, firstOffer) {
    if (!Array.isArray(list)) return [];
    var out = [];
    for (var i = 0; i < list.length; i++) {
        var id = itemId(list[i], firstOffer);
        if (id !== "" && out.indexOf(id) === -1) out.push(id);
    }
    return out;
}

// The buckets of the tray, each a list of { id, index, item }, `index` the
// item's place in `entries` and `item` the entry's own `item`, in that order. A passive item, one the app says needs
// no attention, takes no bucket. Of the others, an id `hidden` names is
// hidden, whatever `pinned` says; then an id `pinned` names is pinned; every
// other item sits in the drawer. `listed` is every item that is not passive,
// the rows the manage popup draws.
function buckets(entries, pinned, hidden) {
    var out = { pinned: [], drawer: [], hidden: [], listed: [] };
    for (var i = 0; i < entries.length; i++) {
        var entry = entries[i];
        if (entry.passive) continue;
        var row = { id: entry.id, index: i, item: entry.item };
        out.listed.push(row);
        if (hidden.indexOf(entry.id) !== -1) out.hidden.push(row);
        else if (pinned.indexOf(entry.id) !== -1) out.pinned.push(row);
        else out.drawer.push(row);
    }
    return out;
}

// The lowest `item-N` name, N from 1, that no item of `list` holds.
function freeName(list) {
    var taken = list.map(function (entry) { return entry.name; });
    for (var n = 1; ; n++)
        if (taken.indexOf("item-" + n) === -1) return "item-" + n;
}

// `list` without its items that name `id`.
function without(list, id, firstOffer) {
    return list.filter(function (entry) { return itemId(entry, firstOffer) !== id; });
}

// The two lists after a toggle of `id`: `kind` "pin" or "hide". A toggle
// on an id its own list names takes it out of that list. Otherwise it adds
// one item for it, under a free name, and takes the id out of the other
// list, so pinning shows a hidden item and hiding unpins it. The answer is
// { pinned, hidden }, each a new list, the input lists untouched.
function toggle(kind, id, pinned, hidden, firstOffer) {
    var lists = { pin: Array.isArray(pinned) ? pinned : [], hide: Array.isArray(hidden) ? hidden : [] };
    var own = lists[kind];
    var other = lists[kind === "pin" ? "hide" : "pin"];
    var named = ids(own, firstOffer).indexOf(id) !== -1;
    var nextOwn = named ? without(own, id, firstOffer) : own.concat([{ name: freeName(own), item: id }]);
    var nextOther = named ? other.slice() : without(other, id, firstOffer);
    return kind === "pin" ? { pinned: nextOwn, hidden: nextOther } : { pinned: nextOther, hidden: nextOwn };
}

// The name of an item, as the manage popup, its icon's label and the
// Settings choices give it: its title, else its tooltip's title, else its
// id after the last slash; "" for an item already gone.
function labelOf(entry) {
    entry = entry || {};
    var title = String(entry.title || "").trim();
    if (title !== "") return title;
    var tip = String(entry.tooltipTitle || "").trim();
    if (tip !== "") return tip;
    var id = String(entry.id || "");
    return id.slice(id.lastIndexOf("/") + 1);
}

// The text of an item's tooltip: its tooltip's title, else its title, else
// its id; "" for an item already gone.
function tooltipOf(entry) {
    entry = entry || {};
    return String(entry.tooltipTitle || entry.title || entry.id || "");
}

// Whether an icon is a symbolic one, whose fixed fill the host is meant to
// recolour: the freedesktop `-symbolic` name suffix, before any query.
function isSymbolic(icon) {
    return String(icon || "").split("?")[0].slice(-9) === "-symbolic";
}

// The `items` choices the service publishes for the Settings page: one
// { label, value } per item that is not passive, its id the value, in tray
// order, each id once. A control character in a label becomes a space and
// a label past LABEL_MAX is cut; an item whose id is empty, holds a control
// character or passes VALUE_MAX is left out, and so is every item past
// CHOICES_MAX.
function choices(entries) {
    var out = [];
    var seen = [];
    for (var i = 0; i < entries.length && out.length < CHOICES_MAX; i++) {
        var entry = entries[i];
        var id = String(entry.id || "");
        if (entry.passive || id === "" || id.length > VALUE_MAX || id.search(CONTROL_OR_SEPARATOR) !== -1 || seen.indexOf(id) !== -1) continue;
        var label = labelOf(entry).replace(CONTROL_OR_SEPARATOR, " ").trim().slice(0, LABEL_MAX).trim();
        seen.push(id);
        out.push({ label: label !== "" ? label : id.slice(0, LABEL_MAX), value: id });
    }
    return out;
}

// Whether the menu leaves out the row at `index` of a level, `depth` 0 for
// the root: at the root, a first entry that opens a submenu named as the
// item itself, which some apps wrap their whole menu in, and a separator in
// the first two rows, which would open the menu with a line.
function rowHidden(depth, index, row, title) {
    if (depth !== 0) return false;
    if (index === 0 && row.hasChildren && String(row.text || "").toLowerCase() === String(title || "").toLowerCase()) return true;
    return row.isSeparator === true && index <= 1;
}
