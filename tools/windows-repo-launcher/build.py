#!/usr/bin/env python3
"""Build the tiny root GameSmith.exe used by the GitHub source checkout.

The PE intentionally does only three things: find its own directory, make that
the working directory, and start launch-gamesmith.ps1 through PowerShell. The
PowerShell script owns the readable/download/bootstrap logic.
"""
from __future__ import annotations

import argparse
import struct
from pathlib import Path

IMAGE_BASE = 0x140000000
SECTION_RVA = 0x1000
RAW_PTR = 0x200
SECTION_RAW_SIZE = 0x400
SECTION_VIRTUAL_SIZE = 0x380
FILE_ALIGN = 0x200
SECTION_ALIGN = 0x1000

CODE_OFF = 0x000
COMMAND_OFF = 0x100
IMPORT_DESC_OFF = 0x200
IAT_OFF = 0x250
ILT_OFF = 0x280
GETMODULE_NAME_OFF = 0x2B0
SETCWD_NAME_OFF = 0x2C8
WINEXEC_NAME_OFF = 0x2E0
EXIT_NAME_OFF = 0x2F0
DLL_NAME_OFF = 0x310

COMMAND = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ".\\launch-gamesmith.ps1"'
IMPORTS = [
    (GETMODULE_NAME_OFF, b"GetModuleFileNameW"),
    (SETCWD_NAME_OFF, b"SetCurrentDirectoryW"),
    (WINEXEC_NAME_OFF, b"WinExec"),
    (EXIT_NAME_OFF, b"ExitProcess"),
]


def align(value: int, alignment: int) -> int:
    return (value + alignment - 1) & ~(alignment - 1)


def rva(off: int) -> int:
    return SECTION_RVA + off


def build_code() -> bytes:
    code = bytearray()
    labels: dict[str, int] = {}
    short_patches: list[tuple[int, str]] = []
    rip_patches: list[tuple[int, int]] = []

    def emit(data: bytes) -> None:
        code.extend(data)

    def label(name: str) -> None:
        labels[name] = len(code)

    def short(opcode: int, target: str) -> None:
        emit(bytes([opcode, 0]))
        short_patches.append((len(code) - 1, target))

    def call_iat(slot: int) -> None:
        emit(b"\xFF\x15\0\0\0\0")
        rip_patches.append((len(code) - 4, IAT_OFF + slot * 8))

    # Reserve shadow space plus a 1024-WCHAR path buffer. 0x828 also restores
    # 16-byte stack alignment for Win64 calls from the process entrypoint.
    emit(b"\x48\x81\xEC\x28\x08\x00\x00")  # sub rsp, 0x828
    emit(b"\x48\x8D\x5C\x24\x20")          # lea rbx, [rsp+0x20]
    emit(b"\x31\xC9")                        # xor ecx, ecx (hModule=NULL)
    emit(b"\x48\x89\xDA")                  # mov rdx, rbx (buffer)
    emit(b"\x41\xB8\x00\x04\x00\x00")  # mov r8d, 1024 WCHARs
    call_iat(0)                                # GetModuleFileNameW
    emit(b"\x85\xC0")                        # test eax, eax
    short(0x74, "launch")                    # jz launch
    emit(b"\x89\xC1")                        # mov ecx, eax (char count)
    emit(b"\xFF\xC9")                        # dec ecx

    label("scan")
    emit(b"\x66\x83\x3C\x4B\x5C")          # cmp word [rbx+rcx*2], '\\'
    short(0x74, "found")                     # je found
    emit(b"\xFF\xC9")                        # dec ecx
    short(0x79, "scan")                      # jns scan
    short(0xEB, "launch")                    # no slash -> keep inherited cwd

    label("found")
    emit(b"\x66\xC7\x04\x4B\x00\x00")     # terminate at final slash
    emit(b"\x48\x89\xD9")                  # mov rcx, rbx
    call_iat(1)                                # SetCurrentDirectoryW

    label("launch")
    emit(b"\x48\x8D\x0D\0\0\0\0")        # lea rcx, [rip+command]
    rip_patches.append((len(code) - 4, COMMAND_OFF))
    emit(b"\xBA\x01\x00\x00\x00")          # mov edx, SW_SHOWNORMAL
    call_iat(2)                                # WinExec
    emit(b"\x31\xC9")                        # xor ecx, ecx
    call_iat(3)                                # ExitProcess(0)
    emit(b"\xCC")

    for disp_pos, target_off in rip_patches:
        instr_end = disp_pos + 4
        disp = rva(target_off) - rva(instr_end)
        struct.pack_into("<i", code, disp_pos, disp)
    for disp_pos, target in short_patches:
        if target not in labels:
            raise ValueError(f"unknown label {target}")
        next_off = disp_pos + 1
        disp = labels[target] - next_off
        if not -128 <= disp <= 127:
            raise ValueError(f"short jump to {target} out of range")
        struct.pack_into("<b", code, disp_pos, disp)
    return bytes(code)


