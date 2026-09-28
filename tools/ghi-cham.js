// Ghi kết quả chấm tay vào sale_response_review.
// Dùng: ELECTRON_RUN_AS_NODE=1 "D:/Microsoft VS Code/Code.exe" tools/ghi-cham.js ket-qua.json [--thu] [--soat-miss]
// ket-qua.json = [{id, verdict, severity?, issue?, suggestion?, source_faq?}, ...]
// Mặc định: chỉ ghi vào dòng đang `chua_cham` — KHÔNG bao giờ ghi đè dòng đã chấm.
// --soat-miss: soát dòng miss (khong_tra_loi / chi_bot) mà job tự gắn. Chỉ nhận 2 kết luận:
//   'khong_lien_quan' = tin tương tác / không hỏi mua → bỏ qua;  'giu' = miss thật, giữ nguyên, đánh dấu đã soát.
//   Dòng đã soát có cham_boi ≠ null → lần sau không soát lại.
// --thu: kiểm file, không ghi.
// Monsieur Claude
const fs = require('fs');
const K = require('./keys.js');
const soatMiss = process.argv.includes('--soat-miss');
const VERDICTS = soatMiss ? ['khong_lien_quan', 'giu']
  : ['dung', 'thieu', 'sai', 'khong_lien_quan', 'khong_tra_loi', 'chi_bot', 'tra_loi_inbox'];
const SEV = ['cao', 'trung', 'thap'];
const file = process.argv[2], thu = process.argv.includes('--thu');
if (!file) { console.error('Thiếu file kết quả'); process.exit(1); }
const rows = JSON.parse(fs.readFileSync(file, 'utf8'));
const loi = [];
for (const r of rows) {
  if (!Number.isInteger(r.id)) loi.push(`id không hợp lệ: ${JSON.stringify(r.id)}`);
  if (!VERDICTS.includes(r.verdict)) loi.push(`#${r.id}: verdict "${r.verdict}" không hợp lệ${soatMiss ? ' (--soat-miss chỉ nhận khong_lien_quan | giu)' : ''}`);
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
const v = `with v as (select * from jsonb_to_recordset($${tag}$${data}$${tag}$::jsonb)
  as x(id bigint, verdict text, severity text, issue text, suggestion text, source_faq text))`;
const sql = soatMiss
  ? `${v} update sale_response_review s set
       verdict = case when v.verdict='khong_lien_quan' then 'khong_lien_quan' else s.verdict end,
       severity = case when v.verdict='khong_lien_quan' then null else s.severity end,
       issue = case when v.verdict='khong_lien_quan' then coalesce(v.issue, 'Tin tương tác, không phải khách hỏi mua') else s.issue end,
       suggestion = case when v.verdict='khong_lien_quan' then null else s.suggestion end,
       cham_boi='sonnet', reviewed_at=now()
     from v where s.id=v.id and s.verdict in ('khong_tra_loi','chi_bot') and s.cham_boi is null returning s.id`
  // Nhãn do soat-miss-pancake.js gắn (trả lời muộn / qua tin nhắn) luôn được GIỮ ở đầu issue — 28/9 Sonnet ghi đè mất 21 dòng
  : `${v} update sale_response_review s set verdict=v.verdict, severity=v.severity,
       issue = case when s.issue ~ '^(Trả lời muộn|Bình luận → tư vấn qua tin nhắn)'
                     and coalesce(v.issue,'') !~ '^(Trả lời muộn|Bình luận → tư vấn qua tin nhắn)'
                    then substring(s.issue from '^(Trả lời muộn [0-9,]+ (?:giờ|phút)(?: \\([^)]*\\))?\\.?|Bình luận → tư vấn qua tin nhắn[^.]*\\.)') || coalesce(' ' || v.issue, '')
                    else v.issue end,
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
  console.log(`Đã ghi ${ghi.size} dòng.` + (bo.length ? ` Bỏ qua ${bo.length} dòng (không còn ở trạng thái được phép ghi): ${bo.join(', ')}` : ''));
})();
