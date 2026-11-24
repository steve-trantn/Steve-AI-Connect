"""export_ifc without a CAD: fake solids, real file. Run with the Python of the installed server (needs pywin32, mcp)."""
import os, re, sys, tempfile

sys.path.insert(0, os.path.join(sys.argv[1], 'server'))
from stevecad import ifc, meta, tools

bad = 0


def check(name, ok, info=''):
    global bad
    print(('PASS  ' if ok else 'FAIL  ') + name + ('' if ok else '  ' + str(info)[:500]), flush=True)
    bad += not ok


class Solid:
    ObjectName, Color, Handle, Volume = 'AcDb3dSolid', 1, 'A1', 6000.0
    Layer = 'CONG'

    def GetBoundingBox(self):
        return (10.0, 20.0, 5.0), (20.0, 40.0, 35.0)


class Doc:
    Name = 'thu.dwg'


f = getattr(ifc.export_ifc, '__wrapped__', ifc.export_ifc)
ifc.C.drawings = type('D', (), {'target': staticmethod(lambda: Doc())})
ifc._solids = lambda d, h, l: [Solid()]
meta.read = lambda e: None
d = tempfile.mkdtemp()
for unit, k in (('m', 1), ('mm', 0.001), ('ft', 0.3048), ('us-ft', 1200 / 3937), ('inch', 0.0254)):
    p = os.path.join(d, unit + '.ifc')
    r = f(p, units=unit)
    t = open(r['path'], encoding='ascii').read()
    m = re.search(r'IFCRECTANGLEPROFILEDEF\(.AREA.,\$,#\d+,([\d.E+-]+),([\d.E+-]+)\)', t)
    h = re.search(r'IFCEXTRUDEDAREASOLID\(#\d+,#\d+,#\d+,([\d.E+-]+)\)', t)
    v = re.search(r"IFCQUANTITYVOLUME\('NetVolume',\$,\$,([\d.E+-]+)", t)
    got = [float(m.group(1)), float(m.group(2)), float(h.group(1)), float(v.group(1))]
    check('IFC ' + unit + ': kích thước và thể tích ra mét', all(abs(a - b) < 1e-3 + abs(b) * 1e-4 for a, b in zip(got, [10 * k, 20 * k, 30 * k, 6000 * k ** 3])), got)
check('IFC có khối nhìn thấy được, có màu, ghi rõ gần đúng', 'IFCBOUNDINGBOX' not in t and 'IFCSTYLEDITEM' in t and 'IFCBOOLEAN(.T.)' in t and r['bounding_box_only'] == ['A1'])
try:
    import ifcopenshell
    check('ifcopenshell mở được', len(ifcopenshell.open(r['path']).by_type('IfcBuildingElementProxy')) == 1)
except ImportError:
    print('      (không có ifcopenshell, bỏ qua bước mở thử)')
n = len(os.listdir(d))
r = f(os.path.join(d, 'xem.ifc'), units='m', preview=True)
check('xem trước không ghi file', r['elements'] == 1 and r['approximate'] == 1 and r['layers'][0]['volume_m3'] == 6000 and len(os.listdir(d)) == n, r)
for bad_unit in ('', 'feet?', 'km'):
    try:
        f(os.path.join(d, 'x.ifc'), units=bad_unit)
        check('đơn vị lạ bị chặn ' + bad_unit, False)
    except ifc.UserError:
        check('đơn vị lạ bị chặn ' + repr(bad_unit), True)
# ---- non-graphic data: read, edit, export
import contextlib
store = {}


class S2(Solid):
    Centroid = (15.0, 30.0, 20.0)

    def __init__(self, h):
        self.Handle = h


sol = {h: S2(h) for h in ('A1', 'A2')}
geo = {'t': 'ext', 'o': [0, 0, 0], 'X': [1, 0, 0], 'Y': [0, 1, 0], 'E': [0, 0, 1], 'lo': 0, 'hi': 1, 'loops': [[[0, 0], [1, 0], [1, 1]]]}
store['A1'] = {'v': 1, 'part': 'Tường đầu BT M250', 'props': {'structure': 'CH4', 'Mác': 'cũ'}, 'geo': geo, 'chk': {'vol': 6000.0, 'cen': [15.0, 30.0, 20.0]}}
meta.read = lambda e: __import__('copy').deepcopy(store.get(e.Handle))
meta.write = lambda e, rec, d=None: store.__setitem__(e.Handle, rec)


