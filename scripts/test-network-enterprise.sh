#!/usr/bin/env bash
# Run the shipped join owner against private nmcli. Controls leak a secret
# through argv and omit failed-profile cleanup in disposable source copies.
# inputs: shell/plugins/vgs.network/bin/join-network scripts/smoke/fixtures/devices/network-join-nmcli.py
set -euo pipefail
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)" || { echo 'network-enterprise: scratch=mktemp-failed' >&2; exit 1; }
[[ -d $TMP_ROOT && ! -L $TMP_ROOT ]] || { echo 'network-enterprise: scratch=not-a-directory' >&2; exit 1; }
TMP_ROOT="$(cd -- "$TMP_ROOT" && pwd -P)" || { echo 'network-enterprise: scratch=resolve-failed' >&2; exit 1; }
trap 'rm -rf -- "${TMP_ROOT:?}"' EXIT
python3 - "$repo" "$TMP_ROOT" <<'PY'
import hashlib,json,os,pathlib,shlex,signal,subprocess,sys,time,uuid
repo, scratch = map(pathlib.Path,sys.argv[1:])
helper = repo/'shell/plugins/vgs.network/bin/join-network'
fake = repo/'scripts/smoke/fixtures/devices/network-join-nmcli.py'
secret = 'private: pass \\ $(literal)'
fixture = scratch/'world.json'; calls = scratch/'calls'; ready = scratch/'ready'
shim = scratch/'nmcli'
shim.write_text('#!/bin/sh\nexec /usr/bin/python3 '+ ' '.join(shlex.quote(str(p)) for p in [fake,fixture,calls,ready])+' "$@"\n')
shim.chmod(0o700)
env={'PATH':str(scratch)+':/usr/bin:/bin','HOME':str(scratch),'LC_ALL':'C','VGS_TEST_RUN':'1'}
cases=[('psk','','', '802-11-wireless-security.psk', True),('peap','person','auth.example.test','802-1x.password',True),('ttls','person','auth.example.test','802-1x.password',False)]
def world(field,fail=None,hold=None):
    fixture.write_text(json.dumps({'secret_codes':list(map(ord,secret)), 'stdin_digest':hashlib.sha256((field+':'+secret+'\n').encode()).hexdigest(),'fail':fail or {},'hold':hold}))
    calls.unlink(missing_ok=True); ready.unlink(missing_ok=True)
def records():
    return [json.loads(line) for line in calls.read_text().splitlines()] if calls.exists() else []
def run(path,method,identity,domain,hidden):
    p=subprocess.run(['/usr/bin/python3',str(path),'wlan0','A: network \\ $(literal)','yes' if hidden else 'no',method,identity,domain],input=secret,text=True,capture_output=True,env=env,timeout=10)
    assert secret not in p.stdout+p.stderr
    return p,json.loads(p.stdout),records()
def contract(p,result,rows,method,hidden,expect_kind):
    assert result['kind']==expect_kind and p.returncode==(0 if expect_kind=='ok' else 1)
    assert all(not r['argv_secret'] and not r['helper_argv_secret'] for r in rows)
    add=rows[0]['argv']; profile=add[add.index('connection.uuid')+1]
    assert str(uuid.UUID(profile))==profile==result['uuid']
    assert add[add.index('802-11-wireless.hidden')+1]==('yes' if hidden else 'no')
    assert add[add.index('connection.autoconnect')+1]=='no'
    assert add[add.index('ifname')+1]=='wlan0'
    assert add[add.index('ssid')+1]=='A: network \\ $(literal)'
    assert add[add.index('802-11-wireless-security.key-mgmt')+1]==('wpa-psk' if method=='psk' else 'wpa-eap')
    if method!='psk':
        assert add[add.index('802-1x.identity')+1]=='person'
        assert add[add.index('802-1x.eap')+1]==method
        assert add[add.index('802-1x.phase2-auth')+1]==('mschapv2' if method=='peap' else 'pap')
        assert add[add.index('802-1x.system-ca-certs')+1]=='yes'
        assert add[add.index('802-1x.domain-suffix-match')+1]=='auth.example.test'
    up=next(r for r in rows if r['operation']=='up')
    assert up['helper_argv'][2:]==['wlan0','A: network \\ $(literal)','yes' if hidden else 'no',method,'' if method=='psk' else 'person','' if method=='psk' else 'auth.example.test']
    assert up['argv']==['--wait','120','connection','up','uuid',profile,'passwd-file','/dev/stdin'] and up['stdin_ok']
    if expect_kind!='ok':
        assert rows[-1]['argv']==['--wait','5','connection','delete','uuid',profile]
        assert result['cleanup']=='deleted'
        assert profile not in json.loads(fixture.read_text())['profiles']
    else:
        assert not any(r['operation']=='delete' for r in rows) and result['cleanup']=='not-needed'
    return profile
