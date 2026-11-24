'use strict';
const host = window.chrome.webview, $ = id => document.getElementById(id);
const post = m => host.postMessage(m);
let size = +(localStorage.font || 14), running = false, client = '';
const term = new Terminal({ fontFamily: 'Cascadia Mono, Consolas, monospace', fontSize: size, cursorBlink: true, scrollback: 8000,
  theme: { background: '#0d1421', foreground: '#e6edf6', cursor: '#60a5fa', selectionBackground: '#2b4a7d' },
  linkHandler: { activate: (e, u) => post({ t: 'link', u }) } });
const fit = new FitAddon.FitAddon();
term.loadAddon(fit); term.open($('term')); fit.fit();
term.onData(d => running && post({ t: 'in', d }));
let rs = 0;
new ResizeObserver(() => { clearTimeout(rs); rs = setTimeout(() => { try { fit.fit(); } catch (e) {} }, 60); }).observe($('term'));
term.onResize(s => post({ t: 'size', cols: s.cols, rows: s.rows }));
// Ctrl+C copies when text is selected, Ctrl+V pastes
term.attachCustomKeyEventHandler(e => {
  if (e.type === 'keydown' && e.ctrlKey && e.key.toLowerCase() === 'c' && term.hasSelection()) { navigator.clipboard.writeText(term.getSelection()); term.clearSelection(); return false; }
  if (e.ctrlKey && e.key.toLowerCase() === 'v') return false;
  return true;
});

function state(text, cls) { $('state').textContent = text; $('dot').className = cls || ''; }
function setRun(on) { running = on; $('stop').disabled = !on; $('send').disabled = !on; }
function start() {
  term.reset(); setRun(false); state('Đang mở trợ lý…');
  post({ t: 'start', client, skill: $('skill').value });
  $('skill').value = '';
  $('box').focus();
}
// Vietnamese input methods misbehave inside terminals, so typing happens in a normal text box and is pasted as one block
function send(text) {
  text = text.replace(/\r\n?/g, '\n').replace(/[\x00-\x08\x0b-\x1f\x7f]/g, '').trim();
  if (!text || !running) return false;
  post({ t: 'in', d: '\x1b[200~' + text + '\x1b[201~' });
  setTimeout(() => post({ t: 'in', d: '\r' }), 200);
  term.scrollToBottom();
  return true;
}
const box = $('box');
function grow() { box.style.height = 'auto'; box.style.height = Math.min(box.scrollHeight + 2, 140) + 'px'; }
function sendBox() { if (send(box.value)) { box.value = ''; grow(); } box.focus(); }
box.addEventListener('input', grow);
const keys = { ArrowUp: '\x1b[A', ArrowDown: '\x1b[B', ArrowLeft: '\x1b[D', ArrowRight: '\x1b[C', Escape: '\x1b', Enter: '\r', Tab: '\t' };
box.addEventListener('keydown', e => {
  if (e.isComposing) return;
  if (e.key === 'Enter' && !e.shiftKey && box.value.trim()) { e.preventDefault(); sendBox(); return; }
  if (e.key === 'Escape' && running) { e.preventDefault(); post({ t: 'in', d: '\x1b' }); return; }
  if (box.value || !running || e.ctrlKey || e.altKey) return;
  const seq = e.key === 'Tab' && e.shiftKey ? '\x1b[Z' : keys[e.key];
  if (seq && !(e.key === 'Enter' && e.shiftKey)) { e.preventDefault(); post({ t: 'in', d: seq }); }
});
$('send').onclick = sendBox;
$('new').onclick = start;
$('stop').onclick = () => { post({ t: 'stop' }); setRun(false); state('Đã dừng. Bấm Phiên mới để mở lại.'); };
$('skill').onchange = () => { if ($('skill').value) start(); };
const zoom = d => { size = Math.max(9, Math.min(24, size + d)); localStorage.font = size; term.options.fontSize = size; fit.fit(); };
$('minus').onclick = () => zoom(-1); $('plus').onclick = () => zoom(1);

// quick prompts are put in the box so the person can finish the sentence before sending
[['Đối tượng đang chọn', 'Với các đối tượng tôi đang chọn trong CAD, hãy '], ['Layer', 'Bản vẽ đang mở có những layer nào, mỗi layer bao nhiêu đối tượng?'],
 ['Đếm block', 'Đếm số lượng từng loại block trong bản vẽ.'], ['Chiều dài, diện tích', 'Tính tổng chiều dài và diện tích các polyline tôi đang chọn.'],
 ['Đối tượng trùng', 'Tìm các đối tượng bị trùng nhau (chưa xoá).']].forEach(([n, p]) => {
  const b = document.createElement('button'); b.textContent = n; b.onclick = () => { box.value = p; grow(); box.focus(); box.setSelectionRange(p.length, p.length); }; $('quick').append(b);
});
// digits 1-9 answer a question of the assistant when the box is empty and the terminal shows a numbered menu
box.addEventListener('beforeinput', e => {
  if (!running || box.value || !/^[1-9]$/.test(e.data || '')) return;
  const b = term.buffer.active, lines = [];
  for (let i = 0; i < term.rows; i++) { const l = b.getLine(b.viewportY + i); if (l) lines.push(l.translateToString(true)); }
  if (lines.some(l => /^\s*[❯›>]\s*\d\.\s/.test(l))) { e.preventDefault(); post({ t: 'in', d: e.data }); }
});

host.addEventListener('message', ev => {
  const m = ev.data;
  if (m.t === 'out') term.write(Uint8Array.from(atob(m.d), c => c.charCodeAt(0)));
  else if (m.t === 'info') {
    const ok = m.clients.filter(c => c.ok);
    $('clients').replaceChildren(...m.clients.map(c => {
      const b = document.createElement('button'); b.textContent = c.label; b.disabled = !c.ok; b.dataset.id = c.id;
      b.title = c.ok ? '' : 'Chưa cài hoặc chưa kết nối trong Steve AI Connect';
      b.onclick = () => { if (client !== c.id) { client = c.id; mark(); start(); } };
      return b;
    }));
    const first = document.createElement('option'); first.value = ''; first.textContent = 'Skill…';
    $('skill').replaceChildren(first, ...m.skills.map(s => { const o = document.createElement('option'); o.value = s.name; o.textContent = s.name; o.title = s.description; return o; }));
    client = [m.client, m.default].find(x => ok.some(c => c.id === x)) || (ok[0] && ok[0].id) || '';
    mark();
    if (!client) { state('Máy chưa có trợ lý AI. Mở Steve AI Connect để kết nối.', 'err'); return; }
    if (m.skill) $('skill').value = m.skill;
    start(); post({ t: 'snap' });
  }
  else if (m.t === 'started') { setRun(true); client = m.client; mark(); state(m.label + ' đang chạy', 'on'); }
  else if (m.t === 'exit') { setRun(false); state('Phiên đã kết thúc. Bấm Phiên mới để mở lại.'); }
  else if (m.t === 'error') { setRun(false); state(m.text, 'err'); $('state').title = m.text; }
});
function mark() { for (const b of $('clients').children) b.classList.toggle('on', b.dataset.id === client); }
setRun(false);
post({ t: 'ready', cols: term.cols, rows: term.rows });
