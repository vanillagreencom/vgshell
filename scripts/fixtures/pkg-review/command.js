#!/usr/bin/env node
// Safe production-entry stand-ins: this PATH contains every reachable
// package, credential and agent command, and never delegates a mutation.
"use strict";
const fs=require("node:fs"),path=require("node:path");
const name=path.basename(process.argv[1]),args=process.argv.slice(2),originalArgs=args.slice(),root=process.env.REVIEW_WORLD;
const log=(kind,extra={})=>fs.appendFileSync(path.join(root,"calls.jsonl"),JSON.stringify({kind,name,args:originalArgs,...extra})+"\n");
if(name==="gum"){
 if(args[0]==="choose"){
  let choices=JSON.parse(fs.readFileSync(path.join(root,"choices.json"))),choice=choices.shift();
  fs.writeFileSync(path.join(root,"choices.json"),JSON.stringify(choices));
  const offered=args.slice(args.indexOf("--")+1),at=args.indexOf("--selected"),selected=at<0?offered[0]:args[at+1];
  if(choice==="continue-then-decline"){
   choice=offered.includes("Yes")?"Yes":"Install without review";
   choices.unshift("continue-then-decline");fs.writeFileSync(path.join(root,"choices.json"),JSON.stringify(choices));
  }
  log("offer",{offered,selected,choice,selectedIndex:offered.indexOf(selected),choiceIndex:offered.indexOf(choice)});
  if(choice==="cancel")process.exit(130);
  if(!offered.includes(choice))throw new Error("fixture choice invalid "+choice);
  console.log(choice);
 }else if(args[0]==="style")console.log(args.slice(args.indexOf("--")+1).join("\n"));
 process.exit(0);
}
if(["sudo","doas","run0"].includes(name)){
 log("credential");
 if(["-k","-n","/usr/bin/true"].includes(args[0]))process.exit(0);
 const cp=require("node:child_process"),r=cp.spawnSync(args[0],args.slice(1),{stdio:"inherit",env:process.env});process.exit(r.status||0);
}
log("query");
const configAt=args.indexOf("--config");if(configAt>=0)args.splice(configAt,2);
if(name==="pacman-conf"){
 if(fs.existsSync(path.join(root,"query-failed")))process.exit(7);
 if(args.includes("--repo-list"))console.log("core\ncustom");
 else if(args.includes("Server")&&!fs.existsSync(path.join(root,"server-empty")))console.log("https://user:secret@packages.example.org/$repo/$arch");
 else if(args.includes("SigLevel"))console.log("Required DatabaseOptional");
 else if(args.includes("DBPath"))console.log(path.join(root,"db"));
 else if(args.includes("HookDir"))console.log(path.join(root,"hooks"));
 process.exit(0);
}
if(name==="checkupdates"||args.includes("-Qua")||args.includes("-Qu")){console.log("widget 1 -> "+(fs.existsSync(path.join(root,"pending-changed"))?"3":"2"));process.exit(0);}
if(name==="pacman"||name==="paru"||name==="yay"){
 if(args.includes("-Sl")){console.log("core official 1\n"+(fs.existsSync(path.join(root,"origin-changed"))?"core":"custom")+" widget 2\ncustom aurpkg 2");process.exit(0);}
 if(args.includes("-Si")){console.log("Repository : aur\nName : "+(fs.existsSync(path.join(root,"provider-ambiguous"))?"provider":args.at(-1)));process.exit(0);}
 if(args.includes("-Qoq")){console.log("vgshell-git");process.exit(0);}
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
   fs.writeFileSync(path.join(dir,"PKGBUILD"),"pkgname="+pkg+"\n");
  }
  process.exit(0);
 }
 log("mutation");process.exit(0);
}
if(name==="snapper"){
 if(args.includes("list-configs"))console.log("config,subvolume\nroot,/");else log("snapshot");process.exit(0);
}
if(name==="git"){
 const dest=path.resolve(process.cwd(),args.at(-1));fs.mkdirSync(dest,{recursive:true});
 fs.writeFileSync(path.join(dest,".SRCINFO"),"pkgbase = paru\npkgname = paru\n");fs.writeFileSync(path.join(dest,"PKGBUILD"),"pkgname=paru\n");process.exit(0);
}
if(name==="makepkg"){
 log("mutation");fs.symlinkSync(fs.realpathSync(__filename),path.join(root,"tools/paru"));process.exit(0);
}
if(name==="claude"||name==="codex"){
 log("agent",{cwd:process.cwd(),reviewDir:/The review directory is `([^`]+)`/.exec(args.at(-1))?.[1]});if(fs.existsSync(path.join(root,"agent-failed")))process.exit(4);const prompt=args.at(-1),match=/The review directory is `([^`]+)`/.exec(prompt);
 if(!match)throw new Error("fixture missing review directory");
 console.log("Reviewing package origin and build files as your user.");
 if(!fs.existsSync(path.join(root,"agent-no-verdict"))){
  const flagged=fs.existsSync(path.join(root,"agent-concern"));
  fs.writeFileSync(path.join(match[1],"verdict"),fs.existsSync(path.join(root,"agent-dependency"))?"verdict flagged\nflag dependency Further verification required.\n":fs.existsSync(path.join(root,"agent-malformed"))?"verdict clean\nflag widget conflict\n":flagged?"verdict flagged\nflag widget A source requires further verification.\n":"verdict clean\n",{mode:0o600});
  console.log(flagged?"Review complete: one concern requires your choice.":"Review complete: no concern in the listed packages.");
 }
 process.exit(0);
}
if(name==="fzf"){process.stdout.write("widget\n");process.exit(0);}
throw new Error("fixture unexpected command "+name);
