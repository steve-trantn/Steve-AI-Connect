# -*- coding: utf-8 -*-
"""Chuyen so lieu trac ngang TDT (vnroad) .tdtn -> NTD (TDN Version 3.5) cho ADSCivil.

Dung:
  python -I -X utf8 tdtn2ntd.py <file.tdtn | thu_muc> [...] [-o THU_MUC_RA] [--map ma.json]
         [--re-trai D2,D5] [--dao-ben] [--xem]

Ket qua cho moi file: <ten>.ntd + <ten>_ma.csv (doi chieu tung diem, giu ma TDT goc).
"""
import argparse, csv, glob, json, math, os, struct, sys

# ---------------- doc .tdtn ----------------
def doc_tdtn(path):
    b = open(path, 'rb').read()
    I = lambda o: struct.unpack_from('<i', b, o)[0]
    D = lambda o: struct.unpack_from('<d', b, o)[0]

    def chuoi(p):
        L = I(p)
        if not 0 <= L <= 256:
            raise ValueError(f'do dai chuoi sai ({L}) tai byte {p}')
        raw = b[p + 4:p + 4 + L]
        try:
            s = raw.decode('utf-8')
        except UnicodeDecodeError:
            s = raw.decode('cp1258', 'replace')
        return s, p + 4 + L

    def ben(p):
        c = I(p); p += 4
        if not 0 <= c <= 10000:
            raise ValueError(f'so diem sai ({c}) tai byte {p-4}')
        pts = [(D(p + 16 * i), D(p + 16 * i + 8)) for i in range(c)]; p += 16 * c
        ma = [I(p + 4 * i) for i in range(c)]; p += 4 * c
        return pts, ma, p

    n = I(0); p = 4; coc = []
    for _ in range(n):
        ten, p = chuoi(p)
        p += 4                                   # truong int (luon 0)
        ly_trinh, cao_do = D(p), D(p + 8); p += 16
        goc, p = chuoi(p)
        p += 48                                  # vung du phong (0)
        trai, ma_t, p = ben(p)
        phai, ma_p, p = ben(p)
        coc.append(dict(ten=ten, lt=ly_trinh, z=cao_do, goc=goc,
                        trai=trai, ma_t=ma_t, phai=phai, ma_p=ma_p))
    if p != len(b):
        raise ValueError(f'cau truc khong khop: doc {p}/{len(b)} byte')
    return coc

# ---------------- goc ----------------
def goc_do(s):
    """'180' -> 180 ; '9.27.137' -> 9 do 27 phut 13.7 giay."""
    a = s.strip().split('.')
    d = float(a[0]) if a[0] else 0.0
    m = float(a[1]) if len(a) > 1 and a[1] else 0.0
    sec = float(a[2][:2] + '.' + a[2][2:]) if len(a) > 2 and a[2] else 0.0
    return d + m / 60 + sec / 3600

def goc_ntd(s, re_trai):
    """TDT: '180' = thang; goc khac = goc chuyen huong. NTD: pi = thang."""
    if s.strip() in ('', '180'):
        return math.pi
    g = goc_do(s) % 360
    if g > 180:
        g -= 360                                 # 359.59.600 = 0 (thang)
    g = math.radians(g)
    return math.pi + g if re_trai else math.pi - g

