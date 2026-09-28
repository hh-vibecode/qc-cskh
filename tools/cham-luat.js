// CHẤM BẰNG LUẬT — tầng 1, không tốn token. Chỉ chốt các ca HIỂN NHIÊN; ca nào còn chút nghi ngờ
// trả về null để tầng 2 (agent Sonnet `cham-qc`) đọc hiểu. Nguyên tắc: chấm oan tệ hơn chưa chấm.
//
// Dùng:
//   .../Code.exe tools/cham-luat.js --do          đo trên các dòng ĐÃ chấm: luật chốt được bao nhiêu, lệch bao nhiêu
//   .../Code.exe tools/cham-luat.js --ghi --thu   xem trước sẽ chốt những dòng chua_cham nào
//   .../Code.exe tools/cham-luat.js --ghi         ghi thật (chỉ vào dòng chua_cham), cham_boi='luat'
// Monsieur Claude
const K = require('./keys.js');

const bo = s => (s || '').normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/đ/g, 'd').replace(/Đ/g, 'd').toLowerCase()
  .replace(/\s+/g, ' ').trim();

// Tin hệ thống / tự động bị job lưu nhầm vào ô "Sale trả lời"
// (KHÔNG gồm "đã trả lời tin nhắn chào mừng tự động": sau câu đó thường còn câu trả lời thật của Sale — đo 28/9 sai 3/4)
const HE_THONG = /^[^|]{0,60}replied to a (post|comment)[^|]*$/;
// Câu hỏi phân loại của page Sỉ
const PHAN_LOAI = /gia dinh hay nhap si|nhu cau cho gia dinh hay/;
// Khách đã tự nói mình là ai → hỏi phân loại lại là bỏ qua thông tin khách (để tầng 2)
const KHACH_DA_NOI = /gia dinh|tai gia|thinh ve|an vi|nhap si|nhap hang|dai ly|lay si|buon|ban le|cua hang/;
// Sale hỏi lại thông tin / xin ảnh mẫu / chuyển kênh — hợp lệ khi khách hỏi CHUNG CHUNG
const HOI_LAI = /xin (lai )?(anh|hinh|mau)|gui (em|giup em|cho em) (xin )?(anh|hinh|mau)|mau nao|san pham nao|loai nao|ngan sach|kinh phi|tai chinh|kiem tra tin nhan|inbox|nhan tin|zalo|so dien thoai|sdt|hotline|de lai so/;
// Dấu hiệu khách hỏi CỤ THỂ → không được coi là câu hỏi chung
const CU_THE = /\d|(duoc|dc) (ko|khong|k)\b|co (the|duoc)|mua le|co so|quan am|thich ca|a di da|dia tang|than tai|tho dia|di lac|tam the|tam thanh|ho phap|sơn than|son than|mau (nay|kia|do)|bo (nay|kia|do)|cai (nay|kia|do)|loai (nay|kia|do)|con (hang|khong|ko)|ship|giao|dia chi|o dau|bao lau|bao hanh|doi tra|chat lieu|dong|go|su|kich thuoc|cao|rong|size|lap|den|nen|dau|lu huong|ban tho|khieu nai|hong|vo|loi|tra lai|hoan/;
// Câu hỏi thông tin cụ thể mà câu phân loại Sỉ KHÔNG trả lời được (giá thì được: giá phụ thuộc sỉ/lẻ)
const HOI_THONG_TIN = /cao|kich thuoc|size|dia chi|co so|o dau|chat lieu|bao hanh|con hang|ship|giao|(duoc|dc) (ko|khong|k)\b|mua le/;
// Mẫu trả lời chuẩn (đầu câu, đã bỏ dấu) — chỉ thêm mẫu khi đo trên dữ liệu đã chấm ra 100% đúng
const MAU_CHUAN = [
  'da em gui anh/chi bang gia cac san pham ban chay',
  'da tuong quan am van co da sac',
  'da tuong quan tam la tuong bot da thach anh',
  'da tuong quan am anh quan tam la tuong bot da',
  'da tuong quan am chi quan tam la tuong bot da',
];
// LỜI KHẤN / TỤNG NIỆM dưới bài đăng (anh Hải 28/9: "tin này miss gì, cái này bỏ qua được") → khong_lien_quan.
// Bản 1 (đo 28/9) sai 5/9 vì bắt cả "Mô Phật cho e hỏi…" → bản 2 chỉ nhận khi KHÔNG có bất kỳ dấu hiệu hỏi / mua nào.
// Bản 2 đo lại: "binh an", "quan the am bo tat" là TÊN SẢN PHẨM (nến bơ bình an, tượng Quan Thế Âm) → bỏ; khớp theo nguyên từ.
const KHAN = /\b(nam mo|a di da phat|adida phat|mo phat|thuong niem|cui dau|con lay|lay me|lay phat|nguyen cau|cau xin|cau cho|phu ho|do tri)\b/;
const CO_Y_HOI = /\?|\d|\b(dat|lay cho|k|ko|khong|gia|bao nhieu|bn|mua|thinh ve|thinh tuong|size|sz|kich thuoc|cao|ship|dat hang|tu van|inbox|ib|con hang|co khong|co ko|hoi|xem|mau|bo nay|cai nay|dia chi|so dien thoai|sdt|zalo)\b|cho (e|em|minh|toi|chi|anh|co|chu|bac) (hoi|xin|xem)|xin (gia|mau|anh|hinh|thong tin|dia chi|so)/;