def by(d, h):
    if h not in sol:
        raise ifc.UserError('không có ' + h)
    return sol[h]


ifc.by_handle = by
ifc._solids = lambda d, h, l: [sol[x] for x in h] if h else list(sol.values())
ifc.editing = lambda: contextlib.nullcontext(Doc())
ifc.done = lambda d, **k: dict(k, ok=True)
un = lambda fn: getattr(fn, '__wrapped__', fn)
r = un(ifc.solid_info)()
check('đọc thông tin khối', r['total'] == 2 and r['items'][0]['structure'] == 'CH4' and r['items'][0]['props'] == {'Mác': 'cũ'} and not r['items'][0]['approximate'] and r['items'][1]['approximate'] and r['extra_fields'] == ['Mác'], r)
w = un(ifc.tag_solids)(rows=[{'handle': 'A1', 'name': 'Tường "đầu" số 1', 'props': {'Mác': '', 'station': 'Km8+423'}}, {'handle': 'A2', 'name': 'Khối 2', 'material': 'BTCT M300', 'props': {'Nhà thầu': 'Công ty A'}}])
check('ghi theo dòng: thêm, xoá, giữ phần khác và công thức dựng', w['tagged'] == 2 and store['A1']['geo'] == geo and store['A1']['part'] == 'Tường đầu BT M250' and store['A1']['props'] == {'structure': 'CH4', 'station': 'Km8+423'} and store['A1']['chk']['vol'] == 6000.0 and store['A2']['material'] == 'BTCT M300', store)
old = __import__('copy').deepcopy(store)
for name, bad_rows in (('handle sai', [{'handle': 'A1', 'name': 'x'}, {'handle': 'ZZ', 'name': 'y'}]), ('tên cột rỗng', [{'handle': 'A1', 'props': {' ': 'x'}}]), ('giá trị quá dài', [{'handle': 'A1', 'name': 'x' * 501}])):
    try:
        un(ifc.tag_solids)(rows=bad_rows)
        check('chặn ' + name, False)
    except ifc.UserError:
        check('chặn ' + name + ', chưa ghi gì', store == old)
un(ifc.tag_solids)(handles=['A2'], part='Bản đáy', props={'structure': 'CH4'})
check('cách gọi cũ vẫn chạy', store['A2']['part'] == 'Bản đáy' and store['A2']['name'] == 'Khối 2')
r = f(os.path.join(d, 'tt.ifc'), units='m', project='Dự án Á', author='Tên')
t = open(r['path'], encoding='ascii').read()
enc = lambda s: ifc.s_(s)[1:-1]
check('IFC có Name, vật liệu, thông tin thêm, dự án', all(enc(x) in t for x in ('Khối 2', 'Công ty A', 'Nhà thầu', 'BTCT M300', 'Km8+423', 'Dự án Á')) and 'IFCMATERIAL(' in t, r)
try:
    import ifcopenshell
except ImportError:
    ifcopenshell = None
if ifcopenshell:
    m = ifcopenshell.open(r['path'])
    check('đọc lại bằng ifcopenshell', sorted(x.Name for x in m.by_type('IfcBuildingElementProxy')) == sorted(['Tường "đầu" số 1', 'Khối 2']))
print('FILE ' + r['path'])
# ---- a box culvert like the demo drawing: 22 segments x 2 m, two ends, in metres with large coordinates
from stevecad import culvert
E, X, Z = [0.8660254037844387, 0.5, 0.0], [0.5, -0.8660254037844387, 0.0], [0.0, 0.0, 1.0]
rect = lambda a, b, c, e: [[a, b], [c, b], [c, e], [a, e]]
ext = lambda lo, hi, *l: {'t': 'ext', 'o': [1187980.889, 580488.966, 89.33], 'X': X, 'Y': Z, 'E': E, 'lo': lo, 'hi': hi, 'loops': list(l)}
store.clear(); sol.clear()


