// SOÁT LẠI DÒNG MISS BẰNG PANCAKE THẬT (không tốn token AI).
// Vì sao (28/9/2026, ca Lê Huyền #2443): job cũ chụp hội thoại 1 lần theo ngày → Sale trả lời SAU lúc job chạy
// (muộn 1–2 ngày) vẫn bị ghi "Không trả lời" mãi mãi. Bình luận được trả lời ở INBOX ngày khác cũng vậy.
//
// Với mỗi dòng khong_tra_loi / chi_bot:
//  - Mở lại hội thoại gốc. Có tin Sale THẬT (không bot, không tin tự động) sau câu hỏi → hết miss:
//      verdict='chua_cham' (để tầng luật / Sonnet chấm nội dung), sale_reply = câu trả lời, issue ghi "Trả lời muộn N giờ".
//  - Hội thoại là BÌNH LUẬN, không ai trả lời tại chỗ → tìm INBOX của chính khách đó (search theo tên, khớp fb_id),
//      luật đã chốt: có Sale thật trong inbox sau giờ bình luận VÀ tin nội dung mới nhất của khách trong inbox
//      (sau bình luận) có Sale trả lời sau nó → 'tra_loi_inbox'.
//  - Không thấy → giữ nguyên (miss thật).
// Dùng:
//   .../Code.exe tools/soat-miss-pancake.js --thu [--id 2443]   xem trước
//   .../Code.exe tools/soat-miss-pancake.js [--tu 2026-09-15]   ghi thật
// Monsieur Claude
const K = require('./keys.js');
const A = process.argv, thu = A.includes('--thu');
const argOf = k => { const i = A.indexOf(k); return i > 0 ? A[i + 1] : null; };
const ONE = argOf('--id'), TU = argOf('--tu');
const P = 'https://pancake.vn/api/v1';
const sleep = ms => new Promise(r => setTimeout(r, ms));
async function pk(path) {
  for (let i = 0; i < 3; i++) {
    try {
      const r = await fetch(`${P}${path}${path.includes('?') ? '&' : '?'}access_token=${K.pancake}`);
      if (r.ok) return await r.json();
      if (r.status === 429) { await sleep(2000 * (i + 1)); continue; }
      return null;
    } catch (e) { await sleep(1000); }
  }
  return null;
}
async function sql(q) {
  const r = await fetch(`https://api.supabase.com/v1/projects/${K.ref}/database/query`, {
    method: 'POST', headers: { Authorization: 'Bearer ' + K.sbp, 'Content-Type': 'application/json' }, body: JSON.stringify({ query: q }) });
  const j = await r.json().catch(() => null);
  if (!r.ok) throw new Error(r.status + ' ' + JSON.stringify(j));
  return j;
}
const clean = t => (t || '').replace(/<br[^>]*\/?>/g, ' ').replace(/<[^>]+>/g, '').replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&')
  .replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&#39;/g, "'").replace(/&quot;/g, '"').replace(/\s+/g, ' ').trim();
const bo = s => (s || '').normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/đ/g, 'd').replace(/Đ/g, 'd').toLowerCase();
// Tin tự động / hệ thống — KHÔNG tính là Sale trả lời (gộp của extract-sale-pairs.py + các mẫu thấy thêm 28/9)
const TU_DONG = /da tra loi (mot|ve mot) (quang cao|bai viet)|replied to a (post|comment)|ban dang phan hoi binh luan|vui long nhan tin cho ben em|vui long doi (giay lat|mot chut)|ket noi (voi )?nhan vien|kinh chao anh\/chi|tran trong xin chao|han hanh duoc ket noi|xin phep ket noi lai|tin nhan chao mung tu dong|vui long duoc tiep don|ban co 7 ngay|followed your page|just followed/;
// Tin tự động gửi hàng loạt / chào theo quảng cáo: không tên người gửi + mở đầu "Xin chào <tên khách>," (thấy 28/9: #335 gửi sau 62 giờ)
const CHAO_TU_DONG = /^xin chao [^,.!?]{1,40},/;
const BOT = new Set(['botcake']);
const KHONG_CAN_TRA_LOI = /^(ok|oke|okie|vang|da|u|uh|um|cam on|cam on (a|ah|nhe|shop|em|ban)|thanks?|tks|👍|❤️|🙏)[\s.!]*$/;
const utc = s => new Date(/[zZ]|[+-]\d\d:?\d\d$/.test(s) ? s : s + 'Z');

