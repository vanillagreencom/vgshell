// Audit arguments contain field names, never caller-supplied contents.
// Pattern matching cannot recognize an arbitrary password or private text.
"use strict";
const Tools = require("./Tools.js");

/**
 * Describe an argument envelope without copying its values or unknown keys.
 * The action table supplies field names. Release metadata uses the audit
 * contract's fixed envelope. No text, numeric credential, binary payload,
 * nested value or caller-controlled property name enters the result.
 */
function argumentsFor(kind, tool, args) {
    const fields = kind === "release" ? ["labels", "recipients"]
        : Object.hasOwn(Tools.TABLE, tool) ? Object.keys(Tools.TABLE[tool].schema.properties) : [];
    const result = {};
    if (args === null || typeof args !== "object" || Array.isArray(args)) return "[redacted]";
    for (const field of fields)
        if (Object.hasOwn(args, field)) result[field] = "[redacted]";
    return result;
}

function secret(text) {
    if (typeof text !== "string") return false;
    return [
        /\bsk-(?:ant-)?[A-Za-z0-9_-]{16,}\b/,
        /\bgithub_pat_[A-Za-z0-9_]{20,}\b/,
        /\bgh[pousr]_[A-Za-z0-9_]{20,}\b/,
        /\bxox[baprs]-[A-Za-z0-9-]{10,}\b/,
        /\bAKIA[0-9A-Z]{16}\b/,
        /\bAIza[0-9A-Za-z_-]{20,}\b/,
        /-----BEGIN [A-Z ]*PRIVATE KEY-----/,
        /\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b/,
        /[a-z][a-z0-9+.-]*:\/\/[^\/\s:@]+:[^\/\s:@]+@/i
    ].some(pattern => pattern.test(text));
}

module.exports = { argumentsFor, secret };