def add(h, part, vol, geo, mat=''):
    o = S2(h); o.Volume = vol; sol[h] = o
    store[h] = {'v': 1, 'part': part, 'material': mat, 'props': {'structure': 'Cống hộp 4x4', 'station': 'Km8+423.31', 'type': 'Cống hộp BTCT 4,0x4,0 m'}, 'geo': geo, 'chk': {'vol': vol, 'cen': [15.0, 30.0, 20.0]}}


for n in range(22):
    main = ext(2 * n + (0.135), 2 * n + 2, rect(-2.4, -0.4, 2.4, 4.4), rect(-2, 0, 2, 4))
    add('D%d' % n, 'Đốt cống %02d BTCT M300 L=2,0 m' % (n + 1), 14.08, {'t': 'bool', 'op': 'union', 'a': main, 'b': [ext(2 * n, 2 * n + 0.135, rect(-2.2, -0.2, 2.2, 4.2), rect(-2, 0, 2, 4))]}, 'BTCT M300')
add('M1', 'Móng cống BT M200 dày 40 cm, rộng 6,0 m', 98.55, ext(1.5, 42.6, rect(-3, -0.8, 3, -0.4)), 'BT M200')
add('M2', 'Lót móng cống đá 2x4 M100', 24.6, ext(1.5, 42.6, rect(-3, -0.9, 3, -0.8)), 'đá 2x4 M100')
for end in ('thượng lưu', 'hạ lưu'):
    t = end[0]
    add('T' + t, 'Tường đầu %s BT M250' % end, 53.6, ext(0, 1, rect(-5, 0, 5, 7)), 'BT M250')
    add('L' + t, 'Tường cánh %s (trái) BT M250' % end, 7.42, ext(0, 1, rect(0, 0, 1, 5)), 'BT M250')
    add('P' + t, 'Tường cánh %s (phải) BT M250' % end, 7.42, ext(0, 1, rect(0, 0, 1, 5)), 'BT M250')
    add('H' + t, 'Đá hộc xây vữa M100 %s' % end, 22.8, ext(0, 1, rect(0, 0, 1, 1)), 'Đá hộc xây vữa M100')
    add('S' + t, 'Lót sân cống %s' % end, 4.56, ext(0, 1, rect(0, 0, 1, 1)), 'đá 2x4 M100')
Doc.GetVariable = lambda self, n: 4        # the drawing says mm but is drawn in metres
r = un(ifc.solid_info)(units='mm')
c = r['structures'][0]
check('đơn vị khai sai mm được phát hiện', r['unit_hint'] == 'm' and abs(c['volume'] - sum(s.Volume for s in sol.values())) < 1e-6, r['unit_hint'])
check('cống: 22 đốt x 2 m = 44 m, khẩu độ 4x4, thành 0,4', len(r['structures']) == 1 and c['title'] == 'Cống hộp 4x4 Km8+423.31: 22 đốt x 2 m = 44 m, khẩu độ 4x4 m, thành 0,4 m', c['title'])
check('nhóm đúng và đủ khối', [(x['name'], x['count']) for x in c['groups']] == [('Thân cống', 22), ('Móng thân cống', 2), ('Cửa thượng lưu', 5), ('Cửa hạ lưu', 5)], [(x['name'], x['count']) for x in c['groups']])
check('bộ phận giống nhau được gộp', [(p['name'], p['count']) for p in c['groups'][2]['parts']] == [('Tường đầu thượng lưu', 1), ('Tường cánh thượng lưu', 2), ('Đá hộc xây thượng lưu', 1), ('Lót sân cống thượng lưu', 1)], c['groups'][2]['parts'])
store['M2']['props']['group'] = 'Nền'
check('cột Nhóm ghi đè được', any(x['name'] == 'Nền' for x in un(ifc.solid_info)(units='m')['structures'][0]['groups']))
del store['M2']['props']['group']
ring = lambda rr: [[rr * __import__('math').cos(a * 0.19635), rr * __import__('math').sin(a * 0.19635)] for a in range(32)]
dd = culvert.dims({'t': 'ext', 'o': [0, 0, 0], 'E': [1, 0, 0], 'lo': 0, 'hi': 1000, 'loops': [ring(600), ring(500)]}, 0.001)
check('cống tròn: đường kính trong 1 m, thành 0,1', abs(dd['inner_d'] - 1) < 1e-3 and abs(dd['wall'] - 0.1) < 1e-3 and abs(dd['length'] - 1) < 1e-9, dd)


