#!/usr/bin/env python3
"""R340 read-only uMediaServer LS2 pipeline/audio-resource overview on LG.

Only calls two *getters*: /getActivePipelines and /getPipelineState.
Raw replies remain in process memory; URI, appId, mediaId, title, playback
position and arbitrary nested data are never printed, saved or transferred.
No media service restart, logging setup, playback changes or sound generation.
"""
import json
import os
import pty
import re
import select
import signal
import subprocess
import sys
import time

ROOT = "luna://com.webos.media/"
MAX_BYTES = 65536
MAX_PIPELINES = 4
GETTER_TIMEOUT = 4.0
MEDIA_ID = re.compile(r"^_[A-Za-z0-9]{4,64}$")
ALLOWED_STATES = {"play", "pause", "stop", "load", "unload",
                  "MEDIA_PLAY", "MEDIA_PAUSE", "MEDIA_LOAD",
                  "media_loaded", "pipeline_running", "PIPELINE_RUNNING",
                  "PIPELINE_MEDIA_LOADED", "media", "running", "suspended"}
RESOURCE_NAMES = {"ADEC", "AUDIO", "VDEC", "VDEC0", "DISP0", "DISP1"}
ALLOWED_CODECS = {"dts", "dca", "ac3", "eac3", "aac", "pcm", "mp3",
                  "truehd", "DTS", "AC3", "EAC3", "AAC", "PCM"}

def invoke_getter(action, payload):
    assert action in ("getActivePipelines", "getPipelineState")
    master, slave = pty.openpty()
    process = None
    response = bytearray()
    try:
        process = subprocess.Popen(
            ["luna-send", "-n", "1", "-f", ROOT + action,
             json.dumps(payload, separators=(",", ":"))],
            stdin=slave, stdout=slave, stderr=slave,
            close_fds=True, start_new_session=True)
        os.close(slave)
        slave = -1
        deadline = time.monotonic() + GETTER_TIMEOUT
        while time.monotonic() < deadline and len(response) < MAX_BYTES:
            ready, _, _ = select.select([master], [], [],
                min(0.25, max(0.0, deadline - time.monotonic())))
            if ready:
                try:
                    chunk = os.read(master, min(3072, MAX_BYTES-len(response)))
                except OSError:
                    break
                if not chunk:
                    break
                response.extend(chunk)
            if process.poll() is not None and not ready:
                break
    finally:
        if process and process.poll() is None:
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                process.wait(timeout=0.3)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.wait(timeout=0.3)
        if master >= 0:
            os.close(master)
        if slave >= 0:
            os.close(slave)
    return response.decode("utf-8", "replace")

def parse_reply(response, list_expected=False):
    text = re.sub(r"\x1b\[[0-9;]*[A-Za-z]", "", response)
    decoder = json.JSONDecoder()
    candidate = None
    # LS2 CLI may prefix output with status text; decode only complete JSON.
    for idx, token in enumerate(text):
        if token not in "[{":
            continue
        try:
            value, _ = decoder.raw_decode(text[idx:])
        except (ValueError, RecursionError):
            continue
        if list_expected and isinstance(value, list) and all(
                isinstance(item, dict) for item in value):
            candidate = value
            break
        if not list_expected and isinstance(value, dict) and (
                "returnValue" in value or "errorCode" in value):
            candidate = value
            break
    return candidate

def safe_state(x):
    return x if isinstance(x, str) and x in ALLOWED_STATES else "UNKNOWN"

def summarize_pipeline(item):
    resources = item.get("resources", [])
    counts = {}
    if isinstance(resources, list):
        for entry in resources[:32]:
            if isinstance(entry, dict):
                label = entry.get("resource")
                if label in RESOURCE_NAMES:
                    counts[label] = counts.get(label, 0) + 1
    return {
        "managed": item.get("is_managed") if type(item.get("is_managed")) is bool else None,
        "foreground": item.get("is_foreground") if type(item.get("is_foreground")) is bool else None,
        "policy_suspended": item.get("policy_state") if type(item.get("policy_state")) is bool else None,
        "state": safe_state(item.get("mediaState")),
        "process_state": safe_state(item.get("processState")),
        "resource_counts": counts,
    }