# ---------------- ghi NTD ----------------
def chuyen(src, out_dir, cmap, re_trai, dao_ben):
    coc = doc_tdtn(src)
    ten = os.path.splitext(os.path.basename(src))[0]
    dst = os.path.join(out_dir, ten + '.ntd')
    dst_csv = os.path.join(out_dir, ten + '_ma.csv')

    def ma_ads(c):
        return cmap.get(str(c), str(c) if 1 <= c <= 130 else '')

    L = ['TDN\tVersion 3.5', 'SYMBOLS\tND\tTD\tP\tTC\tNC', 'TYPEINPUT\t0\t0\t0\t0\t0']
    rows, canh_bao, dem = [], [], {}
    for c in coc:
        a = goc_ntd(c['goc'], c['ten'] in re_trai)
        if abs(a - math.pi) > 1e-9:
            canh_bao.append(f"  coc {c['ten']}: goc TDT {c['goc']} -> {a:.6f} rad "
                            f"({'re trai' if c['ten'] in re_trai else 're phai'}) - kiem tra tren binh do")
        L.append(f"POLE\t{c['ten']}\t{c['lt']:.6f}\t{c['z']:.6f}\t0.00000\t0.000000\t{a:.12f}")
        t, mt, ph, mp = c['trai'], c['ma_t'], c['phai'], c['ma_p']
        if dao_ben:
            t, mt, ph, mp = ph, mp, t, mt
        for tag, pts, ms, sg in (('TARGETL', t, mt, -1), ('TARGETR', ph, mp, 1)):
            for (x, y), m in zip(pts, ms):
                v = ma_ads(m)
                L.append(f"{tag}\t{sg*abs(x):.6f}\t{y:.6f}\t{v or 'NOBLOCK'}*0*")
                rows.append([c['ten'], 'T' if sg < 0 else 'P', f'{sg*abs(x):.3f}', f'{y:.3f}', m, v])
                if m:
                    dem[m] = dem.get(m, 0) + 1

    txt = '\r\n'.join(L) + '\r\n'
    try:
        data = txt.encode('cp1252')
    except UnicodeEncodeError:
        data = txt.encode('utf-8')
    open(dst, 'wb').write(data)
    with open(dst_csv, 'w', newline='', encoding='utf-8-sig') as f:
        w = csv.writer(f)
        w.writerow(['Coc', 'Ben', 'KhoangCach', 'CaoDo', 'MaTDT', 'MaADS'])
        w.writerows(rows)

    chua_map = sorted(m for m in dem if not ma_ads(m))
    print(f'{src}\n  -> {dst}\n  -> {dst_csv}\n  {len(coc)} coc, {len(rows)} diem')
    print('  ma TDT (so diem): ' + ', '.join(f'{m}:{dem[m]}->{ma_ads(m) or "NOBLOCK"}' for m in sorted(dem)))
    if chua_map:
        print(f'  CANH BAO: ma TDT {chua_map} chua co ma ADSCivil (ghi NOBLOCK, ma goc van trong CSV)')
    for s in canh_bao:
        print(s)

def xem(src):
    for c in doc_tdtn(src):
        print(f"{c['ten']:10} LT={c['lt']:9.3f} Z={c['z']:7.3f} goc={c['goc']}")
        for nm, pts, ms in (('T', c['trai'], c['ma_t']), ('P', c['phai'], c['ma_p'])):
            print(f'   {nm}', [(round(x, 2), round(y, 2), m) for (x, y), m in zip(pts, ms)])

def ban_ma_mac_dinh():
    """Bang ma nguoi dung tu sua (~/Steve-CAD-AI/ma_TDT_sang_ADS.json, cap nhat chuong trinh khong dong vao)
    truoc, roi bang ma di kem skill."""
    for p in (os.path.join(os.path.expanduser('~'), 'Steve-CAD-AI', 'ma_TDT_sang_ADS.json'),
              os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'ma_TDT_sang_ADS.json')):
        if os.path.isfile(p):
            return p
    return None

def main():
    ap =argparse.ArgumentParser(description='TDT .tdtn -> NTD (ADSCivil)')
    ap.add_argument('vao', nargs='+', help='file .tdtn hoac thu muc')
    ap.add_argument('-o', '--out', help='thu muc ra (mac dinh: <thu muc file>/<ten>_NTD)')
    ap.add_argument('--map', help='JSON doi ma TDT -> ma Fcode ADSCivil, vd {"-1":"35","2":"2"} '
                    '(mac dinh: ~/Steve-CAD-AI/ma_TDT_sang_ADS.json neu co, khong thi bang di kem skill)')
    ap.add_argument('--re-trai', default='', help='ten cac coc dinh re trai, cach nhau dau phay')
    ap.add_argument('--dao-ben', action='store_true', help='dao trai/phai neu trac ngang bi nguoc')
    ap.add_argument('--xem', action='store_true', help='chi in noi dung, khong ghi file')
    a = ap.parse_args()

    files = []
    for v in a.vao:
        files += sorted(glob.glob(os.path.join(v, '*.tdtn'))) if os.path.isdir(v) else [v]
    if not files:
        sys.exit('Khong co file .tdtn nao.')
    if not a.map:
        a.map = ban_ma_mac_dinh()
    cmap = json.load(open(a.map, encoding='utf-8-sig')) if a.map else {}
    if a.map:
        print(f'Bang ma: {a.map}')
    re_trai = {s.strip() for s in a.re_trai.split(',') if s.strip()}

    loi = 0
    for f in files:
        try:
            if a.xem:
                xem(f); continue
            od = a.out or os.path.join(os.path.dirname(os.path.abspath(f)),
                                       os.path.splitext(os.path.basename(f))[0] + '_NTD')
            os.makedirs(od, exist_ok=True)
            chuyen(f, od, cmap, re_trai, a.dao_ben)
        except Exception as e:
            loi += 1
            print(f'LOI {f}: {e}')
    sys.exit(1 if loi else 0)

if __name__ == '__main__':
    main()