class Far(S2):
    Centroid = (1188000.0, 580500.0, 90.0)

    def GetBoundingBox(self):
        return (1000000.0, 580490.0, 88.0), (1188010.0, 580510.0, 92.0)


check('hộp bao sai của ZWCAD được sửa', ifc._bbox(Far('F'))[0][0] == 1187990.0, ifc._bbox(Far('F')))
for det in ('part', 'solid'):
    r = f(os.path.join(d, 'cong-%s.ifc' % det), units='m', detail=det, schema='IFC4X3' if det == 'solid' else 'IFC4')
    t = open(r['path'], encoding='ascii').read()
    n = len(re.findall(r'=\s*(?:IFCPIPESEGMENT|IFCWALL|IFCSLAB|IFCFOOTING|IFCBUILDINGELEMENTPROXY)\(', t))
    want = len(sol) if det == 'solid' else sum(len(x['parts']) for x in c['groups'])
    check('xuất %s: %d phần tử trong một cống' % (det, want), n == want and t.count('IFCELEMENTASSEMBLY(') == 5 and len(r['structures']) == 1, (n, want, r['structures']))
    print('FILE ' + r['path'])
# ---- levels, slope, skew, many culverts
import math
from stevecad import culvert_geo as cg


def cv(code, st, n=10, o=(0.0, 0.0, 10.0), az=90.0, i=2.0, wall=None, start=0, name='Đốt cống %02d', inner=None, end=True, seglen=2.0):
    """n segments from the upstream invert o, azimuth az (from North), slope i %, head walls turned by wall degrees from the axis."""
    a = math.radians(az); h = math.hypot(1, i / 100)
    E_ = [math.sin(a) / h, math.cos(a) / h, -i / 100 / h]; X_ = [math.cos(a), -math.sin(a), 0.0]
    Y_ = [X_[1] * E_[2] - X_[2] * E_[1], X_[2] * E_[0] - X_[0] * E_[2], X_[0] * E_[1] - X_[1] * E_[0]]
    if Y_[2] < 0:
        Y_ = [-v for v in Y_]
    res = []
    def one(part, geo, vol, cen):
        res.append({'handle': '%s-%d' % (code, len(res) + start), 'part': part, 'material': 'BT', 'structure': code, 'station': st, 'type': '', 'group': '', 'layer': 'L', 'name': '',
                    'vol': vol, 'near': False, 'extra': {}, 'cen': cen, 'geo': geo})
    for s in range(n):
        m = (s + .5) * seglen
        one(name % (s + 1), {'t': 'ext', 'o': list(o), 'X': X_, 'Y': Y_, 'E': E_, 'lo': s * seglen, 'hi': (s + 1) * seglen, 'loops': [rect(-2.4, -.4, 2.4, 4.4)] + (inner or [rect(-2, 0, 2, 4)])}, 14.08, [o[q] + E_[q] * m for q in range(3)])
    if end:
        w = math.radians(az + (90 if wall is None else wall))
        for nm, t in (('Tường đầu thượng lưu', 0), ('Tường đầu hạ lưu', n * seglen)):
            p = [o[q] + E_[q] * t for q in range(3)]
            one(nm, {'t': 'ext', 'o': p, 'X': [math.cos(w), -math.sin(w), 0.0], 'Y': [0, 0, 1], 'E': [math.sin(w), math.cos(w), 0.0], 'lo': -5, 'hi': 5, 'loops': [rect(0, 0, 1, 5)]}, 20, p)
    return res


near = lambda a, b, e=1e-3: a is not None and abs(a - b) <= e
g1 = culvert.build(cv('C01', 'Km1+100'), 1)[0]['geo']
check('cống dốc 2%: cao độ, độ dốc, phương vị', near(g1['z_up'], 10) and near(g1['slope'], 2) and near(g1['z_down'], 10 - .02 * g1['length_plan']) and near(g1['azimuth'], 90) and near(g1['skew'], 90, .01) and near(g1['length_true'], 20), g1)
for ang in (60, 120, 45):
    g1 = culvert.build(cv('C01', 'Km1+100', az=30, wall=ang), 1)[0]['geo']
    check('góc chéo %d' % ang, near(g1['skew'], min(ang, 180 - ang), .01) and near(g1['azimuth'], 30), g1)