def build() -> bytes:
    section = bytearray(SECTION_RAW_SIZE)
    code = build_code()
    section[CODE_OFF:CODE_OFF + len(code)] = code

    command = COMMAND.encode("ascii") + b"\0"
    if COMMAND_OFF + len(command) >= IMPORT_DESC_OFF:
        raise ValueError("launcher command overlaps import table")
    section[COMMAND_OFF:COMMAND_OFF + len(command)] = command

    struct.pack_into("<IIIII", section, IMPORT_DESC_OFF,
                     rva(ILT_OFF), 0, 0, rva(DLL_NAME_OFF), rva(IAT_OFF))
    thunk_values = [rva(off) for off, _ in IMPORTS] + [0]
    for off in (IAT_OFF, ILT_OFF):
        struct.pack_into("<" + "Q" * len(thunk_values), section, off, *thunk_values)
    for off, name in IMPORTS:
        payload = b"\0\0" + name + b"\0"
        section[off:off + len(payload)] = payload
    dll = b"KERNEL32.dll\0"
    section[DLL_NAME_OFF:DLL_NAME_OFF + len(dll)] = dll

    headers = bytearray(RAW_PTR)
    headers[0:2] = b"MZ"
    struct.pack_into("<I", headers, 0x3C, 0x80)
    stub = b"This program cannot be run in DOS mode.\r\n$"
    headers[0x40:0x40 + len(stub)] = stub

    pe = 0x80
    headers[pe:pe + 4] = b"PE\0\0"; pe += 4
    struct.pack_into("<HHIIIHH", headers, pe, 0x8664, 1, 0, 0, 0, 0xF0, 0x0022); pe += 20
    opt = pe
    struct.pack_into("<HBBIIIIIQIIHHHHHHIIIIHHQQQQII", headers, opt,
        0x20B, 14, 0,
        SECTION_RAW_SIZE, 0, 0,
        rva(CODE_OFF), SECTION_RVA,
        IMAGE_BASE, SECTION_ALIGN, FILE_ALIGN,
        6, 0, 0, 0, 6, 0,
        0,
        align(SECTION_RVA + SECTION_VIRTUAL_SIZE, SECTION_ALIGN),
        RAW_PTR, 0,
        2, 0x8160,
        0x100000, 0x1000, 0x100000, 0x1000,
        0, 16)
    dd = opt + 0x70
    struct.pack_into("<II", headers, dd + 1 * 8, rva(IMPORT_DESC_OFF), 40)
    struct.pack_into("<II", headers, dd + 12 * 8, rva(IAT_OFF), len(thunk_values) * 8)

    sec = opt + 0xF0
    headers[sec:sec + 8] = b".text\0\0\0"
    struct.pack_into("<IIIIIIHHI", headers, sec + 8,
                     SECTION_VIRTUAL_SIZE, SECTION_RVA,
                     SECTION_RAW_SIZE, RAW_PTR,
                     0, 0, 0, 0, 0x60000020)
    return bytes(headers + section)


def verify(path: Path) -> None:
    expected = build()
    actual = path.read_bytes()
    if actual != expected:
        raise SystemExit(f"{path} does not match deterministic launcher build")
    if not actual.startswith(b"MZ") or actual[0x80:0x84] != b"PE\0\0":
        raise SystemExit("not a PE executable")
    for _, name in IMPORTS:
        if name not in actual:
            raise SystemExit(f"missing import {name.decode()}")
    if COMMAND.encode("ascii") not in actual:
        raise SystemExit("launcher command missing")
    print(f"PASS: {path} is the deterministic {len(actual)}-byte GameSmith repo launcher")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("output", nargs="?", default="GameSmith.exe")
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()
    path = Path(args.output)
    if args.verify:
        verify(path)
    else:
        path.write_bytes(build())
        print(path)


if __name__ == "__main__":
    main()