profiles=set()
for method,identity,domain,field,hidden in cases:
    for failure in (None,'failed','refused'):
        world(field, {'up':failure} if failure else {})
        p,result,rows=run(helper,method,identity,domain,hidden)
        profile=contract(p,result,rows,method,hidden,failure or 'ok')
        assert profile not in profiles; profiles.add(profile)
        assert result['phase']=='activate' and result['code']==(4 if failure else 0)
        assert [r['operation'] for r in rows]==(['add','up','delete'] if failure else ['add','up'])
# Refused creation never activates, retries, or runs an authentication agent.
world('802-1x.password',{'add':'refused'})
p,result,rows=run(helper,'peap','person','auth.example.test',False)
assert result['kind']=='refused' and result['phase']=='create' and result['code']==10
assert [r['operation'] for r in rows]==['add']
# A cleanup refusal remains visible in typed output.
world('802-1x.password',{'up':'failed','delete':'refused'})
p,result,rows=run(helper,'peap','person','auth.example.test',False)
assert result['kind']=='failed' and result['cleanup']=='failed'
# A NetworkManager delete that never replies must release the worker.
world('802-1x.password',{'up':'failed'},hold='delete')
p,result,rows=run(helper,'peap','person','auth.example.test',False)
assert p.returncode==1 and result['kind']=='failed' and result['cleanup']=='failed'
assert rows[-1]['argv']==['--wait','5','connection','delete','uuid',result['uuid']]
try: os.kill(int(ready.read_text()),0)
except ProcessLookupError: pass
else: raise AssertionError('cleanup command survived its deadline')
# Both form cancellation and Quickshell's direct-child SIGKILL leave the
# worker responsible for stopping nmcli and deleting its owned UUID.
for stop in (signal.SIGTERM,signal.SIGKILL):
    world('802-1x.password',hold='up')
    p=subprocess.Popen(['/usr/bin/python3',str(helper),'wlan0','Hidden','yes','peap','person','auth.example.test'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,env=env)
    p.stdin.write(secret);p.stdin.close();p.stdin=None
    deadline=time.monotonic()+5
    while not ready.exists() and time.monotonic()<deadline:
        if p.poll() is not None: raise AssertionError('helper exited before acknowledgement')
        time.sleep(.01)
    assert ready.exists()
    p.send_signal(stop)
    out,err=p.communicate(timeout=10)
    result=json.loads(out); rows=records()
    assert p.returncode==(1 if stop==signal.SIGTERM else -signal.SIGKILL)
    assert result['kind']=='canceled' and result['cleanup']=='deleted'
    assert result['uuid'] not in json.loads(fixture.read_text())['profiles']
    assert rows[-1]['argv']==['--wait','5','connection','delete','uuid',result['uuid']]
    assert secret not in out+err
    try: os.kill(int(ready.read_text()),0)
    except ProcessLookupError: pass
    else: raise AssertionError('nmcli child survived')
# Disposable production mutations must violate the same assertions.
source=helper.read_text()
mutations=[('argv', '"passwd-file", "/dev/stdin"],', '"passwd-file", "/dev/stdin", secret],'),('cleanup','if created and not complete:', 'if created and False:'),('network-settings','"con-name", ssid, "ssid", ssid,','"con-name", ssid, "ssid", "wrong-network",')]
for name,old,new in mutations:
    assert source.count(old)==1
    mutant=scratch/('mutant-'+name);mutant.write_text(source.replace(old,new))
    world('802-1x.password',{'up':'failed'})
    p,result,rows=run(mutant,'peap','person','auth.example.test',False)
    try: contract(p,result,rows,'peap',False,'failed')
    except AssertionError: pass
    else: raise AssertionError('control survived: '+name)
    assert secret not in calls.read_text()
    print('network-enterprise: control='+name+' red')
print('network-enterprise: pass')
PY
