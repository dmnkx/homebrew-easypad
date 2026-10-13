import struct, sys
b = open(sys.argv[1], 'rb').read()
print(b[:8], len(b))
toc_off, sec_start, nsec = struct.unpack_from('<IIH', b, 16)[0], struct.unpack_from('<I', b, 20)[0], struct.unpack_from('<H', b, 24)[0]
print('hdr', b[8:40].hex())
for i in range(nsec):
    o = toc_off + i*32
    ident = b[o:o+16]; flags, sflags, qual, off, ln = struct.unpack_from('<HHIII', b, o+16)
    print(i, ident, flags, sflags, qual, off, ln, 'abs', sec_start+off)
