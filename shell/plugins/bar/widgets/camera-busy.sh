#!/bin/bash
# Print busy, idle, or absent.
#
# A webcam is a v4l2 or libcamera Video/Source. Screen sharing is also a
# Video/Source, and its client is Stream/Input/Video, so those classes are
# not enough on their own.
#
# When pw-dump returns data, presence is the count of those webcam nodes.
# The camera is busy while a link leaves one of them, or while a process has
# that node's /dev/videoN open. Metadata, codec, and leftover loopback nodes
# do not count.
#
# When pw-dump fails, times out, or returns nothing, fall back to any
# /dev/videoN node.
#
# CAMERA_BUSY_DUMP replaces pw-dump. CAMERA_BUSY_DEVICES replaces the
# fallback device list. Leave both unset in normal use.

shopt -s nullglob

dump=$(mktemp)
trap 'rm -f "$dump"' EXIT

dump_ok=0
if [[ -v CAMERA_BUSY_DUMP ]]; then
  if [[ -n $CAMERA_BUSY_DUMP ]] && cp -- "$CAMERA_BUSY_DUMP" "$dump" 2>/dev/null && [[ -s $dump ]]; then
    dump_ok=1
  fi
elif timeout 2 pw-dump >"$dump" 2>/dev/null && [[ -s $dump ]]; then
  dump_ok=1
fi

cameras=0
linked=0
paths=()

if (( dump_ok )); then
  parsed=$(jq -r '
    def props: (.info.props // {});
    def camera:
      .type == "PipeWire:Interface:Node"
      and (props["media.class"] == "Video/Source")
      and (
        (props["device.api"] == "v4l2")
        or (props["device.api"] == "libcamera")
        or ((props["api.v4l2.path"] // "") | startswith("/dev/video"))
      );
    def consuming:
      .type == "PipeWire:Interface:Link"
      and ((.info.state // "") != "error")
      and ((.info.state // "") != "unlinked");
    [ .[] | select(camera) ] as $cams
    | [ $cams[].id ] as $ids
    | ([ .[]
        | select(consuming)
        | .info["output-node-id"]
        | select(. as $id | $ids | index($id) != null)
      ] | length) as $links
    | [ $cams[]
        | (props["api.v4l2.path"] // "")
        | select(test("^/dev/video[0-9]+$"))
      ] | unique as $paths
    | "\($ids | length)\t\(if $links > 0 then 1 else 0 end)\t\($paths | join(","))"
  ' "$dump" 2>/dev/null) || parsed=""

  cameras=""
  linked=""
  path_csv=""
  IFS=$'\t' read -r cameras linked path_csv <<<"$parsed"
  if [[ $cameras =~ ^[0-9]+$ && $linked =~ ^[01]$ ]]; then
    if [[ -n $path_csv ]]; then
      IFS=',' read -r -a paths <<<"$path_csv"
    fi
  else
    dump_ok=0
    cameras=0
    linked=0
    paths=()
  fi
fi

if (( dump_ok == 0 )); then
  candidates=()
  if [[ -v CAMERA_BUSY_DEVICES ]]; then
    if [[ -n $CAMERA_BUSY_DEVICES ]]; then
      IFS=',' read -r -a candidates <<<"$CAMERA_BUSY_DEVICES"
    fi
  else
    candidates=(/dev/video*)
  fi
  paths=()
  linked=0
  for candidate in "${candidates[@]}"; do
    [[ $candidate =~ ^/dev/video[0-9]+$ ]] || continue
    paths+=("$candidate")
  done
  cameras=${#paths[@]}
fi

video_nodes=()
for candidate in "${paths[@]}"; do
  [[ $candidate =~ ^/dev/video[0-9]+$ ]] || continue
  video_nodes+=("$candidate")
done

device_open=0
if ((${#video_nodes[@]} > 0)) && fuser "${video_nodes[@]}" >/dev/null 2>&1; then
  device_open=1
fi

if (( device_open == 1 || linked == 1 )); then
  echo busy
elif (( cameras > 0 )); then
  echo idle
else
  echo absent
fi
exit 0
