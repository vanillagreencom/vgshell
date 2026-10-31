#!/usr/bin/env node
// The package persistence caller against a fake live Config endpoint. The
// production Config writer is exercised by its QML suite and live UI proof.
"use strict";
const fs=require("node:fs"),path=require("node:path"),assert=require("node:assert/strict");
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
const owner=require(path.join(tree,"bin/lib/pkg-review.js")),file=path.join(root,"config/vgshell/shell.json"),snapshot=owner.settingsRead();
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
if(["offline","saved-off","live-confirm"].includes(mode))assert.equal(error,null,error?.first);
else assert.ok(error?.first,mode);
if(mode==="live-unconfirmed"){
 assert.ok(error.first.startsWith("review-settings=live-unconfirmed"));
 assert.equal(fs.readFileSync(file,"utf8"),before);
 assert.equal(fs.readFileSync(path.join(root,"writes"),"utf8").trim().split("\n").length,1);
}
if(mode==="live-confirm")assert.equal(fs.readFileSync(file,"utf8"),before,"reply confirmation does not make the caller an offline writer");
if(mode==="offline"||mode==="saved-off"){
 const saved=JSON.parse(fs.readFileSync(file));assert.deepEqual(saved.disabledPlugins,["vgs.updates"]);
 assert.equal(saved.packages.review.agent,"codex");
 assert.equal(Object.hasOwn(saved.packages.review,"enabled"),mode==="saved-off");
 if(mode==="saved-off")assert.equal(saved.packages.review.enabled,false);
}
if(["concurrent","malformed","future"].includes(mode))assert.equal(fs.readFileSync(file,"utf8"),before);
if(mode==="offline-race")assert.equal(fs.readFileSync(file,"utf8"),snapshot.text+" ");
console.log("package-settings-proof: "+JSON.stringify({mode,outcome:error?error.first:"confirmed",preferencePresent:Object.hasOwn(choices,"enabled")}));
