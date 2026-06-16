#!/usr/bin/env bash

set -euo pipefail

user_agent='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36'
home_url='https://www.zenradio.com/'
api_root='https://api.audioaddict.com/v1/zenradio'

# ZenRadio runs on the AudioAddict platform. The homepage bootstraps its web
# player via `di.app.start({...})`, whose JSON state carries both the list of
# channels and a guest `audio_token` used to authorize stream requests.
fetch_state() {
  local html
  local state

  if ! html=$(curl -A "$user_agent" -fsSL "$home_url"); then
    echo >&2 "warning: failed to fetch $home_url"
    return 1
  fi

  state=$(printf '%s' "$html" | grep -F 'di.app.start(' |
    sed -r 's|^.*di\.app\.start\((\{.*\})\);?\s*$|\1|' || true)

  if [ -z "$state" ]; then
    echo >&2 'warning: could not extract ZenRadio app state'
    return 1
  fi

  printf '%s' "$state"
}

if ! state=$(fetch_state); then
  echo >&2 'fatal: could not load ZenRadio'
  exit 1
fi

audio_token=$(printf '%s' "$state" | jq -r '.user.audio_token // empty')
if [ -z "$audio_token" ]; then
  echo >&2 'fatal: no audio_token in ZenRadio app state'
  exit 1
fi

# Channel picker.
channel_name=$(printf '%s' "$state" | jq -r '
  .channels[]
  | (.name + "   \t"
     + ((.description // "") | gsub("[\r\n\t]+"; " ") | gsub("^ +| +$"; ""))) ' |
  column -t -s $'\t' | LC_ALL=C sort | sk --no-sort |
  sed -r 's|^(.*)   .*$|\1|g ; s|\s*$||g' || true)

if [ -z "$channel_name" ]; then
  exit 0
fi

channel_id=$(printf '%s' "$state" | jq -r --arg name "$channel_name" '
  first(.channels[] | select(.name == $name) | .id) // empty')
if [ -z "$channel_id" ]; then
  echo >&2 "fatal: could not resolve channel id for '$channel_name'"
  exit 1
fi

echo
echo "Channel: $channel_name"

# A "routine" is a server-curated playlist of individual track files for the
# channel. Play it track by track, fetching the next batch when it runs out.
# The first request uses `tune_in=true` to start fresh; later ones advance.
tune_in=true
while true; do
  routine_json=$(curl -A "$user_agent" -fsSL \
    "$api_root/routines/channel/${channel_id}?audio_token=${audio_token}&tune_in=${tune_in}" || true)

  track_count=0
  if [ -n "$routine_json" ]; then
    track_count=$(printf '%s' "$routine_json" | jq -r '(.tracks // []) | length' 2>/dev/null || echo 0)
  fi

  # An empty/invalid routine usually means the guest audio_token expired;
  # refresh it from the homepage and start over.
  if [ "$track_count" = "0" ]; then
    echo >&2 'warning: empty routine from ZenRadio, refreshing audio_token...'
    if state=$(fetch_state); then
      audio_token=$(printf '%s' "$state" | jq -r '.user.audio_token // empty')
    fi
    sleep 2
    tune_in=true
    continue
  fi

  tune_in=false

  track_list=$(printf '%s' "$routine_json" | jq -r '
    .tracks[]
    | select((.content.assets // []) | length > 0)
    | select(.content.assets[0].url != null)
    | [ ("https:" + .content.assets[0].url),
        (.display_title // .title // ""),
        (.display_artist // .artist.name // ""),
        (.release.title // "") ]
    | @tsv')

  if [ -z "$track_list" ]; then
    echo >&2 'warning: no playable tracks in routine'
    sleep 2
    continue
  fi

  while IFS=$'\t' read -r track_url title artist album; do
    if [ -z "$track_url" ]; then
      continue
    fi

    echo
    echo "Track:   $title"
    echo "Artist:  $artist"
    if [ -n "$album" ]; then
      echo "Album:   $album"
    fi
    echo "Channel: $channel_name"
    echo "URL:     $track_url"
    echo

    rc=0
    mpv \
      --user-agent="$user_agent" \
      --no-ytdl \
      --no-resume-playback \
      "$track_url" || rc=$?

    # Pressing 'q' (rc 0) skips to the next track; Ctrl-C / a signal quits.
    if [ "$rc" -eq 4 ] || [ "$rc" -ge 128 ]; then
      exit "$rc"
    fi
  done <<<"$track_list"
done
