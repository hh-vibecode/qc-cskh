// THƯ VIỆN SOÁT MISS VỚI PANCAKE — dùng chung cho tools/soat-miss-pancake.js (chạy tay) và scripts/keo-tin.js (job mỗi giờ).
// Anh Hải 30/9/2026: "lúc kéo thì phải xem lại các data miss, họ clear xong rồi thì clear hết mấy cái tin nhắn miss".
// soat(r) — r cần: conv_id, conv_at, pancake_url, customer_name, verdict. Trả về:
//   { ket:'da_tra_loi', muon, sale, text, them }  Sale thật trả lời sau câu hỏi ngay trong hội thoại gốc (muộn N giờ)
//   { ket:'qua_inbox',  muon, sale, text, them, url }  bình luận → Sale nhắn riêng cho CHÍNH khách đó ở inbox
//   { ket:'miss_that' | 'khong_mo_duoc' | 'inbox_khong_thay' }
// `them` = các dòng hội thoại từ lúc khách hỏi (định dạng "[YYYY-MM-DD HH:MM] Ai: nội dung", giờ UTC như thread cũ).
// Monsieur Claude
function taoSoat(pk, sleep) {
  const clean = t => (t || '').replace(/<br[^>]*\/?>/g, ' ').replace(/<[^>]+>/g, '').replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&#39;/g, "'").replace(/&quot;/g, '"').replace(/\s+/g, ' ').trim();
  const bo = s => (s || '').normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/đ/g, 'd').replace(/Đ/g, 'd').toLowerCase();
  // Tin tự động / hệ thống — KHÔNG tính là Sale trả lời
  const TU_DONG = /da tra loi (mot|ve mot) (quang cao|bai viet)|replied to a (post|comment)|ban dang phan hoi binh luan|vui long nhan tin cho ben em|vui long doi (giay lat|mot chut)|ket noi (voi )?nhan vien|kinh chao anh\/chi|tran trong xin chao|han hanh duoc ket noi|xin phep ket noi lai|tin nhan chao mung tu dong|vui long duoc tiep don|ban co 7 ngay|followed your page|just followed/;
  const CHAO_TU_DONG = /^xin chao [^,.!?]{1,40},/;   // lời chào tự động khi bấm quảng cáo (không tên người gửi)
  const BOT = new Set(['botcake']);
  const utc = s => new Date(/[zZ]|[+-]\d\d:?\d\d$/.test(s) ? s : s + 'Z');
  const tinSale = (m, pageId) => {
    if (String(m.from?.id) !== String(pageId)) return false;
    if (BOT.has(bo(m.from?.admin_name || ''))) return false;
    const t = clean(m.message || m.original_message || '');
    const att = (m.attachments || []).some(a => /photo|image|video|file/.test(a.type || ''));
    if (!t && !att) return false;
    if (t && TU_DONG.test(bo(t))) return false;
    if (t && !m.from?.admin_name && CHAO_TU_DONG.test(bo(t))) return false;
    return true;
  };
  async function tinNhan(pageId, convId) {
    const c = await pk(`/pages/${pageId}/conversations/${encodeURIComponent(convId)}`);
    const conv = c?.conversation || c;
    const cust = conv?.customers?.[0];
    if (!cust?.id) return null;
    const m = await pk(`/pages/${pageId}/conversations/${encodeURIComponent(convId)}/messages?customer_id=${cust.id}`);
    return { conv, cust, msgs: (m?.messages || []).slice().sort((a, b) => utc(a.inserted_at) - utc(b.inserted_at)) };
  }
  const fmt = (m, pageId) => {
    const ts = utc(m.inserted_at).toISOString().slice(0, 16).replace('T', ' ');
    const sale = String(m.from?.id) === String(pageId);
    const who = !sale ? 'Khách' : BOT.has(bo(m.from?.admin_name || '')) || TU_DONG.test(bo(clean(m.message))) ? 'Bot'
      : (m.from?.admin_name ? `Sale (${m.from.admin_name})` : 'Sale');
    return `[${ts}] ${who}: ${clean(m.message) || '(gửi ảnh/tệp)'}`;
  };
  // Search của Pancake KHÔNG khớp khi tên có emoji ("Harri 🪷") → thử tên đăng nhập, tên bỏ emoji, tên đầy đủ
  const tenSach = s => (s || '').replace(/[^\p{L}\p{N}\s.'-]/gu, ' ').replace(/\s+/g, ' ').trim();
  async function timInbox(pageId, g, r) {
    const qs = [...new Set([g.cust.username, g.conv?.from?.username, tenSach(r.customer_name), tenSach(g.cust.name), r.customer_name]
      .filter(x => x && x.length >= 2))];
    for (const q of qs) {
      const s = await pk(`/pages/${pageId}/conversations/search?q=${encodeURIComponent(q)}`);
      const ib = (s?.conversations || []).find(c => (c.type || '').toUpperCase() === 'INBOX' &&
        (c.customers || []).some(x => String(x.id) === String(g.cust.id) || (g.cust.fb_id && String(x.fb_id) === String(g.cust.fb_id))));
      if (ib) return ib;
      await sleep(150);
    }
    return null;
  }
  async function soat(r) {
    const u = (r.pancake_url || '').match(/pancake\.vn\/([^?]+)\?c_id=(.+)$/);
    const pageId = r.page_id || (u ? u[1] : r.conv_id.split('_')[0]);
    const hoi = utc(r.conv_at);
    const g = await tinNhan(pageId, r.conv_id);             // luôn mở hội thoại GỐC theo conv_id
    if (!g) return { ket: 'khong_mo_duoc' };
    const rep = g.msgs.find(m => utc(m.inserted_at) > hoi && tinSale(m, pageId));
    if (rep && r.verdict !== 'tra_loi_inbox') {
      return { ket: 'da_tra_loi', muon: (utc(rep.inserted_at) - hoi) / 36e5, sale: rep.from?.admin_name || null,
        text: clean(rep.message) || '(gửi ảnh/tệp)', them: g.msgs.filter(m => utc(m.inserted_at) >= hoi).slice(0, 60).map(m => fmt(m, pageId)) };
    }
    // Bình luận ↔ tin nhắn là 2 luồng riêng (anh chốt 28/9, ca Harri): tìm inbox của CHÍNH khách đó
    if ((g.conv?.type || '').toUpperCase() === 'COMMENT') {
      const ib = await timInbox(pageId, g, r);
      if (ib) {
        const gi = await tinNhan(pageId, ib.id);
        const sau = (gi?.msgs || []).filter(m => utc(m.inserted_at) > hoi);
        const sale = sau.filter(m => tinSale(m, pageId));
        if (sale.length) {
          const bl = g.msgs.filter(m => utc(m.inserted_at) >= new Date(hoi.getTime() - 6e4));
          return { ket: 'qua_inbox', url: `https://pancake.vn/${pageId}?c_id=${ib.id}`, muon: (utc(sale[0].inserted_at) - hoi) / 36e5,
            sale: sale.find(m => m.from?.admin_name)?.from.admin_name || null,
            text: sale.slice(0, 4).map(m => clean(m.message) || '(gửi ảnh/tệp)').join(' | '),
            them: [...bl, ...sau.slice(0, 40)].sort((a, b) => utc(a.inserted_at) - utc(b.inserted_at)).map(m => fmt(m, pageId)) };
        }
      }
    }
    return { ket: r.verdict === 'tra_loi_inbox' ? 'inbox_khong_thay' : 'miss_that' };
  }
  const fmtH = h => h < 1 ? Math.round(h * 60) + ' phút' : h.toFixed(1).replace('.', ',') + ' giờ';
  // Các cột cần cập nhật khi hết miss (cùng quy ước với soat-miss-pancake.js)
  const capNhat = k => k.ket === 'qua_inbox'
    ? { verdict: 'chua_cham', sale_reply: k.text.slice(0, 1000), severity: null, suggestion: null, source_faq: null, cham_boi: null,
        issue: `Bình luận → tư vấn qua tin nhắn (Sale nhắn sau ${fmtH(k.muon)}).`, pancake_url: k.url,
        full_thread: k.them.join('\n').slice(0, 6000), ...(k.sale ? { sale_name: k.sale } : {}) }
    : { verdict: 'chua_cham', sale_reply: k.text.slice(0, 1000), severity: null, suggestion: null, source_faq: null, cham_boi: null,
        issue: k.muon >= 1 ? `Trả lời muộn ${fmtH(k.muon)} (soát lại Pancake — lúc kéo tin chưa có trả lời).` : null,
        full_thread: k.them.join('\n').slice(0, 6000), ...(k.sale ? { sale_name: k.sale } : {}) };
  return { soat, fmtH, capNhat };
}
module.exports = { taoSoat };
