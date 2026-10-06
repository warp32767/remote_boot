#!/usr/bin/env bash

main() {
  ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

  OS="$(uname -s)"
  LSUSB="${LSUSB:-lsusb}"
  SYSTEM_PROFILER="${SYSTEM_PROFILER:-system_profiler}"
  RG="${RG:-rg}"
  IRECOVERY="${IRECOVERY:-irecovery}"
  PYTHON="${PYTHON:-python3}"
  USBLITER8CTL="${USBLITER8CTL:-$ROOT/../usbliter8/usbliter8ctl}"
  PWND_USB_ID="${PWND_USB_ID:-05ac:1227}"

  if [ "$#" != 4 ]; then
    echo "usage: $0 <patched-iboot.raw> <RestoreDeviceTree.img4> <RestoreTrustCache.img4> <RestoreKernelCache.img4>"
    return 2
  fi

  IBOOT="$1"
  RESTORE_DT="$2"
  RESTORE_TC="$3"
  RESTORE_RKRN="$4"

  if [ "$OS" = "Darwin" ]; then
    USB_SERIAL_COMMAND="$SYSTEM_PROFILER"
  else
    USB_SERIAL_COMMAND="$LSUSB"
  fi

  for cmd in "$USB_SERIAL_COMMAND" "$RG" "$IRECOVERY" "$PYTHON"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      echo "missing command: $cmd"
      return 1
    fi
  done

  if [ ! -f "$USBLITER8CTL" ]; then
    echo "missing usbliter8ctl: $USBLITER8CTL"
    echo "set USBLITER8CTL=/path/to/usbliter8ctl"
    return 1
  fi

  for f in "$IBOOT" "$RESTORE_DT" "$RESTORE_TC" "$RESTORE_RKRN"; do
    if [ ! -f "$f" ]; then
      echo "missing required file: $f"
      return 1
    fi
  done

  echo "== post-pwned DFU check =="
  if [ "$OS" = "Darwin" ]; then
    SERIAL="$("$SYSTEM_PROFILER" SPUSBDataType SPUSBHostDataType 2>/dev/null | "$RG" 'Serial Number:' || true)"
  else
    SERIAL="$("$LSUSB" -v -d "$PWND_USB_ID" 2>/dev/null | "$RG" 'iSerial' || true)"
  fi
  echo "$SERIAL"

  if ! printf '%s\n' "$SERIAL" | "$RG" -q 'PWND'; then
    echo "device $PWND_USB_ID is not post-pwned: serial does not contain PWND"
    return 1
  fi

  echo
  echo "== files =="
  ls -lh "$IBOOT" "$RESTORE_DT" "$RESTORE_TC" "$RESTORE_RKRN"

  echo
  echo "== boot patched iBoot =="
  sudo -E "$PYTHON" "$USBLITER8CTL" boot "$IBOOT"

  echo
  echo "== send restore boot chain =="
  sleep 2
  "$IRECOVERY" -q

  "$IRECOVERY" -f "$RESTORE_DT"
  "$IRECOVERY" -c devicetree

  "$IRECOVERY" -f "$RESTORE_TC"
  "$IRECOVERY" -c firmware

  "$IRECOVERY" -f "$RESTORE_RKRN"
  "$IRECOVERY" -c bootx

  return 0
}

main "$@"
