// CHUẨN LẠI TÊN SALE THÁNG 10 (anh Hải 28/10/2026): "không gán cứng nữa, sale nào trả lời đúng sale đấy theo tên trên pancake;
// khi không phân biệt được tên người thì theo thương hiệu: Hiền Thủy, TTV = Vân Ngọc · Shidai = Nguyên · CT = Lệ".
//   sale_name = Sale CÓ TÊN NGƯỜI nhắn cuối trong hội thoại ("Sale (Tên): …"), bỏ tài khoản dùng chung (PANCAKE THT HOLDING,
//   Sales Admin, Botcake); không có → mặc định theo thương hiệu (cùng bảng với hàm SQL qc_sale_mac_dinh).
// Trigger qc_sale_theo_thuong_hieu giữ quy tắc cho dòng mới. Dùng: …/Code.exe tools/tinh-lai-sale.js [--thu]
// Monsieur Claude
const K = require('./keys.js');
const thu = process.argv.includes('--thu');
const H = { apikey: K.qc, Authorization: 'Bearer ' + K.qc, 'Content-Type': 'application/json' };
const CHUNG = /^(pancake tht holding|sales? admin|botcake)$/i;
const VN = ['105133802417722', '107792638827892', 'ttm_-000uG5lXadOZHV4VWlMRAHc5FZGkQtuyxY3', 'pzl_1927214341338004925', 'pzl_716330578937743406', '100667699549693'];
const SD = ['506247572578559', 'pzl_421283811192749346', 'pzl_636053762312360623'];
const CT = ['107224335550589', '1212423508625663', 'ttm_-000fnwmEFDETu8kL8prpYMAbgrdue0Cc0hG', 'pzl_355233102341719971', 'pzl_357024678860117283', 'ttm_-000wff5HiYIrt76uNDUJiL1kfVVtVkiURi-'];
function macDinh(id, ten) {
  if (VN.includes(id)) return 'Vân Ngọc'; if (SD.includes(id)) return 'Nguyên Khánh'; if (CT.includes(id)) return 'Lệ';
  const t = (ten || '').toLowerCase();
  if (/hiền th|hien th|tự tại|tu tai|nến bơ|cao cấp/.test(t)) return 'Vân Ngọc';
  if (/shidai|thời đại|thoi dai/.test(t)) return 'Nguyên Khánh';
  if (/chánh tâm|chanh tam|hoàng dương|ming ying/.test(t)) return 'Lệ';
  return null;
}
(async () => {
  // anh Hải 28/10: LỌC TRƯỚC — chỉ chuẩn tên cho hội thoại ĐÃ QUA BỘ LỌC (bỏ khong_lien_quan: khấn, nội bộ, spam…)
  const q = `${K.url}/rest/v1/sale_response_review?select=id,page_id,page_name,sale_name,full_thread&conv_date=gte.2026-10-01&verdict=neq.khong_lien_quan`;
  let rows = [];
  for (let o = 0; ; o += 1000) { const p = await (await fetch(q + '&order=id&limit=1000&offset=' + o, { headers: H })).json(); rows = rows.concat(p); if (p.length < 1000) break; }
  const doi = [], dem = {}, ketQua = {};
  for (const r of rows) {
    const nguoi = [...(r.full_thread || '').matchAll(/^\[[^\]]+\] Sale \(([^)]+)\):/gm)].map(m => m[1].trim()).filter(n => !CHUNG.test(n)).pop() || null;
    const ten = nguoi || macDinh(r.page_id, r.page_name) || r.sale_name || null;
    ketQua[ten] = (ketQua[ten] || 0) + 1;
    if (ten !== r.sale_name) { doi.push({ id: r.id, sale_name: ten }); const k = `${r.sale_name || '(trống)'} → ${ten || '(trống)'}${nguoi ? '' : ' [mặc định]'}`; dem[k] = (dem[k] || 0) + 1; }
  }
  console.log(`${rows.length} dòng tháng 10 · đổi ${doi.length}:`); Object.entries(dem).sort((a, b) => b[1] - a[1]).forEach(([k, v]) => console.log('  ', v, k));
  console.log('Sau khi chuẩn:', ketQua);
  if (thu) return;
  for (const d of doi) {
    const r = await fetch(`${K.url}/rest/v1/sale_response_review?id=eq.${d.id}`, { method: 'PATCH', headers: { ...H, Prefer: 'return=minimal' }, body: JSON.stringify({ sale_name: d.sale_name }) });
    if (!r.ok) { console.error('LỖI', d.id, r.status, await r.text()); process.exit(1); }
  }
  console.log('đã ghi');
})();
