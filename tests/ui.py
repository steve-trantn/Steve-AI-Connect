"""app/SteveAIUi.ps1: the work behind the panels inside the CAD. Run by run.ps1 (sandbox folders, mock server on 8767)."""
import base64, hashlib, json, os, subprocess, sys, time, urllib.request

root, ws = sys.argv[1], sys.argv[2]            # ws = <sandbox home>\Steve-CAD-AI
bad = 0


def call(op, url='http://127.0.0.1:8767/', **a):
    env = dict(os.environ, STEVECAD_TESTURL=url)
    p = subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', root + r'\app\SteveAIUi.ps1'],
                       input=json.dumps(dict(a, op=op), ensure_ascii=False).encode(), capture_output=True, env=env, timeout=120)
    try:
        return json.loads(p.stdout.decode('utf-8'))
    except ValueError:
        return {'bad_output': p.stdout[:300], 'stderr': p.stderr[:600]}


def get(path):
    return json.loads(urllib.request.urlopen('http://127.0.0.1:8767' + path).read())


def check(name, ok, info=''):
    global bad
    print(('PASS  ' if ok else 'FAIL  ') + name + ('' if ok else '  ' + str(info)[:700]), flush=True)
    bad += not ok


d = os.path.join(ws, 'skills', 'ui-thu')
os.makedirs(os.path.join(d, 'phụ'))
f = os.path.join(d, 'SKILL.md')
open(f, 'w', encoding='utf-8').write('---\nname: ui-thu\ntitle: Thử ạ\n---\n' + 'Bước "1" đọc bản vẽ\n' * 9)
open(os.path.join(d, 'phụ', 'a.lsp'), 'wb').write(b'(d\xe0\xff)')
r = call('ctx')
check('ctx', r.get('email') == 'thu@x.vn' and r.get('version', '').startswith('v'), r)
r = call('diag')
check('diag có phiên bản, không lộ tên người dùng', any('Steve AI Connect v' in x for x in r.get('diag', [])) and os.environ['USERNAME'].lower() not in json.dumps(r).lower(), r)
r = call('xyz')
check('op lạ bị từ chối', 'error' in r, r)
call('draft', text='nháp "ạ"\ndòng 2')
check('nháp giữ nguyên', call('ctx').get('draft') == 'nháp "ạ"\ndòng 2')
desc = 'Nội dung tiếng Việt "ngoặc" \\ dấu chéo $x `y\ndòng 2'
r = call('feature', email='A@b.vn', kind='Báo lỗi', cad='Chung', title='Báo lỗi: thử', desc=desc)
rows = get('/feat')
check('báo lỗi tới nơi nguyên văn, xoá nháp', r.get('ok') and rows[-1][7] == desc and rows[-1][4] == 'Báo lỗi' and call('ctx').get('draft') == '', (r, rows[-1:]))
check('email sai bị chặn', 'error' in call('feature', email='x', kind='a', cad='b', title='12345', desc='x' * 20))
check('mô tả quá dài bị chặn, không cắt ngầm', 'error' in call('feature', email='a@b.vn', kind='a', cad='b', title='12345', desc='x' * 3001))
check('mất mạng báo lỗi', 'error' in call('feature', url='http://127.0.0.1:9/', email='a@b.vn', kind='a', cad='b', title='12345', desc='x' * 20))
r = call('skills')
check('liệt kê skill', [s['name'] for s in r.get('skills', [])] == ['ui-thu'], r)
p = call('pack', name='ui-thu')
check('đóng gói', len(p.get('files', [])) == 2 and len(p.get('sha', '')) == 64, p)
check('tên skill lạ / đường dẫn bị chặn', 'error' in call('pack', name='..') and 'error' in call('pack', name='..\\skills\\ui-thu'))
n = len(get('/state')['drive'])
check('chưa đồng ý giấy phép thì không gửi', 'error' in call('share', name='ui-thu', sha=p.get('sha'), email='a@b.vn', author='', license=False))
open(f, 'a', encoding='utf-8').write('sửa\n')
check('skill đổi sau khi xem trước thì không gửi', 'error' in call('share', name='ui-thu', sha=p.get('sha'), email='a@b.vn', author='', license=True) and len(get('/state')['drive']) == n)
p = call('pack', name='ui-thu')
r = call('share', name='ui-thu', sha=p.get('sha'), email='a@b.vn', author='Tên', license=True)
st = get('/state')
check('gửi skill: có biên nhận, máy chủ nhận đúng SHA', 'SK-' in r.get('text', '') and hashlib.sha256(base64.b64decode(st['drive'][-1]['zip'])).hexdigest() == p.get('sha'), r)
check('QR đọc được', base64.b64decode(call('qr').get('png', ''))[:4] == b'\x89PNG')
t = time.time()
call('ctx')
print('      ctx %.1f s' % (time.time() - t))
sys.exit(1 if bad else 0)
