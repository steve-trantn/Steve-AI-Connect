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
# ---- v1.10 "Thiết lập" inside the CAD: state, registration by email code, trial, connect guard
r = call('setup')
check('setup: trạng thái', r.get('registered') is True and [c['id'] for c in r.get('clients', [])] == ['claudecode', 'codex', 'gemini']
      and {c['id'] for c in r.get('cads', [])} == {'zwcad', 'autocad', 'adscivil'}, r)
check('đăng ký: email sai bị chặn', 'error' in call('reg-send', email='x@', login=False, name='Thu', phone='0912345678', consent=True))
check('đăng ký: chưa tích đồng ý bị chặn', 'error' in call('reg-send', email='moi@x.vn', login=False, name='Thu', phone='0912345678', consent=False))
check('đăng ký: SĐT sai bị chặn', 'error' in call('reg-send', email='moi@x.vn', login=False, name='Thu', phone='12', consent=True))
r = call('reg-send', email='Moi@X.vn', login=False, name='Thu Mới', phone='0912 345 678', consent=True)
m = get('/mail')
check('đăng ký: gửi mã', r.get('ok') is True and m.get('to') == 'moi@x.vn' and len(m.get('code') or '') == 6, (r, m))
r = call('reg-verify', email='moi@x.vn', code='000000' if m.get('code') != '000000' else '111111', login=False, name='Thu Mới', phone='0912345678', consent=True)
check('đăng ký: mã sai báo đúng lỗi, không ghi tài khoản', r.get('ok') is False and r.get('why') == 'code' and call('ctx').get('email') == 'thu@x.vn', r)
r = call('reg-verify', email='moi@x.vn', code=m.get('code'), login=False, name='Thu Mới', phone='0912345678', consent=True, news=False)
check('đăng ký: mã đúng thì lưu tài khoản', r.get('ok') is True and call('ctx').get('email') == 'moi@x.vn', r)
check('đăng ký: máy chủ có dòng mới', 'moi@x.vn' in json.dumps(get('/reg'), ensure_ascii=False))
r = call('reg-send', url='http://127.0.0.1:9/', email='khac@x.vn', login=True)
check('mất mạng: gợi ý dùng tạm', r.get('ok') is False and r.get('why') == 'network' and r.get('trial') is True, r)
r = call('trial')
check('dùng tạm 7 ngày', r.get('ok') is True and r.get('left') == 7, r)
r = call('reg-send', url='http://127.0.0.1:9/', email='khac@x.vn', login=True)
check('dùng tạm chỉ một lần', r.get('trial') is False, r)
check('connect: trợ lý lạ bị chặn', 'error' in call('connect', install='calc.exe'))
check('connect: Gemini không key bị chặn', 'API key' in call('connect', install='gemini', key='').get('error', ''))
# ---- a PC without Claude Code / Codex: the "Cài và kết nối" button in the CAD installs it (winget faked: tests\fake-ai.ps1)
mock = {'STEVECAD_TESTMOCK': root + r'\tests\fake-ai.ps1', 'STEVECAD_MOCKSTATE': os.path.join(ws, 'mock-ai.json'), 'STEVECAD_DRYRUN': '1'}


def mcall(op, **a):
    keep = {k: os.environ.get(k) for k in mock}
    os.environ.update(mock)
    try:
        return call(op, **a)
    finally:
        for k, v in keep.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v


def mstate():
    return json.load(open(mock['STEVECAD_MOCKSTATE'], encoding='utf-8-sig'))


r = mcall('setup')
cl = {c['id']: c for c in r.get('clients', [])}
check('máy chưa có trợ lý: Claude Code, Codex hiện "chưa cài"', cl and not cl['claudecode']['installed'] and not cl['codex']['installed'] and r.get('winget') is True, r)
r = mcall('connect', install='claudecode', key='')
st = mstate() if os.path.exists(mock['STEVECAD_MOCKSTATE']) else {}
check('bấm Cài: Claude Code cài qua winget, đúng gói, kho chính thức',
      any('--id Anthropic.ClaudeCode -e --source winget' in x for x in st.get('calls', [])), (r, st))
check('bấm Cài: nối Claude Code với mọi CAD trên máy', r.get('ok') is True and {'claudecode/zwcad', 'claudecode/autocad', 'claudecode/adscivil'} <= set(st.get('conn', [])), (r, st))
r = mcall('setup')
cl = {c['id']: c for c in r.get('clients', [])}
check('sau khi cài: Claude Code "đã kết nối", Codex vẫn "chưa cài"', cl['claudecode']['installed'] and cl['claudecode']['connected'] and not cl['codex']['installed'], r)
r = mcall('connect', install='codex', key='')
st = mstate()
check('bấm Cài Codex: qua winget, nối với CAD', r.get('ok') is True and any('--id OpenAI.Codex' in x for x in st['calls']) and 'codex/zwcad' in st['conn'], (r, st))
s = json.load(open(os.path.join(os.environ['LOCALAPPDATA'], 'SteveCADConnect', 'settings.json'), encoding='utf-8-sig'))
check('trợ lý vừa cài thành trợ lý mặc định', s.get('DefaultAI') == 'codex', s.get('DefaultAI'))

# -Info no longer stops an unregistered PC: the panel shows "Thiết lập" itself
lad = os.path.join(os.path.dirname(ws), 'lad-new')
os.makedirs(os.path.join(lad, 'SteveCADConnect'), exist_ok=True)
for sw, want in (('-Info', 'info'), ('-Prepare', 'prepare')):
    p = subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', root + r'\app\SteveAI.ps1', sw],
                       capture_output=True, env=dict(os.environ, LOCALAPPDATA=lad, STEVECAD_DRYRUN='1'), timeout=120)
    try:
        o = json.loads(p.stdout.decode('utf-8'))
    except ValueError:
        o = {'bad': p.stdout[:300]}
    if want == 'info':
        check('-Info khi chưa đăng ký: không lỗi, access=false', o.get('access') is False and 'error' not in o and o.get('skills'), o)
    else:
        check('-Prepare khi chưa đăng ký: báo cần đăng ký', 'đăng ký' in o.get('error', ''), o)

t = time.time()
call('ctx')
print('      ctx %.1f s' % (time.time() - t))
sys.exit(1 if bad else 0)
