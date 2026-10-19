// NHẬN DIỆN LỜI KHẤN (anh Hải 19/10/2026: tránh để Sonnet chấm xong mới ra "không liên quan").
// Tháng 10: 593 dòng Sonnet chấm ra khong_lien_quan, ~410 là LỜI KHẤN dưới bình luận lọt bộ lọc lúc kéo vì:
//  - "Thích Ca MÂU Ni" bỏ dấu = "mau" → khớp từ "mẫu" (hỏi mua); "Con XIN…" khớp "xin" (xin giá)
//  - gõ sai / viết liền: "Nan mô", "Nmaddphat", "Mò phàt", "A Di đaphat"
// Cách mới — CHẶT, chỉ lọc khi: có DẤU HIỆU KHẤN rõ (nam mô, a di đà phật, niệm, lạy…) + MỌI từ đều thuộc bộ từ cầu khấn
// + không có số, không có từ ý mua. Tên các ngài đứng một mình ("quan âm", "địa tạng") = khách gọi tên tượng → KHÔNG lọc.
// Dùng chung: scripts/keo-tin.js (gắn sẵn lúc kéo, vẫn lưu đủ) · chạy riêng `--do` để đo trên dữ liệu tháng 10 (lọc nhầm phải = 0).
// Monsieur Claude
const bo = s => (s || '').normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/đ/g, 'd').replace(/Đ/g, 'd').toLowerCase();
const TU_KHAN = new Set((
  'nam nan mo mot namo a i di da dda adida phat phap phatt bon su thich camauni quan quang the am bo tat dai tu bi cuu kho nan linh cam ung ' +
  'dia tang vuong duoc luu ly lac sa chu muoi phuong ba doi thanh hien chung sanh sinh tay cuc tiep dan dao ' +
  'van thu pho chi kim cang thien nhan nguyen thuong ' +
  'con xin da vang chau toi cau niem tam sam hoi huong kinh le lay me cha ma ong troi tren on ta cui ' +
  'binh an giadinh giaho suc khoe manh may man tai loc via phuoc hanh phuc lanh vien thuan loi cong benh tieu tru tan ' +
  'tat ca moi nguoi quoc thai nhiem va cung phu ho do che chiu deu duoc o xa xu toan gioi cua tri tue sang ' +
  'xinh don tuoi ty suu dan mao thin ngo mui than dau tuat hoi canh nham quy giap at dinh ky ' +
  'chanhtam khonggian linh giao cam nhieu oi ah nha nhe luon mai ngay hom nay p'
).split(/\s+/));
// DẤU HIỆU KHẤN rõ
const LOI = /\b(nam mo|nam mot|nan mo|namo|adida\w*|a di da phat|di da phat|niem phat|con niem|con lay|lay me|lay phat|bo tat phu ho|phat phu ho)\b/;
// Ý MUA — có là KHÔNG lọc (để Sonnet chấm)
const Y_MUA = /\b(gia|bao nhieu|bn|mua|thinh|mau|ship|tuvan|inbox|ib|sdt|zalo|kich thuoc|cm|dat|co ban|con hang|gui|xem|khong|ko|k|tuong|den|bat huong|lu huong|ban tho|bo nay|cai nay|loai|size|giao|hang|shop|nhan tin|lien he|chat lieu|go|dong)\b/;
const DINH_LIEN = /^(n+a*m+o*|mo|mot)+a*i?(d+i*d*a*)+p+h*a+t+$|^a+d+i*d+a+p+h*a+t+$|^m+o+p+h*a+t+$/;   // nmaddphat, nammmoadidaphat, adidaphat, mophat
const LA_TOI_DA = 0.15;   // câu khấn dài được phép ≤ 15% từ ngoài bộ (gõ sai, "tạ ơn", "thượng"…) — từ ý mua đã chặn ở Y_MUA
function laLoiKhan(ask) {
  if (!ask) return false;
  let t = bo(ask).replace(/\(gui anh\/tep\)|\(sticker\)/g, ' ').replace(/[^a-z0-9\s]+/g, ' ').replace(/\s+/g, ' ').trim();
  if (!t || /\d/.test(t)) return false;                    // có số (kích thước, giá, sđt) → để Sonnet
  t = t.replace(/\bthich ca mau ni\b/g, 'thich camauni').replace(/\bgia (dinh|ho)\b/g, 'gia$1').replace(/\bchanh tam\b/g, 'chanhtam')
       .replace(/\bkhong gian\b/g, 'khonggian').replace(/\btu van\b/g, 'tuvan');
  if (Y_MUA.test(t)) return false;
  const tu = t.split(' ');
  if (LOI.test(t) && tu.filter(w => !TU_KHAN.has(w)).length <= Math.floor(tu.length * LA_TOI_DA)) return true;
  const lien = tu.join('').replace(/^(con|da|xin)+/, '');
  return lien.length <= 30 && DINH_LIEN.test(lien);       // viết liền / gõ sai: "Nmaddphat", "Adidàphật"
}
// 19/10: đã thử thêm lọc tin máy (kết bạn, sinh nhật, cuộc gọi nhỡ) + câu chỉ khen → đo NHẦM 15 hội thoại thật (Sale chủ động
// nhắn Zalo sau khi khách đồng ý kết bạn, chúc sinh nhật khách quen…) → BỎ, chỉ giữ lời khấn (đo nhầm 0). Đừng thêm lại khi chưa đo.
// TIN KẾT BẠN Zalo (anh Hải 19/10: "mấy cái lời mời kết bạn thì bỏ qua, k care") — "Bạn nhận được lời mời kết bạn…",
// "X đã đồng ý kết bạn", "Bạn vừa kết bạn với…", "Bạn vừa gửi lời mời kết bạn…". NGOẠI LỆ: lời mời có viết kèm ý mua
// (#2914 "Kết bạn với mình nhé! chị muốn mua lá dán phong thuỷ") → vẫn chấm.
const KET_BAN = /(ban nhan duoc loi moi ket ban|da dong y ket ban|ban vua ket ban voi|ban vua gui loi moi ket ban)/;
const Y_MUA_KB = /\b(gia|bao nhieu|mua|thinh|mau|ship|tu van|bao gia|dat hang|can tim|cho minh xin|xin thong tin|hoi|tuong|den|nen|ban tho|bat huong)\b/;
function laKetBan(ask) {
  const t = bo(ask).replace(/[^a-z0-9\s]+/g, ' ').replace(/\s+/g, ' ').trim();
  if (!KET_BAN.test(t)) return false;
  const conLai = t.replace(/ban nhan duoc loi moi ket ban|xin chao|minh la [a-z ]{1,40}?(?= ket| minh|$)|ket ban voi minh nhe|minh biet ban qua (so dien thoai|nhom chung|[a-z ]{1,20})/g, ' ');
  return !Y_MUA_KB.test(conLai);
}
module.exports = { laLoiKhan, laKetBan };

