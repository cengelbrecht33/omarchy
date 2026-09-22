#!/bin/bash
# Print busy, idle, or absent.
shopt -s nullglob
devs=(/dev/video*)
if pw-dump 2>/dev/null | grep -q 'Stream/Input/Video'; then
  echo busy
  exit 0
fi
if ((${#devs[@]} == 0)); then
  echo absent
  exit 0
fi
if fuser "${devs[@]}" >/dev/null 2>&1; then
  echo busy
else
  echo idle
fi
exit 0
