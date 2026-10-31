#!/usr/bin/env node
"use strict";
const fs=require("node:fs"),path=require("node:path"),args=process.argv.slice(2),root=process.env.REVIEW_WORLD,kind=process.env.PACKAGE_PIPELINE_KIND;
fs.appendFileSync(path.join(root,"calls.jsonl"),JSON.stringify({kind:"updates-entry",args})+"\n");
const custom=kind==="recognized"||kind==="recognized-skip"?"paru -Sua":kind.startsWith("custom")?"paru -Sua --devel":"";
if(args[0]==="pkg"&&args[1]==="detect")console.log(JSON.stringify({primary:{id:"pacman",binary:"pacman"},overlays:fs.existsSync(path.join(root,"tools/paru"))?[{id:"aur",binary:"paru"}]:[],sources:[]}));
else if(args[0]==="plugin"&&args[1]==="settings")console.log(JSON.stringify({aurCommand:custom,snapshot:"auto",trustPluginUpdates:false}));
else if(args[0]==="self"&&args[1]==="status")console.log(JSON.stringify({version:"0.1.0",method:"package",package:"vgshell-git",current:"0.1.0",latest:"0.2.0",behind:true,step:kind==="helper"?"install-helper":"rebuild",reason:null,error:null}));
else if(["plugin","theme"].includes(args[0])&&args[1]==="outdated")console.log("[]");
else if(args[0]==="ipc")console.log("started");
else if(args[0]==="pid")process.exit(69);
else if(args[0]==="plugin"&&args[1]==="rescan")console.log("shell=not-running");
else throw Error("unexpected Updates endpoint "+JSON.stringify(args));
