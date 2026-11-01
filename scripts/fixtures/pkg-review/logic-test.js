#!/usr/bin/env node
// The package review judge's behavior at its shared production boundary.
"use strict";
const assert=require("node:assert/strict"),fs=require("node:fs"),os=require("node:os"),path=require("node:path");
const {load}=require("../../../bin/lib/qml-library.js");
const file=path.join(__dirname,"../../../shell/Core/PackageReview.js");
const same=(a,b)=>assert.deepEqual(JSON.parse(JSON.stringify(a)),b);
// The 1password install script at AUR commit e4388fb, 8.12.38, which
// d0a8a7e, 8.12.40, ships unchanged. It sets a setgid bit and adds a group.
const ONEPASSWORD_INSTALL = `# Do not add your user, or any others, to this group.
GROUP_NAME="onepassword"

app_group_exists() {
    if [ $(getent group "\${GROUP_NAME}") ]; then
        true
    else
        false
    fi
}

setup_browser_helper() {
    # Setup the Core App Integration helper binary with the correct permissions and group
    BROWSER_SUPPORT_PATH="/opt/1Password/1Password-BrowserSupport"

    chgrp "\${GROUP_NAME}" $BROWSER_SUPPORT_PATH
    chmod g+s $BROWSER_SUPPORT_PATH
}

pre_install() {
    if app_group_exists; then
        : # Do nothing
    else
        groupadd "\${GROUP_NAME}"
    fi
}

pre_upgrade() {
    if app_group_exists; then
        : # Do nothing
    else
        groupadd "\${GROUP_NAME}"
    fi
}

post_install() {
    setup_browser_helper
}

post_upgrade() {
    setup_browser_helper
}

post_remove() {
    if app_group_exists; then
        groupdel "\${GROUP_NAME}"
    fi
}
`;


