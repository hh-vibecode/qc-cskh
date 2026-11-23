// ĐÁNH GIÁ KHÁCH TIỀM NĂNG — công cụ cho phiên máy / agent (chạy bù nhiều ngày). Lịch cloud dùng RPC qc_lo_tiem_nang / qc_ghi_tiem_nang.
// Luật xếp loại: routine/cham-cloud.md mục "ĐÁNH GIÁ KHÁCH TIỀM NĂNG". Dùng Management API (khoá trong qc-keys.local.txt), không in khoá.
//   …/Code.exe tools/tiem-nang.js lo <YYYY-MM-DD> <file_ra.json> [so=40]
//        → ghi lô cần đánh giá của ngày đó ra file: [{id, page_name, customer_name, sale_name, la_binh_luan, thread}]
//          thread ĐÃ CẮT tới hết ngày đó (ngày đã qua: không nhìn tin các ngày sau), lấy 6000 ký tự cuối. In "lô N".
//   …/Code.exe tools/tiem-nang.js ghi <YYYY-MM-DD> <file_kq.json>
//        → file [{id, ket: tiem_nang|da_chot|tu_choi|chua_du, ly_do}] → ghi qc_khach_tiem_nang (ghi đè cùng ngày + id).
//        23/11: page Shidai (page_si = true trong lô) thêm "loai_khach": "si" | "le" — bắt buộc; page khác tự ghi 'le'.
//   …/Code.exe tools/tiem-nang.js si-lo <file_ra.json> [phan=k/n]
//        → khách Shidai đang ở view qc_khach_tiem_nang_ngay mà lần đánh giá mới nhất chưa có loai_khach (chạy bù sỉ / lẻ 23/11).
//          Mỗi dòng: {ngay, id, customer_name, ly_do, thread (6000 ký tự cuối)}. In "lô N".
//   …/Code.exe tools/tiem-nang.js si-ghi <file_kq.json>   → file [{ngay, id, loai_khach: si|le}] → cập nhật đúng dòng đánh giá đó.
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
  if (lenh === 'si-lo') {   // ngay = file ra, file = phan k/n
    const m = /^(\d+)\/(\d+)$/.exec(file || ''), phan = m ? `and k.review_id % ${+m[2]} = ${+m[1]}` : '';
    const rows = await sql(`select k.ngay::text ngay, k.review_id id, s.customer_name, k.ly_do, right(s.full_thread, 6000) thread
      from qc_khach_tiem_nang k join sale_response_review s on s.id = k.review_id
      where qc_page_si(s.page_name) and k.loai_khach is null ${phan}
        and (k.ket in ('tiem_nang', 'tu_choi')   -- chỉ tệp tiềm năng (anh 23/11): như view — chưa đủ chỉ khi có chưa khai thác hết
             or k.ket = 'chua_du' and exists (select 1 from qc_chua_khai_thac c where c.review_id = k.review_id and c.ket))
        and not exists (select 1 from qc_khach_tiem_nang k2 where k2.review_id = k.review_id
                          and (k2.ngay > k.ngay or k2.ngay = k.ngay and k2.danh_gia_luc > k.danh_gia_luc))
      order by k.review_id`);
    fs.writeFileSync(ngay, JSON.stringify(rows, null, 1));
    console.log(`lô ${rows.length}`); return;
  }
  if (lenh === 'si-ghi') {
    const kq = JSON.parse(fs.readFileSync(ngay, 'utf8'));
    const sai = kq.filter(x => !['si', 'le'].includes(x.loai_khach) || !Number.isInteger(+x.id) || !/^\d{4}-\d\d-\d\d$/.test(x.ngay || ''));
    if (sai.length) throw new Error('Dòng sai định dạng: ' + sai.map(x => x.id).join(','));
    if (!kq.length) { console.log('ghi 0'); return; }
    const v = kq.map(x => `(${lit(x.ngay)}::date, ${+x.id}, ${lit(x.loai_khach)})`).join(',');
    const [r] = await sql(`with x(ngay, id, loai) as (values ${v}), u as (update qc_khach_tiem_nang k set loai_khach = x.loai
      from x where k.ngay = x.ngay and k.review_id = x.id returning 1) select count(*) n from u`);
    console.log(`ghi ${r.n} / ${kq.length}`); return;
  }
  if (!/^\d{4}-\d\d-\d\d$/.test(ngay || '')) throw new Error('Thiếu ngày YYYY-MM-DD');
  if (lenh === 'lo') {
    const rows = await sql(`select s.id, s.page_name, s.customer_name, s.sale_name,
        not qc_la_inbox(s.conv_id, s.page_id) la_binh_luan, qc_page_si(s.page_name) page_si, s.full_thread
      from sale_response_review s
      where s.verdict <> 'khong_lien_quan' and not coalesce(s.noi_bo, false) and s.conv_id not like 'pzl\\_%'   -- chỉ Social, bỏ Zalo (anh Hải 20/11)
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
    const lo = rows.map(r => ({ id: r.id, page_name: r.page_name, customer_name: r.customer_name, sale_name: r.sale_name, la_binh_luan: r.la_binh_luan, page_si: r.page_si,
      thread: (r.full_thread || '').split('\n').filter(l => { const m = l.match(/^\[(\d{4}-\d\d-\d\d \d\d:\d\d)\]/); return !m || m[1] <= het; })
        .reverse().reduce((a, l) => (a.n + l.length + 1 <= 6000 ? { n: a.n + l.length + 1, l: [l, ...a.l] } : { ...a, n: 1e9 }), { n: 0, l: [] }).l.join('\n') }));   // 6000 ký tự cuối, cắt theo dòng (23/11)
    fs.writeFileSync(file, JSON.stringify(lo, null, 1));
    console.log(`lô ${lo.length}`);
  } else if (lenh === 'ghi') {
    const kq = JSON.parse(fs.readFileSync(file, 'utf8'));
    const sai = kq.filter(x => !['tiem_nang', 'da_chot', 'tu_choi', 'chua_du'].includes(x.ket) || !String(x.ly_do || '').trim() || !Number.isInteger(+x.id)
      || (x.loai_khach != null && !['si', 'le'].includes(x.loai_khach)));
    if (sai.length) throw new Error('Dòng sai định dạng: ' + sai.map(x => x.id).join(','));
    if (!kq.length) { console.log('ghi 0'); return; }
    const values = kq.map(x => `(${lit(ngay)}::date, ${+x.id}, ${lit(x.ket)}, ${lit(String(x.ly_do).trim().slice(0, 500))}, now(), ${x.loai_khach ? lit(x.loai_khach) : 'null'})`).join(',\n');
    await sql(`insert into qc_khach_tiem_nang (ngay, review_id, ket, ly_do, danh_gia_luc, loai_khach) values ${values}
      on conflict (ngay, review_id) do update set ket = excluded.ket, ly_do = excluded.ly_do, loai_khach = excluded.loai_khach, danh_gia_luc = now()`);
    // 23/11: page không phải Shidai luôn là khách lẻ (Shidai mà thiếu loai_khach thì để trống — chạy si-lo / si-ghi bù)
    await sql(`update qc_khach_tiem_nang k set loai_khach = 'le' from sale_response_review s
      where s.id = k.review_id and k.ngay = ${lit(ngay)}::date and k.loai_khach is null and not qc_page_si(s.page_name)`);
    // chống trùng (20/11): bình luận + tin nhắn riêng cùng khách → 1 dòng
    const [g] = await sql(`select qc_gop_tiem_nang_trung(${lit(ngay)}::date) n`);
    console.log(`ghi ${kq.length}` + (g && g.n ? ` · gộp trùng ${g.n}` : ""));
  } else throw new Error('Lệnh: lo | ghi');
})().catch(e => { console.error('LỖI', e.message); process.exit(1); });
