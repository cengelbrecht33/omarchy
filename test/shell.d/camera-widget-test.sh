#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq

script="$ROOT/shell/plugins/bar/widgets/camera-busy.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

probe() {
  local dump=$1
  local devices=$2
  local open_devices=$3

  CAMERA_BUSY_DUMP="$dump" \
    CAMERA_BUSY_DEVICES="$devices" \
    CAMERA_BUSY_OPEN_DEVICES="$open_devices" \
    bash "$script"
}

expect() {
  local description=$1
  local actual=$2
  local wanted=$3

  [[ $actual == "$wanted" ]] || fail "$description" "actual: $actual"
  pass "$description"
}

cat >"$tmp/screencast.json" <<'EOF'
[
  {
    "id": 10,
    "type": "PipeWire:Interface:Node",
    "info": {"props": {"node.name": "xdg-desktop-portal-hyprland", "media.class": "Video/Source"}}
  },
  {
    "id": 11,
    "type": "PipeWire:Interface:Node",
    "info": {"props": {"node.name": "webrtc-consume", "media.class": "Stream/Input/Video"}}
  },
  {
    "id": 12,
    "type": "PipeWire:Interface:Link",
    "info": {"output-node-id": 10, "input-node-id": 11, "state": "active"}
  }
]
EOF

cat >"$tmp/camera-idle.json" <<'EOF'
[
  {
    "id": 58,
    "type": "PipeWire:Interface:Node",
    "info": {"props": {"media.class": "Video/Source", "device.api": "v4l2", "api.v4l2.path": "/dev/video0", "media.role": "Camera"}}
  }
]
EOF

cat >"$tmp/camera-linked.json" <<'EOF'
[
  {
    "id": 58,
    "type": "PipeWire:Interface:Node",
    "info": {"props": {"media.class": "Video/Source", "device.api": "v4l2", "api.v4l2.path": "/dev/video0"}}
  },
  {
    "id": 80,
    "type": "PipeWire:Interface:Node",
    "info": {"props": {"media.class": "Stream/Input/Video", "node.name": "ffmpeg"}}
  },
  {
    "id": 90,
    "type": "PipeWire:Interface:Link",
    "info": {"output-node-id": 58, "input-node-id": 80, "state": "active"}
  },
  {
    "id": 10,
    "type": "PipeWire:Interface:Node",
    "info": {"props": {"media.class": "Video/Source", "node.name": "xdg-desktop-portal-hyprland"}}
  },
  {
    "id": 11,
    "type": "PipeWire:Interface:Node",
    "info": {"props": {"media.class": "Stream/Input/Video", "node.name": "webrtc-consume"}}
  },
  {
    "id": 91,
    "type": "PipeWire:Interface:Link",
    "info": {"output-node-id": 10, "input-node-id": 11, "state": "paused"}
  }
]
EOF

cat >"$tmp/error-link.json" <<'EOF'
[
  {
    "id": 58,
    "type": "PipeWire:Interface:Node",
    "info": {"props": {"media.class": "Video/Source", "device.api": "v4l2"}}
  },
  {
    "id": 90,
    "type": "PipeWire:Interface:Link",
    "info": {"output-node-id": 58, "input-node-id": 80, "state": "error"}
  }
]
EOF

cat >"$tmp/libcamera.json" <<'EOF'
[
  {
    "id": 40,
    "type": "PipeWire:Interface:Node",
    "info": {"props": {"media.class": "Video/Source", "device.api": "libcamera"}}
  },
  {
    "id": 41,
    "type": "PipeWire:Interface:Node",
    "info": {"props": {"media.class": "Stream/Input/Video"}}
  },
  {
    "id": 42,
    "type": "PipeWire:Interface:Link",
    "info": {"output-node-id": 40, "input-node-id": 41, "state": "negotiating"}
  }
]
EOF

echo '[]' >"$tmp/empty.json"

expect "screen sharing with no webcam is absent" \
  "$(probe "$tmp/screencast.json" "" "")" "absent"

expect "screen sharing leaves a plugged-in webcam idle" \
  "$(probe "$tmp/screencast.json" "/dev/video0" "")" "idle"

expect "an unlinked v4l2 camera is idle" \
  "$(probe "$tmp/camera-idle.json" "/dev/video0" "")" "idle"

expect "a link from the v4l2 camera is busy during screen sharing" \
  "$(probe "$tmp/camera-linked.json" "/dev/video0" "")" "busy"

expect "a process holding /dev/video is busy without a PipeWire link" \
  "$(probe "$tmp/camera-idle.json" "/dev/video0" "/dev/video0")" "busy"

expect "an errored camera link is not in use" \
  "$(probe "$tmp/error-link.json" "/dev/video0" "")" "idle"

expect "a libcamera source with a negotiating link is busy" \
  "$(probe "$tmp/libcamera.json" "" "")" "busy"

expect "no camera nodes and no devices is absent" \
  "$(probe "$tmp/empty.json" "" "")" "absent"

qml="$ROOT/shell/plugins/bar/widgets/Camera.qml"
if grep -q 'pipewireCamera' "$qml"; then
  fail "camera widget does not treat every Video/Source as a webcam"
fi
pass "camera widget does not treat every Video/Source as a webcam"
