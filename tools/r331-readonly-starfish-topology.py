#!/usr/bin/env python3
"""R331: enumerate only sanitized live LG Starfish process topology.

READ ONLY: no attachment, GDB, signals, ptrace, process environment values,
command line arguments, user media data or service changes. Public source
emits a bounded allowlisted JSON snapshot for diagnostic design.
"""
import json
import os
from pathlib import Path
import re
import sys

PROC = Path("/proc")
ALLOWED = {"starfish-media-", "umediaserver", "WebAppMgr", "chrome",
           "audiod", "audiooutputd", "pulseaudio", "sam", "activitymanager"}
ENV_KEYS = ("GST_PLUGIN_PATH_1_0", "GST_REGISTRY_1_0", "GST_TRACERS", "GST_DEBUG",
            "LD_PRELOAD", "ALEKS_DTS_R130_ALLOW_AUTOPLUG", "GST_PLUGIN_SYSTEM_PATH_1_0")
MAP_TOKENS = ("libgstreamer-1.0.so", "libgstbase-1.0.so", "libgstaleksdts16dec.so",
              "libgstaleksdts.so", "libgstaleksdtscaps.so", "libgstcooltracer.so",
              "libgstrstracers.so")
STATUS_RE = re.compile(r"^(?:PPid|Tgid|Uid|State):\s*(.*)$", re.M)
MAX_PIDS = 16384
MAX_PROC_BYTES = 1400000


def safe_read(path, limit=400):
    try:
        with path.open("rb") as f:
            return f.read(limit)
    except OSError:
        return b""


def name_of(pid):
    if not isinstance(pid, int) or pid <= 0:
        return "UNKNOWN"
    name = safe_read(PROC / str(pid) / "comm", 80).decode("ascii", "replace").strip()
    return name if name in ALLOWED else "OTHER"


def proc_status(pid):
    result = {}
    raw = safe_read(PROC / str(pid) / "status", 5000).decode("ascii", "replace")
    for line in raw.splitlines():
        match = STATUS_RE.match(line)
        if not match:
            continue
        key = line.split(":", 1)[0]
        if key in ("PPid", "Tgid", "Uid"):
            number = match.group(1).split()[0]
            if number.isdigit():
                result[key.lower()] = int(number)
        elif key == "State":
            result["running_state"] = match.group(1)[:1]
    return result


def env_names(pid):
    raw = safe_read(PROC / str(pid) / "environ", 262144)
    if not raw:
        return {"readable": False, "keys_present": []}
    present = set()
    for item in raw.split(b"\0")[:10000]:
        if b"=" not in item:
            continue
        name = item.split(b"=", 1)[0].decode("ascii", "ignore")
        if name in ENV_KEYS:
            present.add(name)
    return {"readable": True, "keys_present": sorted(present)}


def mapped(pid):
    raw = safe_read(PROC / str(pid) / "maps", MAX_PROC_BYTES)
    if not raw:
        return {"readable": False, "library_presence": {}}
    ascii_maps = raw.decode("ascii", "replace")
    return {"readable": True,
            "library_presence": {item: (item in ascii_maps) for item in MAP_TOKENS}}


def main():
    if len(sys.argv) != 2 or sys.argv[1] != "snapshot":
        print("RESULT=R331_USAGE")
        return 2
    try:
        children = list(PROC.iterdir())[:MAX_PIDS]
    except OSError:
        print("RESULT=R331_PROC_UNAVAILABLE")
        return 2
    items = []
    for entry in children:
        if not entry.name.isdigit():
            continue
        pid = int(entry.name)
        comm = name_of(pid)
        if comm not in ALLOWED:
            continue
        status = proc_status(pid)
        ancestors = []
        parent = status.get("ppid", 0)
        for _ in range(5):
            if parent <= 0:
                break
            ancestors.append(name_of(parent))
            parent = proc_status(parent).get("ppid", 0)
        items.append({
            "type": comm,
            "pid": pid,
            "parent": ancestors,
            "status": status,
            "environment": env_names(pid),
            "maps": mapped(pid),
        })
    ptrace = safe_read(PROC / "sys" / "kernel" / "yama" / "ptrace_scope", 20)
    scope = ptrace.decode("ascii", "replace").strip()
    if scope not in ("0", "1", "2", "3"):
        scope = "UNAVAILABLE"
    out = {
        "schema": "aleks-dts-r331-starfish-topology-v1",
        "processes": items[:40],
        "ptrace_scope": scope,
        "user_media_or_environment_values_included": False,
        "process_attached": False,
        "service_changes": False,
    }
    print("R331_TOPOLOGY_JSON=" + json.dumps(out, sort_keys=True, separators=(",", ":")))
    print("RESULT=R331_LIVE_TOPOLOGY_READONLY_PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
