/**
 * Steve AI Connect - máy chủ đăng ký (Google Apps Script gắn với một Google Sheet).
 * Cách cài: xem register/README.md. File này không chứa bí mật nào.
 *
 * POST JSON:
 *   {action:'send',   email}                                         -> gửi mã 6 số qua email
 *   {action:'verify', email, code, name?, phone?, consent?, news?, version?}
 *        -> {ok:true, name}; email mới mà chưa có họ tên/SĐT -> {ok:false, error:'profile'} (mã vẫn còn hiệu lực)
 *   {action:'feature', email, kind, cad, title, desc, version}        -> ghi vào sheet 'YeuCau'
 *   {action:'skill', email, name, title, desc, body, author, license, version} -> sheet 'SkillGopY' chờ duyệt
 *   {action:'skillpack', email, name, title, desc, author, license, version, sha, zip} -> gói .zip (base64) vào Google Drive, dòng ở sheet 'SkillGoi'
 *        -> {ok:true, receipt, sha}; gửi lại cùng gói thì trả mã biên nhận cũ
 *   {action:'report', key, src, version, msg, stack, sys}              -> gộp vào sheet 'Loi' (ẩn danh)
 * error: many | empty | email | wait | limit | quota | code | expired | profile | busy | server | sha | file | full
 * 'send' trả lời giống nhau dù email đã đăng ký hay chưa, để không ai dò được danh sách.
 */
var SHEET = 'DangKy';
var HEAD = ['Đăng ký lúc', 'Email', 'Họ và tên', 'SĐT', 'Đồng ý lưu thông tin', 'Nhận giới thiệu sản phẩm', 'Phiên bản', 'Đăng nhập gần nhất', 'Số lần đăng nhập'];
var CODE_TTL = 600;        // mã sống 10 phút
var MAX_TRIES = 5;         // nhập sai tối đa cho mỗi mã
var MAX_PER_HOUR = 5;      // số mã gửi tới một email mỗi giờ
var MAIL_RESERVE = 5;      // chừa lại một ít hạn mức mail trong ngày

function doGet() { return out_({ ok: true, service: 'Steve AI Connect register' }); }

function doPost(e) {
  var lock = LockService.getScriptLock();
  if (!lock.tryLock(15000)) return out_({ ok: false, error: 'busy' });
  try {
    var q = JSON.parse(e.postData.contents);
    if (q.action === 'report') return out_(report_(q));   // ẩn danh, không có email
    var email = String(q.email || '').trim().toLowerCase();
    if (email.length > 120 || !/^[a-z0-9][a-z0-9._%+\-]*@[a-z0-9\-]+(\.[a-z0-9\-]+)*\.[a-z]{2,}$/.test(email)) return out_({ ok: false, error: 'email' });
    if (q.action === 'send') return out_(send_(email));
    if (q.action === 'verify') return out_(verify_(email, q));
    if (q.action === 'feature') return out_(feature_(email, q));
    if (q.action === 'skill') return out_(skill_(email, q));   // bản v1.7.0
    if (q.action === 'skillpack') return out_(skillPack_(email, q));
    return out_({ ok: false, error: 'server' });
  } catch (err) {
    console.error(err);
    return out_({ ok: false, error: 'server' });
  } finally { SpreadsheetApp.flush(); lock.releaseLock(); }
}

function send_(email) {
  var c = CacheService.getScriptCache(), k = hash_(email);
  if (c.get('w' + k)) return { ok: false, error: 'wait' };
  var n = Number(c.get('n' + k) || 0);
  if (n >= MAX_PER_HOUR) return { ok: false, error: 'limit' };
  if (MailApp.getRemainingDailyQuota() <= MAIL_RESERVE) return { ok: false, error: 'quota' };
  var code = newCode_();
  // nội dung mail cố định, không chứa chữ do người gửi yêu cầu nhập vào
  MailApp.sendEmail({
    to: email, name: 'Steve AI Connect', subject: 'Mã xác nhận Steve AI Connect: ' + code,
    body: 'Mã xác nhận của bạn: ' + code + '\n\nMã có hiệu lực 10 phút. Không đưa mã này cho người khác.\n' +
          'Nếu bạn không yêu cầu, hãy bỏ qua email này.\n\nSteve AI Connect - Steve Tran - 0987 779 228'
  });
  c.put('c' + k, JSON.stringify({ h: hash_(email + ':' + code), t: 0 }), CODE_TTL);
  c.put('w' + k, '1', 60);
  c.put('n' + k, String(n + 1), 3600);
  return { ok: true };
}