if (require.main === module && process.argv.includes('--do')) (async () => {
  // ĐO trên dữ liệu thật tháng 10: lọc trúng bao nhiêu dòng AI đã chấm khong_lien_quan (bắt được) và bao nhiêu dòng
  // đã chấm là khách thật (đúng / thiếu / sai / miss) — số sau PHẢI = 0 mới được dùng.
  const K = require('./keys.js'), H = { apikey: K.qc, Authorization: 'Bearer ' + K.qc };
  let ds = [], tu = 0;
  for (;;) {
    const r = await (await fetch(`${K.url}/rest/v1/sale_response_review?select=id,customer_ask,verdict,cham_boi,issue&conv_date=gte.2026-10-01&order=id&limit=1000&offset=${tu}`, { headers: H })).json();
    ds = ds.concat(r); if (r.length < 1000) break; tu += 1000;
  }
  const laKhan = r => /khấn|nam mô|a di đà|niệm|tri ân|phật/i.test(r.issue || '');
  // đo như job kéo: customer_ask gộp các lượt bằng " · " — hội thoại chỉ thành "không liên quan" khi MỌI lượt đều là lời khấn
  const trung = ds.filter(r => r.customer_ask && r.customer_ask.split(' · ').every(x => laLoiKhan(x) || /^\(gửi ảnh\/tệp\)$/.test(x.trim())) && r.customer_ask.split(' · ').some(x => laLoiKhan(x)));
  const ai = trung.filter(r => ['sonnet', 'claude'].includes(r.cham_boi));
  const bat = ai.filter(r => r.verdict === 'khong_lien_quan').length;
  const sai = ai.filter(r => r.verdict !== 'khong_lien_quan' && r.verdict !== 'chua_cham');
  const tong = ds.filter(r => r.cham_boi === 'sonnet' && r.verdict === 'khong_lien_quan' && laKhan(r)).length;
  console.log(`Dòng tháng 10: ${ds.length} · bộ mới nhận là lời khấn: ${trung.length}`);
  console.log(`AI đã chấm: bắt được ${bat} dòng khong_lien_quan (Sonnet chấm ra "khấn": ${tong}) · LỌC NHẦM khách thật: ${sai.length}`);
  sai.forEach(r => console.log(`  NHẦM #${r.id} [${r.verdict}] ${r.customer_ask.slice(0, 120)}`));
  const sot = ds.filter(r => r.cham_boi === 'sonnet' && r.verdict === 'khong_lien_quan' && laKhan(r) && !laLoiKhan(r.customer_ask));
  console.log(`Lời khấn Sonnet chấm mà bộ mới vẫn để lọt: ${sot.length} — vd:`);
  sot.slice(0, 20).forEach(r => console.log('  -', r.customer_ask.slice(0, 110)));
})();
