#!/usr/bin/env node
// The package persistence caller against a fake live Config endpoint. The
// production Config writer is exercised by its QML suite and live UI proof.
// offline-previous and offline-copy-blocked start from a user file of the
// previous format version, which the offline write converts only once its
// pre-conversion copy under XDG_STATE_HOME holds its bytes.
// offline-editor-blocked and offline-editor-changed drive the terminal
// editor's Save (bin/lib/pkg-review-settings.sh) through a tree copy of
// bin/vgshell-pkg on a pseudo-terminal, since the owner refuses a write
// without one. Stand-ins for the tui and choice functions answer Save,
// Return to editor, then cancel, and log each line the editor shows.
"use strict";
const fs=require("node:fs"),path=require("node:path"),assert=require("node:assert/strict"),cp=require("node:child_process");
const [root,mode]=process.argv.slice(2),repo=path.resolve(__dirname,"../../.."),tree=path.join(root,"tree");
fs.mkdirSync(path.join(tree,"bin/lib"),{recursive:true});
for(const name of ["pkg-review.js","pkg-review.sh","pkg-review-settings.sh","qml-library.js","judge-files.js","ipc-reply.sh","tui.sh"])fs.copyFileSync(path.join(repo,"bin/lib",name),path.join(tree,"bin/lib",name));
for(const name of ["shell","config"])fs.symlinkSync(path.join(repo,name),path.join(tree,name));
const endpoint=`#!/usr/bin/env node
const fs=require("node:fs"),path=require("node:path");
const args=process.argv.slice(2),root=${JSON.stringify(root)},mode=${JSON.stringify(mode)};
if(args[3]==="packageReviewRead"){
 if(mode.startsWith("offline")||mode==="saved-off"){
  if(mode==="offline-race")fs.appendFileSync(path.join(root,"config/vgshell/shell.json")," ");
  process.stderr.write("vgshell: refused: shell=not-running lock=fixture\\n");process.exit(69);
 }
 process.stdout.write("INFO client log\\n{}\\n");process.exit(0);
}
if(args[3]!=="packageReviewWrite")process.exit(2);
fs.appendFileSync(path.join(root,"writes"),JSON.stringify(args)+"\\n");
if(mode==="live-confirm")process.stdout.write("INFO client log\\n\\u001b[32mok\\u001b[0m\\n");
`;
fs.writeFileSync(path.join(tree,"bin/vgshell"),endpoint,{mode:0o755});
process.env.XDG_STATE_HOME=path.join(root,"state");
const file=path.join(root,"config/vgshell/shell.json"),copy=path.join(root,"state/vgshell/shell-pre-conversion.json");
const configVersion=require(path.join(repo,"bin/lib/qml-library.js")).load(path.join(repo,"shell/Core/ConfigLogic.js")).CONFIG_VERSION;
const previous=["offline-previous","offline-copy-blocked","offline-editor-blocked"].includes(mode);
if(previous)fs.writeFileSync(file,JSON.stringify({version:configVersion-1,disabledPlugins:["vgs.updates"],packages:{review:{agent:"",command:""}}},null,1));
if(mode==="offline-copy-blocked"||mode==="offline-editor-blocked")fs.mkdirSync(copy,{recursive:true});
if(mode.startsWith("offline-editor-")){
 fs.cpSync(path.join(repo,"bin/lib"),path.join(tree,"bin/lib"),{recursive:true});
 fs.copyFileSync(path.join(repo,"bin/vgshell-pkg"),path.join(tree,"bin/vgshell-pkg"));
 const driver=path.join(root,"editor.sh"),log=path.join(root,"editor.log"),q=v=>"'"+v.replaceAll("'","'\\''")+"'";
 fs.writeFileSync(driver,`log=$1 file=$2 mode=$3
vgs_tui_clear() { :; }
vgs_tui_header() { :; }
vgs_tui_text() { printf 'text: %s\\n' "$1" >>"$log"; }
vgs_tui_error() { printf 'error: %s\\n' "$1" >>"$log"; }
vgs_tui_success() { printf 'success: %s\\n' "$1" >>"$log"; }
vgs_pkg_review_command() { :; }
vgs_pkg_review_choose() {
  case $1 in
    'Change package review choices')
      [[ ! -e $log.saved ]] || return 1
      : >"$log.saved"
      [[ $mode != offline-editor-changed ]] || printf ' ' >>"$file"
      printf 'Save\\n' ;;
    'Keep your choices') printf 'Return to editor\\n' ;;
    *) return 1 ;;
  esac
}
source "$4"
vgs_pkg_review_settings "$5"
printf 'status: %s\\n' "$?" >>"$log"
`);
 const before=fs.readFileSync(file,"utf8");
 const command=["bash",driver,log,file,mode,path.join(tree,"bin/lib/pkg-review-settings.sh"),path.join(tree,"bin/vgshell-pkg")].map(q).join(" ");
 const run=cp.spawnSync("script",["-qec",command,"/dev/null"],{encoding:"utf8",timeout:60000});
 const shown=fs.existsSync(log)?fs.readFileSync(log,"utf8").split("\n"):[];
 const detail=run.stdout+run.stderr+shown.join("\n");
 assert.ok(shown.includes("status: 130"),detail);
 assert.ok(shown.includes("error: VGS could not save the settings. Your choices are still open."),detail);
 const reopen=shown.filter(line=>line.includes("reopen"));
 if(mode==="offline-editor-blocked"){
  assert.ok(shown.includes("text: VGS could not save a backup of your settings file, so it did not update the file to the new format."),detail);
  assert.deepEqual(reopen,[],detail);
  assert.equal(fs.readFileSync(file,"utf8"),before,"the user file is left");
 }else{
  assert.deepEqual(reopen,["text: The settings file changed after this editor read it. Cancel and reopen this editor to read it again."],detail);
 }
 console.log("package-settings-proof: "+JSON.stringify({mode,cause:shown[shown.indexOf("error: VGS could not save the settings. Your choices are still open.")+1]}));
 process.exit(0);
}
const owner=require(path.join(tree,"bin/lib/pkg-review.js")),snapshot=owner.settingsRead();
const choices={agent:"codex",command:""};
if(mode==="saved-off")choices.enabled=false;
if(mode==="concurrent")fs.appendFileSync(file," ");
if(mode==="malformed")fs.writeFileSync(file,"{");
if(mode==="future")fs.writeFileSync(file,JSON.stringify({version:999}));
if(mode==="unreadable")fs.chmodSync(file,0);
const before=mode==="unreadable"?null:fs.readFileSync(file,"utf8");
let error=null;
try{owner.settingsWrite(snapshot,choices);}catch(e){error=e;}
if(mode==="unreadable")fs.chmodSync(file,0o600);
if(["offline","offline-previous","saved-off","live-confirm"].includes(mode))assert.equal(error,null,error?.first);
else assert.ok(error?.first,mode);
if(mode==="live-unconfirmed"){
 assert.ok(error.first.startsWith("review-settings=live-unconfirmed"));
 assert.equal(fs.readFileSync(file,"utf8"),before);
 assert.equal(fs.readFileSync(path.join(root,"writes"),"utf8").trim().split("\n").length,1);
}
if(mode==="live-confirm")assert.equal(fs.readFileSync(file,"utf8"),before,"reply confirmation does not make the caller an offline writer");
if(mode==="offline-previous"){
 assert.equal(fs.readFileSync(copy,"utf8"),before,"the copy holds the bytes before");
 const saved=JSON.parse(fs.readFileSync(file));assert.equal(saved.version,configVersion);
 assert.deepEqual(saved.disabledPlugins,["vgs.updates"]);assert.equal(saved.packages.review.agent,"codex");
}
if(mode==="offline-copy-blocked")assert.ok(error.first.startsWith("user-config=pre-conversion-unsaved path="+copy+" "),error.first);
if(mode==="offline"||mode==="saved-off"){
 const saved=JSON.parse(fs.readFileSync(file));assert.deepEqual(saved.disabledPlugins,["vgs.updates"]);
 assert.equal(saved.packages.review.agent,"codex");
 assert.equal(Object.hasOwn(saved.packages.review,"enabled"),mode==="saved-off");
 if(mode==="saved-off")assert.equal(saved.packages.review.enabled,false);
}
if(["concurrent","malformed","future","offline-copy-blocked"].includes(mode))assert.equal(fs.readFileSync(file,"utf8"),before);
if(mode==="offline-race")assert.equal(fs.readFileSync(file,"utf8"),snapshot.text+" ");
console.log("package-settings-proof: "+JSON.stringify({mode,outcome:error?error.first:"confirmed",preferencePresent:Object.hasOwn(choices,"enabled")}));