function verify_(email, q) {
  var c = CacheService.getScriptCache(), k = hash_(email), raw = c.get('c' + k);
  if (!raw) return { ok: false, error: 'expired' };
  var st = JSON.parse(raw);
  if (st.h !== hash_(email + ':' + String(q.code || '').trim())) {
    st.t++;
    if (st.t >= MAX_TRIES) { c.remove('c' + k); return { ok: false, error: 'expired' }; }
    c.put('c' + k, JSON.stringify(st), CODE_TTL);
    return { ok: false, error: 'code' };
  }
  var name = String(q.name || '').replace(/[\x00-\x1f]+/g, ' ').replace(/^[\s=+\-@']+/, '').trim().slice(0, 80);
  var phone = String(q.phone || '').replace(/[^\d+]/g, '').replace(/^\+?84/, '0').replace(/\+/g, '');
  var given = name.length >= 2 && /^0\d{8,10}$/.test(phone) && q.consent === true;
  var sh = sheet_(), row = find_(sh, email), now = new Date();
  var ver = String(q.version || '').replace(/[^\w.\-]/g, '').slice(0, 20);
  if (!row) {
    if (!given) return { ok: false, error: 'profile' };
    // dấu ' ở đầu: Google Sheet giữ nguyên là chữ (số 0 đầu SĐT, không chạy công thức)
    sh.appendRow([now, "'" + email, "'" + name, "'" + phone, now, q.news === true ? 'Có' : 'Không', "'" + ver, now, 1]);
  } else {
    if (given) sh.getRange(row, 3, 1, 4).setValues([["'" + name, "'" + phone, now, q.news === true ? 'Có' : 'Không']]);
    else name = String(sh.getRange(row, 3).getValue());
    var count = Number(sh.getRange(row, 9).getValue() || 0) + 1;
    sh.getRange(row, 7, 1, 3).setValues([["'" + ver, now, count]]);
  }
  c.remove('c' + k);
  return { ok: true, name: name };
}

// Đề xuất tính năng. Email ở đây do người gửi tự khai (không qua mã), cột "Đã đăng ký" chỉ cho biết email có trong danh sách.
var SHEET2 = 'YeuCau';
var HEAD2 = ['Gửi lúc', 'Email', 'Họ và tên', 'Đã đăng ký', 'Loại', 'Dùng với', 'Tên tính năng', 'Mô tả', 'Phiên bản', 'Trạng thái', 'Ghi chú của Steve'];
function feature_(email, q) {
  var txt = function (v, n) { return String(v || '').replace(/[\x00-\x08\x0b-\x1f]/g, ' ').trim().slice(0, n); };
  var title = txt(q.title, 120), desc = txt(q.desc, 3000);
  if (title.length < 5 || desc.length < 15) return { ok: false, error: 'empty' };
  var c = CacheService.getScriptCache(), k = 'f' + hash_(email);   // 5 đề xuất mỗi email, 200 tổng cộng, trong 6 giờ
  var n = Number(c.get(k) || 0), all = Number(c.get('fall') || 0);
  if (n >= 5 || all >= 200) return { ok: false, error: 'many' };
  var users = sheet_(), row = find_(users, email), name = row ? String(users.getRange(row, 3).getValue()) : '';
  sheet_(SHEET2, HEAD2).appendRow([new Date(), "'" + email, "'" + name, row ? 'Có' : 'Không', "'" + txt(q.kind, 40), "'" + txt(q.cad, 20),
    "'" + title, "'" + desc, "'" + txt(q.version, 20), 'Mới', '']);
  c.put(k, String(n + 1), 21600); c.put('fall', String(all + 1), 21600);
  return { ok: true };
}

// Báo lỗi ẩn danh (người dùng đã đồng ý). Cùng một lỗi chỉ tăng cột "Số lần".
var SHEET3 = 'Loi';
var HEAD3 = ['Mã lỗi', 'Lần đầu', 'Lần cuối', 'Số lần', 'Phiên bản', 'Phần', 'Nội dung', 'Vị trí', 'Hệ thống', 'Trạng thái', 'Ghi chú'];
function report_(q) {
  var txt = function (v, n) { return String(v || '').replace(/[\x00-\x08\x0b-\x1f]/g, ' ').trim().slice(0, n); };
  var key = txt(q.key, 16), msg = txt(q.msg, 1500);
  if (!/^[0-9a-f]{16}$/.test(key) || !msg) return { ok: false, error: 'empty' };
  var c = CacheService.getScriptCache(), n = Number(c.get('rall') || 0);
  if (n >= 300) return { ok: false, error: 'many' };   // tổng cộng trong 6 giờ
  c.put('rall', String(n + 1), 21600);
  var sh = sheet_(SHEET3, HEAD3), last = sh.getLastRow(), now = new Date();
  if (last > 1) {
    var v = sh.getRange(2, 1, last - 1, 1).getValues();
    for (var i = 0; i < v.length; i++) if (String(v[i][0]) === key) {
      var cnt = Number(sh.getRange(i + 2, 4).getValue() || 0) + 1;
      sh.getRange(i + 2, 3, 1, 2).setValues([[now, cnt]]);
      return { ok: true };
    }
  }
  if (last > 5000) return { ok: false, error: 'many' };
  sh.appendRow(["'" + key, now, now, 1, "'" + txt(q.version, 20), "'" + txt(q.src, 60), "'" + msg, "'" + txt(q.stack, 1500), "'" + txt(q.sys, 400), 'Mới', '']);
  return { ok: true };
}

// Skill người dùng chia sẻ để Steve duyệt. Chưa duyệt thì không ai dùng được; đọc kỹ nội dung trước khi đưa vào công cụ.
var SHEET4 = 'SkillGopY';
var HEAD4 = ['Gửi lúc', 'Tên skill', 'Tiêu đề', 'Mô tả', 'Nội dung skill', 'Tên ghi công', 'Email', 'Đồng ý giấy phép', 'Phiên bản', 'Trạng thái', 'Ghi chú của Steve'];
function skill_(email, q) {
  var txt = function (v, n) { return String(v || '').replace(/[\x00-\x08\x0b\x0c\x0e-\x1f]/g, ' ').trim().slice(0, n); };
  var name = txt(q.name, 40), body = txt(q.body, 45000);
  if (!/^[a-z0-9]+(-[a-z0-9]+)*$/.test(name) || body.length < 50 || q.license !== true) return { ok: false, error: 'empty' };
  var c = CacheService.getScriptCache(), k = 's' + hash_(email), n = Number(c.get(k) || 0), all = Number(c.get('sall') || 0);
  if (n >= 5 || all >= 100) return { ok: false, error: 'many' };
  sheet_(SHEET4, HEAD4).appendRow([new Date(), "'" + name, "'" + txt(q.title, 80), "'" + txt(q.desc, 400), "'" + body, "'" + txt(q.author, 80), "'" + email, 'Apache 2.0', "'" + txt(q.version, 20), 'Mới', '']);
  c.put(k, String(n + 1), 21600); c.put('sall', String(all + 1), 21600);
  return { ok: true };
}

// Gói skill (.zip). Chỉ lưu khi SHA-256 của dữ liệu nhận được khớp với mã người gửi tính; đọc lại file trên Drive rồi mới trả mã biên nhận.
// SHA-256 chỉ chứng minh gói không bị đổi trên đường đi, KHÔNG chứng minh gói an toàn: đọc kỹ trước khi dùng, không chạy .lsp chưa đọc.
var SHEET5 = 'SkillGoi';
var HEAD5 = ['Gửi lúc', 'Mã biên nhận', 'Tên skill', 'Tiêu đề', 'Mô tả', 'Tên ghi công', 'Email', 'Đồng ý giấy phép', 'Phiên bản', 'Dung lượng (KB)', 'Danh sách file', 'Link file', 'SHA-256', 'Trạng thái', 'Ghi chú của Steve'];
var MAX_ZIP = 5 * 1024 * 1024;
var MAX_FILES = 60;
var FOLDER = 'Steve AI Connect - Skill gop y';
function skillPack_(email, q) {
  var txt = function (v, n) { return String(v || '').replace(/[\x00-\x08\x0b-\x1f]/g, ' ').trim().slice(0, n); };
  var name = txt(q.name, 41), sha = String(q.sha || ''), b64 = String(q.zip || '');
  if (name.length > 40 || !/^[a-z0-9]+(-[a-z0-9]+)*$/.test(name) || !/^[0-9a-f]{64}$/.test(sha) || !b64 || q.license !== true) return { ok: false, error: 'empty' };
  if (b64.length > MAX_ZIP * 4 / 3 + 8) return { ok: false, error: 'file' };
  var bytes; try { bytes = Utilities.base64Decode(b64); } catch (e) { return { ok: false, error: 'sha' }; }
  if (bytes.length > MAX_ZIP) return { ok: false, error: 'file' };
  if (hex_(Utilities.computeDigest(Utilities.DigestAlgorithm.SHA_256, bytes)) !== sha) return { ok: false, error: 'sha' };
  var files = zipNames_(bytes);
  if (!files || files.indexOf('SKILL.md') < 0) return { ok: false, error: 'file' };
  // cùng gói đã nhận: trả mã cũ, không tạo trùng (không tính vào giới hạn)
  var sh = sheet_(SHEET5, HEAD5), last = sh.getLastRow();
  if (last > 1) {
    var v = sh.getRange(2, 2, last - 1, 12).getValues();
    for (var i = 0; i < v.length; i++) if (String(v[i][11]) === sha && String(v[i][1]) === name) return { ok: true, receipt: String(v[i][0]), sha: sha };
  }
  var c = CacheService.getScriptCache(), k = 'p' + hash_(email), n = Number(c.get(k) || 0), all = Number(c.get('pall') || 0);
  if (n >= 5 || all >= 40) return { ok: false, error: 'many' };
  if (DriveApp.getStorageLimit() - DriveApp.getStorageUsed() < 500 * 1024 * 1024) return { ok: false, error: 'full' };   // chừa chỗ cho mail và Sheet
  var receipt = 'SK-' + Utilities.formatDate(new Date(), 'Asia/Ho_Chi_Minh', 'yyMMdd') + '-' + sha.slice(0, 8).toUpperCase();
  var f = folder_().createFile(Utilities.newBlob(bytes, 'application/zip', receipt + '_' + name + '.zip'));
  try {
    if (hex_(Utilities.computeDigest(Utilities.DigestAlgorithm.SHA_256, f.getBlob().getBytes())) !== sha) throw new Error('sha');
    sh.appendRow([new Date(), "'" + receipt, "'" + name, "'" + txt(q.title, 80), "'" + txt(q.desc, 400), "'" + txt(q.author, 80), "'" + email, 'Apache 2.0', "'" + txt(q.version, 20),
      Math.ceil(bytes.length / 1024), "'" + files.join('\n').slice(0, 5000), f.getUrl(), "'" + sha, 'Mới', '']);
    SpreadsheetApp.flush();
  } catch (e) { f.setTrashed(true); throw e; }
  c.put(k, String(n + 1), 21600); c.put('pall', String(all + 1), 21600);
  return { ok: true, receipt: receipt, sha: sha };
}
function hex_(b) { return b.map(function (x) { return ('0' + (x & 255).toString(16)).slice(-2); }).join(''); }
// tên file đọc từ mục lục của zip; null nếu hỏng, có đường dẫn lạ hoặc loại file không cho phép
function zipNames_(b) {
  var u = function (p, n) { var r = 0; for (var i = n - 1; i >= 0; i--) r = r * 256 + (b[p + i] & 255); return r; };
  if (b.length < 22 || u(0, 4) !== 0x04034b50) return null;
  var e = b.length - 22; while (e >= 0 && u(e, 4) !== 0x06054b50) e--;
  if (e < 0) return null;
  var count = u(e + 10, 2), p = u(e + 16, 4), out = [], total = 0;
  if (count < 1 || count > MAX_FILES) return null;
  for (var i = 0; i < count; i++) {
    if (p + 46 > b.length || u(p, 4) !== 0x02014b50) return null;
    var len = u(p + 28, 2), name = Utilities.newBlob(b.slice(p + 46, p + 46 + len)).getDataAsString('UTF-8');
    total += u(p + 24, 4);
    if (/[\x00-\x1f\\:*?"<>|]/.test(name) || /^\/|(^|\/)\.{1,2}(\/|$)/.test(name) || !/\.(md|lsp|txt|csv|xlsx|png|jpe?g)$/i.test(name) || out.indexOf(name) >= 0) return null;
    out.push(name); p += 46 + len + u(p + 30, 2) + u(p + 32, 2);
  }
  return total > 20 * 1024 * 1024 ? null : out;
}
// thư mục riêng tư (Drive mặc định không chia sẻ); chỉ tạo một lần
function folder_() {
  var pr = PropertiesService.getScriptProperties(), id = pr.getProperty('SKILL_FOLDER'), d;
  if (id) { try { d = DriveApp.getFolderById(id); if (!d.isTrashed()) return d; } catch (e) {} }
  d = DriveApp.createFolder(FOLDER); pr.setProperty('SKILL_FOLDER', d.getId());
  return d;
}

function sheet_(name, head) {
  name = name || SHEET; head = head || HEAD;
  var ss = SpreadsheetApp.getActiveSpreadsheet(), sh = ss.getSheetByName(name);
  if (!sh) { sh = ss.insertSheet(name); sh.appendRow(head); sh.setFrozenRows(1); }
  return sh;
}
function find_(sh, email) {
  var n = sh.getLastRow(); if (n < 2) return 0;
  var v = sh.getRange(2, 2, n - 1, 1).getValues();
  for (var i = 0; i < v.length; i++) if (String(v[i][0]).toLowerCase() === email) return i + 2;
  return 0;
}
function newCode_() {   // Utilities.getUuid dùng nguồn ngẫu nhiên tốt hơn Math.random
  return ('000000' + (parseInt(Utilities.getUuid().replace(/-/g, '').slice(0, 8), 16) % 1000000)).slice(-6);
}
function hash_(s) {
  return Utilities.base64EncodeWebSafe(Utilities.computeDigest(Utilities.DigestAlgorithm.SHA_256, s, Utilities.Charset.UTF_8));
}
function out_(o) { return ContentService.createTextOutput(JSON.stringify(o)).setMimeType(ContentService.MimeType.JSON); }

/**
 * Chạy hàm này một lần sau mỗi lần dán code mới (cấp quyền nếu được hỏi). KHÔNG xoá hay sửa dữ liệu:
 *  1. sao lưu từng bảng đang có dữ liệu sang một sheet ẩn "<tên>_SaoLuu_<ngày giờ>";
 *  2. tạo bảng còn thiếu;
 *  3. chỉ định dạng (màu, độ rộng, bộ lọc, danh sách trạng thái). Cột không đúng thứ tự thì dừng, không đụng vào bảng đó.
 */
function caiDat() {
  var ss = SpreadsheetApp.getActiveSpreadsheet(), all = [[SHEET, HEAD], [SHEET2, HEAD2], [SHEET3, HEAD3], [SHEET4, HEAD4], [SHEET5, HEAD5]], msg = [];
  var stamp = Utilities.formatDate(new Date(), ss.getSpreadsheetTimeZone(), 'yyyyMMdd_HHmmss');
  all.forEach(function (t) {
    var sh = ss.getSheetByName(t[0]);
    if (sh && sh.getLastRow() > 1) { sh.copyTo(ss).setName(t[0] + '_SaoLuu_' + stamp).hideSheet(); msg.push('Đã sao lưu ' + t[0] + ': ' + (sh.getLastRow() - 1) + ' dòng.'); }
  });
  all.forEach(function (t) {
    var sh = sheet_(t[0], t[1]), now = sh.getRange(1, 1, 1, t[1].length).getValues()[0];
    if (now.join('|') !== t[1].join('|')) { msg.push('⚠ ' + t[0] + ': cột không đúng thứ tự chuẩn, KHÔNG định dạng. Cột chuẩn: ' + t[1].join(', ')); return; }
    try { dinhDang_(sh, t[1]); msg.push('Đã định dạng ' + t[0] + '.'); } catch (e) { msg.push('⚠ ' + t[0] + ': ' + e.message); }
  });
  try { msg.push('Thư mục nhận skill: ' + folder_().getUrl()); } catch (e) { msg.push('⚠ Thư mục nhận skill: ' + e.message); }
  Logger.log(msg.join('\n') + '\nCòn gửi được ' + MailApp.getRemainingDailyQuota() + ' mail hôm nay.');
}
var DO_RONG = { 'Email': 220, 'Họ và tên': 170, 'SĐT': 110, 'Tên tính năng': 220, 'Mô tả': 380, 'Nội dung': 360, 'Vị trí': 280, 'Hệ thống': 220, 'Ghi chú': 220,
  'Ghi chú của Steve': 240, 'Tên skill': 150, 'Tiêu đề': 160, 'Nội dung skill': 380, 'Mã lỗi': 130, 'Mã biên nhận': 160, 'Danh sách file': 220, 'Link file': 260, 'SHA-256': 180, 'Số lần': 70, 'Phiên bản': 85, 'Trạng thái': 105, 'Phần': 140 };
function dinhDang_(sh, head) {
  var n = head.length, rows = sh.getMaxRows();
  if (!sh.getBandings().length) sh.getRange(1, 1, rows, n).applyRowBanding(SpreadsheetApp.BandingTheme.LIGHT_GREY, true, false);
  sh.getRange(1, 1, 1, n).setBackground('#0b57d0').setFontColor('#ffffff').setFontWeight('bold').setVerticalAlignment('middle').setWrap(true);
  sh.setRowHeight(1, 38); sh.setFrozenRows(1); sh.setFrozenColumns(2);
  var body = sh.getRange(2, 1, rows - 1, n).setVerticalAlignment('top').setWrapStrategy(SpreadsheetApp.WrapStrategy.CLIP);
  body.setFontFamily('Arial').setFontSize(10);
  head.forEach(function (h, i) {
    var col = sh.getRange(2, i + 1, rows - 1, 1);
    sh.setColumnWidth(i + 1, DO_RONG[h] || 130);
    if (/lúc|Lần đầu|Lần cuối|gần nhất|Đồng ý lưu/.test(h)) col.setNumberFormat('dd/MM/yyyy HH:mm');
    if (/Số lần/.test(h)) col.setNumberFormat('0').setHorizontalAlignment('center');
    if (h === 'Trạng thái') col.setDataValidation(SpreadsheetApp.newDataValidation().requireValueInList(['Mới', 'Đang xem', 'Đang làm', 'Đã xong', 'Không làm'], true).setAllowInvalid(true).build());
  });
  if (!sh.getFilter()) sh.getRange(1, 1, rows, n).createFilter();
}