def summarize_audio(reply):
    if not isinstance(reply, dict):
        return {"status":"UNAVAILABLE"}
    if reply.get("returnValue") is not True:
        return {"status":"NOT_SUPPORTED",
                "error_code": reply.get("errorCode") if type(reply.get("errorCode")) is int else None}
    raw = reply.get("data")
    if isinstance(raw, str) and len(raw) <= MAX_BYTES:
        try:
            raw = json.loads(raw)
        except (ValueError, RecursionError):
            return {"status":"UNPARSEABLE"}
    if not isinstance(raw, dict):
        return {"status":"NO_STRUCTURED_AUDIO_DATA"}
    info = raw.get("sourceInfo", {})
    streams = info.get("audio_streams", []) if isinstance(info, dict) else []
    out = []
    for stream in streams[:12] if isinstance(streams, list) else []:
        if not isinstance(stream, dict):
            continue
        codec = stream.get("codec")
        if type(codec) is int and 0 <= codec <= 65535:
            coded = codec
        elif isinstance(codec, str) and codec in ALLOWED_CODECS:
            coded = codec
        else:
            coded = "UNKNOWN"
        rate = stream.get("sample_rate")
        out.append({
            "codec": coded,
            "sample_rate": rate if type(rate) is int and 8000<=rate<=192000 else None,
            "channels": stream.get("channels") if type(stream.get("channels")) is int and 1<=stream["channels"]<=8 else None,
        })
    return {
        "status":"OK",
        "media_state":safe_state(raw.get("mediaState")),
        "process_state":safe_state(raw.get("procState")),
        "audio_streams":out,
    }

def selftest():
    resp='echo off\r\n[{"mediaId":"_SecretMediaABCD","uri":"file:///private/film.mkv","appId":"secret","pid":123,"resources":[{"resource":"ADEC","index":2}],"mediaState":"play","processState":"media_loaded","is_managed":true,"is_foreground":true}]'
    parsed=parse_reply(resp,list_expected=True)
    assert len(parsed)==1
    item=summarize_pipeline(parsed[0])
    assert item["resource_counts"]=={"ADEC":1}
    assert item["state"]=="play"
    assert "uri" not in item and "mediaId" not in item and "appId" not in item
    detail={"returnValue":True,"data":json.dumps({
        "sourceInfo":{"audio_streams":[{"codec":"DTS","sample_rate":48000,"channels":6,
            "title":"SECRET","uri":"https://private.invalid/film"}]},
        "mediaId":"_SecretMediaABCD","currentTime":12345,"mediaState":"play"})}
    a=summarize_audio(detail)
    assert a["audio_streams"]==[{"codec":"DTS","sample_rate":48000,"channels":6}]
    assert "title" not in str(a) and "private" not in str(a) and "Secret" not in str(a)
    assert parse_reply('{"returnValue":false,"errorCode":-1}')=={"returnValue":False,"errorCode":-1}
    print("RESULT=R340_PRIVATE_REDACTION_AND_PARSER_SELFTEST_8_PASS")

def main():
    if sys.argv[1:]==["selftest"]:
        selftest();return
    if sys.argv[1:]!=["snapshot"]:
        print("RESULT=R340_USAGE");raise SystemExit(2)
    raw=parse_reply(invoke_getter("getActivePipelines",{}),list_expected=True)
    if raw is None:
        obj={"schema":"aleks-dts-r340-ums-readonly-v1",
             "status":"NO_SUPPORTED_PIPELINE_ARRAY",
             "mutated":False,"media_identifiers_exported":False}
    else:
        items=[]
        for p in raw[:MAX_PIPELINES]:
            v=summarize_pipeline(p)
            ident=p.get("mediaId") or p.get("id")
            if isinstance(ident,str) and MEDIA_ID.fullmatch(ident):
                v["detail"]=summarize_audio(parse_reply(
                    invoke_getter("getPipelineState", {"mediaId": ident})))
            else:
                v["detail"]={"status":"NO_VALID_ID"}
            items.append(v)
        obj={"schema":"aleks-dts-r340-ums-readonly-v1",
             "status":"OK","reported_pipeline_count":len(raw),
             "pipelines":items,
             "mutated":False,"media_identifiers_exported":False}
    print("R340_UMS_SANITIZED="+json.dumps(obj,sort_keys=True,separators=(",",":")))
    print("RESULT=R340_UMS_READONLY_CAPTURE_FINISHED")

if __name__=="__main__":
    main()
