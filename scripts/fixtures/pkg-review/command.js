#!/usr/bin/env node
// Safe production-entry stand-ins: this PATH contains every reachable
// package, credential and agent command, and never delegates a mutation.
"use strict";
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process");
const name=path.basename(process.argv[1]),args=process.argv.slice(2),originalArgs=args.slice(),root=process.env.REVIEW_WORLD;
const log=(kind,extra={})=>fs.appendFileSync(path.join(root,"calls.jsonl"),JSON.stringify({kind,name,args:originalArgs,...extra})+"\n");
if(name==="gum"){
 if(args[0]==="choose"){
  const choices=JSON.parse(fs.readFileSync(path.join(root,"choices.json")));let choice=choices.shift();
  fs.writeFileSync(path.join(root,"choices.json"),JSON.stringify(choices));
  const offered=args.slice(args.indexOf("--")+1),at=args.indexOf("--selected"),selected=at<0?offered[0]:args[at+1];
  if(choice==="@selected")choice=selected;
  if(choice==="@skip")choice=offered.find(value=>value.startsWith("Skip "));
  log("offer",{offered,selected,choice,selectedIndex:offered.indexOf(selected),choiceIndex:offered.indexOf(choice)});
  // gum 2.0.2's choose: Ctrl-C exits 130 and Esc 1.
  if(choice==="cancel")process.exit(130);
  if(choice==="esc")process.exit(1);
  if(!offered.includes(choice))throw new Error("fixture choice invalid "+choice);
  console.log(args.some(arg=>arg.startsWith("--label-delimiter="))?choice.split("\t").at(-1):choice);
 }else if(args[0]==="style")console.log(args.slice(args.indexOf("--")+1).join("\n"));
 process.exit(0);
}
if(["sudo","doas","run0","pkcheck"].includes(name)){
 log("credential");
 // polkit src/programs/pkcheck.c: --revoke-temp's two failures, no login
 // session and a failed revoke; an authorization check of one process
 // subject, pid,start-time,uid, answers 0 when pkcheck-authorized exists,
 // else 1 with "Not authorized.", and 126 for any other subject form.
 if(name==="pkcheck"&&args[0]==="--action-id"){
  if(!/^\d+,\d+,\d+$/.test(args[args.indexOf("--process")+1]||"")){process.stderr.write("Invalid --process value\n");process.exit(126);}
  if(fs.existsSync(path.join(root,"pkcheck-authorized")))process.exit(0);
  process.stderr.write("Not authorized.\n");process.exit(1);
 }
 if(name==="pkcheck"&&fs.existsSync(path.join(root,"pkcheck-no-session"))){process.stderr.write("Error getting session: No session for pid "+process.pid+"\n");process.exit(1);}
 if(name==="pkcheck"&&fs.existsSync(path.join(root,"pkcheck-failed"))){process.stderr.write("Error revoking temporary authorizations: GDBus.Error:org.freedesktop.PolicyKit1.Error.Failed: fixture\n");process.exit(1);}
 if(["-k","--revoke-temp","-n","/usr/bin/true"].includes(args[0]))process.exit(0);
 const cp=require("node:child_process"),r=cp.spawnSync(args[0],args.slice(1),{stdio:"inherit",env:process.env});process.exit(r.status||0);
}
log("query");
if(args[0]==="--version"){console.log(name==="makepkg"?"makepkg (pacman) 7.1.0":name+" v"+(name==="paru"?"2.2.0 +git":"12.5.0")+" - libalpm v16.0.1");process.exit(0);}
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
// paru v2.1.0 (70f66dc9) --gendb registers each installed base's git
// sources (devel.rs:121-126,153-161,204-210). devel-world.json's untracked
// names the bases it leaves out, as devel.rs:529-553 omits a failed lookup
// while --gendb exits zero. This stand-in writes only this world's
// devel.toml, never a host file.
if(name==="paru"&&args.includes("--gendb")){
 log("devel-completion",{config:effectiveConfig});
 const file=path.join(root,"devel-world.json"),untracked=fs.existsSync(file)?JSON.parse(fs.readFileSync(file)).untracked||[]:[];
 const sources=Object.entries({"vgshell-git":{url:"https://example.org/vgs.git",commit:"new-vgs-commit"}}).filter(([base])=>!untracked.includes(base));
 const dir=path.join(process.env.XDG_STATE_HOME,"paru");fs.mkdirSync(dir,{recursive:true});
 fs.writeFileSync(path.join(dir,"devel.toml"),sources.map(([base,source])=>`[[${base}.repos]]\nurl = ${JSON.stringify(source.url)}\ncommit = ${JSON.stringify(source.commit)}\n`).join("\n"));
 process.exit(0);
}
if(name==="pacman-conf"){
 if(args.includes("--repo-list"))console.log([...fs.readFileSync(path.join(root,"included.conf"),"utf8").matchAll(/^\[([^\]]+)\]/gm)].map(row=>row[1]).join("\n"));
 else if(args.includes("Server"))console.log("https://user:secret@packages.example.org/$repo/$arch");
 else if(args.includes("SigLevel"))console.log("Required DatabaseOptional");
 else if(args.includes("DBPath"))console.log(path.join(root,"db"));
 else if(args.includes("HookDir"))console.log(path.join(root,"hooks"));
 process.exit(0);
}
if(name==="checkupdates"||args.includes("-Qua")||args.includes("-Qu")){
 // AUR-only queries need an AUR target; a world declares pending explicitly.
 const target=args.includes("-Qua")?(Object.hasOwn(dependencies,"pending")?dependencies.pending:"foreign"):"widget";
 for(const pkg of Array.isArray(target)?target:[target])console.log(pkg+" 1 -> 2");process.exit(0);
}
if(name==="pacman"||name==="paru"||name==="yay"){
 if(args.includes("-Po")){
  if(dependencies.buildOrder){console.log(named(dependencies.buildOrder,args.at(-1))||named(dependencies.buildOrder,"upgrade"));process.exit(0);}
  for(const target of args.slice(args.indexOf("--")+1))console.log("AUR TARGET "+target+" "+target);process.exit(0);
 }
 if(args.includes("-Qoq")){console.log("vgshell-git");process.exit(0);}
 if(args.includes("-Qtdq"))process.exit(1);
 if(args.includes("-Q")){console.log(args.includes("--")?args.slice(args.indexOf("--")+1).map(target=>target+" 1-1").join("\n"):"widget 1-1\nvgshell-git 1-1");process.exit(0);}
 if(args.includes("-Slq")||args.includes("-Slqa")){console.log("widget");process.exit(0);}
 if(name==="paru"&&!args.includes("--skipreview")){
  const fmAt=args.indexOf("--fm");
  if(fmAt>=0){
   log("helper-start");
   const {cloneRecipe,git}=require("./world.js"),protectedRoot=fs.realpathSync(path.join(root,"protected"));
   const file=path.join(root,"hook-world.json"),scenario=fs.existsSync(file)?JSON.parse(fs.readFileSync(file)):{};
   const targets=args.includes("-Sua")?(dependencies.pending||["foreign"]):args.slice(args.indexOf("--")+1);
   const rows=scenario.packages||targets.map(base=>({base}));
   const ignored=args.flatMap((word,index)=>word==="--ignore"?args[index+1].split(","):[]);
   const view=fs.mkdtempSync(path.join(protectedRoot,"view-")),diffs=path.join(protectedRoot,"diffs");fs.mkdirSync(diffs,{recursive:true});
   for(const row of rows){
    if((row.names||[row.base]).every(pkg=>ignored.includes(pkg)))continue;
    let clone=path.join(protectedRoot,"clones",row.base);
    if(!fs.existsSync(clone))clone=cloneRecipe({protectedRoot},row.base,row);
    const changed=path.join(root,"change-tree-on-repeat");
    if(fs.existsSync(changed)&&fs.existsSync(path.join(root,"hook-called"))){
     fs.appendFileSync(path.join(clone,"PKGBUILD"),"# new tree\n");git(clone,"add","--","PKGBUILD");git(clone,"commit","--quiet","-m","new tree");
    }
    fs.symlinkSync(clone,path.join(view,row.base));
    for(const name of ["PKGBUILD","SRCINFO"])fs.symlinkSync(path.join(clone,name==="SRCINFO"?".SRCINFO":name),path.join(view,row.base+"."+name));
    const diff=path.join(diffs,row.base+".diff");fs.writeFileSync(diff,row.diff||"SUPPLIED_PARU_DIFF "+row.base+"\n");
    fs.symlinkSync(diff,path.join(view,row.base+".diff"));
   }
   fs.writeFileSync(path.join(root,"hook-called"),"");
   const countFile=path.join(root,"hook-count");fs.writeFileSync(countFile,String(fs.existsSync(countFile)?Number(fs.readFileSync(countFile,"utf8"))+1:1));
   const fm=cp.spawnSync(args[fmAt+1],[...(scenario.foreignLeading?["--foreign"]:[]),view],{stdio:"inherit",env:process.env});
   log("file-manager",{view,status:fm.status});
   fs.rmSync(view,{recursive:true,force:true});
   if(fm.error)throw fm.error;
   if(fm.status!==0){process.stderr.write("error: file manager did not execute successfully\n");process.exit(1);}
  }
 }
 log("mutation");
 // pacman builds no recipe: a scenario's failing pacman exits with its status alone.
 if(name==="pacman"){const file=path.join(root,"build.json");process.exit(fs.existsSync(file)?JSON.parse(fs.readFileSync(file)).pacman||0:0);}
 process.exit(build());
}
if(name==="snapper"){
 if(args.includes("list-configs"))console.log("config,subvolume\nroot,/");else log("snapshot");process.exit(0);
}
if(name==="git"){
 if(args.includes("clone")){
  const dest=path.resolve(process.cwd(),args.at(-1));
  const {cloneRecipe}=require("./world.js");
  const world={protectedRoot:fs.realpathSync(path.join(root,"protected"))};
  const cloned=cloneRecipe(world,"paru");
  fs.renameSync(cloned,dest);process.exit(0);
 }
 const r=cp.spawnSync("/usr/bin/git",args,{env:process.env,stdio:"inherit",timeout:30000});
 if(r.error)throw r.error;process.exit(r.status===null?1:r.status);
}
if(name==="makepkg"){
 log("mutation",{cwd:process.cwd()});const status=build();if(status===0)fs.symlinkSync(fs.realpathSync(__filename),path.join(root,"tools/paru"));process.exit(status);
}
if(name==="claude"||name==="codex"){
 const reviewDir=/The review directory is `([^`]+)`/.exec(args.at(-1))?.[1],listed=reviewDir&&path.join(reviewDir,"packages.txt");
 log("agent",{cwd:process.cwd(),reviewDir,packages:listed&&fs.existsSync(listed)?fs.readFileSync(listed,"utf8").split("\n").filter(Boolean):null});
 // The owner's Ctrl-C reaches the agent, which ends by the signal.
 if(fs.existsSync(path.join(root,"agent-interrupted")))process.kill(process.pid,"SIGINT");
 if(reviewDir){
  const snapshots=path.join(root,"agent-evidence");fs.mkdirSync(snapshots,{recursive:true});
  fs.cpSync(reviewDir,path.join(snapshots,String(fs.readdirSync(snapshots).length)),{recursive:true,verbatimSymlinks:true});
 }

 const refusal=require("./agent-argv.js").agentArgvRefusal(name,args,process.cwd());
 if(refusal!==null){process.stderr.write(refusal+"\n");process.exit(5);}
 // A TERM from outside reaches the review owner alone: the nearest ancestor
 // running paru's file-manager launcher. The agent then ends only by the
 // TERM the owner passes on, or notes that none came.
 if(fs.existsSync(path.join(root,"agent-terminates-owner"))){
  let pid=process.ppid,owner=null;
  while(pid>1&&owner===null){
   const argv=fs.readFileSync("/proc/"+pid+"/cmdline","utf8").split("\0");
   if(argv[1]&&path.basename(argv[1])==="review")owner=pid;
   else pid=Number(/\) \S+ (\d+)/.exec(fs.readFileSync("/proc/"+pid+"/stat","utf8"))[1]);
  }
  if(owner===null)throw new Error("fixture review owner not found");
  process.on("SIGTERM",()=>{log("agent-term");process.exit(143);});
  process.kill(owner,"SIGTERM");
  setTimeout(()=>{log("agent-unsignalled");process.exit(0);},20000);
  return;
 }
 if(fs.existsSync(path.join(root,"agent-failed-once"))&&name==="claude"){
  if(fs.existsSync(path.join(root,"agent-mutates"))){
   const base=fs.readdirSync(path.join(reviewDir,"build"))[0];
   fs.appendFileSync(path.join(reviewDir,"build",base,"PKGBUILD"),"\nAGENT_MUTATION\n");
   log("agent-edit",{base});
  }
  console.log("agent limit https://user:secret@example.org/ ghp_12345678901234567890");process.exit(4);
 }
 const prompt=args.at(-1),match=/The review directory is `([^`]+)`/.exec(prompt);
 if(!match)throw new Error("fixture missing review directory");
 console.log("Reading AUR build recipes as your user.");
 if(!fs.existsSync(path.join(root,"agent-no-verdict"))){
  const first=fs.readFileSync(path.join(match[1],"packages.txt"),"utf8").split("\n").find(line=>line.startsWith("aur "))?.split(" ")[1];
  const flaggedName=dependencies.flagOnRepeat&&Number(fs.readFileSync(path.join(root,"hook-count"),"utf8"))>1?first:dependencies.flag;
  fs.writeFileSync(path.join(match[1],"verdict"),flaggedName?"verdict flagged\nflag "+flaggedName+" Further verification required.\n":"verdict clean\n",{mode:0o600});
  if(fs.existsSync(path.join(root,"agent-unsafe")))fs.chmodSync(path.join(match[1],"verdict"),0o644);
  console.log("The review is done. Exit the agent to see the summary and installation choices.");
 }
 process.exit(0);
}
if(name==="fzf"){process.stdout.write("widget\n");process.exit(0);}
throw new Error("fixture unexpected command "+name);