s = cv('C01', 'Km1+100', wall=60); s[0]['extra']['road_azimuth'] = '150'
g1 = culvert.build(s, 1)[0]['geo']; check('góc chéo theo tim đường khớp tường đầu', near(g1['skew'], 60, .01) and g1['skew_from'] == 'tim đường', g1)
s[0]['extra']['road_azimuth'] = '180'; g1 = culvert.build(s, 1)[0]['geo']; check('hai nguồn góc lệch nhau: để trống, nêu lý do', 'skew' not in g1 and any('lệch' in x for x in g1['notes']), g1)
g1 = culvert.build(cv('C01', 'Km1+100', i=-1), 1)[0]; check('độ dốc âm được cảnh báo', any('độ dốc âm' in x['text'] for x in g1['issues']) and near(g1['geo']['slope'], -1), g1['issues'])
g1 = culvert.build(cv('C01', 'Km1+100', end=False), 1)[0]['geo']; check('không có cửa: suy đoán và ghi rõ', g1.get('guessed_ends') and near(g1['slope'], 2) and 'skew' not in g1, g1)
g1 = culvert.build(cv('C01', 'Km1+100', end=False, i=0), 1)[0]['geo']; check('không cửa, đáy phẳng: để trống', 'z_up' not in g1 and g1['notes'], g1)
s = cv('C01', 'Km1+100'); s[3]['near'] = True; g1 = culvert.build(s, 1)[0]['geo']; check('đốt sửa tay: để trống, nêu lý do', 'slope' not in g1 and g1['notes'], g1)
g1 = culvert.build(cv('C01', 'Km1+100') + cv('C01', 'Km1+100', o=(20, 0, 9.6), az=120, end=False, start=50), 1)[0]; check('thân gấp khúc: báo lỗi, không tính', g1['geo']['split'] and any(x['level'] == 'err' for x in g1['issues']) and 'slope' not in g1['geo'])
g1 = culvert.build(cv('C01', '') + cv('C01', '', o=(500, 0, 10), start=50), 1)[0]; check('hai cống trùng tên: báo lỗi', g1['geo']['split'] and any(x['level'] == 'err' for x in g1['issues']))
g1 = culvert.build(cv('C01', 'Km1+100') + cv('C01', 'Km1+100', o=(0, 5.2, 10), end=False, start=50), 1)[0]; check('hai hàng ống song song: một cống, dài một hàng', g1['geo']['lanes'] == 2 and near(g1['barrel']['length'], 20) and not any(x['level'] == 'err' for x in g1['issues']) and '2 hàng' in g1['title'], g1['title'])
g1 = culvert.build(cv('C01', 'Km1+100', inner=[rect(-2.2, 0, -.2, 4), rect(.2, 0, 2.2, 4)]), 1)[0]; check('hai khoang: một cống, số khoang', g1['geo']['cells'] == 2 and near(g1['barrel']['clear_w'], 2) and near(g1['barrel']['wall'], .2) and '2 khoang' in g1['title'], (g1['title'], g1['barrel']))
cut = cv('C01', 'Km1+100', n=1, seglen=20, i=0)
cut[0]['geo'] = {'t': 'clip', 'n': {'t': 'clip', 'n': cut[0]['geo'], 'p': [1, 0, 0], 'nrm': [-.866, .5, 0]}, 'p': [18, 0, 0], 'nrm': [.866, .5, 0]}
g1 = culvert.build(cut, 1)[0]['geo']; check('đầu cắt chéo: chiều dài theo tim', near(g1['length_true'], 17), g1)
mm = cv('C01', 'Km1+100'); kk = 1000
for q in mm:
    ge = q['geo']; ge['o'] = [v * kk for v in ge['o']]; ge['lo'] *= kk; ge['hi'] *= kk; ge['loops'] = [[[p[0] * kk, p[1] * kk] for p in lp] for lp in ge['loops']]
