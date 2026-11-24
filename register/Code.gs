/**
 * Steve AI Connect - máy chủ đăng ký (Google Apps Script gắn với một Google Sheet).
 * Cách cài: xem register/README.md. File này không chứa bí mật nào.
 *
 * POST JSON:
 *   {action:'send',   email}                                         -> gửi mã 6 số qua email
 *   {action:'verify', email, code, name?, phone?, consent?, news?, version?}
 *        -> {ok:true, name}; email mới mà chưa có họ tên/SĐT -> {ok:false, error:'profile'} (mã vẫn còn hiệu lực)
 * error: email | wait | limit | quota | code | expired | profile | busy | server
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
    var email = String(q.email || '').trim().toLowerCase();
    if (email.length > 120 || !/^[a-z0-9][a-z0-9._%+\-]*@[a-z0-9\-]+(\.[a-z0-9\-]+)*\.[a-z]{2,}$/.test(email)) return out_({ ok: false, error: 'email' });
    if (q.action === 'send') return out_(send_(email));
    if (q.action === 'verify') return out_(verify_(email, q));
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

function sheet_() {
  var ss = SpreadsheetApp.getActiveSpreadsheet(), sh = ss.getSheetByName(SHEET);
  if (!sh) { sh = ss.insertSheet(SHEET); sh.appendRow(HEAD); sh.setFrozenRows(1); }
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

/** Chạy hàm này một lần trong trình soạn Apps Script để cấp quyền (Sheet + gửi mail) và tạo sheet. */
function caiDat() { sheet_(); Logger.log('Còn gửi được ' + MailApp.getRemainingDailyQuota() + ' mail hôm nay.'); }
