"""Skill tdtn2ntd: TDT .tdtn -> NTD. Builds a small .tdtn in a temp folder (no customer data), converts it and checks
the NTD lines, angles (turning angle, --re-trai), codes, the user's own code table and a broken file.
Usage: python tests/tdtn.py <repo>"""
import math
import os
import struct
import subprocess
import sys
import tempfile

root = sys.argv[1]
script = os.path.join(root, 'server', 'skills', 'tdtn2ntd', 'scripts', 'tdtn2ntd.py')
bad = 0


def check(name, ok, info=''):
    global bad
    print(('PASS  ' if ok else 'FAIL  ') + 'tdtn2ntd: ' + name + ('' if ok else '  ' + str(info)[:500]), flush=True)
    bad += not ok


def s(t):
    b = t.encode('utf-8')
    return struct.pack('<i', len(b)) + b


def side(pts, codes):
    return struct.pack('<i', len(pts)) + b''.join(struct.pack('<dd', x, z) for x, z in pts) + b''.join(struct.pack('<i', c) for c in codes)


def pole(name, km, z, angle, left, right):
    return s(name) + struct.pack('<i', 0) + struct.pack('<dd', km, z) + s(angle) + b'\0' * 48 + side(*left) + side(*right)


data = struct.pack('<i', 3) + \
    pole('D1', 0.0, 10.5, '180', ([(2.5, 10.4), (6.0, 10.1)], [12, 0]), ([(3.0, 10.6)], [2])) + \
    pole('D2', 25.0, 10.8, '9.27.137', ([(4.0, 10.7)], [-1]), ([(4.0, 10.9), (7.5, 11.0)], [0, 999])) + \
    pole('D3', 50.0, 11.0, '359.59.600', ([(1.0, 11.0)], [0]), ([(1.0, 11.1)], [0]))

tmp = tempfile.mkdtemp(prefix='tdtn-')
home = os.path.join(tmp, 'home')
os.makedirs(os.path.join(home, 'Steve-CAD-AI'))
src = os.path.join(tmp, 'TUYENA.tdtn')
open(src, 'wb').write(data)
env = dict(os.environ, USERPROFILE=home, HOME=home)


def run(*args):
    return subprocess.run([sys.executable, '-I', '-X', 'utf8', script, *args], capture_output=True, text=True, env=env)


r = run(src)
out = os.path.join(tmp, 'TUYENA_NTD', 'TUYENA.ntd')
check('chuyển xong', r.returncode == 0 and os.path.isfile(out), r.stdout + r.stderr)
check('dùng bảng mã đi kèm', 'ma_TDT_sang_ADS.json' in r.stdout and 'Steve-CAD-AI' not in r.stdout, r.stdout)
L = open(out, encoding='utf-8', newline='').read().split('\r\n') if os.path.isfile(out) else []
check('đầu file NTD', L[:1] == ['TDN\tVersion 3.5'], L[:3])
poles = [l.split('\t') for l in L if l.startswith('POLE')]
check('3 cọc', [p[1] for p in poles] == ['D1', 'D2', 'D3'], poles)
g = lambda i: float(poles[i][6])
turn = math.radians(9 + 27 / 60 + 13.7 / 3600)
check('180 = đi thẳng (π)', len(poles) == 3 and abs(g(0) - math.pi) < 1e-9, poles)
check('góc chuyển hướng rẽ phải = π - góc', len(poles) == 3 and abs(g(1) - (math.pi - turn)) < 1e-9, poles)
check('359.59.600 = đi thẳng', len(poles) == 3 and abs(g(2) - math.pi) < 1e-9, poles)
check('trái âm, có mã', 'TARGETL\t-2.500000\t10.400000\t12*0*' in L, L)
check('điểm không mã ghi NOBLOCK', 'TARGETL\t-6.000000\t10.100000\tNOBLOCK*0*' in L, L)
check('mã ngoài 1-130 ghi NOBLOCK và cảnh báo', 'TARGETR\t7.500000\t11.000000\tNOBLOCK*0*' in L and '999' in r.stdout, r.stdout)
csvf = os.path.join(tmp, 'TUYENA_NTD', 'TUYENA_ma.csv')
check('CSV giữ mã TDT gốc', os.path.isfile(csvf) and ',999,' in open(csvf, encoding='utf-8-sig').read())

r = run(src, '--re-trai', 'D2', '-o', os.path.join(tmp, 'b'))
L = open(os.path.join(tmp, 'b', 'TUYENA.ntd'), encoding='utf-8', newline='').read().split('\r\n') if r.returncode == 0 else []
p2 = [l.split('\t') for l in L if l.startswith('POLE\tD2')]
check('--re-trai: π + góc', p2 and abs(float(p2[0][6]) - (math.pi + turn)) < 1e-9, r.stdout + r.stderr)

open(os.path.join(home, 'Steve-CAD-AI', 'ma_TDT_sang_ADS.json'), 'w', encoding='utf-8').write('{"12": "35", "-1": "7"}')
r = run(src, '-o', os.path.join(tmp, 'c'))
L = open(os.path.join(tmp, 'c', 'TUYENA.ntd'), encoding='utf-8', newline='').read() if r.returncode == 0 else ''
check('bảng mã của người dùng được ưu tiên', 'Steve-CAD-AI' in r.stdout and '\t35*0*' in L and '\t7*0*' in L, r.stdout)

r = run(src, '--xem')
check('--xem không ghi file', r.returncode == 0 and 'D2' in r.stdout and not os.path.isdir(os.path.join(tmp, 'd')))

broken = os.path.join(tmp, 'HONG.tdtn')
open(broken, 'wb').write(data + b'\0\0\0\0')
r = run(broken)
check('file khác cấu trúc: báo lỗi, không ghi', r.returncode == 1 and 'cau truc khong khop' in r.stdout
      and not os.path.isfile(os.path.join(tmp, 'HONG_NTD', 'HONG.ntd')), r.stdout)

os.makedirs(os.path.join(tmp, 'thu-muc'))
for n in 'A', 'B':
    open(os.path.join(tmp, 'thu-muc', n + '.tdtn'), 'wb').write(data)
r = run(os.path.join(tmp, 'thu-muc'))
check('cả thư mục', r.returncode == 0 and all(os.path.isfile(os.path.join(tmp, 'thu-muc', n + '_NTD', n + '.ntd')) for n in 'AB'), r.stdout)

sys.exit(1 if bad else 0)
