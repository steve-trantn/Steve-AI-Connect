// node tests/report-text.test.js
const { reportText } = require('../chat/web/ui.js'), assert = require('assert');
assert.strictEqual(reportText(' a\r\nb ', [], []), 'a\nb');
assert.strictEqual(reportText('x', ['loi: 1'], ['d']), 'x\n\n--- Lỗi gần đây ---\nloi: 1\n\n--- Chẩn đoán ---\nd');
const t = reportText('x'.repeat(1200), ['loi: a'], Array.from({ length: 300 }, (_, i) => 'dòng chẩn đoán ' + i));
assert(t.length === 3000 && t.endsWith('(đã rút gọn)') && t.includes('loi: a'));
console.log('PASS  reportText');
const { parsePaste } = require('../chat/web/panels.js');
assert.strictEqual(parsePaste('a\tb\n1\t2'), null);
assert.deepStrictEqual(parsePaste('Handle\tTên\tMác\r\n2A1\tTường "đầu"\tM300\r\n2A2\t"có ""ngoặc"""\t\r\n\t\t\r\n'), { head: ['Handle', 'Tên', 'Mác'], rows: [['2A1', 'Tường "đầu"', 'M300'], ['2A2', 'có "ngoặc"', '']] });
assert.deepStrictEqual(parsePaste('handle\tTên\n1E5\t"hai\ndòng"').rows, [['1E5', 'hai dòng']]);
console.log('PASS  parsePaste');
