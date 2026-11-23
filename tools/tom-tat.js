// TÓM TẮT HỘI THOẠI — công cụ cho phiên máy / agent (chạy bù). Lịch cloud dùng RPC qc_lo_tom_tat / qc_ghi_tom_tat.
// Luật viết tóm tắt: routine/cham-cloud.md mục "TÓM TẮT HỘI THOẠI". Dùng Management API (khoá trong qc-keys.local.txt), không in khoá.
//   …/Code.exe tools/tom-tat.js lo <file_ra.json> [so=40] [phan=k/n]
//        → lô cần tóm tắt (chưa có / có tin mới) từ view qc_tom_tat_hoi_thoai, mới nhất trước; phan=k/n chỉ lấy review_id % n = k
//          (chia cho nhiều agent không trùng). Mỗi dòng: {id, page_name, customer_name, sale_name, tin_cuoi_luc, tom_tat_cu, thread}. In "lô N".
//   …/Code.exe tools/tom-tat.js ghi <file_kq.json>
//        → file [{id, tom_tat, tin_cuoi_luc}] → ghi qc_tom_tat (ghi đè theo page + hội thoại). In số đã ghi.
// Monsieur Claude (23/11/2026)
const fs = require('fs');
const K = require('./keys.js');
const sleep = ms => new Promise(r => setTimeout(r, ms));
async function sql(q) {
  for (let i = 0; ; i++) {
    const r = await fetch(`https://api.supabase.com/v1/projects/${K.ref}/database/query`, {
      method: 'POST', headers: { Authorization: 'Bearer ' + K.sbp, 'Content-Type': 'application/json' }, body: JSON.stringify({ query: q }) });
    const t = await r.text();
    if ((r.status === 429 || r.status >= 500) && i < 8) { await sleep(5000 * (i + 1)); continue; }
    if (!r.ok) throw new Error(r.status + ' ' + t.slice(0, 300));
    return t ? JSON.parse(t) : [];
  }
}
const lit = s => "'" + String(s).replace(/'/g, "''") + "'";
(async () => {
  const [lenh, file, a3, a4] = process.argv.slice(2);
  if (!file) throw new Error('Thiếu file');
  if (lenh === 'lo') {
    const so = Math.min(Math.max(parseInt(a3 || '40', 10) || 40, 1), 60);
    const m = /^(\d+)\/(\d+)$/.exec(a4 || '');
    const phan = m ? `and v.review_id % ${+m[2]} = ${+m[1]}` : '';
    const rows = await sql(`select v.review_id id, s.page_name, s.customer_name, s.sale_name, v.tin_cuoi_luc, v.tom_tat tom_tat_cu,
        right(s.full_thread, 4000) thread
      from qc_tom_tat_hoi_thoai v join sale_response_review s on s.id = v.review_id
      where (v.tom_tat is null or v.tin_cuoi_luc > v.tom_tat_den_tin) ${phan}
      order by v.tin_cuoi_luc desc limit ${so}`);
    fs.writeFileSync(file, JSON.stringify(rows, null, 1));
    console.log('lô', rows.length);
  } else if (lenh === 'ghi') {
    const rows = JSON.parse(fs.readFileSync(file, 'utf8'));
    if (!Array.isArray(rows)) throw new Error('File phải là mảng');
    const loi = [];
    for (const r of rows) {
      const t = String(r.tom_tat || '').trim();
      if (!Number.isInteger(+r.id)) loi.push(`id "${r.id}" không hợp lệ`);
      else if (!t) loi.push(`#${r.id}: thiếu tom_tat`);
      else if (t.length > 300) loi.push(`#${r.id}: tom_tat dài ${t.length} ký tự (tối đa 300)`);
      else if (!/^\d{4}-\d\d-\d\d[ T]\d\d:\d\d/.test(String(r.tin_cuoi_luc || ''))) loi.push(`#${r.id}: thiếu / sai tin_cuoi_luc`);
    }
    if (loi.length) { console.log('KHÔNG GHI —', loi.join('; ')); process.exit(1); }
    if (!rows.length) { console.log('ghi 0'); return; }
    const vals = rows.map(r => `(${+r.id}, ${lit(String(r.tom_tat).trim())}, ${lit(r.tin_cuoi_luc)}::timestamp)`).join(',');
    const kq = await sql(`with x(id, tom_tat, den) as (values ${vals}),
      ins as (insert into qc_tom_tat (page_id, conversation_id, review_id, tom_tat, den_tin_luc, cap_nhat_luc)
        select s.page_id, s.conv_id, s.id, x.tom_tat, x.den, now() from x join sale_response_review s on s.id = x.id
        on conflict (page_id, conversation_id) do update
          set review_id = excluded.review_id, tom_tat = excluded.tom_tat, den_tin_luc = excluded.den_tin_luc, cap_nhat_luc = now()
        returning 1)
      select count(*) n from ins`);
    console.log('ghi', kq[0].n, '/', rows.length);
  } else throw new Error('Lệnh: lo | ghi');
})().catch(e => { console.error(e.message); process.exit(1); });
