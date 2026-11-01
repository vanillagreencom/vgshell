#!/usr/bin/env node
// Production admission and authority, in an isolated stand-in PATH on a PTY.
"use strict";
const assert=require("node:assert/strict"),fs=require("node:fs"),os=require("node:os"),path=require("node:path"),cp=require("node:child_process");
const {create}=require("./world.js");
const only=process.argv.includes("--cancel-control");
const surfaceAt=process.argv.indexOf("--surface"),surface=surfaceAt<0?"all":process.argv[surfaceAt+1];
const select=name=>surface==="all"||surface===name;
assert.ok(["all","direct","routes","choices","authority","availability","evidence","updates","bootstrap","settings","protocol","origin","workspace","control","origin-control","customize","customize-control","retry","retry-held"].includes(surface));
if(only)assert.ok(["all","direct"].includes(surface));
const overrideAt=process.argv.indexOf("--owner"),ownerOverride=overrideAt<0?null:process.argv[overrideAt+1];
const scratch=fs.mkdtempSync(path.join(os.tmpdir(),"package-review-runtime-"));
const q=s=>"'"+s.replaceAll("'","'\\''")+"'";
function tty(w,args){
 const executable=args[0]==="vgshell"?["/usr/bin/bash",path.resolve(__dirname,"../../../bin/vgshell"),...args.slice(1)]:[process.execPath,ownerOverride||w.owner,...args];
 const command=executable.map(s=>"'"+s.replaceAll("'","'\\''")+"'").join(" ");
 return cp.spawnSync("/usr/bin/script",["-qec",command,"/dev/null"],{env:{...w.env,SHELL:"/usr/bin/bash"},encoding:"utf8",timeout:30000});
}
try{
 for(const manager of ["pacman","aur"])for(const scenario of ["review","decline","cancel"]){
  if(!select("direct"))continue;
  if(only && (manager!=="pacman"||scenario!=="cancel"))continue;
  const w=create(path.join(scratch,manager+scenario),{choices:scenario==="decline"?["Install without review"]:scenario==="cancel"?["cancel"]:["Review","Use Claude Code","Yes"]});
  const r=tty(w,["run","upgrade","--manager",manager,"--config",w.config,"--ignore","excluded"]),calls=w.calls();
  assert.equal(r.status,scenario==="cancel"?130:0,r.stdout+r.stderr);
  if(!only)console.log("package-route-proof: "+JSON.stringify({route:"direct-"+manager+"-"+scenario,calls}));
  const offer=calls.find(c=>c.kind==="offer");assert.ok(offer);assert.equal(offer.selectedIndex,0);
  if(scenario==="cancel")assert.ok(!calls.some(c=>["credential","mutation","agent"].includes(c.kind)));
  else{
   const mutation=calls.find(c=>c.kind==="mutation");assert.ok(mutation,JSON.stringify(calls));
   assert.deepEqual(mutation.args,["--config",w.config,manager==="pacman"?"-Syu":"-Sua","--ignore","excluded"]);
   const firstCredential=calls.findIndex(c=>c.kind==="credential"),review=calls.findIndex(c=>c.kind==="offer");
   assert.ok(firstCredential<0||firstCredential>review);
   assert.equal(calls.some(c=>c.kind==="agent"),scenario==="review");
   if(scenario==="review")assert.equal(calls.find(c=>c.kind==="agent").cwd,path.join(w.root,"run/vgshell/package-review"));
  }
 }
 if(!only&&select("origin"))for(const manager of ["pacman","aur"]){
  const w=create(path.join(scratch,"official-collision-"+manager),{choices:["cancel"]});fs.writeFileSync(path.join(w.root,"origin-changed"),"");
  const r=tty(w,["run","upgrade","--manager",manager,"--config",w.config]),calls=w.calls();
  console.log("package-origin-attempt-proof: "+JSON.stringify({manager,status:r.status,offered:calls.some(c=>c.kind==="offer"),mutated:calls.some(c=>c.kind==="mutation")}));
  // Pacman uses a nondefault local DB, whose freshness remains unknown.
  // The AUR-only query/plan must never turn this same-name official row
  // into permission to build without the common offer.
  assert.equal(r.status,130,r.stdout+r.stderr);assert.ok(calls.some(c=>c.kind==="offer"));
  assert.ok(!calls.some(c=>["credential","agent","mutation"].includes(c.kind)));
  console.log("package-origin-proof: "+JSON.stringify({manager,calls}));
 }
 if(!only&&select("workspace"))for(const kind of ["presenter","writable","symlink"]){
  const w=create(path.join(scratch,"workspace-"+kind),{choices:["Review","Use Claude Code","Yes"]}),ns=path.join(w.root,"run/vgshell");
  if(kind==="symlink"){fs.mkdirSync(path.join(w.root,"outside"));fs.symlinkSync(path.join(w.root,"outside"),ns);}
  else{fs.mkdirSync(ns);fs.chmodSync(ns,kind==="presenter"?0o755:0o777);}
  const allocated=cp.spawnSync(process.execPath,[w.owner,"review-transaction"],{env:w.env,encoding:"utf8"});
  assert.equal(allocated.status,kind==="presenter"?0:1,allocated.stderr);
  if(kind==="presenter"){
   const dir=allocated.stdout.trim(),base=path.join(ns,"package-review");assert.equal(path.dirname(dir),base);assert.equal(fs.statSync(dir).mode&0o777,0o700);fs.rmSync(dir,{recursive:true});
   const r=tty(w,["run","upgrade","--manager","aur","--config",w.config]);assert.equal(r.status,0,r.stdout+r.stderr);
   const agent=w.calls().find(c=>c.kind==="agent");assert.equal(agent.cwd,base);assert.ok(agent.reviewDir.startsWith(base+path.sep));assert.ok(!fs.existsSync(agent.reviewDir));
  }else assert.ok(!w.calls().some(c=>["agent","credential","mutation"].includes(c.kind)));
  console.log("package-workspace-proof: "+JSON.stringify({kind,status:allocated.status}));
 }
 if(!only&&select("routes"))for(const [route,args,expected] of [
  ["named-cli",["vgshell","pkg","run","install","--manager","pacman","widget"],["-S","--needed","--","widget"]],
  ["cli-install-alias",["vgshell","pkg","install","--manager","pacman","widget"],["-S","--needed","--","widget"]],
  ["direct-install-alias",["install","--manager","pacman","widget"],["-S","--needed","--","widget"]],
  ["picker",["install","--manager","pacman"],["-S","--needed","--","widget"]],
  ["requirements-install",["run","install","--manager","pacman","widget"],["-S","--needed","--","widget"]],
  ["requirements-update",["run","update","--manager","pacman","widget"],["-S","--needed","--","widget"]],
  ["requirements-mixed",["run","update","--manager","pacman","widget","--install","aurpkg"],["-S","--needed","--","widget","aurpkg"]],
  ["reinstall",["run","reinstall","--manager","pacman","widget"],["-S","--","widget"]]
 ]){
  const w=create(path.join(scratch,route)),r=tty(w,args),calls=w.calls();
  assert.equal(r.status,0,r.stdout+r.stderr);
  const offer=calls.find(c=>c.kind==="offer");assert.ok(offer);assert.equal(offer.choiceIndex,1);
  const mutation=calls.find(c=>c.kind==="mutation");assert.ok(mutation);assert.deepEqual(mutation.args,expected);
  console.log("package-route-proof: "+JSON.stringify({route,args,calls}));
 }
 if(!only&&select("choices"))for(const [label,settings,agents,selectedIndex] of [
  ["saved-on",{enabled:true,agent:"",command:""},false,0],
  ["saved-off",{enabled:false,agent:"claude",command:""},true,1],
  ["absent-configured",{agent:"claude",command:""},true,0],
  ["absent-configured-unavailable",{agent:"claude",command:""},false,0],
  ["absent-default",{agent:"",command:""},true,0],
  ["absent-neither",{agent:"",command:""},false,1]]){
  const w=create(path.join(scratch,label),{settings,agents,choices:["cancel"]});const r=tty(w,["run","install","--manager","aur","--config",w.config,"widget"]);
  assert.equal(r.status,130,r.stdout);assert.equal(w.calls().find(c=>c.kind==="offer").selectedIndex,selectedIndex);assert.ok(!w.calls().some(c=>c.kind==="mutation"||c.kind==="credential"));
 }
 // A review run through Customize, with one edit view opened and left, keeps
 // the caller's screen: no kind, the inline editor included, clears it.
 if(!only&&select("customize")){
  const w=create(path.join(scratch,"customize"),{choices:["Review","Customize","First choice","Back","Cancel","Use Claude Code"]});
  const r=tty(w,["run","install","--manager","aur","--config",w.config,"widget"]),calls=w.calls();
  assert.equal(r.status,0,r.stdout+r.stderr);
  assert.ok(calls.some(c=>c.kind==="offer"&&c.offered.includes("First choice")),JSON.stringify(calls));
  assert.ok(calls.some(c=>c.kind==="agent")&&calls.some(c=>c.kind==="mutation"));
  assert.ok(!r.stdout.includes("\x1b[2J"),"package-customize=screen-cleared");
  console.log("package-customize-proof: "+JSON.stringify({status:r.status,offers:calls.filter(c=>c.kind==="offer").length}));
 }
 if(!only&&select("authority"))for(const [manager,change] of [
  ...["pacman","aur"].flatMap(manager=>["none","consumed","manager","action","targets","config","include","config-path","ignore","pending","origin","binary","transaction","missing","unreadable","symlink","recipe","outer","outer-missing","config-link","config-link-changed"].map(change=>[manager,change])),
  ["pacman","origin-read-failed"],
  ["aur","custom-origin-read-failed"]
 ]){
  const w=create(path.join(scratch,"authority-"+manager+"-"+change),{choices:change==="recipe"?["Review","Use Claude Code","Yes"]:change==="custom-origin-read-failed"?["Install without review","Yes"]:["Install without review"]});
  const fixture=path.join(__dirname,"authority.js");
  const command=[process.execPath,fixture,w.root,change,manager].map(s=>"'"+s.replaceAll("'","'\\''")+"'").join(" ");
  const r=cp.spawnSync("/usr/bin/script",["-qec",command,"/dev/null"],{env:{...w.env,SHELL:"/usr/bin/bash"},encoding:"utf8",timeout:30000});
  assert.equal(r.status,0,r.stdout+r.stderr);
  const result=JSON.parse(fs.readFileSync(path.join(w.root,"authority-result.json"))),calls=w.calls();
  const allowed=change==="none"||change==="config-link"||(change==="outer"&&manager==="pacman");
  assert.equal(result.code===0,allowed,r.stdout);
  if(change==="origin-read-failed"||change==="custom-origin-read-failed")assert.match(r.stdout,/review=authority-binding-(?:unreadable|changed)/);
  assert.equal(calls.filter(c=>c.kind==="mutation").length-result.before,allowed?(change==="none"&&manager==="pacman"?3:1):0,change+":"+JSON.stringify(calls));
  assert.equal(calls.filter(c=>c.kind==="offer"&&c.offered.includes("Review")).length,1);
  if(change==="outer"&&manager==="pacman")assert.ok(!calls.some(c=>c.kind==="credential"&&c.args[0]==="-k"));
  console.log("package-authority-proof: "+JSON.stringify({manager,change,result,mutations:calls.filter(c=>c.kind==="mutation")}));
 }
 if(!only&&select("availability")){
  const w=create(path.join(scratch,"configured-unavailable"),{agents:false,settings:{agent:"codex",command:""},choices:["Review","No"]});
  const r=tty(w,["run","install","--manager","aur","--config",w.config,"widget"]);assert.equal(r.status,0,r.stdout);
  assert.equal(w.calls().find(c=>c.kind==="offer").selectedIndex,0);
  assert.equal(w.calls().filter(c=>c.kind==="offer").at(-1).selectedIndex,0);
  assert.ok(!w.calls().some(c=>["agent","credential","mutation"].includes(c.kind)));
  const f=create(path.join(scratch,"probe-failed"),{agents:false,settings:{agent:"codex",command:""},choices:[]});
  fs.symlinkSync("codex",path.join(f.root,"tools/codex"));
  const failed=tty(f,["run","install","--manager","aur","--config",f.config,"widget"]);assert.equal(failed.status,1,failed.stdout);
  assert.ok(!f.calls().some(c=>["offer","agent","credential","mutation"].includes(c.kind)));
  assert.equal(JSON.parse(fs.readFileSync(path.join(f.root,"config/vgshell/shell.json"))).packages.review.agent,"codex");
 }
 if(!only&&select("evidence"))for(const [marker,target,choices,mutation,agent] of [
  ["install-risk","foreign",["Review","Use Claude Code","Yes","Skip"],false,true],
  ["install-link","foreign",["Review","Use Claude Code","Yes","Skip"],false,false],
  ["srcinfo-link","foreign",["Review","Use Claude Code","Yes","Skip"],false,false],
  ["agent-no-verdict","widget",["Review","Use Claude Code","No"],false,true],
  ["agent-failed","widget",["Review","Use Claude Code","No"],false,true],
  ["agent-malformed","widget",["Review","Use Claude Code","No"],false,true],
  ["agent-dependency","foreign",["Review","Use Claude Code","No"],false,true],
  ["fetch-failed","foreign",["Review","Use Claude Code","No"],false,false],
  ["server-empty","widget",["Review","Use Claude Code","No"],false,true],
  ["query-failed","widget",["Review","Use Claude Code","No"],false,true],
  ["provider-ambiguous","foreign",["Review","Use Claude Code","No"],false,true],
  ["agent-concern","widget",["Review","Use Claude Code","Skip"],false,true]
 ]){
  const w=create(path.join(scratch,"evidence-"+marker),{choices});fs.writeFileSync(path.join(w.root,marker),"");
  const r=tty(w,["run","install","--manager","aur","--config",w.config,target]),calls=w.calls();
  assert.equal(r.status,0,r.stdout+r.stderr);assert.equal(calls.some(c=>c.kind==="mutation"),mutation);assert.equal(calls.some(c=>c.kind==="agent"),agent);
  assert.ok(!calls.some(c=>c.kind==="credential"));
  if(marker==="query-failed")assert.ok(r.stdout.includes(target),"the requested package remains visible when provenance cannot be read");
  for(const answer of calls.filter(c=>c.kind==="offer"&&c.offered.includes("Yes")))assert.equal(answer.selectedIndex,0);
  console.log("package-evidence-proof: "+JSON.stringify({marker,calls}));
 }
 if(!only&&select("evidence")){
  const w=create(path.join(scratch,"named-skip"),{choices:["Review","Use Claude Code","Skip"]});fs.writeFileSync(path.join(w.root,"agent-concern"),"");
  const r=tty(w,["run","update","--manager","pacman","--config",w.config,"widget","--install","aurpkg"]);assert.equal(r.status,0,r.stdout);
  assert.deepEqual(w.calls().find(c=>c.kind==="mutation").args,["--config",w.config,"-S","--needed","--","aurpkg"]);
  const u=create(path.join(scratch,"upgrade-skip"),{choices:["Review","Use Claude Code","Yes","Skip"]});fs.writeFileSync(path.join(u.root,"agent-concern"),"");
  const upgrade=tty(u,["run","upgrade","--manager","pacman","--config",u.config,"--ignore","input-ignore"]);assert.equal(upgrade.status,0,upgrade.stdout);
  assert.deepEqual(u.calls().find(c=>c.kind==="mutation").args,["--config",u.config,"-Syu","--ignore","input-ignore","--ignore","widget"]);
 }
 if(!only&&select("updates"))for(const kind of ["existing","helper","recognized","recognized-skip","custom","custom-stop"]){
  const choices=kind==="recognized-skip"?["Review","Use Claude Code","Yes","Skip"]:kind==="helper"?["Install without review","Install without review","Install without review"]:kind.startsWith("custom")?["Install without review",kind==="custom-stop"?"No":"Yes"]:["Install without review"];
  const w=create(path.join(scratch,"updates-"+kind),{choices,helper:kind!=="helper"}),fixture=path.join(__dirname,"pipeline.js");
  if(kind==="recognized-skip")fs.writeFileSync(path.join(w.root,"agent-concern"),"");
  const command=[process.execPath,fixture,w.root,kind].map(s=>"'"+s.replaceAll("'","'\\''")+"'").join(" ");
  const r=cp.spawnSync("/usr/bin/script",["-qec",command,"/dev/null"],{env:{...w.env,SHELL:"/usr/bin/bash"},encoding:"utf8",timeout:60000});
  assert.equal(r.status,0,r.stdout+r.stderr);
  const calls=w.calls(),offers=calls.map((c,i)=>[c,i]).filter(([c])=>c.kind==="offer"&&c.offered.includes("Review"));
  if(kind==="custom-stop")assert.ok(!calls.some(c=>["credential","mutation","snapshot"].includes(c.kind)));
  else{
   const offer=offers.at(-1)[1],snapshot=calls.findIndex(c=>c.kind==="snapshot");
   assert.ok(snapshot>offer);assert.ok(calls.findIndex((c,i)=>i>offer&&c.kind==="credential")>offer);
   assert.equal(offers.length,kind==="helper"?3:1);
   assert.ok(!calls.slice(snapshot).some(c=>c.kind==="offer"));
   const upgrades=calls.filter(c=>c.kind==="package-entry"&&c.args[1]==="run"&&["upgrade","reinstall"].includes(c.args[2]));
   assert.ok(upgrades.every(c=>c.args.includes("--review-receipt")));
   assert.equal(upgrades.length,kind==="helper"||kind==="custom"?2:3);
   assert.equal(calls.filter(c=>c.kind==="mutation").length,kind==="helper"?4:3);
   if(kind==="helper")assert.ok(calls.findIndex(c=>c.kind==="mutation"&&c.name==="makepkg")<offer);
   if(kind==="custom")assert.ok(calls.some(c=>c.kind==="mutation"&&c.args.includes("--devel")));
  }
  assert.ok(!fs.readdirSync(path.join(w.root,"run/vgshell/package-review")).some(n=>/^(transaction|review|bootstrap)-/.test(n)));
  console.log("package-route-proof: "+JSON.stringify({route:"updates-"+kind,calls}));
 }
 if(!only&&select("bootstrap"))for(const scenario of ["review","decline","cancel"]){
  const choices=scenario==="review"?["Review","Use Claude Code","continue-then-decline"]:scenario==="cancel"?["cancel"]:["Install without review","continue-then-decline"];
  const w=create(path.join(scratch,"bootstrap-"+scenario),{choices,helper:false});
  const r=tty(w,["ensure-helper"]),calls=w.calls();
  assert.equal(r.status,scenario==="cancel"?130:0,r.stdout+r.stderr);
  const firstCredential=calls.findIndex(c=>c.kind==="credential"),build=calls.findIndex(c=>c.kind==="mutation"&&c.name==="makepkg");
  if(scenario==="cancel")assert.ok(firstCredential<0&&build<0);
  else{
   assert.ok(build>=0);assert.equal(calls.filter(c=>c.kind==="offer"&&c.offered.includes("Review")).length,2);
   if(scenario==="review")assert.ok(calls.findIndex(c=>c.name==="git")<firstCredential);
   assert.ok(calls.findIndex(c=>c.kind==="offer")<firstCredential);
  }
  console.log("package-route-proof: "+JSON.stringify({route:"helper-bootstrap-"+scenario,calls}));
 }
 if(!only&&select("settings"))for(const mode of ["offline","saved-off","offline-race","live-confirm","live-unconfirmed","concurrent","malformed","future","unreadable"]){
  const w=create(path.join(scratch,"settings-"+mode),{settings:{agent:"",command:""}});
  const r=cp.spawnSync(process.execPath,[path.join(__dirname,"settings.js"),w.root,mode],{env:w.env,encoding:"utf8",timeout:30000});
  assert.equal(r.status,0,r.stdout+r.stderr);process.stdout.write(r.stdout);
 }
 if(!only&&select("protocol"))for(const kind of ["malformed","request-link","result-link","request-large","request-public","result-filled","mode-action","source-set","null-group-config"]){
  const w=create(path.join(scratch,"protocol-"+kind),{choices:[]}),dir=path.join(w.root,"run/transaction");fs.mkdirSync(dir,{mode:0o700});
  const request=path.join(dir,"request"),result=path.join(dir,"result"),doc={version:1,mode:"named",action:"install",groups:[{manager:"pacman",names:["widget"],installs:[],ignored:[]}],sources:[],rebuild:[],config:w.config,customAurArgv:null};
  fs.writeFileSync(request,JSON.stringify(doc),{mode:0o600});fs.writeFileSync(result,"",{mode:0o600});
  if(kind==="mode-action"){doc.action="upgrade";fs.writeFileSync(request,JSON.stringify(doc));}
  if(kind==="source-set"){doc.mode="upgrade";doc.action="upgrade";doc.groups[0].names=[];doc.sources=["aur"];fs.writeFileSync(request,JSON.stringify(doc));}
  if(kind==="null-group-config"){doc.groups[0].config=null;fs.writeFileSync(request,JSON.stringify(doc));}
  if(kind==="malformed")fs.writeFileSync(request,"{");
  if(kind==="request-large")fs.writeFileSync(request," ".repeat(1024*1024+1));
  if(kind==="request-public")fs.chmodSync(request,0o644);
  if(kind==="result-filled")fs.writeFileSync(result,"{}");
  if(kind.endsWith("-link")){const file=kind.startsWith("request")?request:result;fs.renameSync(file,file+".saved");fs.symlinkSync(file+".saved",file);}
  const r=tty(w,["review","--request",request,"--result",result]);assert.equal(r.status,1,r.stdout+r.stderr);
  assert.ok(!w.calls().some(c=>["offer","credential","mutation","agent"].includes(c.kind)));
  console.log("package-protocol-proof: "+JSON.stringify({kind,status:r.status}));
 }
 if(!only&&select("control")){
  const repo=path.resolve(__dirname,"../../.."),copy=path.join(scratch,"mutant"),source=fs.readFileSync(path.join(repo,"bin/vgshell-pkg"),"utf8");
  fs.mkdirSync(path.join(copy,"bin"),{recursive:true});
  for(const entry of ["shell","config","VERSION"])fs.symlinkSync(path.join(repo,entry),path.join(copy,entry));
  fs.symlinkSync(path.join(repo,"bin/lib"),path.join(copy,"bin/lib"));fs.symlinkSync(path.join(repo,"bin/vgshell"),path.join(copy,"bin/vgshell"));
  const needle='require("./lib/pkg-review.js").admit(action, manager, names, ignored, installs, config, receipt)';
  assert.equal(source.split(needle).length-1,1);
  const mutant=path.join(copy,"bin/vgshell-pkg");fs.writeFileSync(mutant,source.replace(needle,"({names,ignored,installs,config})"));
  const control=cp.spawnSync(process.execPath,[__filename,"--cancel-control","--owner",mutant],{env:{PATH:"/usr/bin:/bin",TMPDIR:scratch},encoding:"utf8",timeout:30000});
  assert.equal(control.status,1,control.stdout+control.stderr);
 }
 // A build whose own tests alone failed offers one retry without them,
 // Stop selected, and never retries by itself. Stand-in builds replay the
 // recorded transcripts (scripts/fixtures/pkg/check-failure).
 const TARGET="vgs-fixture-check-only",CHECK={transcript:"paru-check-only",status:1},ORDINARY={transcript:"paru-build-fail",status:1},PASS={status:0};
 const scenario=(w,first,retry)=>fs.writeFileSync(path.join(w.root,"build.json"),JSON.stringify({first,retry}));
 const mutations=w=>w.calls().filter(c=>c.kind==="mutation");
 const retryOffers=w=>w.calls().filter(c=>c.kind==="offer"&&c.offered.includes("Retry without tests"));
 // The keyed cause a failure prints when the classifier could not read it.
 const unclassified=r=>/vgshell: build-failure=unclassified reason=(\S+)/.exec(r.stdout)?.[1]??null,UNCLASSIFIED={"German messages":"locale=unsupported"};
 if(!only&&select("retry"))for(const [label,args,first,retry,choice,status,again,env] of [
  ["retried",["run","install","--manager","aur","--config","CONFIG",TARGET],CHECK,PASS,"Retry without tests",0,["--config","CONFIG","-S","--needed","--nocheck","--",TARGET]],
  ["update with installs",["run","update","--manager","aur","--config","CONFIG","widget","--install",TARGET],CHECK,PASS,"Retry without tests",0,["--config","CONFIG","-S","--needed","--nocheck","--",TARGET]],
  ["reinstall",["run","reinstall","--manager","aur","--config","CONFIG",TARGET],CHECK,PASS,"Retry without tests",0,["--config","CONFIG","-S","--nocheck","--",TARGET]],
  ["install alias",["install","--manager","aur",TARGET],CHECK,PASS,"Retry without tests",0,["-S","--needed","--nocheck","--",TARGET]],
  ["stopped",["run","install","--manager","aur","--config","CONFIG",TARGET],CHECK,null,"Stop",1,null],
  ["cancelled",["run","install","--manager","aur","--config","CONFIG",TARGET],CHECK,null,"cancel",130,null],
  ["escaped",["run","install","--manager","aur","--config","CONFIG",TARGET],CHECK,null,"esc",130,null],
  ["retry failed",["run","install","--manager","aur","--config","CONFIG",TARGET],CHECK,{transcript:"paru-check-only",status:1},"Retry without tests",1,["--config","CONFIG","-S","--needed","--nocheck","--",TARGET]],
  ["ordinary",["run","install","--manager","aur","--config","CONFIG",TARGET],ORDINARY,null,null,1,null],
  ["two failed bases",["run","install","--manager","aur","--config","CONFIG",TARGET],{transcript:"paru-multi",status:1},null,null,1,null],
  ["German messages",["run","install","--manager","aur","--config","CONFIG",TARGET],CHECK,null,null,1,null,{LC_ALL:"",LANG:"de_DE.UTF-8"}]
 ]){
  const w=create(path.join(scratch,"retry-"+label.replaceAll(" ","-")),{choices:["Install without review",...(choice?[choice]:[])]});
  scenario(w,first,retry);
  const r=tty({...w,env:{...w.env,...(env||{})}},args.map(a=>a==="CONFIG"?w.config:a)),built=mutations(w),offers=retryOffers(w);
  assert.equal(r.status,status,label+": "+r.stdout);
  assert.equal(unclassified(r),UNCLASSIFIED[label]??null,label);
  assert.equal(offers.length,choice?1:0,label);
  if(choice)assert.equal(offers[0].selected,"Stop",label);
  assert.equal(built.length,again?2:1,label+": "+JSON.stringify(built));
  assert.ok(!built[0].args.includes("--nocheck"),label);
  if(again){
   assert.deepEqual(built[1].args,again.map(a=>a==="CONFIG"?w.config:a),label);
   const calls=w.calls(),asked=calls.findIndex(c=>c.kind==="offer"&&c.offered.includes("Retry without tests")),ran=calls.findLastIndex(c=>c.kind==="mutation");
   assert.ok(ran>asked&&calls.findIndex(c=>c.kind==="mutation")<asked,label+": the retry follows its question");
  }
  console.log("package-retry-proof: "+JSON.stringify({label,status:r.status,offers:offers.length,mutations:built.map(c=>c.args)}));
 }
 if(!only&&select("retry"))for(const [label,choice,status,built] of [["retried","Retry without tests",0,2],["stopped","Stop",4,1]]){
  const w=create(path.join(scratch,"bootstrap-retry-"+label),{choices:["Install without review","Install without review",choice],helper:false});
  scenario(w,{transcript:"makepkg-check-only",status:4,base:"paru"},PASS);
  const r=tty(w,["ensure-helper"]),builds=mutations(w).filter(c=>c.name==="makepkg");
  assert.equal(r.status,status,label+": "+r.stdout);
  assert.equal(builds.length,built,label);
  assert.deepEqual(builds.map(c=>c.args),[["-si"],["-si","--nocheck"]].slice(0,built),label);
  assert.ok(builds.every(c=>c.cwd===builds[0].cwd),label+": the retry builds the same tree");
  assert.ok(!fs.existsSync(builds[0].cwd),label+": the tree goes with the owner");
  assert.ok(builds[0].cwd.startsWith(fs.realpathSync(path.join(w.root,"tmp"))+path.sep),label+": the tree is in the temporary directory");
  assert.equal(fs.existsSync(path.join(w.root,"tools/paru")),status===0,label);
  console.log("package-retry-proof: "+JSON.stringify({label:"bootstrap-"+label,status:r.status,builds:builds.map(c=>c.args)}));
 }
 // A prepared Updates step keeps Updates' own failure report: its build that
 // failed only in check() asks nothing.
 if(!only&&select("retry")){
  const w=create(path.join(scratch,"authority-check-failed"));
  scenario(w,{transcript:"paru-check-only",status:1,base:"aurpkg"},null);
  const command=[process.execPath,path.join(__dirname,"authority.js"),w.root,"check-failed","aur"].map(q).join(" ");
  const r=cp.spawnSync("/usr/bin/script",["-qec",command,"/dev/null"],{env:{...w.env,SHELL:"/usr/bin/bash"},encoding:"utf8",timeout:30000});
  assert.equal(r.status,0,r.stdout+r.stderr);
  const result=JSON.parse(fs.readFileSync(path.join(w.root,"authority-result.json")));
  assert.equal(result.code,1,r.stdout);assert.deepEqual(retryOffers(w),[]);assert.equal(mutations(w).length-result.before,1);
  console.log("package-retry-proof: "+JSON.stringify({label:"prepared",status:result.code}));
 }
 // The presenter's outcome channel carries the owner's typed outcome into
 // the run's ended record, and a requirement run that stopped holds its one
 // retry for `vgshell pkg retry`.
 if(!only&&select("retry-held")){
  const w=create(path.join(scratch,"retry-held"),{choices:[]}),records=path.join(w.root,"run/vgshell/tui"),held=path.join(w.root,"run/vgshell/package-review/retry");
  const choose=list=>fs.writeFileSync(path.join(w.root,"choices.json"),JSON.stringify(list));
  const present=(key,run,args,wrap)=>{
   const owner=[process.execPath,w.owner,...args],command=wrap?["/usr/bin/bash","-c",owner.map(q).join(" ")+"; exit $?"]:owner;
   const argv=["/usr/bin/bash",path.resolve(__dirname,"../../../bin/vgshell-tui"),"present","--presentation","plain","--record",key,"--run",run,"--record-dir",records,"--app-id","vgs-test","--window-title","Test","--",...command];
   const r=cp.spawnSync("/usr/bin/script",["-qec",argv.map(q).join(" "),"/dev/null"],{env:{...w.env,SHELL:"/usr/bin/bash"},encoding:"utf8",timeout:60000});
   const ended=path.join(records,key.replace("/","@")+"@"+run+".ended.json");
   return {...r,record:fs.existsSync(ended)?JSON.parse(fs.readFileSync(ended,"utf8")):null};
  };
  const install=["run","install","--manager","aur","--config",w.config,TARGET],INSTALL="core/requirements-install";
  const checkFailed=(run,state,status=1)=>({kind:"package-check-failed",manager:"aur",helper:"paru",package:TARGET,status,retry:state===null?null:{originRun:run,state}});
  const stop=(run,key=INSTALL)=>{choose(["Install without review","Stop"]);scenario(w,CHECK,null);return present(key,run,install);};
  const retried=(run,origin,retry)=>{
   choose([]);scenario(w,null,retry);const before=w.calls().length,r=present(INSTALL,run,["retry",origin]),after=w.calls().slice(before);
   assert.ok(!after.some(c=>c.kind==="offer"),"a held retry asks nothing again");
   return {...r,built:after.filter(c=>c.kind==="mutation")};
  };
  const heldRuns=()=>fs.existsSync(held)?fs.readdirSync(held).filter(n=>n.endsWith(".json")):[];
  let r=stop("run1");
  assert.equal(r.record.code,1);assert.deepEqual(r.record.package,checkFailed("run1","available"));
  assert.deepEqual(heldRuns(),["core@requirements-install@run1.json"]);
  assert.equal(fs.statSync(path.join(held,heldRuns()[0])).mode&0o777,0o600);
  r=retried("run2","run1",PASS);
  assert.equal(r.record.code,0,r.stdout);assert.deepEqual(r.record.package,{kind:"package-installed",manager:"aur",helper:"paru",package:TARGET,testsSkipped:true});
  assert.deepEqual(r.built.map(c=>c.args),[["--config",w.config,"-S","--needed","--nocheck","--",TARGET]]);
  assert.deepEqual(heldRuns(),[]);
  r=retried("run3","run1",PASS);
  assert.equal(r.record.code,1);assert.equal(r.record.package,undefined);assert.deepEqual(r.built,[]);assert.match(r.stdout,/refused: retry=unavailable run=run1/);
  stop("run4");r=retried("run5","run4",{transcript:"paru-check-only",status:1});
  assert.equal(r.record.code,1);assert.deepEqual(r.record.package,checkFailed("run4","consumed"));assert.equal(r.built.length,1);
  r=retried("run6","run4",PASS);assert.deepEqual(r.built,[]);assert.match(r.stdout,/retry=unavailable/);
  stop("run7");r=retried("run8","run7",{status:130});
  assert.equal(r.record.code,130);assert.deepEqual(r.record.package,{kind:"package-cancelled",manager:"aur",status:130});
  r=retried("run9","run7",PASS);assert.deepEqual(r.built,[]);assert.match(r.stdout,/retry=unavailable/);
  stop("run10");fs.rmSync(path.join(records,"core@requirements-install@run10.ended.json"));
  r=retried("run11","run10",PASS);assert.deepEqual(r.built,[]);assert.match(r.stdout,/retry=stale run=run10/);assert.deepEqual(heldRuns(),[]);
  stop("run12");choose(["Install without review"]);scenario(w,PASS,null);r=present(INSTALL,"run13",install);
  assert.deepEqual(r.record.package,{kind:"package-installed",manager:"aur",helper:"paru"});assert.deepEqual(heldRuns(),[]);
  stop("run14","core/requirements-update");stop("run15");
  assert.deepEqual(heldRuns().sort(),["core@requirements-install@run15.json","core@requirements-update@run14.json"]);
  r=stop("run16","core/pkg-install");assert.deepEqual(r.record.package,checkFailed("run16",null));
  assert.ok(!heldRuns().some(n=>n.includes("pkg-install")));
  choose(["Install without review","Stop"]);scenario(w,CHECK,null);r=present("core/pkg-install","run17",install,true);
  assert.equal(r.record.code,1);assert.equal(r.record.package,undefined,"a nested owner reports nothing");
  fs.appendFileSync(w.include,"# changed\n");
  r=retried("run18","run15",PASS);assert.deepEqual(r.built,[]);assert.match(r.stdout,/retry=changed run=run15/);
  // A held retry builds only the recipe it held.
  const marked=(name,act)=>{fs.writeFileSync(path.join(w.root,name),"");try{return act();}finally{fs.rmSync(path.join(w.root,name));}};
  stop("run19");r=marked("recipe-changed",()=>retried("run20","run19",PASS));
  assert.deepEqual(r.built,[]);assert.match(r.stdout,/retry=changed run=run19/);
  // A binding that cannot be read now is refused by its cause, and one that
  // could not be read at Stop holds nothing.
  stop("run21");r=marked("info-failed",()=>retried("run22","run21",PASS));
  assert.deepEqual(r.built,[]);assert.match(r.stdout,/retry=unreadable run=run21 reason=query=paru /);assert.doesNotMatch(r.stdout,/retry=changed/);
  r=marked("fetch-failed",()=>stop("run23"));
  assert.deepEqual(r.record.package,checkFailed("run23",null));assert.match(r.stdout,/vgshell: retry=unheld reason=recipe=fetch-failed/);
  assert.ok(!heldRuns().some(n=>n.includes("run23")));
  // Esc on the review offer and on the retry question is their cancel,
  // whose outcome the judge accepts.
  for(const [run,list,first] of [["run24",["esc"],null],["run25",["Install without review","esc"],CHECK]]){
   choose(list);scenario(w,first,null);r=present(INSTALL,run,install);
   assert.equal(r.record.code,130,run+": "+r.stdout);assert.deepEqual(r.record.package,{kind:"package-cancelled",manager:"aur",status:130},run);
   assert.doesNotMatch(r.stdout,/package-outcome=unwritten/,run);
  }
  assert.ok(!fs.readdirSync(records).some(n=>n.includes(".outcome.")),"each presenter removes its channel");
  console.log("package-retry-held-proof: ok");
 }
 for(const entry of fs.readdirSync(scratch)){const dir=path.join(scratch,entry,"run/vgshell/package-review");if(fs.existsSync(dir)&&!entry.startsWith("authority-"))assert.ok(!fs.readdirSync(dir).some(n=>/^(review|bootstrap|transaction|build|helper|recipe)-/.test(n)),entry);}
 if(!only&&(select("control")||surface==="origin-control")){
  const repo=path.resolve(__dirname,"../../.."),copy=path.join(scratch,"origin-mutant");
  fs.mkdirSync(path.join(copy,"bin/lib"),{recursive:true});
  fs.symlinkSync(path.join(repo,"bin/vgshell"),path.join(copy,"bin/vgshell"));
  for(const entry of ["shell","config","VERSION"])fs.symlinkSync(path.join(repo,entry),path.join(copy,entry));
  for(const entry of fs.readdirSync(path.join(repo,"bin/lib")))if(entry!=="pkg-review.js")fs.symlinkSync(path.join(repo,"bin/lib",entry),path.join(copy,"bin/lib",entry));
  fs.copyFileSync(path.join(repo,"bin/vgshell-pkg"),path.join(copy,"bin/vgshell-pkg"));
  const source=fs.readFileSync(path.join(repo,"bin/lib/pkg-review.js"),"utf8"),needle='target.origin === "aur" && matches.length > 0';
  assert.equal(source.split(needle).length-1,1);
  const changed=source.replace(needle,'target.origin === "never-aur" && matches.length > 0');assert.notEqual(changed,source);
  fs.writeFileSync(path.join(copy,"bin/lib/pkg-review.js"),changed);
  const control=cp.spawnSync(process.execPath,[__filename,"--surface","origin","--owner",path.join(copy,"bin/vgshell-pkg")],{env:{PATH:"/usr/bin:/bin",TMPDIR:scratch},encoding:"utf8",timeout:60000});
  assert.equal(control.status,1,control.stdout+control.stderr);
  assert.match(control.stderr,/ERR_ASSERTION/,control.stdout+control.stderr);
  const attempted=control.stdout.split("\n").filter(line=>line.startsWith("package-origin-attempt-proof: ")).map(line=>JSON.parse(line.slice("package-origin-attempt-proof: ".length)));
  const mutant=attempted.find(row=>row.manager==="aur");
  assert.deepEqual(mutant,{manager:"aur",status:0,offered:false,mutated:true});
  console.log("package-origin-control-proof: "+JSON.stringify({status:control.status,mutant}));
 }
 if(!only&&(select("control")||surface==="customize-control")){
  const repo=path.resolve(__dirname,"../../.."),copy=path.join(scratch,"customize-mutant");
  fs.mkdirSync(path.join(copy,"bin/lib"),{recursive:true});
  fs.symlinkSync(path.join(repo,"bin/vgshell"),path.join(copy,"bin/vgshell"));
  for(const entry of ["shell","config","VERSION"])fs.symlinkSync(path.join(repo,entry),path.join(copy,entry));
  // node runs a linked module from its target, so pkg-review.js is a copy:
  // it finds the mutant pkg-review.sh beside it.
  for(const entry of fs.readdirSync(path.join(repo,"bin/lib")))if(!["pkg-review.sh","pkg-review.js"].includes(entry))fs.symlinkSync(path.join(repo,"bin/lib",entry),path.join(copy,"bin/lib",entry));
  for(const file of ["bin/vgshell-pkg","bin/lib/pkg-review.js"])fs.copyFileSync(path.join(repo,file),path.join(copy,file));
  const source=fs.readFileSync(path.join(repo,"bin/lib/pkg-review.sh"),"utf8"),needle='vgs_pkg_review_settings "$1" inline ;;';
  assert.equal(source.split(needle).length-1,1);
  fs.writeFileSync(path.join(copy,"bin/lib/pkg-review.sh"),source.replace(needle,'vgs_pkg_review_settings "$1" ;;'),{mode:0o755});
  const control=cp.spawnSync(process.execPath,[__filename,"--surface","customize","--owner",path.join(copy,"bin/vgshell-pkg")],{env:{PATH:"/usr/bin:/bin",TMPDIR:scratch},encoding:"utf8",timeout:60000});
  assert.equal(control.status,1,control.stdout+control.stderr);
  assert.match(control.stderr,/package-customize=screen-cleared/,control.stdout+control.stderr);
  console.log("package-customize-control-proof: "+JSON.stringify({status:control.status}));
 }
 console.log("test-package-review-runtime: ok");
}finally{fs.rmSync(scratch,{recursive:true,force:true});}
