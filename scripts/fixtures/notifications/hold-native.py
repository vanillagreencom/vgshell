#!/usr/bin/env python3
"""Observe the real private graph and signal only an acquired shell writer.

The deadline uses comment 7c7e9c13's started/first-hold origin window.
Requests sleep 10 ms between reads; receipt times retain the measured
sampling intervals and every silent unlink/relink sample.
"""
import json
import copy
import os
from pathlib import Path
import signal
import subprocess
import sys
import time


class DeadlineFailure(AssertionError):
    def __init__(self, kind):
        self.kind = kind
        super().__init__("deadline stream reaches real output within hold bound" if kind == "no-release" else "deadline-bracket:" + kind)


def active_snapshot(snapshot):
    return (snapshot["state"] == "linked" and bool(snapshot["nodes"]) and bool(snapshot["links"])
            and all(n["state"] == "running" for n in snapshot["nodes"])
            and all(link["info"].get("state") == "active" for link in snapshot["links"]))


def deadline_judge(record):
    """The sole row/offline judge for comment 7c7e9c13's replacement contract."""
    def require(condition, kind):
        if not condition:
            raise DeadlineFailure(kind)
    samples = record["readings"]
    require(record["acquired"] and samples, "stream-unacquired")
    require(record["guardsChecked"] == len(samples), "lease-or-adoption-unproved")
    require(record["firstHold"] is not None, "never-held")
    require(all(a["at"] < b["at"] for a, b in zip(samples, samples[1:])), "sample-order")
    earliest = record["started"] + record["deadlineSeconds"]
    nominal = record["firstHold"] + record["deadlineSeconds"]
    require(record["started"] <= record["firstHold"], "origin-order")

    def classify(sample):
        prior = [s for s in record["snapshots"] if s["at"] <= sample["at"]]
        if not prior:
            return "unproved"
        snapshot = prior[-1]
        if active_snapshot(snapshot):
            if sample["targets"] == ["vgs-notification-mute-hold"]:
                return "held"
            if sample["targets"] == ["vgs-smoke-speakers"]:
                return "audible"
        if (sample["targets"] == [] and snapshot["state"] == "unlinked"
                and snapshot["nodes"] and not snapshot["links"]
                and all(n["state"] == "idle" for n in snapshot["nodes"])):
            return "silent"
        return "unproved"

    states = [classify(sample) for sample in samples]
    muted = [i for i, state in enumerate(states) if state == "held"]
    real = [i for i, state in enumerate(states) if state == "audible"]
    require(bool(muted), "active-mute-unproved")
    require(all(samples[i]["at"] >= earliest for i in real), "early-release")
    if not real:
        require(all(state == "held" for state in states[muted[0]:]), "control-not-muted-throughout")
        require(samples[-1]["at"] >= nominal, "observation-too-short")
        raise DeadlineFailure("no-release")
    first_real = real[0]
    require(muted[0] < first_real and all(state in ("held", "silent")
            for state in states[muted[0]:first_real]), "hold-transition-unproved")
    require(all(i < first_real for i in muted), "audible-gap")
    first_real_at = samples[first_real]["at"]
    interval = first_real_at - samples[first_real - 1]["at"]
    require(first_real_at <= nominal + interval, "late-release")
    # The sample immediately before audible output can be silent: stock
    # WirePlumber unlinks the destroyed sink before its queued relink.
    return {"earliest": earliest, "nominal": nominal,
            "originWindow": record["firstHold"] - record["started"],
            "lastMute": samples[muted[-1]]["at"], "firstActiveReal": first_real_at,
            "measuredInterval": interval, "afterDeadline": first_real_at - nominal,
            "crossingSamples": [{**samples[i], "classification": states[i]}
                                for i in range(muted[-1], first_real + 1)]}


def graph():
    result = subprocess.run(["pw-dump"], capture_output=True, text=True, timeout=5, check=True)
    return json.loads(result.stdout)


def metadata(objects, name, key):
    stores = [o for o in objects if o.get("type") == "PipeWire:Interface:Metadata"
              and o.get("props", {}).get("metadata.name") == name]
    assert len(stores) == 1, ("metadata-store", name, len(stores))
    return next((m.get("value") for m in stores[0].get("metadata", [])
                 if m.get("subject") == 0 and m.get("key") == key), None)


