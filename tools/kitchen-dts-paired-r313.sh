#!/bin/sh
# R313: one owner-triggered paired DTS silent->audible capture on kitchen LG.
# Captures only R308 safe scalar summaries, no media recording or route changes.
# The owner changes AC3 -> DTS; this script NEVER controls media or services.
set -eu
umask 077
LC_ALL=C;export LC_ALL
[ "$#" -ge 1 ] || { echo 'USAGE: r313.sh capture | compare silent.txt audible.txt' >&2;exit 2; }
action=$1
source_url=https://raw.githubusercontent.com/aerolit266/AlekS-DTS-webOS/d80b37a3033bc3e2fda5e29371d83b1eeeb2167d/tools/capture-kitchen-dts-first-start-r308.sh
source_sha=1235dc9ff013ae73f0089cecac93056ac0ce00ffa8d049ce2e0c8d9b027ed7bc

compare() {
  printf '%s\nR313_PAIR_DIVIDER\n%s\n' "$1" "$2" | awk -F= '
    BEGIN {
      side=1;n=0;differ=0
      n++; keys[n]="DTS_WRAPPER_HOLDERS"
      n++; keys[n]="ALSA_PCM6"
      n++; keys[n]="ALSA_HW_FRAMES_2S"
      n++; keys[n]="ALSA_APPL_FRAMES_2S"
      n++; keys[n]="R130_INITIAL_EVENT_LIMIT"
      n++; keys[n]="R130_NO_INPUT_CAPS"
      n++; keys[n]="R130_UNRECOGNIZED_CAPS"
      n++; keys[n]="GST_NOT_NEGOTIATED"
      n++; keys[n]="NATIVE_AUDIO_SINK_ERROR_HINT"
      n++; keys[n]="DCADEC_ERROR_HINT"
      n++; keys[n]="NATIVE_LOG_COUNTS"
      n++; keys[n]="QUERY_CODEC"
      n++; keys[n]="QUERY_OUTPUT"
    }
    $0=="R313_PAIR_DIVIDER" {side=2;query="";next}
    $1=="STAGE" {
      split($0,fields,/ +/)
      split(fields[1],pair,"=")
      tag[side]=pair[2]
      next
    }
    $1=="STARFISH" {
      nwords=split($0,fields,/ +/)
      for(i=1;i<=nwords;i++)if(fields[i]~/^DTS_WRAPPER_HOLDERS=/) {
        split(fields[i],pair,"=")
        value[side,"DTS_WRAPPER_HOLDERS"]=pair[2]
      }
      next
    }
    $1=="QUERY" {query=$2;next}
    $1=="QUERY_STATUS" && (query=="CODEC" || query=="OUTPUT") {
      value[side,"QUERY_"query]=$2;next
    }
    # R308 emits allowlisted, bounded individual LS2 fields as e.g. "muted":false.
    # R310 compared only QUERY_STATUS, missing actual policy changes.
    (query=="CODEC" || query=="OUTPUT") &&
    $0~/^"(codec|source|sink|soundOutput|outputMode|muted|streamType)"[[:space:]]*:/ {
      row=$0
      sub(/^"/,"",row)
      parts=split(row,fields,/"[[:space:]]*:[[:space:]]*/)
      if(parts==2) {
        name=fields[1]; item=fields[2]
        gsub(/^"/,"",item);gsub(/"$/,"",item)
        if(length(item)>0 && length(item)<=40 && item~/^[A-Za-z0-9_.-]+$/) {
          policy[side,query,name]=item
        }
      }
      next
    }
    # R308 places both ALSA pointers on ONE line separated by spaces.
    # Split each key=value token, never treat the rest of the line as a pointer.
    $1=="ALSA_HW_FRAMES_2S" || $1=="ALSA_APPL_FRAMES_2S" {
      count=split($0,words,/ +/)
      for(j=1;j<=count;j++) {
        pieces=split(words[j],pair,/=/)
        if(pieces==2 && pair[1]~/^(ALSA_HW_FRAMES_2S|ALSA_APPL_FRAMES_2S)$/ &&
           pair[2]~/^[0-9]+$/) value[side,pair[1]]=pair[2]
      }
      next
    }
    $1~/^(ALSA_PCM6|R130_INITIAL_EVENT_LIMIT|R130_NO_INPUT_CAPS|R130_UNRECOGNIZED_CAPS|GST_NOT_NEGOTIATED|NATIVE_AUDIO_SINK_ERROR_HINT|DCADEC_ERROR_HINT|NATIVE_LOG_COUNTS)$/ {
      value[side,$1]=$2;next
    }
    END {
      if(tag[1]!="silent" || tag[2]!="audible"){
        print "R313_INVALID_CAPTURE_STAGE_TAGS";exit 2
      }
      print "R313_RESULT=COMPARISON_ONLY_NOT_CAUSAL_PROOF"
      # Stable ordering prevents JSON property-order differences from looking like changes.
      pcount=split("codec source sink soundOutput outputMode muted streamType",pkeys," ")
      for(s=1;s<=2;s++){
        for(q=1;q<=2;q++){
          qname=(q==1)?"CODEC":"OUTPUT"
          dest="QUERY_"qname
          summary=((s SUBSEP dest) in value)?value[s,dest]:"UNAVAILABLE"
          for(p=1;p<=pcount;p++) {
            prop=pkeys[p]
            if((s SUBSEP qname SUBSEP prop) in policy) {
              summary=summary "," prop ":" policy[s,qname,prop]
            }
          }
          value[s,dest]=summary
        }
      }
      for(i=1;i<=n;i++){
        key=keys[i]
        left=((1 SUBSEP key) in value)?value[1,key]:"UNAVAILABLE"
        right=((2 SUBSEP key) in value)?value[2,key]:"UNAVAILABLE"
        state=(left==right)?"SAME":"DIFFERENT"
        if(state=="DIFFERENT")differ++
        printf "METRIC=%s SILENT=%s AUDIBLE=%s STATUS=%s\n",key,left,right,state
      }
      printf "R313_CHANGED_METRICS=%d\n",differ
      print "R313_NOTE=LS2_fields_are_allowlisted_but_not_attributed_to_individual_playback_streams."
      print "R313_NOTE=Journal_counters_are_not_attributed_to_individual_streams."
      print "R313_NOTE=ALSA_activity_does_not_prove_nonzero_or_audible_DTS."
      print "RESULT=R313_PAIR_COMPARISON_COMPLETE"
    }'
}

case "$action" in
  compare)
    [ "$#" -eq 3 ] || exit 2
    [ -f "$2" ] && [ ! -L "$2" ] && [ -f "$3" ] && [ ! -L "$3" ] || exit 2
    compare "$(cat "$2")" "$(cat "$3")"
    ;;
  capture)
    [ "$#" -eq 1 ] || exit 2
    arch=$(uname -m 2>/dev/null || :)
    case "$arch" in armv7l|armv6l|arm|aarch64) :;;*) echo R313_BLOCKED_NOT_ARM;exit 2;;esac
    for cmd in curl sha256sum mktemp sh;do command -v "$cmd" >/dev/null || exit 2;done
    dir=$(mktemp -d /tmp/aleks-r313.XXXXXX)
    trap 'rm -rf "$dir"' EXIT HUP INT TERM
    curl -fLsS --proto '=https' --proto-redir '=https' --connect-timeout 8 --max-time 25 "$source_url" -o "$dir/r308.sh"
    printf '%s  %s\n' "$source_sha" "$dir/r308.sh" | sha256sum -c - >/dev/null || {
      echo R313_SOURCE_PIN_FAILURE;exit 2;
    }
    echo R313_R308_SOURCE_SHA256_PASS
    echo 'Run during FIRST SILENT DTS. Do not change track yet.'
    printf 'Type SILENT to confirm current silence (anything else aborts): '
    IFS= read -r confirm || exit 2
    [ "$confirm" = SILENT ] || { echo R313_CAPTURE_ABORTED;exit 2; }
    first=$(sh "$dir/r308.sh" silent)
    printf '%s\n' "$first" | grep -Fxq 'RESULT=R308_READ_ONLY_CAPTURE_COMPLETE' || exit 2
    echo 'Now manually switch DTS -> AC3 -> DTS and confirm the DTS sound.'
    printf 'Type AUDIBLE only after DTS sound is audible: '
    IFS= read -r confirm || exit 2
    [ "$confirm" = AUDIBLE ] || { echo R313_CAPTURE_ABORTED;exit 2; }
    second=$(sh "$dir/r308.sh" audible)
    printf '%s\n' "$second" | grep -Fxq 'RESULT=R308_READ_ONLY_CAPTURE_COMPLETE' || exit 2
    compare "$first" "$second"
    ;;
  *)
    echo 'USAGE: r313.sh capture | compare silent.txt audible.txt' >&2
    exit 2
    ;;
esac
