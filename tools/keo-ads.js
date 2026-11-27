// LẤY BÙ QUẢNG CÁO (Ad ID Meta) CHO HỘI THOẠI PANCAKE → qc_ads_hoi_thoai (app MKT đọc view qc_hoi_thoai_ads). Chỉ ĐỌC Pancake.
// Job kéo tin mỗi giờ tự ghi cho hội thoại mới; công cụ này lấy bù khoảng cũ (anh duyệt 27/11: từ 1/11 trước, rồi lùi về 1/6).
// Dùng: ELECTRON_RUN_AS_NODE=1 "D:/Microsoft VS Code/Code.exe" tools/keo-ads.js
//   FROM=2026-11-01 (giờ VN, mặc định 1/11) · TO=2026-11-30 (mặc định hôm nay) — lấy hội thoại có hoạt động cuối (khách nhắn cuối,
//   bình luận thì updated_at) trong khoảng · PAGE_IDS=a,b (chia luồng song song) · LAI=1 (đọc lại cả hội thoại đã có)
//   DRY_RUN=1 (không ghi). Pancake không lọc danh sách theo giờ (since/until bị bỏ qua, thử 27/11) → phải lật danh sách tới mốc.
// Chỉ gọi tin nhắn cho INBOX Facebook / TikTok (ad_clicks nằm ở đó); bình luận + Zalo ghi từ danh sách (post_id, khách).
// Nhịp ≥150 ms; tự nghỉ phút 0–10 mỗi giờ và nửa đầu giờ 6h / 7h / 18h (giờ bận của app MKT/Sale). Monsieur Claude
const K = require('./keys.js');
const { dongAds, ghiAds, loaiKenh } = require('./ads-lib.js');
const TOK = K.pancake, SBK = K.qc, SB = K.url;
if (!TOK || !SBK) { console.error('Thiếu PANCAKE_SESSION_TOKEN hoặc QC_SUPABASE_KEY'); process.exit(1); }
const sleep = ms => new Promise(r => setTimeout(r, ms));
const utc = s => new Date(/[zZ]|[+-]\d\d:?\d\d$/.test(s) ? s : s + 'Z');
const vnNow = () => new Date(Date.now() + 7 * 36e5);
const FROM = process.env.FROM || '2026-11-01', TO = process.env.TO || vnNow().toISOString().slice(0, 10);
const tu = new Date(FROM + 'T00:00:00+07:00'), den = new Date(TO + 'T23:59:59.999+07:00');
const DRY = !!process.env.DRY_RUN, LAI = !!process.env.LAI;
const CHI = (process.env.PAGE_IDS || '').split(',').map(x => x.trim()).filter(Boolean);
const BO_QUA = new Set(['pzl_714131186705158830']);   // Zalo Kế Toán (13/11) — như keo-tin

async function choRanh() {
  for (;;) {
    const d = vnNow(), h = d.getUTCHours(), m = d.getUTCMinutes();
    if (m >= 11 && !([6, 7, 18].includes(h) && m < 30)) return;
    await sleep(30000);
  }
}
async function pk(path) {
  for (let i = 0; i < 4; i++) {
    await choRanh();
    try {
      const r = await fetch(`https://pancake.vn/api/v1${path}${path.includes('?') ? '&' : '?'}access_token=${TOK}`);
      if (r.ok) return await r.json();
      if (r.status === 429) { await sleep(3000 * (i + 1)); continue; }
      return null;
    } catch (e) { await sleep(1500); }
  }
  return null;
}
async function daCo(pageId) {   // conv_id → cap_nhat_luc đã lưu (bỏ qua hội thoại không có gì mới)
  const m = new Map();
  for (let off = 0; ; off += 1000) {
    const r = await fetch(`${SB}/rest/v1/qc_ads_hoi_thoai?select=conv_id,cap_nhat_luc&page_id=eq.${encodeURIComponent(pageId)}&order=conv_id&limit=1000&offset=${off}`,
      { headers: { apikey: SBK, Authorization: 'Bearer ' + SBK } });
    const j = await r.json(); if (!Array.isArray(j)) throw new Error('đọc qc_ads_hoi_thoai lỗi: ' + JSON.stringify(j).slice(0, 200));
    j.forEach(x => m.set(x.conv_id, new Date(x.cap_nhat_luc))); if (j.length < 1000) break;
  }
  return m;
}

