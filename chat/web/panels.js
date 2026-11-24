'use strict';
// Tables that work without AI: audit, quantities, title blocks. Data comes from server/panel.py through the host program.
// a block copied from Excel: first row = titles, first column = Handle; null when it is something else
function parsePaste(text) {
  // Excel quotes a cell that holds a line break or a quote
  const rows = []; let row = [], cell = '', q = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (q) { if (c === '"') { if (text[i + 1] === '"') { cell += '"'; i++; } else q = false; } else cell += c; }
    else if (c === '"' && cell === '') q = true;
    else if (c === '\t') { row.push(cell); cell = ''; }
    else if (c === '\n') { row.push(cell); rows.push(row); row = []; cell = ''; }
    else if (c !== '\r') cell += c;
  }
  if (cell || row.length) { row.push(cell); rows.push(row); }
  const ok = rows.map(r => r.map(x => x.replace(/\s+/g, ' ').trim())).filter(r => r.some(x => x));
  if (ok.length < 2 || ok[0][0].toLowerCase() !== 'handle') return null;
  return { head: ok[0], rows: ok.slice(1).filter(r => r[0]) };
}
if (typeof module !== 'undefined') module.exports = { parsePaste };
const Panels = typeof document === 'undefined' ? null : (() => {
  const calls = new Map(); let seq = 0, cur = '';
  const el = (tag, props, ...kids) => { const e = Object.assign(document.createElement(tag), props || {}); e.append(...kids.filter(k => k != null)); return e; };
  function call(name, args) {
    return new Promise((ok, no) => { const id = ++seq; calls.set(id, { ok, no }); post({ t: 'tool', id, name, args: args || {} }); });
  }
  function reply(m) {
    const c = calls.get(m.id); if (!c) return;
    calls.delete(m.id); m.ok ? c.ok(m.r) : c.no(new Error(m.error));
  }
  function fail(text) { for (const c of calls.values()) c.no(new Error(text)); calls.clear(); }

  const view = el('section', { id: 'view', hidden: true }), body = el('div', { className: 'vbody' }), note = el('div', { className: 'vnote' });
  const ttl = el('b'), bars = el('div', { className: 'vbar' });
  const ask = el('button', { textContent: 'Nhờ AI', title: 'Giao việc này cho trợ lý AI (tốn lượt AI)' });
  const x = el('button', { className: 'ic', textContent: '✕', title: 'Đóng bảng, về chat' });
  view.append(el('div', { className: 'vhead' }, ttl, ask, x), bars, note, body);
  document.body.append(view);
  // the assistant is only started when it is needed: opening a table alone costs nothing
  const close = () => { view.hidden = true; cur = ''; if (!running && !started) start(); };
  x.onclick = close;
  ask.onclick = () => { const k = cur; view.hidden = true; cur = ''; runSkill(k); };
  const say = (t, cls) => { note.textContent = t || ''; note.className = 'vnote ' + (cls || ''); };
  // one job at a time; errors go to the note line
  let busy = false;
  async function job(text, fn) {
    if (busy) return;
    busy = true; say(text, 'run'); view.classList.add('busy');
    try { await fn(); } catch (e) { say(e.message, 'err'); } finally { busy = false; view.classList.remove('busy'); }
  }
  const btn = (text, act, cls) => { const b = el('button', { textContent: text, className: 'vb ' + (cls || '') }); b.onclick = act; return b; };
  // changing the drawing takes two clicks
  const twice = (text, act) => { const b = btn(text, () => { if (b.dataset.arm) { delete b.dataset.arm; b.textContent = text; act(); return; } b.dataset.arm = 1; b.textContent = 'Bấm lần nữa để xác nhận'; setTimeout(() => { delete b.dataset.arm; b.textContent = text; }, 4000); }, 'warn'); return b; };
  const num = (v, d = 3) => (+v).toLocaleString('vi-VN', { maximumFractionDigits: d });
  const stamp = () => { const d = new Date(), p = n => String(n).padStart(2, '0'); return `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}-${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}`; };
  const base = path => path.split(/[\\/]/).pop().replace(/\.dwg$/i, '').replace(/[<>:"|?*]/g, '_');
  async function xlsx(kind, drawing, sheets) {
    const r = await call('export_xlsx', { _drawing: drawing, path: `Excel\\${kind}-${base(drawing)}-${stamp()}.xlsx`, sheets });
    say('✓ Đã lưu ' + r.path, 'ok'); note.append(' ', btn('Mở', () => post({ t: 'open', path: r.path })));
  }

  // ---------------------------------------------------------------- audit
  function audit() {
    let s = null, d = null;
    const go = btn('Quét bản vẽ', scan, 'pri'), dup = el('input', { type: 'checkbox', checked: true });
    bars.replaceChildren(go, el('label', {}, dup, ' Tìm trùng (chậm hơn)'));
    say('Chỉ đọc, chưa sửa gì. Bản vẽ lớn có thể mất vài phút.');
    function scan() {
      job('Đang quét…', async () => { s = await call('audit', { max_objects: 5000, max_items: 500 }); d = dup.checked ? await call('find_duplicates', { max_objects: 5000, _drawing: s._drawing }) : null; show(); });
    }
    const zoomTo = h => job('Đang zoom…', async () => { await call('zoom_to', { handles: [h], _drawing: s._drawing }); say('Đã zoom tới đối tượng ' + h); });
    function fix(name, args, text) { job('Đang sửa…', async () => { await call(name, { ...args, _drawing: s._drawing }); say('✓ ' + text + '. Sai thì gõ UNDO. Đang quét lại…', 'ok'); s = await call('audit', { max_objects: 5000, max_items: 500 }); d = dup.checked ? await call('find_duplicates', { max_objects: 5000, _drawing: s._drawing }) : null; show('✓ ' + text + '. Sai thì gõ UNDO.'); }); }
    function row(level, name, count, handles, action) {
      const r = el('details', { className: 'vrow ' + (count ? level : 'okk') });
      r.append(el('summary', {}, el('span', { textContent: name }), el('b', { textContent: count ? num(count, 0) : '✓' })));
      if (count && (handles.length || action)) r.append(el('div', { className: 'chips' }, ...handles.slice(0, 60).map(h => btn(h.text || h, () => zoomTo(h.h || h), 'chip')), action || null));
      return r;
    }
    function show(done) {
      const f = s.forced_color, z = s.zero_length, t = s.empty_text, o = s.dim_override;
      const all = k => k.count > k.items.length ? ` (${k.items.length} đối tượng đầu)` : '';
      body.replaceChildren(
        row('bad', 'Đối tượng trùng nhau', d ? d.extra_copies : 0, d ? d.examples.map(e => ({ text: `${e.type} · ${e.layer}`, h: e.handles[0] })) : [], twice('Xoá bản thừa', () => fix('delete_duplicates', { max_objects: 5000 }, 'Đã xoá bản trùng'))),
        row('bad', 'Đường dài bằng 0', z.count, z.items, twice('Xoá' + all(z), () => fix('delete', { handles: z.items }, 'Đã xoá'))),
        row('bad', 'Chữ rỗng', t.count, t.items, twice('Xoá' + all(t), () => fix('delete', { handles: t.items }, 'Đã xoá'))),
        row('bad', 'Kích thước gõ tay', o.count, o.items.map(i => ({ text: `${i.shown} (đo ${num(i.measured)})`, h: i.handle }))),
        row('bad', 'Xref không tìm thấy', s.missing_xrefs.length, s.missing_xrefs.map(i => ({ text: i.name, h: '' })).filter(() => false), el('div', { textContent: s.missing_xrefs.map(i => i.name + ': ' + i.path).join('\n') })),
        row('mid', 'Màu gán tay (không ByLayer)', f.count, f.items, twice('Đổi về ByLayer' + all(f), () => fix('set_props', { handles: f.items, color: 'bylayer' }, 'Đã đổi về ByLayer'))),
        row('mid', 'Đối tượng trên layer 0', s.on_layer_0, []), row('mid', 'Đối tượng trên Defpoints', s.on_defpoints, []),
        row('mid', 'Layer tắt / đóng băng còn đối tượng', s.hidden_layers_with_objects.length, [], el('div', { textContent: s.hidden_layers_with_objects.join(', ') })),
        row('mid', 'Tên layer gần giống nhau', s.similar_layer_names.length, [], el('div', { textContent: s.similar_layer_names.map(a => a.join(' ≈ ')).join('\n') })));
      const partial = s.partial || (d && d.total > d.scanned);
      say((done ? done + ' ' : '') + `${base(s.drawing)}: quét ${num(s.scanned, 0)}/${num(s.objects, 0)} đối tượng` + (partial ? ' - CHƯA HẾT, kết quả có thể thiếu' : '') + (d ? '' : ' · chưa tìm trùng'), partial ? 'err' : 'ok');
    }
  }

  // ---------------------------------------------------------------- quantities
  function quantities() {
    const lay = el('select'), unit = el('select'), sel = el('input', { type: 'checkbox' });
    for (const [t, v] of [['mm → m', 0.001], ['cm → m', 0.01], ['m → m', 1], ['giữ nguyên', 0]]) unit.append(el('option', { textContent: t, value: v }));
    let r = null;
    bars.replaceChildren(lay, unit, el('label', {}, sel, ' Đang chọn'), btn('Tính', run, 'pri'), btn('Excel', exp));
    lay.append(el('option', { textContent: 'Mọi layer', value: '' }));
    job('Đang đọc layer…', async () => {
      const i = await call('info'); unit.value = { mm: 0.001, cm: 0.01, m: 1 }[i.units] ?? 0;
      for (const l of await call('list_layers', { count_objects: false })) lay.append(el('option', { textContent: l.name, value: l.name }));
      say(`Đơn vị bản vẽ: ${i.units || 'chưa rõ'}. Kiểm tra ô đổi đơn vị trước khi tính.`);
    });
    const k = () => +unit.value || 1, u = () => +unit.value ? ['m', 'm²'] : ['đv', 'đv²'];
    function run() { job('Đang tính…', async () => { r = await call('quantities', { layer: lay.value, selection_only: sel.checked, max_objects: 20000 }); show(); }); }
    unit.onchange = () => r && show();
    function show() {
      const [a, b] = u(), tb = el('table');
      tb.append(el('tr', {}, ...['Layer', 'Loại', 'SL', 'Dài ' + a, 'Diện tích ' + b].map(t => el('th', { textContent: t }))));
      for (const q of r.rows) {
        const tr = el('tr', { title: 'Bấm để zoom tới một đối tượng mẫu' }, ...[q.layer, q.type, num(q.count, 0), num(q.length * k()), num(q.area * k() * k())].map(t => el('td', { textContent: t })));
        tr.onclick = () => job('Đang zoom…', async () => { await call('zoom_to', { handles: q.sample_handles, _drawing: r._drawing }); say('Đã zoom tới đối tượng mẫu'); });
        tb.append(tr);
      }
      const tl = r.rows.reduce((s, q) => s + q.length, 0) * k(), ta = r.rows.reduce((s, q) => s + q.area, 0) * k() * k();
      tb.append(el('tr', { className: 'sum' }, ...['Tổng', '', num(r.rows.reduce((s, q) => s + q.count, 0), 0), num(tl), num(ta)].map(t => el('td', { textContent: t }))));
      const bl = el('table');
      if (r.blocks.length) { bl.append(el('tr', {}, ...['Layer', 'Block', 'SL'].map(t => el('th', { textContent: t })))); for (const q of r.blocks) bl.append(el('tr', {}, ...[q.layer, q.block, num(q.count, 0)].map(t => el('td', { textContent: t })))); }
      body.replaceChildren(tb, bl);
      const skip = Object.entries(r.not_measured).map(([t, n]) => `${t} ${n}`).join(', ');
      say((r.partial ? 'CHƯA HẾT đối tượng, chia nhỏ theo layer. ' : '') + `${num(r.scanned, 0)} đối tượng. Hình vẽ theo tỷ lệ và đối tượng trùng chưa được xử lý.` + (skip ? ' Không đo được: ' + skip : ''), r.partial ? 'err' : 'ok');
    }
    function exp() {
      if (!r) { say('Bấm Tính trước.', 'err'); return; }
      const [a, b] = u(), [m, n] = [k(), k() * k()];
      job('Đang xuất…', () => xlsx('KhoiLuong', r._drawing, {
        'Khoi luong': [['Layer', 'Loại', 'Số lượng', 'Dài (' + a + ')', 'Diện tích (' + b + ')', 'Handle mẫu'], ...r.rows.map(q => [q.layer, q.type, q.count, q.length * m, q.area * n, q.sample_handles.join(' ')])],
        Block: [['Layer', 'Block', 'Số lượng'], ...r.blocks.map(q => [q.layer, q.block, q.count])],
        'Gia thiet': [['Mục', 'Giá trị'], ['Bản vẽ', r._drawing], ['Đổi đơn vị', unit.selectedOptions[0].textContent], ['Phạm vi', sel.checked ? 'Đang chọn' : (lay.value || 'Mọi layer')], ['Đã tính hết', r.partial ? 'KHÔNG' : 'Có'], ['Không đo được', JSON.stringify(r.not_measured)]] }));
    }
  }

  // ---------------------------------------------------------------- title blocks
  function titles() {
    let r = null, rows = [], tags = [];
    const pick = el('select');
    bars.replaceChildren(btn('Đọc', read, 'pri'), pick, twice('Áp dụng', apply), btn('Excel', exp));
    say('Đọc thuộc tính của block trong mô hình và mọi layout.');
    pick.onchange = show;
    function read() {
      job('Đang đọc…', async () => {
        r = await call('list_attributes', { max_blocks: 500 });
        const n = {}; for (const i of r.items) n[i.block] = (n[i.block] || 0) + 1;
        const old = pick.value; pick.replaceChildren(...Object.entries(n).sort((a, b) => b[1] - a[1]).map(([b, c]) => el('option', { textContent: `${b} (${c})`, value: b })));
        if (n[old]) pick.value = old;
        show(); if (!r.items.length) say('Không có block nào có thuộc tính.', 'err');
      });
    }
    function show() {
      if (!r) return;
      rows = r.items.filter(i => i.block === pick.value); tags = [...new Set(rows.flatMap(i => Object.keys(i.attributes)))];
      const tb = el('table');
      const fill = t => { const c = [...tb.querySelectorAll('input')].filter(i => i.dataset.tag === t); for (const i of c) { i.value = c[0].value; mark(i); } };
      const mark = i => i.classList.toggle('chg', i.value !== i.dataset.old);
      tb.append(el('tr', {}, el('th', { textContent: 'Layout' }), ...tags.map(t => { const b = btn('↓', () => fill(t)); b.title = 'Điền cả cột theo ô đầu'; return el('th', {}, t + ' ', b); })));
      for (const i of rows) {
        const go = el('td', { textContent: i.space, className: 'lnk', title: 'Zoom tới (mô hình)' });
        go.onclick = () => i.space === 'Model' && job('Đang zoom…', async () => { await call('zoom_to', { handles: [i.handle], _drawing: r._drawing }); say(''); });
        tb.append(el('tr', {}, go, ...tags.map(t => {
          if (!(t in i.attributes)) return el('td');
          const inp = el('input', { value: i.attributes[t] }); inp.dataset.old = i.attributes[t]; inp.dataset.tag = t; inp.dataset.h = i.handle; inp.oninput = () => mark(inp);
          return el('td', {}, inp);
        })));
      }
      body.replaceChildren(tb);
      say(`${rows.length} block` + (r.partial ? ' - CHƯA HẾT (tối đa 500)' : '') + '. Sửa trong bảng rồi bấm Áp dụng.', r.partial ? 'err' : 'ok');
    }
    function apply() {
      const ch = {}; let n = 0;
      for (const i of body.querySelectorAll('input.chg')) { (ch[i.dataset.h] = ch[i.dataset.h] || {})[i.dataset.tag] = i.value; n++; }
      if (!n) { say('Chưa đổi ô nào.', 'err'); return; }
      job('Đang ghi…', async () => {
        await call('set_attributes', { _drawing: r._drawing, changes: Object.entries(ch).map(([handle, values]) => ({ handle, values })) });
        r = await call('list_attributes', { max_blocks: 500 }); show(); say(`✓ Đã ghi ${n} ô. Sai thì gõ UNDO.`, 'ok');
      });
    }
    function exp() {
      if (!r || !rows.length) { say('Bấm Đọc trước.', 'err'); return; }
      job('Đang xuất…', () => xlsx('DanhMuc', r._drawing, { 'Danh muc': [['STT', 'Layout', ...tags], ...rows.map((i, n) => [n + 1, i.space, ...tags.map(t => i.attributes[t] ?? '')])] }));
    }
  }

  // ---------------------------------------------------------------- layer standard
  function layers() {
    let rows = [], dr = '';
    const std = () => { try { return JSON.parse(localStorage.layerStd || '[]'); } catch (e) { return []; } };   // [{ from, to, color }]
    const norm = s => s.normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/đ/gi, 'd').replace(/[\s_\-.]+/g, '').toLowerCase();
    bars.replaceChildren(btn('Đọc layer', read, 'pri'), twice('Áp dụng', apply), btn('Bảng chuẩn', edit), btn('Excel', exp));
    say('Gõ layer mới ở cột bên phải. Lưu bảng chuẩn một lần để lần sau tự điền.');
    function read() {
      job('Đang đọc…', async () => {
        const i = await call('info'); dr = i._drawing;
        const l = await call('list_layers', { count_objects: true }); const s = std();
        rows = l.filter(q => !q.name.includes('|')).map(q => {
          const hit = s.find(t => norm(t.from) === norm(q.name)) || s.find(t => t.to !== q.name && norm(t.to) === norm(q.name));
          return { ...q, to: hit ? hit.to : '' };
        });
        show();
      });
    }
    function show() {
      const tb = el('table'), names = el('datalist', { id: 'lyr' }, ...[...new Set([...std().map(t => t.to), ...rows.map(q => q.name)])].map(n => el('option', { value: n })));
      tb.append(el('tr', {}, ...['Layer hiện có', 'SL', 'Chuyển sang'].map(t => el('th', { textContent: t }))));
      for (const q of rows) {
        const inp = el('input', { value: q.to, placeholder: q.name === '0' || /^defpoints$/i.test(q.name) ? '(giữ nguyên)' : '' }); inp.setAttribute('list', 'lyr');
        inp.oninput = () => { q.to = inp.value.trim(); inp.classList.toggle('chg', !!q.to && q.to !== q.name); }; inp.oninput();
        tb.append(el('tr', {}, el('td', { textContent: q.name + (q.locked ? ' 🔒' : '') }), el('td', { textContent: num(q.objects, 0) }), el('td', {}, inp)));
      }
      body.replaceChildren(names, tb);
      const n = rows.filter(q => q.to && q.to !== q.name).length;
      say(`${rows.length} layer, ${n} layer sẽ chuyển. Không gồm đối tượng trong block; layer cũ không bị xoá.`, 'ok');
    }
    function apply() {
      const m = {}, c = {};
      for (const q of rows) if (q.to && q.to !== q.name) m[q.name] = q.to;
      if (!Object.keys(m).length) { say('Chưa có layer nào cần chuyển.', 'err'); return; }
      for (const t of std()) if (t.color) c[t.to] = t.color;
      job('Đang chuyển…', async () => {
        const r = await call('map_layers', { _drawing: dr, mapping: m, colors: c });
        const n = r.moved.reduce((s, q) => s + q.objects, 0);
        busy = false; view.classList.remove('busy');
        for (const q of rows) { const k = r.moved.find(v => v.from === q.name); if (k) { q.objects -= k.objects; q.to = ''; } }
        show(); say(`✓ Đã chuyển ${num(n, 0)} đối tượng (layout: ${r.layout_objects}${r.failed ? ', lỗi: ' + r.failed : ''}). Sai thì gõ UNDO, rồi bấm Đọc layer.`, r.failed ? 'err' : 'ok');
      });
    }
    function edit() {
      const ta = el('textarea', { className: 'std', value: std().map(t => [t.from, t.to, t.color || ''].join('\t')).join('\n'), placeholder: 'Mỗi dòng: layer cũ <Tab> layer chuẩn <Tab> màu ACI (không bắt buộc)\nDán thẳng từ Excel được.' });
      body.replaceChildren(ta, btn('Lưu bảng chuẩn', () => {
        const out = [];
        for (const line of ta.value.split('\n')) { const f = line.split(/\t|;/).map(s => s.trim()); if (f[0] && f[1]) { const c = parseInt(f[2], 10); out.push({ from: f[0], to: f[1], color: c >= 1 && c <= 255 ? c : 0 }); } }
        localStorage.layerStd = JSON.stringify(out); body.replaceChildren(); say(`✓ Đã lưu ${out.length} dòng. Bấm Đọc layer để áp vào bản vẽ.`, 'ok');
      }, 'pri'));
      say('Bảng chuẩn được nhớ trên máy này.'); ta.focus();
    }
    function exp() {
      if (!rows.length) { say('Bấm Đọc layer trước.', 'err'); return; }
      job('Đang xuất…', () => xlsx('Layer', dr, { Layer: [['Layer', 'Số đối tượng', 'Màu', 'Kiểu nét', 'Chuyển sang'], ...rows.map(q => [q.name, q.objects, q.color, q.linetype, q.to])] }));
    }
  }

  // ---------------------------------------------------------------- IFC
  // reads and edits the non-graphic data kept on the solids, then exports where the person chooses
  const FIX = [['name', 'Tên'], ['part', 'Bộ phận'], ['material', 'Vật liệu'], ['structure', 'Công trình'], ['station', 'Lý trình'], ['type', 'Loại'], ['group', 'Nhóm']];
  function ifc() {
    const scope = el('select'), sch = el('select'), unit = el('select'), det = el('select'), one = el('select'), inp = (ph, max) => el('input', { placeholder: ph, maxLength: max || 120 });
    const proj = inp('Tên dự án'), site = inp('Công trường / địa điểm'), road = inp('Tên tuyến (IFC4X3)'), author = inp('Người lập');
    let dr = '', r = null, cols = [];
    for (const [t, v] of [['Mọi khối 3D', '*'], ['Đang chọn', '+']]) scope.append(el('option', { textContent: t, value: v }));
    for (const [t, v] of [['IFC4', 'IFC4'], ['IFC4X3 (4.3)', 'IFC4X3']]) sch.append(el('option', { textContent: t, value: v }));
    for (const [t, v] of [['Đơn vị bản vẽ?', ''], ['m', 'm'], ['mm', 'mm'], ['cm', 'cm'], ['feet', 'ft'], ['US survey feet', 'us-ft'], ['inch', 'inch']]) unit.append(el('option', { textContent: t, value: v }));
    for (const [t, v] of [['Gộp theo bộ phận', 'part'], ['Tách từng khối', 'solid']]) det.append(el('option', { textContent: t, value: v }));
    for (const [t, v] of [['Một file chung', ''], ['Mỗi cống một file', '1']]) one.append(el('option', { textContent: t, value: v }));
    const more = el('details', { className: 'ifcmeta' }, el('summary', { textContent: 'Thông tin dự án (ghi vào file)' }), proj, site, road, author);
    bars.replaceChildren(scope, btn('Đọc khối', read, 'pri'), twice('Ghi vào bản vẽ', write), btn('Excel', exp), btn('Dán từ Excel', paste), btn('+ Cột', addCol), btn('Excel tổng hợp', summarySheet), one, det, sch, unit, btn('Xuất IFC…', save, 'pri'), more);
    job('Đang đọc bản vẽ…', async () => {
      const i = await call('info'); dr = i._drawing;
      unit.value = { m: 'm', mm: 'mm', cm: 'cm', feet: 'ft', 'US survey feet': 'us-ft', inch: 'inch' }[i.units] || '';
      for (const l of await call('list_layers', { count_objects: false })) scope.append(el('option', { textContent: 'Layer ' + l.name, value: '=' + l.name }));
      say(`Đơn vị bản vẽ: ${i.units || 'chưa rõ'}. Kiểm tra ô đơn vị, sai đơn vị là sai tỷ lệ. Chỉ khối solid 3D; corridor, surface, pipe network và khối trong block không được xuất.`);
    });
    const where = () => ({ from_layer: scope.value[0] === '=' ? scope.value.slice(1) : '', selection_only: scope.value === '+' });
    const edits = () => [...body.querySelectorAll('input.chg')];
    let wanted = '*';
    scope.onchange = () => { if (edits().length) { scope.value = wanted; say(`Còn ${edits().length} ô chưa ghi vào bản vẽ.`, 'err'); return; } wanted = scope.value; r = null; body.replaceChildren(); say('Bấm Đọc khối.'); };
    async function load() {
      const v = await call('solid_info', { ...where(), limit: 500, units: unit.value || 'm' });
      if (!v.total) { r = null; body.replaceChildren(); throw new Error('Không có khối 3D (solid) nào trong phạm vi này.'); }
      r = v; dr = v._drawing; off = new Set(v.structures.filter(c => c.issues.some(i => i.level === 'err')).map(c => c.key)); cols = [...FIX.map(f => f[0]), ...v.extra_fields.map(k => 'p:' + k)]; if (v.unit_hint && unit.value !== v.unit_hint && !unitByHand) { unit.value = v.unit_hint; fixed = true; } show();
    }
    let unitByHand = false, fixed = false;
    unit.onchange = () => { unitByHand = true; if (r && !edits().length) job('Đang tính lại…', async () => { await load(); summary(); }); };
    function read() {
      if (edits().length) { say(`Còn ${edits().length} ô chưa ghi. Ghi vào bản vẽ trước, hoặc đóng bảng để bỏ.`, 'err'); return; }
      job('Đang đọc khối…', async () => { await load(); summary(); });
    }
    function summary(lead) {
      const n = r.items.filter(q => q.approximate).length, miss = r.items.filter(q => !q.name && !q.part).length;
      const ne = r.structures.filter(c => c.issues.some(i => i.level === 'err')).length;
      say((lead ? lead + ' ' : '') + `${r.structures.length} cống, ${num(r.total, 0)} khối` + (ne ? `, ✖ ${ne} cống có lỗi (không chọn sẵn)` : '') + (r.partial ? ` (bảng hiện ${r.items.length} khối đầu; xuất vẫn đủ)` : '') + (miss ? `, ${miss} khối chưa có tên` : '')
        + (n ? `. ⚠ ${n} khối chỉ xuất dạng HỘP BAO (không do Steve AI dựng hoặc đã sửa).` : '.')
        + (r.unit_hint && unit.value !== r.unit_hint ? ' ⚠ Kích thước giống MÉT, ô đơn vị đang khác: xuất sẽ sai tỷ lệ.' : fixed ? ' ⚠ Bản vẽ khai báo mm/cm nhưng kích thước giống mét: đã chọn đơn vị m, hãy kiểm tra.' : ''), n || miss || ne || r.unit_hint ? 'run' : 'ok');
    }
    const label = c => c.startsWith('p:') ? c.slice(2) : FIX.find(f => f[0] === c)[1];
    const val = (q, c) => String((c.startsWith('p:') ? q.props[c.slice(2)] : q[c]) ?? '');
    const mark = i => i.classList.toggle('chg', i.value.trim() !== i.dataset.old.trim());
    function show(keep) {
      const tb = el('table');
      // fills the ticked rows (all rows when none is ticked) with the first non-empty value of the column
      const fill = c => {
        const all = [...tb.querySelectorAll('input[data-c]')].filter(i => i.dataset.c === c), tick = new Set([...tb.querySelectorAll('input[type=checkbox][data-h]:checked')].map(i => i.dataset.h));
        const to = tick.size ? all.filter(i => tick.has(i.dataset.h)) : all, src = to.find(i => i.value.trim());
        if (!src) { say('Nhập một ô trong cột trước rồi bấm ↓.', 'err'); return; }
        for (const i of to) { i.value = src.value; mark(i); }
      };
      const allBox = el('input', { type: 'checkbox', title: 'Chọn tất cả' });
      allBox.onchange = () => { for (const i of tb.querySelectorAll('input[type=checkbox][data-h]')) i.checked = allBox.checked; };
      tb.append(el('tr', {}, el('th', {}, allBox), el('th', { textContent: 'Khối' }), ...cols.map(c => { const b = btn('↓', () => fill(c)); b.title = 'Điền cả cột (hoặc các dòng đã tích) theo ô có chữ đầu tiên'; return el('th', {}, label(c) + ' ', b); }), el('th', { textContent: 'Layer' })));
      for (const q of r.items) {
        const ck = el('input', { type: 'checkbox' }); ck.dataset.h = q.handle;
        const go = el('td', { textContent: q.handle + (q.approximate ? ' ⚠' : ''), className: 'lnk', title: (q.approximate ? 'Chỉ xuất dạng hộp bao. ' : '') + 'Bấm để zoom tới khối' });
        go.onclick = () => job('Đang zoom…', async () => { await call('zoom_to', { handles: [q.handle], _drawing: dr }); say('Đã zoom tới khối ' + q.handle); });
        tb.append(el('tr', {}, el('td', {}, ck), go, ...cols.map(c => {
          const i = el('input', { value: val(q, c), maxLength: 500 }); i.dataset.old = i.value; i.dataset.c = c; i.dataset.h = q.handle; i.oninput = () => mark(i);
          if (c === 'material' && q.material_guess) i.placeholder = q.material_guess;
          if (c === 'group') i.placeholder = q.group_guess;
          if (keep && keep[q.handle + '|' + c] !== undefined) { i.value = keep[q.handle + '|' + c]; mark(i); }
          return el('td', {}, i);
        }), el('td', { textContent: q.layer })));
      }
      body.replaceChildren(...tree(), el('details', { className: 'vrow mid', open: !r.structures.length || !!keep }, el('summary', {}, el('span', { textContent: 'Thông tin từng khối (xem, sửa)' }), el('b', { textContent: r.items.length })), el('div', { className: 'vscroll' }, tb)));
    }
    // the culverts of the drawing, one row each; a row opens to its groups and parts
    let off = new Set();
    const f2 = (v, n = 2) => v === undefined || v === null ? '' : num(v, n);
    function tree() {
      const list = r.structures || []; if (!list.length) return [];
      const z = p => () => job('Đang zoom…', async () => { await call('zoom_to', { handles: p.handles, _drawing: dr }); say('Đã zoom tới ' + (p.name || p.key)); });
      const all = el('input', { type: 'checkbox', checked: list.every(c => !off.has(c.key)), title: 'Chọn tất cả' }), tb = el('table', { className: 'cv' }), boxes = [];
      all.onchange = () => { for (const b of boxes) { b.checked = all.checked; all.checked ? off.delete(b.dataset.k) : off.add(b.dataset.k); } };
      tb.append(el('tr', {}, el('th', {}, all), ...['Cống', 'Đốt', 'L (m)', 'i (%)', 'Góc chéo', 'Đáy TL', 'Đáy HL', 'V (m³)', 'Kiểm tra'].map(t => el('th', { textContent: t }))));
      for (const c of list) {
        const b = el('input', { type: 'checkbox', checked: !off.has(c.key) }); b.dataset.k = c.key; boxes.push(b);
        b.onchange = () => { b.checked ? off.delete(c.key) : off.add(c.key); };
        const nm = el('td', { className: 'lnk', textContent: c.key + (c.type ? ' · ' + c.type : ''), title: 'Bấm để zoom tới cống' }); nm.onclick = z(c);
        const bad = c.issues.some(i => i.level === 'err'), more = [...c.issues.map(i => (i.level === 'err' ? '✖ ' : '⚠ ') + i.text), ...c.geo.notes.map(t => '· ' + t)];
        const tr2 = el('tr', { hidden: true }), see = btn(bad ? '✖ Xem' : c.issues.length ? `⚠ ${c.issues.length}` : '✓', () => { tr2.hidden = !tr2.hidden; }, 'chip');
        tb.append(el('tr', {}, el('td', {}, b), nm, ...[c.barrel.segments ?? '', f2(c.geo.length_true ?? c.barrel.length, 3), f2(c.geo.slope, 3), f2(c.geo.skew, 1), f2(c.geo.z_up, 3), f2(c.geo.z_down, 3), f2(c.volume)].map(t => el('td', { textContent: t })), el('td', {}, see)));
        const t = el('table');
        for (const g of c.groups) t.append(el('tr', {}, el('th', { textContent: `${g.name} (${g.count} khối, ${num(g.volume)} m³)`, colSpan: 4 })), ...g.parts.map(p => { const a = el('td', { textContent: p.name + (p.approximate ? ' ⚠' : ''), className: 'lnk', title: 'Bấm để zoom' }); a.onclick = z(p); return el('tr', {}, a, el('td', { textContent: p.material }), el('td', { textContent: num(p.count, 0) + (p.segment_length ? ` x ${num(p.segment_length)} m` : '') }), el('td', { textContent: num(p.volume) + ' m³' })); }));
        tr2.append(el('td', { colSpan: 10 }, el('div', { textContent: c.title }), el('div', { className: 'cvnote', textContent: more.join('\n') }), el('div', { textContent: Object.entries(c.by_material).map(([m, v]) => `${m}: ${num(v)} m³`).join('   ') }), t));
        tb.append(tr2);
      }
      const n = Object.keys(r.suggestions || {}).length;
      return [el('div', { className: 'vscroll' }, tb), n ? el('div', { className: 'chips' }, `${n} khối chưa rõ thuộc cống nào, công cụ có đề xuất. `, btn('Đưa đề xuất vào bảng', takeSuggestions)) : null].filter(Boolean);
    }
    function takeSuggestions() {
      const k = pending(); let n = 0, out = 0;
      for (const [h, v] of Object.entries(r.suggestions)) { if (!r.items.some(q => q.handle === h)) { out++; continue; } for (const c of ['structure', 'station', 'type']) if (v[c]) { k[h + '|' + c] = v[c]; n++; } }
      show(k); say(`Đã đưa ${n} ô đề xuất vào bảng (màu vàng)` + (out ? `; ${out} khối ngoài 500 dòng đầu` : '') + '. Kiểm tra từng khối rồi bấm Ghi vào bản vẽ.', 'run');
    }
    function summarySheet() {
      if (!r || !r.structures.length) { say('Bấm Đọc khối trước.', 'err'); return; }
      const c = r.structures, m = [...new Set(c.flatMap(x => Object.keys(x.by_material)))];
      job('Đang xuất…', () => xlsx('TongHopCong', dr, {
        'Tong hop cong': [['STT', 'Công trình', 'Lý trình', 'Loại', 'Số đốt', 'Dài một đốt (m)', 'Dài danh nghĩa (m)', 'Dài thật (m)', 'Khẩu độ rộng (m)', 'Khẩu độ cao (m)', 'Đường kính trong (m)', 'Số khoang', 'Số hàng ống', 'Đáy thượng lưu', 'Đáy hạ lưu', 'Độ dốc (%)', 'Phương vị (độ)', 'Góc chéo (độ)', 'Thể tích (m³)', 'Kiểm tra'],
          ...c.map((x, i) => [i + 1, x.structure, x.station, x.type, x.barrel.segments ?? '', x.barrel.segment_length ?? '', x.barrel.length ?? '', x.geo.length_true ?? '', x.barrel.clear_w ?? '', x.barrel.clear_h ?? '', x.barrel.inner_d ?? '', x.geo.cells ?? '', x.geo.lanes ?? '', x.geo.z_up ?? '', x.geo.z_down ?? '', x.geo.slope ?? '', x.geo.azimuth ?? '', x.geo.skew ?? '', x.volume, [...x.issues.map(q => q.text), ...x.geo.notes].join('; ')])],
        'Khoi luong': [['Công trình', 'Lý trình', ...m.map(q => q + ' (m³)')], ...c.map(x => [x.structure, x.station, ...m.map(q => x.by_material[q] ?? 0)])] }));
    }
    const pending = () => Object.fromEntries(edits().map(i => [i.dataset.h + '|' + i.dataset.c, i.value]));
    function addCol() {
      if (!r) { say('Bấm Đọc khối trước.', 'err'); return; }
      const n = el('input', { placeholder: 'Tên thông tin, ví dụ: Mác bê tông', maxLength: 60 });
      say('Cột mới: '); note.append(n, btn('Thêm', () => { const c = n.value.trim(); if (!c) return; const key = 'p:' + c; if (cols.some(x => label(x).toLowerCase() === c.toLowerCase())) { say('Đã có cột này.', 'err'); return; } const k = pending(); cols.push(key); show(k); say('Đã thêm cột. Nhập giá trị rồi bấm Ghi vào bản vẽ.', 'ok'); }, 'pri'));
      n.focus();
    }
    function write() {
      const by = {}, ch = edits();
      if (!ch.length) { say('Chưa đổi ô nào.', 'err'); return; }
      for (const i of ch) { const w = by[i.dataset.h] = by[i.dataset.h] || { handle: i.dataset.h, props: {} }, c = i.dataset.c; if (c === 'name' || c === 'part' || c === 'material') w[c] = i.value; else w.props[c.startsWith('p:') ? c.slice(2) : c] = i.value; }
      job('Đang ghi vào bản vẽ…', async () => {
        const w = await call('tag_solids', { _drawing: dr, rows: Object.values(by) });
        if (w.failed && w.failed.length) { for (const i of ch) if (!w.failed.includes(i.dataset.h)) { i.dataset.old = i.value; mark(i); } throw new Error(`Đã ghi ${w.tagged} khối; KHÔNG ghi được ${w.failed.length} khối: ${w.failed.slice(0, 8).join(', ')}`); }
        await load(); summary(`✓ Đã ghi ${ch.length} ô của ${w.tagged} khối vào bản vẽ. Sai thì gõ UNDO.`);
      });
    }
    const table = () => [['Handle', ...cols.map(label), 'Layer', 'Thể tích (đv bản vẽ³)', 'Hộp bao'], ...r.items.map(q => [q.handle, ...cols.map(c => val(q, c)), q.layer, q.volume, q.approximate ? 'Có' : ''])];
    function exp() { if (!r) { say('Bấm Đọc khối trước.', 'err'); return; } job('Đang xuất…', () => xlsx('ThongTinIFC', dr, { 'Thong tin': table() })); }
    function paste() {
      if (!r) { say('Bấm Đọc khối trước.', 'err'); return; }
      const keep = pending(), ta = el('textarea', { className: 'std', placeholder: 'Bấm Excel để lấy bảng mẫu, sửa trong Excel, chép cả dòng tiêu đề (cột đầu là Handle) rồi dán vào đây.' });
      body.replaceChildren(ta, btn('Đưa vào bảng', () => {
        const p = parsePaste(ta.value);
        if (!p) { say('Dòng đầu phải là tiêu đề và cột đầu là Handle.', 'err'); return; }
        const known = new Map(r.items.map(q => [q.handle.toUpperCase(), q])), skip = new Set(['layer', 'thể tích (đv bản vẽ³)', 'hộp bao']); let n = 0, lost = 0;
        const key = p.head.map(h => { if (!h || skip.has(h.toLowerCase())) return ''; const c = cols.find(x => label(x).toLowerCase() === h.toLowerCase()); if (c) return c; cols.push('p:' + h.slice(0, 60)); return 'p:' + h.slice(0, 60); });
        for (const row of p.rows) { const q = known.get(row[0].toUpperCase()); if (!q) { lost++; continue; } key.forEach((c, i) => { if (c && i && row[i] !== undefined && row[i].trim() !== val(q, c).trim()) { keep[q.handle + '|' + c] = row[i].trim(); n++; } }); }
        show(keep); say(`Đã đưa ${n} ô vào bảng (màu vàng là ô đổi)` + (lost ? `, ${lost} dòng không có trong bảng nên bỏ qua` : '') + '. Kiểm tra rồi bấm Ghi vào bản vẽ.', lost ? 'run' : 'ok');
      }, 'pri'), btn('Thôi', () => { show(keep); summary(); }));
      ta.focus();
    }
    function save() {
      if (!r) { say('Bấm Đọc khối để xem trước rồi mới xuất.', 'err'); return; }
      if (edits().length) { say(`Còn ${edits().length} ô chưa ghi vào bản vẽ nên chưa có trong file. Bấm Ghi vào bản vẽ trước.`, 'err'); return; }
      if (!unit.value) { say('Chọn đơn vị bản vẽ trước.', 'err'); return; }
      const pick = r.structures.filter(c => !off.has(c.key)), many = one.value === '1';
      if (!pick.length) { say('Chưa chọn cống nào. Cống có lỗi ✖ mặc định không được chọn; xem lỗi rồi tích nếu vẫn muốn xuất.', 'err'); return; }
      job('Chọn chỗ lưu…', async () => {
        const f = await new Promise((ok, no) => { const id = ++seq; calls.set(id, { ok, no }); post({ t: 'savefile', id, name: `${base(dr)}.ifc`, many, dir: localStorage.ifcDir || '' }); });
        if (!f.path) { say('Chưa xuất: bạn chưa chọn chỗ lưu.'); return; }
        localStorage.ifcDir = f.dir; say('Đang xuất…', 'run');
        const w = await call('export_ifc', { _drawing: dr, path: f.path, detail: det.value, schema: sch.value, units: unit.value, project: proj.value.trim(), site: site.value.trim(), road: road.value.trim(), author: author.value.trim(), groups: pick.map(c => c.handles), split: many });
        say(`✓ Đã xuất ${pick.length} cống` + (w.files ? ` thành ${w.files.length} file` : '') + `, ${num(w.elements, 0)} khối` + (w.bounding_box_only.length ? `, ${num(w.bounding_box_only.length, 0)} khối là hộp bao` : '') + `. ${w.path}`, 'ok');
        note.append(' ', btn('Mở thư mục', () => post({ t: 'open', path: w.path })));
      });
    }
  }

  const list = { 'xuat-ifc': ['Export IFC', ifc], 'chuan-layer': ['Chuẩn layer', layers], 'kiem-tra-ban-ve': ['Kiểm tra bản vẽ', audit], 'boc-khoi-luong': ['Bóc khối lượng', quantities], 'khung-ten': ['Khung tên', titles] };
  function open(name) {
    if (!list[name]) return false;
    Ui.hide(); pop.hidden = true; view.hidden = false;
    if (cur !== name) { cur = name; ttl.textContent = list[name][0]; body.replaceChildren(); busy = false; view.classList.remove('busy'); list[name][1](); }
    return true;
  }
  const hide = () => { view.hidden = true; cur = ''; };
  return { open, hide, reply, fail, names: Object.keys(list), has: n => n in list, test: () => ({ note: note.textContent, body: body.textContent, cur, busy }) };
})();
