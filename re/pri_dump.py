"""Dump data items (in stored order) and schema names from a PRI file."""
import struct, sys, re
b = open(sys.argv[1], 'rb').read()
toc_off, sec_start, nsec = struct.unpack_from('<IIH', b, 16)[0], struct.unpack_from('<I', b, 20)[0], struct.unpack_from('<H', b, 24)[0]
for i in range(nsec):
    o = toc_off + i*32
    ident = b[o:o+16].rstrip(b'\0 ').decode(); off, ln = struct.unpack_from('<II', b, o+24)
    s = sec_start + off + 32  # skip section header
    if ident == '[mrm_dataitem]' and (len(sys.argv) < 3 or sys.argv[2] == str(i)):
        _, ns, nb, total = struct.unpack_from('<IHHI', b, s)
        p = s + 12; ents = []
        for k in range(ns): ents.append(struct.unpack_from('<HH', b, p)); p += 4
        for k in range(nb): ents.append(struct.unpack_from('<II', b, p)); p += 8
        print(f"## section {i}: strings={ns} blobs={nb}")
        for k, (eo, el) in enumerate(ents):
            d = b[p+eo:p+eo+el]
            try:
                t = d.decode('utf-8').rstrip('\0')
                if '\0' in t: raise ValueError
            except ValueError: t = d.decode('utf-16le', 'replace').rstrip('\0')
            print(f"{k}\t{t!r}")
    if ident == '[mrm_hschemaex]' and len(sys.argv) > 2 and sys.argv[2] == 'names':
        d = b[s:s+ln]
        for m in re.finditer(rb'[\x20-\x7e]{3,}', d): print(m.group().decode())
        for m in re.finditer(rb'(?:[\x20-\x7e]\x00){3,}', d): print(m.group().decode('utf-16le'))
