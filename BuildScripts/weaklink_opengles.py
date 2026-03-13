#!/usr/bin/env python3
"""
Post-process a Mach-O binary to weak-link OpenGLES.framework.

Why:
- Newer tvOS versions may not ship OpenGLES.framework.
- If the app is strongly linked against OpenGLES, dyld can terminate the app
  before main() runs (no in-app logs, no Safe Mode).
- VoidLink uses AVSampleBuffer/Metal, but a prebuilt dependency can still
  introduce a strong LC_LOAD_DYLIB for OpenGLES.

What it does:
- Finds LC_LOAD_DYLIB entries whose name matches:
    /System/Library/Frameworks/OpenGLES.framework/OpenGLES
  and patches the load command to LC_LOAD_WEAK_DYLIB in-place.

Notes:
- CI artifacts are built unsigned. Sideload tools will re-sign after patching.
- This is a pragmatic compatibility shim; the long-term fix is rebuilding the
  dependency stack without OpenGLES.
"""

from __future__ import annotations

import argparse
import os
import struct
import sys
from dataclasses import dataclass
from typing import List, Optional, Tuple


MH_MAGIC_64 = 0xFEEDFACF
FAT_MAGIC = 0xCAFEBABE
FAT_MAGIC_64 = 0xCAFEBABF

LC_LOAD_DYLIB = 0xC
LC_LOAD_WEAK_DYLIB = 0x18

OPENGLES_PATH = b"/System/Library/Frameworks/OpenGLES.framework/OpenGLES"


@dataclass(frozen=True)
class PatchResult:
    slice_offset: int
    patched_count: int


def _read_u32_le(buf: bytearray, off: int) -> int:
    return struct.unpack_from("<I", buf, off)[0]


def _write_u32_le(buf: bytearray, off: int, value: int) -> None:
    struct.pack_into("<I", buf, off, value)


def _patch_macho_slice(buf: bytearray, slice_offset: int) -> PatchResult:
    magic = _read_u32_le(buf, slice_offset)
    if magic != MH_MAGIC_64:
        raise ValueError(f"Unexpected Mach-O magic at {slice_offset:#x}: {magic:#x}")

    # mach_header_64 is 8 u32s = 32 bytes:
    # magic, cputype, cpusubtype, filetype, ncmds, sizeofcmds, flags, reserved
    ncmds = _read_u32_le(buf, slice_offset + 16)
    cmd_off = slice_offset + 32
    patched = 0

    for _ in range(ncmds):
        if cmd_off + 8 > len(buf):
            break
        cmd = _read_u32_le(buf, cmd_off)
        cmdsize = _read_u32_le(buf, cmd_off + 4)
        if cmdsize < 8 or cmd_off + cmdsize > len(buf):
            break

        if cmd == LC_LOAD_DYLIB and cmdsize >= 24:
            # dylib_command:
            # u32 cmd, u32 cmdsize, u32 name_offset, u32 timestamp,
            # u32 current_version, u32 compatibility_version
            name_off = _read_u32_le(buf, cmd_off + 8)
            if 0 <= name_off < cmdsize:
                raw = bytes(buf[cmd_off + name_off : cmd_off + cmdsize])
                name = raw.split(b"\x00", 1)[0]
                if name == OPENGLES_PATH:
                    _write_u32_le(buf, cmd_off, LC_LOAD_WEAK_DYLIB)
                    patched += 1

        cmd_off += cmdsize

    return PatchResult(slice_offset=slice_offset, patched_count=patched)


def _parse_fat_arches(buf: bytes) -> List[Tuple[int, int]]:
    # Returns list of (offset, size) for each slice in a FAT binary.
    magic_be = struct.unpack_from(">I", buf, 0)[0]
    if magic_be not in (FAT_MAGIC, FAT_MAGIC_64):
        return []

    nfat_arch = struct.unpack_from(">I", buf, 4)[0]
    arches: List[Tuple[int, int]] = []
    off = 8

    if magic_be == FAT_MAGIC:
        for _ in range(nfat_arch):
            # struct fat_arch (big-endian): cputype, cpusubtype, offset, size, align
            _, _, slice_off, slice_size, _ = struct.unpack_from(">IIIII", buf, off)
            arches.append((slice_off, slice_size))
            off += 20
    else:
        for _ in range(nfat_arch):
            # struct fat_arch_64 (big-endian): cputype, cpusubtype, offset, size, align, reserved
            _, _, slice_off, slice_size, _, _ = struct.unpack_from(">IIQQII", buf, off)
            arches.append((int(slice_off), int(slice_size)))
            off += 32

    return arches


def patch_file(path: str) -> List[PatchResult]:
    with open(path, "rb") as f:
        data = bytearray(f.read())

    arches = _parse_fat_arches(data)
    results: List[PatchResult] = []

    if arches:
        for slice_off, _slice_size in arches:
            results.append(_patch_macho_slice(data, slice_off))
    else:
        results.append(_patch_macho_slice(data, 0))

    with open(path, "wb") as f:
        f.write(data)

    return results


def main(argv: Optional[List[str]] = None) -> int:
    p = argparse.ArgumentParser(description="Weak-link OpenGLES.framework in a Mach-O binary")
    p.add_argument("binary", help="Path to Mach-O executable (e.g. VoidLinkTV.app/VoidLinkTV)")
    args = p.parse_args(argv)

    path = args.binary
    if not os.path.isfile(path):
        print(f"error: file not found: {path}", file=sys.stderr)
        return 2

    try:
        results = patch_file(path)
    except Exception as e:
        print(f"error: failed to patch: {e}", file=sys.stderr)
        return 1

    total = sum(r.patched_count for r in results)
    if total == 0:
        print("weaklink_opengles: no OpenGLES LC_LOAD_DYLIB entries found (no changes)")
    else:
        for r in results:
            if r.patched_count:
                print(f"weaklink_opengles: patched {r.patched_count} slice(s) at offset {r.slice_offset:#x}")
        print(f"weaklink_opengles: total patched: {total}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