def targets(objects, name):
    nodes = {o["id"]: o.get("info", {}).get("props", {}) for o in objects
             if o.get("type") == "PipeWire:Interface:Node"}
    streams = [node_id for node_id, props in nodes.items() if props.get("node.name") == name]
    if not streams:
        return []
    assert len(streams) == 1, "unique test stream"
    return sorted({nodes.get(o["info"]["props"].get("link.input.node"), {}).get("node.name")
                   for o in objects if o.get("type") == "PipeWire:Interface:Link"
                   and o["info"]["props"].get("link.output.node") == streams[0]})


def exact_stream(objects, name, pid):
    """Keep only the created player's Nodes/Links, including mapping failures."""
    clients = {o["id"] for o in objects if o.get("type") == "PipeWire:Interface:Client"
               and str(o.get("info", {}).get("props", {}).get("pipewire.sec.pid")) == str(pid)}
    candidates = []
    for obj in objects:
        if obj.get("type") != "PipeWire:Interface:Node":
            continue
        info = obj.get("info") or {}
        props = info.get("props") or {}
        if (props.get("node.name") == name or str(props.get("application.process.id")) == str(pid)
                or props.get("client.id") in clients):
            candidates.append({"id": obj["id"], "state": info.get("state"), "error": info.get("error"), "props": props})
    ids = {n["id"] for n in candidates}
    links = []
    for obj in objects:
        if obj.get("type") != "PipeWire:Interface:Link":
            continue
        info = obj.get("info") or {}
        props = info.get("props") or {}
        if props.get("link.output.node") in ids or info.get("output-node-id") in ids:
            links.append({"id": obj["id"], "info": info})
    named = [n for n in candidates if n["props"].get("node.name") == name]
    state = "missing" if not candidates else "mapping-failure" if len(named) != 1 else "unlinked" if not links else "linked"
    return {"state": state, "player": pid, "expectedName": name, "nodes": candidates, "links": links}


def writer(action, shell_pid):
    hold = metadata(graph(), "vgs-notification-hold", "hold")
    assert isinstance(hold, dict), "actual hold required"
    pid = hold["pid"]
    fd = os.pidfd_open(pid)
    try:
        # Opening first holds this generation even if it exits during the
        # ownership read. pidfd_send_signal cannot hit a reused process ID.
        info = Path("/proc/self/fdinfo/" + str(fd)).read_text()
        assert "Pid:\t" + str(pid) + "\n" in info, "live acquired pidfd"
        assert Path("/proc/" + str(pid) + "/exe").resolve().name == "pw-cli", "writer executable"
        status = Path("/proc/" + str(pid) + "/status").read_text().splitlines()
        assert next(s.split()[1] for s in status if s.startswith("PPid:")) == shell_pid, "writer belongs to shell"
        if action == "kill-writer":
            signal.pidfd_send_signal(fd, signal.SIGKILL)
        print(json.dumps({"pid": pid, "deadlineMs": hold["deadlineMs"], "acquired": True, "action": action}))
    finally:
        os.close(fd)


