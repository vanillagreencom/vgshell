"use strict";
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process");
const repo=path.resolve(__dirname,"../../.."),node=process.execPath;
const owned=new Set();
// Every elevator and credential-drop command a package step or review can
// run, read from the table that owns them, with the members it must hold.
// Read once, when the first world is built: a stand-in that loads this file
// only for cloneRecipe or git never builds one.
let elevation=null;
function elevationCommands(){
 if(elevation!==null)return elevation;
 const managers=require("../../../bin/lib/qml-library.js").load(path.join(repo,"shell/Core/PackageManagers.js"));
 const commands=[...new Set(managers.ELEVATORS.concat(managers.ELEVATORS.map(elevator=>managers.CREDENTIAL_DROPS[elevator]).filter(drop=>drop!==null).map(drop=>drop.argv[0])))];
 if(!["sudo","doas","run0","pkcheck"].every(command=>commands.includes(command)))throw Error("fixture elevation commands incomplete: "+commands.join(","));
 return elevation=commands;
}
process.once("exit",()=>{for(const folder of owned)fs.rmSync(folder,{recursive:true,force:true});});
function git(dir,...args){
 const result=cp.spawnSync("/usr/bin/git",["-c","core.hooksPath=/dev/null","-c","core.fsmonitor=false","-C",dir,...args],{
  env:{PATH:"/usr/bin:/bin",HOME:dir,GIT_CONFIG_NOSYSTEM:"1",GIT_CONFIG_GLOBAL:"/dev/null",GIT_CONFIG_COUNT:"0",GIT_AUTHOR_NAME:"Fixture",GIT_AUTHOR_EMAIL:"fixture@example.invalid",GIT_COMMITTER_NAME:"Fixture",GIT_COMMITTER_EMAIL:"fixture@example.invalid"},encoding:"utf8",timeout:30000});
 if(result.error||result.status!==0)throw Error("fixture git: "+(result.error?.message||result.stderr));
 return result.stdout.trim();
}
function protectedParent(){
 for(const name of fs.readdirSync("/run/user")){
  const candidate=path.join("/run/user",name),stat=fs.lstatSync(candidate);
  if(!stat.isDirectory()||stat.uid!==process.getuid())continue;
  try{fs.accessSync(candidate,fs.constants.W_OK|fs.constants.X_OK);return candidate;}catch(error){if(error.code!=="EACCES"&&error.code!=="EROFS")throw error;}
 }
 throw Error("fixture protected runtime parent unavailable");
}
// A world with a helper links the host's git. There only the review's
// snapshot copy runs git, and the stand-in would forward each call unchanged
// at the cost of a node start. The world's environment keeps that git on
// this world's files: no system or global configuration, and the file
// transport alone (git(1) GIT_ALLOW_PROTOCOL). A world without a helper
// bootstraps paru through the stand-in's git clone, and a suite that reads
// git calls keeps the stand-in with gitStandIn.
function create(root,{choices=["Install without review"],settings={agent:"claude",command:""},agents=true,helper=true,gitStandIn=!helper}={}){
 fs.mkdirSync(root,{recursive:true});
 // Codex can write /tmp. Keep build clones and owner results outside it,
 // even when a suite's disposable outer world is under /tmp.
 const runtimeParent=protectedParent();
 const protectedRoot=fs.mkdtempSync(path.join(runtimeParent,"vgs-review-fixture-"));owned.add(protectedRoot);
 for(const dir of ["tools","home","tmp","config/vgshell","db/local","hooks","state","data"])fs.mkdirSync(path.join(root,dir),{recursive:true,mode:0o700});
 fs.mkdirSync(path.join(protectedRoot,"runtime"),{mode:0o700});
 fs.mkdirSync(path.join(protectedRoot,"cache"),{mode:0o700});fs.symlinkSync(path.join(protectedRoot,"cache"),path.join(root,"cache"));
 fs.symlinkSync(path.join(protectedRoot,"runtime"),path.join(root,"run"));
 fs.symlinkSync(protectedRoot,path.join(root,"protected"));
 for(const tool of ["bash","python3","readlink","dirname","cat","head","stat","awk","grep","sort","df","uname","findmnt","flock","sleep","mktemp","mkdir","mv","ln","cp","basename","rm","chmod","diff","env","id","date","sed","tail","wc","tr","script","timeout",...(gitStandIn?[]:["git"])]){
  const found="/usr/bin/"+tool;fs.accessSync(found,fs.constants.X_OK);fs.symlinkSync(found,path.join(root,"tools",tool));
 }
 fs.symlinkSync(node,path.join(root,"tools/node"));
 for(const tool of ["pacman",...(helper?["paru"]:[]),"pacman-conf","checkupdates",...elevationCommands(),"gum","fzf",...(gitStandIn?["git"]:[]),"makepkg","snapper",...(agents?["claude","codex"]:[])])fs.symlinkSync(path.join(__dirname,"command.js"),path.join(root,"tools",tool));
 fs.writeFileSync(path.join(root,"choices.json"),JSON.stringify(choices));fs.writeFileSync(path.join(root,"calls.jsonl"),"");
 const config=path.join(root,"pacman.conf"),include=path.join(root,"included.conf");
 fs.writeFileSync(include,"[core]\nServer=https://packages.example.org\n[custom]\nServer=https://packages.example.org\n");fs.writeFileSync(config,"[options]\nInclude = "+include+"\n");
 fs.mkdirSync(path.join(root,"config/paru"),{recursive:true});fs.writeFileSync(path.join(root,"config/paru/paru.conf"),"[options]\nPacmanConf = "+config+"\n");
 fs.writeFileSync(path.join(root,"config/vgshell/shell.json"),JSON.stringify({version:6,disabledPlugins:["vgs.updates"],packages:{review:settings}}));
 const env={PATH:path.join(root,"tools"),HOME:path.join(root,"home"),XDG_RUNTIME_DIR:path.join(protectedRoot,"runtime"),XDG_CONFIG_HOME:path.join(root,"config"),XDG_STATE_HOME:path.join(root,"state"),XDG_DATA_HOME:path.join(root,"data"),XDG_CACHE_HOME:path.join(protectedRoot,"cache"),TMPDIR:path.join(root,"tmp"),LC_ALL:"C",TERM:"xterm-256color",REVIEW_WORLD:root,VGS_TEST_RUN:"1",...(gitStandIn?{}:{GIT_CONFIG_NOSYSTEM:"1",GIT_CONFIG_GLOBAL:"/dev/null",GIT_ALLOW_PROTOCOL:"file"})};
 standInsOnly(env);
 return {root,protectedRoot,config,include,env,owner:path.join(repo,"bin/vgshell-pkg"),calls:()=>fs.readFileSync(path.join(root,"calls.jsonl"),"utf8").trim().split("\n").filter(Boolean).map(l=>JSON.parse(l))};
}
// The review drops saved authorizations before an agent starts
// (PackageManagers.CREDENTIAL_DROPS). A world reaches only stand-ins for
// each elevator and drop command, never the host's, which would end the
// live session's authorizations.
function standInsOnly(env){
 const standIn=fs.realpathSync(path.join(__dirname,"command.js"));
 for(const command of elevationCommands()){
  const found=env.PATH.split(":").map(dir=>path.join(dir,command)).find(file=>{try{fs.accessSync(file,fs.constants.X_OK);return true;}catch(_){return false;}});
  if(found===undefined||fs.realpathSync(found)!==standIn)throw Error("fixture world reaches "+(found||"no")+" "+command+", not its stand-in");
 }
}
function cloneRecipe(world,base,{source,names=[base],depends=[],script=null}={}){
 const clone=path.join(world.protectedRoot,"clones",base);fs.mkdirSync(clone,{recursive:true,mode:0o700});
 if(source)fs.cpSync(source,clone,{recursive:true});
 else{
  fs.writeFileSync(path.join(clone,"PKGBUILD"),"pkgname="+base+"\npkgver=1\n");
  fs.writeFileSync(path.join(clone,".SRCINFO"),"pkgbase = "+base+"\n"+depends.map(dep=>"depends = "+dep+"\n").join("")+(script?"install = package.install\n":"")+names.map(name=>"pkgname = "+name+"\n").join(""));
  if(script)fs.writeFileSync(path.join(clone,"package.install"),script);
 }
 git(clone,"init","--quiet","--template=");git(clone,"add","--force","--all","--",".");git(clone,"commit","--quiet","-m","recipe");
 fs.mkdirSync(path.join(clone,"src/build-output"),{recursive:true});fs.writeFileSync(path.join(clone,"src/build-output/untracked"),"BUILD_OUTPUT_NOT_RECIPE");
 fs.mkdirSync(path.join(clone,"pkg"));fs.writeFileSync(path.join(clone,base+"-1-x86_64.pkg.tar.zst"),"BUILT_PACKAGE_NOT_RECIPE");
 return clone;
}
module.exports={create,cloneRecipe,git,protectedParent};
