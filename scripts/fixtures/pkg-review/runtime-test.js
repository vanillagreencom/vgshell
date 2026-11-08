#!/usr/bin/env node
// Production admission and authority, in an isolated stand-in PATH on a PTY.
"use strict";
const assert=require("node:assert/strict"),fs=require("node:fs"),os=require("node:os"),path=require("node:path"),cp=require("node:child_process");
const {create}=require("./world.js");
const only=process.argv.includes("--cancel-control");
const surfaceAt=process.argv.indexOf("--surface"),surface=surfaceAt<0?"all":process.argv[surfaceAt+1];
const select=name=>surface==="all"||surface===name;
const caseAt=process.argv.indexOf("--case"),caseName=caseAt<0?null:process.argv[caseAt+1];
assert.ok(["all","direct","routes","choices","authority","aur-authority","review-result","review-result-control","aur-authority-control","availability","evidence","updates","bootstrap","settings","protocol","origin","workspace","control","origin-control","customize","customize-control","retry","retry-held","retry-held-control","publisher","publisher-control","dependencies","dependency-authority","dependency-control","dependency-official-control","one-review","review-again","one-review-control","devel","devel-control"].includes(surface));
if(only)assert.ok(["all","direct"].includes(surface));
const overrideAt=process.argv.indexOf("--owner"),ownerOverride=overrideAt<0?null:process.argv[overrideAt+1];
const writerAt=process.argv.indexOf("--writer-owner"),writerOverride=writerAt<0?null:process.argv[writerAt+1];
const writerIncomplete=process.argv.includes("--writer-incomplete");
const scratch=fs.mkdtempSync(path.join(os.tmpdir(),"package-review-runtime-"));
const q=s=>"'"+s.replaceAll("'","'\\''")+"'";
function tty(w,args){
 const executable=args[0]==="vgshell"?["/usr/bin/bash",path.resolve(__dirname,"../../../bin/vgshell"),...args.slice(1)]:[process.execPath,w.tree||ownerOverride||w.owner,...args];
 const command=executable.map(s=>"'"+s.replaceAll("'","'\\''")+"'").join(" ");
 return cp.spawnSync("/usr/bin/script",["-qec",command,"/dev/null"],{env:{...w.env,SHELL:"/usr/bin/bash"},encoding:"utf8",timeout:30000});
}
function gathered(w,names){
 const request={version:1,mode:"named",action:"reinstall",groups:[{manager:"aur",names,installs:[],ignored:[]}],sources:[],rebuild:[],config:w.config,customAurArgv:null};
 const owner=path.join(path.dirname(ownerOverride||w.owner),"lib/pkg-review.js");
 const r=cp.spawnSync(process.execPath,["-e",'process.stdout.write(JSON.stringify(require(process.argv[1]).gather(JSON.parse(process.argv[2]))))',owner,JSON.stringify(request)],{env:w.env,encoding:"utf8",timeout:30000});
 assert.equal(r.status,0,r.stdout+r.stderr);return JSON.parse(r.stdout);
}
// A disposable owner tree: bin/vgshell-pkg, bin/lib/pkg-review.js and its
// loader bin/lib/pkg-retry.js are copies, since node runs a linked module
// from its target, with each of
// EDITS, [file, needle, replacement], applied to its one match; the rest
// links to the tree under test. Without recipes it has no packaging/arch.
function ownerTree(name,edits=[],{recipes=true}={}){
 const source=ownerOverride?path.resolve(path.dirname(ownerOverride),".."):path.resolve(__dirname,"../../.."),copy=path.join(scratch,"owners",name);
 const copied=new Set(["bin/vgshell-pkg","bin/lib/pkg-review.js","bin/lib/pkg-retry.js",...edits.map(edit=>edit[0])]);
 fs.mkdirSync(path.join(copy,"bin/lib"),{recursive:true});
 const tableEdited=copied.has("shell/Core/PackageManagers.js");
 for(const entry of [...(tableEdited?[]:["shell"]),"config","VERSION","bin/vgshell",...(recipes?["packaging"]:[])])fs.symlinkSync(path.join(source,entry),path.join(copy,entry));
 if(tableEdited){
  fs.mkdirSync(path.join(copy,"shell/Core"),{recursive:true});
  for(const entry of fs.readdirSync(path.join(source,"shell")))if(entry!=="Core")fs.symlinkSync(path.join(source,"shell",entry),path.join(copy,"shell",entry));
  for(const entry of fs.readdirSync(path.join(source,"shell/Core")))if(entry!=="PackageManagers.js")fs.symlinkSync(path.join(source,"shell/Core",entry),path.join(copy,"shell/Core",entry));
 }
 for(const entry of fs.readdirSync(path.join(source,"bin/lib")))if(!copied.has("bin/lib/"+entry))fs.symlinkSync(path.join(source,"bin/lib",entry),path.join(copy,"bin/lib",entry));
 for(const file of copied)fs.copyFileSync(path.join(source,file),path.join(copy,file));
 for(const [file,needle,replacement] of edits){
  const text=fs.readFileSync(path.join(copy,file),"utf8");assert.equal(text.split(needle).length-1,1,name+": "+needle);
  fs.writeFileSync(path.join(copy,file),text.replace(needle,replacement));
 }
 return path.join(copy,"bin/vgshell-pkg");
}
// A must-fail control: SURFACE run against the owner with EDITS must fail
// at the row FAILS names.
function control(name,surface,edits,fails,caseName){
 const r=cp.spawnSync(process.execPath,[__filename,"--surface",surface,...(caseName?["--case",caseName]:[]),"--owner",ownerTree(name,edits)],{env:{PATH:"/usr/bin:/bin",TMPDIR:scratch},encoding:"utf8",timeout:120000});
 assert.equal(r.status,1,name+": "+r.stdout+r.stderr);assert.match(r.stderr,fails,name+": "+r.stdout+r.stderr);
 console.log("package-control-proof: "+JSON.stringify({name,status:r.status}));
 return r;
}
try{
 if(!only&&(select("control")||surface==="devel-control")){
  control("devel-old-path","devel",[["shell/Core/PackageManagers.js",
   '    plan.steps.push([plan.binary].concat(config === undefined ? [] : ["--config", config], build.complete));',
   '    void build.complete;']],/devel: installed git package remains tracked/,"success");
 }
 // The native diagnostic is delivered output: preserve its git failure cause.
 const lookupDiagnostic="error: failed to lookup: vgshell-git: fatal: unable to access 'https://example.org/vgs.git/': Could not resolve host: example.org";
 if(!only&&select("devel"))for(const {label,installStatus=0,trackingStatus=0,status=installStatus||trackingStatus,trackingDiagnostic,missingTracking=false,missingResult=false} of [
  {label:"success"},{label:"install-failed",installStatus:9},{label:"tracking-failed",trackingStatus:8},
  {label:"lookup-failed",status:1,trackingDiagnostic:lookupDiagnostic,missingTracking:true},
  {label:"diagnostic-with-entry",status:1,trackingDiagnostic:lookupDiagnostic},
  {label:"missing-entry",status:1,missingTracking:true},{label:"missing-result",status:1,missingResult:true}
 ]){
  if(caseName!==null&&caseName!==label)continue;
  const w=create(path.join(scratch,"devel-"+label),{choices:[]});
  fs.writeFileSync(path.join(w.root,"config-corresponds"),"");
  fs.writeFileSync(path.join(w.root,"dependency-world.json"),JSON.stringify({pending:["vgshell-git"],buildOrder:{"vgshell-git":"AUR TARGET vgshell-git vgshell-git"}}));
  fs.writeFileSync(path.join(w.root,"devel-world.json"),JSON.stringify({
   cachedSources:{"vgshell-git":null},sources:{"vgshell-git":{url:"https://example.org/vgs.git",commit:"new-vgs-commit"}},
   tracked:{"vgshell-git":{url:"https://example.org/vgs.git",commit:"old-vgs-commit"},"other-git":{url:"https://example.org/other.git",commit:"other-installed-commit"}},
   installStatus,trackingStatus,trackingDiagnostic,missingTracking,missingResult
  }));
  const argv=[process.execPath,path.join(__dirname,"one-review.js"),w.root,ownerOverride||w.owner,"devel"];
  const r=cp.spawnSync("/usr/bin/script",["-qec",argv.map(q).join(" "),"/dev/null"],{env:{...w.env,SHELL:"/usr/bin/bash"},encoding:"utf8",timeout:60000});
  const results=fs.readFileSync(path.join(w.root,"devel-results.jsonl"),"utf8").trim().split("\n").map(JSON.parse).filter(result=>result.manager==="aur");
  assert.equal(results[0].status,status,label+": production status: "+r.stdout+r.stderr);
  assert.equal(r.status,status,label+": "+r.stdout+r.stderr);
  const calls=w.calls(),completed=calls.filter(c=>c.kind==="devel-completion");
  assert.equal(completed.length,installStatus?0:status?1:2,label+": tracking only follows successful installs");
  assert.ok(completed.every(c=>c.config===calls.find(c=>c.kind==="mutation"&&c.name==="paru").args[1]),label+": tracking uses the transaction config");
  if(trackingDiagnostic)assert.ok((r.stdout+r.stderr).includes(trackingDiagnostic),label+": native lookup cause retained");
  if(label==="success"){
   const checkpoints=fs.readFileSync(path.join(w.root,"devel-checkpoints.jsonl"),"utf8").trim().split("\n").map(JSON.parse);
   assert.deepEqual(checkpoints.map(c=>c.action),["upgrade","reinstall"],"devel: proof after each shared production operation");
  }
  console.log("package-devel-proof: "+JSON.stringify({label,status:r.status,completed:completed.length,commands:calls.filter(c=>c.kind==="mutation"||c.kind==="devel-completion").map(c=>c.args)}));
 }
 if(!only&&(select("control")||surface==="one-review-control")){
  const owner="bin/lib/pkg-review.js";
  control("generated-config","one-review",[[owner,'if (!p.complete && group.manager === "aur") state.unknown.push("pending=config-correspondence");','if (group.manager === "aur") state.unknown.push("pending=config-correspondence");']],/clean:/,"clean");
  control("repository-order","one-review",[[owner,'else if (matches.length) origin = matches[0].repository;','else if (matches.length === 1) origin = matches[0].repository;\n                else if (matches.length > 1) { state.unknown.push("origin=ambiguous name=" + name); origin = "unknown"; }']],/clean:/,"clean");
  control("verdict-group-membership","one-review",[[owner,'known.filter(name => !concerns.has(name))','known']],/skipped: clean summary members/,"skipped");
  control("review-agent-return","review-again",[[owner,'continue reviewChoice;','return { ...result, decision: "stop" };']],/No: review agents/);
  control("review-offer-return","review-again",[[owner,'if (!reviewable || !["agent", "command"].includes(plan.state)) choice = null;','if (false) choice = null;']],/no-agent-No:/,"no-agent-No");
  control("helper-repo-format","one-review",[[owner,'managers.parseBuildOrder(order.stdout)', 'managers.parseBuildOrder(order.stdout.replace(/^REPO /gm, "INSTALL "))']],/clean: helper review prompts/,"clean");
  control("helper-skipped-coverage","one-review",[[owner,'p.aur && permitted.has(p.name)','p.aur']],/skipped: helper review prompts/,"skipped");
  control("receipt-format","one-review",[[owner,'coverage: result.coverage, owner:', 'coverage: result.coverage, skipped: result.skipped, owner:']],/receipt-format: unchanged receipt decision fields/,"receipt-format");
  control("receipt-original-fields","one-review",[[owner,'const origins = state.steps.flatMap(decision => decision.binding === null ? [] : decision.binding.origins);','const origins = Object.values(state.dependents).flat();']],/receipt-format:/,"receipt-format");
  control("helper-order-diagnostic","one-review",[[owner,'process.stderr.write("package-review: " + JSON.stringify','void ("package-review: " + JSON.stringify']],/unread-order: order diagnostics/,"unread-order");
  control("helper-review-once","one-review",[["bin/vgshell-pkg",'if (receipt !== undefined) r.plan = table.reviewedBuild','if (false && receipt !== undefined) r.plan = table.reviewedBuild']],/declined: helper review prompts/,"declined");
 }
 if(!only&&select("review-again"))for(const kind of ["failed-agent","no-agent","unreviewable"])for(const decision of ["No","Yes","Stop"]){
  const label=kind==="failed-agent"?decision:kind+"-"+decision;
  if(caseName!==null&&caseName!==label)continue;
  const choices=["Review",...(kind==="failed-agent"?["Use Claude Code"]:[]),decision,...(decision==="No"?(kind==="failed-agent"?["Customize","AI agent","Codex\tcodex","Save","Use Codex"]:["Install without review"]):[])];
  const w=create(path.join(scratch,"review-again-"+label),{choices,agents:kind!=="no-agent"});
  fs.writeFileSync(path.join(w.root,"agent-failed-once"),"");
  if(kind==="unreviewable")fs.writeFileSync(path.join(w.root,"dependency-world.json"),JSON.stringify({info:{"vgshell-git":{"Check Deps":null}}}));
  const r=tty(w,["run",kind==="unreviewable"?"reinstall":"upgrade","--manager","aur","--config",w.config,...(kind==="unreviewable"?["vgshell-git"]:[])]),calls=w.calls();
  assert.equal(r.status,0,label+": "+r.stdout+r.stderr);
  const agents=calls.filter(c=>c.kind==="agent");
  assert.deepEqual(agents.map(c=>c.name),kind!=="failed-agent"?[]:decision==="No"?["claude","codex"]:["claude"],label+": review agents");
  if(decision==="No"&&kind==="failed-agent"){
   assert.deepEqual(agents[1].packages,agents[0].packages,"retry keeps packages and resets failed notes");
   assert.equal(calls.filter(c=>c.kind==="offer"&&c.offered.includes("Review")).length,1,"retry returns directly to agent choice");
  }
  if(kind!=="failed-agent")assert.equal(calls.filter(c=>c.kind==="offer"&&c.offered.includes("Review")).length,decision==="No"?2:1,label+": return to offer");
  assert.equal(calls.some(c=>c.kind==="mutation"),decision!=="Stop",decision+": mutation");
  console.log("package-review-again-proof: "+JSON.stringify({decision,agents:agents.map(c=>c.name),installs:decision!=="Stop"}));
 }
 if(!only&&select("one-review"))for(const scenario of ["clean","declined","unknown","retry","dependency","reviewed-dependency","skipped","propagated-skip","unread-order","signal-order","stderr-order","unknown-order","receipt-format"]){
  if(caseName!==null&&caseName!==scenario)continue;
  const skips=["skipped","propagated-skip"].includes(scenario);
  const w=create(path.join(scratch,"one-review-"+scenario),{choices:scenario==="declined"?["Install without review"]:["Review","Use Claude Code",...(scenario==="unknown"||scenario==="receipt-format"&&writerIncomplete?["Yes"]:scenario==="retry"?["No","Customize","AI agent","Codex\tcodex","Save","Use Codex"]:skips?["Skip"]:[])]});
  if(scenario==="unknown")fs.writeFileSync(path.join(w.root,"agent-failed"),"");
  if(scenario==="retry")fs.writeFileSync(path.join(w.root,"agent-failed-once"),"");
  fs.writeFileSync(path.join(w.root,"config-corresponds"),"");
  if(scenario==="clean"){
   fs.writeFileSync(w.include,"[cachyos-extra-znver4]\nServer=https://packages.example.org\n[core]\nServer=https://packages.example.org\n[custom]\nServer=https://packages.example.org\n");
   fs.writeFileSync(path.join(w.root,"sync-extra"),"core widget 2\ncachyos-extra-znver4 widget 2");
   fs.writeFileSync(path.join(w.root,"server-empty"),"");
  }
  // paru v2.1.0 src/order.rs emits REPO rows, including make dependencies.
  const order=(skips?"":"REPO MAKE core cmake\n")+"AUR TARGET second second\n"+(scenario==="propagated-skip"?"AUR DEP vgshell-git vgshell-git":"AUR DEP foreign foreign")+(["dependency","reviewed-dependency"].includes(scenario)?"\nAUR DEP extra extra":"");
  const unavailable={"unread-order":"exit-status","signal-order":"signal","stderr-order":"stderr","unknown-order":"unknown-output"}[scenario];
  const failure=scenario==="unread-order"?{status:7,stderr:"order read failed"}:scenario==="signal-order"?{signal:"SIGTERM"}:scenario==="stderr-order"?{stderr:"order warning"}:scenario==="unknown-order"?{stdout:"SRCINFO TARGET /recipes local second second"}:{};
  const dependency=scenario==="propagated-skip"?"foreign":scenario==="reviewed-dependency"?"extra":null;
  fs.writeFileSync(path.join(w.root,"dependency-world.json"),JSON.stringify({pending:["foreign","second"],prompts:true,flag:skips?"foreign":undefined,...(dependency?{info:{"vgshell-git":{"Depends On":dependency}},missing:[dependency]}:{}),buildOrder:{upgrade:unavailable?failure:order,foreign:"AUR TARGET foreign foreign",extra:"AUR TARGET extra extra","vgshell-git":"AUR TARGET vgshell-git vgshell-git"+(scenario==="reviewed-dependency"?"\nAUR DEP extra extra":"")}}));
  // The pre-VGS-2248 writer has no dependency mirror in its version-1
  // receipt. Its final steps and bound origins still carry the decision.
  const writer=scenario==="receipt-format"?writerOverride||ownerTree("receipt-original-schema",[["bin/lib/pkg-review.js",", dependents: Object.create(null)",""]]):null;
  const argv=[process.execPath,path.join(__dirname,"one-review.js"),w.root,ownerOverride||w.owner,scenario,...(writer?[writer]:[])];
  const r=cp.spawnSync("/usr/bin/script",["-qec",argv.map(q).join(" "),"/dev/null"],{env:{...w.env,SHELL:"/usr/bin/bash"},encoding:"utf8",timeout:60000}),calls=w.calls();
  assert.equal(r.status,0,scenario+": "+r.stdout+r.stderr);
  const reply=JSON.parse(fs.readFileSync(path.join(w.root,"one-review-result.json")));
  if(scenario==="clean"||scenario==="skipped"){
   const members=label=>[...r.stdout.matchAll(new RegExp(label+": ([^\\r\\n]*)\\.\\r?$","gm"))].map(match=>match[1].split(", "));
   assert.deepEqual(members("No concerns found"),[scenario==="clean"?["foreign","second"]:["second"]],scenario+": clean summary members");
   assert.deepEqual(members("Needs your decision"),scenario==="clean"?[]:[["foreign"]],scenario+": flagged summary members");
  }
  if(scenario==="clean"){
   const origins=JSON.parse(fs.readFileSync(path.join(w.root,"one-review-origins.json")));
   assert.equal(origins.find(row=>row.target==="widget").origin,"cachyos-extra-znver4","clean: pacman configuration order wins");
   const reviewed=calls.find(call=>call.kind==="agent").packages;
   assert.deepEqual(reviewed.filter(line=>line.startsWith("aur ")).map(line=>line.split(" ")[1]),["foreign","second"],"clean: mixed update reviews AUR targets only");
   assert.ok(!reviewed.some(line=>/^(repo|server|siglevel) /.test(line)),"clean: no repository evidence");
   assert.equal((r.stdout.match(/AUR packages:/g)||[]).length,1,"clean: list appears once");
   assert.equal((r.stdout.match(/No concerns found:/g)||[]).length,1,"clean: one grouped result");
   assert.doesNotMatch(r.stdout,/(?:origin|recipe)=[a-z-]+/,"clean: no raw failure keys");
  }
  assert.equal(reply.coverage,scenario==="declined"?"declined":scenario==="unknown"||scenario==="receipt-format"&&writerIncomplete?"unknown":"complete",scenario+": generated config coverage");
  if(!writerIncomplete)assert.ok(!calls.some(c=>c.kind==="agent"&&c.packages.some(line=>line.includes("pending=config-correspondence"))),scenario+": generated wrapper has complete pending list");
  assert.equal(calls.filter(c=>c.kind==="offer"&&c.offered.includes("Yes")).length,["unknown","retry"].includes(scenario)||scenario==="receipt-format"&&writerIncomplete?1:0,scenario+": unavailable question");
  const mutations=calls.filter(c=>c.kind==="mutation");assert.equal(mutations.length,scenario==="propagated-skip"?2:3,scenario+": permitted update steps install");
  if(skips)assert.deepEqual(reply.skipped,scenario==="propagated-skip"?["foreign","vgshell-git"]:["foreign"],scenario+": skipped packages");
  const prompts=calls.filter(c=>c.kind==="helper-prompt"),confirmations=calls.filter(c=>c.kind==="pacman-confirmation");
  const covered=["clean","declined","unknown","retry","reviewed-dependency"].includes(scenario)||scenario==="receipt-format"&&!writerOverride;
  assert.equal(prompts.length,covered?0:3,scenario+": helper review prompts");
  assert.equal(confirmations.length,covered||scenario==="propagated-skip"?4:5,scenario+": pacman transaction confirmations");
  const diagnostics=[...r.stdout.matchAll(/^package-review: (.+)\r?$/gm)].map(m=>JSON.parse(m[1]));
  assert.equal(diagnostics.length,unavailable?1:0,scenario+": order diagnostics");
  if(unavailable){assert.equal(diagnostics[0].review,"helper-order-unavailable");assert.equal(diagnostics[0].operation,"paru-build-order");assert.equal(diagnostics[0].cause,unavailable);assert.ok(diagnostics[0].command.includes("-Po"));if(failure.stderr)assert.equal(diagnostics[0].stderr,failure.stderr);if(failure.signal)assert.equal(diagnostics[0].signal,failure.signal);if(failure.status)assert.equal(diagnostics[0].status,failure.status);}
  assert.ok(mutations.filter(c=>c.name==="paru").every(c=>!c.args.includes("--noconfirm")&&!c.args.includes("-y")));
  console.log("package-one-review-proof: "+JSON.stringify({scenario,coverage:reply.coverage,helperPrompts:prompts.length,confirmations:confirmations.map(c=>c.transaction),mutations:mutations.map(c=>c.args)}));
 }
 for(const manager of ["aur"])for(const scenario of ["review","decline","cancel"]){
  if(!select("direct"))continue;
  if(only && scenario!=="cancel")continue;
  const w=create(path.join(scratch,manager+scenario),{choices:scenario==="decline"?["Install without review"]:scenario==="cancel"?["cancel"]:["Review","Use Claude Code"]});
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
 if(!only&&select("origin"))for(const manager of ["aur"]){
  const w=create(path.join(scratch,"official-collision-"+manager),{choices:["cancel"]});fs.writeFileSync(path.join(w.root,"origin-changed"),"");
  fs.writeFileSync(path.join(w.root,"dependency-world.json"),JSON.stringify({pending:"widget"}));
  const r=tty(w,["run","upgrade","--manager",manager,"--config",w.config]),calls=w.calls();
  console.log("package-origin-attempt-proof: "+JSON.stringify({manager,status:r.status,offered:calls.some(c=>c.kind==="offer"),mutated:calls.some(c=>c.kind==="mutation")}));
  // The AUR-only query/plan must never turn this same-name repository row
  // into permission to build without the common offer.
  assert.equal(r.status,130,r.stdout+r.stderr);assert.ok(calls.some(c=>c.kind==="offer"));
  assert.ok(!calls.some(c=>["credential","agent","mutation"].includes(c.kind)));
  console.log("package-origin-proof: "+JSON.stringify({manager,calls}));
 }
 if(!only&&select("workspace"))for(const kind of ["presenter","writable","symlink"]){
  const w=create(path.join(scratch,"workspace-"+kind),{choices:kind==="presenter"?["Review","Use Claude Code"]:[]}),ns=path.join(w.root,"run/vgshell");
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
  const w=create(path.join(scratch,route),{choices:[]}),r=tty(w,args),calls=w.calls();
  assert.equal(r.status,0,r.stdout+r.stderr);
  assert.ok(!calls.some(c=>c.kind==="offer"||c.kind==="agent"),route+": repository package needs no review");
  const mutation=calls.find(c=>c.kind==="mutation");assert.ok(mutation);assert.deepEqual(mutation.args,expected);
  console.log("package-route-proof: "+JSON.stringify({route,args,calls}));
 }
 // [label, saved settings, agents installed, the offer's selected row or
 // null for no offer]: a saved Install without review asks nothing and
 // installs as a submitted decline; every other saved choice asks.
 if(!only&&select("choices"))for(const [label,settings,agents,selectedIndex] of [
  ["saved-on",{enabled:true,agent:"",command:""},false,0],
  ["saved-off",{enabled:false,agent:"claude",command:""},true,null],
  ["absent-configured",{agent:"claude",command:""},true,0],
  ["absent-configured-unavailable",{agent:"claude",command:""},false,0],
  ["absent-default",{agent:"",command:""},true,0],
  ["absent-neither",{agent:"",command:""},false,1]]){
  const w=create(path.join(scratch,label),{settings,agents,choices:["cancel"]});const r=tty(w,["run","install","--manager","aur","--config",w.config,"foreign"]),calls=w.calls();
  const offer=calls.find(c=>c.kind==="offer");
  if(selectedIndex===null){
   assert.equal(r.status,0,label+": "+r.stdout);assert.equal(offer,undefined,label);assert.ok(!calls.some(c=>c.kind==="agent"),label);
   assert.deepEqual(calls.find(c=>c.kind==="mutation")?.args,["--config",w.config,"-S","--needed","--","foreign"],label);
  }else{
   assert.equal(r.status,130,label+": "+r.stdout);assert.equal(offer?.selectedIndex,selectedIndex,label);assert.ok(!calls.some(c=>c.kind==="mutation"||c.kind==="credential"),label);
  }
 }
 // A package VGS publishes, named by its recipes' pkgname lines, is not
 // listed for review when the owner resolved it through the AUR helper.
 // With its listed dependencies resolved, it opens no review question. The
 // same name from any pacman repository, one named aur included, needs
 // no review; recipes the owner cannot read are unavailable evidence. Each
 // row, under saved Review with an agent: [label, owner arguments, world
 // files, the owner's tree, lines the agent's packages.txt holds (none: no
 // agent runs), patterns no line of it matches, the AUR recipes fetched,
 // whether the requested package installs, the choices made].
 const REVIEWED=["Review","Use Claude Code"];
 if(!only&&select("publisher"))for(const [label,args,files,tree,listed,unlisted,fetched,installs,choices] of [
  ["mixed",["run","reinstall","--manager","aur","vgshell-git","foreign","widget","aurpkg"],{},"checkout",["aur foreign ? ?","unknown dependencies=unresolved name=foreign"],[/^aur vgshell/,/dependencies=unresolved name=vgshell/,/^(repo|server|siglevel) /,/^(aur|install) (widget|aurpkg) /],["foreign"],true,REVIEWED],
  ["vgs-only",["run","upgrade","--manager","aur"],{"dependency-world.json":'{"pending":"vgshell-git"}'},"checkout",[],[],[],true,["cancel"]],
  ["repository-same-name",["run","install","--manager","pacman","vgshell-git"],{"sync-extra":"custom vgshell-git 2"},"checkout",[],[],[],true,[]],
  ["repository-named-aur",["run","install","--manager","pacman","vgshell-git"],{"repo-aur":"","sync-extra":"aur vgshell-git 2"},"checkout",
   [],[/^aur /],[],true,[]],
  ["recipes-unreadable",["run","reinstall","--manager","aur","vgshell-git"],{},"no-recipes",
   ["aur vgshell-git ? ?","unknown vgs-packages=unreadable cause=ENOENT","unknown dependencies=unresolved name=vgshell-git"],[],["vgshell-git"],true,["Review","Use Claude Code","Yes"]]
 ]){
  if(caseName!==null&&caseName!==label)continue;
  const w=create(path.join(scratch,"publisher-"+label),{settings:{enabled:true,agent:"claude",command:""},choices});
  for(const [name,text] of Object.entries(files))fs.writeFileSync(path.join(w.root,name),text);
  if(tree==="no-recipes")w.tree=ownerTree("publisher-tree-"+label,[],{recipes:false});
  const requested=args.slice(4),r=tty(w,[...args.slice(0,4),"--config",w.config,...requested]),calls=w.calls();
  assert.equal(r.status,0,label+": "+r.stdout+r.stderr);
  assert.equal(calls.some(c=>c.kind==="offer"&&c.offered.includes("Review")),listed.length>0,label+": review offer");
  const agent=calls.find(c=>c.kind==="agent"),packages=agent?.packages||[];
  assert.equal(agent!==undefined,listed.length>0,label+": "+(listed.length?"the agent reviews":"no agent runs"));
  if(!listed.length){
   assert.ok(!calls.some(c=>c.kind==="offer"),label+": no review question");
  }
  for(const line of listed)assert.ok(packages.includes(line),label+": listed "+line+" in "+JSON.stringify(packages));
  for(const pattern of unlisted)assert.ok(!packages.some(line=>pattern.test(line)),label+": unlisted "+pattern+" in "+JSON.stringify(packages));
  assert.deepEqual(calls.filter(c=>c.kind==="query"&&c.args.includes("-G")).flatMap(c=>c.args.slice(c.args.indexOf("--")+1)),fetched,label+": fetched");
  const built=calls.filter(c=>c.kind==="mutation").flatMap(c=>c.args);
  assert.equal(built.includes(args[1]==="upgrade"?"-Sua":requested.at(-1)),installs,label+": "+(installs?"installs":"nothing installs")+" "+JSON.stringify(calls));
  console.log("package-publisher-proof: "+JSON.stringify({label,packages}));
 }
 // Each rule above and the saved choice fails its row when its code is
 // undone: the exemption, resolved VGS dependencies, the AUR fact kept
 // apart from a repository's name, and the saved Install without review.
 if(!only&&(select("control")||surface==="publisher-control")){
  const owner="bin/lib/pkg-review.js";
  control("publisher-exemption","publisher",[[owner,'published: publisher === "vgs",','published: false,']],/mixed: unlisted/);
  control("publisher-dependencies","publisher",[[owner,'if (viaAur && publisher !== "vgs") state.unknown.push','if (viaAur) state.unknown.push']],/vgs-only:/,"vgs-only");
  control("aur-only-scope","publisher",[[owner,'if (!viaAur) continue;','if (["core", "extra", "multilib"].includes(origin)) continue;']],/mixed: unlisted/,"mixed");
  control("saved-decline","choices",[[owner,"if (!judge.initialChoice(settings, foundAgents(settings)).ask) {","if (false) {"]],/saved-off:/);
 }
 // Resolver answers are canned by full entry, independently of VGS's
 // origin index. Paired order worlds keep that index identical.
 const dependencyCases=[
  {label:"version",entry:"hyprland>=0.57.0",satisfiers:{"hyprland>=0.57.0":"custom hyprland",hyprland:"core hyprland"},resolved:{target:"hyprland",origin:"custom"}},
  {label:"provider",entry:"virtual-engine>=2",satisfiers:{"virtual-engine>=2":"custom concrete-engine"},resolved:{target:"concrete-engine",origin:"custom"}},
  {label:"custom-first",entry:"cmake",satisfiers:{cmake:"custom cmake"},resolved:{target:"cmake",origin:"custom"},repos:["custom","core"]},
  {label:"official-first",entry:"cmake",satisfiers:{cmake:"core cmake"},resolved:{target:"cmake",origin:"core"},repos:["core","custom"]},
  {label:"aur-version",entry:"cpptrace>=2",order:{"cpptrace>=2":"AUR TARGET cpptrace cpptrace"},listed:"aur cpptrace ? ?"},
  {label:"aur-provider",entry:"virtual-engine>=2",order:{"virtual-engine>=2":"AUR TARGET engine engine-git"},failed:true},
  {label:"aur-missing",entry:"unavailable>=2",failed:true},
  {label:"aur-ambiguous",entry:"cpptrace",order:{cpptrace:"AUR TARGET cpptrace cpptrace\nAUR TARGET other other"},failed:true},
  {label:"pacman-malformed",entry:"cmake",satisfiers:{cmake:"core cmake\ncustom cmake"},failed:true},
  {label:"pacman-empty",entry:"cmake",satisfiers:{cmake:""},failed:true},
  {label:"pacman-failed",entry:"cmake",satisfiers:{cmake:{error:"error: failed to prepare transaction (invalid or corrupted database)\n"}},failed:true},
  {label:"metadata-missing",entry:"cmake",info:{"Check Deps":null},failed:true},
  {label:"wrapped",entry:"cmake\n                cpptrace>=2",missing:["cmake","cpptrace>=2"],satisfiers:{cmake:"core cmake"},order:{"cpptrace>=2":"AUR TARGET cpptrace cpptrace"},listed:"aur cpptrace ? ?"},
  {label:"satisfied",entry:"cmake>=2",missing:[]},
  {label:"shared-root-skip",entry:"vgshell-quickshell>=2",roots:["vgshell-git","vgshell"],missing:["vgshell-quickshell>=2","cpptrace"],order:{"vgshell-quickshell>=2":"AUR TARGET vgshell-quickshell vgshell-quickshell",cpptrace:"AUR TARGET cpptrace cpptrace"},extraInfo:{"vgshell-quickshell":{"Make Deps":"cpptrace"}},listed:"aur cpptrace ? ?",flag:"cpptrace"},
  {label:"prototype-root-skip",entry:"__proto__",order:{["__proto__"]:"AUR TARGET __proto__ __proto__"},listed:"aur __proto__ ? ?",flag:"__proto__"},
  {label:"cycle",entry:"vgshell-quickshell",missing:["vgshell-quickshell","vgshell-git"],order:{"vgshell-quickshell":"AUR TARGET vgshell-quickshell vgshell-quickshell","vgshell-git":"AUR TARGET vgshell-git vgshell-git"},extraInfo:{"vgshell-quickshell":{"Depends On":"vgshell-git"}}}
 ];
 if(!only&&select("dependencies"))for(const row of dependencyCases){
  if(caseName!==null&&caseName!==row.label)continue;
  const choices=row.failed?["Review","Use Claude Code","Stop"]:row.flag?["Review","Use Claude Code","Skip"]:["Review","Use Claude Code"];
  const w=create(path.join(scratch,"dependency-"+row.label),{choices});
  const roots=row.roots||["vgshell-git"],model={missing:row.missing||[row.entry],satisfiers:row.satisfiers||{},order:row.order||{},flag:row.flag,info:{...Object.fromEntries(roots.map(root=>[root,{"Depends On":row.entry,...row.info}])),...row.extraInfo}};
  fs.writeFileSync(path.join(w.root,"dependency-world.json"),JSON.stringify(model));
  fs.writeFileSync(path.join(w.root,"sync-extra"),"core hyprland 0.56.0\ncustom hyprland 0.57.0\ncore cmake 2\ncustom cmake 2");
  if(row.repos)fs.writeFileSync(w.include,row.repos.map(repo=>"["+repo+"]\nServer=https://packages.example.org").join("\n")+"\n");
  const r=tty(w,["run","reinstall","--manager","aur","--config",w.config,"foreign",...roots]),calls=w.calls(),agent=calls.find(c=>c.kind==="agent"),packages=agent?.packages||[];
  assert.equal(r.status,0,row.label+": "+r.stdout+r.stderr);
  if(row.listed)assert.ok(packages.includes(row.listed),row.label+": listed "+JSON.stringify(packages));
  if(row.label==="satisfied")assert.ok(!calls.some(call=>call.args.includes("-Sddp")||call.args.includes("-Po")),"satisfied: no missing dependency to resolve");
  assert.ok(!packages.some(line=>/^(repo|server|siglevel) /.test(line)),row.label+": no repository review");
  if(row.resolved){
   const binding=gathered(w,["foreign",...roots]).steps[0].binding;
   const resolved=binding.origins.find(origin=>origin.entry===row.entry&&origin.neededBy===roots[0]);
   assert.deepEqual({target:resolved?.target,origin:resolved?.origin},row.resolved,row.label+": resolved dependency binding");
  }
  const unavailable=calls.filter(c=>c.kind==="offer"&&c.offered.includes("Yes"));
  assert.equal(unavailable.length,row.failed?1:0,row.label+": unavailable");
  if(row.failed){assert.equal(unavailable[0].selected,"No",row.label);assert.ok(!calls.some(c=>c.kind==="mutation"||c.kind==="credential"),row.label);}
  else assert.ok(calls.some(c=>c.kind==="mutation"),row.label+": installs");
  if(row.flag)for(const root of roots)assert.ok(!calls.filter(c=>c.kind==="mutation").some(c=>c.args.includes(root)),row.label+": skips root "+root);
  for(const call of calls.filter(c=>c.args.includes("-Sddp")||c.args.includes("-Po"))){
   assert.deepEqual(call.args.slice(0,2),["--config",w.config],row.label+": effective config");
   assert.ok(model.missing.includes(call.args.at(-1)),row.label+": full entry");
   assert.equal(call.args.at(-2),"--",row.label+": argument boundary");
  }
  if(row.label==="pacman-failed")assert.ok(!calls.some(c=>c.args.includes("-Po")),"pacman-failed: no helper on database failure");
  console.log("package-dependency-proof: "+JSON.stringify({label:row.label,packages,unavailable:unavailable.length}));
 }
 if(!only&&select("dependency-authority"))for(const change of ["drop","new","origin","official"]){
  if(caseName!==null&&caseName!==change)continue;
  const w=create(path.join(scratch,"authority-engine-"+change),{choices:["Review","Use Claude Code"]});
  const model={pending:"vgshell-quickshell",missing:["vgshell-quickshell>=2","cpptrace"],order:{"vgshell-quickshell>=2":"AUR TARGET vgshell-quickshell vgshell-quickshell",cpptrace:"AUR TARGET cpptrace cpptrace"},satisfiers:{},info:{"vgshell-git":{"Depends On":"vgshell-quickshell>=2"},"vgshell-quickshell":{"Make Deps":"cpptrace"}}};
  fs.writeFileSync(path.join(w.root,"dependency-world.json"),JSON.stringify(model));
  const argv=[process.execPath,path.join(__dirname,"authority.js"),w.root,"engine-"+change,"aur",ownerOverride||w.owner];
  const r=cp.spawnSync("/usr/bin/script",["-qec",argv.map(q).join(" "),"/dev/null"],{env:{...w.env,SHELL:"/usr/bin/bash"},encoding:"utf8",timeout:30000});
  assert.equal(r.status,0,change+": engine authority "+r.stdout+r.stderr);
  const result=JSON.parse(fs.readFileSync(path.join(w.root,"authority-result.json"))),calls=w.calls(),mutations=calls.filter(c=>c.kind==="mutation");
  assert.ok(calls.find(c=>c.kind==="agent")?.packages.includes("aur cpptrace ? ?"),change+": cpptrace reviewed");
  assert.ok(!calls.some(c=>c.kind==="offer"&&c.offered.includes("Yes")),change+": no unavailable override");
  assert.ok(calls.some(c=>c.args.includes("-Po")&&c.args.at(-1)==="vgshell-quickshell>=2"),change+": full constrained helper resolution");
  assert.equal(result.before,1,change+": AUR upgrade consumed");
  assert.equal(result.code===0,change==="drop",change+": engine admission "+r.stdout);
  assert.equal(mutations.length,change==="drop"?2:1,change+": engine mutations");
  if(change!=="drop")assert.match(r.stdout,/review=authority-binding-changed field=origins/,change+": origins guard");
  console.log("package-engine-proof: "+JSON.stringify({change,result,mutations}));
 }
 if(!only&&(select("control")||surface==="dependency-control")){
  const owner="bin/lib/pkg-review.js";
  control("dependency-version","dependencies",[[owner,'"%r %n", "--", entry','"%r %n", "--", name']],/version: resolved dependency binding/,"version");
  control("dependency-provider","dependencies",[[owner,'target: row[2], origin: row[1]','target: name, origin: row[1]']],/provider: resolved dependency binding/,"provider");
  control("dependency-order","dependencies",[[owner,'target: row[2], origin: row[1]','target: row[2], origin: "core"']],/custom-first: resolved dependency binding/,"custom-first");
  control("dependency-helper","dependency-authority",[[owner,'"-Po", "--", entry','"-Si", "--", entry']],/drop: engine authority/,"drop");
  control("dependency-root-skip","dependencies",[[owner,'if (!result.skipped.includes(dependent)) result.skipped.push(dependent);','if (false) result.skipped.push(dependent);']],/shared-root-skip: skips root/,"shared-root-skip");
  control("dependency-prototype-skip","dependencies",[[owner,'dependents: Object.create(null)','dependents: {}']],/prototype-root-skip: skips root/,"prototype-root-skip");
  control("dependency-drop","dependency-authority",[[owner,'if (!dependencies(current.binding).every(row => reviewed.some(prior => same(row, prior)))) return field;','if (!same(dependencies(current.binding), reviewed)) return field;']],/drop: engine admission/,"drop");
  for(const change of ["new","origin"])control("dependency-"+change,"dependency-authority",[[owner,'if (!dependencies(current.binding).every(row => reviewed.some(prior => same(row, prior)))) return field;','if (false) return field;']],new RegExp(change+": engine admission"),change);
 }
 if(!only&&(select("control")||surface==="dependency-control"||surface==="dependency-official-control"))
  control("dependency-official","dependency-authority",[["bin/lib/pkg-review.js",'binding.origins.push({ target: target.target, origin,','if (target.neededBy !== undefined && !viaAur) continue;\n                binding.origins.push({ target: target.target, origin,']],/official: engine admission/,"official");


 // A review run through Customize, with one edit view opened and left, keeps
 // the caller's screen: no kind, the inline editor included, clears it.
 if(!only&&select("customize")){
  const w=create(path.join(scratch,"customize"),{choices:["Review","Customize","Before installing","Back","Cancel","Use Claude Code"]});
  const r=tty(w,["run","install","--manager","aur","--config",w.config,"foreign"]),calls=w.calls();
  assert.equal(r.status,0,r.stdout+r.stderr);
  assert.ok(calls.some(c=>c.kind==="offer"&&c.offered.includes("Before installing")),JSON.stringify(calls));
  assert.ok(calls.some(c=>c.kind==="agent")&&calls.some(c=>c.kind==="mutation"));
  assert.ok(!r.stdout.includes("\x1b[2J"),"package-customize=screen-cleared");
  console.log("package-customize-proof: "+JSON.stringify({status:r.status,offers:calls.filter(c=>c.kind==="offer").length}));
 }
 if(!only&&select("settings"))for(const [label,initial,choice,expected] of [
  ["automatic",true,"Automatic (review when an agent is available)",undefined],
  ["agent",false,"Review with an agent",true],
  ["without-review",true,"Install without review",false]]){
  const w=create(path.join(scratch,"settings-"+label),{settings:{enabled:initial,agent:"claude",command:""},choices:["Before installing",choice,"Save"]});
  const r=tty(w,["review-settings"]);
  assert.equal(r.status,0,r.stdout+r.stderr);
  const saved=JSON.parse(fs.readFileSync(path.join(w.root,"config/vgshell/shell.json"))).packages.review;
  assert.equal(Object.hasOwn(saved,"enabled"),expected!==undefined);
  assert.equal(saved.enabled,expected);
  assert.equal(saved.agent,"claude");assert.equal(saved.command,"");
  assert.ok(!w.calls().some(c=>["mutation","credential","agent"].includes(c.kind)));
  console.log("package-settings-choice-proof: "+JSON.stringify({choice,saved}));
 }
 if(!only&&select("authority"))for(const [manager,change] of [
  ...["pacman","aur"].flatMap(manager=>["none","consumed","manager","action","targets","config","include","config-path","ignore","pending","origin","binary","transaction","missing","unreadable","symlink","recipe","outer","outer-missing","config-link","config-link-changed"].map(change=>[manager,change])),
  ["aur","custom-origin-read-failed"]
 ]){
  const w=create(path.join(scratch,"authority-"+manager+"-"+change),{choices:change==="recipe"?["Review","Use Claude Code"]:change==="custom-origin-read-failed"?["Install without review","Yes"]:["Install without review"]});
  const fixture=path.join(__dirname,"authority.js");
  const command=[process.execPath,fixture,w.root,change,manager].map(s=>"'"+s.replaceAll("'","'\\''")+"'").join(" ");
  const r=cp.spawnSync("/usr/bin/script",["-qec",command,"/dev/null"],{env:{...w.env,SHELL:"/usr/bin/bash"},encoding:"utf8",timeout:30000});
  assert.equal(r.status,0,r.stdout+r.stderr);
  const result=JSON.parse(fs.readFileSync(path.join(w.root,"authority-result.json"))),calls=w.calls();
  const allowed=change==="none"||change==="config-link"||(change==="outer"&&manager==="pacman")||(manager==="aur"&&["config","include","config-link-changed","binary"].includes(change));
  assert.equal(result.code===0,allowed,r.stdout);
  if(change==="custom-origin-read-failed")assert.match(r.stdout,/review=authority-binding-(?:unreadable|changed)/);
  assert.equal(calls.filter(c=>c.kind==="mutation").length-result.before,allowed?(change==="none"&&manager==="pacman"?3:1):0,change+":"+JSON.stringify(calls));
  assert.equal(calls.filter(c=>c.kind==="offer"&&c.offered.includes("Review")).length,1);
  if(change==="outer"&&manager==="pacman")assert.ok(!calls.some(c=>c.kind==="credential"&&c.args[0]==="-k"));
  console.log("package-authority-proof: "+JSON.stringify({manager,change,result,mutations:calls.filter(c=>c.kind==="mutation")}));
 }
 // Updates consumes the system and then AUR step of the same receipt. Only
 // the reviewed content may invalidate the AUR step after the system step.
 const aurAuthority=[
  ["include",true,null],["binary",true,null],["config",true,null],["candidate",true,null],
  ["recognized-binary",true,null],["recognized-include",true,null],
  ["pending",false,"pending"],["pending-old",false,"pending"],["pending-name",false,"pending"],
  ["origin",false,"origins"],["aur-recipe",false,"recipes"],["custom-binary",false,null],["custom-include",false,null]
 ];
 if(!only&&select("aur-authority"))for(const [change,allowed,field] of aurAuthority){
  if(caseName!==null&&caseName!==change)continue;
  const w=create(path.join(scratch,"aur-authority-"+change),{choices:change.startsWith("custom-")?["Install without review","Yes"]:["Review","Use Claude Code"]});
  const argv=[process.execPath,path.join(__dirname,"authority.js"),w.root,"after-system-"+change,"aur",ownerOverride||w.owner];
  const r=cp.spawnSync("/usr/bin/script",["-qec",argv.map(q).join(" "),"/dev/null"],{env:{...w.env,SHELL:"/usr/bin/bash"},encoding:"utf8",timeout:30000});
  assert.equal(r.status,0,change+": "+r.stdout+r.stderr);
  const result=JSON.parse(fs.readFileSync(path.join(w.root,"authority-result.json"))),calls=w.calls(),mutations=calls.filter(c=>c.kind==="mutation");
  assert.equal(result.before,1,change+": system step consumed");
  assert.equal(result.code===0,allowed,change+": AUR admission "+r.stdout);
  assert.equal(mutations.length,allowed?2:1,change+": mutation count");
  if(field!==null)assert.match(r.stdout,new RegExp("review=authority-binding-changed field="+field+"\\b"),change+": binding field");
  console.log("package-aur-authority-proof: "+JSON.stringify({change,allowed,field,system:mutations[0].name,aur:mutations[1]?.name||null}));
 }
 // A valid AUR verdict's dependency limit is displayed to the terminal
 // reader but grants no failed-read consent. Every failed read still asks.
 const reviewResults=[
  ["clean",null,true,null],["missing","agent-no-verdict",false,"verdict is missing"],
  ["unsafe","agent-unsafe",false,"verdict is unsafe"],["unreadable","agent-unreadable",false,"verdict is unreadable"],
  ["malformed","agent-malformed",false,"verdict is malformed"],["failed","agent-failed",false,"review agent failed"],
  ["fetch","fetch-failed",false,"could not be downloaded for foreign"],["read","info-failed",false,"paru package query failed"],
  ["unavailable",null,false,"No review agent is available"]
 ];
 if(!only&&select("review-result"))for(const [label,marker,installs,cause] of reviewResults){
  if(caseName!==null&&caseName!==label)continue;
  const w=create(path.join(scratch,"review-result-"+label),{agents:label!=="unavailable",choices:["unavailable","read"].includes(label)?["Review","Stop"]:["Review","Use Claude Code","Stop"]});
  if(marker)fs.writeFileSync(path.join(w.root,marker),"");
  const r=tty(w,["run","upgrade","--manager","aur","--config",w.config]),calls=w.calls();
  assert.equal(r.status,0,label+": "+r.stdout+r.stderr);
  const unavailable=calls.filter(c=>c.kind==="offer"&&c.offered.includes("Yes"));
  assert.equal(unavailable.length,installs?0:1,label+": unavailable question");
  if(!installs){assert.equal(unavailable[0].selected,"No",label);assert.ok(r.stdout.includes(cause),label+": named cause "+r.stdout);}
  else assert.match(r.stdout,/AUR builds may add dependencies that cannot be reviewed before the build\./,"clean: dependency limit");
  assert.doesNotMatch(r.stdout,/(?:origin|recipe|verdict|agent|fetch|query)=[a-z-]+/,label+": plain failure");
  assert.equal(calls.some(c=>c.kind==="mutation"),installs,label+": mutation");
  if(!installs)assert.ok(!calls.some(c=>c.kind==="credential"),label);
  console.log("package-review-result-proof: "+JSON.stringify({label,questions:unavailable.length,installs,cause}));
 }
 if(!only&&(select("control")||surface==="review-result-control")){
  const owner="bin/lib/pkg-review.js";
  control("review-clean-limit","review-result",[[owner,"verdict === null || !verdict.ok || failures.length","verdict === null || !verdict.ok || state.unknown.length"]],/clean: /,"clean");
  for(const [label] of reviewResults.filter(row=>row[3]!==null))
   control("review-failure-"+label,"review-result",[[owner,"verdict === null || !verdict.ok || failures.length","false"]],new RegExp(label+": unavailable question"),label);
 }
 if(!only&&(select("control")||surface==="aur-authority-control")){
  const owner="bin/lib/pkg-review.js";
  for(const [change,allowed,field] of aurAuthority){
   const edits=allowed?[[owner,'bindingChange(step, current.steps[0], group.manager === "aur")','bindingChange(step, current.steps[0], false)']]
    :field==="recipes"?[[owner,'record.state.recipes.length && !same(recipesIdentity','false && record.state.recipes.length && !same(recipesIdentity']]
    :field!==null?[[owner,'if (!same(project(current.binding), project(step.binding))) return field;',`if (field !== ${JSON.stringify(field)} && !same(project(current.binding), project(step.binding))) return field;`]]
    :[[owner,'const field = bindingChange(step, current.steps[0]);','const field = (bindingChange(step, current.steps[0]), null);'],
     change==="custom-binary"?[owner,'const binary = customArgv[0];\n            if (!record.state.customBinding || !same(identity(fs.realpathSync(commandFile(binary) || binary)), record.state.customBinding)) refuse("review=authority-custom-changed");','const binary = customArgv[0];\n            if (false) refuse("review=authority-custom-changed");']
      :[owner,'if (record.state.customConfig !== null && !same(configIdentity(record.request.config), record.state.customConfig)) refuse("review=authority-config-changed");','if (false) refuse("review=authority-config-changed");']];
   control("aur-binding-"+change,"aur-authority",edits,new RegExp(change+": (?:AUR admission|binding field)"),change);
  }
 }
 if(!only&&select("availability")){
  const w=create(path.join(scratch,"configured-unavailable"),{agents:false,settings:{agent:"codex",command:""},choices:["Review","Stop"]});
  const r=tty(w,["run","install","--manager","aur","--config",w.config,"foreign"]);assert.equal(r.status,0,r.stdout);
  assert.equal(w.calls().find(c=>c.kind==="offer").selectedIndex,0);
  assert.equal(w.calls().filter(c=>c.kind==="offer").at(-1).selectedIndex,0);
  assert.ok(!w.calls().some(c=>["agent","credential","mutation"].includes(c.kind)));
  const f=create(path.join(scratch,"probe-failed"),{agents:false,settings:{agent:"codex",command:""},choices:[]});
  fs.symlinkSync("codex",path.join(f.root,"tools/codex"));
  const failed=tty(f,["run","install","--manager","aur","--config",f.config,"foreign"]);assert.equal(failed.status,1,failed.stdout);
  assert.ok(!f.calls().some(c=>["offer","agent","credential","mutation"].includes(c.kind)));
  assert.equal(JSON.parse(fs.readFileSync(path.join(f.root,"config/vgshell/shell.json"))).packages.review.agent,"codex");
 }
 if(!only&&select("evidence"))for(const [marker,target,choices,mutation,agent] of [
  ["install-risk","foreign",["Review","Use Claude Code","Skip"],false,true],
  ["install-link","foreign",["Review","Use Claude Code","Yes","Skip"],false,false],
  ["srcinfo-link","foreign",["Review","Use Claude Code","Yes","Skip"],false,false],
  ["agent-no-verdict","foreign",["Review","Use Claude Code","Stop"],false,true],
  ["agent-failed","foreign",["Review","Use Claude Code","Stop"],false,true],
  ["agent-malformed","foreign",["Review","Use Claude Code","Stop"],false,true],
  ["agent-dependency","foreign",["Review","Use Claude Code","Stop"],false,true],
  ["fetch-failed","foreign",["Review","Use Claude Code","Stop"],false,false],
  // With no package listed, Review asks no agent: the unavailable question follows.
  ["query-failed","foreign",["Review","Stop"],false,false],
  ["provider-ambiguous","foreign",["Review","Stop"],false,false],
  ["agent-concern","foreign",["Review","Use Claude Code","Skip"],false,true]
 ]){
  const w=create(path.join(scratch,"evidence-"+marker),{choices});fs.writeFileSync(path.join(w.root,marker),"");
  const r=tty(w,["run","install","--manager","aur","--config",w.config,target]),calls=w.calls();
  assert.equal(r.status,0,r.stdout+r.stderr);assert.equal(calls.some(c=>c.kind==="mutation"),mutation);assert.equal(calls.some(c=>c.kind==="agent"),agent);
  assert.ok(!calls.some(c=>c.kind==="credential"));
  if(marker==="query-failed")assert.ok(r.stdout.includes(target),"the requested package remains visible when provenance cannot be read");
  if(marker==="install-link"||marker==="srcinfo-link"){
   assert.ok(r.stdout.includes(marker==="install-link"?"foreign/package.install":"foreign/.SRCINFO"),marker+": named recipe");
   assert.ok(r.stdout.includes("symbolic link"),marker+": named file kind");
   assert.doesNotMatch(r.stdout,/(?:origin|recipe)=[a-z-]+/,marker+": plain failure");
  }
  for(const answer of calls.filter(c=>c.kind==="offer"&&c.offered.includes("Yes")))assert.equal(answer.selectedIndex,0);
  console.log("package-evidence-proof: "+JSON.stringify({marker,calls}));
 }
 if(!only&&select("evidence")){
  const w=create(path.join(scratch,"named-skip"),{choices:["Review","Use Claude Code","Skip"]});fs.writeFileSync(path.join(w.root,"agent-concern"),"");
  const r=tty(w,["run","update","--manager","aur","--config",w.config,"foreign","--install","second"]);assert.equal(r.status,0,r.stdout);
  assert.deepEqual(w.calls().find(c=>c.kind==="mutation").args,["--config",w.config,"-S","--needed","--","second"]);
  const u=create(path.join(scratch,"upgrade-skip"),{choices:["Review","Use Claude Code","Skip"]});fs.writeFileSync(path.join(u.root,"agent-concern"),"");
  const upgrade=tty(u,["run","upgrade","--manager","aur","--config",u.config,"--ignore","input-ignore"]);assert.equal(upgrade.status,0,upgrade.stdout);
  assert.deepEqual(u.calls().find(c=>c.kind==="mutation").args,["--config",u.config,"-Sua","--ignore","input-ignore","--ignore","foreign"]);
 }
 if(!only&&select("updates"))for(const kind of ["existing","helper","recognized","recognized-skip","custom","custom-stop","one-review"]){
  if(caseName!==null&&caseName!==kind)continue;
  const choices=kind==="one-review"?["Review","Use Claude Code"]:kind==="recognized-skip"?["Review","Use Claude Code","Skip"]:kind==="helper"?["Install without review","Install without review"]:kind.startsWith("custom")?["Install without review",kind==="custom-stop"?"No":"Yes"]:["Install without review"];
  const w=create(path.join(scratch,"updates-"+kind),{choices,helper:kind!=="helper"}),fixture=path.join(__dirname,"pipeline.js");
  if(kind==="helper"){
   // The helper must finish before reviewing the VGS rebuild's AUR
   // dependency; repository prerequisites need no review offer.
   fs.writeFileSync(path.join(w.root,"dependency-world.json"),JSON.stringify({info:{"vgshell-git":{"Make Deps":"foreign"}},missing:["foreign"],order:{foreign:"AUR TARGET foreign foreign"}}));
  }
  if(kind==="one-review"){
   fs.writeFileSync(path.join(w.root,"config-corresponds"),"");
   fs.writeFileSync(path.join(w.root,"dependency-world.json"),JSON.stringify({pending:["foreign","second"],prompts:true,buildOrder:{upgrade:"REPO MAKE core cmake\nAUR TARGET foreign foreign\nAUR TARGET second second","vgshell-git":"AUR TARGET vgshell-git vgshell-git"}}));
  }
  if(kind==="recognized-skip")fs.writeFileSync(path.join(w.root,"agent-concern"),"");
  const command=[process.execPath,fixture,w.root,kind].map(s=>"'"+s.replaceAll("'","'\\''")+"'").join(" ");
  const r=cp.spawnSync("/usr/bin/script",["-qec",command,"/dev/null"],{env:{...w.env,SHELL:"/usr/bin/bash"},encoding:"utf8",timeout:60000});
  assert.equal(r.status,0,r.stdout+r.stderr);
  const calls=w.calls(),offers=calls.map((c,i)=>[c,i]).filter(([c])=>c.kind==="offer"&&c.offered.includes("Review"));
  if(kind==="custom-stop")assert.ok(!calls.some(c=>["credential","mutation","snapshot"].includes(c.kind)));
  else{
   const offer=offers.at(-1)[1],snapshot=calls.findIndex(c=>c.kind==="snapshot");
   assert.ok(snapshot>offer);assert.ok(calls.findIndex((c,i)=>i>offer&&c.kind==="credential")>offer);
   assert.equal(offers.length,kind==="helper"?2:1);
   assert.ok(!calls.slice(snapshot).some(c=>c.kind==="offer"));
   const upgrades=calls.filter(c=>c.kind==="package-entry"&&c.args[1]==="run"&&["upgrade","reinstall"].includes(c.args[2]));
   assert.ok(upgrades.every(c=>c.args.includes("--review-receipt")));
   assert.equal(upgrades.length,kind==="helper"||kind==="custom"?2:3);
   assert.equal(calls.filter(c=>c.kind==="mutation").length,kind==="helper"?4:3);
   if(kind==="one-review"){
    assert.equal(calls.filter(c=>c.kind==="helper-prompt").length,0,"Updates has no helper review/pager/diff prompt");
    assert.deepEqual(calls.filter(c=>c.kind==="pacman-confirmation").map(c=>c.transaction),["system-upgrade","repository-make-dependencies","built-packages","built-packages"],"Updates keeps each pacman transaction confirmation");
   }
   if(kind==="helper")assert.ok(calls.findIndex(c=>c.kind==="mutation"&&c.name==="makepkg")<offer);
   if(kind==="custom")assert.ok(calls.some(c=>c.kind==="mutation"&&c.args.includes("--devel")));
  }
  assert.ok(!fs.readdirSync(path.join(w.root,"run/vgshell/package-review")).some(n=>/^(transaction|review|bootstrap)-/.test(n)));
  console.log("package-route-proof: "+JSON.stringify({route:"updates-"+kind,calls}));
 }
 if(!only&&select("bootstrap"))for(const scenario of ["review","decline","cancel"]){
  const choices=scenario==="review"?["Review","Use Claude Code"]:scenario==="cancel"?["cancel"]:["Install without review"];
  const w=create(path.join(scratch,"bootstrap-"+scenario),{choices,helper:false});
  const r=tty(w,["ensure-helper"]),calls=w.calls();
  assert.equal(r.status,scenario==="cancel"?130:0,r.stdout+r.stderr);
  const firstCredential=calls.findIndex(c=>c.kind==="credential"),build=calls.findIndex(c=>c.kind==="mutation"&&c.name==="makepkg");
  if(scenario==="cancel")assert.ok(firstCredential<0&&build<0);
  else{
   assert.ok(build>=0);assert.equal(calls.filter(c=>c.kind==="offer"&&c.offered.includes("Review")).length,1);
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
  const w=create(path.join(scratch,"bootstrap-retry-"+label),{choices:["Install without review",choice],helper:false});
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
   const owner=[process.execPath,ownerOverride||w.owner,...args],command=wrap?["/usr/bin/bash","-c",owner.map(q).join(" ")+"; exit $?"]:owner;
   const argv=["/usr/bin/bash",path.resolve(__dirname,"../../../bin/vgshell-tui"),"present","--presentation","plain","--record",key,"--run",run,"--record-dir",records,"--app-id","vgs-test","--window-title","Test","--",...command];
   const r=cp.spawnSync("/usr/bin/script",["-qec",argv.map(q).join(" "),"/dev/null"],{env:{...w.env,SHELL:"/usr/bin/bash"},encoding:"utf8",timeout:60000});
   const ended=path.join(records,key.replace("/","@")+"@"+run+".ended.json");
   return {...r,record:fs.existsSync(ended)?JSON.parse(fs.readFileSync(ended,"utf8")):null};
  };
  const install=["run","install","--manager","aur","--config",w.config,TARGET],INSTALL="core/requirements-install";
  const checkFailed=(run,state,status=1)=>({kind:"package-check-failed",manager:"aur",helper:"paru",package:TARGET,status,retry:state===null?null:{originRun:run,state}});
  const stop=(run,key=INSTALL,target=TARGET,choices=["Install without review","Stop"])=>{choose(choices);scenario(w,{...CHECK,base:target},null);return present(key,run,install.slice(0,-1).concat(target));};
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
  // A package VGS publishes, which no review lists, holds its recipe too.
  r=stop("run26",INSTALL,"vgshell-git",["Stop"]);assert.ok(heldRuns().includes("core@requirements-install@run26.json"),"vgs-recipe: held "+r.stdout);
  r=marked("recipe-changed",()=>retried("run27","run26",PASS));
  assert.deepEqual(r.built,[],"vgs-recipe: a changed recipe builds nothing");assert.match(r.stdout,/retry=changed run=run26/);
  assert.ok(!fs.readdirSync(records).some(n=>n.includes(".outcome.")),"each presenter removes its channel");
  console.log("package-retry-held-proof: ok");
 }
 // The held recipe of a VGS package fails its row when gather drops the
 // package before the retry's binding reads it.
 if(!only&&(select("control")||surface==="retry-held-control"))
  control("retry-published-recipe","retry-held",[["bin/lib/pkg-review.js","const pkg = { name, origin,",'if (publisher === "vgs") continue;\n                const pkg = { name, origin,']],/vgs-recipe: a changed recipe builds nothing/);
 for(const entry of fs.readdirSync(scratch)){const dir=path.join(scratch,entry,"run/vgshell/package-review");if(fs.existsSync(dir)&&!entry.startsWith("authority-")&&!entry.startsWith("aur-authority-"))assert.ok(!fs.readdirSync(dir).some(n=>/^(review|bootstrap|transaction|build|helper|recipe)-/.test(n)),entry);}
 if(!only&&(select("control")||surface==="origin-control")){
  const control=cp.spawnSync(process.execPath,[__filename,"--surface","origin","--owner",ownerTree("origin-mutant",[["bin/lib/pkg-review.js",'target.origin === "aur" && matches.length > 0','target.origin === "never-aur" && matches.length > 0']])],{env:{PATH:"/usr/bin:/bin",TMPDIR:scratch},encoding:"utf8",timeout:60000});
  assert.equal(control.status,1,control.stdout+control.stderr);
  assert.match(control.stderr,/ERR_ASSERTION/,control.stdout+control.stderr);
  const attempted=control.stdout.split("\n").filter(line=>line.startsWith("package-origin-attempt-proof: ")).map(line=>JSON.parse(line.slice("package-origin-attempt-proof: ".length)));
  const mutant=attempted.find(row=>row.manager==="aur");
  assert.deepEqual(mutant,{manager:"aur",status:0,offered:false,mutated:true});
  console.log("package-origin-control-proof: "+JSON.stringify({status:control.status,mutant}));
 }
 if(!only&&(select("control")||surface==="customize-control"))
  control("customize-inline","customize",[["bin/lib/pkg-review.sh",'vgs_pkg_review_settings "$1" inline ;;','vgs_pkg_review_settings "$1" ;;']],/package-customize=screen-cleared/);
 console.log("test-package-review-runtime: ok");
}finally{fs.rmSync(scratch,{recursive:true,force:true});}
