// Nạp "BẢNG KHOẢNG GIÁ BÁO KHÁCH - SALES" (Google Sheet đã publish) vào qc_bang_gia — thay toàn bộ.
// Link sheet KHÔNG để trong repo (repo công khai): lấy từ qc_cau_hinh khoa 'bang_gia_url' (…/pubhtml hoặc gốc …/2PACX-…).
// Dùng: ELECTRON_RUN_AS_NODE=1 "D:/Microsoft VS Code/Code.exe" C:/Users/HP/Desktop/qc-cskh/tools/nap-bang-gia.js [--thu]
// Monsieur Claude (anh Hải gửi bảng 6/10/2026)
const K = require('./keys.js');
const thu = process.argv.includes('--thu');
const H = { apikey: K.qc, Authorization: 'Bearer ' + K.qc, 'Content-Type': 'application/json' };
const REST = `${K.url}/rest/v1`;

function csv(text) {   // CSV chuẩn: ngoặc kép, xuống dòng trong ô
  const rows = []; let row = [], cell = '', q = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (q) { if (c === '"') { if (text[i + 1] === '"') { cell += '"'; i++; } else q = false; } else cell += c; }
    else if (c === '"') q = true;
    else if (c === ',') { row.push(cell); cell = ''; }
    else if (c === '\n' || c === '\r') { if (c === '\r' && text[i + 1] === '\n') i++; row.push(cell); rows.push(row); row = []; cell = ''; }
    else cell += c;
  }
  if (cell || row.length) { row.push(cell); rows.push(row); }
  return rows.map(r => r.map(x => x.trim()));
}
const bo = s => (s || '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/đ/gi, 'd').toLowerCase();
// Tên cột trong sheet → cột bảng (các tab đặt tên hơi khác nhau)
const COT = [
  [/^loai$/, 'loai'], [/^kich thuoc|^cac size/, 'kich_thuoc'], [/^chat lieu|^go/, 'chat_lieu'], [/^phan khuc/, 'phan_khuc'],
  [/^muc gia pho bien/, 'gia_pho_bien'], [/^gia thap nhat/, 'gia_min_max'], [/^theo kieu|^chi tiet/, 'chi_tiet'],
  [/^so mau/, 'so_mau'], [/^mau co san/, 'co_san'], [/^ghi chu/, 'ghi_chu'],
];

(async () => {
  const cfg = await (await fetch(`${REST}/qc_cau_hinh?select=gia_tri&khoa=eq.bang_gia_url`, { headers: H })).json();
  const goc = (cfg?.[0]?.gia_tri || '').replace(/\/pub(html)?.*$/, '');
  if (!goc) throw new Error('Chưa có qc_cau_hinh.bang_gia_url');
  const html = await (await fetch(goc + '/pubhtml')).text();
  const tabs = [...html.matchAll(/items\.push\(\{name: "([^"]*)",[^}]*?gid: "(\d+)"/g)].map(m => ({ ten: m[1], gid: m[2] }));
  const capNhat = ((html.match(/KiotViet (\d\d)\.(\d\d)\.(\d{4})/) || []).slice(1));
  const ngay = capNhat.length ? `${capNhat[2]}-${capNhat[1]}-${capNhat[0]}` : null;
  const out = [];
  for (const t of tabs) {
    if (!/^[1-7]\./.test(t.ten)) continue;            // tab 0 cách dùng, 8–9 rà soát nội bộ: không phải giá báo khách
    const rows = csv(await (await fetch(`${goc}/pub?gid=${t.gid}&single=true&output=csv`)).text());
    const hi = rows.findIndex(r => r.some(c => /^MỨC GIÁ PHỔ BIẾN/i.test(c)));
    if (hi < 0) { console.log('bỏ tab (không thấy cột giá):', t.ten); continue; }
    const map = rows[hi].map(h => (COT.find(([re]) => re.test(bo(h))) || [])[1]);
    const nhom = t.ten.replace(/^\d+\.\s*/, '');
    let n = 0;
    for (const r of rows.slice(hi + 1)) {
      if (!r.some(c => c)) continue;
      const o = { nhom, cap_nhat: ngay };
      map.forEach((k, i) => { if (k && r[i]) o[k] = r[i]; });
      if (!o.gia_pho_bien && !o.gia_min_max) continue;
      out.push(o); n++;
    }
    console.log(`${t.ten}: ${n} dòng`);
  }
  console.log('Tổng', out.length, 'dòng · cập nhật', ngay);
  if (thu || !out.length) return;
  const keys = [...new Set(out.flatMap(Object.keys))];
  const full = out.map(o => Object.fromEntries(keys.map(k => [k, o[k] ?? null])));
  let r = await fetch(`${REST}/qc_bang_gia?id=gt.0`, { method: 'DELETE', headers: H });
  if (!r.ok) throw new Error('Xoá cũ lỗi ' + r.status + ' ' + await r.text());
  r = await fetch(`${REST}/qc_bang_gia`, { method: 'POST', headers: { ...H, Prefer: 'return=minimal' }, body: JSON.stringify(full) });
  if (!r.ok) throw new Error('Ghi lỗi ' + r.status + ' ' + await r.text());
  console.log('Đã nạp', full.length, 'dòng vào qc_bang_gia');
})().catch(e => { console.error('LỖI', e.message); process.exit(1); });
