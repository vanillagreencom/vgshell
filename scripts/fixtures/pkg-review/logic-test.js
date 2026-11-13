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
  const recipe=fs.readFileSync(path.join(__dirname,"../pkg/aur-x86.SRCINFO"),"utf8");
  for(const [label,text,name,base,want] of [
    ["base architecture",recipe,"need-two","need-two-base",["x86_64"]],
    ["CRLF recipe",recipe.replace(/\n/g,"\r\n"),"need-two","need-two-base",["x86_64"]],
    ["split override",recipe+"\tarch = aarch64\npkgname = sibling\n\tarch = any\n","need-two","need-two-base",["aarch64"]],
    ["split sibling",recipe+"pkgname = sibling\n\tarch = any\n","need-two","need-two-base",["x86_64"]],
    ["architecture independent",recipe.replace("x86_64","any"),"need-two","need-two-base",["any"]],
    ["wrong package",recipe,"other","need-two-base",null],
    ["wrong base",recipe,"need-two","other-base",null],
    ["missing architecture",recipe.replace("\tarch = x86_64\n",""),"need-two","need-two-base",null],
    ["malformed architecture",recipe.replace("x86_64","'x86_64'"),"need-two","need-two-base",null]
  ]) assert.deepEqual(JSON.parse(JSON.stringify(logic.srcinfoArchitectures(text,name,base))),want,"recipe architecture: "+label);
  // [settings, agents found, initial row, preference, availability, asks]:
  // only a saved Install without review asks nothing.
  const cases = [
    [{enabled:true}, [], "review", "on", "unavailable", true],
    [{enabled:false,agent:"claude"}, ["claude"], "decline", "off", "available", false],
    [{enabled:false}, [], "decline", "off", "unavailable", false],
    [{agent:"codex"}, ["codex"], "review", "absent", "available", true],
    [{agent:"codex"}, [], "review", "absent", "unavailable", true],
    [{}, ["claude"], "review", "absent", "available", true],
    [{}, [], "decline", "absent", "unavailable", true],
    [{command:"/abs/agent --flag"}, [], "review", "absent", "unavailable", true]
  ];
  for(const [settings,found,action,preference,availability,ask] of cases) {
    const result=logic.initialChoice(settings,found),row=JSON.stringify(settings);
    assert.equal(result.action,action,row);assert.equal(result.preference,preference,row);assert.equal(result.availability,availability,row);assert.equal(result.ask,ask,row);
  }
  // [name, resolved through the AUR helper, the recipes or null, publisher]:
  // VGS publishes through the AUR alone, so a name from any pacman
  // repository, one named aur included, is third-party, and unread recipes
  // never exempt a package.
  const published=["vgshell","vgshell-git","vgshell-quickshell"];
  for(const [name,viaAur,recipes,want] of [
    ["vgshell-git",true,published,"vgs"],
    ["vgshell-quickshell",true,published,"vgs"],
    ["cpptrace",true,published,"third-party"],
    ["vgshell-git",false,published,"third-party"],
    ["vgshell-git",true,null,"unread"],
    ["widget",true,null,"unread"],
    ["vgshell-git",false,null,"third-party"]
  ])assert.equal(logic.publisher(name,viaAur,recipes),want,"publisher: "+name+(viaAur?" through the AUR":" from a repository"));
  // A split recipe's .SRCINFO, as makepkg --printsrcinfo writes it.
  same(logic.srcinfoFields("pkgbase = vgshell\n\tpkgver = 1.0\n\n# a comment\npkgname = vgshell\npkgname = vgshell-extra\n\tinstall = vgshell.install\n"),
    [{key:"pkgbase",value:"vgshell"},{key:"pkgver",value:"1.0"},{key:"pkgname",value:"vgshell"},{key:"pkgname",value:"vgshell-extra"},{key:"install",value:"vgshell.install"}]);
  same(logic.reviewChoices(["codex","claude"]).map(a=>a.value),["claude","codex"]);
  same(logic.commandWords(' cmd "word quoted" $(literal)'),["cmd",'"word','quoted"',"$(literal)"]);
  assert.equal(logic.reviewPlan({agent:"codex"},["claude"]).state,"missing");
  same(logic.reviewPlan({command:"/abs/agent --flag"},["/abs/agent"]).command,["/abs/agent","--flag"]);
  const claudeWords=["claude","--model","opus","--effort","medium","--tools","Read,Glob,Grep,Write","--strict-mcp-config","--permission-mode","dontAsk","--no-chrome"];
  same(logic.reviewPlan({agent:"claude"},["claude"]).command,claudeWords);
  const codexWords=["codex","-m","gpt-6.1-sol","-c","model_reasoning_effort=medium","-c","default_permissions=:workspace","--ask-for-approval","never"];
  same(logic.reviewPlan({agent:"codex"},["codex"]).command,codexWords);
  // [settings, found, the launch of the review whose evidence folder is
  // /run/work/review-a/evidence beside the agent home /run/work/agent]:
  // Claude adds that folder and the one rule naming its verdict in the
  // absolute //path form, and starts in the home; Codex starts in that
  // evidence folder. A saved command runs as written, in the home when its
  // first word is claude and in the evidence folder for any other agent.
  const review={home:"/run/work/agent",evidence:"/run/work/review-a/evidence"};
  for(const [settings,found,want] of [
    [{agent:"claude"},["claude"],{argv:claudeWords.concat(["--add-dir=/run/work/review-a/evidence","--allowedTools=Edit(//run/work/review-a/evidence/verdict)"]),cwd:"/run/work/agent"}],
    [{agent:"codex"},["codex"],{argv:codexWords,cwd:"/run/work/review-a/evidence"}],
    [{command:"codex --sandbox workspace-write"},["codex"],{argv:["codex","--sandbox","workspace-write"],cwd:"/run/work/review-a/evidence"}],
    [{command:"claude --model opus"},["claude"],{argv:["claude","--model","opus"],cwd:"/run/work/agent"}],
    [{command:"opencode run"},["opencode"],{argv:["opencode","run"],cwd:"/run/work/review-a/evidence"}]
  ])same(logic.reviewCommand(logic.reviewPlan(settings,found),review),want);
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
const managersAt=process.argv.indexOf("--managers");
const managers=load(managersAt<0?path.join(__dirname,"../../../shell/Core/PackageManagers.js"):process.argv[managersAt+1]);
const available=name=>["pacman","paru"].includes(name);
same(managers.plan("pacman","install",["widget"],available,[],"/nondefault.conf").plan.steps,[["pacman","--config","/nondefault.conf","-S","--needed","--","widget"]]);
for(const [label,effective,complete] of [
 ["generated-hook-wrapper",{repositories:["core","extra"],dbPath:"/var/lib/pacman/"},true],
 ["other-repositories",{repositories:["core","custom"],dbPath:"/var/lib/pacman/"},false],
 ["other-dbpath",{repositories:["core","extra"],dbPath:"/other/db/"},false]
]){
 const read=file=>file==="/etc/pacman.conf"?{repositories:["core","extra"],dbPath:"/var/lib/pacman/"}:effective;
 const pending=managers.reviewCheckFor("pacman","pacman","/transaction/pacman.conf",read);
 assert.equal(pending.complete,complete,label);
 same(pending.check.argv,complete?["checkupdates"]:["pacman","--config","/transaction/pacman.conf","-Qu"],label);
}
same(managers.reviewCheckFor("aur","paru","/nondefault.conf").check.argv,["paru","--config","/nondefault.conf","-Qua"]);
assert.equal(managers.reviewCheckFor("aur","paru","/nondefault.conf").origin,"aur");
verify(load(file));
const scratch=fs.mkdtempSync(path.join(os.tmpdir(),"test-package-review-"));
try {
 const source=fs.readFileSync(file,"utf8");
 // The judge imports the package table from beside it.
 fs.copyFileSync(path.join(path.dirname(file),"PackageManagers.js"),path.join(scratch,"PackageManagers.js"));
 // [mutant, needle, replacement, the row that must fail]: a flag for a
 // package not reviewed; any repository's package read as VGS's; a saved
 // Install without review that still asks.
 for(const [label,needle,replacement,fails] of [
  ["verdict","reviewed.indexOf(m[1]) < 0 || ","",/line=2/],
  ["publisher","if (viaAur !== true) return \"third-party\";\n","",/publisher: vgshell-git from a repository/],
  ["ask","ask: !(hasOwn(s, \"enabled\") && s.enabled === false) };","ask: true };",/"enabled":false/],
  ["architecture","var selected = own.length > 0 ? own : inherited;","var selected = inherited;",/recipe architecture: split override/]
 ]){
  assert.equal(source.split(needle).length-1,1,label);
  const mutant=path.join(scratch,"PackageReview-"+label+".js");fs.writeFileSync(mutant,source.replace(needle,replacement));
  assert.throws(()=>verify(load(mutant)),fails,label);
 }
} finally {fs.rmSync(scratch,{recursive:true,force:true});}
console.log("test-package-review: ok");
