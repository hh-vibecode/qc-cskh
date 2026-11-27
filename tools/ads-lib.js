// TÁCH QUẢNG CÁO (Ad ID Meta) TỪ 1 HỘI THOẠI PANCAKE — dùng chung cho scripts/keo-tin.js (mỗi giờ) và tools/keo-ads.js (lấy bù).
// App MKT nhờ, anh Hải duyệt 27/11/2026: mỗi hội thoại lấy quảng cáo GẦN NHẤT khách nhắn đến từ đó, vẫn lưu danh sách tất cả.
// Đọc từ response /pages/{page}/conversations/{conv}/messages (lời gọi job kéo vốn đã làm):
//   ad_clicks      → lịch sử bấm quảng cáo của khách vào hội thoại (ad_id, post_id, inserted_at, custom_tag)
//   activities     → mục có ad_id (nguồn ADS, OPEN_THREAD; ads_context_data.ad_title / post_id không kèm page)
//   messages       → thẻ quảng cáo trong chat (attachments[].ad_id)
// Gộp trùng (cùng ad_id < 5 phút) + chọn gần nhất làm trong CSDL (qc_gop_ads / trigger qc_ads_gan_nhat).
// Giờ Pancake không kèm múi = UTC → ghi ISO có Z. Monsieur Claude
const utc = s => new Date(/[zZ]|[+-]\d\d:?\d\d$/.test(s) ? s : s + 'Z');
const iso = s => { if (!s) return null; const d = utc(String(s)); return isNaN(d) ? null : d.toISOString(); };
const loaiKenh = pl => /zalo/.test(pl || '') ? 'zalo' : /tiktok/.test(pl || '') ? 'tiktok' : /facebook/.test(pl || '') ? 'facebook' : (pl || 'khác');
const gon = o => Object.fromEntries(Object.entries(o).filter(([, v]) => v != null && v !== ''));
const coPage = (pageId, post) => !post ? null : String(post).includes('_') ? String(post) : `${pageId}_${post}`;

function tachAds(pageId, resp, msgs) {
  const ds = [];
  for (const arr of Object.values(resp?.ad_clicks || {})) for (const x of (Array.isArray(arr) ? arr : [])) {
    if (x?.ad_id) ds.push(gon({ ad_id: String(x.ad_id), luc: iso(x.inserted_at), post_id: coPage(pageId, x.post_id),
      custom_tag: x.custom_tag, nguon: ['ad_clicks'] }));
  }
  for (const a of (resp?.activities || [])) if (a?.ad_id) {
    const c = a.ads_context_data || {};
    ds.push(gon({ ad_id: String(a.ad_id), luc: iso(a.inserted_at), post_id: coPage(pageId, c.post_id), tieu_de: c.ad_title, nguon: ['referral'] }));
  }
  for (const m of (msgs || [])) for (const at of (m.attachments || [])) if (at?.ad_id) {
    ds.push(gon({ ad_id: String(at.ad_id), luc: iso(m.inserted_at), post_id: coPage(pageId, at.post_id), nguon: ['the_quang_cao'] }));
  }
  return ds.filter(x => x.luc);
}

// 1 dòng cho qc_ghi_ads. resp/msgs có thể rỗng (bình luận / Zalo lấy bù chỉ từ danh sách hội thoại).
function dongAds(page, c, resp, msgs) {
  const cuoi = (msgs || []).reduce((m, x) => { const t = iso(x.inserted_at); return t && (!m || t > m) ? t : m; }, null);
  return gon({
    conv_id: String(c.id), page_id: String(page.id), page_name: page.name, kenh: loaiKenh(page.platform),
    loai: (c.type || '').toLowerCase() || null,
    khach_id: c.customers?.[0]?.id ? String(c.customers[0].id) : null,
    ten_khach: c.customers?.[0]?.name || c.from?.name || null,
    sdt: (c.recent_phone_numbers || [])[0]?.phone_number || null,
    post_id: c.post_id ? String(c.post_id) : null,
    ads: resp ? tachAds(page.id, resp, msgs) : [],
    tin_dau_luc: iso(c.inserted_at), tin_cuoi_luc: cuoi || iso(c.updated_at), khach_cuoi_luc: iso(c.last_customer_interactive_at),
  });
}

// Ghi theo lô qua RPC (khoá QC). Lỗi thì ném — nơi gọi tự quyết có dừng hay không.
async function ghiAds(rows, { url, key }, lo = 200) {
  let n = 0;
  // 27/11: Pancake trả cùng 1 hội thoại 2 lần khi lật trang (thứ tự đổi trong lúc lật) → 1 lô trùng conv_id, ON CONFLICT từ chối
  // cả lô. Gộp trước: nối danh sách quảng cáo, giữ dòng có tin mới hơn.
  const m = new Map();
  for (const r of rows) {
    const c = m.get(r.conv_id);
    if (!c) { m.set(r.conv_id, r); continue; }
    const moi = (r.tin_cuoi_luc || '') >= (c.tin_cuoi_luc || '') ? r : c;
    m.set(r.conv_id, { ...moi, ads: [...(c.ads || []), ...(r.ads || [])] });
  }
  rows = [...m.values()];
  const sach = (k, v) => typeof v === 'string' ? v.replace(/[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]|\u0000/g, '') : v;
  for (let i = 0; i < rows.length; i += lo) {
    for (let t = 0; ; t++) {
      const r = await fetch(`${url}/rest/v1/rpc/qc_ghi_ads`, { method: 'POST',
        headers: { apikey: key, Authorization: 'Bearer ' + key, 'Content-Type': 'application/json' },
        body: JSON.stringify({ p_rows: rows.slice(i, i + lo) }, sach) });
      if (r.status === 429 && t < 5) { await new Promise(s => setTimeout(s, 5000 * (t + 1))); continue; }
      const tx = await r.text();
      if (!r.ok) throw new Error(`qc_ghi_ads → ${r.status} ${tx.slice(0, 300)}`);
      n += Number(tx) || 0; break;
    }
  }
  return n;
}

module.exports = { tachAds, dongAds, ghiAds, loaiKenh };
