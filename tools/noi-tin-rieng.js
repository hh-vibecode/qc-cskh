// NỐI TIN SALE NHẮN RIÊNG VÀO DÒNG BÌNH LUẬN — chạy bù 1 lần cho tháng 10 (job kéo tự làm từ 13/10).
// Vì sao (báo sai #52 Bông Ô Mai, 13/10/2026): khách hỏi giá dưới bình luận, Sale nhắn riêng bảng giá qua tin nhắn nhưng khách
// chưa nhắn lại → hội thoại inbox không có lượt khách nên job kéo bỏ qua → dòng bình luận chỉ thấy phần bình luận, bị chấm Thiếu.
// Với mỗi dòng BÌNH LUẬN thật (không phải khấn / lọc) từ 1/10:
//  1. Mở hội thoại bình luận trên Pancake → lấy mã khách → ghi cột khach_id (để job kéo nối về sau).
//  2. Tìm inbox của CHÍNH khách đó (khớp mã khách / fb_id). Inbox CHỈ có Sale nhắn sau giờ bình luận (khách chưa nhắn) →
//     nối các dòng inbox vào full_thread (ghepThread, không ghi đè) → về chờ chấm lại cả đoạn (dòng đã chốt tay: chỉ nối thread).
//     Inbox có khách nhắn → hội thoại đó có dòng chấm riêng, không đụng.
// Chỉ ĐỌC Pancake, nhịp ≥ 200 ms, tự dừng nếu rơi vào phút 0–10.
// Dùng: ELECTRON_RUN_AS_NODE=1 "D:/Microsoft VS Code/Code.exe" C:/Users/HP/Desktop/qc-cskh/tools/noi-tin-rieng.js [--thu]
// Monsieur Claude (13/10/2026)
const K = require('./keys.js');
const thu = process.argv.includes('--thu');
const P = 'https://pancake.vn/api/v1', REST = `${K.url}/rest/v1`, sleep = ms => new Promise(r => setTimeout(r, ms));
const H = { apikey: K.qc, Authorization: 'Bearer ' + K.qc, 'Content-Type': 'application/json' };
async function pk(path) {
  if (new Date(Date.now() + 7 * 36e5).getUTCMinutes() <= 10) throw new Error('phút 0–10 — dừng để không tranh Pancake với app MKT/Sale');
  for (let i = 0; i < 3; i++) {
    const r = await fetch(`${P}${path}${path.includes('?') ? '&' : '?'}access_token=${K.pancake}`).catch(() => null);
    await sleep(200);
    if (r?.ok) return r.json();
    if (r?.status === 429) await sleep(2000 * (i + 1)); else return null;
  }
  return null;
}
const clean = t => (t || '').replace(/<br[^>]*\/?>/g, ' ').replace(/<[^>]+>/g, '').replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/\s+/g, ' ').trim();
const bo = s => (s || '').normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/đ/g, 'd').toLowerCase();
const TU_DONG = /da tra loi (mot|ve mot) (quang cao|bai viet)|replied to a (post|comment)|ban dang phan hoi binh luan|vui long nhan tin cho ben em|vui long doi (giay lat|mot chut)|ket noi (voi )?nhan vien|kinh chao anh\/chi|tran trong xin chao|han hanh duoc ket noi|xin phep ket noi lai|tin nhan chao mung tu dong|vui long duoc tiep don|ban co 7 ngay|followed your page|just followed/;
const utc = s => new Date(/[zZ]|[+-]\d\d:?\d\d$/.test(s) ? s : s + 'Z');
const gio = d => new Date(d.getTime() + 7 * 36e5).toISOString().slice(0, 16).replace('T', ' ');   // giờ VIỆT NAM như gioThread
const tenSach = s => (s || '').replace(/[^\p{L}\p{N}\s.'-]/gu, ' ').replace(/\s+/g, ' ').trim();
function dong(m, pageId) {
  const sale = String(m.from?.id) === String(pageId), t = clean(m.message);
  const auto = sale && (bo(m.from?.admin_name) === 'botcake' || TU_DONG.test(bo(t)));
  const stk = (m.attachments || []).length && m.attachments.every(a => /sticker/i.test(a.type || ''));
  const who = !sale ? 'Khách' : auto ? 'Bot' : m.from?.admin_name ? `Sale (${m.from.admin_name})` : 'Sale';
  return { who, auto, sale, at: utc(m.inserted_at), line: `[${gio(utc(m.inserted_at))}] ${who}: ${t || (stk ? '(sticker)' : '(gửi ảnh/tệp)')}` };
}
function ghepThread(a, b) {   // giống scripts/keo-tin.js
  const l = [...new Set([...(a || '').split('\n'), ...(b || '').split('\n')].filter(Boolean))];
  return l.sort((x, y) => x.slice(0, 18).localeCompare(y.slice(0, 18))).join('\n').slice(-6000);
}
(async () => {
  const rows = await (await fetch(`${REST}/sale_response_review?select=id,page_id,conv_id,conv_at,customer_name,verdict,cham_boi,full_thread,sale_reply,sale_name,khach_id`
    + `&conv_date=gte.2026-10-01&verdict=neq.khong_lien_quan&conv_id=not.like.pzl_*&order=conv_at`, { headers: H })).json();
  const bl = rows.filter(r => r.page_id && !String(r.conv_id).startsWith(r.page_id + '_'));
  console.log(`Dòng bình luận thật từ 1/10: ${bl.length}`);
  const dem = { khach_id: 0, noi: 0, inbox_co_khach: 0, khong_inbox: 0, khong_mo: 0 };
  for (const r of bl) {
    const c = await pk(`/pages/${r.page_id}/conversations/${encodeURIComponent(r.conv_id)}`);
    const conv = c?.conversation || c, cust = conv?.customers?.[0];
    if (!cust?.id) { dem.khong_mo++; continue; }
    const body = {};
    if (!r.khach_id) { body.khach_id = String(cust.id); dem.khach_id++; }
    let ib = null;
    for (const q of [...new Set([cust.username, tenSach(r.customer_name), tenSach(cust.name)].filter(x => x && x.length >= 2))]) {
      const s = await pk(`/pages/${r.page_id}/conversations/search?q=${encodeURIComponent(q)}`);
      ib = (s?.conversations || []).find(x => (x.type || '').toUpperCase() === 'INBOX' &&
        (x.customers || []).some(y => String(y.id) === String(cust.id) || (cust.fb_id && String(y.fb_id) === String(cust.fb_id))));
      if (ib) break;
    }
    if (!ib) dem.khong_inbox++;
    else {
      const m = await pk(`/pages/${r.page_id}/conversations/${encodeURIComponent(ib.id)}/messages?customer_id=${ib.customers[0].id}`);
      const ds = (m?.messages || []).map(x => dong(x, r.page_id)).filter(x => !/: $/.test(x.line)).sort((a, b) => a.at - b.at);
      const moc = new Date(r.conv_at), sau = ds.filter(x => x.at > moc);
      if (sau.some(x => !x.sale)) dem.inbox_co_khach++;   // khách đã nhắn ở inbox → có dòng chấm riêng
      else if (sau.some(x => x.sale && !x.auto)) {
        const vo = ghepThread(r.full_thread, sau.map(x => x.line).join('\n'));
        if (vo !== (r.full_thread || '')) {
          body.full_thread = vo; dem.noi++;
          if (r.cham_boi !== 'claude') Object.assign(body, { verdict: 'chua_cham', cham_boi: null, severity: null, suggestion: null, sai_quy_trinh: null,
            sale_reply: r.sale_reply || sau.filter(x => x.sale && !x.auto).map(x => x.line.replace(/^\[[^\]]+\] [^:]+: /, '')).join(' | ').slice(0, 1000),
            sale_name: r.sale_name || (sau.find(x => x.sale && !x.auto).who.match(/\((.+)\)/) || [])[1] || null, issue: 'Bình luận → tư vấn qua tin nhắn riêng.' });
          console.log(`  nối #${r.id} ${r.customer_name} (${r.verdict} → ${body.verdict || 'giữ'}): +${sau.length} dòng inbox`);
        }
      }
    }
    if (Object.keys(body).length && !thu)
      await fetch(`${REST}/sale_response_review?id=eq.${r.id}`, { method: 'PATCH', headers: { ...H, Prefer: 'return=minimal' }, body: JSON.stringify(body) });
  }
  console.log(thu ? '(chạy thử — chưa ghi)' : 'đã ghi', dem);
})().catch(e => { console.error('LỖI', e.message); process.exit(1); });
