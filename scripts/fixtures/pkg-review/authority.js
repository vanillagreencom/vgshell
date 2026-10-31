#!/usr/bin/env node
// One live transaction owner prepares and consumes production authority.
// Each test changes one source input between those production entry calls.
"use strict";
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process");
const [root,change="none",manager="pacman"]=process.argv.slice(2);
const owner=path.resolve(__dirname,"../../../bin/vgshell-pkg");
const created=cp.spawnSync(process.execPath,[owner,"review-transaction"],{env:process.env,encoding:"utf8"});
if(created.status!==0)throw Error(created.stderr);
const env={...process.env,VGS_PACKAGE_TRANSACTION:created.stdout.trim()};
const config=path.join(root,"pacman.conf"),other=path.join(root,"aur.conf");fs.copyFileSync(config,other);
const linkedConfig=manager==="pacman"?config:other;
if(change==="config-link"||change==="config-link-changed"){fs.renameSync(linkedConfig,linkedConfig+".source");fs.symlinkSync(linkedConfig+".source",linkedConfig);}
const request={version:1,mode:"upgrade",action:"upgrade",groups:[{manager:"pacman",names:[],installs:[],ignored:["input-ignore"],config},{manager:"aur",names:[],installs:[],ignored:[],config:other}],sources:["pacman","aur"],rebuild:["aurpkg"],config:other,customAurArgv:null};
if(change==="recipe")request.rebuild=["foreign"];
const req=path.join(env.VGS_PACKAGE_TRANSACTION,"request"),result=path.join(env.VGS_PACKAGE_TRANSACTION,"result");
for(const [file,value]of [[req,JSON.stringify(request)],[result,""]])fs.writeFileSync(file,value,{flag:"wx",mode:0o600});
function run(args){return cp.spawnSync(process.execPath,[owner,...args],{env,stdio:"inherit"}).status;}
if(run(["review","--request",req,"--result",result])!==0)process.exit(80);
const reply=JSON.parse(fs.readFileSync(result));
if(reply.decision!=="proceed")process.exit(81);
let args=["run","upgrade","--manager",manager,"--review-receipt",reply.receipt,"--config",manager==="pacman"?config:other,...(manager==="pacman"?["--ignore","input-ignore"]:[])];
const replace=(needle,value)=>{const at=args.indexOf(needle);if(at<0)throw Error(needle);args[at]=value;};
switch(change){
 case"none":case"config-link":break;
 case"config-link-changed":fs.copyFileSync(linkedConfig,linkedConfig+".new");fs.appendFileSync(linkedConfig+".new","# changed\n");fs.unlinkSync(linkedConfig);fs.symlinkSync(linkedConfig+".new",linkedConfig);break;
 case"outer":env.VGS_TUI_SUDO_SESSION=String(process.pid);break;
 case"outer-missing":env.VGS_TUI_SUDO_SESSION=String(process.pid);args.splice(args.indexOf("--review-receipt"),2);break;
 case"recipe":fs.appendFileSync(path.join(env.VGS_PACKAGE_TRANSACTION,path.dirname(reply.receipt),"evidence/build/foreign/PKGBUILD"),"# changed\n");break;
 case"consumed":if(run(args)!==0)process.exit(82);break;
 case"manager":replace(manager,manager==="pacman"?"aur":"pacman");break;
 case"action":replace("upgrade","reinstall");args.push("widget");break;
 case"targets":replace("upgrade","install");args.push("widget");break;
 case"config":fs.appendFileSync(manager==="pacman"?config:other,"# changed\n");break;
 case"include":fs.appendFileSync(path.join(root,"included.conf"),"# changed\n");break;
 case"config-path":replace(manager==="pacman"?config:other,path.join(root,"other.conf"));break;
 case"ignore":if(manager==="aur")args.push("--ignore");args.push("new-ignore");break;
 case"origin":fs.writeFileSync(path.join(root,"origin-changed"),"");break;
 case"pending":fs.writeFileSync(path.join(root,"pending-changed"),"");break;
 case"binary":fs.unlinkSync(path.join(root,"tools",manager==="pacman"?"pacman":"paru"));fs.copyFileSync(path.join(__dirname,"command.js"),path.join(root,"tools",manager==="pacman"?"pacman":"paru"));fs.appendFileSync(path.join(root,"tools",manager==="pacman"?"pacman":"paru"),"\n// changed\n");fs.chmodSync(path.join(root,"tools",manager==="pacman"?"pacman":"paru"),0o755);break;
 case"transaction":env.VGS_PACKAGE_TRANSACTION=path.join(root,"run/foreign");fs.mkdirSync(env.VGS_PACKAGE_TRANSACTION,{mode:0o700});break;
 case"missing":replace(reply.receipt,reply.receipt.replace(/[a-f0-9]{48}$/,"a".repeat(48)));break;
 case"unreadable":fs.writeFileSync(path.join(env.VGS_PACKAGE_TRANSACTION,reply.receipt),"{");break;
 case"symlink":{const file=path.join(env.VGS_PACKAGE_TRANSACTION,reply.receipt);fs.renameSync(file,file+".saved");fs.symlinkSync(file+".saved",file);break;}
 default:throw Error(change);
}
const before=fs.readFileSync(path.join(root,"calls.jsonl"),"utf8").split("\n").filter(Boolean).map(JSON.parse).filter(c=>c.kind==="mutation").length;
const code=run(args);
fs.writeFileSync(path.join(root,"authority-result.json"),JSON.stringify({code,before,reply}));
// Prepared siblings remain independent and each consume once.
if(change==="none"&&manager==="pacman"){
 if(run(["run","upgrade","--manager","aur","--review-receipt",reply.receipt,"--config",other])!==0)process.exit(83);
 if(run(["run","reinstall","--manager","aur","--review-receipt",reply.receipt,"--config",other,"aurpkg"])!==0)process.exit(84);
}
process.exit(0);
