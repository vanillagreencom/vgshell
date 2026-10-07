// accounts.js --tree ABSOLUTE_VGS_TREE VERB [ARGS...]
// Public verbs expose metadata only. Explicit Verify uses the outbound door.
// table, accounts, providers and items print the setup terminal's rows for
// a terminal WIDTH columns wide: table the CSV `gum table --print` draws,
// the others AccountProviders.choiceLine lines.
"use strict";
const path = require("node:path");
const { parseWidth, fitText, choiceLine, providerChoices, helperFailure } = require("../AccountProviders.js");
const { stateLabel } = require("../AccountStatus.js");

// gum 2.0.2 `table --print`, rounded border, draws one space on each side
// of every cell and a rule before, between and after the cells: a row is
// its cell widths plus 3 per column plus 1 (a run of gum 2.0.2 on
// 2026-10-06).
const TABLE_COLUMNS = ["AI provider", "Account", "Status", "Plan"];
const TABLE_FRAME = 3 * TABLE_COLUMNS.length + 1;

function fail(reason) { throw new Error("jarvis-accounts: " + reason); }

function width(text) {
    const value = parseWidth(text);
    if (value === null) fail("arguments=width");
    return value;
}

// An account by its sign-in email where the program reports one.
function accountName(account) {
    if (account.email) return account.email;
    if (account.source.kind === "local") return "This computer";
    if (account.source.kind === "variable") return "Environment variable";
    return account.label;
}

function status(account) {
    return stateLabel(account.state.kind, account.source.kind);
}

function csv(cells) {
    return cells.map(cell => "\"" + cell.replace(/"/g, "\"\"") + "\"").join(",");
}

// The header first, then one row per account, no line for no account; label
// is the account judge's provider label. The widest column gives up one
// character at a time until a row fits.
function accountTable(accounts, columns, label) {
    if (accounts.length === 0) return [];
    const rows = [TABLE_COLUMNS, ...accounts.map(account => [label(account.provider), accountName(account),
        status(account), account.plan || ""])];
    const widths = TABLE_COLUMNS.map((_, column) => Math.max(...rows.map(row => Array.from(row[column]).length)));
    while (widths.reduce((sum, value) => sum + value, 0) > columns - TABLE_FRAME) widths[widths.indexOf(Math.max(...widths))]--;
    return rows.map(row => csv(row.map((cell, column) => fitText(cell, widths[column]))));
}

async function main() {
    if (process.argv[2] !== "--tree" || !path.isAbsolute(process.argv[3] || "")) throw new Error("jarvis-accounts: arguments=tree");
    require("./Core.js").use(process.argv[3]);
    const { Accounts, provider } = require("./Accounts.js");
    const label = id => provider(id).label;
    const args = process.argv.slice(4);
    const state = path.join(process.env.XDG_STATE_HOME || path.join(process.env.HOME, ".local/state"), "vgshell/jarvis");
    const snapshot = args[0] === "presence" && args.length === 2 ? JSON.parse(args[1]) : undefined;
    const judge = new Accounts(state, process.env, snapshot);
    let value, lines;
    switch (args[0]) {
    case "presence":
        if (args.length !== 2) throw new Error("jarvis-accounts: arguments=presence");
        judge.discover();
        await judge.readEmails();
        value = judge.status();
        break;
    case "list":
        if (args.length !== 1) throw new Error("jarvis-accounts: arguments=list");
        value = judge.discover();
        break;
    case "table":
        if (args.length !== 2) throw new Error("jarvis-accounts: arguments=table");
        judge.discover();
        await judge.readEmails();
        lines = accountTable(judge.accounts, width(args[1]), label);
        break;
    case "accounts": {
        if (args.length !== 2) throw new Error("jarvis-accounts: arguments=accounts");
        const columns = width(args[1]);
        judge.discover();
        await judge.readEmails();
        lines = judge.accounts.map(account => choiceLine(label(account.provider) + ": " + accountName(account)
            + " (" + status(account) + ")", account.id, columns));
        break;
    }
    case "providers":
        if (args.length !== 3 || !["cli", "key"].includes(args[1])) throw new Error("jarvis-accounts: arguments=providers");
        lines = providerChoices(args[1], width(args[2]), false);
        break;
    case "items": {
        if (args.length !== 2) throw new Error("jarvis-accounts: arguments=items");
        const columns = width(args[1]);
        lines = judge.keyItems().map(item => choiceLine(item.label + (item.presence === "locked" ? " (keyring locked)" : ""),
            item.path, columns));
        break;
    }
    case "add":
        if (args.length !== 4) throw new Error("jarvis-accounts: arguments=add");
        judge.add({ provider: args[1], directory: args[2], label: args[3] });
        value = { kind: "stored" };
        break;
    case "remember":
        if (args.length !== 4) throw new Error("jarvis-accounts: arguments=remember");
        judge.remember(args[1], args[2], args[3]);
        value = { kind: "stored" };
        break;
    case "verify":
        if (![3, 4].includes(args.length) || args[2] !== "user") throw new Error("jarvis-accounts: verify=explicit-user-required");
        judge.discover();
        value = await judge.verify(args[1], "user", undefined, args[3] || "");
        if (value.kind !== "verified") process.exitCode = 69;
        break;
    default: throw new Error("jarvis-accounts: arguments=verb");
    }
    if (lines === undefined) process.stdout.write(JSON.stringify(value) + "\n");
    else if (lines.length > 0) process.stdout.write(lines.join("\n") + "\n");
}

main().catch(error => {
    const reason = helperFailure(error.message) || "jarvis-accounts: operation=failed";
    process.stderr.write(reason + "\n");
    process.exitCode = 1;
});
