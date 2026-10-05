.pragma library

// The web apps' pure rules: which list items are apps, the window class a
// Chromium-family browser gives a site's app window, which browser opens
// one, which icons a page offers, and the desktop entry that lists an app
// in the launcher. The service runs them.

// Each entry's file is vgs-webapp-<name>.desktop, and the service removes
// every such file the list no longer holds.
var ENTRY_PREFIX = "vgs-webapp-";
var NAME_MAX = 80;
// Chromium-family browsers, read as one word of a desktop id or of a
// program's file name: these take `--app=<url>` and map the site in its
// own window.
var CHROMIUM_WORDS = ["chromium", "chrome", "brave", "vivaldi", "edge", "msedge", "thorium", "helium", "opera"];

// parseUrl(TEXT): { ok: true, href, host, path } for an http or https
// address with a host and no user part, else { ok: false }. The scheme
// and host are lower case, the path "/" when the address has none.
function parseUrl(text) {
    var match = /^(https?):\/\/([A-Za-z0-9.-]+|\[[0-9A-Fa-f:.]+\])(:[0-9]{1,5})?(\/[^\s?#]*)?(\?[^\s#]*)?(#\S*)?$/i.exec(String(text === undefined || text === null ? "" : text).trim());
    if (match === null)
        return { ok: false };
    var host = match[2].toLowerCase();
    var path = match[4] || "/";
    return { ok: true, href: match[1].toLowerCase() + "://" + host + (match[3] || "") + path + (match[5] || "") + (match[6] || ""), host: host, path: path };
}

// The part of an app window's class a Chromium-family browser derives from
// URL: the host, "_" and the path with every "/" as "_". The browser puts
// its own word before it and the profile after it, each joined by "-", as
// in chrome-web.whatsapp.com__-Default, so such a class holds `-<key>-`.
function classKey(url) {
    return url.host + "_" + url.path.replace(/\//g, "_");
}

function classMatches(windowClass, url) {
    return String(windowClass || "").indexOf("-" + classKey(url) + "-") !== -1;
}

function words(text) {
    return String(text || "").toLowerCase().split(/[^a-z0-9]+/).filter(function (word) { return word !== ""; });
}

function baseName(path) {
    var text = String(path || "");
    return text.slice(text.lastIndexOf("/") + 1);
}

// isChromium(ID, COMMAND): whether a desktop entry, by its ID without
// .desktop or the file name of its COMMAND's program, names a
// Chromium-family browser, and its COMMAND starts that browser rather than
// one site: the shortcuts a browser makes for a site carry --app or
// --app-id, and running one with --app=<url> opens that shortcut's app.
function isChromium(id, command) {
    var argv = Array.from(command);
    if (argv.length === 0 || argv.some(function (word) { return /^--app(-id)?(=|$)/.test(word); }))
        return false;
    return words(id).concat(words(baseName(argv[0]))).some(function (word) { return CHROMIUM_WORDS.indexOf(word) !== -1; });
}

// The desktop entry id in xdg-mime's answer, a file name such as
// chromium.desktop, or "" for an empty answer.
function entryId(answer) {
    return String(answer || "").trim().replace(/\.desktop$/, "");
}

// browserArgv(COMMAND, HREF): a browser entry's parsed Exec with any field
// code left out and the app flag added.
function browserArgv(command, href) {
    return Array.from(command).filter(function (word) { return !/^%[A-Za-z]$/.test(word); }).concat(["--app=" + href]);
}

// apps(ITEMS): the `apps` setting's items split into `good`, each
// { name, url, title, icon } with `url` a parseUrl answer, and `bad`, each
// { name, reason } with reason `address` for an item no address opens.
function apps(items) {
    var good = [];
    var bad = [];
    (Array.isArray(items) ? items : []).forEach(function (item) {
        if (item === null || typeof item !== "object" || !/^[a-z0-9-]+$/.test(String(item.name)))
            return;
        var url = parseUrl(item.url);
        if (!url.ok) {
            bad.push({ name: item.name, reason: "address" });
            return;
        }
        good.push({ name: item.name, url: url, title: plainText(item.title), icon: String(item.icon === undefined || item.icon === null ? "" : item.icon).trim() });
    });
    return { good: good, bad: bad };
}

// One printable line of at most NAME_MAX characters: control characters
// become spaces and runs of white space close up.
function plainText(text) {
    return String(text === undefined || text === null ? "" : text).replace(/[\u0000-\u001f\u007f]/g, " ").replace(/\s+/g, " ").trim().slice(0, NAME_MAX).trim();
}

var ENTITIES = { amp: "&", lt: "<", gt: ">", quot: "\"", apos: "'", nbsp: " " };

function decodeEntities(text) {
    return text.replace(/&(#[xX][0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);/g, function (whole, code) {
        if (code[0] === "#") {
            var point = code[1] === "x" || code[1] === "X" ? parseInt(code.slice(2), 16) : parseInt(code.slice(1), 10);
            return point > 0 && point < 0x110000 ? String.fromCodePoint(point) : " ";
        }
        var named = ENTITIES[code.toLowerCase()];
        return named === undefined ? whole : named;
    });
}

function attribute(tag, name) {
    var match = new RegExp("\\s" + name + "\\s*=\\s*(\"([^\"]*)\"|'([^']*)'|([^\\s\"'>]+))", "i").exec(tag);
    if (match === null)
        return null;
    return decodeEntities(match[2] !== undefined ? match[2] : match[3] !== undefined ? match[3] : match[4]);
}

// resolve(BASE, HREF): HREF read against BASE, a parseUrl answer, as an
// absolute http or https address, or "" for an empty HREF or another
// scheme.
function resolve(base, href) {
    var text = String(href === undefined || href === null ? "" : href).trim();
    if (text === "")
        return "";
    var origin = base.href.slice(0, base.href.indexOf("/", base.href.indexOf("//") + 2));
    if (text.slice(0, 2) === "//")
        text = origin.slice(0, origin.indexOf(":")) + ":" + text;
    if (/^[a-z][a-z0-9+.-]*:/i.test(text)) {
        var absolute = parseUrl(text);
        return absolute.ok ? absolute.href : "";
    }
    var tail = /[?#].*$/.exec(text);
    var path = text.replace(/[?#].*$/, "");
    if (path[0] !== "/")
        path = base.path.slice(0, base.path.lastIndexOf("/") + 1) + path;
    var segments = [];
    path.split("/").forEach(function (part, index, parts) {
        if (part === "..") {
            if (segments.length > 1) segments.pop();
        } else if (part !== "." || index === parts.length - 1) {
            segments.push(part === "." ? "" : part);
        }
    });
    return origin + ("/" + segments.join("/")).replace(/^\/+/, "/") + (tail === null ? "" : tail[0]);
}

function largestSide(sizes) {
    if (sizes === null)
        return 0;
    if (/any/i.test(sizes))
        return 100000;
    return String(sizes).split(/\s+/).reduce(function (best, size) {
        var match = /^(\d+)x(\d+)$/i.exec(size);
        return match === null ? best : Math.max(best, parseInt(match[1], 10));
    }, 0);
}

// The rel tokens that name an icon a launcher can draw; a mask-icon is a
// one-colour shape with no fill of its own.
var ICON_RELS = ["icon", "apple-touch-icon", "apple-touch-icon-precomposed"];

// page(HTML, URL): what a site's page offers, `title`, a plain line or "",
// and `icons`, its icon addresses best first: each apple-touch-icon, then
// each `icon` link by its largest declared size, then /favicon.ico. URL is
// the address the page came from, after any redirect.
function page(html, url) {
    var text = String(html || "");
    var titleMatch = /<title[^>]*>([\s\S]*?)<\/title>/i.exec(text);
    var found = [];
    (text.match(/<link\b[^>]*>/gi) || []).forEach(function (tag, order) {
        var rel = String(attribute(tag, "rel") || "").toLowerCase().split(/\s+/).filter(function (token) { return ICON_RELS.indexOf(token) !== -1; });
        var href = resolve(url, attribute(tag, "href"));
        if (href === "" || rel.length === 0)
            return;
        var touch = rel.some(function (token) { return token !== "icon"; });
        found.push({ href: href, rank: touch ? 1 : 0, side: largestSide(attribute(tag, "sizes")), order: order });
    });
    found.sort(function (a, b) { return b.rank - a.rank || b.side - a.side || a.order - b.order; });
    var icons = [];
    found.concat([{ href: resolve(url, "/favicon.ico") }]).forEach(function (icon) {
        if (icons.indexOf(icon.href) === -1) icons.push(icon.href);
    });
    return { title: titleMatch === null ? "" : plainText(decodeEntities(titleMatch[1])), icons: icons };
}

// iconSources(ICON, HOME): the source a custom Icon value names, as a
// list: an http or https address, an absolute path, or a path under ~/
// read against HOME; [] for anything else.
function iconSources(icon, home) {
    var text = String(icon || "").trim();
    if (/^https?:\/\//i.test(text)) {
        var url = parseUrl(text);
        return url.ok ? [url.href] : [];
    }
    if (text.slice(0, 2) === "~/")
        text = home + text.slice(1);
    return text[0] === "/" ? [text] : [];
}

// A desktop entry string value, escaped as the Desktop Entry
// Specification's string type sets out.
function desktopString(text) {
    return String(text).replace(/\\/g, "\\\\").replace(/[\r\n\t]/g, " ");
}

// One Exec argument: `%` doubled, and quoted when it holds a reserved
// character, with `"`, `` ` ``, `$` and `\` escaped inside the quotes.
function execArg(word) {
    var text = String(word).replace(/%/g, "%%");
    if (text !== "" && !/[\s"'\\><~|&;$*?#()`=]/.test(text))
        return text;
    return "\"" + text.replace(/(["`$\\])/g, "\\$1") + "\"";
}

function entryFile(name) {
    return ENTRY_PREFIX + name + ".desktop";
}

// desktopEntry(APP, TITLE, ICON, VGSHELL): the launcher's entry for APP,
// named TITLE, or the host when TITLE is empty, drawn with the image file
// ICON, which runs VGSHELL, the shell's own vgshell, to open the app or
// focus its window.
function desktopEntry(app, title, icon, vgshell) {
    var exec = [vgshell, "ipc", "call", "vgs.webapps", "invoke", "open", app.name].map(execArg).join(" ");
    return [
        "[Desktop Entry]",
        "Type=Application",
        "Name=" + desktopString(plainText(title) || app.url.host),
        "Comment=" + desktopString(app.url.href),
        "Exec=" + desktopString(exec),
        "Icon=" + desktopString(icon),
        "Categories=Network;",
        ""
    ].join("\n");
}
