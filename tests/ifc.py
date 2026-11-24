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
sys.exit(1 if bad else 0)
