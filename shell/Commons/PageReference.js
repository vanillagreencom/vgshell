.pragma library

// The one reader of a reference in text a user reads: a page reference,
// `[words](page:<plugin id>)`, `[words](page:<plugin id>/<tab>)` or
// `[words](page:<plugin id>/Settings/<field key>)`, or a file reference,
// `[words](file:<path>)`. LinkText draws the words as a link that opens
// the page or the file, and a surface that cannot draw a link, such as a
// notice another server shows, gives the words alone. The third page form
// opens Settings at the field: its tab, `Settings/<field key>`, travels as
// one tab, which place reads. A file reference's path holds no space and
// no parenthesis: it is absolute, starts with `~/` for the home folder, or
// is relative to the configuration directory, and a path that ends in `/`
// names a folder (PluginLogic.editRoute).
//
// A file reference travels as the page `file:<path>` with no tab, so
// every owner that hands a page reference on hands a file reference on
// unchanged, and the one that opens it reads the path back (file). No
// plugin id holds a colon (PluginLogic.ID_PATTERN).

var REFERENCE = /\[([^\[\]]+)\]\((?:page:([^\s()\/]*)(?:\/(Settings\/[^\s()\/]+|[^\s()\/]+))?|file:([^\s()]+))\)/;
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

// TEXT with its first reference's words in the reference's place.
function plain(text) {
    return parse(text).text;
}

// The path PAGE, a reference's page, names when it is a file reference,
// "" for a plugin page.
function file(page) {
    return page.indexOf(FILE_SCHEME) === 0 ? page.slice(FILE_SCHEME.length) : "";
}

// Where TAB, a reference's tab, opens a page: { tab, field }, `field` the
// key of the Settings field a `Settings/<field key>` tab shows, "" for a
// tab alone.
function place(tab) {
    var at = tab.indexOf("/");
    return at === -1 ? { tab: tab, field: "" } : { tab: tab.slice(0, at), field: tab.slice(at + 1) };
}
