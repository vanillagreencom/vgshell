.pragma library

// The one reader of a reference in text a user reads: a page reference,
// `[words](page:<plugin id>)`, `[words](page:<plugin id>/<tab>)` or
// `[words](page:<plugin id>/<tab>/<key>)`, TAB one of Settings, Setup and
// Details and KEY a Settings field key or the key of a status row Setup or
// Details draws, or a file reference, `[words](file:<encoded path>)`.
// LinkText draws the words as a link that opens the page or the file, and a
// surface that cannot draw a link, such as a notice another server shows,
// gives the words alone. The third page form opens the tab at that row,
// scrolled into view: its tab, `<tab>/<key>`, travels as one tab, which
// place reads. A file reference percent-encodes its path,
// including parentheses. The decoded path is absolute, starts with `~/`, or
// is relative to the configuration directory, and a path that ends in `/`
// names a folder (PluginLogic.editRoute).
//
// A file reference travels as the page `file:<path>` with no tab, so
// every owner that hands a page reference on hands a file reference on
// unchanged, and the one that opens it reads the path back (file). No
// plugin id holds a colon (PluginLogic.ID_PATTERN).

var REFERENCE = /\[([^\[\]]+)\]\((?:page:([^\s()\/]*)(?:\/((?:Settings|Setup|Details)\/[^\s()\/]+|[^\s()\/]+))?|file:((?:[A-Za-z0-9_.!~*'\-]|%[0-9A-Fa-f]{2})+))\)/;
var FILE_SCHEME = "file:";

// TEXT's first reference: `text`, TEXT with the reference's words in its
// place, `words`, `page` and `tab`, "" for no tab, and `reference`, the
// reference as written. A file reference's page is `file:<path>` and its
// tab "". With no reference, `text` is TEXT and the rest "". A reference
// to no page, as `[words](page:)`, answers page "".
function parse(text) {
    var found = REFERENCE.exec(text);
    if (found === null) return { text: text, words: "", page: "", tab: "", reference: "" };
    var file = found[4] !== undefined;
    return { text: text.slice(0, found.index) + found[1] + text.slice(found.index + found[0].length),
        words: found[1], page: file ? FILE_SCHEME + found[4] : found[2], tab: file || found[3] === undefined ? "" : found[3], reference: found[0] };
}

// All references, with their [start, end) positions in the plain text.
function references(text) {
    var rest = text;
    var out = "";
    var links = [];
    var found;
    while ((found = REFERENCE.exec(rest)) !== null) {
        var first = parse(rest);
        out += rest.slice(0, found.index);
        links.push({ start: out.length, end: out.length + first.words.length,
            words: first.words, page: first.page, tab: first.tab, reference: first.reference });
        out += first.words;
        rest = rest.slice(found.index + found[0].length);
    }
    return { text: out + rest, links: links };
}

// One written file form. encodeURIComponent leaves parentheses literal.
function fileReference(words, path) {
    return "[" + words + "](file:" + encodeURIComponent(path).replace(/\(/g, "%28").replace(/\)/g, "%29") + ")";
}

// TEXT with every reference replaced by its words.
function plain(text) {
    return references(text).text;
}

// The path PAGE, a reference's page, names when it is a file reference,
// "" for a plugin page.
function file(page) {
    return page.indexOf(FILE_SCHEME) === 0 ? decodeURIComponent(page.slice(FILE_SCHEME.length)) : "";
}

// Where TAB, a reference's tab, opens a page: { tab, key }, `key` the key
// of the row a `<tab>/<key>` tab shows, a Settings field's or a Setup or
// Details status row's, "" for a tab alone.
function place(tab) {
    var at = tab.indexOf("/");
    return at === -1 ? { tab: tab, key: "" } : { tab: tab.slice(0, at), key: tab.slice(at + 1) };
}
