#!/usr/bin/env bash

set -euo pipefail

user_agent='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36'
mpv_mute_script='@mpvMuteScript@'
stations_yaml='@stationsYaml@'

get_station_url() {
  local name="$1"

  # shellcheck disable=SC2016
  yq -r --arg station "$name" '.stations[] | select(.name == $station) | .url' "$stations_yaml"
}

get_station_mpv_override() {
  local name="$1"

  # shellcheck disable=SC2016
  yq -r --arg station "$name" '.stations[] | select(.name == $station) | (."mpv-override" // "")' "$stations_yaml"
}

get_station_infixes() {
  local name="$1"

  # shellcheck disable=SC2016
  yq -r --arg station "$name" '.stations[] | select(.name == $station) | (."mute-title-infixes" // []) | join(",")' "$stations_yaml"
}

get_station_mute_empty_title() {
  local name="$1"

  # shellcheck disable=SC2016
  yq -r --arg station "$name" '.stations[] | select(.name == $station) | (."mute-empty-title" // false)' "$stations_yaml"
}

get_station_type() {
  local name="$1"

  # shellcheck disable=SC2016
  yq -r --arg station "$name" '.stations[] | select(.name == $station) | (.type // "stream")' "$stations_yaml"
}

play_stream() {
  local name="$1"
  local url="$2"
  local infixes="${3:-}"
  local mute_empty_title="${4:-false}"
  local mpv_override="${5:-}"
  local mpv_args=(
    --user-agent="$user_agent"
    --no-ytdl
    --no-resume-playback
    --loop-playlist=inf
    --script="$mpv_mute_script"
  )

  if [ -n "$infixes" ]; then
    mpv_args+=(--script-opts-append="radio-mute-title_infixes=$infixes")
  fi

  if [ "$mute_empty_title" = "true" ]; then
    mpv_args+=(--script-opts-append="radio-mute-mute_empty_title=yes")
  fi

  echo
  echo "Station: $name"
  echo "URL:     $url"
  echo

  local cmd
  if [ -n "$mpv_override" ] && [ "$mpv_override" != "null" ]; then
    cmd=("$mpv_override" --loop-playlist=inf "$url")
  else
    cmd=(mpv "${mpv_args[@]}" "$url")
  fi

  local retry_delay=2
  local max_retry_delay=60
  while true; do
    local start=$SECONDS
    local rc=0
    "${cmd[@]}" || rc=$?
    # Exit on success (0) or signal quit (4)
    if ((rc == 0 || rc == 4)); then exit "$rc"; fi
    # Reset backoff if mpv ran for more than a minute (transient vs. immediate failure)
    if ((SECONDS - start > 60)); then
      retry_delay=2
    fi
    echo >&2 "mpv exited with error (code $rc), retrying in ${retry_delay}s..."
    sleep "$retry_delay"
    retry_delay=$((retry_delay * 2))
    if ((retry_delay > max_retry_delay)); then
      retry_delay=$max_retry_delay
    fi
  done
}

play_youtube_channel() {
  local name="$1"
  local url="$2"
  local mpv_override="${3:-}"

  if ! command -v yt-dlp &>/dev/null; then
    echo >&2 'fatal: yt-dlp not found on PATH; install it and try again'
    exit 1
  fi

  echo
  echo "Station: $name"
  echo

  local retry_delay=2
  local max_retry_delay=60

  while true; do
    echo "Fetching video list..."

    local video_ids
    mapfile -t video_ids < <(yt-dlp --flat-playlist --print id "$url" 2>/dev/null | shuf)

    if [ ${#video_ids[@]} -eq 0 ]; then
      echo >&2 "No videos found, retrying in ${retry_delay}s..."
      sleep "$retry_delay"
      retry_delay=$((retry_delay * 2))
      if ((retry_delay > max_retry_delay)); then retry_delay=$max_retry_delay; fi
      continue
    fi

    retry_delay=2
    echo "Found ${#video_ids[@]} videos, playing in shuffled order."

    for video_id in "${video_ids[@]}"; do
      local video_url="https://www.youtube.com/watch?v=${video_id}"

      echo
      echo "Now playing: $video_url"
      echo

      local cmd
      if [ -n "$mpv_override" ] && [ "$mpv_override" != "null" ]; then
        cmd=("$mpv_override" "$video_url")
      else
        cmd=(mpv --no-resume-playback --ytdl-format=bestaudio --user-agent="$user_agent" "$video_url")
      fi

      local rc=0
      "${cmd[@]}" || rc=$?
      if ((rc == 4)); then exit 0; fi
    done

    echo
    echo "All videos played. Re-fetching and re-shuffling..."
  done
}

mapfile -t stations_from_yaml < <(
  yq -r '.stations | .[] | .name' "$stations_yaml"
)
mapfile -t stations < <(
  printf '%s\n' "AccuRadio.com" "Chillhop.com" "JazzRadio.fr" "${stations_from_yaml[@]}" | LC_ALL=C sort -u
)

station=$(printf '%s\n' "${stations[@]}" | sk --no-sort)

if [ -z "${station}" ]; then
  exit 0
fi

case "$station" in
"AccuRadio.com")
  exec accuradio
  ;;
"Chillhop.com")
  exec radio-chillhop
  ;;
"JazzRadio.fr")
  exec radio-jazzradio-fr
  ;;
*)
  url=$(get_station_url "$station")
  station_type=$(get_station_type "$station")
  mpv_override=$(get_station_mpv_override "$station")

  if [ -z "$url" ]; then
    echo "No URL found for station: $station" >&2
    exit 1
  fi

  if [ "$station_type" = "youtube-channel" ]; then
    play_youtube_channel "$station" "$url" "$mpv_override"
  else
    infixes=$(get_station_infixes "$station")
    mute_empty_title=$(get_station_mute_empty_title "$station")
    play_stream "$station" "$url" "$infixes" "$mute_empty_title" "$mpv_override"
  fi
  ;;
esac
