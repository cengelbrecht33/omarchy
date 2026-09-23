#!/bin/bash
# Print busy, idle, or absent.
#
# A webcam is a v4l2 or libcamera Video/Source. It is busy while a PipeWire
# link carries that source, or while a process has the /dev/video* node open.
# Stream/Input/Video alone is not camera use: screen sharing uses that class,
# and its producer is also a Video/Source.
#
# CAMERA_BUSY_DUMP, CAMERA_BUSY_DEVICES, and CAMERA_BUSY_OPEN_DEVICES are
# test overrides. Leave them unset in normal use.

shopt -s nullglob

if [[ -v CAMERA_BUSY_DEVICES ]]; then
  if [[ -n $CAMERA_BUSY_DEVICES ]]; then
    IFS=',' read -r -a devs <<< "$CAMERA_BUSY_DEVICES"
  else
    devs=()
  fi
else
  devs=(/dev/video*)
fi

device_open=0
if [[ -v CAMERA_BUSY_OPEN_DEVICES ]]; then
  if [[ -n $CAMERA_BUSY_OPEN_DEVICES ]]; then
    device_open=1
  fi
else
  if ((${#devs[@]} > 0)) && fuser "${devs[@]}" >/dev/null 2>&1; then
    device_open=1
  fi
fi

dump=$(mktemp)
trap 'rm -f "$dump"' EXIT

if [[ -v CAMERA_BUSY_DUMP ]]; then
  if [[ -n $CAMERA_BUSY_DUMP ]]; then
    cp -- "$CAMERA_BUSY_DUMP" "$dump"
  fi
else
  pw-dump >"$dump" 2>/dev/null || true
fi

cameras=0
linked=0
if [[ -s $dump ]]; then
  read -r cameras linked < <(jq -r '
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
    [ .[] | select(camera) | .id ] as $ids
    | ([ .[]
        | select(consuming)
        | .info["output-node-id"]
        | select(. as $id | $ids | index($id) != null)
      ] | length) as $links
    | "\($ids | length) \(if $links > 0 then 1 else 0 end)"
  ' "$dump" 2>/dev/null || true)
fi

if (( device_open == 1 || linked == 1 )); then
  echo busy
elif (( cameras > 0 || ${#devs[@]} > 0 )); then
  echo idle
else
  echo absent
fi
exit 0
