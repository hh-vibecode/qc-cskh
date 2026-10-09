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
const { taoSoat } = require('../tools/soat-lib.js');
const TOK = K.pancake, SBK = K.qc, SB = K.url;
if (!TOK || !SBK) { console.error('Thiếu PANCAKE_SESSION_TOKEN hoặc QC_SUPABASE_KEY'); process.exit(1); }

const vnDay = (d = new Date()) => new Date(d.getTime() + 7 * 36e5).toISOString().slice(0, 10);
const DRY = !!process.env.DRY_RUN;
const BANG = process.env.BANG || 'qc_review_thu';
// 2 chế độ (29/9/2026, anh Hải: "kéo tin và chấm cùng lúc, mỗi giờ 1 lần"):
//  - KHOẢNG: có FROM/TO (giờ VN) → kéo trọn các ngày đó (lượt 6h20 quét lại hôm qua, chạy tay, chạy bù).
//  - MỐC (mặc định, pg_cron mỗi giờ): chỉ kéo hội thoại khách nhắn TỪ lượt trước (mốc lưu ở qc_cau_hinh 'moc_keo:<bảng>'),
//    lùi 30 phút cho khỏi hở. Nhẹ cho token Pancake dùng chung với app MKT/Sale.
const CHE_DO = (process.env.FROM || process.env.TO) ? 'khoang' : 'moc';
const FROM = process.env.FROM || process.env.TO, TO = process.env.TO || process.env.FROM;
let tuUtc = CHE_DO === 'khoang' ? new Date(FROM + 'T00:00:00+07:00') : null;
let denUtc = CHE_DO === 'khoang' ? new Date(TO + 'T23:59:59.999+07:00') : new Date(Date.now() + 36e5);
const BAT_DAU = new Date();
const KHOA_MOC = 'moc_keo:' + BANG;
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
// 5/10: cắt chuỗi (slice 700/1000/6000) có thể cắt đôi 1 emoji → nửa ký tự lẻ (surrogate) làm PostgREST từ chối CẢ LÔ
// ("Empty or invalid json") — 4 lượt 10h25–13h25 fail vì 1 lời khấn đầy 🙏🌹. Làm sạch mọi chuỗi trước khi ghi.
const sachChuoi = (k, v) => typeof v === 'string'
  ? v.replace(/[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]|\u0000/g, '') : v;
