#!/bin/sh
# AlekS Homebrew Channel repository launcher for DTS/Lampa testing.
# Only opens the standard Homebrew Channel "Add repository" dialog.
# It does not edit localStorage, install IPKs, or change DTS/media settings.
set -u
LC_ALL=C; export LC_ALL
repo='https://gamefree24.ru/webos/repository.json'
payload='{"id":"org.webosbrew.hbchannel","params":{"launchMode":"addRepository","url":"https://gamefree24.ru/webos/repository.json"}}'
echo '=== ALEKS HOMEBREW REPOSITORY PREFILL ==='
echo "REPO_URL=$repo"
if command -v curl >/dev/null 2>&1; then
  code=$(curl -fLsS --connect-timeout 5 --max-time 15 -o /dev/null -w '%{http_code}' "$repo" 2>/dev/null)
  if [ "$code" = 200 ]; then
    echo 'PASS REPO_HTTP_200_FROM_TV'
  else
    echo "WARN REPO_FETCH_ON_TV_FAILED code=$code (will still open dialog)"
  fi
fi
result=''
sent=0
for manager in com.webos.applicationManager com.webos.service.applicationManager; do
  [ "$sent" = 0 ] || break
  for sender in luna-send-pub luna-send; do
    [ "$sent" = 0 ] || break
    command -v "$sender" >/dev/null 2>&1 || continue
    output=$("$sender" -n 1 -f "luna://$manager/launch" "$payload" 2>&1)
    status=$?
    case "$output" in
      *'"returnValue":false'*|*'"returnValue": false'*|*'Service does not exist'*|*'Permission denied'*)
        echo "WARN_LUNA_ATTEMPT manager=$manager tool=$sender result=failed"
        ;;
      *)
        if [ "$status" -eq 0 ]; then
          echo "PASS LUNA_LAUNCH_DISPATCHED manager=$manager sender=$sender"
          if printf '%s\n' "$output" | grep -Eq '"returnValue"[[:space:]]*:[[:space:]]*true'; then
            echo 'PASS LUNA_RETURN_VALUE_TRUE'
          else
            echo 'INFO LUNA_RETURN_VALUE_UNAVAILABLE_OVER_NONINTERACTIVE_SSH'
          fi
          sent=1
        else
          echo "WARN_LUNA_ATTEMPT manager=$manager tool=$sender exit=$status"
        fi
        ;;
    esac
  done
done
if [ "$sent" = 0 ]; then
  echo 'RESULT=LAUNCH_FAILED; REPO_NOT_ADDED'
  exit 1
fi
echo 'RESULT=ADD_REPOSITORY_DIALOG_REQUESTED; NOT_YET_SAVED'
echo 'On the TV: verify that the URL is prefilled, press Add repository, then refresh apps.'
