// JOB KÉO TIN CỦA APP QC (repo qc-cskh) — thay cho 3 script cũ bên mkt-sale-app
// (crawl-pancake.js → extract-sale-pairs.py → push-sale-review.py). Chạy trên GitHub Actions, do pg_cron kích 6h/18h.
//
// Sửa so với job cũ (lỗi đo được 28/9/2026):
//  1. Bỏ nhóm Zalo `pzl_g_` ngay từ lúc kéo (job cũ đẩy 132 dòng rác).
//  2. Ngày theo GIỜ VIỆT NAM (job cũ theo UTC → tin 0h–7h sáng bị xếp sang hôm trước).
//  3. Lấy mọi hội thoại có cập nhật TỪ ngày FROM trở đi (job cũ bỏ hội thoại hôm qua mà sáng nay khách nhắn tiếp),
//     quét tới khi 2 trang liền toàn hội thoại cũ hơn mốc (Pancake không sắp chặt theo thời gian).
//  4. KHÔNG tự đoán bình luận → inbox bằng tên / ghép mã (job cũ ghép sai) — bình luận chưa ai trả lời để miss,
//     rồi tools/soat-miss-pancake.js tìm inbox của chính khách đó (xuyên ngày) và chấm cả đoạn tin nhắn.
//  5. Tin tự động (lời chào khi bấm quảng cáo, "tin nhắn chào mừng tự động", "followed your page") không tính là Sale.
//  6. Ghi bằng khoá Supabase RIÊNG của QC (qc_cskh) qua REST, gộp lô — không đi cổng quản trị (hết lỗi 429).
//  7. Chống trùng theo (conv_id, 160 ký tự đầu câu hỏi) — không theo ngày, để không đẻ trùng với dòng job cũ đã ghi.
//  8. Chỉ kéo tin của hội thoại có KHÁCH nhắn từ FROM (last_customer_interactive_at): job MKT/Sale gắn thẻ / tạo đơn
//     cũng làm đổi updated_at (đo 29/9: 1.439 hội thoại Chánh Tâm "cập nhật" trong 1 ngày) — kéo hết sẽ đè token Pancake chung.
//
// DÙNG CHUNG VỚI APP MKT/SALE (lưu ý của phiên đó, 29/9): chỉ ĐỌC Pancake; nhịp gọi ≥150 ms, 429 thì nghỉ rồi thử lại;
// tránh 6h/18h (tạo đơn), 7h & 18h (phân loại SP), phút 0–10 mỗi giờ; ghi theo lô, return=minimal.
// Đang chạy song song với job cũ → ghi bảng RIÊNG qc_review_thu (BANG). Chuyển hẳn thì đặt BANG=sale_response_review.
//
// Biến môi trường: FROM, TO (YYYY-MM-DD giờ VN, mặc định hôm qua) · DRY_RUN=1 (không ghi, in thống kê + ghi file)
//                  QC_SUPABASE_KEY, PANCAKE_SESSION_TOKEN (secrets của repo) · OUT (file JSON kết quả, tuỳ chọn)
// Monsieur Claude
const fs = require('fs');
const K = require('../tools/keys.js');
const TOK = K.pancake, SBK = K.qc, SB = K.url;
if (!TOK || !SBK) { console.error('Thiếu PANCAKE_SESSION_TOKEN hoặc QC_SUPABASE_KEY'); process.exit(1); }

const vnDay = (d = new Date()) => new Date(d.getTime() + 7 * 36e5).toISOString().slice(0, 10);
const homQua = vnDay(new Date(Date.now() - 864e5));
const FROM = process.env.FROM || homQua, TO = process.env.TO || homQua;
const DRY = !!process.env.DRY_RUN;
const BANG = process.env.BANG || 'qc_review_thu';
const tuUtc = new Date(FROM + 'T00:00:00+07:00'), denUtc = new Date(TO + 'T23:59:59.999+07:00');
const utc = s => new Date(/[zZ]|[+-]\d\d:?\d\d$/.test(s) ? s : s + 'Z');
const sleep = ms => new Promise(r => setTimeout(r, ms));