function tinSale(m, pageId) {
  if (String(m.from?.id) !== String(pageId)) return false;
  if (BOT.has(bo(m.from?.admin_name || ''))) return false;
  const t = clean(m.message || m.original_message || '');
  const att = (m.attachments || []).some(a => /photo|image|video|file/.test(a.type || ''));
  if (!t && !att) return false;
  if (t && TU_DONG.test(bo(t))) return false;
  if (t && !m.from?.admin_name && CHAO_TU_DONG.test(bo(t))) return false;
  return true;
}
async function tinNhan(pageId, convId) {
  const c = await pk(`/pages/${pageId}/conversations/${convId}`);
  const conv = c?.conversation || c;
  const cust = conv?.customers?.[0];
  if (!cust?.id) return null;
  const m = await pk(`/pages/${pageId}/conversations/${convId}/messages?customer_id=${cust.id}`);
  const msgs = (m?.messages || []).slice().sort((a, b) => utc(a.inserted_at) - utc(b.inserted_at));
  return { conv, cust, msgs };
}
const fmt = (m, pageId) => {
  const d = new Date(utc(m.inserted_at).getTime());
  const ts = d.toISOString().slice(0, 16).replace('T', ' ');
  const sale = String(m.from?.id) === String(pageId);
  const who = !sale ? 'Khách' : BOT.has(bo(m.from?.admin_name || '')) || TU_DONG.test(bo(clean(m.message))) ? 'Bot'
    : (m.from?.admin_name ? `Sale (${m.from.admin_name})` : 'Sale');
  return `[${ts}] ${who}: ${clean(m.message) || '(gửi ảnh/tệp)'}`;
};

async function soat(r) {
  const u = (r.pancake_url || '').match(/pancake\.vn\/([^?]+)\?c_id=(.+)$/);
  const pageId = u ? u[1] : r.conv_id.split('_')[0], convId = u ? u[2] : r.conv_id;
  const hoi = utc(r.conv_at);
  const g = await tinNhan(pageId, convId);
  if (!g) return { ket: 'khong_mo_duoc' };
  // 1) Có Sale thật trả lời sau câu hỏi ngay trong hội thoại gốc?
  const rep = g.msgs.find(m => utc(m.inserted_at) > hoi && tinSale(m, pageId));
  if (rep) {
    const h = (utc(rep.inserted_at) - hoi) / 36e5;
    const moi = g.msgs.filter(m => utc(m.inserted_at) >= hoi).map(m => fmt(m, pageId));
    return { ket: 'da_tra_loi', muon: h, sale: rep.from?.admin_name || null, text: clean(rep.message) || '(gửi ảnh/tệp)', them: moi };
  }
  // 2) Bình luận → tìm inbox của chính khách đó
  if ((g.conv?.type || '').toUpperCase() === 'COMMENT') {
    const fb = g.cust.fb_id || g.cust.id;
    const s = await pk(`/pages/${pageId}/conversations/search?q=${encodeURIComponent(r.customer_name || g.cust.name || '')}`);
    const ib = (s?.conversations || []).find(c => (c.type || '').toUpperCase() === 'INBOX' &&
      (c.customers || []).some(x => String(x.fb_id) === String(fb) || String(x.id) === String(g.cust.id)));
    if (ib) {
      const gi = await tinNhan(pageId, ib.id);
      const sau = (gi?.msgs || []).filter(m => utc(m.inserted_at) > hoi);
      const coSale = sau.some(m => tinSale(m, pageId));
      const khach = sau.filter(m => String(m.from?.id) !== String(pageId) && clean(m.message) && !KHONG_CAN_TRA_LOI.test(bo(clean(m.message))));
      const cuoi = khach[khach.length - 1];
      const cuoiDuocTL = !cuoi || sau.some(m => utc(m.inserted_at) > utc(cuoi.inserted_at) && tinSale(m, pageId));
      if (coSale && cuoiDuocTL) return { ket: 'tra_loi_inbox', inbox: ib.id, url: `https://pancake.vn/${pageId}?c_id=${ib.id}`,
        them: sau.map(m => fmt(m, pageId)) };
    }
  }
  return { ket: 'miss_that' };
}