(async () => {
  console.log(`Lấy bù quảng cáo ${FROM} → ${TO}${CHI.length ? ' · page ' + CHI.join(',') : ''}${DRY ? ' · THỬ' : ''}${LAI ? ' · đọc lại cả hội thoại đã có' : ''}`);
  const pj = await pk('/pages');
  const pages = (pj?.categorized?.activated || []).filter(p => !BO_QUA.has(String(p.id)) && (!CHI.length || CHI.includes(String(p.id))));
  if (!pages.length) throw new Error('Không có page nào (token / PAGE_IDS?)');
  const tong = { hoi_thoai: 0, goi_tin: 0, co_ad: 0, ghi: 0, bo_qua: 0 };
  for (const p of pages) {
    const kenh = loaiKenh(p.platform), co = LAI || DRY ? new Map() : await daCo(String(p.id));
    let count = 0, lastId = null, cuLien = 0, buf = [], cuNhat = null; const st = { hoi_thoai: 0, goi_tin: 0, co_ad: 0, bo_qua: 0 };
    const xa = async () => { if (!buf.length) return; if (!DRY) tong.ghi += await ghiAds(buf, { url: SB, key: SBK }); buf = []; };
    for (let b = 0; b < 6000 && cuLien < 2; b++) {
      const d = await pk(`/pages/${p.id}/conversations${count ? `?current_count=${count}${lastId ? `&last_conversation_id=${encodeURIComponent(lastId)}` : ''}` : ''}`);
      const cs = d?.conversations || [];
      if (!cs.length) break;
      let moi = 0;
      for (const c of cs) {
        if (utc(c.updated_at || '1970-01-01') >= tu) moi++;
        if (String(c.id).startsWith('pzl_g_')) continue;
        const hd = utc(c.last_customer_interactive_at || c.updated_at || '1970-01-01');
        if (hd < tu || hd > den) continue;
        st.hoi_thoai++; if (!cuNhat || hd < cuNhat) cuNhat = hd;
        const cu = co.get(String(c.id));
        if (cu && cu >= hd) { st.bo_qua++; continue; }
        const custId = c.customers?.[0]?.id;
        const docTin = custId && (c.type || '').toUpperCase() === 'INBOX' && (kenh === 'facebook' || kenh === 'tiktok');
        let resp = null, msgs = [];
        if (docTin) {
          resp = await pk(`/pages/${p.id}/conversations/${encodeURIComponent(c.id)}/messages?customer_id=${custId}`);
          msgs = resp?.messages || []; st.goi_tin++;
          await sleep(150);
        }
        const row = dongAds(p, c, resp, msgs);
        if (row.ads?.length) st.co_ad++;
        buf.push(row); if (buf.length >= 100) await xa();
      }
      cuLien = moi ? 0 : cuLien + 1;
      count += cs.length; lastId = cs[cs.length - 1].id;
      if (b % 20 === 19) console.log(`  ${p.name}: đã lật ${count} hội thoại, ${st.hoi_thoai} trong khoảng, ${st.co_ad} có Ad ID`);
      await sleep(150);
    }
    await xa();
    for (const k of Object.keys(st)) tong[k] += st[k];
    console.log(`${p.name} [${kenh}]: lật ${count} · trong khoảng ${st.hoi_thoai} (cũ nhất ${cuNhat ? cuNhat.toISOString().slice(0, 10) : '-'}) · gọi tin ${st.goi_tin} · có Ad ID ${st.co_ad} · bỏ qua (đã có) ${st.bo_qua}`);
  }
  console.log('TỔNG', JSON.stringify(tong));
})().catch(e => { console.error('LỖI', e.message); process.exit(1); });
