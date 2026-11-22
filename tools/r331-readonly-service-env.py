#!/usr/bin/env python3
"""R331 read-only service env and tracer preflight (no env values printed).

This is not a live injector. It neither opens /proc/<pid>/mem nor sends
signals. stdout contains only allowlisted key names and checksums.
"""
from pathlib import Path
import hashlib
import json
import os
import re
import subprocess
import sys

ENV = Path("/var/systemd/system/env/umediaserver.env")
BACKUP = Path("/var/lib/webosbrew/aleks-dts-r278/installed.env")
ROOT_PLUGIN = "/var/lib/webosbrew/aleks-dts-r278/plugins"


def read(path, size=100000):
    try:
        with path.open("rb") as handle:
            return handle.read(size)
    except OSError:
        return None


def keys(data):
    if data is None:
        return []
    return sorted(set(
        match.group(1).decode("ascii", "ignore")
        for line in data.splitlines()
        if (match := re.match(rb"^([A-Za-z_][A-Za-z0-9_]*)=", line.strip()))
    ))


def bool_env(key, data):
    if not data:
        return False
    prefix = (key + "=").encode("ascii")
    return any(item.startswith(prefix) for item in data.split(b"\0"))


def main():
    if len(sys.argv) != 2 or sys.argv[1] != "snapshot":
        print("RESULT=R331_PREFLIGHT_USAGE")
        return 2
    result = subprocess.run(
        ["systemctl", "show", "umediaserver.service", "-p", "MainPID",
         "-p", "ActiveState", "-p", "EnvironmentFiles", "-p", "FragmentPath",
         "-p", "DropInPaths", "--no-pager"],
        capture_output=True, text=True, timeout=6,
    )
    props = {}
    if result.returncode == 0:
        for line in result.stdout.splitlines():
            if "=" in line:
                key, value = line.split("=", 1)
                props[key] = value
    main_pid = props.get("MainPID", "0")
    pid = int(main_pid) if main_pid.isdigit() else 0
    environ = read(Path("/proc") / str(pid) / "environ", 262144) if pid else None
    actual, installed = read(ENV), read(BACKUP)
    stat = ENV.stat() if actual is not None else None
    actual_sha = hashlib.sha256(actual).hexdigest() if actual is not None else ""
    installed_sha = hashlib.sha256(installed).hexdigest() if installed is not None else ""
    plugins = {}
    for name in ("libgstcooltracer.so", "libgstrstracers.so"):
        path = Path("/usr/lib/gstreamer-1.0") / name
        plugins[name] = path.is_file()
    out = {
        "schema": "aleks-dts-r331-service-preflight-v1",
        "service_active": props.get("ActiveState") == "active",
        "process_pid_present": pid > 0,
        "service_environment_file_registered": ENV.as_posix() in props.get("EnvironmentFiles", ""),
        "systemd_dropins_present": bool(props.get("DropInPaths")),
        "root_env_exists": actual is not None,
        "env_sha256": actual_sha,
        "installed_sha256": installed_sha,
        "env_matches_installed": actual is not None and actual == installed,
        "env_mode": oct(stat.st_mode & 0o777) if stat else "",
        "env_uid": stat.st_uid if stat else -1,
        "env_keys": keys(actual),
        "r278_plugin_path_in_env": ROOT_PLUGIN.encode() in (actual or b""),
        "live_service_has_gst_tracers_key": bool_env("GST_TRACERS", environ),
        "live_service_has_ld_preload_key": bool_env("LD_PRELOAD", environ),
        "live_service_has_gst_plugin_path_key": bool_env("GST_PLUGIN_PATH_1_0", environ),
        "native_tracer_libraries_present": plugins,
        "secrets_or_env_values_recorded": False,
        "runtime_modified": False
    }
    print("R331_SERVICE_ENV_JSON=" + json.dumps(out, sort_keys=True, separators=(",", ":")))
    print("RESULT=R331_SERVICE_ENV_READONLY_PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
