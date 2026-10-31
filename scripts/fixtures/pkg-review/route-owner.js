#!/usr/bin/env node
// A test endpoint delegates package admission to the production owner on a
// safe PTY, then asserts offered review, submitted decline and prior argv.
// Route suites keep their own downstream success/failure/postcheck fixtures.
"use strict";
const fs=require("node:fs"),os=require("node:os"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const {create}=require("./world.js");
let args=process.argv.slice(2),owner=null,proof=null,route="package-route";
while(args[0]?.startsWith("--")){
 const key=args.shift(),value=args.shift();
 if(key==="--owner")owner=value;else if(key==="--proof")proof=value;else if(key==="--route")route=value;else throw Error(key);
}
const root=fs.mkdtempSync(path.join(os.tmpdir(),"package-route-"));
try{
 const w=create(root,{choices:["Install without review"]});
 const command=[process.execPath,owner||w.owner,...args].map(s=>"'"+s.replaceAll("'","'\\''")+"'").join(" ");
 const r=cp.spawnSync("/usr/bin/script",["-qec",command,"/dev/null"],{env:{...w.env,SHELL:"/usr/bin/bash"},encoding:"utf8",timeout:30000});
 assert.equal(r.status,0,r.stdout+r.stderr);
 const calls=w.calls(),offer=calls.find(c=>c.kind==="offer");
 assert.ok(offer,"route must enter common offer");assert.equal(offer.choiceIndex,1);
 assert.ok(calls.some(c=>c.kind==="mutation"),"submitted decline must reach prior package plan");
 const firstMutation=calls.findIndex(c=>c.kind==="mutation"),offerAt=calls.indexOf(offer);
 assert.ok(firstMutation>offerAt);
 assert.ok(calls.every((c,i)=>c.kind!=="credential"||i>offerAt));
 if(proof){
  const entry=owner||w.owner,tree=path.dirname(path.dirname(entry)),crypto=require("node:crypto");
  const sources=[entry,path.join(tree,"bin/lib/pkg-review.js"),path.join(tree,"shell/Core/PackageReview.js"),path.join(tree,"shell/Core/PackageManagers.js")].map(file=>({file,sha256:crypto.createHash("sha256").update(fs.readFileSync(file)).digest("hex")}));
  fs.appendFileSync(proof,JSON.stringify({route,args,owner:entry,sources,coverage:"declined",calls:calls.filter(c=>["offer","credential","mutation","agent"].includes(c.kind))})+"\n");
 }
}finally{fs.rmSync(root,{recursive:true,force:true});}
