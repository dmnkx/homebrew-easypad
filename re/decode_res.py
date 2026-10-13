"""Decode menu / string table / accelerator / dialog payloads from a PE .mui
using the payload file ranges reported by REA inspect_pe_resources."""
import struct, sys

def u16(b, o): return struct.unpack_from('<H', b, o)[0]
def u32(b, o): return struct.unpack_from('<I', b, o)[0]
def wstr(b, o):
    e = o
    while u16(b, e): e += 2
    return b[o:e].decode('utf-16le'), e + 2

def strings(b, block):
    o = 0
    for i in range(16):
        n = u16(b, o); o += 2
        if n:
            print(f"  {(block-1)*16+i}: {b[o:o+2*n].decode('utf-16le')!r}")
        o += 2*n

VK = {8:'Back',9:'Tab',13:'Enter',27:'Esc',45:'Ins',46:'Del',112:'F1',113:'F2',114:'F3',115:'F4',116:'F5',117:'F6',187:'=/+',189:'-',107:'Num+',109:'Num-',48:'0',96:'Num0'}
def accels(b):
    for o in range(0, len(b), 8):
        f, key, cmd = b[o], u16(b, o+2), u16(b, o+4)
        mods = '+'.join(m for bit, m in ((8,'Ctrl'),(4,'Shift'),(16,'Alt')) if f & bit)
        k = VK.get(key, chr(key) if 32 < key < 127 else hex(key)) if f & 1 else f"char {key:#x}"
        print(f"  {mods+'+' if mods else ''}{k} -> cmd {cmd}")

def menu(b):
    ver = u16(b, 0)
    if ver == 0:
        o = 4; depth = 0; stack = []
        while o < len(b):
            fl = u16(b, o); o += 2
            if fl & 0x10:
                s, o = wstr(b, o); print('  '*depth + f"[POPUP] {s!r}"); stack.append(bool(fl & 0x80)); depth += 1
            else:
                mid = u16(b, o); o += 2; s, o = wstr(b, o)
                print('  '*depth + (f"{mid}: {s!r}" if s or mid else "----") + (" (grayed)" if fl & 1 else "") + (" (checked)" if fl & 8 else ""))
                if fl & 0x80:
                    while stack:
                        depth -= 1
                        if not stack.pop(): break
                    else:
                        break
    else:
        print("  MENUEX ver", ver, b[:64].hex())

def dialog(b):
    ex = u16(b, 0) == 1 and u16(b, 2) == 0xFFFF
    if ex:
        style = u32(b, 12); n = u16(b, 16); x, y, cx, cy = struct.unpack_from('<hhhh', b, 18); o = 26
    else:
        style = u32(b, 0); n = u16(b, 8); x, y, cx, cy = struct.unpack_from('<hhhh', b, 10); o = 18
    def sz(o):
        if u16(b, o) == 0xFFFF: return f"#{u16(b, o+2)}", o + 4
        return wstr(b, o)
    m, o = sz(o); c, o = sz(o); t, o = wstr(b, o)
    print(f"  DIALOG{'EX' if ex else ''} title={t!r} size={cx}x{cy} style={style:#x} items={n}")
    if style & 0x40:
        pt = u16(b, o); o += 2
        if ex: o += 4
        f, o = wstr(b, o); print(f"  font {f} {pt}")
    CLS = {0x80:'Button',0x81:'Edit',0x82:'Static',0x83:'ListBox',0x84:'ScrollBar',0x85:'ComboBox'}
    for _ in range(n):
        o = (o + 3) & ~3
        if ex:
            st = u32(b, o+8); x, y, cx, cy = struct.unpack_from('<hhhh', b, o+12); cid = u32(b, o+20); o += 24
        else:
            st = u32(b, o); x, y, cx, cy = struct.unpack_from('<hhhh', b, o+8); cid = u16(b, o+16); o += 18
        if u16(b, o) == 0xFFFF: cl = CLS.get(u16(b, o+2), hex(u16(b, o+2))); o += 4
        else: cl, o = wstr(b, o)
        tx, o = sz(o); extra = u16(b, o); o += 2 + extra
        print(f"    {cl:9} id={cid:<6} ({x},{y},{cx},{cy}) style={st:#010x} {tx!r}")

if __name__ == '__main__':
    path = sys.argv[1]; data = open(path, 'rb').read()
    for spec in sys.argv[2:]:
        kind, name, off, n = spec.split(':'); p = data[int(off):int(off)+int(n)]
        print(f"== {kind} {name}")
        try:
            {'str': lambda: strings(p, int(name)), 'acc': lambda: accels(p), 'menu': lambda: menu(p), 'dlg': lambda: dialog(p)}[kind]()
        except Exception as e:
            print("  !! decode error", e)
