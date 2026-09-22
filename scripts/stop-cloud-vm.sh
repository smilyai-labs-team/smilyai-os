#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${SMILYAI_VM_STATE_DIR:-$HOME/.cache/smilyai-cloud-vm}"

for name in novnc qemu; do
  pidfile="$STATE_DIR/$name.pid"
  if [[ -f "$pidfile" ]]; then
    pid="$(cat "$pidfile" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      echo "Stopped $name (PID $pid)."
    fi
    rm -f "$pidfile"
  fi
done

rm -f "$STATE_DIR/qemu-monitor.sock"
echo "SmilyAI cloud VM stopped."