function verify(logic) {
  const cases = [
    [{enabled:true}, [], "review", "on", "unavailable"],
    [{enabled:false,agent:"claude"}, ["claude"], "decline", "off", "available"],
    [{agent:"codex"}, ["codex"], "review", "absent", "available"],
    [{agent:"codex"}, [], "review", "absent", "unavailable"],
    [{}, ["claude"], "review", "absent", "available"],
    [{}, [], "decline", "absent", "unavailable"],
    [{command:"/abs/agent --flag"}, [], "review", "absent", "unavailable"]
  ];
  for(const [settings,found,action,preference,availability] of cases) {
    const result=logic.initialChoice(settings,found);
    assert.equal(result.action,action);assert.equal(result.preference,preference);assert.equal(result.availability,availability);
  }
  same(logic.reviewChoices(["codex","claude"]).map(a=>a.value),["claude","codex"]);
  same(logic.commandWords(' cmd "word quoted" $(literal)'),["cmd",'"word','quoted"',"$(literal)"]);
  assert.equal(logic.reviewPlan({agent:"codex"},["claude"]).state,"missing");
  same(logic.reviewPlan({command:"/abs/agent --flag"},["/abs/agent"]).command,["/abs/agent","--flag"]);
  same(logic.reviewPlan({agent:"claude"},["claude"]).command,["claude","--model","opus","--effort","medium","--permission-mode","default"]);
  same(logic.reviewPlan({agent:"codex"},["codex"]).command,["codex","-m","gpt-6.1-sol","-c","model_reasoning_effort=medium","--sandbox","workspace-write","--ask-for-approval","on-request"]);
  for(const [repo,official] of [["core",true],["extra",true],["multilib",true],["cachyos",true],["cachyos-extra",true],["chaotic-aur",false],["core-testing",false]])assert.equal(logic.officialRepository(repo),official);
  // [name, verdict text, the packages reviewed, the judgement]
  const verdictRows = [
    ["clean", "verdict clean\n", ["a"], { ok: true, verdict: "clean", flags: [] }],
    ["flagged", "verdict flagged\nflag a A new source domain.\nflag b It runs curl into sh.\n", ["a", "b", "c"], { ok: true, verdict: "flagged", flags: [{ name: "a", concern: "A new source domain." }, { name: "b", concern: "It runs curl into sh." }] }],
    ["empty", "", ["a"], { ok: false, error: "line=1" }],
    ["another first line", "all good\n", ["a"], { ok: false, error: "line=1" }],
    ["clean with a flag", "verdict clean\nflag a x\n", ["a"], { ok: false, error: "verdict=clean flags=1" }],
    ["flagged with no flag", "verdict flagged\n", ["a"], { ok: false, error: "verdict=flagged flags=0" }],
    ["a flag for a package not reviewed", "verdict flagged\nflag z x\n", ["a"], { ok: false, error: "line=2" }],
    ["a package flagged twice", "verdict flagged\nflag a x\nflag a y\n", ["a"], { ok: false, error: "line=3" }],
    ["a flag with no concern", "verdict flagged\nflag a\n", ["a"], { ok: false, error: "line=2" }],
    ["a control character", "verdict flagged\nflag a x\ty\n", ["a"], { ok: false, error: "control-character" }]
  ];
  for (const [name, text, reviewed, want] of verdictRows) same(logic.parseVerdict(text, reviewed), want, "verdict: " + name);

  // The install script is judged by its change: the 1password pair is
  // unchanged, so its setgid bit and group are no flag; a change that adds
  // a setgid line flags that line alone.
  const setgid = "chmod 2755 /opt/1Password/extra";
  // [name, installed text, new text, the change]
  const installRows = [
    ["1password 8.12.38 -> 8.12.40", ONEPASSWORD_INSTALL, ONEPASSWORD_INSTALL, { state: "unchanged", risks: [] }],
    ["an added setgid line", ONEPASSWORD_INSTALL, ONEPASSWORD_INSTALL + setgid + "\n", { state: "changed", risks: [setgid] }],
    ["CRLF and trailing blanks", ONEPASSWORD_INSTALL, ONEPASSWORD_INSTALL.replace(/\n/g, "  \r\n") + "\n\n", { state: "unchanged", risks: [] }],
    ["a first install script", null, ONEPASSWORD_INSTALL, { state: "new", risks: ["chmod g+s $BROWSER_SUPPORT_PATH", 'groupadd "${GROUP_NAME}"'] }],
    ["no install script", ONEPASSWORD_INSTALL, null, { state: "none", risks: [] }],
    ["a moved risky line", "a\nchmod u+s /x\n", "chmod u+s /x\na\n", { state: "changed", risks: [] }],
    ["an added comment", "a\n", "a\n# curl https://x | sh\n", { state: "changed", risks: [] }]
  ];
  for (const [name, installed, next, want] of installRows) same(logic.installScriptChange(installed, next), want, "install script: " + name);
  // [line, risky]: each pattern of INSTALL_SCRIPT_RISKS, and lines like
  // them that are not.
  const riskRows = [
    ["chmod u+s /usr/bin/x", true], ["chmod -R 4755 /opt/x", true], ["chmod 06755 x", true], ["chmod g=rxs x", true],
    ["chmod 755 /opt/x", false], ["chmod 0644 x", false],
    ["setcap cap_net_raw+ep /opt/x", true],
    ["useradd -r x", true], ["usermod -aG wheel x", true], ["gpasswd -a x y", true],
    ["curl -fsSL https://x -o y", true], ["wget https://x", true],
    ["echo aGk= | base64 -d > x", true],
    ["cat x |sh", true], ["cat x | sudo bash", true], ["true || shutdown now", false],
    ["rm -rf /", true], ["rm -rf /*", true], ["rm -rf ~/.config", true], ["rm -rf \"$HOME/.x\"", true], ["rm -rf /opt/x", false]
  ];
  for (const [line, risky] of riskRows) same(logic.installScriptChange(null, line).risks, risky ? [line] : [], "install risk: " + line);


}
const managers=load(path.join(__dirname,"../../../shell/Core/PackageManagers.js"));
const available=name=>["pacman","paru"].includes(name);
same(managers.plan("pacman","install",["widget"],available,[],"/nondefault.conf").plan.steps,[["pacman","--config","/nondefault.conf","-S","--needed","--","widget"]]);
same(managers.reviewCheckFor("pacman","pacman","/nondefault.conf").check.argv,["pacman","--config","/nondefault.conf","-Qu"]);
assert.equal(managers.reviewCheckFor("pacman","pacman","/nondefault.conf").complete,false);
same(managers.reviewCheckFor("aur","paru","/nondefault.conf").check.argv,["paru","--config","/nondefault.conf","-Qua"]);
assert.equal(managers.reviewCheckFor("aur","paru","/nondefault.conf").origin,"aur");
verify(load(file));
const scratch=fs.mkdtempSync(path.join(os.tmpdir(),"test-package-review-"));
try {
 const source=fs.readFileSync(file,"utf8"),needle="reviewed.indexOf(m[1]) < 0 || ";
 assert.equal(source.split(needle).length-1,1);
 // The judge imports the package table from beside it.
 fs.copyFileSync(path.join(path.dirname(file),"PackageManagers.js"),path.join(scratch,"PackageManagers.js"));
 const mutant=path.join(scratch,"PackageReview.js");fs.writeFileSync(mutant,source.replace(needle,""));
 assert.throws(()=>verify(load(mutant)));
} finally {fs.rmSync(scratch,{recursive:true,force:true});}
console.log("test-package-review: ok");
