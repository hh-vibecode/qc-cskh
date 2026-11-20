// ĐÁNH GIÁ KHÁCH TIỀM NĂNG — công cụ cho phiên máy / agent (chạy bù nhiều ngày). Lịch cloud dùng RPC qc_lo_tiem_nang / qc_ghi_tiem_nang.
// Luật xếp loại: routine/cham-cloud.md mục "ĐÁNH GIÁ KHÁCH TIỀM NĂNG". Dùng Management API (khoá trong qc-keys.local.txt), không in khoá.
//   …/Code.exe tools/tiem-nang.js lo <YYYY-MM-DD> <file_ra.json> [so=40]
//        → ghi lô cần đánh giá của ngày đó ra file: [{id, page_name, customer_name, sale_name, la_binh_luan, thread}]
//          thread ĐÃ CẮT tới hết ngày đó (ngày đã qua: không nhìn tin các ngày sau), lấy 6000 ký tự cuối. In "lô N".
//   …/Code.exe tools/tiem-nang.js ghi <YYYY-MM-DD> <file_kq.json>
//        → file [{id, ket: tiem_nang|da_chot|tu_choi|chua_du, ly_do}] → ghi qc_khach_tiem_nang (ghi đè cùng ngày + id).
// Lọc trước như RPC: đã qua bộ lọc QC, khách có nhắn trong ngày, có tin Sale chứa con số giá, chưa đánh giá ngày đó; bình luận có tin nhắn riêng cùng khách thì bỏ (chống trùng 20/11). Monsieur Claude (20/11/2026)
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
  const [lenh, ngay, file, so] = process.argv.slice(2);
  if (!/^\d{4}-\d\d-\d\d$/.test(ngay || '')) throw new Error('Thiếu ngày YYYY-MM-DD');
  if (lenh === 'lo') {
    const rows = await sql(`select s.id, s.page_name, s.customer_name, s.sale_name,
        not qc_la_inbox(s.conv_id, s.page_id) la_binh_luan, s.full_thread
      from sale_response_review s
      where s.verdict <> 'khong_lien_quan' and not coalesce(s.noi_bo, false) and s.conv_id not like 'pzl\\_g\\_%'
        and s.conv_date >= ${lit(ngay)}::date - 1
        and s.full_thread ~ ('\\[' || ${lit(ngay)} || ' \\d\\d:\\d\\d\\] Khách:')
        and qc_co_bao_gia(s.full_thread)
        and not (s.khach_id is not null and not qc_la_inbox(s.conv_id, s.page_id)
          and exists (select 1 from sale_response_review i where i.page_id = s.page_id and i.khach_id = s.khach_id and i.id <> s.id
            and qc_la_inbox(i.conv_id, i.page_id) and i.verdict <> 'khong_lien_quan' and i.conv_date >= ${lit(ngay)}::date - 1
            and i.full_thread ~ ('\\[' || ${lit(ngay)} || ' \\d\\d:\\d\\d\\] Khách:') and qc_co_bao_gia(i.full_thread)))
        and not exists (select 1 from qc_khach_tiem_nang k where k.ngay = ${lit(ngay)}::date and k.review_id = s.id)
      order by s.id limit ${Math.min(Number(so) || 40, 60)}`);
    const het = ngay + ' 23:59';
    const lo = rows.map(r => ({ id: r.id, page_name: r.page_name, customer_name: r.customer_name, sale_name: r.sale_name, la_binh_luan: r.la_binh_luan,
      thread: (r.full_thread || '').split('\n').filter(l => { const m = l.match(/^\[(\d{4}-\d\d-\d\d \d\d:\d\d)\]/); return !m || m[1] <= het; }).join('\n').slice(-6000) }));
    fs.writeFileSync(file, JSON.stringify(lo, null, 1));
    console.log(`lô ${lo.length}`);
  } else if (lenh === 'ghi') {
    const kq = JSON.parse(fs.readFileSync(file, 'utf8'));
    const sai = kq.filter(x => !['tiem_nang', 'da_chot', 'tu_choi', 'chua_du'].includes(x.ket) || !String(x.ly_do || '').trim() || !Number.isInteger(+x.id));
    if (sai.length) throw new Error('Dòng sai định dạng: ' + sai.map(x => x.id).join(','));
    if (!kq.length) { console.log('ghi 0'); return; }
    const values = kq.map(x => `(${lit(ngay)}::date, ${+x.id}, ${lit(x.ket)}, ${lit(String(x.ly_do).trim().slice(0, 500))}, now())`).join(',\n');
    await sql(`insert into qc_khach_tiem_nang (ngay, review_id, ket, ly_do, danh_gia_luc) values ${values}
      on conflict (ngay, review_id) do update set ket = excluded.ket, ly_do = excluded.ly_do, danh_gia_luc = now()`);
    // chống trùng (20/11): bình luận + tin nhắn riêng cùng khách → 1 dòng
    const [g] = await sql(`select qc_gop_tiem_nang_trung(${lit(ngay)}::date) n`);
    console.log(`ghi ${kq.length}` + (g && g.n ? ` · gộp trùng ${g.n}` : ""));
  } else throw new Error('Lệnh: lo | ghi');
})().catch(e => { console.error('LỖI', e.message); process.exit(1); });
