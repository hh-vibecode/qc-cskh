-- CHIA TỆP TIỀM NĂNG THÀNH 2 NHÓM (anh Hải chốt 23/11/2026, app MKT/Sale chuyển lời):
--   TIỀM NĂNG THỰC SỰ (nhom = 'tiem_nang') = khách VẪN ĐỂ MỞ (chưa kết thúc, chưa từ chối), không chê đắt;
--                                            HOẶC Sale quên / chưa khai thác hết (chua_khai_thac = true — luôn 'tiem_nang').
--   KHÁCH ĐẠT (nhom = 'dat')               = phần còn lại của tệp: khách từ chối mềm/cứng (chê đắt, so giá, Sale báo không có
--                                            đúng hàng, đã mua chỗ khác…). (Bản đầu 23/11 sáng tính cả khách dừng > 7 ngày là đạt — anh sửa
--                                            cùng ngày: "khách im vẫn ok, có nhu cầu là được" → khách dừng VẪN là tiềm năng, để Sale chăm lại.)
-- Trước 23/11 khách tu_choi rơi khỏi view; nay VẪN ở trong view, gắn nhom = 'dat'. Đã chốt / chưa đủ vẫn không vào view.
-- "Vẫn để mở" đo bằng tin cuối (bỏ Bot) trong thread — giờ trong thread là giờ VN:
--   khách nhắn cuối (đang chờ Sale) → mở, bất kể bao lâu (để lâu là lỗi Sale, không phải khách dừng);
--   Sale nhắn cuối → vẫn 'tiem_nang'; quá 7 ngày lịch thì chỉ đổi nhãn ly_do_nhom thành "Khách dừng: im N ngày sau tin Sale".
--   Khách từ chối hẳn: vẫn 'dat' (app MKT không hiện nhóm này).
-- Chỉ THÊM cột ở cuối (nhom, ly_do_nhom, tin_cuoi_luc, ngay_im; 23/11 chiều thêm loai_khach 'si' | 'le' — xem
-- supabase-schema-qc-tiem-nang-si-le.sql) — cột cũ giữ nguyên tên / thứ tự (X10, app MKT đọc).
-- Monsieur Claude
create or replace view public.qc_khach_tiem_nang_ngay with (security_invoker = true) as
with k as (
  select k.*
  from qc_khach_tiem_nang k
  where not exists (select 1 from qc_khach_tiem_nang k2
                    where k2.review_id = k.review_id
                      and (k2.ngay > k.ngay or k2.ngay = k.ngay and k2.danh_gia_luc > k.danh_gia_luc))
), x as (
  select k.ngay, k.ket, k.ly_do, k.danh_gia_luc, k.loai_khach k_loai_khach, s.*, c.review_id ckt_id, c.ly_do ckt_ly_do,
         tc.m[1]::timestamp tin_cuoi, tc.m[2] ai_cuoi,
         bg.bao_gia_n is not null and coalesce(bg.khach_n, 0) < bg.bao_gia_n im_sau_bao_gia,
         -- 23/11 trưa anh "qc khớp app": Sale nhắn cuối (sau đó khách im / chỉ đáp lễ) quá 7 ngày → khách dừng = ĐẠT (như app MKT)
         bg.sale_n is not null and coalesce(bg.khach_n, 0) < bg.sale_n
           and bg.sale_ts::timestamp < (now() at time zone 'Asia/Ho_Chi_Minh') - interval '7 days' khach_dung,
         (now() at time zone 'Asia/Ho_Chi_Minh')::date - bg.sale_ts::timestamp::date ngay_im_sale,
         coalesce(bg.khach_n, 0) > coalesce(bg.sale_n, 0) khach_cho
  from k
  join sale_response_review s on s.id = k.review_id
  left join lateral (
    select c_1.review_id, c_1.ly_do
    from qc_chua_khai_thac c_1
    where c_1.review_id = s.id and c_1.ket
      and not exists (select 1 from regexp_matches(right(s.full_thread, 3000), '\[(\d{4}-\d\d-\d\d \d\d:\d\d)\] (?!Bot:)', 'g') m(m)
                      where m.m[1]::timestamp > c_1.tin_cuoi_luc)
    order by c_1.tin_cuoi_luc desc limit 1) c on true
  left join lateral (select regexp_match(right(s.full_thread, 4000), '.*\[(\d{4}-\d\d-\d\d \d\d:\d\d)\] (Khách|Sale)', 's') m) tc on true
  -- 23/11 ~10h40 anh: "báo giá xong không nói gì không được tính là tiềm năng nữa, là ĐẠT thôi" → vị trí tin BÁO GIÁ CUỐI của Sale
  -- (cùng mẫu con số giá với qc_co_bao_gia) và tin KHÁCH CÓ NỘI DUNG cuối; "ok / dạ / cảm ơn / (sticker)" ngắn không tính là phản hồi.
  left join lateral (
    select max(t.n) filter (where t.l ~ '^\[[^]]+\] Sale[^:]*:[^\n]*(\d+([.,]\d+)?\s*(tr\M|triệu|k\M|nghìn|ngàn)|\d{1,3}([.,]\d{3}){1,2}\s*(đ|vnđ|vnd|\M))') bao_gia_n,
           max(t.n) filter (where t.l ~ '^\[[^]]+\] Khách: '
                              and not (length(t.l) <= 50 and t.l !~ '\?'
                                       and substr(t.l, 27) ~* '^\W*(dạ|vâng|ok|oke|okie|ừ|uk|vang|da|à|e|em|mình|cảm ơn|cám ơn|thank|thanks|tks|\(sticker\)|\s|,|\.|!|ạ|nhé|nha|shop|bạn|c|chị|anh)*\W*$')) khach_n,
           max(t.n) filter (where t.l ~ '^\[[^]]+\] Sale') sale_n,
           (array_agg(substr(t.l, 2, 16) order by t.n desc) filter (where t.l ~ '^\[[^]]+\] Sale'))[1] sale_ts
    from regexp_split_to_table(right(s.full_thread, 6000), '\n') with ordinality t(l, n)) bg on true
  where k.ket in ('tiem_nang', 'tu_choi') or (k.ket = 'chua_du' and c.review_id is not null)
), y as (
  select x.*,
         (now() at time zone 'Asia/Ho_Chi_Minh')::date - tin_cuoi::date ngay_im,
         case
           -- 23/11 (anh, ca Trần Vân Tuấn Tuấn #20987 — khách chặn page, báo sai #94/#96 đã chấm loi_nen_tang): lỗi nền tảng
           -- (không gửi được tin cho khách) KHÔNG tiềm năng, không "chờ Sale" — view tôn trọng kết quả chấm / báo sai
           when verdict = 'loi_nen_tang' then 'dat'
           when ckt_id is not null then 'tiem_nang'
           when ket = 'tu_choi' then 'dat'
           when im_sau_bao_gia then 'dat'      -- 23/11 ~10h40: báo giá (cuối) xong khách không nói gì → đạt
           when khach_dung then 'dat'          -- 23/11 trưa: khớp app MKT — Sale nhắn cuối quá 7 ngày, khách im / chỉ đáp lễ
           else 'tiem_nang'
         end nhom
  from x
)
select y.ngay,
       y.ket,
       y.ly_do,
       y.danh_gia_luc,
       case when y.page_id like 'pzl\_%' then 'zalo' when y.page_id like 'ttm\_%' then 'tiktok' else 'facebook' end nen_tang,
       y.page_name kenh,
       y.page_id,
       y.conv_id pancake_conversation_id,
       coalesce(y.khach_id, nullif(regexp_replace(y.conv_id, '^pzl_u_\d+_', ''), y.conv_id)) khach_id,
       y.customer_name ten_khach,
       y.phone sdt,
       t.ten_nhan_su sale,
       y.sale_name sale_qc,
       y.pancake_url,
       y.ckt_id is not null chua_khai_thac,
       y.ckt_ly_do ly_do_chua_khai_thac,
       y.nhom,
       case
         when y.verdict = 'loi_nen_tang' then 'Lỗi nền tảng: không gửi được tin cho khách'
         when y.ckt_id is not null then 'Chưa khai thác hết (lỗi Sale)'
         when y.ket = 'tu_choi' and y.ly_do ~* 'đã mua|không mua|thôi không|cũng không có tiền' then 'Khách từ chối hẳn'
         when y.ket = 'tu_choi' and y.ly_do ~* 'đắt|cao quá|cao vậy|giá cao|so (chỗ|giá)|rẻ hơn|đủ tiền|đủ kinh tế' then 'Chê giá / chưa đủ tiền'
         when y.ket = 'tu_choi' and y.ly_do ~* 'không có|chỉ có|chỉ còn|khác mẫu|chưa ưng|không ưng' then 'Không có đúng hàng / chưa ưng mẫu'
         when y.ket = 'tu_choi' then 'Khách từ chối'
         when y.im_sau_bao_gia then 'Báo giá xong khách chưa phản hồi'
         when y.khach_dung then 'Khách dừng: im ' || y.ngay_im_sale || ' ngày sau tin Sale'
         when y.khach_cho then 'Đang mở: khách hỏi, chờ Sale'   -- 23/11: tin khách CÓ NỘI DUNG sau tin Sale cuối (đáp lễ không tính)
         else 'Đang mở: Sale đã đáp, chờ khách'
       end ly_do_nhom,
       y.tin_cuoi tin_cuoi_luc,
       y.ngay_im,
       coalesce(y.k_loai_khach, case when not qc_page_si(y.page_name) then 'le' end) loai_khach
from y
left join qc_sale_ten t on t.ten_pancake = y.sale_name
where (y.verdict <> 'khong_lien_quan' or y.verdict is null)
  and not coalesce(y.noi_bo, false);   -- 23/11: app MKT tự tạo đơn Pancake theo view → chặn cả hội thoại bị đánh dấu nội bộ sau này

-- ĐƯỜNG LÙI (bản trước 23/11 — chỉ tiem_nang + chua_du có chưa khai thác hết, 16 cột). Muốn trả bản cũ phải DROP VIEW rồi tạo lại
-- vì bản cũ ít cột hơn:
-- select k.ngay, k.ket, k.ly_do, k.danh_gia_luc, <nen_tang>, s.page_name kenh, s.page_id, s.conv_id pancake_conversation_id,
--   <khach_id>, s.customer_name ten_khach, s.phone sdt, t.ten_nhan_su sale, s.sale_name sale_qc, s.pancake_url,
--   c.review_id is not null chua_khai_thac, c.ly_do ly_do_chua_khai_thac
-- from qc_khach_tiem_nang k join sale_response_review s on s.id = k.review_id left join qc_sale_ten t on t.ten_pancake = s.sale_name
--   left join lateral (<chưa khai thác hết như trên>) c on true
-- where (k.ket = 'tiem_nang' or k.ket = 'chua_du' and c.review_id is not null) and <lần đánh giá mới nhất>;
