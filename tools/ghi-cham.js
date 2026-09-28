// Ghi kết quả chấm tay vào sale_response_review.
// Dùng: ELECTRON_RUN_AS_NODE=1 "D:/Microsoft VS Code/Code.exe" tools/ghi-cham.js ket-qua.json [--thu]
// ket-qua.json = [{id, verdict, severity?, issue?, suggestion?, source_faq?}, ...]
// Chỉ ghi vào dòng đang `chua_cham` — KHÔNG bao giờ ghi đè dòng đã chấm. --thu: kiểm file, không ghi.
// Monsieur Claude
const fs = require('fs');
const K = require('./keys.js');
const VERDICTS = ['dung', 'thieu', 'sai', 'khong_lien_quan', 'khong_tra_loi', 'chi_bot', 'tra_loi_inbox'];
const SEV = ['cao', 'trung', 'thap'];
const file = process.argv[2], thu = process.argv.includes('--thu');
if (!file) { console.error('Thiếu file kết quả'); process.exit(1); }
const rows = JSON.parse(fs.readFileSync(file, 'utf8'));
const loi = [];
for (const r of rows) {
  if (!Number.isInteger(r.id)) loi.push(`id không hợp lệ: ${JSON.stringify(r.id)}`);
  if (!VERDICTS.includes(r.verdict)) loi.push(`#${r.id}: verdict lạ "${r.verdict}"`);
  if (['thieu', 'sai'].includes(r.verdict)) {
    if (!SEV.includes(r.severity)) loi.push(`#${r.id}: ${r.verdict} phải có severity cao|trung|thap`);
    if (!r.issue || !r.suggestion) loi.push(`#${r.id}: ${r.verdict} phải có issue + suggestion`);
  } else if (r.severity) loi.push(`#${r.id}: ${r.verdict} không có severity`);
}
if (new Set(rows.map(r => r.id)).size !== rows.length) loi.push('trùng id trong file');
if (loi.length) { console.error('File lỗi:\n  ' + loi.join('\n  ')); process.exit(1); }
const count = {}; rows.forEach(r => count[r.verdict] = (count[r.verdict] || 0) + 1);
console.log(`${rows.length} dòng:`, count);
if (thu) process.exit(0);

const data = JSON.stringify(rows.map(r => ({ id: r.id, verdict: r.verdict, severity: r.severity || null,
  issue: r.issue || null, suggestion: r.suggestion || null, source_faq: r.source_faq || null })));
const tag = 'qc' + Date.now();   // dollar-quote tag riêng để nội dung không phá câu SQL
const sql = `with v as (select * from jsonb_to_recordset($${tag}$${data}$${tag}$::jsonb)
  as x(id bigint, verdict text, severity text, issue text, suggestion text, source_faq text))
update sale_response_review s set verdict=v.verdict, severity=v.severity, issue=v.issue,
  suggestion=v.suggestion, source_faq=v.source_faq, cham_boi='sonnet', reviewed_at=now()
from v where s.id=v.id and s.verdict='chua_cham' returning s.id`;
(async () => {
  const r = await fetch(`https://api.supabase.com/v1/projects/${K.ref}/database/query`, {
    method: 'POST', headers: { Authorization: 'Bearer ' + K.sbp, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: sql }),
  });
  const j = await r.json().catch(() => null);
  if (!r.ok) { console.error('HTTP', r.status, JSON.stringify(j)); process.exit(1); }
  const ghi = new Set(j.map(x => Number(x.id)));
  const bo = rows.filter(x => !ghi.has(x.id)).map(x => x.id);
  console.log(`Đã ghi ${ghi.size} dòng.` + (bo.length ? ` Bỏ qua ${bo.length} dòng không còn chua_cham: ${bo.join(', ')}` : ''));
})();
