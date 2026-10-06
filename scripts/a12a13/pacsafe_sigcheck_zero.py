#!/usr/bin/env python3
from pathlib import Path
import struct
import sys

MOV_W0_0 = 0x52800000
WIDE_PATCH_WORD = 16
WIDE_RETAB_WORD = 24

WIDE_PATTERN = (
    (0x97000000, 0xfc000000),
    (0x14000009, 0xffffffff),
    (0x1100aea0, 0xffffffff),
    (0x14000005, 0xffffffff),
    (0x52800588, 0xffffffff),
    (0x14000002, 0xffffffff),
    (0x52800548, 0xffffffff),
    (0x2a0802a0, 0xffffffff),
    (0x94000000, 0xfc000000),
    (0x12800014, 0xffffffff),
    (0xf85a83a8, 0xffffffff),
    (0x90000000, 0x9f000000),
    (0xd503201f, 0xffffffff),
    (0xf9400129, 0xffc003ff),
    (0xeb08013f, 0xffffffff),
    (0x54000061, 0xff00001f),
    (0xaa1403e0, 0xffffffff),
    (0xa94d7bfd, 0xffffffff),
    (0xa94c4ff4, 0xffffffff),
    (0xa94b57f6, 0xffffffff),
    (0xa94a5ff8, 0xffffffff),
    (0xa94967fa, 0xffffffff),
    (0xa9486ffc, 0xffffffff),
    (0x910383ff, 0xffffffff),
    (0xd65f0fff, 0xffffffff),
)

def is_auto(value):
    return value.lower() == "auto"

def parse_u32(value):
    if is_auto(value):
        return None
    return int(value, 0) & 0xffffffff

def parse_off(value):
    if is_auto(value):
        return None
    return int(value, 0)

def read_u32(buf, off):
    return struct.unpack_from("<I", buf, off)[0]

def write_u32(buf, off, value):
    struct.pack_into("<I", buf, off, value)

def read_words(buf):
    return [
        struct.unpack_from("<I", buf, off)[0]
        for off in range(0, len(buf) - 3, 4)
    ]

def pattern_matches(words, idx, pattern):
    if idx + len(pattern) > len(words):
        return False

    for i, (want, mask) in enumerate(pattern):
        if (words[idx + i] & mask) != (want & mask):
            return False

    return True

def find_wide_site(buf):
    words = read_words(buf)
    hits = []

    for idx in range(0, len(words) - len(WIDE_PATTERN) + 1):
        if pattern_matches(words, idx, WIDE_PATTERN):
            hits.append(idx * 4)

    print("auto wide-site hits=" + str(len(hits)))
    for off in hits[:16]:
        print(f"auto wide-site start=0x{off:x}")

    if len(hits) != 1:
        print("refusing to patch: auto site is not unique")
        return None

    start = hits[0]
    return start + WIDE_PATCH_WORD * 4, start + WIDE_RETAB_WORD * 4

def main(argv):
    if len(argv) not in (6, 7):
        print("usage: pacsafe_sigcheck_zero.py <input> <output> <patch_off|auto> <expected_old|auto> <retab_off|auto> [expected_retab|auto]")
        return 2

    src = Path(argv[1])
    dst = Path(argv[2])
    patch_off = parse_off(argv[3])
    expected_old = parse_u32(argv[4])
    retab_off = parse_off(argv[5])
    expected_retab = parse_u32(argv[6]) if len(argv) == 7 else 0xd65f0fff

    if not src.is_file():
        print(f"missing input: {src}")
        return 1

    buf = bytearray(src.read_bytes())

    if patch_off is None or retab_off is None:
        if patch_off is not None or retab_off is not None:
            print("refusing to patch: auto patch and retab offsets must be used together")
            return 1

        found = find_wide_site(buf)
        if found is None:
            return 1

        patch_off, retab_off = found

    for name, off in (("patch", patch_off), ("retab", retab_off)):
        if off < 0 or off + 4 > len(buf):
            print(f"{name} offset out of range: 0x{off:x}")
            return 1

    old = read_u32(buf, patch_off)
    retab = read_u32(buf, retab_off)

    if expected_old is None:
        expected_old = 0xaa1403e0
    if expected_retab is None:
        expected_retab = 0xd65f0fff

    print(f"patch_off=0x{patch_off:x}")
    print(f"old=0x{old:08x}")
    print(f"expected_old=0x{expected_old:08x}")
    print(f"new=0x{MOV_W0_0:08x}")
    print(f"retab_off=0x{retab_off:x}")
    print(f"retab=0x{retab:08x}")
    print(f"expected_retab=0x{expected_retab:08x}")

    if old != expected_old:
        print("refusing to patch: old instruction mismatch")
        return 1

    if retab != expected_retab:
        print("refusing to patch: return instruction mismatch")
        return 1

    write_u32(buf, patch_off, MOV_W0_0)
    dst.write_bytes(buf)
    print(f"wrote {dst}")
    return 0

if __name__ == "__main__":
    sys.exit(main(sys.argv))
