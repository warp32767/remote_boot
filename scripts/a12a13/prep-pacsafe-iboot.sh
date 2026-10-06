#!/usr/bin/env bash

main() {
  ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  HBOOTPATCHER="${HBOOTPATCHER:-$ROOT/vendor/hBootPatcher/hBootPatcher}"
  PATCHER="$ROOT/scripts/a12a13/pacsafe_sigcheck_zero.py"

  if [ "$#" -lt 5 ] || [ "$#" -gt 6 ]; then
    echo "usage: $0 <input-raw> <output-raw> <patch_off> <expected_old> <retab_off> [expected_retab]"
    return 2
  fi

  IN="$1"
  OUT="$2"
  PATCH_OFF="$3"
  EXPECTED_OLD="$4"
  RETAB_OFF="$5"
  EXPECTED_RETAB="${6:-0xd65f0fff}"

  if [ ! -f "$IN" ]; then
    echo "missing input: $IN"
    return 1
  fi

  if [ ! -x "$HBOOTPATCHER" ]; then
    cd "$ROOT/vendor/hBootPatcher" || return 1
    mkdir -p obj/patches plooshfinder/obj plooshfinder/obj/asm plooshfinder/obj/formats

    if ! make -j1; then
      echo "hBootPatcher build failed"
      return 1
    fi
  fi

  mkdir -p "$(dirname "$OUT")"

  AIR="$(mktemp "${TMPDIR:-/tmp}/remote_boot-air.XXXXXX")"
  LOG="$OUT.log"

  rm -f "$OUT" "$LOG"

  echo "[*] hBootPatcher -air"
  "$HBOOTPATCHER" -air "$IN" "$AIR" >"$LOG" 2>&1
  HBOOT_RC="$?"
  cat "$LOG"

  if [ "$HBOOT_RC" != "0" ] || grep -Eiq 'patchfinding failed|failed to find|failed!' "$LOG" || [ ! -s "$AIR" ]; then
    echo "hBootPatcher -air failed"
    rm -f "$AIR"
    return 1
  fi

  echo "[*] PAC-safe return-value patch"
  PATCH_LOG="$OUT.patch.log"
  rm -f "$PATCH_LOG"
  "$PATCHER" "$AIR" "$OUT" "$PATCH_OFF" "$EXPECTED_OLD" "$RETAB_OFF" "$EXPECTED_RETAB" >"$PATCH_LOG" 2>&1
  PATCH_RC="$?"
  cat "$PATCH_LOG"
  cat "$PATCH_LOG" >>"$LOG"
  rm -f "$PATCH_LOG"

  if [ "$PATCH_RC" != "0" ] || [ ! -s "$OUT" ]; then
    echo "PAC-safe return-value patch failed"
    rm -f "$AIR"
    return 1
  fi

  rm -f "$AIR"

  echo "[*] Output:"
  ls -lh "$OUT"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$OUT"
  else
    shasum -a 256 "$OUT"
  fi
  return 0
}

main "$@"
