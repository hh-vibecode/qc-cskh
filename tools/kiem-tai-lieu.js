// Kiểm tài liệu quy trình anh Hải gửi (bảng qc_tai_lieu): tải lại mọi tab Google Sheet đã publish, so dấu vân tay với bản lưu.
// Đổi → lưu bản mới (giữ bản cũ để so), ghi Nhật ký chạy (đỏ, loại 'tai-lieu') để phiên Claude cập nhật luật chấm;
// bảng giá đổi thì nạp lại qc_bang_gia (tools/nap-bang-gia.js). Dùng riêng hoặc gọi từ scripts/keo-tin.js (lượt quét 6h20).
// Chạy tay: ELECTRON_RUN_AS_NODE=1 "D:/Microsoft VS Code/Code.exe" C:/Users/HP/Desktop/qc-cskh/tools/kiem-tai-lieu.js [--in]
//   --in : in toàn văn bản đang lưu (để Claude đọc và so luật). Monsieur Claude (12/10/2026)
const crypto = require('crypto');
const K = require('./keys.js');
const H = { apikey: K.qc, Authorization: 'Bearer ' + K.qc, 'Content-Type': 'application/json' };
const REST = `${K.url}/rest/v1`;

async function taiSheet(url) {
  const goc = url.replace(/\/pub(html)?.*$/, '');
  const html = await (await fetch(goc + '/pubhtml')).text();
  const tabs = [...html.matchAll(/items\.push\(\{name: "([^"]*)",[^}]*?gid: "(\d+)"/g)].map(m => ({ ten: m[1], gid: m[2] }));
  if (!tabs.length) throw new Error('Không đọc được danh sách tab: ' + url);
  const phan = [];
  for (const t of tabs) {
    const csv = await (await fetch(`${goc}/pub?gid=${t.gid}&single=true&output=csv`)).text();
    phan.push(`### ${t.ten}\n${csv.replace(/\r\n/g, '\n').trim()}`);
  }
  return phan.join('\n\n');
}
const theoTab = s => Object.fromEntries((s || '').split(/\n(?=### )/).filter(Boolean).map(p => { const i = p.indexOf('\n'); return [p.slice(4, i < 0 ? undefined : i), i < 0 ? '' : p.slice(i + 1)]; }));
function tomTat(cu, moi) {
  const a = theoTab(cu), b = theoTab(moi), ra = [];
  for (const t of new Set([...Object.keys(a), ...Object.keys(b)])) {
    if (!(t in a)) { ra.push(`thêm tab "${t}"`); continue; }
    if (!(t in b)) { ra.push(`bỏ tab "${t}"`); continue; }
    if (a[t] === b[t]) continue;
    const la = new Set(a[t].split('\n')), lb = new Set(b[t].split('\n'));
    const them = [...lb].filter(x => !la.has(x)).length, bot = [...la].filter(x => !lb.has(x)).length;
    ra.push(`tab "${t}": +${them} / −${bot} dòng`);
  }
  return ra.join(' · ') || 'đổi định dạng';
}

async function kiemTaiLieu({ log = console.log } = {}) {
  const ds = await (await fetch(`${REST}/qc_tai_lieu?select=*`, { headers: H })).json();
  const doi = [];
  for (const d of ds) {
    let moi;
    try { moi = await taiSheet(d.url); } catch (e) { log(`[tài liệu] ${d.ten}: LỖI tải — ${e.message}`); doi.push({ khoa: d.khoa, ten: d.ten, loi: e.message }); continue; }
    const vt = crypto.createHash('sha256').update(moi).digest('hex');
    const body = { kiem_luc: new Date().toISOString() };
    if (vt !== d.dau_van_tay) {
      const lanDau = !d.dau_van_tay;
      Object.assign(body, { noi_dung: moi, noi_dung_cu: d.noi_dung, dau_van_tay: vt, thay_doi_luc: new Date().toISOString(),
        tom_tat_doi: lanDau ? 'lưu bản đầu' : tomTat(d.noi_dung, moi) });
      if (!lanDau) doi.push({ khoa: d.khoa, ten: d.ten, tom_tat: body.tom_tat_doi });
      log(`[tài liệu] ${d.ten}: ${lanDau ? 'lưu bản đầu' : 'CÓ THAY ĐỔI — ' + body.tom_tat_doi}`);
    } else log(`[tài liệu] ${d.ten}: không đổi`);
    await fetch(`${REST}/qc_tai_lieu?khoa=eq.${d.khoa}`, { method: 'PATCH', headers: { ...H, Prefer: 'return=minimal' }, body: JSON.stringify(body) });
  }
  if (doi.length) {   // Nhật ký chạy: đỏ để anh / phiên Claude thấy
    await fetch(`${REST}/qc_nhat_ky_chay`, { method: 'POST', headers: { ...H, Prefer: 'return=minimal' }, body: JSON.stringify({
      loai: 'tai-lieu', trang_thai: 'loi', ket_thuc: new Date().toISOString(),
      khoang: doi.map(x => x.ten).join(' · ').slice(0, 300),
      loi: ('Tài liệu quy trình thay đổi — Claude cần đọc (tools/kiem-tai-lieu.js --in) và cập nhật luật chấm + trang Logic: ' +
        doi.map(x => `${x.ten}: ${x.tom_tat || 'lỗi tải ' + x.loi}`).join(' | ')).slice(0, 1000) }) });
    if (doi.some(x => x.khoa === 'bang_gia' && x.tom_tat)) {
      log('[tài liệu] bảng giá đổi → nạp lại qc_bang_gia');
      await new Promise((ok, no) => require('child_process').execFile(process.execPath, [__dirname + '/nap-bang-gia.js'],
        { env: process.env }, (e, out) => { log(out || ''); e ? no(e) : ok(); }));
    }
  }
  return doi;
}
module.exports = { kiemTaiLieu };

if (require.main === module) (async () => {
  if (process.argv.includes('--in')) {
    const ds = await (await fetch(`${REST}/qc_tai_lieu?select=ten,thay_doi_luc,tom_tat_doi,noi_dung`, { headers: H })).json();
    for (const d of ds) console.log(`\n================ ${d.ten} (đổi lần cuối ${d.thay_doi_luc}: ${d.tom_tat_doi})\n${d.noi_dung}`);
    return;
  }
  await kiemTaiLieu();
})().catch(e => { console.error('LỖI', e.message); process.exit(1); });