// NHÂN VIÊN NỘI BỘ đứng ở vị trí "khách" (chat nội bộ, gửi báo cáo) → không phải khách, không tính.
// Anh Hải báo 28/9/2026: Đức Tuấn + Đinh Ngọc Diệp (Chánh Tâm), cùng SĐT 0973763458. Có thêm người thì bổ sung vào đây.
const NOI_BO_SDT = ['0973763458'];
const NOI_BO_TEN = ['duc tuan', 'dinh ngoc diep'];
const laNoiBo = r => {
  const sdt = (r.phone || '').replace(/\D/g, '').replace(/^84/, '0');
  return (sdt && NOI_BO_SDT.includes(sdt)) || NOI_BO_TEN.includes(bo(r.customer_name));
};

function chamLuat(r) {
  if (laNoiBo(r)) return { verdict: 'khong_lien_quan', luat: 'noi_bo' };
  const ask = bo(r.customer_ask), rep = bo(r.sale_reply), page = bo(r.page_name);
  if (!ask) return null;
  if (KHAN.test(ask) && !CO_Y_HOI.test(ask)) return { verdict: 'khong_lien_quan', luat: 'loi_khan' };
  if (!rep) return null;                                        // không có trả lời: đã do job xử lý (chi_bot/khong_tra_loi)
  // 1) "Câu trả lời" chỉ là tin hệ thống
  if (HE_THONG.test(rep)) return { verdict: 'chi_bot', luat: 'tin_he_thong' };
  // 2) Page Sỉ hỏi phân loại, khách chưa tự nói mình là ai, và không hỏi thông tin cụ thể ngoài giá
  if (PHAN_LOAI.test(rep) && !KHACH_DA_NOI.test(ask) && !HOI_THONG_TIN.test(ask) && /si|thoi dai|shidai|tong kho/.test(page))
    return { verdict: 'dung', luat: 'phan_loai_si' };
  // 3) Khách hỏi chung chung (ngắn, không số, không tên SP) → Sale hỏi lại / xin ảnh / chuyển kênh là đúng
  if (ask.length <= 60 && !CU_THE.test(ask) && HOI_LAI.test(rep)) return { verdict: 'dung', luat: 'hoi_chung_hoi_lai' };
  // 4) Bình luận → Sale mời khách check inbox (luật đã chốt: chuyển inbox là đúng). Đo 28/9: 41/41 đúng.
  if (/check (ib|inbox)|kiem tra (tin nhan|inbox)/.test(rep) && rep.length <= 90) return { verdict: 'dung', luat: 'moi_check_ib' };
  // 5) Mẫu trả lời chuẩn theo quảng cáo / bảng giá, khách hỏi không có số cụ thể. Đo 28/9 trên dữ liệu đã chấm.
  if (!/\d/.test(ask) && ask.length <= 80 && MAU_CHUAN.some(m => rep.startsWith(m)) && !HOI_THONG_TIN.test(ask))
    return { verdict: 'dung', luat: 'mau_chuan' };
  return null;                                                   // còn lại → Sonnet
}
module.exports = { chamLuat };

