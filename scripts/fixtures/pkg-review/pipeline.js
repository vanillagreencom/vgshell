#!/usr/bin/env node
// Execute Updates' production pipeline with its real common package owner.
// A private /etc supplies exact configuration. Every package/credential/
// snapshot/agent executable is a stand-in; no host action is delegated.
"use strict";
const fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process");
const [root,kind="existing"]=process.argv.slice(2),repo=path.resolve(__dirname,"../../.."),tree=path.join(root,"pipeline-tree");
fs.mkdirSync(path.join(tree,"bin"),{recursive:true});
fs.symlinkSync(path.join(repo,"bin/lib"),path.join(tree,"bin/lib"));
fs.symlinkSync(path.join(repo,"shell"),path.join(tree,"shell"));
fs.mkdirSync(path.join(root,"etc"));
fs.copyFileSync(path.join(root,"pacman.conf"),path.join(root,"etc/pacman.conf"));fs.writeFileSync(path.join(root,"etc/os-release"),"ID=arch\n");
const wrapper=`#!/usr/bin/bash
if [[ $1 == pkg && $2 != detect ]]; then
  /usr/bin/node -e 'require("fs").appendFileSync(process.argv[1],JSON.stringify({kind:"package-entry",args:process.argv.slice(2)})+"\\n")' "$REVIEW_WORLD/calls.jsonl" "$@"
  shift
  exec ${JSON.stringify(process.execPath)} ${JSON.stringify(path.join(repo,"bin/vgshell-pkg"))} "$@"
fi
exec ${JSON.stringify(process.execPath)} ${JSON.stringify(path.join(__dirname,"pipeline-endpoint.js"))} "$@"
`;
fs.writeFileSync(path.join(tree,"bin/vgshell"),wrapper,{mode:0o755});
fs.mkdirSync(path.join(root,"state/vgshell/updates"),{recursive:true});
fs.writeFileSync(path.join(root,"update.part"),"");
const env={...process.env,PACKAGE_PIPELINE_KIND:kind,VGS_TUI_LIB:path.join(tree,"bin/lib/tui.sh"),VGS_PLUGIN_ID:"vgs.updates",VGS_PLUGIN_DIR:path.join(repo,"shell/plugins/vgs.updates"),VGS_TUI_LOGGED:"1",UPDATES_LOG_PART:path.join(root,"update.part")};
const args=["--unshare-user","--unshare-pid","--unshare-net","--die-with-parent","--ro-bind","/","/","--bind",root,root,"--ro-bind",path.join(root,"etc"),"/etc","--dev-bind","/dev","/dev","--proc","/proc","--","/usr/bin/bash",path.join(repo,"shell/plugins/vgs.updates/tui/update.sh"),"-y"];
const r=cp.spawnSync("/usr/bin/bwrap",args,{env,stdio:"inherit"});process.exit(r.status===null?1:r.status);
