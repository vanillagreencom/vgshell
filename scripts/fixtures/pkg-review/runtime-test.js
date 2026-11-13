#!/usr/bin/env node
// Real package-owner execution on a PTY. Paru's stub supplies the aur-fetch
// 0.11.3 make_view shape; all package, privilege and agent commands are stubs.
"use strict";
const assert=require("node:assert/strict"),fs=require("node:fs"),os=require("node:os"),path=require("node:path"),cp=require("node:child_process");
const {create}=require("./world.js");
const {load}=require("../../../bin/lib/qml-library.js");
const judge=load(path.resolve(__dirname,"../../../shell/Core/PackageReview.js"));
const scratch=fs.mkdtempSync(path.join(os.tmpdir(),"package-review-runtime-"));
const q=value=>"'"+value.replaceAll("'","'\\''")+"'";
function tty(world,args,env={}){
 const command=[process.execPath,world.owner,...args].map(q).join(" ");
 return cp.spawnSync("/usr/bin/script",["-qec",command,"/dev/null"],{env:{...world.env,...env,SHELL:"/usr/bin/bash"},encoding:"utf8",timeout:60000});
}
const write=(world,file,value)=>fs.writeFileSync(path.join(world.root,file),typeof value==="string"?value:JSON.stringify(value));
const agents=world=>world.calls().filter(call=>call.kind==="agent");
const builds=world=>world.calls().filter(call=>call.kind==="mutation"&&call.name==="paru");
const offers=world=>world.calls().filter(call=>call.kind==="offer");
// The keyed lines Updates reads from a step (pipeline.sh _updates_review_of).
const keyed=(result,key)=>judge.transcriptLines(result.stdout).filter(line=>line.startsWith("vgshell: "+key+": "));
try{
 // Each entry point reaches the same file-manager operation. The picker and
 // requirement notice themselves route to these same public owner verbs.
 for(const [name,args] of [
  ["terminal",["run","install","--manager","aur","widget"]],
  ["picker",["install","--manager","aur","widget"]],
  ["notice",["run","update","--manager","aur","widget","--install","dependency"]],
  ["upgrade",["run","upgrade","--manager","aur"]]
 ]){
  const world=create(path.join(scratch,name),{choices:["Review"]});
  const result=tty(world,args);
  assert.equal(result.status,0,name+": "+result.stdout+result.stderr);
  assert.equal(agents(world).length,1,name+": one agent review");
  assert.equal(world.calls().filter(call=>call.kind==="file-manager").length,1,name+": helper-owned view");
  assert.equal(builds(world).length,1,name+": reviewed build");
  const build=builds(world)[0];
  assert.ok(build.args.includes("--review")&&build.args.includes("--nosudoloop")&&!build.args.includes("--skipreview"),name);
  const snapshot=path.join(world.root,"agent-evidence/0/build");
  const base=fs.readdirSync(snapshot)[0],files=fs.readdirSync(path.join(snapshot,base));
  assert.ok(files.includes("PKGBUILD")&&files.includes(".SRCINFO"),name+": tracked recipe files");
  assert.ok(!files.includes("src")&&!files.includes("pkg")&&!files.some(file=>file.endsWith(".pkg.tar.zst")),name+": build output excluded");
  const before=world.calls().findIndex(call=>call.kind==="agent"),after=world.calls().findIndex(call=>call.kind==="mutation");
  assert.ok(before>=0&&after>before,name+": helper builds after review");
  for(const [command,drop] of [["sudo","-k"],["pkcheck","--revoke-temp"]]){
   const dropped=world.calls().findIndex(call=>call.kind==="credential"&&call.name===command&&call.args[0]===drop);
   assert.ok(dropped>=0&&dropped<before,name+": "+command+" "+drop+" goes before the agent starts");
  }
  assert.ok(!world.calls().some(call=>call.name==="doas"),name+": doas persist needs no drop");
 }
 // A saved decline and VGS-only full build order bypass the hook. A newly
 // added third-party dependency restores it even for a VGS target.
 for(const [name,settings,order,expected] of [
  ["saved",{enabled:false,agent:"claude",command:""},null,0],
  ["publisher",{agent:"claude",command:""},"AUR TARGET vgshell-git vgshell-git",0],
  ["publisher-dependency",{agent:"claude",command:""},"AUR TARGET vgshell-git vgshell-git\nAUR DEP dependency dependency",1]
 ]){
  const world=create(path.join(scratch,name),{settings,choices:expected?["Review"]:[]});
  write(world,"dependency-world.json",{pending:["vgshell-git"],...(order?{buildOrder:{upgrade:order,"vgshell-git":order}}:{})});
  write(world,"hook-world.json",{packages:[{base:"vgshell-git"},{base:"dependency"}]});
  const result=tty(world,["run","upgrade","--manager","aur"]);
  assert.equal(result.status,0,name+": "+result.stdout+result.stderr);
  assert.equal(agents(world).length,expected,name+": agent count");
  assert.equal(offers(world).length,expected?1:0,name+": review questions");
  assert.equal(builds(world)[0].args.includes("--skipreview"),expected===0,name+": helper review choice");
 }
 // paru --gendb follows a successful build; a built devel base it leaves
 // untracked is a result line, never a failed install.
 for(const [name,untracked] of [["devel-tracked",[]],["devel-untracked",["vgshell-git"]]]){
  const world=create(path.join(scratch,name),{settings:{agent:"claude",command:""},choices:[]}),order="AUR TARGET vgshell-git vgshell-git";
  write(world,"dependency-world.json",{pending:["vgshell-git"],buildOrder:{upgrade:order,"vgshell-git":order}});
  write(world,"devel-world.json",{untracked});
  const result=tty(world,["run","upgrade","--manager","aur"]);
  assert.equal(result.status,0,name+": "+result.stdout+result.stderr);
  assert.equal(world.calls().filter(call=>call.kind==="devel-completion").length,1,name+": tracking repair after the build");
  assert.deepEqual(keyed(result,"package-result").filter(line=>line.includes("vgshell-git")).length,untracked.length,name+": untracked devel base result");
 }
 // A flagged base and its pending transitive dependents leave one second
 // call. The clean tree's stored verdict means no repeated VGS question.
 for(const [name,changed,status,agentCount,offerCount] of [["same-tree",false,0,1,2],["changed-tree",true,1,2,3]]){
  const world=create(path.join(scratch,name),{choices:["Review","@skip",...(changed?["Review"]:[])]});
  write(world,"dependency-world.json",{pending:["bad","dependent","transitive","vgshell-git","clean"],flag:"bad",flagOnRepeat:changed});
  write(world,"hook-world.json",{packages:[{base:"bad"},{base:"dependent",depends:["bad>=1"]},{base:"transitive",depends:["dependent"]},{base:"vgshell-git",depends:["bad"]},{base:"clean"}]});
  if(changed)write(world,"change-tree-on-repeat","");
  const result=tty(world,["run","upgrade","--manager","aur"]);
  assert.equal(result.status,status,name+": "+result.stdout+result.stderr);
  assert.equal(agents(world).length,agentCount,name+": verdict belongs to its tree");
  assert.equal(world.calls().filter(call=>call.kind==="helper-start").length,2,name+": one repeated helper call");
  assert.equal(offers(world).length,offerCount,name+": review questions");
  const calls=world.calls().filter(call=>call.kind==="helper-start"),second=calls[1];
  const ignored=second.args.flatMap((word,index)=>word==="--ignore"?[second.args[index+1]]:[]);
  assert.deepEqual(ignored.sort(),["bad","dependent","transitive","vgshell-git"],name+": dependency closure");
  const delivered=judge.transcriptLines(result.stdout).join(" ").replace(/\s+/g," ");
  const skippedSentences=[...delivered.matchAll(/Packages skipped after the review: ([^.]+)\./g)];
  assert.equal(skippedSentences.length,1,name+": skipped names are delivered once");
  assert.deepEqual(skippedSentences[0][1].split(/,\s*/).sort(),["bad","dependent","transitive","vgshell-git"],name+": every skipped package is named");
  // One result line per flagged package names it and every dependent.
  const results=keyed(result,"package-result");
  assert.equal(results.length,1,name+": one skip result line");
  assert.ok(["bad","dependent","transitive","vgshell-git"].every(pkg=>results[0].includes(pkg)),name+": the skip result names each skipped package");
  assert.ok(!second.args.includes("--skipreview"),name+": second call preserves paru review");
  assert.equal(builds(world).length,status?0:1,name+": a second flag builds nothing and never loops");
  for(const call of calls){
   const store=path.dirname(call.args[call.args.indexOf("--fm")+1]);
   assert.ok(store.startsWith(world.env.XDG_RUNTIME_DIR+"/vgshell/updates/"),name+": owner store in runtime updates root");
   assert.ok(!store.startsWith("/tmp/")&&!store.startsWith(world.env.TMPDIR+"/"),name+": store outside temporary write roots");
   for(const agent of agents(world))assert.ok(!store.startsWith(agent.reviewDir+"/")&&!store.startsWith(agent.cwd+"/"),name+": store outside every agent working root");
  }
 }
 // Agent failures choose the other installed agent first. Skipping the AUR
 // skips the step, status 0, as a Skip of every named package does. A
 // missing agent is never started, and a signal during the agent cancels
 // the step with no further question.
 for(const [name,marker,choices,expected,offerCount,status,built,options] of [
  ["other-agent","agent-failed-once",["Review","@selected"],2,2,0,1,{}],
  ["skip-aur","agent-failed-once",["Review","Skip AUR packages"],1,2,0,0,{}],
  ["no-verdict","agent-no-verdict",["Review","Skip AUR packages"],1,2,0,0,{}],
  ["unsafe-verdict","agent-unsafe",["Review","Skip AUR packages"],1,2,0,0,{}],
  ["missing-agent",null,["Review","Skip AUR packages"],0,2,0,0,{agents:false}],
  ["agent-interrupted","agent-interrupted",["Review"],1,1,130,0,{}],
  ["owner-terminated","agent-terminates-owner",["Review"],1,1,143,0,{}],
  ["drop-no-session","pkcheck-no-session",["Review"],1,1,0,1,{}],
  ["drop-no-session-authorized",["pkcheck-no-session","pkcheck-authorized"],["Review"],0,1,1,0,{}],
  ["drop-failed","pkcheck-failed",["Review"],0,1,1,0,{}]
 ]){
  const world=create(path.join(scratch,name),{choices,...options});
  for(const file of [].concat(marker??[]))write(world,file,"");
  if(name==="other-agent")write(world,"agent-mutates","");
  const result=tty(world,["run","install","--manager","aur","widget"]);
  assert.equal(result.status,status,name+": "+result.stdout+result.stderr);
  assert.equal(agents(world).length,expected,name);
  assert.equal(offers(world).length,offerCount,name+": review questions");
  if(name==="missing-agent")assert.deepEqual(offers(world)[1].offered,["Install without review","Skip AUR packages"],name+": no other agent to offer");
  // A drop that could not run lets the review go on only when polkit
  // answers that nothing is held; any other failed drop ends it, with the
  // command's own cause on the diagnostic line.
  if(name.startsWith("drop-no-session"))assert.ok(world.calls().some(call=>call.name==="pkcheck"&&call.args[0]==="--action-id"),name+": polkit is asked about this process");
  if(name==="drop-failed")assert.ok(keyed(result,"review-diagnostic").some(line=>line.includes("Error revoking temporary authorizations")),name+": the drop's own cause");
  if(name==="owner-terminated")assert.deepEqual(world.calls().filter(call=>call.kind.startsWith("agent-")&&call.kind!=="agent-edit").map(call=>call.kind),["agent-term"],name+": the TERM sent to the owner reaches the agent");
  if(status===0&&built===0)assert.equal(keyed(result,"package-review").length,1,name+": the skip is the step's one review result");
  if(expected===2){
   assert.deepEqual(agents(world).map(call=>call.name),["claude","codex"],name);
   assert.equal(world.calls().filter(call=>call.kind==="agent-edit").length,1,name+": first agent changed its own recipe copy");
   const first=fs.readFileSync(path.join(world.root,"agent-evidence/0/build/widget/PKGBUILD"),"utf8");
   const second=fs.readFileSync(path.join(world.root,"agent-evidence/1/build/widget/PKGBUILD"),"utf8");
   assert.equal(second,first,name+": fallback agent reads the original tracked bytes");
   assert.ok(!second.includes("AGENT_MUTATION"),name+": first agent edits do not cross attempts");
  }
  assert.equal(builds(world).length,built,name);
  const sentence=result.stdout.slice(result.stdout.lastIndexOf("vgshell: package-review:"));
  assert.ok(!sentence.includes("user:secret")&&!sentence.includes("ghp_"),name+": sanitized reported last line");
 }
 // Paru's leading flags and untrusted tracked metadata cannot widen the
 // file-manager path or installed-script lookup before review.
 for(const [name,scenario] of [
  ["foreign-leading",{foreignLeading:true}],
  ["metadata-path",{packages:[{base:"widget",names:["../outside"]}]}]
 ]){
  const world=create(path.join(scratch,name),{choices:[]});
  write(world,"hook-world.json",scenario);
  const result=tty(world,["run","install","--manager","aur","widget"]);
  assert.equal(result.status,1,name+": "+result.stdout+result.stderr);
  assert.equal(agents(world).length,0,name);assert.equal(builds(world).length,0,name);
 }
 // Bootstrap reviews its existing fetched clone through the same operation.
 // A Skip of paru there skips the helper, as a Skip of every target does.
 for(const [name,flag] of [["bootstrap",null],["bootstrap-skip","paru"]]){
  const {cloneRecipe}=require("./world.js"),world=create(path.join(scratch,name),{choices:flag?["Review","@skip"]:["Review"],gitStandIn:true});
  if(flag)write(world,"dependency-world.json",{flag});
  const clone=cloneRecipe(world,"paru"),answer=path.join(world.root,"ended.json");
  const code='require(process.argv[1]).bootstrap(process.argv[2]).then(ended=>{require("node:fs").writeFileSync(process.argv[3],JSON.stringify(ended));})';
  const command=[process.execPath,"-e",code,path.resolve(__dirname,"../../../bin/lib/pkg-review.js"),clone,answer].map(q).join(" ");
  const result=cp.spawnSync("/usr/bin/script",["-qec",command,"/dev/null"],{env:{...world.env,SHELL:"/usr/bin/bash"},encoding:"utf8",timeout:60000});
  assert.equal(result.status,0,name+": "+result.stdout+result.stderr);assert.equal(agents(world).length,1,name);
  const ended=JSON.parse(fs.readFileSync(answer,"utf8"));
  assert.deepEqual(ended&&{status:ended.status,kind:ended.outcome.kind},flag?{status:0,kind:"package-skipped"}:null,name+": review outcome");
  assert.ok(!world.calls().some(call=>call.name==="git"&&call.args.includes("clone")),name+": no second fetch");
  assert.ok(fs.existsSync(path.join(clone,"PKGBUILD")),name+": original build clone remains");
 }
 // A check-only failure retries through the same hook and tree store,
 // without asking the VGS review question a second time.
 {
  const world=create(path.join(scratch,"immediate-retry"),{choices:["Install without review","Retry without tests"]}),target="vgs-fixture-check-only";
  write(world,"build.json",{first:{transcript:"paru-check-only",status:1},retry:{status:0}});
  const result=tty(world,["run","install","--manager","aur",target]);
  assert.equal(result.status,0,result.stdout+result.stderr);
  assert.equal(builds(world).length,2,"immediate retry: one additional build");
  assert.equal(offers(world).length,2,"immediate retry: only initial review and retry choices");
  assert.equal(builds(world).filter(call=>call.args.includes("--nocheck")).length,1,"immediate retry: tests skipped once");
  assert.equal(world.calls().filter(call=>call.kind==="devel-completion").length,1,"immediate retry: tracking follows successful install once");
 }
 // A requirement failure holds one retry. Claiming consumes it once, and
 // the retry enters current file-manager review before disabling tests.
 {
  const world=create(path.join(scratch,"held-retry"),{choices:["Install without review","Stop"]});
  const records=path.join(world.env.XDG_RUNTIME_DIR,"vgshell/tui"),key="core/requirements-install",target="vgs-fixture-check-only";
  function present(run,args){
   const command=["/usr/bin/bash",path.resolve(__dirname,"../../../bin/vgshell-tui"),"present","--presentation","plain","--record",key,"--run",run,"--record-dir",records,"--app-id","vgs-test","--window-title","Test","--",process.execPath,world.owner,...args].map(q).join(" ");
   const result=cp.spawnSync("/usr/bin/script",["-qec",command,"/dev/null"],{env:{...world.env,SHELL:"/usr/bin/bash"},encoding:"utf8",timeout:60000});
   const file=path.join(records,"core@requirements-install@"+run+".ended.json");
   return {...result,record:fs.existsSync(file)?JSON.parse(fs.readFileSync(file,"utf8")):null};
  }
  write(world,"build.json",{first:{transcript:"paru-check-only",status:1},retry:{status:0}});
  let result=present("held1",["run","install","--manager","aur",target]);
  assert.equal(result.status,1,result.stdout+result.stderr);
  assert.deepEqual(result.record.package.retry,{originRun:"held1",state:"available"});
  write(world,"choices.json",["Review"]);
  result=present("held2",["retry","held1"]);
  assert.equal(result.status,0,result.stdout+result.stderr);
  assert.equal(result.record.package.testsSkipped,true);
  assert.equal(agents(world).length,1,"held retry: current recipe reviewed");
  result=present("held3",["retry","held1"]);
  assert.equal(result.status,1,"held retry: only one claim");
  assert.equal(builds(world).filter(call=>call.args.includes("--nocheck")).length,1,"held retry: exactly one test-skipping build");
  write(world,"choices.json",["esc"]);
  result=present("held4",["run","install","--manager","aur",target]);
  assert.equal(result.status,130,result.stdout+result.stderr);
  assert.deepEqual(result.record.package,{kind:"package-cancelled",manager:"aur",status:130},"review cancellation keeps the presenter's typed outcome");

 }
 // Every settings persistence mode keeps its existing Config contract.
 for(const mode of ["offline","saved-off","offline-race","live-confirm","live-unconfirmed","concurrent","malformed","future","unreadable"]){
  const world=create(path.join(scratch,"settings-"+mode),{settings:{agent:"",command:""}});
  const result=cp.spawnSync(process.execPath,[path.join(__dirname,"settings.js"),world.root,mode],{env:world.env,encoding:"utf8",timeout:30000});
  assert.equal(result.status,0,result.stdout+result.stderr);
 }
 console.log("test-package-review-runtime: ok");
}finally{fs.rmSync(scratch,{recursive:true,force:true});}