async function sql(q) {
  const r = await fetch(`https://api.supabase.com/v1/projects/${K.ref}/database/query`, {
    method: 'POST', headers: { Authorization: 'Bearer ' + K.sbp, 'Content-Type': 'application/json' }, body: JSON.stringify({ query: q }) });
  const j = await r.json().catch(() => null);
  if (!r.ok) throw new Error(r.status + ' ' + JSON.stringify(j));
  return j;
}

if (require.main === module) (async () => {
  const a = process.argv;
  if (a.includes('--do')) {
    const rows = await sql(`select id, conv_date, page_name, customer_name, phone, customer_ask, sale_reply, verdict from sale_response_review
      where conv_id not like 'pzl\\_g\\_%' and verdict in ('dung','thieu','sai','khong_lien_quan','chi_bot')
        and sale_reply is not null`);
    const kq = {}; let chot = 0; const lech = [];
    for (const r of rows) {
      const x = chamLuat(r); if (!x) continue; chot++;
      const k = x.luat; kq[k] = kq[k] || { chot: 0, khop: 0 }; kq[k].chot++;
      if (x.verdict === r.verdict) kq[k].khop++; else lech.push({ id: r.id, ngay: r.conv_date, luat: k, luat_cham: x.verdict, that: r.verdict, ask: (r.customer_ask || '').slice(0, 90), rep: (r.sale_reply || '').slice(0, 90) });
    }
    console.log(`Dòng đã chấm có câu trả lời: ${rows.length} · luật chốt được: ${chot} (${(chot / rows.length * 100).toFixed(1)}%) · lệch: ${lech.length}`);
    console.table(Object.entries(kq).map(([luat, v]) => ({ luat, chot: v.chot, khop: v.khop, lech: v.chot - v.khop })));
    if (lech.length) { console.log('CÁC DÒNG LỆCH:'); lech.forEach(l => console.log(JSON.stringify(l))); }
    return;
  }
  if (a.includes('--ghi')) {
    // chua_cham: áp mọi luật. khong_tra_loi/chi_bot do job tự gắn: chỉ áp luật nội bộ (nhân viên không phải khách → không phải miss)
    const rows = await sql(`select id, page_name, customer_name, phone, customer_ask, sale_reply, verdict from sale_response_review
      where verdict in ('chua_cham','khong_tra_loi','chi_bot') and conv_id not like 'pzl\\_g\\_%'`);
    const ra = rows.map(r => ({ id: r.id, cu: r.verdict, ...chamLuat(r) }))
      .filter(x => x.verdict && (x.cu === 'chua_cham' || x.luat === 'noi_bo' || x.luat === 'loi_khan'));
    const dem = {}; ra.forEach(x => dem[x.luat] = (dem[x.luat] || 0) + 1);
    const cho = rows.filter(r => r.verdict === 'chua_cham').length;
    console.log(`chua_cham: ${cho} · luật chốt: ${ra.length} · còn cho Sonnet: ${cho - ra.filter(x => x.cu === 'chua_cham').length}`, dem);
    ra.filter(x => x.cu !== 'chua_cham').forEach(x => console.log(`  ${x.luat} #${x.id}: ${x.cu} → ${x.verdict}`));
    if (a.includes('--thu') || !ra.length) return;
    const data = JSON.stringify(ra.map(x => ({ id: x.id, verdict: x.verdict })));
    const done = await sql(`with v as (select * from jsonb_to_recordset($q$${data}$q$::jsonb) as x(id bigint, verdict text))
      update sale_response_review s set verdict=v.verdict, severity=null, issue=null, suggestion=null, source_faq=null,
        cham_boi='luat', reviewed_at=now()
      from v where s.id=v.id and s.verdict in ('chua_cham','khong_tra_loi','chi_bot') returning s.id`);
    console.log(`Đã ghi ${done.length} dòng (cham_boi='luat').`);
    return;
  }
  console.log('Dùng: --do | --ghi [--thu]');
})().catch(e => { console.error('LỖI', e.message); process.exit(1); });
