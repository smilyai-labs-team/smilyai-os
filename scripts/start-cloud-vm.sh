#!/usr/bin/env bash
set -euo pipefail

REPO="${GITHUB_REPOSITORY:-smilyai-labs-team/smilyai-os}"
ARTIFACT_NAME="${SMILYAI_ARTIFACT_NAME:-smilyai-0.3-x86_64-preview}"
STATE_DIR="${SMILYAI_VM_STATE_DIR:-$HOME/.cache/smilyai-cloud-vm}"
ARTIFACT_DIR="$STATE_DIR/artifact"
ZIP="$STATE_DIR/artifact.zip"
QEMU_PID="$STATE_DIR/qemu.pid"
NOVNC_PID="$STATE_DIR/novnc.pid"
MONITOR="$STATE_DIR/qemu-monitor.sock"
SERIAL_LOG="$STATE_DIR/serial.log"

mkdir -p "$ARTIFACT_DIR"

stop_pidfile() {
  local file="$1"
  if [[ -f "$file" ]]; then
    local pid
    pid="$(cat "$file" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      sleep 1
    fi
    rm -f "$file"
  fi
}

echo "== SmilyAI OS cloud VM =="
echo "Repository: $REPO"
echo "Artifact:   $ARTIFACT_NAME"

if ! gh auth status >/dev/null 2>&1; then
  echo
  echo "GitHub CLI is not authenticated."
  echo "In a GitHub Codespace this should normally be automatic."
  echo "Run: gh auth login"
  exit 1
fi

ISO="$(find "$ARTIFACT_DIR" -maxdepth 3 -type f -iname '*.iso' -print -quit 2>/dev/null || true)"

if [[ -z "$ISO" ]]; then
  echo
  echo "Finding the newest non-expired x86 artifact on GitHub..."
  ARTIFACT_ID="$(
    gh api "repos/$REPO/actions/artifacts?name=$ARTIFACT_NAME&per_page=100" \
      --jq '.artifacts | map(select(.expired == false)) | sort_by(.created_at) | reverse | .[0].id // empty'
  )"

  if [[ -z "$ARTIFACT_ID" ]]; then
    echo "No non-expired artifact named '$ARTIFACT_NAME' was found."
    echo "Run the x86_64 image workflow first."
    exit 1
  fi

  echo "Downloading artifact ID $ARTIFACT_ID inside the cloud VM..."
  rm -f "$ZIP"
  rm -rf "$ARTIFACT_DIR"
  mkdir -p "$ARTIFACT_DIR"

  gh api \
    -H "Accept: application/vnd.github+json" \
    "repos/$REPO/actions/artifacts/$ARTIFACT_ID/zip" > "$ZIP"

  echo "Extracting artifact..."
  unzip -q "$ZIP" -d "$ARTIFACT_DIR"
  rm -f "$ZIP"

  ISO="$(find "$ARTIFACT_DIR" -maxdepth 3 -type f -iname '*.iso' -print -quit 2>/dev/null || true)"
fi

if [[ -z "$ISO" || ! -f "$ISO" ]]; then
  echo "The artifact downloaded, but no ISO file was found inside it."
  exit 1
fi

echo "ISO: $ISO"
echo
echo "Stopping any previous cloud VM..."
stop_pidfile "$NOVNC_PID"
stop_pidfile "$QEMU_PID"
rm -f "$MONITOR"

QEMU_ACCEL="tcg"
if [[ -r /dev/kvm && -w /dev/kvm ]]; then
  QEMU_ACCEL="kvm"
fi

echo "Starting QEMU with accelerator: $QEMU_ACCEL"
qemu-system-x86_64 \
  -name "SmilyAI OS" \
  -machine "q35,accel=$QEMU_ACCEL" \
  -smp 2 \
  -m 4096 \
  -boot order=d \
  -cdrom "$ISO" \
  -vga std \
  -vnc 127.0.0.1:0 \
  -monitor "unix:$MONITOR,server,nowait" \
  -serial "file:$SERIAL_LOG" \
  -no-reboot \
  -daemonize \
  -pidfile "$QEMU_PID"

NOVNC_WEB="/usr/share/novnc"
if [[ ! -d "$NOVNC_WEB" ]]; then
  echo "noVNC web files were not found at $NOVNC_WEB."
  exit 1
fi

echo "Starting private browser console on port 6080..."
nohup websockify --web="$NOVNC_WEB" 0.0.0.0:6080 127.0.0.1:5900 \
  >"$STATE_DIR/novnc.log" 2>&1 &
echo $! > "$NOVNC_PID"

sleep 2

if ! kill -0 "$(cat "$QEMU_PID")" 2>/dev/null; then
  echo "QEMU exited unexpectedly."
  echo "Serial log:"
  tail -n 80 "$SERIAL_LOG" 2>/dev/null || true
  exit 1
fi

echo
echo "✅ SmilyAI OS is booting in the Codespace."
echo
echo "Open this link from the Codespace terminal:"
echo "http://localhost:6080/vnc.html?autoconnect=1&resize=scale"
echo
echo "GitHub Codespaces will forward port 6080 privately to your browser."
echo "The first boot can be slow because QEMU may be using software emulation."
echo
echo "To stop the VM later:"
echo "bash scripts/stop-cloud-vm.sh"
echo
echo "Serial log:"
echo "$SERIAL_LOG"
