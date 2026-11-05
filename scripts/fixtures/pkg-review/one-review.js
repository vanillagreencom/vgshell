#!/usr/bin/env node
// One owner prepares a generated-config Updates decision, then consumes its
// AUR upgrade and VGS rebuild. All commands come from the fixture PATH.
"use strict";
const assert=require("node:assert/strict"),fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process");
const [root,owner,scenario,writer=owner]=process.argv.slice(2);
function run(args,entry=owner){const r=cp.spawnSync(process.execPath,[entry,...args],{env,stdio:"inherit"});if(r.status!==0)process.exit(r.status||1);}
const created=cp.spawnSync(process.execPath,[owner,"review-transaction"],{encoding:"utf8"});
if(created.status!==0)throw Error(created.stderr);
const env={...process.env,VGS_PACKAGE_TRANSACTION:created.stdout.trim()};
try{
 const config=path.join(env.VGS_PACKAGE_TRANSACTION,"pacman.conf");
 fs.writeFileSync(config,"Include = "+path.join(root,"pacman.conf")+"\nHookDir = "+path.join(root,"hooks")+"\n",{mode:0o600});
 const request={version:1,mode:"upgrade",action:"upgrade",groups:[{manager:"pacman",names:[],installs:[],ignored:[],config},{manager:"aur",names:[],installs:[],ignored:[],config}],sources:["pacman","aur"],rebuild:["vgshell-git"],config,customAurArgv:null};
 const req=path.join(env.VGS_PACKAGE_TRANSACTION,"request"),result=path.join(env.VGS_PACKAGE_TRANSACTION,"result");
 fs.writeFileSync(req,JSON.stringify(request),{mode:0o600});fs.writeFileSync(result,"",{mode:0o600});
 run(["review","--request",req,"--result",result],writer);
 const reply=JSON.parse(fs.readFileSync(result));
 fs.writeFileSync(path.join(root,"one-review-result.json"),JSON.stringify(reply));
 if(reply.decision!=="proceed")process.exit(0);
 if(scenario==="receipt-format"){
  const record=JSON.parse(fs.readFileSync(path.join(env.VGS_PACKAGE_TRANSACTION,reply.receipt)));
  assert.equal(record.version,1,"receipt-format: receipt version");
  assert.equal(Object.hasOwn(record,"skipped"),false,"receipt-format: unchanged receipt decision fields");
 }
 for(const [action,manager,names] of [["upgrade","pacman",[]],["upgrade","aur",[]],["reinstall","aur",["vgshell-git"]]]){
  if(action==="reinstall"&&reply.skipped.includes("vgshell-git"))continue;
  run(["run",action,"--manager",manager,"--review-receipt",reply.receipt,"--config",config,...(action==="upgrade"&&reply.skipped.length?["--ignore",...reply.skipped]:[]),...names],action==="upgrade"?writer:owner);
 }
}finally{fs.rmSync(env.VGS_PACKAGE_TRANSACTION,{recursive:true,force:true});}