async function pk(path) {
  for (let i = 0; i < 4; i++) {
    try {
      const r = await fetch(`https://pancake.vn/api/v1${path}${path.includes('?') ? '&' : '?'}access_token=${TOK}`);
      if (r.ok) return await r.json();
      if (r.status === 429) { await sleep(3000 * (i + 1)); continue; }
      return null;
    } catch (e) { await sleep(1500); }
  }
  return null;
}
async function rest(method, path, body) {
  for (let i = 0; ; i++) {
    const r = await fetch(`${SB}/rest/v1/${path}`, { method, body: body ? JSON.stringify(body) : undefined,
      headers: { apikey: SBK, Authorization: 'Bearer ' + SBK, 'Content-Type': 'application/json', Prefer: 'return=minimal' } });
    if (r.status === 429 && i < 5) { await sleep(5000 * (i + 1)); continue; }
    const t = await r.text();
    if (!r.ok) throw new Error(`${method} ${path.slice(0, 60)} → ${r.status} ${t.slice(0, 300)}`);
    return t ? JSON.parse(t) : null;
  }
}

// ── làm sạch + phân loại tin (giữ đúng quy ước extract-sale-pairs.py để số liệu nối tiếp được) ──────────
const unesc = s => s.replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&#39;/g, "'").replace(/&quot;/g, '"');
function clean(t) {
  if (!t) return '';
  t = String(t).replace(/<Copy[^>]*text='([^']*)'[^>]*>[\s\S]*?<\/Copy>/g, '$1').replace(/<br[^>]*\/?>/g, ' ')
    .replace(/<a href='([^']*)'[^>]*>[\s\S]*?<\/a>/g, '$1').replace(/<[^>]+>/g, '');
  return unesc(t).replace(/\s+/g, ' ').trim();
}
const bo = s => (s || '').normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/đ/g, 'd').replace(/Đ/g, 'd').toLowerCase();
const BOT = new Set(['botcake']);
const TU_DONG = /da tra loi (mot|ve mot) (quang cao|bai viet)|replied to a (post|comment)|ban dang phan hoi binh luan|vui long nhan tin cho ben em|vui long doi (giay lat|mot chut)|ket noi (voi )?nhan vien|kinh chao anh\/chi|tran trong xin chao|han hanh duoc ket noi|xin phep ket noi lai|tin nhan chao mung tu dong|vui long duoc tiep don|ban co 7 ngay|followed your page|just followed/;
const CHAO_TU_DONG = /^xin chao [^,.!?]{1,40},/;   // lời chào tự động khi khách bấm quảng cáo (không tên người gửi)
const INTENT = /giá|bao nhiêu|bn |bnhiêu|size|kích thước|còn hàng|có bán|mua|ship|đặt|order|tư vấn|mẫu|hình|ảnh|inbox|ib\b|sỉ|đại lý|nhập|combo|khuyến mãi|km\b|bảo hành|đổi trả|chất liệu|gỗ|đồng|cách|hướng dẫn|lắp|giao hàng|phí|freeship|thanh toán|cọc|báo giá|xin|cho e|cho c|cho a|còn ko|còn không|có ko|có không|lấy cho|\?/i;

function kind(m, pageId) {
  if (String(m.from?.id) !== String(pageId)) return 'cust';
  if (BOT.has(bo(m.from?.admin_name || ''))) return 'auto';
  const t = bo(clean(m.message));
  if (TU_DONG.test(t)) return 'auto';
  if (!m.from?.admin_name && CHAO_TU_DONG.test(t)) return 'auto';
  return 'sale';
}
const coTep = m => (m.attachments || []).length > 0;
function dong(m, k) {
  const ts = utc(m.inserted_at).toISOString().slice(0, 16).replace('T', ' ');   // giữ giờ UTC như thread cũ
  const who = k === 'cust' ? 'Khách' : k === 'auto' ? 'Bot' : (m.from?.admin_name ? `Sale (${m.from.admin_name})` : 'Sale');
  return `[${ts}] ${who}: ${clean(m.message) || (coTep(m) ? '(gửi ảnh/tệp)' : '')}`;
}

