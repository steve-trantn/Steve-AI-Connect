'use strict';
// Tables that work without AI: audit, quantities, title blocks. Data comes from server/panel.py through the host program.
const Panels = (() => {
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

  const list = { 'chuan-layer': ['Chuẩn layer', layers], 'kiem-tra-ban-ve': ['Kiểm tra bản vẽ', audit], 'boc-khoi-luong': ['Bóc khối lượng', quantities], 'khung-ten': ['Khung tên', titles] };
  function open(name) {
    if (!list[name]) return false;
    Ui.hide(); pop.hidden = true; view.hidden = false;
    if (cur !== name) { cur = name; ttl.textContent = list[name][0]; body.replaceChildren(); busy = false; view.classList.remove('busy'); list[name][1](); }
    return true;
  }
  const hide = () => { view.hidden = true; cur = ''; };
  return { open, hide, reply, fail, names: Object.keys(list), has: n => n in list, test: () => ({ note: note.textContent, body: body.textContent, cur, busy }) };
})();
