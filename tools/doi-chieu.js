// ĐỐI CHIẾU job cũ (sale_response_review, do mkt-sale-app ghi) với job mới (qc_review_thu) cho 1 ngày giờ VN.
// Dùng: .../Code.exe tools/doi-chieu.js 2026-09-28
// So theo từng page: số hội thoại, số lượt hỏi–đáp, số lượt khớp (conv_id + 160 ký tự đầu câu hỏi),
// rồi in mẫu lượt chỉ có ở 1 bên để giải thích lệch. Bỏ nhóm Zalo pzl_g_ ở cả 2 bên. Chỉ đọc.
// Monsieur Claude
const K = require('./keys.js');
const D = (process.argv[2] || '').replace(/[^0-9-]/g, '');
if (!D) { console.error('Thiếu ngày YYYY-MM-DD'); process.exit(1); }
async function sql(q) {
  const r = await fetch(`https://api.supabase.com/v1/projects/${K.ref}/database/query`, {
    method: 'POST', headers: { Authorization: 'Bearer ' + K.sbp, 'Content-Type': 'application/json' }, body: JSON.stringify({ query: q }) });
  const j = await r.json().catch(() => null);
  if (!r.ok) throw new Error(r.status + ' ' + JSON.stringify(j));
  return j;
}
(async () => {
  const q = `
    with cu as (select coalesce(page_id, substring(pancake_url from 'pancake\\.vn/([^?]+)\\?')) pid, page_name, conv_id, left(customer_ask,160) k, verdict
                from sale_response_review
                where (conv_at at time zone 'Asia/Ho_Chi_Minh')::date = '${D}' and conv_id not like 'pzl\\_g\\_%'),
         moi as (select page_id pid, page_name, conv_id, left(customer_ask,160) k, verdict
                from qc_review_thu where conv_date = '${D}'),
         ten as (select pid, max(page_name) ten from (select pid, page_name from cu union all select pid, page_name from moi) x group by pid)
    select t.ten page,
      (select count(distinct conv_id) from cu where cu.pid=t.pid) hoi_thoai_cu,
      (select count(distinct conv_id) from moi where moi.pid=t.pid) hoi_thoai_moi,
      (select count(*) from cu where cu.pid=t.pid) luot_cu,
      (select count(*) from moi where moi.pid=t.pid) luot_moi,
      (select count(*) from cu join moi using (conv_id, k) where cu.pid=t.pid) khop
    from ten t order by 4 desc`;
  const rows = await sql(q);
  console.log(`ĐỐI CHIẾU ngày ${D} (giờ VN)`);
  console.table(rows);
  const tong = k => rows.reduce((s, r) => s + Number(r[k]), 0);
  console.log(`Tổng: cũ ${tong('luot_cu')} lượt / mới ${tong('luot_moi')} lượt / khớp ${tong('khop')}`);
  const lech = await sql(`
    with cu as (select page_name, conv_id, left(customer_ask,160) k, customer_ask, verdict, conv_at from sale_response_review
                where (conv_at at time zone 'Asia/Ho_Chi_Minh')::date = '${D}' and conv_id not like 'pzl\\_g\\_%'),
         moi as (select page_name, conv_id, left(customer_ask,160) k, customer_ask, verdict, conv_at from qc_review_thu where conv_date = '${D}')
    (select 'chỉ job CŨ' ben, page_name, left(customer_ask,70) hoi, verdict from cu where not exists (select 1 from moi where moi.conv_id=cu.conv_id and moi.k=cu.k) limit 15)
    union all
    (select 'chỉ job MỚI', page_name, left(customer_ask,70), verdict from moi where not exists (select 1 from cu where cu.conv_id=moi.conv_id and cu.k=moi.k) limit 15)`);
  if (lech.length) { console.log('Mẫu lượt lệch:'); console.table(lech); }
})().catch(e => { console.error('LỖI', e.message); process.exit(1); });
