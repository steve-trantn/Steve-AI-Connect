"""server/panel.py kcs_check: the bridge to the separate Kiểm tra KCS package. No CAD: the drawing is a stand-in.
Run by run.ps1 with the server's python (LOCALAPPDATA is a sandbox there)."""
import json
import os
import sys
import tempfile

root = sys.argv[1]
sys.path.insert(0, os.path.join(root, 'server'))
bad = 0


def check(name, ok, info=''):
    global bad
    print(('PASS  ' if ok else 'FAIL  ') + name + ('' if ok else '  ' + str(info)[:500]), flush=True)
    bad += not ok


lad = tempfile.mkdtemp(prefix='kcs-')
os.environ['LOCALAPPDATA'] = lad
os.environ['USERPROFILE'] = lad
import panel  # noqa: E402


class Doc:
    def __init__(self, full, saved):
        self.FullName, self.Saved, self.Name = full, saved, os.path.basename(full) or 'Drawing1.dwg'


def use(doc):
    panel.tools.doc = lambda: doc
    panel.tools.Drawings.name = staticmethod(lambda d: d.Name)


use(Doc(r'D:\x\tuyen.dwg', True))
try:
    panel.kcs_check()
    check('chưa cài gói KCS thì báo rõ', False, 'no error')
except ValueError as e:
    check('chưa cài gói KCS thì báo rõ', 'chưa cài gói Kiểm tra KCS' in str(e), e)

pkg = os.path.join(lad, 'SteveCADConnect', 'kcs', 'stevekcs')
os.makedirs(pkg)
open(os.path.join(pkg, '__init__.py'), 'w').close()
open(os.path.join(pkg, 'api.py'), 'w', encoding='utf-8').write(
    'def catalog():\n    return dict(standards=[dict(id="tcvn5729", options=[dict(value=80)])])\n'
    'def check_file(path, v=80, out_dir=None, module="tuyen", standard="tcvn5729", convert=None):\n'
    '    if module != "tuyen":\n        raise ValueError("Phần này đang làm")\n'
    '    return dict(path=path, v=v, out_dir=out_dir, module=module, standard=standard, convert=callable(convert), routes=[], items=[], notes=[])\n')
use(Doc(r'D:\x\tuyen.dwg', False))
r = panel.kcs_check(module='tuyen', standard='tcvn5729', v=100)
check('danh sách tiêu chuẩn lấy từ gói', panel.kcs_catalog()['standards'][0]['id'] == 'tcvn5729')
check('chuyển tiêu chuẩn và cách đổi DXF qua CAD cho gói', r['standard'] == 'tcvn5729' and r['convert'] is True, r)
check('gói KCS nhận đúng file, cấp, thư mục Excel', r['path'] == r'D:\x\tuyen.dwg' and r['v'] == 100 and r['out_dir'].endswith(os.path.join('Steve-CAD-AI', 'Excel')), r)
check('báo bản vẽ có thay đổi chưa lưu', r['unsaved'] is True and r['_drawing'] == 'tuyen.dwg', r)
check('kết quả gửi được qua JSON', bool(json.dumps(r, ensure_ascii=False)))
use(Doc('', True))
try:
    panel.kcs_check()
    check('bản vẽ chưa lưu thành file thì báo', False, 'no error')
except ValueError as e:
    check('bản vẽ chưa lưu thành file thì báo', 'chưa được lưu' in str(e), e)
use(Doc(r'D:\x\tuyen.dwg', True))
try:
    panel.kcs_check(module='bien-bao')
    check('phần chưa làm thì báo', False, 'no error')
except ValueError as e:
    check('phần chưa làm thì báo', 'đang làm' in str(e), e)
p = panel.kcs_feedback({'criterion': 'Bán kính', 'design': 'R = 300', 'x' * 5: 'bỏ'}, 'sai', 'dự án được duyệt châm chước', 'TCVN 5729:2012', 'cấp 80', 'tuyen.dwg')['saved']
row = json.loads(open(p, encoding='utf-8').read().splitlines()[-1])
check('phản hồi từng lỗi lưu trên máy, đúng nội dung', row['verdict'] == 'sai' and row['comment'] == 'dự án được duyệt châm chước' and row['criterion'] == 'Bán kính' and 'xxxxx' not in row
      and p.startswith(lad), row)
try:
    panel.kcs_feedback({}, 'gì đó')
    check('phản hồi lạ bị từ chối', False)
except ValueError:
    check('phản hồi lạ bị từ chối', True)
sys.exit(1 if bad else 0)