function tachLuot(page, c, msgs, userMap) {
  const ms = msgs.filter(m => clean(m.message) || coTep(m)).map(m => ({ m, k: kind(m, page.id), at: utc(m.inserted_at) }))
    .sort((a, b) => a.at - b.at);
  const real = ms.filter(x => x.k !== 'auto'), turns = [];
  for (const x of real) {
    if (turns.length && turns[turns.length - 1].side === x.k) turns[turns.length - 1].ms.push(x);
    else turns.push({ side: x.k, ms: [x] });
  }
  const thread = ms.map(x => dong(x.m, x.k)).join('\n').slice(-4000);
  const out = [];
  turns.forEach((t, i) => {
    if (t.side !== 'cust') return;
    const first = t.ms[0].at, last = t.ms[t.ms.length - 1].at;
    if (first < tuUtc || first > denUtc) return;
    const ask = t.ms.map(x => clean(x.m.message)).filter(Boolean).join(' ').trim();
    if (ask.length <= 8 || !INTENT.test(ask)) return;
    const nxt = turns[i + 1];
    let reply = null, sale = null;
    if (nxt && nxt.side === 'sale') {
      reply = nxt.ms.map(x => clean(x.m.message)).filter(Boolean).join(' | ').trim() || null;
      if (!reply && nxt.ms.some(x => coTep(x.m))) reply = '(gửi ảnh/tệp)';
      sale = nxt.ms.find(x => x.m.from?.admin_name)?.m.from.admin_name || null;
    }
    const botSau = ms.some(x => x.k === 'auto' && x.at > last);
    const verdict = reply ? 'chua_cham' : botSau ? 'chi_bot' : 'khong_tra_loi';
    out.push({
      conv_date: vnDay(first), conv_at: first.toISOString(), page_name: page.name, page_id: String(page.id), conv_id: c.id,
      customer_name: c.customers?.[0]?.name || c.from?.name || '', phone: (c.recent_phone_numbers || [])[0]?.phone_number || null,
      sale_name: sale || (c.assignee_ids || []).map(id => userMap[id]).find(Boolean) || null,
      customer_ask: ask.slice(0, 700), sale_reply: reply ? reply.slice(0, 1000) : null, verdict,
      severity: null, source_faq: null, suggestion: null,
      issue: verdict === 'chi_bot' ? 'Chỉ có bot trả lời tự động, không có sale nào vào tư vấn.'
        : verdict === 'khong_tra_loi' ? 'Khách có nhu cầu thật nhưng không ai trả lời (kể cả bot).' : null,
      full_thread: thread, pancake_url: `https://pancake.vn/${page.id}?c_id=${c.id}`,
    });
  });
  return out;
}