def rehold_record(log, offset, capture_status, started, ended, result, status):
    """Record state next to an unsuccessful audio read, never a later retry."""
    def serial(props):
        value = props.get("object.serial")
        return str(value) if value is not None else None

    record = {"audio": {"startMs": int(started), "endMs": int(ended),
                        "result": result, "status": int(status)}}
    try:
        with open(log, "rb") as source:
            source.seek(int(offset))
            lines = source.read().decode("utf-8").splitlines()
        samples = [json.loads(line.split("VGS_APP_SOUND_READ ", 1)[1])
                   for line in lines if "VGS_APP_SOUND_READ " in line]
        if capture_status != "ok" or len(samples) != 1:
            raise ValueError("capture=" + capture_status + " records=" + str(len(samples)))
        record["shell"] = samples[0]
    except (OSError, ValueError, UnicodeError) as error:
        record["shell"] = {"status": "unavailable", "error": str(error)}
    native = {"startMs": time.time_ns() // 1000000}
    try:
        objects = graph()
        native["endMs"] = time.time_ns() // 1000000
        native["status"] = "available"
        for field, store, key in (("exact", "vgs-notification-hold", "hold"),
                                  ("effectiveStreams", "vgs-notification-sounds", "held")):
            try:
                native[field] = metadata(objects, store, key)
            except AssertionError as error:
                native[field] = {"status": "unavailable", "error": str(error)}
        hold = native["exact"]
        if isinstance(hold, dict) and "pid" in hold:
            native["visibleHolder"] = [
                {"id": o["id"], "pid": o["info"]["props"].get("pipewire.sec.pid"),
                 "serial": serial(o["info"]["props"])}
                for o in objects if o.get("type") == "PipeWire:Interface:Client"
                and str(o.get("info", {}).get("props", {}).get("pipewire.sec.pid")) == str(hold["pid"])]
        else:
            native["visibleHolder"] = {"status": "unavailable", "error": "no holder pid"}
        nodes = {o["id"]: o.get("info", {}).get("props", {}) for o in objects
                 if o.get("type") == "PipeWire:Interface:Node"}
        target_ids = [node_id for node_id, props in nodes.items()
                      if props.get("node.name") == "smoke-ping-held"]
        native["stream"] = [{"id": node_id, "serial": serial(nodes[node_id])}
                            for node_id in target_ids]
        native["muteRoute"] = {
            "targets": targets(objects, "smoke-ping-held"),
            "muteNodes": [{"id": node_id, "serial": serial(props)}
                          for node_id, props in nodes.items()
                          if props.get("node.name") == "vgs-notification-mute-hold"],
            "links": [{"id": o["id"], "state": o.get("info", {}).get("state"),
                       "output": o["info"]["props"].get("link.output.node"),
                       "input": o["info"]["props"].get("link.input.node")}
                      for o in objects if o.get("type") == "PipeWire:Interface:Link"
                      and o.get("info", {}).get("props", {}).get("link.output.node") in target_ids]}
    except (AssertionError, OSError, subprocess.SubprocessError, ValueError, KeyError, TypeError) as error:
        native.update(status="unavailable", error=str(error), endMs=time.time_ns() // 1000000)
    record["native"] = native
    print(json.dumps(record, separators=(",", ":")))


def stream(mode, tone, evidence):
    name = "vgs-revision2-" + mode
    started = time.monotonic()
    player = subprocess.Popen(["pw-cat", "--playback", "--target", "vgs-smoke-speakers", "--volume", "0.5",
                               "-P", '{ media.role = "Notification" application.name = "Revision2" node.name = "' + name + '" }', tone],
                              stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    readings = []
    first_hold = None
    deadline = None
    lease_fd = None
    acquired = False
    snapshots = []
    previous_snapshot = None
    guard_checks = 0

    def receipt():
        return {"mode": mode, "started": started, "firstHold": first_hold,
                "deadlineSeconds": deadline, "acquired": acquired,
                "playerArgv": player.args, "guardsChecked": guard_checks,
                "snapshots": snapshots, "readings": readings}
    try:
        initial = graph()
        hold = metadata(initial, "vgs-notification-hold", "hold")
        assert isinstance(hold, dict), "daemon hold survives"
        deadline = hold["deadlineMs"] / 1000
        if mode == "deadline":
            lease_fd = os.pidfd_open(hold["pid"])
        while time.monotonic() - started < deadline + 5:
            objects = graph()
            now = time.monotonic()
            output = targets(objects, name)
            snapshot = exact_stream(objects, name, player.pid)
            # Bound retained diagnostics to sixteen changes in this exact
            # player's graph, never a graph-wide capture.
            if snapshot != previous_snapshot and len(snapshots) < 16:
                snapshots.append({"at": now, **snapshot})
                previous_snapshot = snapshot
            if snapshot["state"] == "mapping-failure":
                raise AssertionError("player stream mapping failed")
            acquired = acquired or snapshot["state"] in ("unlinked", "linked")
            readings.append({"at": now, "targets": output})
            assert player.poll() is None, "continuously playing stream remains alive"
            if mode == "restart":
                if output:
                    assert acquired, "actual player stream is acquired"
                    assert output == ["vgs-notification-mute-hold"], "restart chime routes to mute hold before shell event"
                    print("held")
                    return
            elif mode == "lease":
                if output:
                    assert acquired, "actual player stream is acquired"
                    assert output == ["vgs-smoke-speakers"], "dead acquired lease routes new chime to real output"
                    print("real")
                    return
            else:
                signal.pidfd_send_signal(lease_fd, 0)
                current = metadata(objects, "vgs-notification-hold", "hold")
                serials = [str(o.get("info", {}).get("props", {}).get("object.serial")) for o in objects
                           if o.get("type") == "PipeWire:Interface:Node"
                           and o.get("info", {}).get("props", {}).get("node.name") == name]
                assert all(s not in current["streams"] and s not in current["released"] for s in serials), "missed frame leaves this rule hold unadopted"
                guard_checks += 1
                if output == ["vgs-notification-mute-hold"]:
                    if first_hold is None:
                        first_hold = now
                elif output == ["vgs-smoke-speakers"]:
                    if active_snapshot(snapshot):
                        bracket = deadline_judge(receipt())
                        print("deadline-bracket=" + json.dumps(bracket, sort_keys=True))
                        print("bounded")
                        return
                elif output:
                    raise AssertionError(("unexpected-target", output))
            time.sleep(0.01)
        assert acquired, "actual player stream is acquired"
        if mode == "deadline":
            deadline_judge(receipt())
        raise AssertionError("deadline stream reaches real output within hold bound" if mode == "deadline" else "stream obtains required route")
    finally:
        player.terminate()
        player.wait(timeout=5)
        player_error = player.stderr.read().decode(errors="replace")
        if lease_fd is not None:
            os.close(lease_fd)
        recorded = receipt()
        recorded["playerStderr"] = player_error[-32768:]
        Path(evidence).write_text(json.dumps(recorded, indent=2) + "\n")


# Minimal projections of the real c-only receipts, preserving their observed
# active-state/crossing boundaries (cachy, 2026-11-01, unit
# VGS-2127-c-only-1793545406). Synthetic changes below are controls only.
# deadline-actual.json SHA256 665c6a386dce950287df43ccd7ca9d60001f28a70540d797b7b299ca96c60ec8
RECORDED_ACTUAL = {'acquired': True,
 'started': 54941.457294883,
 'firstHold': 54941.469732385,
 'deadlineSeconds': 15.0,
 'readings': [{'at': 54941.469732385, 'targets': ['vgs-notification-mute-hold']},
              {'at': 54941.486111982, 'targets': ['vgs-notification-mute-hold']},
              {'at': 54956.464851313, 'targets': ['vgs-notification-mute-hold']},
              {'at': 54956.481280904, 'targets': ['vgs-smoke-speakers']}],
 'guardsChecked': 4,
 'snapshots': [{'at': 54941.469732385,
                'state': 'linked',
                'nodes': [{'state': 'suspended'}],
                'links': [{'info': {'state': 'negotiating'}}, {'info': {'state': 'negotiating'}}]},
               {'at': 54941.486111982,
                'state': 'linked',
                'nodes': [{'state': 'running'}],
                'links': [{'info': {'state': 'active'}}, {'info': {'state': 'active'}}]},
               {'at': 54956.481280904,
                'state': 'linked',
                'nodes': [{'state': 'running'}],
                'links': [{'info': {'state': 'active'}}, {'info': {'state': 'active'}}]}]}
# deadline-control.json SHA256 ad7183dd09f1d5cd574b78d825248fd171e7070bc239da2e88052e55d246501b
RECORDED_CONTROL = {'acquired': True,
 'started': 54957.044766613,
 'firstHold': 54957.057652649,
 'deadlineSeconds': 15.0,
 'readings': [{'at': 54957.057652649, 'targets': ['vgs-notification-mute-hold']},
              {'at': 54957.073515523, 'targets': ['vgs-notification-mute-hold']},
              {'at': 54977.025762361, 'targets': ['vgs-notification-mute-hold']},
              {'at': 54977.043122391, 'targets': ['vgs-notification-mute-hold']}],
 'guardsChecked': 4,
 'snapshots': [{'at': 54957.057652649,
                'state': 'linked',
                'nodes': [{'state': 'suspended'}],
                'links': [{'info': {'state': 'negotiating'}}, {'info': {'state': 'negotiating'}}]},
               {'at': 54957.073515523,
                'state': 'linked',
                'nodes': [{'state': 'running'}],
                'links': [{'info': {'state': 'active'}}, {'info': {'state': 'active'}}]}]}


# Projection of the actual silent crossing in failed receipt
# 1793563891483789512-8006, closure/notification-hold.uUCXho/deadline-actual.json.
# This is an input to the replacement contract, not a rejudgement of that receipt.
RECORDED_STAGED = {
    "acquired": True, "started": 80677.375863953, "firstHold": 80677.388435538,
    "deadlineSeconds": 15.0, "guardsChecked": 4,
    "readings": [
        {"at": 80677.404326714, "targets": ["vgs-notification-mute-hold"]},
        {"at": 80692.368279273, "targets": ["vgs-notification-mute-hold"]},
        {"at": 80692.384892226, "targets": []},
        {"at": 80692.401056806, "targets": ["vgs-smoke-speakers"]}],
    "snapshots": [
        {"at": 80677.404326714, "state": "linked", "nodes": [{"state": "running"}],
         "links": [{"info": {"state": "active"}}]},
        {"at": 80692.384892226, "state": "unlinked", "nodes": [{"state": "idle"}], "links": []},
        {"at": 80692.401056806, "state": "linked", "nodes": [{"state": "running"}],
         "links": [{"info": {"state": "active"}}]}]}


def deadline_judge_controls():
    cases = [("direct-crossing", RECORDED_ACTUAL, None),
             ("silent-crossing", RECORDED_STAGED, None),
             ("no-release", RECORDED_CONTROL, "no-release")]
    value = copy.deepcopy(RECORDED_STAGED)
    earliest = value["started"] + value["deadlineSeconds"]
    value["readings"][1]["at"] = earliest - 0.03
    value["readings"][2]["at"] = earliest - 0.02
    value["snapshots"][1]["at"] = earliest - 0.02
    value["readings"][3]["at"] = earliest - 0.01
    value["snapshots"][2]["at"] = earliest - 0.01
    cases.append(("early-release", value, "early-release"))
    value = copy.deepcopy(RECORDED_ACTUAL)
    value["acquired"] = False
    cases.append(("unacquired", value, "stream-unacquired"))
    value = copy.deepcopy(RECORDED_ACTUAL)
    value["guardsChecked"] = 0
    cases.append(("unproved-guards", value, "lease-or-adoption-unproved"))
    value = copy.deepcopy(RECORDED_ACTUAL)
    value["firstHold"] = None
    cases.append(("never-held", value, "never-held"))
    value = copy.deepcopy(RECORDED_ACTUAL)
    value["readings"][1]["at"] = value["readings"][0]["at"]
    cases.append(("sample-order", value, "sample-order"))
    value = copy.deepcopy(RECORDED_ACTUAL)
    value["started"] = value["firstHold"] + 1
    cases.append(("origin-order", value, "origin-order"))
    value = copy.deepcopy(RECORDED_ACTUAL)
    for snapshot in value["snapshots"][:-1]:
        snapshot["nodes"][0]["state"] = "suspended"
    cases.append(("inactive-mute", value, "active-mute-unproved"))
    value = copy.deepcopy(RECORDED_STAGED)
    value["snapshots"][1]["nodes"][0]["state"] = "running"
    cases.append(("unproved-silence", value, "hold-transition-unproved"))
    value = copy.deepcopy(RECORDED_STAGED)
    value["readings"][-2]["at"] += 1
    value["snapshots"][-2]["at"] += 1
    value["readings"][-1]["at"] += 1
    value["snapshots"][-1]["at"] += 1
    cases.append(("late-release", value, "late-release"))
    value = copy.deepcopy(RECORDED_ACTUAL)
    value["readings"].append({"at": value["readings"][-1]["at"] + 0.01,
                              "targets": ["vgs-notification-mute-hold"]})
    value["guardsChecked"] += 1
    cases.append(("audible-gap", value, "audible-gap"))
    value = copy.deepcopy(RECORDED_CONTROL)
    value["readings"][-1]["targets"] = []
    cases.append(("control-not-muted", value, "control-not-muted-throughout"))
    value = copy.deepcopy(RECORDED_CONTROL)
    value["readings"] = value["readings"][:2]
    value["guardsChecked"] = len(value["readings"])
    cases.append(("short-observation", value, "observation-too-short"))
    checks = []
    for name, value, expected in cases:
        try:
            result = deadline_judge(value)
        except DeadlineFailure as error:
            assert error.kind == expected, (name, error.kind, expected)
        else:
            assert expected is None, ("deadline judge control survived", name)
            assert result["originWindow"] == value["firstHold"] - value["started"]
            assert result["firstActiveReal"] >= value["started"] + value["deadlineSeconds"]
            assert result["firstActiveReal"] <= result["nominal"] + result["measuredInterval"]
            if name == "silent-crossing":
                assert [s["classification"] for s in result["crossingSamples"]] == ["held", "silent", "audible"]
                assert result["crossingSamples"][1]["targets"] == []
        checks.append(name)
    print("deadline-judge-controls=" + json.dumps(checks))


if __name__ == "__main__":
    try:
        if sys.argv[1] == "judge":
            print(json.dumps(deadline_judge(json.loads(Path(sys.argv[2]).read_text())), sort_keys=True))
        elif sys.argv[1] == "judge-controls":
            deadline_judge_controls()
        elif sys.argv[1] in ("kill-writer", "writer"):
            writer(sys.argv[1], sys.argv[2])
        elif sys.argv[1] == "rehold-record":
            rehold_record(*sys.argv[2:])
        else:
            stream(*sys.argv[1:])
    except (AssertionError, OSError, subprocess.SubprocessError, ValueError, KeyError) as error:
        print("hold-native: failed=" + str(error), file=sys.stderr)
        sys.exit(1)