async function rest(method, path, body) {
  for (let i = 0; ; i++) {
    const r = await fetch(`${SB}/rest/v1/${path}`, { method, body: body ? JSON.stringify(body, sachChuoi) : undefined,
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

// 7/10: INTENT cũ bỏ sót khách thật — câu mẫu quảng cáo "Tôi muốn được thỉnh tượng Phật", gõ không dấu "e bao gia",
// "có tượng … 55cm ko shop" (không "?"). So thêm trên chữ ĐÃ BỎ DẤU với từ ngữ ngành đồ thờ. Lời khấn lọt vào thì tầng luật /
// soát miss chuyển "không liên quan" như trước. KHÔNG thêm tên các vị (a di đà, quan âm…) — kéo theo hàng chục lời khấn "Nam mô".
const INTENT_KD = /\b(thinh|tuong|ban tho|do tho|bat huong|lu huong|den tho|bao gia|gia|bao nhieu|kich thuoc|\d+ ?cm|mau|chat lieu|muon mua|can mua|can tim|tim mua|dat hang|ship|co (ban|ko|khong)|(ko|khong) (shop|ban|a|ah|vay)\b)/;
// Câu CHẮC CHẮN không phải hỏi mua → gắn sẵn khong_lien_quan (vẫn lưu). Có chữ mua / giá / thỉnh / cm… thì KHÔNG lọc.
// 8/10: thêm "con nam mô…", "mô a di đà…", "nam.oadidaphat" (lọt khi vá tháng 10)
const KHAN_THUAN = /^(con |xin |con xin )?(nam ?mo|nammo|nam ?o ?a ?di ?da|mo a di da|a di da phat|adidaphat|nam (dia tang|quan the am|bon su|duoc su|a di da|di lac))/;
const CAU_XA_GIAO = /^((ok+|oke+|okie|okay|vang|da+|uh+|um+|ukm|cam on|camon|thanks?|thank you|tks|ty|alo|hi|hello|xin chao|chao)( (a|ah|nha|nhe|nhe|shop|em|ban|anh|chi|c|e|a|nhieu|nhiu|lam|ca nha|moi nguoi))*)+$/;
function locKhongHoi(ask) {
  const t = bo(ask).replace(/[^a-z0-9 ]+/g, ' ').replace(/\s+/g, ' ').trim();
  if (INTENT.test(ask) || INTENT_KD.test(t)) return null;
  if (!t && ask) return 'chỉ sticker / emoji';
  if (KHAN_THUAN.test(t)) return 'lời khấn';
  if (CAU_XA_GIAO.test(t)) return 'câu xã giao (ok / vâng / cảm ơn / chào)';
  return null;
}
// GIỜ TRONG THREAD = GIỜ VIỆT NAM (7/10: trước đó ghi UTC theo job cũ → trang + nhận xét chấm lệch 7 tiếng, anh Hải phát hiện).
// Mọi nơi ghi thread PHẢI dùng hàm này (soat-lib có bản giống hệt). Tự kiểm khi chạy: sai là dừng ngay, không ghi.
const gioThread = d => new Date(d.getTime() + 7 * 36e5).toISOString().slice(0, 16).replace('T', ' ');
if (gioThread(new Date('2026-10-07T00:55:00Z')) !== '2026-10-07 07:55') throw new Error('gioThread không ra giờ Việt Nam');
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
  const ts = gioThread(utc(m.inserted_at));
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
  const cuoiKhach = turns.map((t, i) => t.side === 'cust' ? i : -1).filter(i => i >= 0).pop();
  turns.forEach((t, i) => {
    if (t.side !== 'cust') return;
    const first = t.ms[0].at, last = t.ms[t.ms.length - 1].at;
    // Hội thoại chỉ có Sale nhắn trong khoảng: lấy lượt khách CUỐI (dù cũ hơn khoảng, từ 1/10) để cập nhật dòng đã có
    const choLayCu = c._chiSale && i === cuoiKhach && first >= new Date('2026-09-30T17:00:00Z');
    if ((first < tuUtc && !choLayCu) || first > denUtc) return;
    const ask = t.ms.map(x => clean(x.m.message)).filter(Boolean).join(' ').trim();
    // 7/10 anh Hải: "kéo hết về trước cho đầy đủ rồi hãy xử lý lọc" — KHÔNG bỏ lượt nào ở bước kéo. Chỉ gắn sẵn
    // "không liên quan" cho câu chắc chắn không hỏi (lời khấn thuần, cảm ơn / ok / sticker), vẫn LƯU để đủ dữ liệu.
    if (!ask && !t.ms.some(x => coTep(x.m))) return;
    const loc = locKhongHoi(ask);
    const nxt = turns[i + 1];
    let reply = null, sale = null, repAt = null;
    if (nxt && nxt.side === 'sale') {
      repAt = nxt.ms[0].at.toISOString();
      reply = nxt.ms.map(x => clean(x.m.message)).filter(Boolean).join(' | ').trim() || null;
      if (!reply && nxt.ms.some(x => coTep(x.m))) reply = '(gửi ảnh/tệp)';
      sale = nxt.ms.find(x => x.m.from?.admin_name)?.m.from.admin_name || null;
    }
    const botSau = ms.some(x => x.k === 'auto' && x.at > last);
    const verdict = loc ? 'khong_lien_quan' : reply ? 'chua_cham' : botSau ? 'chi_bot' : 'khong_tra_loi';
    out.push({
      conv_date: vnDay(first), conv_at: first.toISOString(), page_name: page.name, page_id: String(page.id), conv_id: c.id,
      customer_name: c.customers?.[0]?.name || c.from?.name || '', phone: (c.recent_phone_numbers || [])[0]?.phone_number || null,
      sale_name: sale || (c.assignee_ids || []).map(id => userMap[id]).find(Boolean) || null,
      customer_ask: (ask || '(gửi ảnh/tệp)').slice(0, 700), sale_reply: reply ? reply.slice(0, 1000) : null, verdict,
      severity: null, source_faq: null, suggestion: null, cham_boi: loc ? 'luat' : null,
      issue: loc ? `Tự lọc lúc kéo: ${loc} (vẫn lưu đủ dữ liệu).` : verdict === 'chi_bot' ? 'Chỉ có bot trả lời tự động, không có sale nào vào tư vấn.'
        : verdict === 'khong_tra_loi' ? 'Khách có nhu cầu thật nhưng không ai trả lời (kể cả bot).' : null,
      full_thread: thread, pancake_url: `https://pancake.vn/${page.id}?c_id=${c.id}`,
      _rep_at: repAt,   // giờ Sale trả lời — chỉ dùng để tính "trả lời muộn", không ghi vào bảng
      _chiSale: !!c._chiSale,   // hội thoại chỉ có Sale nhắn trong khoảng — chỉ cập nhật dòng đã có
    });
  });
  return out;
}

// CHẤM CẢ ĐOẠN HỘI THOẠI (anh Hải 7/10: "chấm là chấm cả đoạn hội thoại; hôm qua đúng nhưng mấy hôm sau khách hỏi mà sai thì
// vẫn có thể thành sai — không cần chấm riêng và tách ra nhiều cái giống nhau nữa"). Từ 1/10/2026: 1 dòng / conv_id (mỗi kênh
// Zalo / Messenger / bình luận có conv_id riêng). Lượt khách trong khoảng kéo → gộp: câu khách nối lại, kết quả theo LƯỢT CUỐI
// (Sale đã trả lời → chờ chấm cả đoạn; chưa → miss). Toàn lượt khấn / xã giao → không liên quan.
function gopLuot(got) {
  if (!got.length) return null;
  const that = got.filter(x => x.verdict !== 'khong_lien_quan'), ds = that.length ? that : got;
  const cuoi = ds[ds.length - 1], traLoi = [...ds].reverse().find(x => x.sale_reply);
  return { ...cuoi, customer_ask: ds.map(x => x.customer_ask).join(' · ').slice(-700),
    sale_reply: cuoi.sale_reply || traLoi?.sale_reply || null, sale_name: cuoi.sale_name || traLoi?.sale_name || null };
}
// Nối thread cũ (đã lưu) + mới (lượt này): lượt mỗi giờ chỉ đọc phần mới → không được làm mất đoạn trước
function ghepThread(a, b) {
  const l = [...new Set([...(a || '').split('\n'), ...(b || '').split('\n')].filter(Boolean))];
  return l.sort((x, y) => x.slice(0, 18).localeCompare(y.slice(0, 18))).join('\n').slice(-6000);
}

// ── NHẬT KÝ CHẠY (anh Hải 30/9: "ghi lại lịch xử lý m kéo, cái nào kéo lỗi t còn biết để hỏi") ──────────────
// Mỗi lượt 1 dòng ở qc_nhat_ky_chay → trang Cài đặt › Nhật ký chạy. Ghi nhật ký lỗi thì bỏ qua, KHÔNG làm hỏng lượt kéo.
const NK = { id: null, s: {} };
const LIEN_KET = process.env.GITHUB_RUN_ID
  ? `${process.env.GITHUB_SERVER_URL}/${process.env.GITHUB_REPOSITORY}/actions/runs/${process.env.GITHUB_RUN_ID}` : null;
const HNK = { apikey: SBK, Authorization: 'Bearer ' + SBK, 'Content-Type': 'application/json' };
const gioVN = d => new Date(d.getTime() + 7 * 36e5).toISOString().slice(5, 16).replace('T', ' ').replace(/^(\d\d)-(\d\d)/, '$2/$1');
async function nkMo(khoang) {
  if (DRY) return;
  try {
    const r = await fetch(`${SB}/rest/v1/qc_nhat_ky_chay`, { method: 'POST', headers: { ...HNK, Prefer: 'return=representation' },
      body: JSON.stringify({ loai: CHE_DO === 'moc' ? 'keo-gio' : (LIEN_KET ? 'keo-quet' : 'keo-tay'), khoang, lien_ket: LIEN_KET }) });
    NK.id = (await r.json())?.[0]?.id || null;
  } catch (e) { console.log('(không ghi được nhật ký:', e.message + ')'); }
}
async function nkDong(trang_thai, loi) {
  if (DRY || !NK.id) return;
  try {
    await fetch(`${SB}/rest/v1/qc_nhat_ky_chay?id=eq.${NK.id}`, { method: 'PATCH', headers: { ...HNK, Prefer: 'return=minimal' },
      body: JSON.stringify({ ...NK.s, trang_thai, loi: loi ? String(loi).slice(0, 1000) : null, ket_thuc: new Date().toISOString() }) });
    await fetch(`${SB}/rest/v1/qc_nhat_ky_chay?bat_dau=lt.${new Date(Date.now() - 90 * 864e5).toISOString()}`, { method: 'DELETE', headers: HNK });
  } catch (e) { console.log('(không ghi được nhật ký:', e.message + ')'); }
}
// Kênh kết nối (anh Hải 1/10): xanh = đọc được, đỏ = không đọc được → biết page / Zalo nào cần kết nối lại với Pancake.
const loaiKenh = pl => /zalo/.test(pl || '') ? 'zalo' : /tiktok/.test(pl || '') ? 'tiktok' : /facebook/.test(pl || '') ? 'facebook' : (pl || 'khác');
function kenhDong(p, kichHoat, trang_thai, ly_do, them = {}) {
  const now = new Date().toISOString();
  return { page_id: String(p.id), ten: p.name || null, kenh: loaiKenh(p.platform), kich_hoat: kichHoat, trang_thai, ly_do: ly_do || null,
    lan_kiem: now, ...(trang_thai === 'ok' ? { lan_ok: now } : {}), ...them };
}
async function kenhGhi(rows) {
  if (DRY || !rows.length) return;
  try {   // tách 2 nhóm: dòng 'ok' có lan_ok, dòng 'loi' KHÔNG đụng lan_ok (giữ lần đọc được gần nhất)
    for (const nhom of [rows.filter(r => r.lan_ok), rows.filter(r => !r.lan_ok)]) if (nhom.length)
      await fetch(`${SB}/rest/v1/qc_kenh?on_conflict=page_id`, { method: 'POST', headers: { ...HNK, Prefer: 'resolution=merge-duplicates,return=minimal' },
        body: JSON.stringify(nhom) });
  } catch (e) { console.log('(không ghi được trạng thái kênh:', e.message + ')'); }
}
async function kenhDoTatCa(ly_do) {   // không lấy được danh sách page → mọi kênh đã biết chuyển đỏ
  if (DRY) return;
  try {
    await fetch(`${SB}/rest/v1/qc_kenh?page_id=not.is.null`, { method: 'PATCH', headers: { ...HNK, Prefer: 'return=minimal' },
      body: JSON.stringify({ trang_thai: 'loi', ly_do, lan_kiem: new Date().toISOString() }) });
  } catch (e) { console.log('(không ghi được trạng thái kênh:', e.message + ')'); }
}

(async () => {
  if (CHE_DO === 'moc') {
    const r = await rest('GET', `qc_cau_hinh?select=gia_tri&khoa=eq.${encodeURIComponent(KHOA_MOC)}`);
    const moc = r?.[0]?.gia_tri ? new Date(r[0].gia_tri) : new Date(vnDay(new Date(Date.now() - 864e5)) + 'T00:00:00+07:00');
    tuUtc = new Date(moc.getTime() - 30 * 6e4);
    console.log(`Chế độ MỐC: kéo hội thoại khách nhắn từ ${tuUtc.toISOString()} (mốc lượt trước ${moc.toISOString()})${DRY ? ' · THỬ (không ghi)' : ''}`);
  } else console.log(`Khoảng ngày (giờ VN): ${FROM} → ${TO}${DRY ? ' · THỬ (không ghi)' : ''}`);
  await nkMo(CHE_DO === 'moc' ? `từ ${gioVN(tuUtc)}` : (FROM === TO ? FROM.split('-').reverse().slice(0, 2).join('/') : `${FROM} → ${TO}`));
  const pj = await pk('/pages');
  // PAGE_IDS (7/10): chạy bù song song theo nhóm page — khi đó KHÔNG ghi trạng thái kênh, KHÔNG soát miss (lượt thường lo)
  const CHI_PAGE = (process.env.PAGE_IDS || '').split(',').map(x => x.trim()).filter(Boolean);
  const pages = (pj?.categorized?.activated || []).filter(p => !CHI_PAGE.length || CHI_PAGE.includes(String(p.id)));
  console.log('pages:', pages.length);
  if (!pages.length) {
    await kenhDoTatCa('Pancake không trả danh sách page — token PANCAKE_SESSION_TOKEN có thể đã hết hạn');
    throw new Error('Pancake không trả danh sách page — token PANCAKE_SESSION_TOKEN có thể đã hết hạn (dự kiến ~1/11/2026)');
  }
  const KENH = new Map();   // trạng thái từng kênh lượt này → qc_kenh (Cài đặt › Nhật ký chạy)
  // 7/10 anh Hải: chỉ theo dõi các page ĐANG GẮN (kích hoạt) — kênh Pancake đang tắt không đưa vào bảng
  NK.s.so_page = pages.length;
  const pairs = [], dem = {};
  for (const p of pages) {
    const userMap = {};
    ((await pk(`/pages/${p.id}/users`))?.users || []).forEach(u => userMap[u.id] = u.name);
    let count = 0, lastId = null, cuLien = 0, lay = [], docDuoc = null, moiNhat = null;
    for (let b = 0; b < 60 && cuLien < 2; b++) {
      const d = await pk(`/pages/${p.id}/conversations${count ? `?current_count=${count}${lastId ? `&last_conversation_id=${encodeURIComponent(lastId)}` : ''}` : ''}`);
      if (b === 0) { docDuoc = !!(d && Array.isArray(d.conversations)); moiNhat = (d?.conversations || []).reduce((m, c) => c.updated_at && (!m || utc(c.updated_at) > utc(m)) ? c.updated_at : m, null); }   // Pancake không xếp theo giờ → lấy lớn nhất
      const cs = d?.conversations || [];
      if (!cs.length) break;
      let moi = 0;
      for (const c of cs) {
        if (utc(c.updated_at || '1970-01-01') >= tuUtc) moi++;           // mốc dừng quét: theo thứ tự danh sách (updated_at)
        if (String(c.id).startsWith('pzl_g_')) continue;                 // nhóm Zalo: bỏ
        if (utc(c.last_customer_interactive_at || c.updated_at || '1970-01-01') >= tuUtc) lay.push(c);   // hội thoại khách có nhắn
        // 9/10: CHỈ Sale nhắn (khách không nhắn thêm) → vẫn lấy để cập nhật hội thoại đã có (Sale trả lời sau lúc chấm; trước đây phải chờ quét 18h35 — báo sai #47)
        else if (utc(c.updated_at || '1970-01-01') >= tuUtc) { c._chiSale = true; lay.push(c); }
      }
      cuLien = moi ? 0 : cuLien + 1;
      count += cs.length; lastId = cs[cs.length - 1].id;
      await sleep(150);
    }
    lay = [...new Map(lay.map(c => [c.id, c])).values()];
    {
      const lyDo = !docDuoc ? 'Pancake trả lỗi khi đọc hội thoại — có thể mất kết nối / hết quyền, cần kết nối lại'
        : p.connected === false ? 'Pancake báo kênh MẤT KẾT NỐI (connected = false) — cần kết nối lại'
        : p.need_fix_webhook ? 'Pancake báo cần sửa webhook — tin mới có thể không về' : null;
      KENH.set(String(p.id), kenhDong(p, true, lyDo ? 'loi' : 'ok', lyDo, { tin_moi_nhat: moiNhat ? utc(moiNhat).toISOString() : null, so_hoi_thoai: lay.length }));
    }
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
      const hoi = gopLuot(tachLuot(p, c, msgs, userMap));
      if (hoi) { pairs.push(hoi); n++; }
      await sleep(150);
    }
    dem[p.name] = n;
    console.log(`${p.name}: ${lay.length} hội thoại khách nhắn (quét ${count}) → ${n} hội thoại có lượt khách`);
  }
  if (!CHI_PAGE.length) await kenhGhi([...KENH.values()]);
  const doK = [...KENH.values()].filter(k => k.trang_thai === 'loi');
  console.log(`Kênh: ${KENH.size - doK.length} đọc được, ${doK.length} không đọc được`, doK.map(k => k.ten).join(' · '));
  if (!DRY && !CHI_PAGE.length) try {   // kênh từng có mà lượt này Pancake không trả về nữa → đỏ
    await fetch(`${SB}/rest/v1/qc_kenh?lan_kiem=lt.${BAT_DAU.toISOString()}`, { method: 'PATCH', headers: { ...HNK, Prefer: 'return=minimal' },
      body: JSON.stringify({ trang_thai: 'loi', ly_do: 'Không còn trong danh sách page của Pancake — đã gỡ / mất quyền' }) });
  } catch (e) { console.log('(không ghi được trạng thái kênh:', e.message + ')'); }
  const theoV = {}; pairs.forEach(x => theoV[x.verdict] = (theoV[x.verdict] || 0) + 1);
  console.log(`Tổng ${pairs.length} hội thoại:`, theoV);
  NK.s.luot_tim = pairs.length;
  if (process.env.OUT) fs.writeFileSync(process.env.OUT, JSON.stringify(pairs, null, 1));
  if (DRY) return;

  // Ghi theo HỘI THOẠI: mỗi conv_id (từ 1/10/2026) đúng 1 dòng. Có rồi thì cập nhật khi: khách nhắn thêm (lượt khách mới hơn),
  // Sale nói thêm sau lần chấm trước, hoặc dòng đang miss nay Sale đã trả lời → nối thread, về chờ chấm LẠI CẢ ĐOẠN.
  // CHỐT CHẶN GIỜ (7/10): dòng khách mở đầu lượt phải nằm trong thread đúng giờ VIỆT NAM của conv_at. Lệch (vd ai đổi lại
  // UTC) → dừng cả lượt, không ghi, Nhật ký chạy báo Lỗi + GitHub gửi mail.
  const lechGio = pairs.filter(x => x.full_thread && x.conv_at && !x.full_thread.includes('[' + gioThread(new Date(x.conv_at)) + '] Khách'));
  if (pairs.length >= 5 && lechGio.length > pairs.length * 0.2)
    throw new Error(`Giờ trong thread lệch giờ Việt Nam ở ${lechGio.length}/${pairs.length} hội thoại — dừng, không ghi (kiểm hàm gioThread)`);
  const TU_HT = '2026-10-01';
  const convs = [...new Set(pairs.map(x => x.conv_id))], cu = new Map();
  for (let i = 0; i < convs.length; i += 80) {
    const ds = convs.slice(i, i + 80).map(x => `"${x.replace(/"/g, '\\"')}"`).join(',');
    const rows = await rest('GET', `${BANG}?select=id,conv_id,conv_at,verdict,sale_reply,full_thread,issue,cham_boi&conv_id=in.(${encodeURIComponent(ds)})&conv_date=gte.${TU_HT}&order=conv_at.desc&limit=5000`);
    rows.forEach(r => { if (!cu.has(r.conv_id)) cu.set(r.conv_id, r); });
  }
  const moi = [], capNhat = [], vaThread = [];
  for (const x of pairs) {
    const r = cu.get(x.conv_id);
    if (!r) { if (!x._chiSale) moi.push(x); continue; }   // hội thoại cũ chưa có dòng mà chỉ Sale nhắn → không tạo dòng mới
    const khachMoi = new Date(x.conv_at) > new Date(r.conv_at || 0);
    const hetMiss = x.verdict === 'chua_cham' && ['khong_tra_loi', 'chi_bot'].includes(r.verdict);
    const saleThem = x.verdict === 'chua_cham' && x.sale_reply && x.sale_reply !== r.sale_reply && r.cham_boi !== 'claude';
    if (!khachMoi && !hetMiss && !saleThem) {
      // 8/10: không có gì mới để chấm lại, nhưng thread đã lưu THIẾU đoạn (vd bị soát miss cũ ghi đè) → chỉ vá thread, giữ kết quả chấm
      const vo = ghepThread(r.full_thread, x.full_thread);
      if (vo !== (r.full_thread || '') && vo.length > (r.full_thread || '').length) vaThread.push({ id: r.id, full_thread: vo });
      continue;
    }
    const h = x._rep_at ? (new Date(x._rep_at) - new Date(x.conv_at)) / 36e5 : 0;
    // 7/10: KHÔNG ghi nhãn "Trả lời muộn N giờ" (giờ thực, tính cả đêm) nữa — độ chậm đo trong CSDL theo giờ làm (qc_tinh_tg)
    const nhan = x.verdict !== 'chua_cham' ? x.issue
      : (!khachMoi && /^Bình luận →/.test(r.issue || '')) ? r.issue.match(/^Bình luận → tư vấn qua tin nhắn[^.]*\./)?.[0] || null : null;
    capNhat.push({ id: r.id, body: { conv_at: x.conv_at, conv_date: x.conv_date, customer_ask: x.customer_ask, sale_reply: x.sale_reply,
      sale_name: x.sale_name, full_thread: ghepThread(r.full_thread, x.full_thread), verdict: x.verdict, issue: nhan,
      severity: null, suggestion: null, source_faq: null, sai_quy_trinh: null, cham_boi: x.cham_boi } });
  }
  for (const u of capNhat) await rest('PATCH', `${BANG}?id=eq.${u.id}`, u.body);
  for (const u of vaThread) await rest('PATCH', `${BANG}?id=eq.${u.id}`, { full_thread: u.full_thread });
  if (vaThread.length) console.log(`Vá thread thiếu đoạn: ${vaThread.length} hội thoại (giữ kết quả chấm)`);
  const them = moi.map(({ _rep_at, _chiSale, ...x }) => x);
  for (let i = 0; i < them.length; i += 100) await rest('POST', BANG, them.slice(i, i + 100));
  NK.s.luot_them = them.length; NK.s.miss_cap_nhat = capNhat.length;
  NK.s.luot_loc = them.filter(x => x.verdict === 'khong_lien_quan').length;   // tự lọc lúc kéo (khấn / xã giao), vẫn lưu
  console.log(`[${BANG}] Thêm ${them.length} hội thoại mới, cập nhật ${capNhat.length} hội thoại (khách nhắn thêm / Sale nói thêm / hết miss → chấm lại cả đoạn), bỏ ${pairs.length - them.length - capNhat.length} không đổi.`);
  // Soát lại các dòng MISS còn mở với Pancake thật (anh Hải 30/9: "lúc kéo thì phải xem lại các data miss, họ clear xong
  // rồi thì clear hết"). Sale trả lời bổ sung (dù muộn) / nhắn riêng cho khách bình luận → gỡ khỏi miss, chuyển chấm nội dung,
  // gắn nhãn "Trả lời muộn N giờ" (≥ 1 giờ) hoặc "Bình luận → tư vấn qua tin nhắn". Soát miss 30 ngày ở MỌI lượt (từ 1/10;
  // trước đó lượt mỗi giờ chỉ 3 ngày → Sale trả lời miss cũ lúc 11h thì tới 18h35 mới gỡ, anh mở trang vẫn thấy miss).
  // Miss chỉ ~50 dòng nên soát hết mỗi giờ vẫn nhẹ. Dòng cũ thiếu conv_at cũng soát (mốc = đầu ngày conv_date).
  const soatNgay = CHI_PAGE.length ? -1 : Number(process.env.SOAT_NGAY || 30);
  const misses = soatNgay < 0 ? [] : await rest('GET', `${BANG}?select=id,conv_id,conv_at,conv_date,pancake_url,page_id,customer_name,verdict,full_thread`
    + `&verdict=in.(khong_tra_loi,chi_bot)&conv_id=not.like.pzl_g_*`
    + `&conv_date=gte.${vnDay(new Date(Date.now() - soatNgay * 864e5))}&order=conv_at&limit=500`);
  const { soat, capNhat: capNhatMiss } = taoSoat(pk, sleep);
  let go = 0; const demS = {};
  for (const r of misses) {
    let k; try { k = await soat(r); } catch (e) { k = { ket: 'loi' }; }
    demS[k.ket] = (demS[k.ket] || 0) + 1;
    if (k.ket === 'da_tra_loi' || k.ket === 'qua_inbox') {
      // 8/10: NỐI thread, không ghi đè (trước đây ghi đè bằng đoạn từ lúc khách hỏi → mất ngữ cảnh trước đó, ca Nguyễn Tiến Sơn)
      const body = capNhatMiss(k); body.full_thread = ghepThread(r.full_thread, body.full_thread);
      await rest('PATCH', `${BANG}?id=eq.${r.id}&verdict=in.(khong_tra_loi,chi_bot)`, body); go++;
    }
    await sleep(150);
  }
  console.log(`Soát ${misses.length} dòng miss (${soatNgay} ngày gần nhất): gỡ ${go} dòng Sale đã trả lời`, demS);
  NK.s.miss_soat = misses.length; NK.s.miss_go = go;

  if (CHE_DO === 'moc') {   // lưu mốc = lúc lượt này BẮT ĐẦU (tin tới trong lúc chạy sẽ được lượt sau lấy)
    const r = await fetch(`${SB}/rest/v1/qc_cau_hinh`, { method: 'POST', body: JSON.stringify({ khoa: KHOA_MOC, gia_tri: BAT_DAU.toISOString() }),
      headers: { apikey: SBK, Authorization: 'Bearer ' + SBK, 'Content-Type': 'application/json', Prefer: 'resolution=merge-duplicates,return=minimal' } });
    console.log('mốc mới:', BAT_DAU.toISOString(), r.ok ? 'ok' : 'LỖI ' + r.status + ' ' + (await r.text()).slice(0, 200));
  }
  await nkDong('thanh_cong');
})().catch(async e => { console.error('LỖI', e.message); await nkDong('loi', e.message); process.exit(1); });