(async () => {
  console.log(`Khoảng ngày (giờ VN): ${FROM} → ${TO}${DRY ? ' · THỬ (không ghi)' : ''}`);
  const pages = (await pk('/pages'))?.categorized?.activated || [];
  console.log('pages:', pages.length);
  const pairs = [], dem = {};
  for (const p of pages) {
    const userMap = {};
    ((await pk(`/pages/${p.id}/users`))?.users || []).forEach(u => userMap[u.id] = u.name);
    let count = 0, lastId = null, cuLien = 0, lay = [];
    for (let b = 0; b < 60 && cuLien < 2; b++) {
      const d = await pk(`/pages/${p.id}/conversations${count ? `?current_count=${count}${lastId ? `&last_conversation_id=${encodeURIComponent(lastId)}` : ''}` : ''}`);
      const cs = d?.conversations || [];
      if (!cs.length) break;
      let moi = 0;
      for (const c of cs) {
        if (utc(c.updated_at || '1970-01-01') >= tuUtc) moi++;           // mốc dừng quét: theo thứ tự danh sách (updated_at)
        if (String(c.id).startsWith('pzl_g_')) continue;                 // nhóm Zalo: bỏ
        if (utc(c.last_customer_interactive_at || c.updated_at || '1970-01-01') >= tuUtc) lay.push(c);   // chỉ hội thoại khách có nhắn
      }
      cuLien = moi ? 0 : cuLien + 1;
      count += cs.length; lastId = cs[cs.length - 1].id;
      await sleep(150);
    }
    lay = [...new Map(lay.map(c => [c.id, c])).values()];
    let n = 0;
    for (const c of lay) {
      const custId = c.customers?.[0]?.id;
      if (!custId) continue;
      // Pancake chỉ trả ~25–30 tin mới nhất mỗi lần → hội thoại dài (vd chat nội bộ Zalo) mất tin của ngày cần kéo.
      // Đọc lùi bằng current_count tới khi chạm đầu ngày FROM (tối đa 10 trang). Thấy 29/9 ở 3 lượt Shidai.
      const base = `/pages/${p.id}/conversations/${encodeURIComponent(c.id)}/messages?customer_id=${custId}`;
      let msgs = (await pk(base))?.messages || [];
      for (let t = 0; t < 10 && msgs.length; t++) {
        const cuNhat = Math.min(...msgs.map(x => utc(x.inserted_at).getTime()));
        if (cuNhat < tuUtc.getTime() || (c.message_count && msgs.length >= c.message_count)) break;
        await sleep(150);
        const them = (await pk(`${base}&current_count=${msgs.length}`))?.messages || [];
        const co = new Set(msgs.map(x => x.id)), moi = them.filter(x => !co.has(x.id));
        if (!moi.length) break;
        msgs = msgs.concat(moi);
      }
      const got = tachLuot(p, c, msgs, userMap);
      pairs.push(...got); n += got.length;
      await sleep(150);
    }
    dem[p.name] = n;
    console.log(`${p.name}: ${lay.length} hội thoại khách nhắn từ ${FROM} (quét ${count}) → ${n} lượt`);
  }
  const theoV = {}; pairs.forEach(x => theoV[x.verdict] = (theoV[x.verdict] || 0) + 1);
  console.log(`Tổng ${pairs.length} lượt:`, theoV);
  if (process.env.OUT) fs.writeFileSync(process.env.OUT, JSON.stringify(pairs, null, 1));
  if (DRY || !pairs.length) return;

  // chống trùng theo (conv_id, 160 ký tự đầu câu hỏi) — đọc các dòng đã có của những hội thoại này
  const convs = [...new Set(pairs.map(x => x.conv_id))], co = new Set();
  for (let i = 0; i < convs.length; i += 80) {
    const ds = convs.slice(i, i + 80).map(x => `"${x.replace(/"/g, '\\"')}"`).join(',');
    const rows = await rest('GET', `${BANG}?select=conv_id,customer_ask&conv_id=in.(${encodeURIComponent(ds)})&limit=5000`);
    rows.forEach(r => co.add(r.conv_id + '|' + (r.customer_ask || '').slice(0, 160)));
  }
  const moi = pairs.filter(x => { const k = x.conv_id + '|' + x.customer_ask.slice(0, 160); if (co.has(k)) return false; co.add(k); return true; });
  for (let i = 0; i < moi.length; i += 100) await rest('POST', BANG, moi.slice(i, i + 100));
  console.log(`[${BANG}] Đã thêm ${moi.length} lượt mới (bỏ ${pairs.length - moi.length} lượt đã có).`);
})().catch(e => { console.error('LỖI', e.message); process.exit(1); });
