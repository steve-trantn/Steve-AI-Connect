// node tests/report-text.test.js
const { reportText } = require('../chat/web/ui.js'), assert = require('assert');
assert.strictEqual(reportText(' a\r\nb ', [], []), 'a\nb');
assert.strictEqual(reportText('x', ['loi: 1'], ['d']), 'x\n\n--- Lỗi gần đây ---\nloi: 1\n\n--- Chẩn đoán ---\nd');
const t = reportText('x'.repeat(1200), ['loi: a'], Array.from({ length: 300 }, (_, i) => 'dòng chẩn đoán ' + i));
assert(t.length === 3000 && t.endsWith('(đã rút gọn)') && t.includes('loi: a'));
console.log('PASS  reportText');
