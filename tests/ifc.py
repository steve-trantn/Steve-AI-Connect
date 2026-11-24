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
ifc._solids = lambda d, h, l: list(sol.values())
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
try:
    f(os.path.join(d, 'x.ifc'), units='m', detail='abc')
    check('detail lạ bị chặn', False)
except ifc.UserError:
    check('detail lạ bị chặn', True)
sys.exit(1 if bad else 0)
