"use strict";
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process");
const repo=path.resolve(__dirname,"../../.."),node=process.execPath;
function create(root,{choices=["Install without review"],settings={agent:"claude",command:""},agents=true,helper=true}={}){
 fs.mkdirSync(root,{recursive:true});
 for(const dir of ["tools","home","tmp","run","config/vgshell","db/local","hooks"])fs.mkdirSync(path.join(root,dir),{recursive:true,mode:0o700});
 for(const tool of ["bash","python3","readlink","dirname","cat","head","stat","awk","grep","sort","df","uname","findmnt","flock","sleep","mktemp","mkdir","mv","ln","cp","basename","rm","chmod","diff","env","id","date","sed","tail","wc","tr","script","timeout"]){
  const found="/usr/bin/"+tool;fs.accessSync(found,fs.constants.X_OK);fs.symlinkSync(found,path.join(root,"tools",tool));
 }
 fs.symlinkSync(node,path.join(root,"tools/node"));
 for(const tool of ["pacman",...(helper?["paru"]:[]),"pacman-conf","checkupdates","sudo","gum","fzf","git","makepkg","snapper",...(agents?["claude","codex"]:[])])fs.symlinkSync(path.join(__dirname,"command.js"),path.join(root,"tools",tool));
 fs.writeFileSync(path.join(root,"choices.json"),JSON.stringify(choices));fs.writeFileSync(path.join(root,"calls.jsonl"),"");
 const config=path.join(root,"pacman.conf"),include=path.join(root,"included.conf");
 fs.writeFileSync(include,"[core]\nServer=https://packages.example.org\n[custom]\nServer=https://packages.example.org\n");fs.writeFileSync(config,"[options]\nInclude = "+include+"\n");
 fs.mkdirSync(path.join(root,"config/paru"),{recursive:true});fs.writeFileSync(path.join(root,"config/paru/paru.conf"),"[options]\nPacmanConf = "+config+"\n");
 fs.writeFileSync(path.join(root,"config/vgshell/shell.json"),JSON.stringify({version:6,disabledPlugins:["vgs.updates"],packages:{review:settings}}));
 const env={PATH:path.join(root,"tools"),HOME:path.join(root,"home"),XDG_RUNTIME_DIR:path.join(root,"run"),XDG_CONFIG_HOME:path.join(root,"config"),XDG_STATE_HOME:path.join(root,"state"),TMPDIR:path.join(root,"tmp"),LC_ALL:"C",TERM:"xterm-256color",REVIEW_WORLD:root,VGS_TEST_RUN:"1"};
 return {root,config,include,env,owner:path.join(repo,"bin/vgshell-pkg"),calls:()=>fs.readFileSync(path.join(root,"calls.jsonl"),"utf8").trim().split("\n").filter(Boolean).map(l=>JSON.parse(l))};
}
// A helper cache is a Git checkout whose index owns the recipe file set.
// Stage only the fixture's intended cached recipe, before a case plants
// untracked build output or replaces a selected path with a symlink.
function cacheRecipe(world,fixture,base){
 const source=path.join(fixture,"cached");if(!fs.existsSync(source))return null;
 const clone=path.join(world.env.HOME,".cache/paru/clone",base);
 fs.cpSync(source,clone,{recursive:true});
 const env={PATH:"/usr/bin:/bin",HOME:world.env.HOME,GIT_CONFIG_NOSYSTEM:"1",GIT_CONFIG_GLOBAL:"/dev/null",GIT_CONFIG_COUNT:"0"};
 for(const args of [["init","--quiet","--template="],["add","--force","--all","--","."]]){
  const r=cp.spawnSync("/usr/bin/git",["-c","core.hooksPath=/dev/null","-c","core.fsmonitor=false","-C",clone,...args],{env,encoding:"utf8",timeout:30000});
  if(r.error||r.status!==0)throw new Error("fixture cache index: "+(r.error?.message||r.stderr));
 }
 return clone;
}
module.exports={create,cacheRecipe};
