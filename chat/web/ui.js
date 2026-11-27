'use strict';
// Help, report, feature request, share a skill and update check inside the CAD panel. Names: ui-help, ui-diag, ui-feature, ui-share, ui-update.
// The form shows at once; the work is done by app/SteveAIUi.ps1 through the host program.
// The text of a problem report: the preview shows exactly what is sent (server limit: 3000 characters).
function reportText(say, errs, diag) {
  const cut = '\n(đã rút gọn)';
  let t = say.trim().replace(/\r\n?/g, '\n');
  if (errs.length) t += '\n\n--- Lỗi gần đây ---\n' + errs.join('\n');
  if (diag.length) t += '\n\n--- Chẩn đoán ---\n' + diag.join('\n');
  return t.length > 3000 ? t.slice(0, 3000 - cut.length) + cut : t;
}
if (typeof module !== 'undefined') module.exports = { reportText };

const Ui = typeof document === 'undefined' ? null : (() => {
  const calls = new Map(); let seq = 0, cur = '', ctx = null, gen = 0;
  const el = (tag, props, ...kids) => { const e = Object.assign(document.createElement(tag), props || {}); e.append(...kids.filter(k => k != null)); return e; };
  const call = (op, args) => new Promise((ok, no) => { const id = ++seq; calls.set(id, { ok, no }); post({ t: 'ui', id, op, args: args || {} }); });
  function reply(m) { const c = calls.get(m.id); if (!c) return; calls.delete(m.id); m.error ? c.no(new Error(m.error)) : c.ok(m.r); }
  const view = el('section', { id: 'ui', hidden: true }), ttl = el('b'), body = el('div', { className: 'ubody' }), note = el('div', { className: 'vnote' });
  const x = el('button', { className: 'ic', textContent: '✕', title: 'Đóng, về chat' });
  view.append(el('div', { className: 'vhead' }, ttl, x), body, note);
  document.body.append(view);
  const say = (t, cls) => { note.textContent = t || ''; note.className = 'vnote ' + (cls || ''); };
  let leave = null;   // what to do when the view is left (keeps a draft)
  function hide() { if (leave) { leave(); leave = null; } view.hidden = true; cur = ''; gen++; }
  function close() { hide(); if (client && !running && !started) start(); }
  x.onclick = close;
  addEventListener('keydown', e => { if (e.key === 'Escape' && !view.hidden && pop.hidden && !e.isComposing) { e.preventDefault(); e.stopPropagation(); close(); } }, true);
  const btn = (text, act, cls) => { const b = el('button', { textContent: text, className: 'vb ' + (cls || '') }); b.onclick = act; return b; };
  const field = (label, input) => el('label', { className: 'uf' }, label, input);
  const mail = () => el('input', { type: 'email', maxLength: 120, value: ctx ? ctx.email : '' });
  const okMail = v => /^[A-Za-z0-9][A-Za-z0-9._%+\-]*@[A-Za-z0-9\-]+(\.[A-Za-z0-9\-]+)*\.[A-Za-z]{2,}$/.test(v.trim());
  const outside = part => btn('Mở Steve AI Connect', () => post({ t: 'connect', part }));
  // one send at a time; the buttons stay off until the answer is there
  async function busy(buttons, text, fn) {
    for (const b of buttons) b.disabled = true;
    say(text, 'run');
    try { await fn(); } catch (e) { say(e.message, 'err'); if (/đăng ký/.test(e.message) && cur !== 'ui-setup') note.append(' ', btn('Thiết lập', () => open('ui-setup'), 'pri')); } finally { for (const b of buttons) if (b.isConnected) b.disabled = false; }
  }
  // the account's email etc.; asked once, then known
  async function withCtx(then) { const g = gen; try { ctx = await call('ctx'); } catch (e) { if (g === gen) say(e.message, 'err'); return; } if (g === gen && then) then(ctx); }

  // ---------------------------------------------------------------- help
  function help() {
    const rows = [['AI', 'Mở khung chat với trợ lý AI'], ['STEVEAI', 'Chọn trợ lý rồi mở'], ['STEVEAI-SKILL', 'Chạy một skill, ví dụ dựng cống 3D'], ['STEVECAD', 'Thiết lập: đăng ký, chọn hoặc cài trợ lý AI, kết nối lại'], ['STEVEAI-UPDATE', 'Kiểm tra bản mới']];
    const who = el('p', { textContent: 'Steve Tran  ·  0987 779 228' });
    const qr = el('div', { className: 'uqr' });
    const cf = el('button', { className: 'ulink', textContent: '☕ Mời Steve ly cà phê' });
    cf.onclick = async () => {   // the QR is only read and shown on this click
      if (qr.firstChild) { qr.replaceChildren(); return; }
      cf.disabled = true;
      try { const r = await call('qr'); qr.replaceChildren(el('img', { src: 'data:image/png;base64,' + r.png, alt: 'QR MoMo' }), el('small', { textContent: 'Quét bằng MoMo hoặc app ngân hàng bất kỳ' })); qr.scrollIntoView(); } catch (e) { say(e.message, 'err'); } finally { cf.disabled = false; }
    };
    body.replaceChildren(el('dl', {}, ...rows.flatMap(([a, b]) => [el('dt', { textContent: a }), el('dd', { textContent: b })])),
      el('p', { className: 'dim', textContent: 'Gõ yêu cầu bằng tiếng Việt trong khung chat, ví dụ: "đếm block theo layer". AI sửa bản vẽ thì gõ U hoặc UNDO để hoàn tác.' }),
      el('h3', { textContent: 'Cần hỗ trợ?' }), who,
      el('div', { className: 'ubtn' }, btn('Báo lỗi', () => open('ui-diag'), 'pri'), btn('Đề xuất tính năng', () => open('ui-feature')), btn('Chép số ĐT', () => navigator.clipboard.writeText('0987779228').then(() => say('✓ Đã chép số điện thoại.', 'ok'), () => say('Chưa chép được.', 'err')))),
      el('div', { className: 'ubtn' }, outside('home')), cf, qr);
  }

  // ---------------------------------------------------------------- report a problem
  function report() {
    let diag = [], errs = [], loaded = false, sent = '', g = gen;
    const t = el('textarea', { maxLength: 1200, rows: 5, placeholder: 'Ví dụ: Bấm Bóc khối lượng trong ZWCAD 2026, khung chat báo… (đừng ghi thông tin mật của dự án)' }), m = mail();
    const kd = el('input', { type: 'checkbox', checked: true }), ke = el('input', { type: 'checkbox', checked: true }), el2 = el('span', { textContent: ' Kèm lỗi gần đây của công cụ' });
    const pv = el('textarea', { readOnly: true, rows: 9, className: 'pv' });
    const text = () => reportText(t.value, ke.checked ? errs : [], kd.checked ? diag : []);
    const show = () => { pv.value = text() + (loaded ? '' : '\n\n(đang đọc thông tin chẩn đoán…)'); };
    const go = btn('Gửi cho Steve', send, 'pri'), cp = btn('Chép để gửi Zalo', () => navigator.clipboard.writeText(text()).then(() => say('✓ Đã chép. Dán (Ctrl+V) vào Zalo 0987 779 228.', 'ok'), () => say('Chưa chép được.', 'err')));
    t.oninput = kd.onchange = ke.onchange = show;
    body.replaceChildren(field('Bạn đang làm gì thì gặp lỗi?', t), field('Email để Steve phản hồi', m), el('label', { className: 'uc' }, kd, ' Kèm thông tin chẩn đoán'), el('label', { className: 'uc' }, ke, el2),
      field('Đúng nội dung sẽ gửi, không kèm bản vẽ (phần kèm thêm đã lọc thông tin riêng):', pv), el('div', { className: 'ubtn' }, go, cp));
    show(); t.focus();
    leave = () => { if (t.value !== ((ctx && ctx.draft) || '') || sent) { const d = sent && sent === text() ? '' : t.value; if (ctx) ctx.draft = d; call('draft', { text: d }).catch(() => {}); } };
    withCtx(c => { if (!m.value) m.value = c.email; if (!t.value) t.value = c.draft; show(); });
    call('diag').then(r => { diag = r.diag || []; errs = r.errs || []; }, () => { diag = ['(không đọc được chẩn đoán)']; }).then(() => {
      if (g !== gen) return;
      loaded = true; if (!errs.length) { ke.checked = false; ke.disabled = true; el2.textContent = ' Không có lỗi gần đây được ghi lại'; } else el2.textContent = ` Kèm ${errs.length} lỗi gần đây của công cụ`;
      show();
    });
    function send() {
      if (sent && sent === text()) { say('✓ Nội dung này đã gửi rồi.', 'ok'); return; }
      if (t.value.trim().length < 15) { say('Mô tả thêm một chút (ít nhất 15 ký tự).', 'err'); return; }
      if (!okMail(m.value)) { say('Email chưa đúng.', 'err'); return; }
      if (!loaded) { say('Đang đọc thông tin chẩn đoán, đợi một chút rồi bấm lại.', 'run'); return; }
      const d = text(), one = t.value.trim().replace(/\s+/g, ' ');
      busy([go, cp, t, m, kd], 'Đang gửi…', async () => {
        await call('feature', { email: m.value, kind: 'Báo lỗi', cad: 'Chung', title: 'Báo lỗi: ' + (one.length > 100 ? one.slice(0, 100) + '…' : one), desc: d });
        sent = d; if (ctx) ctx.draft = ''; if (g === gen) say('✓ Đã gửi. Cảm ơn bạn, Steve sẽ xem và phản hồi qua email!', 'ok');
      });
    }
  }

  // ---------------------------------------------------------------- feature request
  function feature() {
    const sel = a => { const s = el('select'); for (const v of a) s.append(el('option', { textContent: v, value: v })); return s; };
    const g = gen, kind = sel(['Tính năng mới', 'Cải tiến tính năng có sẵn']), cad = sel(['Chung', 'ZWCAD', 'AutoCAD', 'ADSCivil']);
    const ti = el('input', { type: 'text', maxLength: 120 }), de = el('textarea', { maxLength: 3000, rows: 7 }), m = mail();
    const go = btn('Gửi đề xuất', send, 'pri');
    body.replaceChildren(el('p', { className: 'dim', textContent: 'Nội dung gửi thẳng tới Steve Tran. Đừng ghi thông tin mật của dự án.' }), field('Loại', kind), field('Dùng với', cad), field('Tên tính năng', ti),
      field('Mô tả: cần làm gì, dùng khi nào, kết quả mong muốn', de), field('Email để Steve phản hồi', m), el('div', { className: 'ubtn' }, go));
    ti.focus(); withCtx(c => { if (!m.value) m.value = c.email; });
    function send() {
      if (ti.value.trim().length < 5) { say('Tên tính năng cần ít nhất 5 ký tự.', 'err'); return; }
      if (de.value.trim().length < 15) { say('Mô tả thêm một chút (ít nhất 15 ký tự).', 'err'); return; }
      if (!okMail(m.value)) { say('Email chưa đúng.', 'err'); return; }
      busy([go, ti, de, m], 'Đang gửi…', async () => { await call('feature', { email: m.value, kind: kind.value, cad: cad.value, title: ti.value, desc: de.value }); if (g !== gen) return; ti.value = de.value = ''; say('✓ Đã gửi. Cảm ơn bạn, Steve sẽ xem và phản hồi qua email!', 'ok'); });
    }
  }

  // ---------------------------------------------------------------- share a skill
  function share() {
    let pack = null, sure = false, n = 0; const g = gen;
    const s = el('select'), pv = el('textarea', { readOnly: true, rows: 12, className: 'pv' }), au = el('input', { type: 'text', maxLength: 80 }), m = mail(), ck = el('input', { type: 'checkbox' });
    const go = btn('Gửi cho Steve', send, 'pri');
    body.replaceChildren(el('p', { className: 'dim', textContent: 'Đang đọc skill của bạn…' }));
    withCtx(c => { if (!m.value) m.value = c.email; });
    call('skills').then(r => {
      if (g !== gen) return;
      if (!r.skills.length) { body.replaceChildren(el('p', { textContent: 'Bạn chưa có skill riêng. Bấm ＋ → Tạo skill trong khung chat để AI giúp bạn viết một skill, rồi quay lại đây chia sẻ.' })); return; }
      for (const k of r.skills) s.append(el('option', { value: k.name, textContent: k.title ? `${k.title} (${k.name})` : k.name }));
      body.replaceChildren(el('p', { className: 'dim', textContent: 'Gửi nguyên cả thư mục skill. Steve đọc và duyệt; được chọn thì skill có trong bản cập nhật, ghi công bạn. Xem kỹ để không gửi tên dự án, khách hàng, mật khẩu.' }),
        field('Skill', s), field('Nội dung gói', pv), field('Tên ghi công (để trống = ẩn danh)', au), field('Email để Steve phản hồi', m),
        el('label', { className: 'uc' }, ck, ' Nội dung này do tôi viết (hoặc tôi được phép chia sẻ) và tôi đồng ý phát hành theo giấy phép Apache 2.0'), el('div', { className: 'ubtn' }, go));
      s.onchange = load; load();
    }, e => { if (g === gen) say(e.message, 'err'); });
    async function load() {
      const me = ++n; pack = null; sure = false; pv.value = 'Đang đóng gói…'; say('');
      try {
        const p = await call('pack', { name: s.value }); if (me !== n || g !== gen) return;
        pack = p;
        pv.value = `GÓI GỒM ${p.files.length} FILE, ${p.kb} KB\n` + p.files.map(f => '  ' + f).join('\n') + (p.skipped.length ? '\nKhông gửi (file tạm, sao lưu): ' + p.skipped.join(', ') : '')
          + (p.notes.length ? '\n\n⚠ XEM LẠI TRƯỚC KHI GỬI\n' + p.notes.map(f => '  ' + f).join('\n') : '') + `\n\nSHA-256: ${p.sha}\n${p.text}`;
      } catch (e) { if (me === n && g === gen) pv.value = 'KHÔNG GỬI ĐƯỢC\n\n' + e.message; }
    }
    function send() {
      if (!pack) { say('Chưa có gói để gửi. Xem thông báo ở khung trên.', 'err'); return; }
      if (!okMail(m.value)) { say('Email chưa đúng.', 'err'); return; }
      if (!ck.checked) { say('Cần tích đồng ý giấy phép để chia sẻ.', 'err'); return; }
      if (pack.notes.length && !sure) { sure = true; say('Có mục cần xem lại (⚠ ở khung trên). Vẫn muốn gửi thì bấm Gửi lần nữa.', 'err'); return; }
      busy([go, s, au, m, ck], 'Đang gửi…', async () => { const r = await call('share', { name: s.value, sha: pack.sha, email: m.value, author: au.value, license: ck.checked }); if (g === gen) say(r.text, 'ok'); });
    }
  }

  // ---------------------------------------------------------------- update check and install (the new Setup.exe runs without a window of the tool)
  function update() {
    const g = gen; body.replaceChildren(); say('Đang kiểm tra bản mới…', 'run');
    call('update').then(r => {
      if (g !== gen) return;
      if (!r.tag) { say(`✓ Bạn đang dùng bản mới nhất (${r.current}).`, 'ok'); return; }
      say('');
      const go = btn('Cập nhật ngay', () => busy([go], 'Đang tải bản mới (kiểm tra mã SHA-256)…', async () => {
        await call('upgrade');
        if (g === gen) say('✓ Đã tải. Cửa sổ cài đặt đang chạy; cài xong hãy lưu bản vẽ, đóng hẳn CAD rồi mở lại.', 'ok');
      }), 'pri');
      body.replaceChildren(el('h3', { textContent: `Có bản mới ${r.tag}` }), el('p', { className: 'dim', textContent: `Bạn đang dùng ${r.current}. Cấu hình và đăng ký được giữ nguyên.` }),
        el('pre', { textContent: r.notes.replace(/[*`#>]/g, '').trim() }), el('div', { className: 'ubtn' }, go));
    }, e => { if (g === gen) say(e.message, 'err'); });
  }

  // ---------------------------------------------------------------- set-up: registration, assistant, connection (v1.10: no outside window)
  function setup() {
    const g = gen; let st = null, login = false, sentTo = '', trialOffer = false, acts = [];
    body.replaceChildren(el('p', { className: 'dim', textContent: 'Đang đọc trạng thái…' }));
    const load = () => call('setup').then(r => { if (g !== gen) return; st = r; draw(); }, e => { if (g === gen) say(e.message, 'err'); });
    // registration form, kept across redraws
    const em = el('input', { type: 'email', maxLength: 120 }), nm = el('input', { type: 'text', maxLength: 80 }), ph = el('input', { type: 'tel', maxLength: 20 });
    const c1 = el('input', { type: 'checkbox' }), c2 = el('input', { type: 'checkbox' }), cd = el('input', { type: 'text', maxLength: 6, inputMode: 'numeric', placeholder: '6 chữ số' });
    const key = el('input', { type: 'password', maxLength: 200, placeholder: 'Dán Gemini API key' });
    const regArgs = () => ({ email: em.value, login, name: nm.value, phone: ph.value, consent: c1.checked, news: c2.checked });
    load();
    function draw() {
      const parts = [];
      // ---- 1. registration
      parts.push(el('h3', { textContent: '1. Đăng ký (miễn phí, một lần)' }));
      if (st.registered) parts.push(el('p', { textContent: '✓ Đã đăng ký: ' + st.email }));
      else {
        if (st.access && st.trialLeft > 0) parts.push(el('p', { className: 'dim', textContent: `Đang dùng tạm, còn ${st.trialLeft} ngày. Đăng ký để dùng tiếp.` }));
        parts.push(el('p', { className: 'dim', textContent: login ? 'Đã đăng ký trên máy khác: nhập email, nhận mã, xác nhận.' : 'Đăng ký xong, máy này dùng được cả khi không có mạng. Bản vẽ không bị gửi đi.' }));
        parts.push(field('Email', em));
        if (!login) parts.push(field('Họ và tên', nm), field('Số điện thoại', ph),
          el('label', { className: 'uc' }, c1, ' Tôi đồng ý để Steve Tran lưu email, họ tên, SĐT để hỗ trợ và báo bản cập nhật (bắt buộc)'),
          el('label', { className: 'uc' }, c2, ' Nhận giới thiệu sản phẩm, đào tạo BIM (không bắt buộc)'));
        const send = btn(sentTo ? 'Gửi lại mã' : 'Gửi mã về email', () => reg('reg-send', [send, ok]), sentTo ? '' : 'pri');
        const ok = btn('Xác nhận', () => reg('reg-verify', [send, ok]), sentTo ? 'pri' : '');
        ok.disabled = !sentTo; cd.disabled = !sentTo;
        parts.push(el('div', { className: 'ubtn' }, send), field('Mã trong email (xem cả mục Spam)', cd), el('div', { className: 'ubtn' }, ok));
        const mode = el('button', { className: 'ulink', textContent: login ? 'Chưa có tài khoản? Đăng ký' : 'Đã đăng ký rồi? Đăng nhập' });
        mode.onclick = () => { login = !login; say(''); draw(); };
        parts.push(mode);
        if (trialOffer) {
          const t = el('button', { className: 'ulink', textContent: 'Không kết nối được máy chủ: dùng tạm 7 ngày' });
          t.onclick = () => busy([t], 'Đang bật dùng tạm…', async () => { await call('trial'); trialOffer = false; await load(); say('✓ Đang dùng tạm. Nhớ đăng ký khi có mạng.', 'ok'); });
          parts.push(t);
        }
      }
      // ---- 2. assistant
      parts.push(el('h3', { textContent: '2. Trợ lý AI' }));
      const cads = st.cads.filter(c => c.ok).map(c => c.label);
      if (!cads.length) parts.push(el('p', { className: 'dim', textContent: '⚠ Máy chưa có ZWCAD, AutoCAD hoặc ADSCivil.' }));
      else parts.push(el('p', { className: 'dim', textContent: 'Nối với: ' + cads.join(', ') + '. Trợ lý cần tài khoản của hãng (Claude Pro, ChatGPT Plus, hoặc Gemini API key miễn phí); lần mở đầu sẽ hỏi đăng nhập ngay trong khung chat.' }));
      acts = [];
      for (const c of st.clients) {
        const done = c.connected && c.key;
        const s = done ? '✓ đã kết nối' : c.installed ? (c.key ? 'đã cài, chưa kết nối' : 'cần API key') : 'chưa cài';
        const b = btn(done ? 'Kết nối lại' : c.installed ? 'Kết nối' : 'Cài và kết nối', () => connect(c), done ? '' : 'pri');
        b.disabled = !st.access || !cads.length || (!c.installed && !st.winget && c.id !== 'gemini'); acts.push(b);
        parts.push(el('div', { className: 'ubtn' }, el('span', { style: 'min-width:110px;align-self:center', textContent: c.label }), el('span', { className: 'dim', style: 'align-self:center;flex:1', textContent: s }), b));
        if (c.id === 'gemini' && !c.key) parts.push(field('Gemini API key (lấy miễn phí tại aistudio.google.com/apikey)', key));
      }
      if (!st.access) parts.push(el('p', { className: 'dim', textContent: 'Đăng ký ở bước 1 trước.' }));
      const ready = st.access && st.clients.some(c => c.installed && c.key && c.connected);
      const go = btn('Bắt đầu chat', () => { hide(); post({ t: 'reinfo' }); }, ready ? 'pri' : '');
      go.disabled = !ready;
      parts.push(el('div', { className: 'ubtn' }, go));
      const adv = el('button', { className: 'ulink', textContent: `Tùy chọn nâng cao (cửa sổ Steve AI Connect) · ${st.version}` });
      adv.onclick = () => post({ t: 'connect', part: 'home' });
      parts.push(adv);
      body.replaceChildren(...parts);
    }
    function reg(op, buttons) {
      busy(buttons.concat([em, nm, ph, c1, c2, cd]), 'Đang kết nối…', async () => {
        const r = await call(op, Object.assign(regArgs(), op === 'reg-verify' ? { code: cd.value } : {}));
        if (g !== gen) return;
        if (!r.ok) {
          if (r.trial) trialOffer = true;
          if (r.why === 'profile') login = false;
          if (r.why === 'expired') { sentTo = ''; cd.value = ''; }
          draw(); say(r.text, 'err'); return;
        }
        if (op === 'reg-send') { sentTo = em.value.trim().toLowerCase(); draw(); say(`✓ Đã gửi mã tới ${sentTo}. Mã có hiệu lực 10 phút.`, 'ok'); cd.focus(); return; }
        await load(); say('✓ Đã đăng ký. Sang bước 2: chọn trợ lý AI.', 'ok');
      });
    }
    function connect(c) {
      if (c.id === 'gemini' && !c.key && !key.value.trim()) { say('Dán Gemini API key vào ô trước.', 'err'); key.focus(); return; }
      const what = c.installed ? 'Đang kết nối…' : `Đang tải và cài ${c.label} từ kho chính thức, khoảng 1-3 phút. Đừng đóng CAD…`;
      busy(acts, what, async () => {
        const r = await call('connect', { install: c.installed ? '' : c.id, key: c.id === 'gemini' ? key.value : '' });
        if (g !== gen) return;
        key.value = '';
        await load();
        if (r.ok) say(`✓ Xong. Bấm “Bắt đầu chat”. Lần đầu, ${c.label} sẽ hỏi đăng nhập tài khoản ngay trong khung chat.`, 'ok');
        else say('Có lỗi: ' + (r.log || []).filter(x => /lỗi/i.test(x)).slice(-3).join(' · ') + ' Cần hỗ trợ: 0987 779 228', 'err');
      });
    }
  }

  const list = { 'ui-help': ['Hướng dẫn & hỗ trợ', help], 'ui-diag': ['Báo lỗi cho Steve', report], 'ui-feature': ['Đề xuất tính năng', feature], 'ui-share': ['Chia sẻ skill', share], 'ui-update': ['Cập nhật', update], 'ui-setup': ['Thiết lập Steve AI', setup] };
  function open(name) {
    if (!list[name]) return false;
    pop.hidden = true;
    if (cur === name && name !== 'ui-update') { view.hidden = false; return true; }   // already there: keep what was typed
    if (leave) { leave(); leave = null; }
    gen++; cur = name; ttl.textContent = list[name][0]; body.replaceChildren(); body.scrollTop = 0; say(''); view.hidden = false; list[name][1]();
    return true;
  }
  return { open, reply, hide, isOpen: () => !view.hidden };
})();
