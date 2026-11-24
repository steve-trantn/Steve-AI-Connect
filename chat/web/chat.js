'use strict';
const host = window.chrome.webview, $ = id => document.getElementById(id);
const post = m => host.postMessage(m);
let size = +(localStorage.font || 13), running = false, client = '', skills = [], inPanel = false, tables = false, started = false, docName = '';
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

function state(text, cls) { $('state').textContent = text; $('state').title = text; $('dot').className = cls || ''; }
function setRun(on) { running = on; $('send').disabled = !on; }
function start(skill, resume) {
  started = true; term.reset(); setRun(false); state('Đang mở…');
  post({ t: 'start', client, skill: skill || '', resume: !!resume });
  box.focus();
}
// Vietnamese input methods misbehave inside terminals, so typing happens in a normal text box and is pasted as one block
function send(text) {
  text = text.replace(/\r\n?/g, '\n').replace(/[\x00-\x08\x0b-\x1f\x7f]/g, '').trim();
  if (!text || !running) return false;
  post({ t: 'in', d: text[0] === '/' && !text.includes('\n') ? text : '\x1b[200~' + text + '\x1b[201~' });   // /commands are typed, not pasted
  setTimeout(() => post({ t: 'in', d: '\r' }), 250);
  term.scrollToBottom();
  return true;
}
let lastSkill = '', lastAt = 0;
function runSkill(name) {
  Ui.hide(); Panels.hide();   // a table left open would cover the answer
  // impatient clicks: the same skill again within 15 s is not sent twice
  if (name === lastSkill && Date.now() - lastAt < 15000 && started) { state('Đã gửi skill này, trợ lý đang xử lý…', running ? 'on' : ''); return; }
  lastSkill = name; lastAt = Date.now();
  if (!running) { start(name); return; }
  send(client === 'claudecode' ? '/' + name : 'Dùng skill ' + name + ': gọi tool get_skill với name=' + name + ' của server CAD đang nối, đọc hướng dẫn rồi làm theo từng bước. Hỏi tôi thông tin còn thiếu trước khi vẽ.');
}
const box = $('box');
function grow() { box.style.height = '30px'; if (box.scrollHeight > 32) box.style.height = Math.min(box.scrollHeight + 2, 120) + 'px'; }
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
// digits 1-9 answer a question of the assistant when the box is empty and the terminal shows a numbered menu
box.addEventListener('beforeinput', e => {
  if (!running || box.value || !/^[1-9]$/.test(e.data || '')) return;
  const b = term.buffer.active, lines = [];
  for (let i = 0; i < term.rows; i++) { const l = b.getLine(b.viewportY + i); if (l) lines.push(l.translateToString(true)); }
  if (lines.some(l => /^\s*[❯›>]\s*\d\.\s/.test(l))) { e.preventDefault(); post({ t: 'in', d: e.data }); }
});
$('send').onclick = sendBox;
$('new').onclick = () => start();
$('client').onchange = () => { client = $('client').value; start(); };
const zoom = d => { size = Math.max(9, Math.min(24, size + d)); localStorage.font = size; term.options.fontSize = size; fit.fit(); };