(async () => {
  const dk = ONE ? `id=${Number(ONE)}` : `verdict in ('khong_tra_loi','chi_bot') and conv_id not like 'pzl\\_g\\_%'
    and conv_at is not null and pancake_url is not null ${TU ? `and conv_date >= '${TU.replace(/[^0-9-]/g, '')}'` : ''}`;
  const rows = await sql(`select id, conv_id, conv_at, conv_date, customer_name, pancake_url, verdict, full_thread from sale_response_review where ${dk} order by conv_at`);
  const dem = {}, ghi = [];
  for (const r of rows) {
    let k; try { k = await soat(r); } catch (e) { k = { ket: 'loi', e: e.message }; }
    dem[k.ket] = (dem[k.ket] || 0) + 1;
    if (k.ket === 'da_tra_loi') console.log(`#${r.id} ${r.customer_name}: Sale ${k.sale || '(không tên)'} trả lời muộn ${k.muon.toFixed(1)} giờ — "${k.text.slice(0, 70)}"`);
    if (k.ket === 'tra_loi_inbox') console.log(`#${r.id} ${r.customer_name}: bình luận → đã tư vấn ở inbox ${k.inbox}`);
    if (k.ket === 'da_tra_loi' || k.ket === 'tra_loi_inbox') ghi.push({ r, k });
    await sleep(150);
  }
  console.log(`Soát ${rows.length} dòng miss:`, dem);
  if (thu || !ghi.length) return;
  const tag = 'sm' + Date.now(), q = s => `$${tag}$${s}$${tag}$`;
  for (const { r, k } of ghi) {
    const thread = ((r.full_thread || '') + '\n' + k.them.join('\n')).slice(-4000);
    if (k.ket === 'da_tra_loi') {
      await sql(`update sale_response_review set verdict='chua_cham', sale_reply=${q(k.text.slice(0, 1000))},
        sale_name=coalesce(${k.sale ? q(k.sale) : 'null'}, sale_name), severity=null, suggestion=null, source_faq=null, cham_boi=null,
        issue=${q(`Trả lời muộn ${k.muon < 1 ? Math.round(k.muon * 60) + ' phút' : k.muon.toFixed(1).replace('.', ',') + ' giờ'} (soát lại Pancake — lúc job chạy chưa có trả lời)`)},
        full_thread=${q(thread)}, reviewed_at=now()
        where id=${r.id} and verdict in ('khong_tra_loi','chi_bot')`);
    } else {
      await sql(`update sale_response_review set verdict='tra_loi_inbox', severity=null, suggestion=null, cham_boi='luat',
        issue='Bình luận → Sale đã tư vấn ở tin nhắn (soát lại Pancake, xuyên ngày) — không tính lỗi.',
        pancake_url=${q(k.url)}, full_thread=${q(thread)}, reviewed_at=now()
        where id=${r.id} and verdict in ('khong_tra_loi','chi_bot')`);
    }
  }
  console.log(`Đã ghi ${ghi.length} dòng.`);
})().catch(e => { console.error('LỖI', e.message); process.exit(1); });
