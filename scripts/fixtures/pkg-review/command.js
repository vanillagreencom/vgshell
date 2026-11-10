#!/usr/bin/env node
// Safe production-entry stand-ins: this PATH contains every reachable
// package, credential and agent command, and never delegates a mutation.
"use strict";
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process");
const name=path.basename(process.argv[1]),args=process.argv.slice(2),originalArgs=args.slice(),root=process.env.REVIEW_WORLD;
const log=(kind,extra={})=>fs.appendFileSync(path.join(root,"calls.jsonl"),JSON.stringify({kind,name,args:originalArgs,...extra})+"\n");
if(name==="gum"){
 if(args[0]==="choose"){
  const choices=JSON.parse(fs.readFileSync(path.join(root,"choices.json"))),choice=choices.shift();
  fs.writeFileSync(path.join(root,"choices.json"),JSON.stringify(choices));
  const offered=args.slice(args.indexOf("--")+1),at=args.indexOf("--selected"),selected=at<0?offered[0]:args[at+1];
  log("offer",{offered,selected,choice,selectedIndex:offered.indexOf(selected),choiceIndex:offered.indexOf(choice)});
  // gum 2.0.2's choose: Ctrl-C exits 130 and Esc 1.
  if(choice==="cancel")process.exit(130);
  if(choice==="esc")process.exit(1);
  if(!offered.includes(choice))throw new Error("fixture choice invalid "+choice);
  console.log(args.some(arg=>arg.startsWith("--label-delimiter="))?choice.split("\t").at(-1):choice);
 }else if(args[0]==="style")console.log(args.slice(args.indexOf("--")+1).join("\n"));
 process.exit(0);
}
if(["sudo","doas","run0"].includes(name)){
 log("credential");
 if(["-k","-n","/usr/bin/true"].includes(args[0]))process.exit(0);
 const cp=require("node:child_process"),r=cp.spawnSync(args[0],args.slice(1),{stdio:"inherit",env:process.env});process.exit(r.status||0);
}
log("query");
if(args[0]==="--version"){console.log(name==="makepkg"?"makepkg (pacman) 7.1.0":name+" v"+(name==="paru"?"2.1.0 +git":"12.5.0")+" - libalpm v16.0.1");process.exit(0);}
// A build scenario, build.json: the recorded transcript a build prints and
// its status, and the retry's (a build given --nocheck), each once in order.
function build(){
 const file=path.join(root,"build.json");if(!fs.existsSync(file))return 0;
 const plan=JSON.parse(fs.readFileSync(file)),step=originalArgs.includes("--nocheck")?plan.retry:plan.first;
 if(!step)throw new Error("fixture build step missing for "+originalArgs.join(" "));
 if(step.transcript){let text=fs.readFileSync(path.resolve(__dirname,"../pkg/check-failure",step.transcript+".out"),"latin1");if(step.base)text=text.replaceAll("vgs-fixture-check-only",step.base);process.stdout.write(Buffer.from(text,"latin1"));}
 return step.status;
}
const configAt=args.indexOf("--config"),effectiveConfig=configAt<0?"/etc/pacman.conf":args[configAt+1];if(configAt>=0)args.splice(configAt,2);
const dependencyFile=path.join(root,"dependency-world.json"),dependencies=fs.existsSync(dependencyFile)?JSON.parse(fs.readFileSync(dependencyFile)):{};
// Canned package answers include only declared entries, even for names
// such as __proto__ that also exist on Object.prototype.
const named=(table,key)=>table&&Object.hasOwn(table,key)?table[key]:undefined;
// Paru v2.1.0, 70f66dc9: install.rs:179-209 snapshots cached .SRCINFO
// before download; devel.rs:503-525 reads its git sources; install.rs:815-822
// removes a base with none. gendb (devel.rs:121-126,153-161,204-210) reads
// the new file for missing bases and leaves existing tracked commits alone.
// devel.rs:529-553 omits failed lookups while gendb returns zero.
// This stand-in writes only this world's scratch state, never a host file.
const develFile=path.join(root,"devel-world.json");
function devel(gendb){
 if(!fs.existsSync(develFile)&&!gendb)return;
 const state=fs.existsSync(develFile)?JSON.parse(fs.readFileSync(develFile)):{sources:{"vgshell-git":{url:"https://example.org/vgs.git",commit:"new-vgs-commit"}},cachedSources:{},tracked:{}};
 if(gendb){
  log("devel-completion",{config:effectiveConfig});
  if(state.trackingStatus)process.exit(state.trackingStatus);
  if(state.trackingDiagnostic)process.stderr.write(state.trackingDiagnostic+"\n");
  for(const [base,source] of Object.entries(state.sources))if(!named(state.tracked,base)&&source&&!state.missingTracking)state.tracked[base]=source;
 }else{
  if(state.installStatus)process.exit(state.installStatus);
  const targets=args.includes("-Sua")?[].concat(dependencies.pending||[]):args.slice(args.indexOf("--")+1);
  for(const base of targets){
   if(named(state.cachedSources,base))state.tracked[base]=named(state.cachedSources,base);
   else delete state.tracked[base];
   state.cachedSources[base]=named(state.sources,base);
  }
 }
 const dir=path.join(process.env.XDG_STATE_HOME,"paru");fs.mkdirSync(dir,{recursive:true});
 if(!state.missingResult)fs.writeFileSync(path.join(dir,"devel.toml"),Object.entries(state.tracked).map(([base,source])=>`[[${base}.repos]]\nurl = ${JSON.stringify(source.url)}\ncommit = ${JSON.stringify(source.commit)}\n`).join("\n"));
 fs.writeFileSync(develFile,JSON.stringify(state));
}
if(name==="paru"&&args.includes("--gendb")){devel(true);process.exit(0);}
if(name==="pacman-conf"){
 if(fs.existsSync(path.join(root,"query-failed")))process.exit(7);
 if(args.includes("--repo-list"))console.log([...fs.readFileSync(path.join(root,"included.conf"),"utf8").matchAll(/^\[([^\]]+)\]/gm)].map(row=>row[1]).concat(fs.existsSync(path.join(root,"repo-aur"))?["aur"]:[]).join("\n"));
 else if(args.includes("Server")&&!fs.existsSync(path.join(root,"server-empty")))console.log("https://user:secret@packages.example.org/$repo/$arch");
 else if(args.includes("SigLevel"))console.log("Required DatabaseOptional");
 else if(args.includes("DBPath"))console.log(effectiveConfig==="/etc/pacman.conf"&&!fs.existsSync(path.join(root,"config-corresponds"))?"/var/lib/pacman/":path.join(root,"db"));
 else if(args.includes("HookDir"))console.log(path.join(root,"hooks"));
 process.exit(0);
}
if(name==="checkupdates"||args.includes("-Qua")||args.includes("-Qu")){
 // AUR-only queries need an AUR target; collisions declare pending explicitly.
 const target=args.includes("-Qua")?(Object.hasOwn(dependencies,"pending")?dependencies.pending:"foreign"):"widget";
 for(const pkg of Array.isArray(target)?target:[target])console.log((fs.existsSync(path.join(root,"pending-name-changed"))?"another":pkg)+" "+(fs.existsSync(path.join(root,"pending-old-changed"))?"0":"1")+" -> "+(fs.existsSync(path.join(root,"pending-changed"))?"3":"2"));process.exit(0);
}
if(name==="pacman"||name==="paru"||name==="yay"){
 if(args.includes("-T")){
  const missing=args.slice(args.indexOf("--")+1).filter(entry=>(dependencies.missing||[]).includes(entry));
  if(missing.length)console.log(missing.join("\n"));process.exit(missing.length?127:0);
 }
 if(args.includes("-Sddp")){
  const entry=args.at(-1),row=named(dependencies.satisfiers,entry);
  if(row?.error){process.stderr.write(row.error);process.exit(1);}
  if(row!==undefined){process.stdout.write(row+"\n");process.exit(0);}
  process.stderr.write("error: target not found: "+entry+"\n");process.exit(1);
 }
 if(args.includes("-Po")){
  if(dependencies.buildOrder){
   const order=named(dependencies.buildOrder,args.at(-1))||named(dependencies.buildOrder,"upgrade");
   if(typeof order==="string")console.log(order);
   else{
    if(order.stdout)process.stdout.write(order.stdout);
    if(order.stderr)process.stderr.write(order.stderr);
    if(order.signal)process.kill(process.pid,order.signal);
    process.exit(order.status||0);
   }
   process.exit(0);
  }
  const row=named(dependencies.order,args.at(-1));
  if(row===undefined){console.log("MISSING "+args.at(-1));process.exit(1);}
  console.log(row);process.exit(0);
 }
 if(args.includes("-Sl")){console.log("core official 1\n"+(fs.existsSync(path.join(root,"origin-changed"))?"core":"custom")+" widget "+(fs.existsSync(path.join(root,"candidate-changed"))?"3":"2")+"\ncustom aurpkg 2"+(fs.existsSync(path.join(root,"sync-extra"))?"\n"+fs.readFileSync(path.join(root,"sync-extra"),"utf8").trim():""));process.exit(0);}
 if(args.includes("-Si")){
  const pkg=args.at(-1);if(fs.existsSync(path.join(root,"info-failed"))||/[<>=]/.test(pkg))process.exit(1);
  console.log("Repository : aur\nName : "+(fs.existsSync(path.join(root,"provider-ambiguous"))?"provider":pkg));
  const fields=named(dependencies.info,pkg)||{};
  for(const key of ["Depends On","Make Deps","Check Deps"])if(fields[key]!==null)console.log(key+" : "+(fields[key]||"None"));
  process.exit(0);
 }
 if(args.includes("-Qoq")){console.log("vgshell-git");process.exit(0);}
 if(args.includes("-Qmq")){const names=dependencies.foreign||[];if(names.length)console.log(names.join("\n"));process.exit(names.length?0:1);}
 if(args.includes("-Qtdq"))process.exit(1);
 if(args.includes("-Q")){console.log(args.includes("--")?args.at(-1)+" 1-1":"widget 1-1\nvgshell-git 1-1");process.exit(0);}
 if(args.includes("-Slq")||args.includes("-Slqa")){console.log("widget");process.exit(0);}
 if(args.includes("-G")){
  if(fs.existsSync(path.join(root,"fetch-failed")))process.exit(8);
  const names=args.slice(args.indexOf("--")+1);
  for(const pkg of names){
   const dir=path.join(process.cwd(),pkg);fs.mkdirSync(dir,{recursive:true});
   const script=fs.existsSync(path.join(root,"install-risk"))||fs.existsSync(path.join(root,"install-link"));
   fs.writeFileSync(path.join(dir,".SRCINFO"),`pkgbase = ${pkg}\n${script?"install = package.install\n":""}pkgname = other-split\npkgname = ${pkg}\n`);
   if(script){
    if(fs.existsSync(path.join(root,"install-link"))){fs.writeFileSync(path.join(root,"private-user-file"),"UNREAD_USER_BYTES");fs.symlinkSync(path.join(root,"private-user-file"),path.join(dir,"package.install"));}
    else fs.writeFileSync(path.join(dir,"package.install"),"chmod u+s /opt/package\n");
   }
   if(fs.existsSync(path.join(root,"srcinfo-link"))){fs.renameSync(path.join(dir,".SRCINFO"),path.join(dir,".SRCINFO.saved"));fs.symlinkSync(path.join(dir,".SRCINFO.saved"),path.join(dir,".SRCINFO"));}
   fs.writeFileSync(path.join(dir,"PKGBUILD"),"pkgname="+pkg+"\n"+(fs.existsSync(path.join(root,"recipe-changed"))?"pkgrel=2\n":""));
  }
  process.exit(0);
 }
 log("mutation");
 if(dependencies.prompts&&name==="paru"){
  if(!args.includes("--skipreview"))for(const prompt of ["review","pager","diff"])log("helper-prompt",{prompt});
  if(args.includes("-Sua"))log("pacman-confirmation",{transaction:"repository-make-dependencies"});
  const count=args.includes("--batchinstall")?1:args.includes("-Sua")?2:1;
  for(let i=0;i<count;i++)log("pacman-confirmation",{transaction:"built-packages"});
 }
 // pacman builds no recipe: a scenario's failing pacman exits with its status alone.
 if(name==="pacman"){if(dependencies.prompts)log("pacman-confirmation",{transaction:"system-upgrade"});const file=path.join(root,"build.json");process.exit(fs.existsSync(file)?JSON.parse(fs.readFileSync(file)).pacman||0:0);}
 const status=build();
 if(status===0&&name==="paru")devel(false);
 process.exit(status);
}
if(name==="snapper"){
 if(args.includes("list-configs"))console.log("config,subvolume\nroot,/");else log("snapshot");process.exit(0);
}
if(name==="git"){
 if(JSON.stringify(args.slice(-4))===JSON.stringify(["ls-files","--cached","-z","--"])){
  const r=cp.spawnSync("/usr/bin/git",args,{env:process.env,stdio:"inherit",timeout:30000});
  if(r.error)throw r.error;process.exit(r.status===null?1:r.status);
 }
 const dest=path.resolve(process.cwd(),args.at(-1));fs.mkdirSync(dest,{recursive:true});
 fs.writeFileSync(path.join(dest,".SRCINFO"),"pkgbase = paru\npkgname = paru\n");fs.writeFileSync(path.join(dest,"PKGBUILD"),"pkgname=paru\n");process.exit(0);
}
if(name==="makepkg"){
 log("mutation",{cwd:process.cwd()});const status=build();if(status===0)fs.symlinkSync(fs.realpathSync(__filename),path.join(root,"tools/paru"));process.exit(status);
}
if(name==="claude"||name==="codex"){
 const reviewDir=/The review directory is `([^`]+)`/.exec(args.at(-1))?.[1],listed=reviewDir&&path.join(reviewDir,"packages.txt");
 log("agent",{cwd:process.cwd(),reviewDir,packages:listed&&fs.existsSync(listed)?fs.readFileSync(listed,"utf8").split("\n").filter(Boolean):null});
 if(fs.existsSync(path.join(root,"agent-failed-once"))&&name==="claude")process.exit(4);
 if(fs.existsSync(path.join(root,"agent-failed")))process.exit(4);const prompt=args.at(-1),match=/The review directory is `([^`]+)`/.exec(prompt);
 if(!match)throw new Error("fixture missing review directory");
 console.log("Reading AUR build recipes as your user.");
 if(!fs.existsSync(path.join(root,"agent-no-verdict"))){
  const flagged=fs.existsSync(path.join(root,"agent-concern"));
  const first=fs.readFileSync(path.join(match[1],"packages.txt"),"utf8").split("\n").find(line=>line.startsWith("aur "))?.split(" ")[1];
  fs.writeFileSync(path.join(match[1],"verdict"),dependencies.flag?"verdict flagged\nflag "+dependencies.flag+" Further verification required.\n":fs.existsSync(path.join(root,"agent-dependency"))?"verdict flagged\nflag dependency Further verification required.\n":fs.existsSync(path.join(root,"agent-malformed"))?"verdict clean\nflag widget conflict\n":flagged?"verdict flagged\nflag "+first+" A source requires further verification.\n":"verdict clean\n",{mode:0o600});
  if(fs.existsSync(path.join(root,"agent-unsafe")))fs.chmodSync(path.join(match[1],"verdict"),0o644);
  if(fs.existsSync(path.join(root,"agent-unreadable")))fs.chmodSync(path.join(match[1],"verdict"),0o000);
  console.log("The review is done. Exit the agent to see the summary and installation choices.");
 }
 process.exit(0);
}
if(name==="fzf"){process.stdout.write("widget\n");process.exit(0);}
throw new Error("fixture unexpected command "+name);