// ---------- popup menus ----------
const pop = $('pop');
function popup(btn, items, up) {
  if (!pop.hidden && pop.owner === btn) { pop.hidden = true; return; }
  pop.owner = btn;
  pop.replaceChildren(...items.map(i => {
    if (i.head) { const h = document.createElement('h4'); h.textContent = i.head; return h; }
    const b = document.createElement('button'); b.textContent = i.text; b.disabled = !!i.off;
    if (i.sub) { const s = document.createElement('small'); s.textContent = i.sub; b.append(s); }
    b.onclick = () => { if (!i.keep) pop.hidden = true; i.act(); };
    return b;
  }));
  pop.hidden = false;
  const r = btn.getBoundingClientRect();
  pop.style.left = Math.max(4, Math.min(r.left, innerWidth - pop.offsetWidth - 4)) + 'px';
  pop.style.top = up ? 'auto' : r.bottom + 2 + 'px';
  pop.style.bottom = up ? innerHeight - r.top + 2 + 'px' : 'auto';
}
addEventListener('pointerdown', e => { if (!pop.hidden && !pop.contains(e.target) && e.target !== pop.owner) pop.hidden = true; }, true);
addEventListener('keydown', e => { if (e.key === 'Escape' && !pop.hidden) { pop.hidden = true; e.stopPropagation(); } }, true);
addEventListener('blur', () => { pop.hidden = true; });
// prompts are put in the box so the person can finish the sentence before sending
const fill = p => { box.value = p; grow(); box.focus(); box.setSelectionRange(p.length, p.length); };
$('add').onclick = () => popup($('add'), [
  ...(tables ? [{ head: 'Bảng (không tốn lượt AI)' }, ...skills.filter(s => Panels.has(s.name)).map(s => ({ text: s.title, act: () => Panels.open(s.name) }))] : []),
  { head: 'Skill (nhờ AI)' }, ...skills.filter(s => !tables || !Panels.has(s.name)).map(s => ({ text: s.title || s.name, sub: s.description, act: () => runSkill(s.name) })),
  { head: 'Câu gợi ý' }, ...[['Với đối tượng đang chọn, hãy…', 'Với các đối tượng tôi đang chọn trong CAD, hãy '],
    ['Liệt kê layer', 'Bản vẽ đang mở có những layer nào, mỗi layer bao nhiêu đối tượng?'], ['Đếm block', 'Đếm số lượng từng loại block trong bản vẽ.'],
    ['Tổng chiều dài, diện tích', 'Tính tổng chiều dài và diện tích các polyline tôi đang chọn.'],
    ['Tìm đối tượng trùng', 'Tìm các đối tượng bị trùng nhau (chưa xoá).']].map(([text, p]) => ({ text, act: () => fill(p) })),
], true);
$('more').onclick = () => popup($('more'), [
  { text: 'Phiên mới', act: () => start() },
  { text: 'Tiếp tục phiên cũ…', sub: 'Chọn bằng ↑ ↓ rồi Enter', off: client === 'gemini', act: () => start('', true) },
  ...(inPanel ? [{ text: 'Hoàn tác bước cuối trong CAD (U)', sub: 'Kể cả thao tác bạn vừa làm tay', act: () => post({ t: 'undo' }) }] : []),
  { text: 'Dừng trợ lý', off: !running, act: () => { post({ t: 'stop' }); setRun(false); state('Đã dừng. Bấm ✚ để mở lại.'); } },
  { text: 'Chữ lớn hơn', keep: true, act: () => zoom(1) }, { text: 'Chữ nhỏ hơn', keep: true, act: () => zoom(-1) },
  { text: 'Hướng dẫn & hỗ trợ', act: () => Ui.open('ui-help') }, { text: 'Báo lỗi cho Steve', act: () => Ui.open('ui-diag') },
  { head: 'AI có thể nhầm. Sai thì gõ UNDO trong CAD.' },
]);

host.addEventListener('message', ev => {
  const m = ev.data;
  if (m.t === 'out') term.write(Uint8Array.from(atob(m.d), c => c.charCodeAt(0)));
  else if (m.t === 'info') {
    const ok = m.clients.filter(c => c.ok);
    $('client').replaceChildren(...m.clients.map(c => { const o = document.createElement('option'); o.value = c.id; o.textContent = c.label; o.disabled = !c.ok; return o; }));
    skills = m.skills; inPanel = !!m.panel; tables = !!m.tables; docName = m.doc || '';
    client = [m.client, m.default].find(x => ok.some(c => c.id === x)) || (ok[0] && ok[0].id) || '';
    $('client').value = client;
    if (!client) { state('Máy chưa có trợ lý AI. Mở Steve AI Connect để kết nối.', 'err'); return; }
    // a skill that has a table opens the table: instant, and no AI is used
    if (Ui.isOpen()) state('Trợ lý AI chưa mở');
    else if (tables && Panels.open(m.skill)) state('Trợ lý AI chưa mở (không cần cho bảng này)'); else start(m.skill);
    post({ t: 'snap' });
  }
  else if (m.t === 'started') { setRun(true); client = m.client; $('client').value = client; state(docName, 'on'); }
  else if (m.t === 'uiopen') Ui.open(m.name);
  else if (m.t === 'uires') Ui.reply(m);
  else if (m.t === 'toolres') Panels.reply(m);
  else if (m.t === 'toolfail') Panels.fail(m.text);
  else if (m.t === 'doc') { docName = m.name; if (running) state(docName, 'on'); }
  else if (m.t === 'files') {   // dropped files: their paths go into the box
    const p = m.paths.map(x => '"' + x + '"').join(' ');
    if (p) { box.value = (box.value ? box.value.trimEnd() + ' ' : '') + p + ' '; grow(); box.focus(); }
  }
  else if (m.t === 'ask') {   // a command in the CAD asked for an assistant and / or a skill while the panel is open
    if (Ui.open(m.skill)) return;
    Ui.hide();
    if (tables && Panels.open(m.skill)) return;
    Panels.hide();
    if (m.client && m.client !== client) { client = m.client; $('client').value = client; start(m.skill); }
    else if (m.skill) runSkill(m.skill);
    box.focus();
  }
  else if (m.t === 'exit') { setRun(false); state('Phiên đã kết thúc. Bấm ✚ để mở lại.'); }
  else if (m.t === 'error') { setRun(false); state(m.text, 'err'); term.write('\r\n' + m.text.replace(/\n/g, '\r\n')); }
});
// drag files from Explorer into the panel
for (const n of ['dragover', 'drop']) addEventListener(n, e => {
  e.preventDefault(); e.stopPropagation();
  if (n === 'drop' && e.dataTransfer.files.length) host.postMessageWithAdditionalObjects({ t: 'files' }, [...e.dataTransfer.files].slice(0, 10));
}, true);
