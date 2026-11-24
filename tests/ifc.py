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
sys.exit(1 if bad else 0)
