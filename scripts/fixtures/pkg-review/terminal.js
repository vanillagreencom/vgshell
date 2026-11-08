#!/usr/bin/env node
// Source-backed isolated terminal fixture. Package/query/credential stand-ins
// log argv; production admission and UI execute, with no host package action.
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process");
const {create}=require("./world.js");
const [root,manager="pacman",scenario="review",action="upgrade"]=process.argv.slice(2);
const reviewed=manager==="aur"&&action!=="remove";
const choices=!reviewed?[]:scenario==="decline"?["Install without review"]:scenario==="cancel"?["cancel"]:["Review","Use Claude Code"];
const w=create(root,{choices});
const args=["run",action,"--manager",manager,"--config",w.config,...(action==="upgrade"?[]:[manager==="aur"?"foreign":"widget"])];
const r=cp.spawnSync(process.execPath,[w.owner,...args],{env:w.env,stdio:"inherit"});process.exit(r.status===null?1:r.status);
