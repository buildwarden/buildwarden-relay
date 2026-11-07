"""Write a minimal arm64 Linux Image that answers one yes/no question about
VZ's boot handoff by how the VM ends: PSCI SYSTEM_OFF (VZ reports "guest
stopped") means yes, a WFE spin (the runner times out) means no.

usage: python3 -I mkstub.py <variant> <out>

variants:
  control  power off unconditionally: VZ accepts the header and runs the code
  spin     never power off: the negative control
  dtb      power off if x0 points at a flattened device tree (magic d00dfeed)
  pc       power off if the code runs at 0x7xxxxxxx, VZ's RAM (not 0x4xxxxxxx)
  uart     store to QEMU virt's PL011 (0x09000000), then power off: a clean
           stop means VZ drops the write, a run-time error means it faults
  ecam     the dtb test at 0x40000000, where the stock loader looks for the
           device tree (QEMU's RAM base, VZ's PCI ECAM window)

The header is the documented 64-byte arm64 Image header
(Documentation/arch/arm64/booting.rst): a branch over the header, text_offset
0, image_size, flags (little-endian, 4K pages, placeable anywhere), and the
magic "ARM\\x64" at offset 56. Instructions are hand-encoded A64.
"""

import struct
import sys

# Shared tails. Each variant's test ends in b.ne to SPIN; falling through
# reaches OFF.
OFF = [
    0xD2800100,  # movz x0, #0x0008
    0xF2B08000,  # movk x0, #0x8400, lsl #16   -> PSCI SYSTEM_OFF 0x84000008
    0xD4000002,  # hvc  #0
]
SPIN = [
    0xD503205F,  # wfe
    0x17FFFFFF,  # b    .-4
]
BNE_OVER_OFF = 0x54000081  # b.ne +16: skips the three OFF words to SPIN

IS_FDT_AT_X0 = [
    0xB9400001,  # ldr  w1, [x0]
    0x5281BA02,  # movz w2, #0x0dd0
    0x72BDBFC2,  # movk w2, #0xedfe, lsl #16  -> d00dfeed read little-endian
    0x6B02003F,  # cmp  w1, w2
    BNE_OVER_OFF,
]

VARIANTS = {
    "control": OFF + SPIN,
    "spin": SPIN,
    "dtb": IS_FDT_AT_X0 + OFF + SPIN,
    "ecam": [
        0xD2A80000,  # movz x0, #0x4000, lsl #16  -> 0x40000000
    ] + IS_FDT_AT_X0 + OFF + SPIN,
    "uart": [
        0xD2A12001,  # movz x1, #0x0900, lsl #16  -> 0x09000000
        0x52800822,  # movz w2, #0x41
        0xB9000022,  # str  w2, [x1]
    ] + OFF + SPIN,
    "pc": [
        0x10000001,  # adr  x1, .
        0xD35CFC21,  # lsr  x1, x1, #28
        0xF1001C3F,  # cmp  x1, #7
        BNE_OVER_OFF,
    ] + OFF + SPIN,
}


def image(code):
    body = b"".join(struct.pack("<I", w) for w in code)
    size = 64 + len(body)
    header = struct.pack(
        "<IIQQQQQQII",
        0x14000010,  # code0: b +64, over the header
        0,           # code1
        0,           # text_offset
        size,        # image_size
        0b1010,      # flags: LE, 4K pages, anywhere in RAM
        0, 0, 0,     # res2-res4
        0x644D5241,  # magic "ARM\x64"
        0,           # res5
    )
    assert len(header) == 64
    return header + body


def main():
    variant, out = sys.argv[1], sys.argv[2]
    with open(out, "wb") as f:
        f.write(image(VARIANTS[variant]))


if __name__ == "__main__":
    main()
