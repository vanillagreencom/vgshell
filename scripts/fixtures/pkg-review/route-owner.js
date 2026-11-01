#!/usr/bin/env node
// A test endpoint delegates package admission to the production owner on a
// safe PTY. The success surface runs one transaction; the failures surface
// checks the owner's negative cases outside a route's completion timing.
// Route suites keep their own downstream success/failure/postcheck fixtures.
"use strict";
const fs=require("node:fs"),os=require("node:os"),path=require("node:path"),cp=require("node:child_process"),assert=require("node:assert/strict");
const {create}=require("./world.js");
let args=process.argv.slice(2),owner=null,proof=null,route="package-route",surface="all";
while(args[0]?.startsWith("--")){
 const key=args.shift(),value=args.shift();
 if(key==="--owner")owner=value;else if(key==="--proof")proof=value;else if(key==="--route")route=value;else if(key==="--surface")surface=value;else throw Error(key);
}
assert.ok(["all","success","failures"].includes(surface));
const root=fs.mkdtempSync(path.join(os.tmpdir(),"package-route-"));
try{
 const w=create(root,{choices:["Install without review"]});
 let calls=[];
 if(surface!=="failures"){
  const command=[process.execPath,owner||w.owner,...args].map(s=>"'"+s.replaceAll("'","'\\''")+"'").join(" ");
  const r=cp.spawnSync("/usr/bin/script",["-qec",command,"/dev/null"],{env:{...w.env,SHELL:"/usr/bin/bash"},encoding:"utf8",timeout:30000});
  assert.equal(r.status,0,r.stdout+r.stderr);
  calls=w.calls();const offer=calls.find(c=>c.kind==="offer");
  assert.ok(offer,"route must enter common offer");assert.equal(offer.choiceIndex,1);
  assert.ok(calls.some(c=>c.kind==="mutation"),"submitted decline must reach prior package plan");
  const firstMutation=calls.findIndex(c=>c.kind==="mutation"),offerAt=calls.indexOf(offer);
  assert.ok(firstMutation>offerAt);
  assert.ok(calls.every((c,i)=>c.kind!=="credential"||i>offerAt));
 }
 // The same route through a failing build: a check-only failure of the
 // route's first target offers the one retry, Stop selected, only where the
 // route builds an AUR recipe; an ordinary failure offers none. Stop keeps
 // the failure's status for the route's own handling.
 const action=args[0]==="run"?args[1]:args[0],at=args.indexOf("--manager"),manager=at<0?null:args[at+1];
 const builds=manager==="aur"&&["install","reinstall","update"].includes(action);
 const target=args.slice(at<0?(args[0]==="run"?2:1):at+2).find(a=>!a.startsWith("--"));
 const failures=[];
 if(surface!=="success"&&["run","install"].includes(args[0])&&["install","reinstall","update"].includes(action))for(const [kind,first] of [["check-only",{transcript:"paru-check-only",status:1,base:target}],["ordinary",{transcript:"paru-build-fail",status:1,base:target}]]){
  const f=fs.mkdtempSync(path.join(os.tmpdir(),"package-route-failure-"));
  try{
   const fw=create(f,{choices:["Install without review","Stop"]});
   fs.writeFileSync(path.join(f,"build.json"),JSON.stringify({first,pacman:1}));
   const failed=cp.spawnSync("/usr/bin/script",["-qec",[process.execPath,owner||fw.owner,...args].map(s=>"'"+s.replaceAll("'","'\\''")+"'").join(" "),"/dev/null"],{env:{...fw.env,SHELL:"/usr/bin/bash"},encoding:"utf8",timeout:30000});
   const asked=fw.calls().filter(c=>c.kind==="offer"&&c.offered.includes("Retry without tests"));
   assert.equal(failed.status,1,kind+": "+failed.stdout);
   assert.equal(asked.length,kind==="check-only"&&builds?1:0,kind+" retry offer");
   if(asked.length)assert.equal(asked[0].selected,"Stop");
   assert.equal(fw.calls().filter(c=>c.kind==="mutation").length,1,kind+": no automatic retry");
   failures.push({kind,status:failed.status,retryOffered:asked.length===1});
  }finally{fs.rmSync(f,{recursive:true,force:true});}
 }
 if(proof){
  const entry=owner||w.owner,tree=path.dirname(path.dirname(entry)),crypto=require("node:crypto");
  const sources=[entry,path.join(tree,"bin/lib/pkg-review.js"),path.join(tree,"shell/Core/PackageReview.js"),path.join(tree,"shell/Core/PackageManagers.js")].map(file=>({file,sha256:crypto.createHash("sha256").update(fs.readFileSync(file)).digest("hex")}));
  fs.appendFileSync(proof,JSON.stringify({route,args,owner:entry,sources,coverage:surface==="failures"?"failures":"declined",failures,calls:calls.filter(c=>["offer","credential","mutation","agent"].includes(c.kind))})+"\n");
 }
}finally{fs.rmSync(root,{recursive:true,force:true});}
