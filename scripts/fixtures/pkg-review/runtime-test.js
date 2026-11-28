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
 // An Update runs the check first, then review-run. The check, as the
 // shell's start does, makes <runtime>/vgshell with the caller's umask; under
 // umask 002, as Fedora gives a user with a private group, it is
 // group-writable. An older check also left updates/ under it. The owner
 // repairs both in place and keeps their runs. test-updates-check.sh holds
 // the check's own side: it makes no updates/ and keeps its lock beside it.
 function updatesRoot(folder,owner=path.resolve(__dirname,"../../../bin/vgshell-pkg")){
  const world=create(path.join(scratch,folder)),bin=path.join(world.root,"check-bin");
  fs.mkdirSync(path.join(bin,"lib"),{recursive:true});
  for(const file of ["qml-library.js","owned-group.sh","owned-group.py"])fs.symlinkSync(path.resolve(__dirname,"../../../bin/lib",file),path.join(bin,"lib",file));
  fs.mkdirSync(path.join(world.root,"shell/Commons"),{recursive:true});
  fs.symlinkSync(path.resolve(__dirname,"../../../shell/Commons/PageReference.js"),path.join(world.root,"shell/Commons/PageReference.js"));
  const probe=path.join(bin,"vgshell");
  fs.writeFileSync(probe,'#!/usr/bin/bash\ncase "$1 $2" in\n"self status") printf \'{"version":"0.1.0","method":"checkout","package":null,"current":"0.1.0","latest":"0.1.0","behind":false,"step":"none","reason":null,"error":null}\\n\' ;;\n*) printf \'[]\\n\' ;;\nesac\n',{mode:0o755});
  const parent=path.join(world.env.XDG_RUNTIME_DIR,"vgshell"),updates=path.join(parent,"updates");
  const result=cp.spawnSync("/usr/bin/bash",["-c",'umask 002 && exec /usr/bin/bash "$0" "$@"',path.resolve(__dirname,"../../../shell/plugins/vgs.updates/bin/check"),"--vgshell",probe],{env:{...world.env,PATH:world.env.PATH+":/usr/bin:/bin"},encoding:"utf8",timeout:30000});
  assert.equal(result.status,0,"updates check: "+result.stderr);
  assert.equal(fs.statSync(parent).mode&0o777,0o775,"updates check: umask 002 leaves the runtime folder group-writable");
  let run=cp.spawnSync(process.execPath,[owner,"review-run"],{env:world.env,encoding:"utf8",timeout:30000});
  assert.equal(run.status,0,"updates review: admitted after check: "+run.stderr);
  assert.equal(fs.statSync(parent).mode&0o777,0o755,"updates review: repairs the runtime folder in place");
  fs.rmSync(updates,{recursive:true});
  fs.mkdirSync(updates,{mode:0o755});
  fs.chmodSync(updates,0o755);
  fs.writeFileSync(path.join(updates,"retained"),"prior run");
  for(const mode of [0o755,0o555,0o000]){
   fs.chmodSync(updates,mode);
   run=cp.spawnSync(process.execPath,[owner,"review-run"],{env:world.env,encoding:"utf8",timeout:30000});
   assert.equal(run.status,0,"updates review: admitted over an older updates folder: "+run.stderr);
   assert.equal(fs.statSync(updates).mode&0o777,0o700,"updates review: repairs owned directory in place");
   assert.equal(fs.readFileSync(path.join(updates,"retained"),"utf8"),"prior run","updates review: preserves prior runs");
   assert.equal(path.dirname(run.stdout.trim()),updates,"updates review: uses the owned root");
  }
 }
 updatesRoot("updates-root");
 // Ownership metadata is injected only in this child. The caller has no
 // permission to chown a real directory to another user's identity. A link,
 // to updates/ or in place of <runtime>/vgshell, is refused before any
 // chmod could reach the folder it names. The target is 0775, a mode either
 // repair would change through the link.
 function unsafeUpdatesRoot(kind,folder="updates-refuse-"+kind,owner=path.resolve(__dirname,"../../../bin/vgshell-pkg")){
  const world=create(path.join(scratch,folder)),parent=path.join(world.env.XDG_RUNTIME_DIR,"vgshell"),updates=path.join(parent,"updates");
  const target=path.join(world.root,"link-target");
  fs.mkdirSync(target);fs.chmodSync(target,0o775);
  if(kind==="parent-link")fs.symlinkSync(target,parent);
  else fs.mkdirSync(parent,{mode:0o700});
  if(kind==="link")fs.symlinkSync(target,updates);
  else if(kind==="file")fs.writeFileSync(updates,"");
  else if(kind!=="parent-link")fs.mkdirSync(updates,{mode:0o700});
  const code='const fs=require("node:fs"),[owner,dir,kind]=process.argv.slice(1);if(kind==="foreign"){const stat=fs.lstatSync;fs.lstatSync=function(file,...args){const value=stat.call(this,file,...args);if(file===dir)value.uid=process.getuid()+1;return value;};}require(owner).createRun();';
  const result=cp.spawnSync(process.execPath,["-e",code,path.resolve(path.dirname(owner),"lib/pkg-review.js"),updates,kind],{env:world.env,encoding:"utf8",timeout:30000});
  assert.notEqual(result.status,0,kind+": unsafe updates root refused");
  assert.match(result.stderr,/review=directory-unsafe/,kind+": directory refusal");
  assert.equal(fs.statSync(target).mode&0o777,0o775,kind+": the linked folder keeps its mode");
 }
 for(const kind of ["link","parent-link","foreign","file"])unsafeUpdatesRoot(kind);
 // The TUI exports the pid of its active password session. Use this test's
 // own live pid for the refusal and pin the run directory's time so even
 // creating and removing a transient snapshot is observable.
 {
  const world=create(path.join(scratch,"review-refused"),{choices:[]});
  const allocation=cp.spawnSync(process.execPath,[world.owner,"review-run"],{env:world.env,encoding:"utf8",timeout:30000});
  assert.equal(allocation.status,0,"review refusal allocates the run: "+allocation.stderr);
  const run=allocation.stdout.trim(),context=path.join(run,"context.json"),view=path.join(world.protectedRoot,"view");
  fs.mkdirSync(view,{mode:0o700});
  fs.writeFileSync(context,'{"attempt":0}\n',{mode:0o600,flag:"wx"});
  fs.utimesSync(run,1,1);
  const priorMtime=fs.statSync(run).mtimeMs;
  const result=tty(world,["review-files","--run",run,"--config",world.config,"--",view],{VGS_TUI_SUDO_SESSION:String(process.pid)});
  assert.equal(result.status,1,"review refusal: exits with the refusal status");
  // The PTY can write CRLF. Keep the line ending in the comparison so an
  // extra blank line also fails the assertion.
  assert.equal(result.stdout.replace(/\r\n/g,"\n"),"vgshell: refused: review=active-password-session\n","review refusal: emits only its key");
  assert.deepEqual(fs.readdirSync(run),["context.json"],"review refusal: leaves no outcome or snapshot");
  assert.equal(fs.readFileSync(context,"utf8"),'{"attempt":0}\n',"review refusal: keeps the run context");
  assert.equal(fs.statSync(run).mtimeMs,priorMtime,"review refusal: creates no transient run entry");
  assert.deepEqual(world.calls(),[],"review refusal: reaches no stand-in");
 }
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
 // A saved decline and VGS-only full build order bypass the hook, on the
 // upgrade route and on the VGS rebuild route pipeline.sh runs. A newly
 // added third-party dependency restores it even for a VGS target. A hook
 // that asks anyway gets "Install without review", so its question reaches
 // the counts. OWNER, when given, is a control's copy of bin/vgshell-pkg.
 const upgrade=["run","upgrade","--manager","aur"];
 const publisherReinstall=["publisher-reinstall",{agent:"claude",command:""},"AUR TARGET vgshell-git vgshell-git",0,["run","reinstall","--manager","aur","vgshell-git"]];
 function bypass([name,settings,order,expected,args],folder=name,owner=undefined){
  const world=create(path.join(scratch,folder),{settings,choices:expected?["Review"]:["Install without review"]});
  if(owner!==undefined)world.owner=owner;
  write(world,"dependency-world.json",{pending:["vgshell-git"],...(order?{buildOrder:{upgrade:order,"vgshell-git":order}}:{})});
  write(world,"hook-world.json",{packages:[{base:"vgshell-git"},{base:"dependency"}]});
  const result=tty(world,args);
  assert.equal(result.status,0,name+": "+result.stdout+result.stderr);
  assert.equal(agents(world).length,expected,name+": agent count");
  assert.equal(offers(world).length,expected?1:0,name+": review questions");
  assert.equal(builds(world)[0].args.includes("--skipreview"),expected===0,name+": helper review choice");
 }
 for(const row of [
  ["saved",{enabled:false,agent:"claude",command:""},null,0,upgrade],
  ["publisher",{agent:"claude",command:""},"AUR TARGET vgshell-git vgshell-git",0,upgrade],
  publisherReinstall,
  ["publisher-dependency",{agent:"claude",command:""},"AUR TARGET vgshell-git vgshell-git\nAUR DEP dependency dependency",1,upgrade]
 ])bypass(row);
 // paru --gendb follows a successful build; a built devel base it leaves
 // untracked, or an error it prints, is a result line, never a failed
 // install. OWNER, when given, is a control's copy of bin/vgshell-pkg.
 const develError=["devel-error",[],true];
 const develCurrent=["devel-paru-2.2.0",[],false,{url:"https://github.com/vanillagreencom/vgshell.git",branch:"main",commit:"a951440bc274aa8e3121cd95fdaf581071cca879"}];
 function devel([name,untracked,error,ref,expected=untracked.length],folder=name,owner=undefined){
  const world=create(path.join(scratch,folder),{settings:{agent:"claude",command:""},choices:[]}),order="AUR TARGET vgshell-git vgshell-git";
  if(owner!==undefined)world.owner=owner;
  write(world,"dependency-world.json",{pending:["vgshell-git"],buildOrder:{upgrade:order,"vgshell-git":order}});
  write(world,"devel-world.json",{untracked,error,ref});
  const result=tty(world,["run","upgrade","--manager","aur"]);
  assert.equal(result.status,0,name+": "+result.stdout+result.stderr);
  assert.equal(world.calls().filter(call=>call.kind==="devel-completion").length,1,name+": tracking repair after the build");
  assert.deepEqual(keyed(result,"package-result").filter(line=>line.includes("vgshell-git")).length,expected,name+": untracked devel base result");
  if(!error&&expected===0)assert.equal(keyed(result,"package-result").length,0,name+": tracked base prints no result line");
  if(error)assert.equal(keyed(result,"package-result").length,1,name+": the tracking error is one result line");
 }
 for(const row of [["devel-tracked",[],false],develCurrent,["devel-untracked",["vgshell-git"],false],
  ["devel-empty-url",[],false,{url:"",commit:"new-vgs-commit"},1],["devel-empty-commit",[],false,{url:"https://example.org/vgs.git",commit:""},1],
  ["devel-no-url",[],false,{commit:"new-vgs-commit"},1],["devel-no-commit",[],false,{url:"https://example.org/vgs.git"},1],develError])devel(row);
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
 // Agent failures choose the other installed agent first, and never offer
 // an agent this review already tried. Each failure is one sentence that
 // names the agent, its account and the next step; the agent's raw last
 // line is on its review-diagnostic line alone. Skipping the AUR skips the
 // step, status 0, as a Skip of every named package does. A missing agent
 // or account is never started, and a signal during the agent cancels the
 // step with no further question. OWNER, when given, is a control's copy
 // of bin/vgshell-pkg.
 const otherAgent=["other-agent","agent-failed-once",["Review","@selected"],2,2,0,1,{}];
 const allFailed=["all-failed","agent-fails-all",["Review","@selected","Skip AUR packages"],2,3,0,0,{}];
 const accountRow=["account",null,["Review"],1,1,0,1,{}];
 const defaultRow=["saved-default",null,["Review"],1,1,0,1,{}];
 const automaticRow=["automatic-provider",null,["Review"],1,1,0,1,{}];
 const noVerdict=["no-verdict","agent-no-verdict",["Review","Skip AUR packages"],1,2,0,0,{}];
 // command.js's agent-failed-once output, and that line as failureLines
 // masks a URL's user and password and a token (failure-test.js rows).
 const agentLine="agent limit https://user:secret@example.org/ ghp_12345678901234567890",shownLine="agent limit https://\u2026@example.org/ \u2026";
 // The sentences Updates puts on its result list (pipeline.sh
 // _updates_review_of reads the package-review line) and the offer shows.
 const unrun=(agent,folder)=>agent+" could not run on the account in "+folder+". Sign in to it, or choose another account in the review settings.";
 const unanswered=(agent,folder)=>agent+" gave no review verdict on the account in "+folder+". Check that you are signed in to it, or choose another account in the review settings.";
 const skipped=" You chose to skip the AUR packages.";
 // Each harness's account variable an agent starts with: VARIABLE set to
 // FOLDER under the world's home, every other one unset; with no VARIABLE,
 // every one unset, as a harness's default folder starts.
 const accountsWith=(world,variable,folder)=>({CLAUDE_CONFIG_DIR:null,CODEX_HOME:null,COPILOT_HOME:null,PI_CODING_AGENT_DIR:null,...(variable?{[variable]:path.join(world.env.HOME,folder)}:{})});
 // The credentials the account, saved-default and automatic-provider rows'
 // terminal carries, as an agent-runtime session or a shell with Jarvis's
 // key exports them, beside a Bedrock user's provider switch.
 const credentials={CLAUDE_CODE_USE_BEDROCK:"1",ANTHROPIC_API_KEY:"sk-ant-fixture",CLAUDE_CODE_OAUTH_TOKEN:"fixture-token",VGS_TEST_UNRELATED:"kept"};
 // What reached a chosen folder's agent: no credential its harness ranks
 // above that folder's sign-in.
 const chosenOnly={CLAUDE_CODE_USE_BEDROCK:false,ANTHROPIC_API_KEY:false,CLAUDE_CODE_OAUTH_TOKEN:false,VGS_TEST_UNRELATED:true};
 function agentFailure([name,marker,choices,expected,offerCount,status,built,options],folder=name,owner=undefined){
  const world=create(path.join(scratch,folder),{choices,...options});
  if(owner!==undefined)world.owner=owner;
  for(const file of [].concat(marker??[]))write(world,file,"");
  if(name==="other-agent")write(world,"agent-mutates","");
  // The review settings choose a second Claude account, one whose folder is
  // gone, or the default one while the terminal names another. Automatic
  // runs where the terminal carries a provider switch and stray credentials.
  const extra=name==="automatic-provider"?{...credentials}:{};
  if(name==="account"||name==="account-gone"||name==="saved-default"){
   const account=path.join(world.env.HOME,{account:".claude-work","account-gone":".claude-gone","saved-default":".claude"}[name]);
   if(name==="account")fs.mkdirSync(account);
   if(name!=="account-gone")Object.assign(extra,credentials);
   if(name==="saved-default")extra.CLAUDE_CONFIG_DIR=path.join(world.env.HOME,".claude-env");
   write(world,"config/vgshell/shell.json",{version:6,disabledPlugins:["vgs.updates"],packages:{review:{agent:"claude",command:"",account}}});
  }
  const result=tty(world,["run","install","--manager","aur","widget"],extra);
  assert.equal(result.status,status,name+": "+result.stdout+result.stderr);
  assert.equal(agents(world).length,expected,name);
  assert.equal(offers(world).length,offerCount,name+": review questions");
  const lines=judge.transcriptLines(result.stdout),delivered=lines.join(" ").replace(/\s+/g," ");
  // Array.from: keyed's array belongs to the judge's own context.
  const reviewed=Array.from(keyed(result,"package-review"),line=>line.slice("vgshell: package-review: ".length));
  if(name==="missing-agent")assert.deepEqual(offers(world)[1].offered,["Install without review","Skip AUR packages"],name+": no other agent to offer");
  if(name==="other-agent"){
   const ended=lines.findIndex(line=>line.includes(agentLine));
   assert.ok(ended>=0,name+": the agent's own output reaches the terminal");
   const after=lines.slice(ended+1),shown=after.filter(line=>!line.startsWith("vgshell: review-diagnostic: ")).join(" ").replace(/\s+/g," ");
   assert.ok(shown.includes(unrun("Claude Code","~/.claude")),name+": one sentence names the agent, its account and the next step");
   assert.ok(!shown.includes("agent limit"),name+": the agent's raw last line stays in the log");
   assert.ok(keyed(result,"review-diagnostic").some(line=>line.startsWith("vgshell: review-diagnostic: agent=claude status=4 ")&&line.includes(shownLine)),name+": the log holds the agent's masked last line");
   assert.deepEqual(agents(world).map(call=>call.accounts),[accountsWith(world),accountsWith(world)],name+": each agent's default account starts with its variable unset");
  }
  if(name==="all-failed"){
   assert.deepEqual(offers(world)[2].offered,["Install without review","Skip AUR packages"],name+": an agent that failed is not offered again");
   assert.ok(delivered.includes(unrun("Codex","~/.codex")),name+": the second agent's sentence names its account");
   assert.deepEqual(reviewed,["No review agent could run."+skipped],name+": one sentence says no review agent could run");
  }
  if(name==="skip-aur")assert.deepEqual(reviewed,[unrun("Claude Code","~/.claude")+skipped],name+": the skip keeps the agent's sentence");
  if(name==="no-verdict"){
   assert.deepEqual(reviewed,[unanswered("Claude Code","~/.claude")+skipped],name+": the sentence names the agent, its account and the next step");
   assert.ok(keyed(result,"review-diagnostic").some(line=>line.startsWith('vgshell: review-diagnostic: agent=claude verdict="is missing" ')),name+": the verdict's problem is on the log line");
  }
  if(name==="account"){
   assert.deepEqual(agents(world)[0].accounts,accountsWith(world,"CLAUDE_CONFIG_DIR",".claude-work"),name+": the agent starts on the chosen account alone");
   assert.deepEqual(agents(world)[0].inherited,chosenOnly,name+": no inherited credential outranks the chosen account");
   assert.ok(delivered.includes("Reviewing AUR build files as your user, on the account in ~/.claude-work"),name+": the command block names the account");
  }
  if(name==="saved-default"){
   assert.deepEqual(agents(world)[0].accounts,accountsWith(world),name+": the default account starts with its variable unset");
   assert.deepEqual(agents(world)[0].inherited,chosenOnly,name+": no inherited credential outranks the default account");
  }
  if(name==="automatic-provider")assert.deepEqual(agents(world)[0].inherited,{CLAUDE_CODE_USE_BEDROCK:true,ANTHROPIC_API_KEY:false,CLAUDE_CODE_OAUTH_TOKEN:false,VGS_TEST_UNRELATED:true},
   name+": automatic keeps the harness's own provider switch and drops stray credentials");
  if(name==="account-gone"){
   assert.ok(offers(world)[1].offered.includes("Use Codex"),name+": the other agent is offered");
   assert.deepEqual(reviewed,[unrun("Claude Code","~/.claude-gone")+skipped],name+": the sentence names the chosen account");
   assert.ok(keyed(result,"review-diagnostic").includes("vgshell: review-diagnostic: agent=claude account=missing"),name+": the missing account is on the log line");
  }
  // A drop that could not run lets the review go on only when polkit
  // answers that nothing is held; any other failed drop ends it, with the
  // command's own cause on the diagnostic line.
  if(name.startsWith("drop-no-session"))assert.ok(world.calls().some(call=>call.name==="pkcheck"&&call.args[0]==="--action-id"),name+": polkit is asked about this process");
  if(name==="drop-failed")assert.ok(keyed(result,"review-diagnostic").some(line=>line.includes("Error revoking temporary authorizations")),name+": the drop's own cause");
  if(name==="owner-terminated")assert.deepEqual(world.calls().filter(call=>call.kind.startsWith("agent-")&&call.kind!=="agent-edit").map(call=>call.kind),["agent-term"],name+": the TERM sent to the owner reaches the agent");
  if(status===0&&built===0)assert.equal(keyed(result,"package-review").length,1,name+": the skip is the step's one review result");
  if(name==="other-agent"){
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
 for(const row of [
  otherAgent,
  allFailed,
  accountRow,
  defaultRow,
  automaticRow,
  ["account-gone",null,["Review","Skip AUR packages"],0,2,0,0,{}],
  ["skip-aur","agent-failed-once",["Review","Skip AUR packages"],1,2,0,0,{}],
  noVerdict,
  ["unsafe-verdict","agent-unsafe",["Review","Skip AUR packages"],1,2,0,0,{}],
  ["missing-agent",null,["Review","Skip AUR packages"],0,2,0,0,{agents:false}],
  ["agent-interrupted","agent-interrupted",["Review"],1,1,130,0,{}],
  ["owner-terminated","agent-terminates-owner",["Review"],1,1,143,0,{}],
  ["drop-no-session","pkcheck-no-session",["Review"],1,1,0,1,{}],
  ["drop-no-session-authorized",["pkcheck-no-session","pkcheck-authorized"],["Review"],0,1,1,0,{}],
  ["drop-failed","pkcheck-failed",["Review"],0,1,1,0,{}]
 ])agentFailure(row);
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
 // An upgrade's check-only failure of one pending package, while paru built
 // the other, offers its retry in the same run. The retry's view holds the
 // same tree, so its stored verdict asks no second review. OWNER, when
 // given, is a control's copy of bin/vgshell-pkg.
 function upgradeRetry(folder="upgrade-retry",owner=undefined){
  const world=create(path.join(scratch,folder),{choices:["Review","Retry without tests"]}),target="vgs-fixture-check-only";
  if(owner!==undefined)world.owner=owner;
  write(world,"dependency-world.json",{pending:[target,"vgs-fixture-check-pass"]});
  write(world,"build.json",{first:{transcript:"paru-2.2-batch-install",status:1},retry:{status:0}});
  const result=tty(world,["run","upgrade","--manager","aur"]);
  assert.equal(result.status,0,"upgrade retry: "+result.stdout+result.stderr);
  assert.equal(agents(world).length,1,"upgrade retry: one agent review");
  const retried=builds(world).filter(call=>call.args.includes("--nocheck"));
  assert.deepEqual(retried.map(call=>call.args.slice(call.args.indexOf("--")+1)),[[target]],"upgrade retry: one test-skipping build of the failed package");
  assert.ok(keyed(result,"package-result").some(line=>line.includes(target)),"upgrade retry: a result line names the package the retry installed");
 }
 upgradeRetry();
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
 for(const mode of ["offline","offline-previous","offline-copy-blocked","offline-editor-blocked","offline-editor-changed","saved-off","offline-race","live-confirm","live-unconfirmed","concurrent","malformed","future","unreadable"]){
  const world=create(path.join(scratch,"settings-"+mode),{settings:{agent:"",command:""}});
  const result=cp.spawnSync(process.execPath,[path.join(__dirname,"settings.js"),world.root,mode],{env:world.env,encoding:"utf8",timeout:30000});
  assert.equal(result.status,0,result.stdout+result.stderr);
 }
 // The editors' owner verbs. The account offers are each folder discovery
 // lists for the choices' agent, its default first, as the editor shows
 // it. The saved account reads as the review would use it: a folder that
 // is gone is not found, and one discovery lists for another agent leaves
 // this agent automatic. A change goes through PackageReview.reviewChange,
 // so another agent drops the saved account. OWNER, when given, is a
 // control's copy of bin/vgshell-pkg.
 function editorVerbs(folder="settings-editor",owner=undefined){
  const world=create(path.join(scratch,folder));
  if(owner!==undefined)world.owner=owner;
  const verb=(...args)=>{
   const read=cp.spawnSync(process.execPath,[world.owner,...args],{env:world.env,encoding:"utf8",timeout:30000});
   assert.equal(read.status,0,"review settings "+args[0]+": "+read.stderr);
   return read.stdout;
  };
  const home=world.env.HOME,work=path.join(home,".claude-work");
  for(const name of [".claude-work",".2codex"])fs.mkdirSync(path.join(home,name));
  for(const [agent,want] of [["claude",[".claude",".claude-work"]],["codex",[".codex",".2codex"]]])
   assert.deepEqual(verb("review-settings-accounts",JSON.stringify({agent,command:""})).split("\n").filter(Boolean).map(line=>line.split("\t")),
    want.map(name=>[path.join(home,name),"~/"+name]),"review settings accounts: "+agent);
  for(const [name,settings,want] of [
   ["automatic",{agent:"claude",command:""},"automatic"],
   ["chosen",{agent:"claude",command:"",account:work},"chosen\t~/.claude-work"],
   ["gone",{agent:"claude",command:"",account:path.join(home,".claude-gone")},"missing\t~/.claude-gone"],
   ["another agent's folder",{agent:"codex",command:"",account:work},"automatic"]
  ])assert.equal(verb("review-settings-account",JSON.stringify(settings)).trim(),want,"review settings account: "+name);
  const change=(settings,key,value)=>JSON.parse(verb("review-settings-change",JSON.stringify(settings),key,JSON.stringify(value)));
  assert.deepEqual(change({agent:"claude",command:"",account:work},"agent","codex"),{agent:"codex",command:""},"review settings change: another agent drops the account");
  assert.deepEqual(change({agent:"claude",command:"",account:work},"agent","claude"),{agent:"claude",command:"",account:work},"review settings change: the same agent keeps the account");
 }
 editorVerbs();
 // Controls: a copy of the owner with one rule of pkg-review.js, or of
 // FILE, removed fails the case that holds the rule, at that rule's own
 // assertion. The copy's bin/ is its own, so the launcher paru runs is the
 // copy's; the rest of the checkout is linked.
 const repo=path.resolve(__dirname,"../../..");
 for(const [name,needle,replacement,rerun,fails,file="bin/lib/pkg-review.js"] of [
  ["updates-repair","if (repaired !== old) fs.chmodSync(dir, repaired);","void repaired;",owner=>updatesRoot("control-updates-repair",owner),/^updates review: admitted after check:/],
  ["runtime-repair",'return repairedFolder(path.join(real, "vgshell"), 0o022);','return ownedFolder(path.join(real, "vgshell"), 0o022);',owner=>updatesRoot("control-runtime-repair",owner),/^updates review: admitted after check:/],
  ["updates-folder-repair",'repairedFolder(path.join(runtimeRoot(), "updates"), 0o077)','ownedFolder(path.join(runtimeRoot(), "updates"))',owner=>updatesRoot("control-updates-folder-repair",owner),/^updates review: admitted over an older updates folder:/],
  ["chmod-before-check","    ownedDirectory(dir, 0);\n    const old","    const old",owner=>unsafeUpdatesRoot("link","control-chmod-before-check",owner),/^link: the linked folder keeps its mode$/],
  ["chmod-before-check-parent","    ownedDirectory(dir, 0);\n    const old","    const old",owner=>unsafeUpdatesRoot("parent-link","control-chmod-before-check-parent",owner),/^parent-link: the linked folder keeps its mode$/],
  ["updates-link",
   "const stat = fs.lstatSync(dir);\n    if (!stat.isDirectory() || stat.uid !== process.getuid() || (stat.mode & forbiddenMode) || fs.realpathSync(dir) !== dir)",
   "const stat = fs.statSync(dir);\n    if (!stat.isDirectory() || stat.uid !== process.getuid() || (stat.mode & forbiddenMode))",
   owner=>unsafeUpdatesRoot("link","control-updates-link",owner),/^link: (?:unsafe updates root refused|the linked folder keeps its mode)$/],
  ["updates-foreign","!stat.isDirectory() || stat.uid !== process.getuid() || (stat.mode & forbiddenMode)","!stat.isDirectory() || (stat.mode & forbiddenMode)",owner=>unsafeUpdatesRoot("foreign","control-updates-foreign",owner),/^foreign: unsafe updates root refused$/],
  ["tracking-old-shape","!Array.isArray(state[base])","!Array.isArray(state[base]?.repos)",owner=>devel(develCurrent,"control-tracking-old-shape",owner),/^devel-paru-2.2.0: untracked devel base result$/,"bin/vgshell-pkg"],
  // helperReviewCovered's named-target branch, which reinstall takes.
  ["reinstall-reviewed","let targets = names;","let targets = [];",owner=>bypass(publisherReinstall,"control-reinstall-reviewed",owner),/^publisher-reinstall: (?:agent count|review questions|helper review choice)$/],
  ["unnamed-account",'" on the account in " + shownFolder(account.directory)','""',owner=>agentFailure(otherAgent,"control-unnamed-account",owner),/^other-agent: one sentence names the agent, its account and the next step$/],
  ["raw-line-shown",'return { failure: failureSentence(plan, account, unrun ? "unrun" : "no-verdict") };','return { failure: failureSentence(plan, account, unrun ? "unrun" : "no-verdict") + " Its last line: " + last };',owner=>agentFailure(otherAgent,"control-raw-line-shown",owner),/^other-agent: the agent's raw last line stays in the log$/],
  ["account-variable","else out[row.variable] = account.directory;","else delete out[row.variable];",owner=>agentFailure(accountRow,"control-account-variable",owner),/^account: the agent starts on the chosen account alone$/],
  ["outranking-kept","for (const name of (account.chosen ? row.outranks : row.strays) || []) delete out[name];","void row;",owner=>agentFailure(accountRow,"control-outranking-kept",owner),/^account: no inherited credential outranks the chosen account$/],
  ["automatic-strips-provider","(account.chosen ? row.outranks : row.strays)","row.outranks",owner=>agentFailure(automaticRow,"control-automatic-strips-provider",owner),/^automatic-provider: automatic keeps the harness's own provider switch and drops stray credentials$/],
  ["automatic-keeps-strays","(account.chosen ? row.outranks : row.strays)","(account.chosen ? row.outranks : [])",owner=>agentFailure(automaticRow,"control-automatic-keeps-strays",owner),/^automatic-provider: automatic keeps the harness's own provider switch and drops stray credentials$/],
  ["default-variable-set",'if (account.source === "default") delete out[row.variable];\n    else out[row.variable] = account.directory;',"out[row.variable] = account.directory;",owner=>agentFailure(defaultRow,"control-default-variable-set",owner),/^saved-default: the default account starts with its variable unset$/],
  ["no-verdict-next-step",'". Check that you are signed in to it, or choose another account in the review settings."','"."',owner=>agentFailure(noVerdict,"control-no-verdict-next-step",owner),/^no-verdict: the sentence names the agent, its account and the next step$/],
  ["skip-one-line",'"\\nYou chose to skip the AUR packages."','" You chose to skip the AUR packages."',owner=>agentFailure(noVerdict,"control-skip-one-line",owner),/^no-verdict: the sentence names the agent, its account and the next step$/],
  ["editor-own-change","judge.reviewChange(JSON.parse(args[0]), args[1], JSON.parse(args[2]))","{ ...JSON.parse(args[0]), [args[1]]: JSON.parse(args[2]) }",owner=>editorVerbs("control-editor-own-change",owner),/^review settings change: another agent drops the account$/,"bin/vgshell-pkg"],
  ["editor-other-agent-not-found",'account.state === "account" && account.directory === saved ?','account.state === "account" ?',owner=>editorVerbs("control-editor-other-agent-not-found",owner),/^review settings account: another agent's folder$/],
  ["failed-offered-again","!tried.includes(agent.id) && available(agent.id)","agent.id !== plan.agent && available(agent.id)",owner=>agentFailure(allFailed,"control-failed-offered-again",owner),/^all-failed: an agent that failed is not offered again$/],
  ["no-agent-sentence",'const none = other === undefined && plan.state !== "none" ? NO_AGENT : "";','const none = "";',owner=>agentFailure(allFailed,"control-no-agent-sentence",owner),/^all-failed: one sentence says no review agent could run$/],
  ["upgrade-unclassified",'["install", "reinstall", "update", "upgrade"].includes(r.plan.action)','["install", "reinstall", "update"].includes(r.plan.action)',owner=>upgradeRetry("control-upgrade-unclassified",owner),/^upgrade retry: /,"bin/vgshell-pkg"],
  ["tracking-error-unread",'if (status !== 0 || review.judge.transcriptLines(stderr).some(line => line.startsWith("error:")))','if (status !== 0)',owner=>devel(develError,"control-tracking-error-unread",owner),/^devel-error: the tracking error is one result line$/,"bin/vgshell-pkg"]
 ]){
  const tree=path.join(scratch,"owner-"+name);
  fs.mkdirSync(tree);fs.cpSync(path.join(repo,"bin"),path.join(tree,"bin"),{recursive:true});
  for(const entry of ["VERSION","shell","config","packaging"])fs.symlinkSync(path.join(repo,entry),path.join(tree,entry));
  const copied=path.join(tree,file),source=fs.readFileSync(copied,"utf8");
  assert.equal(source.split(needle).length-1,1,name+": one rule to remove");
  fs.writeFileSync(copied,source.replace(needle,replacement));
  let caught=null;
  try{rerun(path.join(tree,"bin/vgshell-pkg"));}catch(error){caught=error;}
  // Node appends a diff after an assert.equal message; judge its own line.
  assert.ok(caught?.code==="ERR_ASSERTION"&&fails.test(caught.message.split("\n")[0]),"the "+name+" mutant passes: "+(caught?.message??"no failure"));
 }
 console.log("test-package-review-runtime: ok");
}finally{fs.rmSync(scratch,{recursive:true,force:true});}