g1 = culvert.build(mm, .001)[0]; check('vẽ mm: số liệu ra mét', near(g1['geo']['z_up'], 10) and near(g1['geo']['slope'], 2) and near(g1['barrel']['length'], 20), g1['geo'])
t1 = culvert.build(cv('C10', 'Km10+100') + cv('C09', 'Km9+050') + cv('C01', 'Km8+423.31') + cv('C01', 'KM8+423,310', n=0, start=90) + cv('', ''), 1)
check('nhiều cống: xếp theo lý trình, viết khác kiểu vẫn một cống, chưa rõ xuống cuối', [c_['key'] for c_ in t1] == ['C01 Km8+423.31', 'C09 Km9+050', 'C10 Km10+100', 'Chưa rõ công trình'], [c_['key'] for c_ in t1])
check('lý trình viết nhiều kiểu có cảnh báo', any('nhiều kiểu' in x['text'] for x in t1[0]['issues']))
s = cv('C01', 'Km1+100'); del s[4]; s[2]['part'] = 'Đốt cống 02'; s[-1]['part'] = 'Tường đầu'; q = [x['text'] for x in culvert.build(s, 1)[0]['issues']]
check('cảnh báo: trùng số, thiếu số, thiếu đầu cống', any('trùng số' in x for x in q) and any('thiếu số' in x for x in q) and any('thượng lưu hay' in x for x in q), q)
a, b = cv('C01', 'Km1+100'), cv('C02', 'Km2+100', o=(1000, 0, 10)); lost = [dict(x, structure='', station='', handle='?' + x['handle']) for x in b[:2]]; lost += [dict(lost[0], handle='?xa', cen=[500, 0, 10])]
sg = cg.suggest(lost, culvert.build(a + b, 1), 1); check('đề xuất cống theo vị trí, chỗ không rõ thì không đề xuất', {h: v['structure'] for h, v in sg.items()} == {'?C02-0': 'C02', '?C02-1': 'C02'}, sg)
tt = time.time() if 'time' in globals() else __import__('time').time(); big = [x for n_ in range(100) for x in cv('C%03d' % n_, 'Km%d+%03d' % (n_ // 10, n_ % 10 * 100), o=(n_ * 100.0, 0, 10))]
t1 = culvert.build(big, 1); check('100 cống (1200 khối) dưới 10 giây', len(t1) == 100 and __import__('time').time() - tt < 10, __import__('time').time() - tt)
# two culverts through the real exporter
store.clear(); sol.clear()
for q in cv('C01', 'Km8+423.31') + cv('C02', 'Km9+100', o=(500, 0, 12), az=30, wall=60):
    o_ = S2(q['handle']); o_.Volume = q['vol']; o_.Centroid = tuple(q['cen']); sol[q['handle']] = o_
    store[q['handle']] = {'v': 1, 'part': q['part'], 'material': 'BT M300', 'props': {'structure': q['structure'], 'station': q['station']}, 'geo': q['geo'], 'chk': {'vol': q['vol'], 'cen': list(q['cen'])}}
si = un(ifc.solid_info)(units='m')['structures']
r = f(os.path.join(d, 'cong-haicai.ifc'), units='m', schema='IFC4X3'); t = open(r['path'], encoding='ascii').read()
check('một file, hai cống tách riêng, có cao độ độ dốc góc chéo', t.count("'CULVERT'") == 2 and t.count(enc('Cao độ đáy trong thượng lưu')) == 2 and t.count(enc('Góc chéo (độ)')) == 2, r)
print('FILE ' + r['path'])
r = f(os.path.join(d, 'chon.ifc'), units='m', groups=[si[1]['handles']]); check('chỉ xuất cống được chọn', list(r['structures'])[0].startswith('C02') and len(r['structures']) == 1, r)
r = f(os.path.join(d, 'tach.ifc'), units='m', groups=[c_['handles'] for c_ in si], split=True)
check('mỗi cống một file', [os.path.basename(x) for x in r['files']] == ['tach_C01-Km8+423.31.ifc', 'tach_C02-Km9+100.ifc'] and all(open(x, encoding='ascii').read().count("'CULVERT'") == 1 for x in r['files']), r)
try:
    f(os.path.join(d, 'tach.ifc'), units='m', split=True); check('không ghi đè file cũ', False)
except ifc.UserError:
    check('không ghi đè file cũ', True)
try:
    f(os.path.join(d, 'x.ifc'), units='m', detail='abc')
    check('detail lạ bị chặn', False)
except ifc.UserError:
    check('detail lạ bị chặn', True)
sys.exit(1 if bad else 0)
