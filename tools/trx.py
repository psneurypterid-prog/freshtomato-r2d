#!/usr/bin/env python3
"""Broadcom TRX v1 (HDR0) with a single partition - as the Xiaomi R2D CFE expects in os0/os1.

usage: trx.py build <lzma kernel> <out.trx>
       trx.py check <file.trx>          (exit status 1 on a bad image)
"""
import struct
import sys
import zlib

HDR = struct.Struct('<4sIIIIII')   # magic, len, crc32, flag_version, offsets[3]


def bcm_crc(data):
    # Broadcom hndcrc32 over the header tail + payload, stored inverted (= ~zlib.crc32)
    return (~zlib.crc32(data)) & 0xffffffff


def build(kernel, out, align=0x1000):
    body = open(kernel, 'rb').read()
    ln = (HDR.size + len(body) + align - 1) // align * align
    rest = struct.pack('<IIII', 0x00010000, HDR.size, 0, 0)
    payload = body + b'\0' * (ln - HDR.size - len(body))
    crc = bcm_crc(rest + payload)
    open(out, 'wb').write(struct.pack('<4sII', b'HDR0', ln, crc) + rest + payload)
    print('built %s len=0x%x crc=0x%08x' % (out, ln, crc))


def check(path):
    d = open(path, 'rb').read()
    if len(d) < HDR.size:
        print('%s: too short' % path)
        return False
    magic, ln, crc, fv, o0, o1, o2 = HDR.unpack(d[:HDR.size])
    ok = magic == b'HDR0' and HDR.size <= ln <= len(d) and o0 == HDR.size and bcm_crc(d[12:ln]) == crc
    print('%s: magic=%s len=0x%x crc=0x%08x %s' % (path, magic, ln, crc, 'OK' if ok else 'BAD'))
    return ok


if __name__ == '__main__':
    if len(sys.argv) == 4 and sys.argv[1] == 'build':
        build(sys.argv[2], sys.argv[3])
    elif len(sys.argv) == 3 and sys.argv[1] == 'check':
        sys.exit(0 if check(sys.argv[2]) else 1)
    else:
        sys.exit(__doc__)
